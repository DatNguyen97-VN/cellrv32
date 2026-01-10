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
    parameter int DATA_WIDTH         = 32
) (
    input  logic                                                                       clk_i          ,
    input  logic                                                                       rstn_i         ,
    output logic                                                                       is_idle_o      ,
    output logic                                                                       exec_finished_o,
    //Instruction In
    input  logic                                                                       valid_in       ,
    input  remapped_v_instr                                                            instr_in       ,
    output logic                                                                       ready_o        ,
    //Instruction Out
    output logic                                                                       valid_o        ,
    output to_vector_exec [            VECTOR_LANES-1:0]                               data_to_exec   ,
    output to_vector_exec_info                                                         info_to_exec   ,
    input  logic                                                                       ready_i        ,
    //Memory Unit read ports
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_addr_0     ,
    output logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_data_0     ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_addr_1     ,
    output logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_data_1     ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_addr_2     ,
    output logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_data_2     ,
    //Memory Unit write port
    input  logic          [            VECTOR_LANES-1:0]                               mem_wr_en      ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               mem_wr_addr    ,
    input  logic          [ VECTOR_LANES*DATA_WIDTH-1:0]                               mem_wr_data    ,
    //Unlock ports
    input  logic                                                                       unlock_en      ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               unlock_reg_a   ,
    //Writeback
    input  logic          [            VECTOR_LANES-1:0]                               wr_en          ,
    input  logic          [$clog2(VECTOR_REGISTERS)-1:0]                               wr_addr        ,
    input  logic          [            VECTOR_LANES-1:0][              DATA_WIDTH-1:0] wr_data        ,
    input  logic          [            VECTOR_LANES-1:0]                               rdc_done        
);

    localparam int TOTAL_ELEMENT_ADDR_WIDTH = $clog2(VECTOR_REGISTERS*VECTOR_LANES);
    localparam int ELEMENT_ADDR_WIDTH       = $clog2(VECTOR_LANES)                 ;
    localparam int VREG_ADDR_WIDTH          = $clog2(VECTOR_REGISTERS)             ;
    //=======================================================
    //Internal Status tracking
    //=======================================================
    logic [VECTOR_REGISTERS-1:0][VECTOR_LANES-1:0] pending, locked;
    logic [    VECTOR_LANES-1:0] vl_therm;
    logic [ VREG_ADDR_WIDTH-1:0] current_exp_loop  ; // Count the number of µops issued
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
    logic [VREG_ADDR_WIDTH-1:0] src_1, src_2, dst;
    logic [  VREG_ADDR_WIDTH:0] max_expansion;
    logic [   VECTOR_LANES-1:0] valid_output;

    // Check if instr is memory operation
    assign memory_instr = (instr_in.microop == opcode_vload_c) || (instr_in.microop == opcode_vstore_c) ? valid_in : 1'b0;

    assign start_new_instr = do_issue & ~|current_exp_loop;

    // Do reconfiguration
    assign do_reconfigure  = instr_in.reconfigure & exec_finished_o;
    assign exec_finished_o = instr_is_rdc ? rdc_done[0] : ~(|pending) & ~(|locked);

    //Check if instr expansion finished
    assign total_remaining_elements = instr_in.vl - (current_exp_loop*VECTOR_LANES); // number of unprocessed vector elements
    assign expansion_finished       = maxvl_reached | vl_reached;
    assign maxvl_reached            = (current_exp_loop === (max_expansion-1)); // Check if we are on the last µop according to the hardware configuration
    assign vl_reached               = (((current_exp_loop+1) << $clog2(VECTOR_LANES)) >= instr_in.vl); // Check if after the next µop we have covered the entire VL.

    //Check if the EX is ready to accept (only those that you need to send to)
    assign output_ready = ready_i; // Execution stage (vEX) is ready to receive new data
    assign vl_therm     = ~('1 << total_remaining_elements); // a vector with 1 bits corresponding to the lane to be processed in the current µop

    // memory inst: Inst is valid and no hazard
    // non-memory inst: Instr is valid, EX is available, and no hazard.
    assign do_issue     = memory_instr ? (valid_in) : (valid_in & output_ready);
    assign pop          = valid_in & ready_o; // instrcution is completed
    assign valid_output = (do_issue & ~memory_instr & ~instr_in.reconfigure) ? vl_therm : '0; // mask lane, disable output if memory/reconfiguration instruction 


    assign ready_o = instr_in.reconfigure ?  exec_finished_o                    : // all pending/locked clear
                     memory_instr         ? (expansion_finished)                : // run out of µops memory
                     valid_in             ? (expansion_finished & output_ready) : 1'b0; // run out of µops compute and EX ready

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
    assign info_to_exec.frm       = instr_in.frm;
    assign info_to_exec.vfunary   = instr_in.vfunary;
    assign info_to_exec.dst       = dst;
    assign info_to_exec.head_uop  = start_new_instr;
    assign info_to_exec.end_uop   = expansion_finished;
    assign info_to_exec.is_rdc    = instr_is_rdc;
    // We indicate the remaining VL here, so that the info can be used in EX
    assign info_to_exec.vl        = start_new_instr ? instr_in.vl : total_remaining_elements;

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
    generate
        for (genvar k = 0; k < VECTOR_LANES; k++) begin : g_data_selection
            assign data_to_exec[k].valid     = valid_output[k];
            // DATA 1 Selection
            assign data_to_exec[k].data1  = is_operand_imm    ? {{27{instr_in.immediate[4]}}, instr_in.immediate} :
                                            is_operand_scalar ? instr_in.data1                                    :
                                            instr_is_rdc      ? data_1[0]                                         :
                                                                ({32{~pending[src_1][k]}} & data_1[k]);
            // DATA 2 Selection
            assign data_to_exec[k].data2 = ({32{~pending[src_2][k]}} & data_2[k]);
            // Reductions mask all the elements for all the uops, except element#0 for the last uop
            assign data_to_exec[k].mask  = (instr_is_rdc & expansion_finished) ? (k == 0) : // only element#0 of last uop will writeback a result
                                           (instr_is_rdc)                      ?  1'b0    : // no middle uop will write a result
                                                                                  1'b1;    // No masking (== assume masking is 0xFFFF…FFFF)
        end : g_data_selection
    endgenerate

    //Convert to OH
    logic [VECTOR_LANES-1:0][VECTOR_REGISTERS-1:0] wr_addr_oh, mem_wr_addr_oh;
    logic [VECTOR_REGISTERS-1:0] dst_oh, src1_oh, src2_oh, unlock_reg_a_oh;

    assign dst_oh          = (1 << dst);
    assign src1_oh         = (1 << src_1);
    assign src2_oh         = (1 << src_2);
    assign unlock_reg_a_oh = (1 << unlock_reg_a);

    generate
        for (genvar m = 0; m < VECTOR_LANES; m++) begin : g_oh_pntrs
            assign wr_addr_oh[m]     = (1 << wr_addr);
            assign mem_wr_addr_oh[m] = (1 << mem_wr_addr);
        end : g_oh_pntrs
    endgenerate

    always_ff @(posedge clk_i or negedge rstn_i) begin : StatusPending
        if(!rstn_i) begin
            pending <= '0;
        end else begin
            if(do_reconfigure) begin
                pending <= '0;
            end else if (!instr_in.reconfigure) begin
                for (int k = 0; k < VECTOR_LANES; k++) begin
                    for (int i = 0; i < VECTOR_REGISTERS; i++) begin
                        if(dst_oh[i] && vl_therm[k] && do_issue && !instr_in.dst_iszero) begin
                            pending[i][k] <= 1;
                        end else if(dst_oh[i] && ~vl_therm[k] && do_issue && !instr_in.dst_iszero) begin
                            pending[i][k] <= 0;
                        end else if(wr_en[k] && wr_addr_oh[k][i]) begin
                            pending[i][k] <= 0;
                        end else if (mem_wr_en[k] && mem_wr_addr_oh[k][i]) begin
                            pending[i][k] <= 0;
                        end
                    end
                end
            end
        end
    end : StatusPending

    // Locked status per elem/vreg
    always_ff @(posedge clk_i or negedge rstn_i) begin : StatusLocked
        if(!rstn_i) begin
            locked <= '0;
        end else begin
            for (int k = 0; k < VECTOR_LANES; k++) begin
                for (int i = 0; i < VECTOR_REGISTERS; i++) begin
                    if(do_issue && vl_therm[k] && dst_oh[i] && instr_in.lock) begin
                        locked[i][k] <= 1;
                    end else if (unlock_en && unlock_reg_a_oh[i]) begin
                        locked[i][k] <= 0;
                    end
                end
            end
        end
    end : StatusLocked

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