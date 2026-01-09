// ##################################################################################################
// # << CELLRV32 - Vector Store Unit >>                                                             #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vmu_st_eng #(
    parameter int REQ_DATA_WIDTH     = 256,
    parameter int VECTOR_REGISTERS   = 32 ,
    parameter int VECTOR_LANES       = 8  ,
    parameter int DATA_WIDTH         = 32 ,
    parameter int ADDR_WIDTH         = 32 ,
    parameter int MICROOP_WIDTH      = 5  
) (
    //=======================================================
    // Clock / Reset
    //=======================================================
    input  logic                                clk           , // Main clock
    input  logic                                rst_n         , // Active–low synchronous reset
    //=======================================================
    // Input Interface
    //=======================================================
    input  logic                                valid_in      , // Instruction valid input (handshake)
    input  memory_remapped_v_instr              instr_in      , // Remapped vector memory instruction bundle
    output logic                                ready_o       , // Store engine ready to accept new instruction
    //=======================================================
    // RF Interface (per vreg)
    //=======================================================
    output logic [$clog2(VECTOR_REGISTERS)-1:0] rd_addr_1_o   , // Read address for source vector register (SRC1)
    input  logic [ VECTOR_LANES*DATA_WIDTH-1:0] rd_data_1_i   , // Lane-packed SRC1 data read from RF
    //=======================================================
    // RF Interface (for `OP_INDEXED stride)
    //=======================================================
    output logic [$clog2(VECTOR_REGISTERS)-1:0] rd_addr_2_o   , // Read address for source vector register (SRC2)
    input  logic [ VECTOR_LANES*DATA_WIDTH-1:0] rd_data_2_i   , // Lane-packed SRC2 data read from RF
    //=======================================================
    // Unlock Interface
    //=======================================================
    output logic                                unlock_en_o   , // Indicates SRC registers are ready to be unlocked
    output logic [$clog2(VECTOR_REGISTERS)-1:0] unlock_reg_a_o, // SRC1 register number to unlock
    //=======================================================
    // Request Interface
    //=======================================================
    input  logic                                grant_i       , // Memory system grants request (handshake)
    output logic                                req_en_o      , // Request enable for memory transaction
    output logic [              ADDR_WIDTH-1:0] req_addr_o    , // Generated memory address
    output logic [  $clog2(REQ_DATA_WIDTH/8):0] req_size_o    , // Transfer size in bytes (depends on element width)
    output logic [          REQ_DATA_WIDTH-1:0] req_data_o    , // Data payload (1 element or multiple elements packed)
    //=======================================================
    // Sync Interface
    //=======================================================
    output logic                                is_busy_o     , // Indicates store engine is executing an instruction
    output logic [              ADDR_WIDTH-1:0] start_addr_o  , // First address touched by this instruction
    output logic [              ADDR_WIDTH-1:0] end_addr_o      // Last address touched (if calculable; INDEXED may not)
);

    localparam int ELEMENT_ADDR_WIDTH   = $clog2(VECTOR_LANES)                                                       ;
    localparam int VREG_ADDR_WIDTH      = $clog2(VECTOR_REGISTERS)                                                   ;
    localparam int MAX_MEM_SERVED_LIMIT = REQ_DATA_WIDTH / DATA_WIDTH                                                ;
    localparam int MAX_RF_SERVED_COUNT  = VECTOR_REGISTERS                                                           ;
    localparam int MAX_SERVED_COUNT     = (VECTOR_LANES > MAX_MEM_SERVED_LIMIT) ? MAX_MEM_SERVED_LIMIT : VECTOR_LANES;

    //=======================================================
    // INTERNAL SIGNALS
    //=======================================================
    logic                                           current_finished            ;
    logic                                           currently_idle              ;
    logic                                           expansion_finished          ;
    logic                                           maxvl_reached               ;
    logic                                           vl_reached                  ;
    logic                                           start_new_instruction       ;
    logic                                           start_new_loop              ;
    logic                                           new_transaction_en          ;
    logic                                           request_ready               ;
    logic                                           multi_valid                 ;
    logic [    $clog2(VECTOR_LANES*DATA_WIDTH)-1:0] element_index               ;
    logic [                         ADDR_WIDTH-1:0] offset_read                 ;
    logic [                         ADDR_WIDTH-1:0] current_addr                ;
    logic [                         ADDR_WIDTH-1:0] nxt_base_addr               ;
    logic [                         ADDR_WIDTH-1:0] nxt_strided_addr            ;
    logic [                         ADDR_WIDTH-1:0] nxt_unit_strided_addr       ;
    logic [                         ADDR_WIDTH-1:0] current_addr_r              ;
    logic [                         ADDR_WIDTH-1:0] base_addr_r                 ;
    logic [                         ADDR_WIDTH-1:0] nxt_stride                  ;
    logic [                         ADDR_WIDTH-1:0] stride_r                    ;
    logic [                     REQ_DATA_WIDTH-1:0] data_selected_v             ;
    logic [                         DATA_WIDTH-1:0] data_selected_el            ;
    logic [                     REQ_DATA_WIDTH-1:0] data_selected               ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0] nxt_total_remaining_elements;
    logic [                 ELEMENT_ADDR_WIDTH-1:0] nxt_elem                    ;
    logic [                   ELEMENT_ADDR_WIDTH:0] current_pointer_wb_r        ;
    logic [                         VECTOR_LANES:0] current_pointer_oh          ;
    logic [                         VECTOR_LANES:0] current_served_th           ;
    logic [                       VECTOR_LANES-1:0] nxt_pending_elem            ;
    logic [                       VECTOR_LANES-1:0] nxt_pending_elem_loop       ;
    logic [                       VECTOR_LANES-1:0] pending_elem                ;
    logic [                    VREG_ADDR_WIDTH-1:0] current_exp_loop_r          ;
    logic [                    VREG_ADDR_WIDTH-1:0] src1_r                      ;
    logic [                    VREG_ADDR_WIDTH-1:0] src2_r                      ;
    logic [                    VREG_ADDR_WIDTH-1:0] max_expansion_r             ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0] instr_vl_r                  ;
    logic [                      MICROOP_WIDTH-1:0] microop_r                   ;
    logic [                                    1:0] memory_op_r                 ;
    logic [                                    1:0] nxt_memory_op               ;
    logic [                         ADDR_WIDTH-1:0] start_addr_r                ;
    logic [                         ADDR_WIDTH-1:0] end_addr_r                  ;
    // Create basic control flow
    //=======================================================
    assign ready_o             = currently_idle | current_finished;
    assign is_busy_o           = ~currently_idle; 

    //current instruction finished
    assign current_finished = expansion_finished & new_transaction_en & ~pending_elem[nxt_elem];
    //currently no instructions are being served
    assign currently_idle = current_pointer_oh[0] & ~|pending_elem;

    assign expansion_finished = maxvl_reached | vl_reached;
    assign maxvl_reached      = (current_exp_loop_r === (max_expansion_r-1));
    assign vl_reached         = (((current_exp_loop_r+1) << $clog2(VECTOR_LANES)) >= instr_vl_r);

    assign start_new_instruction = valid_in & ready_o & ~instr_in.reconfigure;

    // Start from element 0 on the next destination vreg
    assign start_new_loop = ~expansion_finished & ~pending_elem[current_pointer_wb_r] & ~pending_elem[nxt_elem];

    // Create the memory request control signals
    assign req_en_o      = request_ready;
    assign req_addr_o    = current_addr;
    assign req_data_o    = data_selected;
    assign req_size_o    = 4;

    assign new_transaction_en = request_ready & grant_i;
    assign request_ready      = pending_elem[current_pointer_wb_r];
    // Unlock register signals
    assign unlock_en_o     = start_new_loop | current_finished;
    assign unlock_reg_a_o  = src1_r;

    // assign the rest of the outputs
    assign rd_addr_1_o  = src1_r;
    assign rd_addr_2_o  = src2_r;
    assign start_addr_o = start_addr_r;
    assign end_addr_o   = end_addr_r;
    //=======================================================
    // Address Generation
    //=======================================================
    assign multi_valid   = 1'b0;
    assign element_index = current_pointer_wb_r << 5; //*32
    assign offset_read   = rd_data_2_i[element_index +: DATA_WIDTH];
    // Generate next non-multi consecutive address
    always_comb begin
        case (memory_op_r)
             OP_UNIT_STRIDED : current_addr = current_addr_r;
             OP_STRIDED      : current_addr = current_addr_r;
             OP_INDEXED      : current_addr = base_addr_r + offset_read;
            default          : current_addr = 'X;
        endcase
    end

    assign nxt_base_addr    = instr_in.data1 + instr_in.data2;
    assign nxt_strided_addr = current_addr_r + stride_r;
    assign nxt_unit_strided_addr = current_addr_r + (1 << 2);

    // Hold current address
    always_ff @(posedge clk) begin
        if(start_new_instruction) begin
            current_addr_r <= nxt_base_addr;
        end else if (new_transaction_en && memory_op_r == OP_STRIDED) begin
            current_addr_r <= nxt_strided_addr;
        end else if(new_transaction_en && memory_op_r == OP_UNIT_STRIDED) begin
            current_addr_r <= nxt_unit_strided_addr;
        end
    end
    // Hold base address
    always_ff @(posedge clk) begin
        if(start_new_instruction) begin
            base_addr_r <= nxt_base_addr;
        end
    end
    // Hold stride
    assign nxt_stride = instr_in.data2;
    always_ff @(posedge clk) begin
        if(start_new_instruction) stride_r <= nxt_stride;
    end

    //=======================================================
    // Data Generation
    //=======================================================
    // single-element data to be stored
    assign data_selected_el = rd_data_1_i[element_index +: DATA_WIDTH];
    // vector of data to be stored
    assign data_selected_v = rd_data_1_i >> ({5'b00000, current_pointer_wb_r} << 5); //bring the data to bit0

    // create the final data vector
    always_comb begin
        data_selected = '0;
        if(!multi_valid) begin
            data_selected[0 +:32] = data_selected_el;
        end else begin
            for (int i = 0; i < MAX_SERVED_COUNT; i++) begin
                data_selected[i*32 +: 32] = data_selected_v[i*32 +: 32]; // pick 32bits from each elem
            end
        end
    end

    //=======================================================
    // Scoreboard maintenance
    //=======================================================
    assign nxt_total_remaining_elements = instr_vl_r - ((current_exp_loop_r+1)*VECTOR_LANES);

    // Maintain current pointer
    assign nxt_elem = current_pointer_wb_r + 1;
    always_ff @(posedge clk or negedge rst_n) begin : current_ptr
        if(!rst_n) begin
            current_pointer_wb_r <= 0;
        end else begin
            if(start_new_instruction) begin
                current_pointer_wb_r <= 0;
            end else if (start_new_loop) begin
                current_pointer_wb_r <= 0;
            end else if (current_finished) begin
                current_pointer_wb_r <= 0;
            end else if(new_transaction_en) begin
                current_pointer_wb_r <= nxt_elem;
            end
        end
    end

    // Create new pending states
    always_comb begin : get_new_elem_pending
        // next pending state for new instruction
        if(instr_in.vl < VECTOR_LANES) begin
            nxt_pending_elem = ~('1 << instr_in.vl);
        end else begin
            nxt_pending_elem = '1;
        end
        // next pending state for new loop
        if(nxt_total_remaining_elements < VECTOR_LANES) begin
            nxt_pending_elem_loop = ~('1 << nxt_total_remaining_elements);
        end else begin
            nxt_pending_elem_loop = '1;
        end
    end

    // Store new pending states
    assign current_served_th  = (~('1 << 1)) << current_pointer_wb_r;
    assign current_pointer_oh = 1 << current_pointer_wb_r;
    always_ff @(posedge clk or negedge rst_n) begin : pending_status
        if(!rst_n) begin
            pending_elem <= '0;
        end else begin
            for (int i = 0; i < VECTOR_LANES; i++) begin
                if(start_new_instruction) begin
                    pending_elem[i] <= nxt_pending_elem[i];
                end else if (start_new_loop) begin
                    pending_elem[i] <= nxt_pending_elem_loop[i];
                end else if(new_transaction_en && current_served_th[i] && multi_valid) begin // multi-request
                    pending_elem[i] <= 1'b0;
                end else if(new_transaction_en && current_pointer_oh[i] && !multi_valid) begin // single-request
                    pending_elem[i] <= 1'b0;
                end
            end
        end
    end

    // Keep track of the expanions happening
    always_ff @(posedge clk or negedge rst_n) begin : loop_tracking
        if(!rst_n) begin
            current_exp_loop_r <= 0;
        end else begin
            if(start_new_instruction) begin
                current_exp_loop_r <= 0;
                src1_r             <= instr_in.dst;
                src2_r             <= instr_in.src2;
            end else if(start_new_loop) begin
                current_exp_loop_r <= current_exp_loop_r + 1;
                src1_r             <= src1_r + 1;
                src2_r             <= src2_r + 1;
            end
        end
    end

    // Store the max expansion when reconfiguring
    always_ff @(posedge clk or negedge rst_n) begin : maxExp
        if(!rst_n) begin
            max_expansion_r <= 'd1;
        end else begin
            max_expansion_r <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end
    end

    //=======================================================
    // Capture Instruction Information
    //=======================================================
    always_ff @(posedge clk or negedge rst_n) begin : proc_vl_r
        if(!rst_n) begin
            instr_vl_r <= VECTOR_LANES;
        end else begin
            if(start_new_instruction) begin
                instr_vl_r <= instr_in.vl;
            end
        end
    end
    always_ff @(posedge clk) begin
        if(start_new_instruction) begin
            microop_r <= instr_in.microop;
        end
    end

    assign nxt_memory_op = instr_in.ir_funct12[MEM_OP_RANGE_HI:MEM_OP_RANGE_LO];
    always_ff @(posedge clk or negedge rst_n) begin : proc_memory_op_r
        if(!rst_n) begin
            memory_op_r <= '0;
        end else begin
            if(start_new_instruction) begin
                memory_op_r <= nxt_memory_op;
            end
        end
    end

    // calculate start-end addresses for the op
    // +- 4 to avoid conflicts due to data sizes
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            start_addr_r <= '0;
            end_addr_r   <= '1;
        end else begin
            if(start_new_instruction) begin
                start_addr_r <= nxt_base_addr;
                if(instr_in.microop[MEM_OP_RANGE_HI:MEM_OP_RANGE_LO] !== OP_INDEXED) begin
                    end_addr_r <= nxt_base_addr + ((instr_in.vl -1) * nxt_stride);
                end else begin
                    end_addr_r <= nxt_base_addr; // cannot calculate end address for `OP_INDEXED ops
                end
            end
        end
    end

endmodule