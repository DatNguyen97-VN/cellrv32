// ##################################################################################################
// # << CELLRV32 - Vector Load Unit >>                                                              #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vmu_ld_eng #(
    parameter int REQ_DATA_WIDTH     = 256,
    parameter int VECTOR_REGISTERS   = 32 ,
    parameter int VECTOR_LANES       = 8  ,
    parameter int DATA_WIDTH         = 32 ,
    parameter int ADDR_WIDTH         = 32 ,
    parameter int MICROOP_WIDTH      = 5  ,
    parameter int VECTOR_TICKET_BITS = 4
) (
    //=======================================================
    // Clock & Reset
    //=======================================================
    input  logic                                clk_i                , // System clock.
    input  logic                                rstn_i               , // Active-low synchronous reset.
    //Input Interface
    //=======================================================
    // Instruction Input Interface
    //=======================================================
    input  logic                                valid_in             , // Indicates a new vector load instruction is available.
    input  memory_remapped_v_instr              instr_in             , // Remapped vector load instruction (decoded fields).
    output logic                                ready_o              , // Engine can accept a new instruction when high.
    //=======================================================
    // RF Read Interface (for OP_INDEXED only)
    //=======================================================
    output logic [$clog2(VECTOR_REGISTERS)-1:0] rd_addr_o            , // Address of vector register to read index values from.
    input  logic [ VECTOR_LANES*DATA_WIDTH-1:0] rd_data_i            , // Lane-wise data read from RF (used to compute indexed addresses).
    input  logic                                rd_pending_i         , // RF read in progress; block address generation.
    input  logic [      VECTOR_TICKET_BITS-1:0] rd_ticket_i          , // Ticket tag for RF read to guarantee ordering.
    //=======================================================
    // RF Writeback Interface
    //=======================================================
    output logic                                wrtbck_req_o         , // Request to write back the loaded vector elements.
    input  logic                                wrtbck_grant_i       , // Grant from RF allowing writeback.
    output logic [            VECTOR_LANES-1:0] wrtbck_en_o          , // Per-lane write-enable vector.
    output logic [$clog2(VECTOR_REGISTERS)-1:0] wrtbck_reg_o         , // Destination vector register index.
    output logic [ VECTOR_LANES*DATA_WIDTH-1:0] wrtbck_data_o        , // Lane-wise load data returned to RF.
    output logic [      VECTOR_TICKET_BITS-1:0] wrtbck_ticket_o      , // Ticket tag for writeback completion tracking.
    //=======================================================
    // RF Writeback Probing Interface
    //=======================================================
    output logic [$clog2(VECTOR_REGISTERS)-1:0] wrtbck_prb_reg_a_o   , // Probe register A for availability (row 0 dst).
    input  logic                                wrtbck_prb_locked_a_i, // Indicates RF A side is locked by another operation.
    input  logic [      VECTOR_TICKET_BITS-1:0] wrtbck_prb_ticket_a_i, // Ticket for RF A side.
    output logic [$clog2(VECTOR_REGISTERS)-1:0] wrtbck_prb_reg_b_o   , // Probe register B for availability (row 1 dst).
    input  logic                                wrtbck_prb_locked_b_i, // Indicates RF B side is locked by another operation.
    input  logic [      VECTOR_TICKET_BITS-1:0] wrtbck_prb_ticket_b_i, // Ticket for RF B side.
    //=======================================================
    // Unlock Interface (after writeback completes)
    //=======================================================
    output logic                                unlock_en_o          , // Assert to unlock the destination/src registers.
    output logic [$clog2(VECTOR_REGISTERS)-1:0] unlock_reg_a_o       , // Register to unlock (dst).
    output logic [$clog2(VECTOR_REGISTERS)-1:0] unlock_reg_b_o       , // Register to unlock (src).
    output logic [      VECTOR_TICKET_BITS-1:0] unlock_ticket_o      , // Ticket tag associated with the completed instruction.
    //=======================================================
    // Memory Request Interface (to L1 / D-cache)
    //=======================================================
    input  logic                                grant_i              , // Memory system grants request.
    output logic                                req_en_o             , // Send memory request when asserted.
    output logic [              ADDR_WIDTH-1:0] req_addr_o           , // Byte address for memory load.
    output logic [           MICROOP_WIDTH-1:0] req_microop_o        , // Micro-operation type (load variants).
    output logic [  $clog2(REQ_DATA_WIDTH/8):0] req_size_o           , // Byte count of the request (depends on element size).
    output logic [      $clog2(VECTOR_LANES):0] req_ticket_o         , // Unique ticket identifying the request (row + lane ID).
    //=======================================================
    // Incoming Data from Cache
    //=======================================================
    input  logic                                resp_valid_i         , // Memory returns valid load data.
    input  logic [      $clog2(VECTOR_LANES):0] resp_ticket_i        , // Ticket indicating which lane/row is being returned.
    input  logic [          REQ_DATA_WIDTH-1:0] resp_data_i          , // Raw memory data (up to REQ_DATA_WIDTH bits).
    //=======================================================
    // Status / Sync Interface
    //=======================================================
    output logic                                is_busy_o            , // High when load engine is executing an instruction.
    output logic [              ADDR_WIDTH-1:0] start_addr_o         , // First address accessed by this load instruction.
    output logic [              ADDR_WIDTH-1:0] end_addr_o             // Last address accessed by this load instruction.
);

    localparam int ELEMENT_ADDR_WIDTH   = $clog2(VECTOR_LANES);
    localparam int VREG_ADDR_WIDTH      = $clog2(VECTOR_REGISTERS);
    localparam int MAX_MEM_SERVED_LIMIT = REQ_DATA_WIDTH / DATA_WIDTH;
    localparam int MAX_RF_SERVED_COUNT  = VECTOR_REGISTERS;
    localparam int MAX_SERVED_COUNT     = (VECTOR_REGISTERS > MAX_MEM_SERVED_LIMIT) ? MAX_MEM_SERVED_LIMIT
                                                                                    : VECTOR_REGISTERS;
    //=======================================================
    // INTERNAL SIGNALS
    // =======================================================
    logic                                                             current_finished            ;
    logic                                                             currently_idle              ;
    logic                                                             expansion_finished          ;
    logic                                                             maxvl_reached               ;
    logic                                                             vl_reached                  ;
    logic                                                             do_reconfigure              ;
    logic                                                             request_ready               ;
    logic                                                             addr_ready                  ;
    logic                                                             row_0_ready                 ;
    logic                                                             row_1_ready                 ;
    logic                                                             multi_valid                 ;
    logic [    $clog2(VECTOR_LANES*DATA_WIDTH)-1:0]                   element_index               ;
    logic [                         ADDR_WIDTH-1:0]                   offset_read                 ;
    logic [                         ADDR_WIDTH-1:0]                   current_addr                ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_base_addr               ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_strided_addr            ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_unit_strided_addr       ;
    logic                                                             start_new_instruction       ;
    logic                                                             new_transaction_en          ;
    logic [                         ADDR_WIDTH-1:0]                   current_addr_r              ;
    logic [                         ADDR_WIDTH-1:0]                   base_addr_r                 ;
    logic [                         ADDR_WIDTH-1:0]                   nxt_stride                  ;
    logic [                         ADDR_WIDTH-1:0]                   stride_r                    ;
    logic                                                             resp_row                    ;
    logic [                   ELEMENT_ADDR_WIDTH:0]                   resp_el_count               ;
    logic [                         VECTOR_LANES:0]                   resp_elem_th                ;
    logic [        MAX_SERVED_COUNT*DATA_WIDTH-1:0]                   unpacked_data               ;
    logic [            VECTOR_LANES*DATA_WIDTH-1:0]                   data_vector                 ;
    logic [1:0][VECTOR_LANES-1:0][DATA_WIDTH-1:0]                     scratchpad                  ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   row_0_rdst                  ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   row_1_rdst                  ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   row_0_src                   ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   row_1_src                   ;
    logic                                                             start_new_loop              ;
    logic [                   ELEMENT_ADDR_WIDTH:0]                   loop_remaining_elements     ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0]                   nxt_total_remaining_elements;
    logic [                   ELEMENT_ADDR_WIDTH:0]                   el_served_count             ;
    logic                                                             nxt_row                     ;
    logic [                 ELEMENT_ADDR_WIDTH-1:0]                   nxt_elem                    ;
    logic [                 ELEMENT_ADDR_WIDTH-1:0]                   current_pointer_wb_r        ;
    logic                                                             current_row                 ;
    logic [                       VECTOR_LANES-1:0]                   nxt_pending_elem            ;
    logic [                       VECTOR_LANES-1:0]                   nxt_pending_elem_loop       ;
    logic [                         VECTOR_LANES:0]                   current_pointer_oh          ;
    logic [                         VECTOR_LANES:0]                   current_served_th           ;
    logic [                                    1:0][VECTOR_LANES-1:0] pending_elem                ;
    logic [                                    1:0][VECTOR_LANES-1:0] active_elem                 ;
    logic [                                    1:0][VECTOR_LANES-1:0] served_elem                 ;
    logic                                                             writeback_complete          ;
    logic                                                             writeback_row               ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   current_exp_loop_r          ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   src2_r                      ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   rdst_r                      ;
    logic [                    VREG_ADDR_WIDTH-1:0]                   max_expansion_r             ;
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0]                   instr_vl_r                  ;
    logic [                      MICROOP_WIDTH-1:0]                   microop_r                   ;
    logic [                 VECTOR_TICKET_BITS-1:0]                   ticket_r                    ;
    logic [                                    4:0]                   last_ticket_src2_r          ;
    logic [                                    1:0]                   memory_op_r                 ;
    logic [                                    1:0]                   nxt_memory_op               ;
    logic [                         ADDR_WIDTH-1:0]                   start_addr_r                ;
    logic [                         ADDR_WIDTH-1:0]                   end_addr_r                  ;

    // Create basic control flow
    //=======================================================
    assign ready_o             =  currently_idle;
    assign is_busy_o           = ~currently_idle;

    // current instruction finished
    assign current_finished = ~pending_elem[current_row][nxt_elem] & expansion_finished & new_transaction_en;

    // currently no instructions are being served
    assign currently_idle = ~|pending_elem & ~|active_elem;

    assign expansion_finished = maxvl_reached | vl_reached;
    assign maxvl_reached      = (current_exp_loop_r === (max_expansion_r-1));
    assign vl_reached         = (((current_exp_loop_r+1) << $clog2(VECTOR_LANES)) >= instr_vl_r);

    assign start_new_instruction = valid_in & ready_o & ~instr_in.reconfigure;
    assign do_reconfigure        = ready_o & instr_in.reconfigure;

    // Start from element 0 on the next destination vreg
    assign start_new_loop = ~|pending_elem[current_row] & ~expansion_finished & ~|active_elem[nxt_row];

    // Create the memory request control signals
    assign req_en_o      = request_ready;
    assign req_addr_o    = current_addr;
    assign req_microop_o = 5'b10000; // REVISIT will change based on instruction
    assign req_ticket_o  = {current_row,current_pointer_wb_r};

    assign req_size_o = el_served_count << 2; // el_served_count * 4

    assign new_transaction_en = req_en_o & grant_i;
    assign request_ready      = addr_ready & pending_elem[current_row][current_pointer_wb_r];
    assign addr_ready         = (memory_op_r === OP_INDEXED) ? ~rd_pending_i & ((rd_ticket_i === ticket_r) | (rd_ticket_i === last_ticket_src2_r)) : 1'b1;

    // Unlock register signals
    assign unlock_en_o     = writeback_complete;
    assign unlock_ticket_o = ticket_r;
    assign unlock_reg_a_o  = row_0_ready ? row_0_rdst : row_1_rdst;
    assign unlock_reg_b_o  = row_0_ready ? row_0_src  : row_1_src;


    // Create the writeback signals for the RF
    assign wrtbck_req_o       = row_0_ready | row_1_ready;
    assign writeback_complete = (row_0_ready | row_1_ready) & wrtbck_grant_i;
    assign writeback_row      = row_0_ready ? 1'b0 : 1'b1;

    assign row_0_ready = ~|(active_elem[0] ^ served_elem[0]) & |active_elem[0] & (wrtbck_prb_ticket_a_i === ticket_r) & wrtbck_prb_locked_a_i;
    assign row_1_ready = ~|(active_elem[1] ^ served_elem[1]) & |active_elem[1] & (wrtbck_prb_ticket_b_i === ticket_r) & wrtbck_prb_locked_b_i;

    // Output aliasing
    assign wrtbck_en_o     = row_0_ready ? {VECTOR_LANES{writeback_complete}} & served_elem[0] :
                                           {VECTOR_LANES{writeback_complete}} & served_elem[1];
    assign wrtbck_data_o   = row_0_ready ? scratchpad[0] : scratchpad[1];
    assign wrtbck_reg_o    = row_0_ready ? row_0_rdst    : row_1_rdst;
    assign wrtbck_ticket_o = ticket_r;
    assign wrtbck_prb_reg_a_o  = row_0_rdst;
    assign wrtbck_prb_reg_b_o  = row_1_rdst;

    // assign the rest of the outputs
    assign rd_addr_o    = src2_r;
    assign start_addr_o = start_addr_r;
    assign end_addr_o   = end_addr_r;
    //=======================================================
    // Address Generation
    //=======================================================
    assign multi_valid   = 1'b0; // Each request can load multiple elements at once.
    assign element_index = current_pointer_wb_r << 5; //*32, each lane has 32 bits
    assign offset_read   = rd_data_i[element_index +: DATA_WIDTH];
    // Generate next non-multi consecutive address
    always_comb begin
        case (memory_op_r)
            OP_UNIT_STRIDED : current_addr = current_addr_r;
            OP_STRIDED      : current_addr = current_addr_r;
            OP_INDEXED      : current_addr = base_addr_r + offset_read;
            default          : current_addr = 'X;
        endcase
    end

    assign nxt_base_addr    = instr_in.data1 + instr_in.data2; // first element address
    assign nxt_strided_addr = current_addr_r + stride_r;

    // size_r indicates the size of each element (8/16/32 bits)
    // el_served_count is the number of elements loaded in a request
    // --> multiply by size to get the number of bytes to add
    assign nxt_unit_strided_addr = current_addr_r + (el_served_count << 2);
    //Hold current address
    always_ff @(posedge clk_i) begin
        if(start_new_instruction) begin
            current_addr_r <= nxt_base_addr;
        end else if (new_transaction_en && memory_op_r == OP_STRIDED) begin
            current_addr_r <= nxt_strided_addr;
        end else if(new_transaction_en && memory_op_r == OP_UNIT_STRIDED) begin
            current_addr_r <= nxt_unit_strided_addr;
        end
    end
    //Hold base address
    always_ff @(posedge clk_i) begin
        if(start_new_instruction) begin
            base_addr_r <= nxt_base_addr;
        end
    end
    //Hold stride
    assign nxt_stride = instr_in.data2;
    always_ff @(posedge clk_i) begin
        if(start_new_instruction) stride_r <= nxt_stride; // distance between two consecutive elements (in bytes)
    end
    //=======================================================
    // Scratchpad maintenance
    //=======================================================
    assign resp_row = resp_ticket_i[ELEMENT_ADDR_WIDTH];
    // Calculate the elements that have a valid response
    assign resp_el_count = 4 >> 2; // el_served_count * 4

    // valid element mask
    // not UNIT_STRIDED: Each request loads only 1 element
    // UNIT_STRIDED: A request can load multiple elements consecutively
    assign resp_elem_th = (memory_op_r != OP_UNIT_STRIDED) ? (1 << resp_ticket_i[ELEMENT_ADDR_WIDTH-1:0]) : 
                                                              ((~('1 << resp_el_count)) << resp_ticket_i[ELEMENT_ADDR_WIDTH-1:0]);
    // Unpack the data into elements
    always_comb begin
        unpacked_data = '0;
        if(!multi_valid) begin
            unpacked_data[0 +: 32] = resp_data_i[0 +: 32];
        end else begin
            for (int i = 0; i < MAX_SERVED_COUNT; i++) begin
                unpacked_data[i*32 +: 32] = resp_data_i[i*32 +: 32]; // pick 32-bits for each elem
            end
        end
    end

    // Shift unpacked data vector to match the elements positions
    assign data_vector = unpacked_data << ({5'b00000, resp_ticket_i[ELEMENT_ADDR_WIDTH-1:0]} << 5);
    // Store new Data
    always_ff @(posedge clk_i) begin : scratchpad_maint
        for (int i = 0; i < VECTOR_LANES; i++) begin
            // row 0 maintenance
            if(resp_valid_i && !resp_row && resp_elem_th[i]) begin
                scratchpad[0][i] <= data_vector[i*32 +: 32];
            end
            // row 1 maintenance
            if(resp_valid_i && resp_row && resp_elem_th[i]) begin
                scratchpad[1][i] <= data_vector[i*32 +: 32];
            end
        end
    end

    // keep track of the rdst for each row
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            row_0_rdst <= 0;
            row_1_rdst <= 0;
        end else begin
            // row 0 maintenance
            if(start_new_instruction) begin
                row_0_rdst <= instr_in.dst;
                row_0_src  <= instr_in.src2;
            end else if(start_new_loop && !nxt_row) begin
                row_0_rdst <= rdst_r + 1;
                row_0_src  <= src2_r + 1;
            end
            // row 1 maintenance
            if(start_new_loop && nxt_row) begin
                row_1_rdst <= rdst_r + 1;
                row_1_src  <= src2_r + 1;
            end
        end
    end
    
    //=======================================================
    // Scoreboard maintenance
    //=======================================================
    
    always_comb begin : proc_loop_remaining_el
        loop_remaining_elements = '0;
        for (int i = 0; i < VECTOR_LANES; i++) begin
            if (pending_elem[current_row][i]) loop_remaining_elements = loop_remaining_elements + 1;
        end
    end
     
    assign nxt_total_remaining_elements = instr_vl_r - ((current_exp_loop_r+1)*VECTOR_LANES);
    always_comb begin : get_served_el_cnt
        if (memory_op_r === OP_UNIT_STRIDED) begin
            el_served_count = 'd1;
        end else if (loop_remaining_elements < MAX_SERVED_COUNT) begin
            el_served_count = loop_remaining_elements; // remaining < max_width
        end else begin
            el_served_count = MAX_SERVED_COUNT; // remaining > max_width
        end
    end

    // Maintain current pointer and row
    assign nxt_row  = ~current_row;
    assign nxt_elem = multi_valid ? (current_pointer_wb_r + el_served_count) : (current_pointer_wb_r + 1);
    always_ff @(posedge clk_i or negedge rstn_i) begin : current_ptr
        if(!rstn_i) begin
            current_pointer_wb_r <= 0;
            current_row          <= 0;
        end else begin
            if(start_new_instruction) begin
                current_pointer_wb_r <= 0;
                current_row          <= 0;
            end else if(start_new_loop) begin
                current_pointer_wb_r <= 0;
                current_row          <= nxt_row;
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
    assign current_served_th  = (~('1 << el_served_count)) << current_pointer_wb_r;
    assign current_pointer_oh = 1 << current_pointer_wb_r;
    always_ff @(posedge clk_i or negedge rstn_i) begin : pending_status
        if(!rstn_i) begin
            pending_elem <= '0;
        end else begin
            for (int i = 0; i < VECTOR_LANES; i++) begin
                //row 0 maintenance
                if(start_new_instruction) begin
                    pending_elem[0][i] <= nxt_pending_elem[i];
                end else if(start_new_loop && !nxt_row) begin
                    pending_elem[0][i] <= nxt_pending_elem_loop[i];
                end else if(new_transaction_en && current_served_th[i] && multi_valid && !current_row) begin // multi-request
                    pending_elem[0][i] <= 1'b0;
                end else if(new_transaction_en && current_pointer_oh[i] && !multi_valid && !current_row) begin // single-request
                    pending_elem[0][i] <= 1'b0;
                end
                //row 1 maintenance
                if(start_new_instruction) begin
                    pending_elem[1][i] <= 1'b0;
                end else if(start_new_loop && nxt_row) begin
                    pending_elem[1][i] <= nxt_pending_elem_loop[i];
                end else if(new_transaction_en && current_served_th[i] && multi_valid && current_row) begin // multi-request
                    pending_elem[1][i] <= 1'b0;
                end else if(new_transaction_en && current_pointer_oh[i] && !multi_valid && current_row) begin // single-request
                    pending_elem[1][i] <= 1'b0;
                end
            end
        end
    end

    // Keep track of active elements
    always_ff @(posedge clk_i or negedge rstn_i) begin : active_status
        if(!rstn_i) begin
            active_elem <= '0;
        end else begin
            for (int i = 0; i < VECTOR_LANES; i++) begin
                // row 0 maintenance
                if (writeback_complete && !writeback_row) begin
                    active_elem[0][i] <= 1'b0;
                end else if(start_new_instruction) begin
                    active_elem[0][i] <= nxt_pending_elem[i];
                end else if(start_new_loop && !nxt_row) begin
                    active_elem[0][i] <= nxt_pending_elem_loop[i];
                end
                // row 1 maintenance
                if (writeback_complete && writeback_row) begin
                    active_elem[1][i] <= 1'b0;
                end else if(start_new_instruction) begin
                    active_elem[1][i] <= 1'b0;
                end else if(start_new_loop && nxt_row) begin
                    active_elem[1][i] <= nxt_pending_elem_loop[i];
                end
            end
        end
    end

    // Keep track of served elements from memory
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            served_elem <= '0;
        end else begin
            for (int i = 0; i < VECTOR_LANES; i++) begin
                // row 0 maintenance
                if(start_new_instruction) begin
                    served_elem[0][i] <= 1'b0;
                end else if(start_new_loop && !nxt_row) begin
                    served_elem[0][i] <= 1'b0;
                end else if(resp_valid_i && resp_elem_th[i] && !resp_row) begin
                    served_elem[0][i] <= 1'b1;
                end
                // row 1 maintenance
                if(start_new_instruction) begin
                    served_elem[1][i] <= 1'b0;
                end else if(start_new_loop && nxt_row) begin
                    served_elem[1][i] <= 1'b0;
                end else if(resp_valid_i && resp_elem_th[i] && resp_row) begin
                    served_elem[1][i] <= 1'b1;
                end
            end
        end
    end

    // Keep track of the expanions happening
    always_ff @(posedge clk_i or negedge rstn_i) begin : loop_tracking
        if(!rstn_i) begin
            current_exp_loop_r <= 0;
        end else begin
            if(start_new_instruction) begin
                current_exp_loop_r <= 0;
                src2_r             <= instr_in.src2;
                rdst_r             <= instr_in.dst;
            end else if(start_new_loop) begin
                current_exp_loop_r <= current_exp_loop_r + 1;
                src2_r             <= src2_r + 1;
                rdst_r             <= rdst_r + 1;
            end
        end
    end
    
    // Store the max expansion when reconfiguring
    always_ff @(posedge clk_i or negedge rstn_i) begin : maxExp
        if(!rstn_i) begin
            max_expansion_r <= 'd1;
        end else begin
            max_expansion_r <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end
    end

    //=======================================================
    // Capture Instruction Information
    always_ff @(posedge clk_i or negedge rstn_i) begin : proc_vl_r
        if(!rstn_i) begin
            instr_vl_r <= VECTOR_LANES;
        end else begin
            if(start_new_instruction) begin
                instr_vl_r <= instr_in.vl;
            end
        end
    end
    always_ff @(posedge clk_i) begin
        if(start_new_instruction) begin
            microop_r          <= instr_in.microop;
            ticket_r           <= instr_in.ticket;
            last_ticket_src2_r <= instr_in.last_ticket_src2;
        end
    end
    assign nxt_memory_op = instr_in.ir_funct12[MEM_OP_RANGE_HI:MEM_OP_RANGE_LO];
    always_ff @(posedge clk_i or negedge rstn_i) begin : proc_memory_op_r
        if(!rstn_i) begin
            memory_op_r <= '0;
        end else begin
            if(start_new_instruction) begin
                memory_op_r <= nxt_memory_op;
            end
        end
    end

    // calculate start-end addresses for the op
    // +- 4 to avoid conflicts due to data sizes
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            start_addr_r <= '0;
            end_addr_r   <= '1;
        end else begin
            if(start_new_instruction) begin
                start_addr_r <= nxt_base_addr;
                if(instr_in.microop[MEM_OP_RANGE_HI:MEM_OP_RANGE_LO] !== OP_INDEXED) begin
                    end_addr_r <= nxt_base_addr + ((instr_in.vl -1) * nxt_stride);
                end else begin
                    end_addr_r <= nxt_base_addr; // cannot calculate end address for OP_INDEXED ops
                end
            end
        end
    end 

endmodule