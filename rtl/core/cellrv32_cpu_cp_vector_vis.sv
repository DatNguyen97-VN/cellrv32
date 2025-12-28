// ##################################################################################################
// # << CELLRV32 - Vector Issuing Logic >>                                                          #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS 

module vis #(
    parameter int VECTOR_REGISTERS   = 32,
    parameter int VECTOR_LANES       = 8 ,
    parameter int DATA_WIDTH         = 32,
    parameter int VECTOR_TICKET_BITS = 4
) (
    input  logic                                                                       clk_i           ,
    input  logic                                                                       rstn_i          ,
    output logic                                                                       is_idle_o       ,
    output logic                                                                       exec_finished_o ,
    //Instruction In
    input  logic                                                                       valid_in        ,
    input  remapped_v_instr                                                            instr_in        ,
    output logic                                                                       ready_o         ,
    //Instruction Out
    output logic                                                                       valid_o         ,
    output to_vector_exec [            VECTOR_LANES-1:0]                               data_to_exec    ,
    output to_vector_exec_info                                                         info_to_exec    ,
    input  logic                                                                       ready_i         ,
    //Memory Unit read ports
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_addr_0      ,
    output logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_data_0      ,
    output logic                                                                       mem_pending_0   ,
    output logic          [      VECTOR_TICKET_BITS-1:0]                               mem_ticket_0    ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_addr_1      ,
    output logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_data_1      ,
    output logic                                                                       mem_pending_1   ,
    output logic          [      VECTOR_TICKET_BITS-1:0]                               mem_ticket_1    ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_addr_2      ,
    output logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_data_2      ,
    output logic                                                                       mem_pending_2   ,
    output logic          [      VECTOR_TICKET_BITS-1:0]                               mem_ticket_2    ,
    //Memory Unit Probing port
    input  logic          [                         3:0][$clog2(VECTOR_REGISTERS)-1:0] mem_prb_reg_i   ,
    output logic          [                         3:0]                               mem_prb_locked_o,
    output logic          [                         3:0][      VECTOR_TICKET_BITS-1:0] mem_prb_ticket_o,
    //Memory Unit write port
    input  logic          [            VECTOR_LANES-1:0]                               mem_wr_en       ,
    input  logic          [      VECTOR_TICKET_BITS-1:0]                               mem_wr_ticket   ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_wr_addr     ,
    input  logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_wr_data     ,
    //Unlock ports
    input  logic                                                                       unlock_en       ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               unlock_reg_a    ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               unlock_reg_b    ,
    input  logic          [      VECTOR_TICKET_BITS-1:0]                               unlock_ticket   ,
    //Forward Point #1
    input  logic          [            VECTOR_LANES-1:0]                               frw_a_en        ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               frw_a_addr      ,
    input  logic          [            VECTOR_LANES-1:0][              DATA_WIDTH-1:0] frw_a_data      ,
    input  logic          [      VECTOR_TICKET_BITS-1:0]                               frw_a_ticket    ,
    //Forward Point #2
    input  logic          [            VECTOR_LANES-1:0]                               frw_b_en        ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               frw_b_addr      ,
    input  logic          [            VECTOR_LANES-1:0][              DATA_WIDTH-1:0] frw_b_data      ,
    input  logic          [      VECTOR_TICKET_BITS-1:0]                               frw_b_ticket    ,
    //Writeback (Forward Point #3)
    input  logic          [            VECTOR_LANES-1:0]                               wr_en           ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               wr_addr         ,
    input  logic          [            VECTOR_LANES-1:0][              DATA_WIDTH-1:0] wr_data         ,
    input  logic          [            VECTOR_LANES-1:0]                               rdc_done        ,
    input  logic          [      VECTOR_TICKET_BITS-1:0]                               wr_ticket
);

    localparam int TOTAL_ELEMENT_ADDR_WIDTH = $clog2(VECTOR_REGISTERS*VECTOR_LANES);
    localparam int ELEMENT_ADDR_WIDTH       = $clog2(VECTOR_LANES)                 ;
    localparam int VREG_ADDR_WIDTH          = $clog2(VECTOR_REGISTERS)             ;
    //=======================================================
    //Internal Status tracking
    //=======================================================
    logic [VECTOR_REGISTERS-1:0][VECTOR_TICKET_BITS-1:0] pending_ticket;
    logic [VECTOR_REGISTERS-1:0][VECTOR_TICKET_BITS-1:0] locked_ticket;
    logic [VECTOR_REGISTERS-1:0][VECTOR_LANES-1:0] pending, locked;
    logic [    VECTOR_LANES-1:0] vl_therm;
    logic [ VREG_ADDR_WIDTH-1:0] current_exp_loop  ; // Count the number of µops issued
    logic                        can_issue, can_issue_m;
    logic                        do_issue, output_ready;
    logic                        memory_instr;
    logic                        expansion_finished, maxvl_reached, vl_reached;
    logic                        do_reconfigure    ;
    logic                        pop               ;
    logic                        start_new_instr   ;
    logic                        instr_is_rdc      ;
    logic                        is_operand_imm    ;
    logic                        is_operand_scalar ;

    logic [6:0] total_remaining_elements;
    logic [VECTOR_LANES-1:0][DATA_WIDTH-1:0] data_1, data_2;
    logic [VREG_ADDR_WIDTH-1:0] src_1, src_2, dst, mask_src;
    logic [  VREG_ADDR_WIDTH:0] max_expansion;
    logic [   VECTOR_LANES-1:0] no_hazards, no_hazards_m;
    logic [   VECTOR_LANES-1:0] can_lock_sources, can_lock_destination;
    logic [   VECTOR_LANES-1:0] issue_masked, issue_m_masked;
    logic [   VECTOR_LANES-1:0] frw_a_src_1, frw_a_src_2;
    logic [   VECTOR_LANES-1:0] frw_b_src_1, frw_b_src_2;
    logic [   VECTOR_LANES-1:0] frw_c_src_1, frw_c_src_2;
    logic [   VECTOR_LANES-1:0] src1_ok, src2_ok, rdst_ok;
    logic [   VECTOR_LANES-1:0] valid_output;
    logic [   VECTOR_LANES-1:0] mask;

    // Check if instr is memory operation
    assign memory_instr = (instr_in.microop == opcode_vload_c) || (instr_in.microop == opcode_vstore_c) ? valid_in : 1'b0;

    assign start_new_instr = do_issue & ~|current_exp_loop;

    // Do reconfiguration
    assign do_reconfigure =  instr_in.reconfigure & exec_finished_o;
    assign exec_finished_o  = ~(|pending) & ~(|locked);

    //Check if instr expansion finished
    assign total_remaining_elements = instr_in.vl - (current_exp_loop*VECTOR_LANES); // number of unprocessed vector elements
    assign expansion_finished       = maxvl_reached | vl_reached;
    assign maxvl_reached            = (current_exp_loop === (max_expansion-1)); // Check if we are on the last µop according to the hardware configuration
    assign vl_reached               = (((current_exp_loop+1) << $clog2(VECTOR_LANES)) >= instr_in.vl); // Check if after the next µop we have covered the entire VL.

    //Check if the EX is ready to accept (only those that you need to send to)
    assign output_ready = ready_i; // Execution stage (vEX) is ready to receive new data
    assign vl_therm     = ~('1 << total_remaining_elements); // a vector with 1 bits corresponding to the lane to be processed in the current µop

    assign do_issue = memory_instr ? (valid_in & can_issue_m)     : // memory inst: Inst is valid and no hazard
                                     (valid_in & output_ready & can_issue); // non-memory inst: Instr is valid, EX is available, and no hazard.

    assign pop          = valid_in & ready_o; // instrcution is completed
    assign valid_output = (do_issue & ~memory_instr & ~instr_in.reconfigure) ? vl_therm : '0; // mask lane, disable output if memory/reconfiguration instruction 


    assign ready_o = instr_in.reconfigure ? exec_finished_o                                 : // all pending/locked clear
                     memory_instr         ? (can_issue_m & expansion_finished)              : // run out of µops memory
                     valid_in             ? (can_issue & expansion_finished & output_ready) : 1'b0; // run out of µops compute and EX ready

    // Track Instruction Expansion
    always_ff @(posedge clk_i or negedge rstn_i) begin : ExpansionTracker
        if(!rstn_i) begin
            current_exp_loop <= '0;
        end else begin
            // new instruction or reconfiguration
            if (do_reconfigure | pop) begin
                current_exp_loop <= '0;
            end else if (do_issue) begin
                // count the number of µops for the current instruction
                current_exp_loop <= current_exp_loop + 1;
            end
        end
    end

    // Store the max expansion per instruction
    // The maximum number of µops that need to be issued to process all maxvl elements
    always_ff @(posedge clk_i or negedge rstn_i) begin : maxExp
        if(!rstn_i) begin
            max_expansion <= '0;
        end else begin
            max_expansion <= instr_in.maxvl >> $clog2(VECTOR_LANES);
        end
    end

    // Struct containing control flow signals
    assign valid_o                = |valid_output;
    assign info_to_exec.ir_funct6 = instr_in.ir_funct12[11:06];
    assign info_to_exec.ir_funct3 = instr_in.ir_funct3;
    assign info_to_exec.ticket    = instr_in.ticket;
    assign info_to_exec.dst       = dst;
    assign info_to_exec.head_uop  = start_new_instr;
    assign info_to_exec.end_uop   = expansion_finished;
    assign info_to_exec.is_rdc    = instr_is_rdc;
    // We indicate the remaining VL here, so that the info can be used in EX
    assign info_to_exec.vl        = start_new_instr ? instr_in.vl : total_remaining_elements;

    assign mask_src = instr_in.mask_src + current_exp_loop;

    // Create the src/dst identifiers
    always_comb begin
        if (instr_is_rdc) begin
            dst   = instr_in.dst;
            src_1 = instr_in.src1;
            src_2 = instr_in.src2 + current_exp_loop;
        end else begin
            dst   = instr_in.dst  + current_exp_loop;
            src_1 = instr_in.src1 + current_exp_loop;
            src_2 = instr_in.src2 + current_exp_loop;
        end
    end

    // Struct containing Data
    assign instr_is_rdc = (instr_in.ir_funct3 == funct3_opmvv_c) && (
                           instr_in.microop == opcode_vector_c ) && (
                           instr_in.ir_funct12[11:06] == funct6_vredsum_c  ||
                           instr_in.ir_funct12[11:06] == funct6_vredand_c  ||
                           instr_in.ir_funct12[11:06] == funct6_vredor_c   ||
                           instr_in.ir_funct12[11:06] == funct6_vredxor_c  ||
                           instr_in.ir_funct12[11:06] == funct6_vredminu_c ||
                           instr_in.ir_funct12[11:06] == funct6_vredmin_c  ||
                           instr_in.ir_funct12[11:06] == funct6_vredmaxu_c ||
                           instr_in.ir_funct12[11:06] == funct6_vredmax_c);

    assign is_operand_imm = instr_in.ir_funct3 == funct3_opivi_c;

    assign is_operand_scalar = (instr_in.ir_funct3 == funct3_opivx_c) || 
                               (instr_in.ir_funct3 == funct3_opfvx_c) ||
                               (instr_in.ir_funct3 == funct3_opmvx_c);
    //
    generate for (genvar k = 0; k < VECTOR_LANES; k++) begin : g_data_selection
        assign data_to_exec[k].valid     = valid_output[k];
        // DATA 1 Selection
        assign data_to_exec[k].data1  = is_operand_imm    ? {{27{instr_in.immediate[4]}}, instr_in.immediate} :
                                        is_operand_scalar ? instr_in.data1                                    :
                                        instr_is_rdc      ? data_1[0]                                         :
                                                            ({32{frw_a_src_1[k]}}     & frw_a_data[k]) |
                                                            ({32{frw_b_src_1[k]}}     & frw_b_data[k]) |
                                                            ({32{frw_c_src_1[k]}}     & wr_data[k])    |
                                                            ({32{~pending[src_1][k]}} & data_1[k]);
        // DATA 2 Selection
        assign data_to_exec[k].data2 = ({32{frw_a_src_2[k]}}     & frw_a_data[k]) |
                                       ({32{frw_b_src_2[k]}}     & frw_b_data[k]) |
                                       ({32{frw_c_src_2[k]}}     & wr_data[k])    |
                                       ({32{~pending[src_2][k]}} & data_2[k]);
        // Reductions mask all the elements for all the uops, except element#0 for the last uop
        assign data_to_exec[k].mask  = (instr_is_rdc & expansion_finished) ? (k == 0) : // only element#0 of last uop will writeback a result
                                       (instr_is_rdc)                      ?  1'b0    : // no middle uop will write a result
                                       (instr_in.use_mask == 2'b10)        ? mask[k]  : // Use v1’s elements lsb as the mask
                                       (instr_in.use_mask == 2'b11)        ? ~mask[k] : // Use ~v1’s elements lsb as the mask
                                                                               1'b1;    // No masking (== assume masking is 0xFFFF…FFFF)
    end endgenerate

    // Forwarding Logic
    generate for (genvar j = 0; j < VECTOR_LANES; j++) begin : g_frw_en
        //Forward Point #1
        assign frw_a_src_1[j] = frw_a_en[j] & (frw_a_addr === src_1) & (frw_a_ticket === pending_ticket[src_1]);
        assign frw_a_src_2[j] = frw_a_en[j] & (frw_a_addr === src_2) & (frw_a_ticket === pending_ticket[src_2]);
        //Forward Point #2
        assign frw_b_src_1[j] = frw_b_en[j] & (frw_b_addr === src_1) & (frw_b_ticket === pending_ticket[src_1]);
        assign frw_b_src_2[j] = frw_b_en[j] & (frw_b_addr === src_2) & (frw_b_ticket === pending_ticket[src_2]);
        //Forward Point #3 (Writeback)
        assign frw_c_src_1[j] = wr_en[j] & (wr_addr === src_1) & (wr_ticket === pending_ticket[src_1]);
        assign frw_c_src_2[j] = wr_en[j] & (wr_addr === src_2) & (wr_ticket === pending_ticket[src_2]);
    end endgenerate

    //Issue Logic -> non-Memory Instructions
    assign can_issue    = &issue_masked;
    assign issue_masked = no_hazards | ~vl_therm;
    generate for (genvar p = 0; p < VECTOR_LANES; p++) begin: g_iss_logic
        //src1
        assign src1_ok[p] = (instr_in.src1_iszero)                             |
                            (frw_a_src_1[p] | frw_b_src_1[p] | frw_c_src_1[p]) |
                            (~pending[src_1][p]);
        //src2
        assign src2_ok[p] = (instr_in.src2_iszero)                             |
                            (frw_a_src_2[p] | frw_b_src_2[p] | frw_c_src_2[p]) |
                            (~pending[src_2][p]);
        //dst
        assign rdst_ok[p]    = ~locked[dst][p];
        assign no_hazards[p] = src1_ok[p] & src2_ok[p] & rdst_ok[p];
    end endgenerate

    //Issue Logic -> Memory Instructions
    assign can_issue_m    = &issue_m_masked;
    assign issue_m_masked = no_hazards_m | ~vl_therm;

    generate for (genvar l = 0; l < VECTOR_LANES; l++) begin: g_iss_logic_mem
        assign can_lock_sources[l]     = instr_in.lock[0] ? ~(locked[src_1][l] | locked[src_2][l]) : 1'b1;
        assign can_lock_destination[l] = instr_in.lock[1] ? ~locked[dst][l] : 1'b1;
        assign no_hazards_m[l]         = can_lock_sources[l] & can_lock_destination[l];
    end endgenerate

    //Convert to OH
    logic [VECTOR_LANES-1:0][VECTOR_REGISTERS-1:0] wr_addr_oh, mem_wr_addr_oh;
    logic [VECTOR_REGISTERS-1:0] dst_oh, src1_oh, src2_oh, unlock_reg_a_oh, unlock_reg_b_oh;

    assign dst_oh          = (1 << dst);
    assign src1_oh         = (1 << src_1);
    assign src2_oh         = (1 << src_2);
    assign unlock_reg_a_oh = (1 << unlock_reg_a);
    assign unlock_reg_b_oh = (1 << unlock_reg_b);

    generate for (genvar m = 0; m < VECTOR_LANES; m++) begin: g_oh_pntrs
        assign wr_addr_oh[m]     = (1 << wr_addr);
        assign mem_wr_addr_oh[m] = (1 << mem_wr_addr);
    end endgenerate

    //Pending status per elem/vreg
    logic ticket_match_pending    ;
    logic mem_ticket_match_pending;

    assign mem_ticket_match_pending = (mem_wr_ticket === pending_ticket[mem_wr_addr]);
    assign ticket_match_pending     = (wr_ticket     === pending_ticket[wr_addr]);

    always_ff @(posedge clk_i or negedge rstn_i) begin: StatusPending
        if(!rstn_i) begin
            pending <= '0;
        end else begin
            if(do_reconfigure) begin
                pending <= '0;
            end else if (!instr_in.reconfigure) begin
                for (int k = 0; k < VECTOR_LANES; k++) begin
                    for (int i = 0; i < VECTOR_REGISTERS; i++) begin
                        if(dst_oh[i] && vl_therm[k] && do_issue && !instr_in.dst_iszero) begin
                            pending[i][k]     <= 1;
                            pending_ticket[i] <= instr_in.ticket;
                        end else if(dst_oh[i] && ~vl_therm[k] && do_issue && !instr_in.dst_iszero) begin
                            pending[i][k]     <= 0;
                        end else if(wr_en[k] && wr_addr_oh[k][i] && ticket_match_pending) begin
                            pending[i][k]     <= 0;
                        end else if (mem_wr_en[k] && mem_wr_addr_oh[k][i] && mem_ticket_match_pending) begin
                            pending[i][k]     <= 0;
                        end
                    end
                end
            end
        end
    end

    //Locked status per elem/vreg
    logic ticket_a_match_locked;
    logic ticket_b_match_locked;
    assign ticket_a_match_locked = (unlock_ticket === locked_ticket[unlock_reg_a]);
    assign ticket_b_match_locked = (unlock_ticket === locked_ticket[unlock_reg_b]);

    always_ff @(posedge clk_i or negedge rstn_i) begin: StatusLocked
        if(!rstn_i) begin
            locked <= '0;
        end else begin
            for (int k = 0; k < VECTOR_LANES; k++) begin
                for (int i = 0; i < VECTOR_REGISTERS; i++) begin
                    if(do_issue && vl_therm[k] && dst_oh[i] && instr_in.lock[1] && !instr_in.dst_iszero) begin
                        locked[i][k]     <= 1;
                        locked_ticket[i] <= instr_in.ticket;
                    end else if(do_issue && vl_therm[k] && src1_oh[i] && instr_in.lock[0] && !instr_in.src1_iszero) begin 
                        locked[i][k]     <= 1;                                                                            
                        locked_ticket[i] <= instr_in.ticket;
                    end else if(do_issue && vl_therm[k] && src2_oh[i] && instr_in.lock[0] && !instr_in.src2_iszero) begin // virtual lock on src2
                        locked[i][k]     <= 1;                                                                            // for constraint purpose
                        locked_ticket[i] <= instr_in.ticket;                                           
                    end else if (unlock_en && ((ticket_a_match_locked && unlock_reg_a_oh[i]) || (ticket_b_match_locked && unlock_reg_b_oh[i]))) begin
                        locked[i][k] <= 0;
                    end
                end
            end
        end
    end

    assign mem_pending_0 = pending[mem_addr_0][0];
    assign mem_ticket_0  = pending_ticket[mem_addr_0];
    assign mem_pending_1 = pending[mem_addr_1][0];
    assign mem_ticket_1  = pending_ticket[mem_addr_1];
    assign mem_pending_2 = pending[mem_addr_2][0];
    assign mem_ticket_2  = pending_ticket[mem_addr_2];

    generate
        for (genvar i = 0; i < 4; i++) begin
            assign mem_prb_locked_o[i] = locked[mem_prb_reg_i[i]][0];
            assign mem_prb_ticket_o[i] = locked_ticket[mem_prb_reg_i[i]];
        end
    endgenerate

    // Mask the writebacks
    logic [VECTOR_LANES-1:0] wr_en_masked;
    always_comb begin : WBmask
        for (int i = 0; i < VECTOR_LANES; i++) begin
            wr_en_masked[i] = instr_is_rdc ? (rdc_done[i] & wr_en[i] & ~locked[wr_addr][i]) : (wr_en[i] & ~locked[wr_addr][i]);
        end
    end

    // Vector Register File
    vrf #(
        .VREGS     (VECTOR_REGISTERS),
        .ELEMENTS  (VECTOR_LANES    ),
        .DATA_WIDTH(DATA_WIDTH      )
    ) vrf (
        .clk_i       (clk_i         ),
        .reset       (do_reconfigure), // state resetted during reconfiguration
        //Read Ports
        .rd_addr_1   (src_1       ),
        .data_out_1  (data_1      ),
        .rd_addr_2   (src_2       ),
        .data_out_2  (data_2      ),
        .mask_src    (mask_src    ),
        .mask        (mask        ),
        //Element Write Ports (per element enabled)
        .el_wr_en    (wr_en_masked),
        .el_wr_addr  (wr_addr     ),
        .el_wr_data  (wr_data     ),
        //Register Read Port
        .v_rd_addr_0 (mem_addr_0  ),
        .v_data_out_0(mem_data_0  ),
        .v_rd_addr_1 (mem_addr_1  ),
        .v_data_out_1(mem_data_1  ),
        .v_rd_addr_2 (mem_addr_2  ),
        .v_data_out_2(mem_data_2  ),
        //Register Write Port (per element enabled)
        .v_wr_en     (mem_wr_en   ),
        .v_wr_addr   (mem_wr_addr ),
        .v_wr_data   (mem_wr_data )
    );

    assign is_idle_o = ~valid_in & ~|pending & ~|locked;

endmodule