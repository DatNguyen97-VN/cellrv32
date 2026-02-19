// ##################################################################################################
// # << CELLRV32 - Vector Store Unit >>                                                             #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vmu_st_eng #(
    parameter int REQ_DATA_WIDTH     = 32,
    parameter int VECTOR_REGISTERS   = 32,
    parameter int VECTOR_LANES       = 8 ,
    parameter int DATA_WIDTH         = 32,
    parameter int ADDR_WIDTH         = 32,
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
    output logic [          REQ_DATA_WIDTH-1:0] req_data_o    , // Data payload (1 element or multiple elements packed)
    //=======================================================
    // Sync Interface
    //=======================================================
    output logic                                is_busy_o       // Indicates store engine is executing an instruction
);

    localparam int ELEMENT_ADDR_WIDTH   = $clog2(VECTOR_LANES)    ;
    localparam int VREG_ADDR_WIDTH      = $clog2(VECTOR_REGISTERS);

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
    logic [    $clog2(VECTOR_LANES*DATA_WIDTH)-1:0] element_index               ;
    logic [                         ADDR_WIDTH-1:0] current_addr                ;
    logic [                         ADDR_WIDTH-1:0] nxt_base_addr               ;
    logic [                         ADDR_WIDTH-1:0] nxt_strided_addr            ;
    logic [                         ADDR_WIDTH-1:0] nxt_unit_strided_addr       ;
    logic [                         ADDR_WIDTH-1:0] current_addr_r              ;
    logic [                         ADDR_WIDTH-1:0] nxt_stride                  ;
    logic [                         ADDR_WIDTH-1:0] stride_r                    ;
    logic [                         DATA_WIDTH-1:0] data_selected_el            ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0] nxt_total_remaining_elements;
    logic [                 ELEMENT_ADDR_WIDTH-1:0] nxt_elem                    ;
    logic [                   ELEMENT_ADDR_WIDTH:0] current_pointer_wb_r        ;
    logic [                         VECTOR_LANES:0] current_pointer_oh          ;
    logic [                       VECTOR_LANES-1:0] nxt_pending_elem            ;
    logic [                       VECTOR_LANES-1:0] nxt_pending_elem_loop       ;
    logic [                       VECTOR_LANES-1:0] pending_elem                ;
    logic [                    VREG_ADDR_WIDTH-1:0] current_exp_loop_r          ;
    logic [                    VREG_ADDR_WIDTH-1:0] src1_r                      ;
    logic [                    VREG_ADDR_WIDTH-1:0] max_expansion_r             ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0] instr_vl_r                  ;
    logic [                                    1:0] memory_op_r                 ;
    logic [                                    1:0] nxt_memory_op               ;
    // Create basic control flow
    //=======================================================
    assign ready_o   = currently_idle | current_finished;
    assign is_busy_o = ~currently_idle; 

    //current instruction finished
    assign current_finished = expansion_finished & new_transaction_en & ~pending_elem[nxt_elem];
    //currently no instructions are being served
    assign currently_idle = current_pointer_oh[0] & ~|pending_elem;

    assign expansion_finished = maxvl_reached | vl_reached;
    assign maxvl_reached      = (current_exp_loop_r == (max_expansion_r-1));
    assign vl_reached         = (((current_exp_loop_r+1) << $clog2(VECTOR_LANES)) >= instr_vl_r);

    assign start_new_instruction = valid_in & ready_o & ~instr_in.reconfigure;

    // Start from element 0 on the next destination vreg
    assign start_new_loop = ~expansion_finished & ~pending_elem[current_pointer_wb_r] & ~pending_elem[nxt_elem];

    // Create the memory request control signals
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_en_o <= 1'b0;
        end else begin
            req_en_o <= request_ready;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            req_addr_o <= '0;
        end else begin
            req_addr_o <= current_addr;
        end
    end

    assign req_data_o = data_selected_el;

    assign new_transaction_en = request_ready & grant_i;
    assign request_ready      = pending_elem[current_pointer_wb_r];
    // Unlock register signals
    assign unlock_en_o    = start_new_loop | current_finished;
    assign unlock_reg_a_o = src1_r;

    // assign the rest of the outputs
    assign rd_addr_1_o = src1_r;
    //=======================================================
    // Address Generation
    //=======================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            element_index <= '0;
        end else begin
            element_index <= current_pointer_wb_r << 5; // pointer * 32
        end
    end
    // Generate next non-multi consecutive address
    always_comb begin
        case (memory_op_r)
             OP_UNIT_STRIDED : current_addr = current_addr_r;
             OP_STRIDED      : current_addr = current_addr_r;
            default          : current_addr = '0;
        endcase
    end

    assign nxt_base_addr    = instr_in.data1;
    assign nxt_strided_addr = current_addr_r + stride_r;
    assign nxt_unit_strided_addr = current_addr_r + 4;

    // Hold current address
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_addr_r <= '0;
        end else if (start_new_instruction) begin
            current_addr_r <= nxt_base_addr;
        end else if (new_transaction_en && memory_op_r == OP_STRIDED) begin
            current_addr_r <= nxt_strided_addr;
        end else if(new_transaction_en && memory_op_r == OP_UNIT_STRIDED) begin
            current_addr_r <= nxt_unit_strided_addr;
        end
    end
    // Hold stride
    assign nxt_stride = instr_in.data2;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stride_r <= '0;
        end else if (start_new_instruction) begin
            stride_r <= nxt_stride;
        end
    end

    //=======================================================
    // Data Generation
    //=======================================================
    assign data_selected_el = rd_data_1_i[element_index +: DATA_WIDTH];

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
            if (start_new_instruction || start_new_loop || current_finished) begin
                current_pointer_wb_r <= 0;
            end else if (new_transaction_en) begin
                current_pointer_wb_r <= nxt_elem;
            end
        end
    end

    // Create new pending states
    always_comb begin : get_new_elem_pending
        // next pending state for new instruction
        if (instr_in.vl < VECTOR_LANES) begin
            nxt_pending_elem = ~('1 << instr_in.vl);
        end else begin
            nxt_pending_elem = '1;
        end
        // next pending state for new loop
        if (nxt_total_remaining_elements < VECTOR_LANES) begin
            nxt_pending_elem_loop = ~('1 << nxt_total_remaining_elements);
        end else begin
            nxt_pending_elem_loop = '1;
        end
    end

    // Store new pending states
    assign current_pointer_oh = 1 << current_pointer_wb_r;
    always_ff @(posedge clk or negedge rst_n) begin : pending_status
        if (!rst_n) begin
            pending_elem <= '0;
        end else begin
            if (start_new_instruction) begin
                pending_elem <= nxt_pending_elem;
            end else if (start_new_loop) begin
                pending_elem <= nxt_pending_elem_loop;
            end else if (new_transaction_en) begin // single-request
                pending_elem[current_pointer_wb_r] <= 1'b0;
            end
        end
    end

    // Keep track of the expanions happening
    always_ff @(posedge clk or negedge rst_n) begin : loop_tracking
        if (!rst_n) begin
            current_exp_loop_r <= 0;
            src1_r             <= 0;
        end else begin
            if (start_new_instruction) begin
                current_exp_loop_r <= 0;
                src1_r             <= instr_in.dst;
            end else if (start_new_loop) begin
                current_exp_loop_r <= current_exp_loop_r + 1;
                src1_r             <= src1_r + 1;
            end
        end
    end

    // Store the max expansion when reconfiguring
    always_ff @(posedge clk or negedge rst_n) begin : maxExp
        if (!rst_n) begin
            max_expansion_r <= 'd1;
        end else begin
            max_expansion_r <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end
    end

    //=======================================================
    // Capture Instruction Information
    //=======================================================
    always_ff @(posedge clk or negedge rst_n) begin : proc_vl_r
        if (!rst_n) begin
            instr_vl_r <= VECTOR_LANES;
        end else begin
            if (start_new_instruction) begin
                instr_vl_r <= instr_in.vl;
            end
        end
    end

    assign nxt_memory_op = instr_in.ir_funct12[MEM_OP_RANGE_HI:MEM_OP_RANGE_LO];
    always_ff @(posedge clk or negedge rst_n) begin : proc_memory_op_r
        if (!rst_n) begin
            memory_op_r <= '0;
        end else begin
            if (start_new_instruction) begin
                memory_op_r <= nxt_memory_op;
            end
        end
    end

endmodule