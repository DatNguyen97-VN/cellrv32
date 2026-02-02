// ##################################################################################################
// # << CELLRV32 - Vector Load Unit >>                                                              #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vmu_ld_eng #(
    parameter int REQ_DATA_WIDTH     = 32 ,
    parameter int VECTOR_REGISTERS   = 32 ,
    parameter int VECTOR_LANES       = 8  ,
    parameter int DATA_WIDTH         = 32 ,
    parameter int ADDR_WIDTH         = 32 ,
    parameter int MICROOP_WIDTH      = 5  
) (
    //=======================================================
    // Clock & Reset
    //=======================================================
    input  logic                                clk_i         , // System clock.
    input  logic                                rstn_i        , // Active-low synchronous reset.
    //Input Interface
    //=======================================================
    // Instruction Input Interface
    //=======================================================
    input  logic                                valid_in      , // Indicates a new vector load instruction is available.
    input  memory_remapped_v_instr              instr_in      , // Remapped vector load instruction (decoded fields).
    output logic                                ready_o       , // Engine can accept a new instruction when high.
    //=======================================================
    // RF Writeback Interface
    //=======================================================
    output logic [            VECTOR_LANES-1:0] wrtbck_en_o   , // Per-lane write-enable vector.
    output logic [$clog2(VECTOR_REGISTERS)-1:0] wrtbck_reg_o  , // Destination vector register index.
    output logic [ VECTOR_LANES*DATA_WIDTH-1:0] wrtbck_data_o , // Lane-wise load data returned to RF.
    //=======================================================
    // Unlock Interface (after writeback completes)
    //=======================================================
    output logic                                unlock_en_o   , // Assert to unlock the destination/src registers.
    output logic [$clog2(VECTOR_REGISTERS)-1:0] unlock_reg_a_o, // Register to unlock (dst).
    //=======================================================
    // Memory Request Interface (to L1 / D-cache)
    //=======================================================
    input  logic                                grant_i       , // Memory system grants request.
    output logic                                req_en_o      , // Send memory request when asserted.
    output logic [              ADDR_WIDTH-1:0] req_addr_o    , // Byte address for memory load.
    output logic [    $clog2(VECTOR_LANES)-1:0] req_ticket_o  , // Unique ticket identifying the request (row + lane ID).
    //=======================================================
    // Incoming Data from Cache
    //=======================================================
    input  logic                                resp_valid_i  , // Memory returns valid load data.
    input  logic [    $clog2(VECTOR_LANES)-1:0] resp_ticket_i , // Ticket indicating which lane/row is being returned.
    input  logic [          REQ_DATA_WIDTH-1:0] resp_data_i   , // Raw memory data (up to REQ_DATA_WIDTH bits).
    //=======================================================
    // Status / Sync Interface
    //=======================================================
    output logic                                is_busy_o       // High when load engine is executing an instruction.
);

    localparam int ELEMENT_ADDR_WIDTH = $clog2(VECTOR_LANES);
    localparam int VREG_ADDR_WIDTH    = $clog2(VECTOR_REGISTERS);
    //=======================================================
    // INTERNAL SIGNALS
    // =======================================================
    logic                                                             current_finished            ;
    logic                                                             currently_idle              ;
    logic                                                             expansion_finished          ;
    logic                                                             maxvl_reached               ;
    logic                                                             vl_reached                  ;
    logic                                                             request_ready               ;
    logic                                                             row_ready                   ;
    logic [                         ADDR_WIDTH-1:0]                   current_addr                ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_base_addr               ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_strided_addr            ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_unit_strided_addr       ;
    logic                                                             start_new_instruction       ;
    logic                                                             new_transaction_en          ;
    logic [                         ADDR_WIDTH-1:0]                   current_addr_r              ;
    logic [                         ADDR_WIDTH-1:0]                   stride_r                    ;
    logic [                       VECTOR_LANES-1:0]                   resp_elem_th                ;
    logic        [VECTOR_LANES-1:0][DATA_WIDTH-1:0]                   scratchpad                  ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   row_rdst                    ;
    logic                                                             start_new_loop              ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0]                   nxt_total_remaining_elements;
    logic [                 ELEMENT_ADDR_WIDTH-1:0]                   nxt_elem                    ;
    logic [                 ELEMENT_ADDR_WIDTH-1:0]                   current_pointer_wb_r        ;
    logic [                       VECTOR_LANES-1:0]                   nxt_pending_elem            ;
    logic [                       VECTOR_LANES-1:0]                   nxt_pending_elem_loop       ;
    logic                                          [VECTOR_LANES-1:0] pending_elem                ;
    logic                                          [VECTOR_LANES-1:0] active_elem                 ;
    logic                                          [VECTOR_LANES-1:0] served_elem                 ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   current_exp_loop_r          ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   rdst_r                      ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   max_expansion_r             ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0]                   instr_vl_r                  ;
    logic [                                    1:0]                   memory_op_r                 ;
    logic [                                    1:0]                   nxt_memory_op               ;

    // Create basic control flow
    //=======================================================
    assign ready_o   =  currently_idle;
    assign is_busy_o = ~currently_idle;

    // current instruction finished
    assign current_finished = ~pending_elem[nxt_elem] & expansion_finished & new_transaction_en;

    // currently no instructions are being served
    assign currently_idle = ~|pending_elem & ~|active_elem;

    assign expansion_finished = maxvl_reached | vl_reached;
    assign maxvl_reached      = (current_exp_loop_r == (max_expansion_r-1));
    assign vl_reached         = (((current_exp_loop_r+1) << $clog2(VECTOR_LANES)) >= instr_vl_r);

    assign start_new_instruction = valid_in & ready_o & ~instr_in.reconfigure;

    // Start from element 0 on the next destination vreg
    assign start_new_loop = ~|pending_elem & ~expansion_finished & ~|active_elem;

    // Create the memory request control signals
    assign req_en_o      = request_ready;
    assign req_addr_o    = current_addr;
    assign req_ticket_o  = current_pointer_wb_r;

    assign new_transaction_en = req_en_o & grant_i;
    assign request_ready      = pending_elem[current_pointer_wb_r];

    // Unlock register signals
    assign unlock_en_o     = row_ready;
    assign unlock_reg_a_o  = row_rdst;

    // Create the writeback signals for the RF
    assign row_ready = ~|(active_elem ^ served_elem) & |active_elem;

    // Output aliasing
    assign wrtbck_en_o     = {VECTOR_LANES{row_ready}} & served_elem;
    assign wrtbck_data_o   = scratchpad;
    assign wrtbck_reg_o    = row_rdst;

    //=======================================================
    // Address Generation
    //=======================================================
    // Generate next non-multi consecutive address
    always_comb begin
        case (memory_op_r)
            OP_UNIT_STRIDED : current_addr = current_addr_r;
            OP_STRIDED      : current_addr = current_addr_r;
            default         : current_addr = '0;
        endcase
    end

    assign nxt_base_addr    = instr_in.data1; // first element address
    assign nxt_strided_addr = current_addr_r + stride_r;

    // size_r indicates the size of each element (8/16/32 bits)
    // the number of elements loaded in a request
    // --> multiply by size to get the number of bytes to add
    assign nxt_unit_strided_addr = current_addr_r + 4;
    
    // Hold current address
    always_ff @(posedge clk_i) begin
        if (start_new_instruction) begin
            current_addr_r <= nxt_base_addr;
        end else if (new_transaction_en && memory_op_r == OP_STRIDED) begin
            current_addr_r <= nxt_strided_addr;
        end else if (new_transaction_en && memory_op_r == OP_UNIT_STRIDED) begin
            current_addr_r <= nxt_unit_strided_addr;
        end
    end

    // Hold stride
    always_ff @(posedge clk_i) begin
        if (start_new_instruction) stride_r <= instr_in.data2; // distance between two consecutive elements (in bytes)
    end
    //=======================================================
    // Scratchpad maintenance
    //=======================================================
    // Each request loads only 1 element
    assign resp_elem_th = resp_ticket_i;

    // Store new Data
    always_ff @(posedge clk_i or negedge rstn_i) begin : scratchpad_maint
        if (!rstn_i) begin
            scratchpad <= '0;
        end else begin
            // ========================
            // row 0 maintenance
            // ========================
            if (resp_valid_i) begin
                scratchpad[resp_elem_th] <= resp_data_i;
            end
        end
    end : scratchpad_maint

    // keep track of the rdst for each row
    always_ff @(posedge clk_i or negedge rstn_i) begin : keep_track_dst
        if(!rstn_i) begin
            row_rdst <= 0;
        end else begin
            // row 0 maintenance
            if (start_new_instruction) begin
                row_rdst <= instr_in.dst;
            end else if (start_new_loop) begin
                row_rdst <= rdst_r + 1;
            end
        end
    end : keep_track_dst
    
    //=======================================================
    // Scoreboard maintenance
    //=======================================================
    assign nxt_total_remaining_elements = instr_vl_r - ((current_exp_loop_r+1)*VECTOR_LANES);

    // Maintain current pointer
    assign nxt_elem = current_pointer_wb_r + 1;
    always_ff @(posedge clk_i or negedge rstn_i) begin : current_ptr
        if(!rstn_i) begin
            current_pointer_wb_r <= 0;
        end else begin
            if (start_new_instruction) begin
                current_pointer_wb_r <= 0;
            end else if (start_new_loop) begin
                current_pointer_wb_r <= 0;
            end else if (current_finished) begin
                current_pointer_wb_r <= 0;
            end else if (new_transaction_en) begin
                current_pointer_wb_r <= nxt_elem;
            end
        end
    end : current_ptr

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
    end : get_new_elem_pending

    // Store new pending states
    always_ff @(posedge clk_i or negedge rstn_i) begin : pending_status
        if (!rstn_i) begin
            pending_elem <= '0;
        end else begin
            // ========================
            // row 0 maintenance
            // ========================
            if (start_new_instruction) begin
                pending_elem <= nxt_pending_elem;
            end else if (start_new_loop) begin
                pending_elem <= nxt_pending_elem_loop;
            end else if (new_transaction_en) begin // single-request
                pending_elem[current_pointer_wb_r] <= 1'b0;
            end
        end
    end  : pending_status

    // Keep track of active elements
    always_ff @(posedge clk_i or negedge rstn_i) begin : active_status
        if (!rstn_i) begin
            active_elem <= '0;
        end else begin
            if (row_ready) begin
                active_elem <= '0;
            end else if (start_new_instruction) begin
                active_elem <= nxt_pending_elem;
            end else if (start_new_loop) begin
                active_elem <= nxt_pending_elem_loop;
            end
        end
    end : active_status

    // Keep track of served elements from memory
    always_ff @(posedge clk_i or negedge rstn_i) begin : keep_track_elem
        if (!rstn_i) begin
            served_elem <= '0;
        end else begin
            if(start_new_instruction) begin
                served_elem <= 1'b0;
            end else if (start_new_loop) begin
                served_elem <= 1'b0;
            end else if (resp_valid_i) begin
                served_elem[resp_elem_th] <= 1'b1;
            end
        end
    end : keep_track_elem

    // Keep track of the expanions happening
    always_ff @(posedge clk_i or negedge rstn_i) begin : loop_tracking
        if (!rstn_i) begin
            current_exp_loop_r <= 0;
        end else begin
            if (start_new_instruction) begin
                current_exp_loop_r <= 0;
                rdst_r             <= instr_in.dst;
            end else if (start_new_loop) begin
                current_exp_loop_r <= current_exp_loop_r + 1;
                rdst_r             <= rdst_r + 1;
            end
        end
    end : loop_tracking
    
    // Store the max expansion when reconfiguring
    always_ff @(posedge clk_i or negedge rstn_i) begin : maxExp
        if (!rstn_i) begin
            max_expansion_r <= 'd1;
        end else begin
            max_expansion_r <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end
    end : maxExp

    //=======================================================
    // Capture Instruction Information
    always_ff @(posedge clk_i or negedge rstn_i) begin : proc_vl_r
        if(!rstn_i) begin
            instr_vl_r <= VECTOR_LANES;
        end else begin
            if (start_new_instruction) begin
                instr_vl_r <= instr_in.vl;
            end
        end
    end : proc_vl_r

    assign nxt_memory_op = instr_in.ir_funct12[MEM_OP_RANGE_HI:MEM_OP_RANGE_LO];
    always_ff @(posedge clk_i or negedge rstn_i) begin : proc_memory_op_r
        if (!rstn_i) begin
            memory_op_r <= '0;
        end else begin
            if (start_new_instruction) begin
                memory_op_r <= nxt_memory_op;
            end
        end
    end : proc_memory_op_r

endmodule