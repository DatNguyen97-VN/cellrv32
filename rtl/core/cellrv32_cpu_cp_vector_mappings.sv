// ##################################################################################################
// # << CELLRV32 - Vector Register Remmaping >>                                                     #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module vrrm #(
    parameter int VECTOR_REGISTERS   = 32,
    parameter int VECTOR_LANES       = 8 ,
    parameter int VECTOR_TICKET_BITS = 4
) (
    input  logic                   clk_i        ,
    input  logic                   rstn_i      ,
    output logic                   is_idle_o  ,
    //Instruction In
    input  logic                   valid_in   ,
    input  to_vector               instr_in   ,
    output logic                   pop_instr  ,
    //Instruction Out
    output logic                   valid_o    ,
    output remapped_v_instr        instr_out  ,
    input  logic                   ready_i    ,
    //Memory Instruction Out
    output logic                   m_valid_o  ,
    output memory_remapped_v_instr m_instr_out,
    input  logic                   m_ready_i
);

    localparam int ELEM_ADDR_WIDTH = $clog2(VECTOR_LANES*32);
    localparam int REGISTER_BITS   = $clog2(VECTOR_REGISTERS);

    logic [  VECTOR_REGISTERS-1:0][VECTOR_TICKET_BITS-1:0] last_producer      ;
    logic [     REGISTER_BITS-1:0]                         next_free_vreg     ;
    logic [     REGISTER_BITS-1:0]                         rdst_destination   ;
    logic [       REGISTER_BITS:0]                         vreg_hop           ;
    logic [     REGISTER_BITS-1:0]                         remapped_src1      ;
    logic [     REGISTER_BITS-1:0]                         remapped_src2      ;
    logic [VECTOR_TICKET_BITS-1:0]                         next_ticket        ;
    logic                                                  do_operation       ;
    logic                                                  do_remap           ;
    logic                                                  rdst_remapped      ;
    logic                                                  store_instr        ;
    logic                                                  do_reconfigure     ;
    logic                                                  load_instr         ;
    logic                                                  last_producer_wr_en;

    //Check for special types of instructions
    assign store_instr  = instr_in.microop[instr_opcode_msb_c : instr_opcode_msb_c-2] == 3'b010; // store instr
    assign load_instr   = instr_in.microop[instr_opcode_msb_c : instr_opcode_msb_c-2] == 3'b000; // load instr
    //Push Pop Signals
    assign valid_o      = valid_in & do_operation;
    assign do_operation = (store_instr || load_instr) ? (valid_in & ready_i & m_ready_i) : (valid_in & ready_i);
    assign pop_instr    = do_operation;
    assign m_valid_o    = valid_in & (store_instr || load_instr) & do_operation;

    assign do_reconfigure = instr_in.reconfigure;

    // Instr Out Generation
    assign instr_out.vl          = instr_in.vl;
    assign instr_out.maxvl       = instr_in.maxvl;
    assign instr_out.valid       = instr_in.valid;
    assign instr_out.use_mask    = instr_in.use_mask;
    assign instr_out.ir_funct12  = instr_in.ir_funct12;
    assign instr_out.ir_funct3   = instr_in.ir_funct3;
    assign instr_out.frm         = instr_in.frm;
    assign instr_out.vfunary     = instr_in.src1;
    assign instr_out.microop     = instr_in.microop;
    assign instr_out.ticket      = next_ticket;
    assign instr_out.data1       = instr_in.data1;
    assign instr_out.data2       = instr_in.data2;
    assign instr_out.immediate   = instr_in.immediate;
    assign instr_out.src1_iszero = 1'b0;
    assign instr_out.src2_iszero = 1'b0;
    assign instr_out.dst_iszero  = store_instr & (~load_instr); // store instructions reconfig
                                                                                               // do not write anything
    assign instr_out.reconfigure = instr_in.reconfigure;
    // Pick the correct destination vreg
    assign instr_out.dst         = rdst_remapped ? rdst_destination :
                                   do_remap      ? next_free_vreg   :
                                                   instr_in.dst;

    // Pick the correct source vregs
    assign instr_out.src1 = (instr_in.src1 === instr_in.dst) ? instr_out.dst : remapped_src1;
    assign instr_out.src2 = (instr_in.src2 === instr_in.dst) ? instr_out.dst : remapped_src2;
    //Assign Locking Bits based on Instruction Type
    assign instr_out.lock = (!instr_in.reconfigure && load_instr ) ? 2'b11 :
                            (!instr_in.reconfigure && store_instr) ? 2'b01 :
                                                                     2'b00;
	//Memory Instr Out Generation
    assign m_instr_out.valid            = instr_out.valid;
    assign m_instr_out.dst              = instr_out.dst;
    assign m_instr_out.src1             = instr_out.src1;
    assign m_instr_out.src2             = instr_out.src2;
    assign m_instr_out.data1            = instr_out.data1;
    assign m_instr_out.data2            = instr_out.data2;
    assign m_instr_out.ticket           = instr_out.ticket;
    assign m_instr_out.ir_funct12       = instr_out.ir_funct12;
    assign m_instr_out.microop          = instr_in.microop;
    assign m_instr_out.reconfigure      = instr_in.reconfigure;
    assign m_instr_out.vl               = instr_in.vl;
    assign m_instr_out.maxvl            = instr_in.maxvl;
    assign m_instr_out.last_ticket_src1 = (last_producer[instr_in.src1] === 0) ? instr_out.ticket : last_producer[instr_in.src1];
    assign m_instr_out.last_ticket_src2 = (last_producer[instr_in.src2] === 0) ? instr_out.ticket : last_producer[instr_in.src2];

    // Do remap enablers
    assign do_remap = do_operation & ~rdst_remapped;
    always_ff @(posedge clk_i or negedge rstn_i) begin : vregHOP
        if(!rstn_i) begin
            vreg_hop <= 1;
        end else begin
            vreg_hop <= (instr_in.maxvl >> $clog2(VECTOR_LANES));
        end
    end

	// Next Free vreg (similar job as the FL)
    always_ff @(posedge clk_i or negedge rstn_i) begin : FreeVreg
        if(!rstn_i) begin
            next_free_vreg <= '0;
        end else begin
        	if (do_reconfigure) begin
        		next_free_vreg <= '0;
            end else if(do_remap) begin
                next_free_vreg <= next_free_vreg + vreg_hop;
            end
        end
    end

    // Next Free Ticket
    always_ff @(posedge clk_i or negedge rstn_i) begin : NextTicket
        if(!rstn_i) begin
            next_ticket <= 1;
        end else begin
            if(do_reconfigure) begin
                next_ticket <= 1;
            end else if(do_operation) begin
                next_ticket <= &next_ticket ? 1 : next_ticket + 1;
            end
        end
    end

    //RAT module - Keeps current Mappings
    vrat #(
        .TOTAL_ENTRIES(VECTOR_REGISTERS),
        .DATA_WIDTH   (REGISTER_BITS   )
    ) vrat (
        .clk_i      (clk_i             ),
        .rstn_i     (rstn_i            ),
        .reconfigure(do_reconfigure    ),
        //Write Port
        .write_addr (instr_in.dst      ),
        .write_data (next_free_vreg    ),
        .write_en   (do_remap          ),
        //Read Port #1
        .read_addr_1(instr_in.dst      ),
        .read_data_1(rdst_destination  ),
        .remapped_1 (rdst_remapped     ),
        //Read Port #2
        .read_addr_2(instr_in.src1     ),
        .read_data_2(remapped_src1     ),
        .remapped_2 (                  ),
        //Read Port #3
        .read_addr_3(instr_in.src2     ),
        .read_data_3(remapped_src2     ),
        .remapped_3 (                  ),
        //Mask Port (always v1)
        .mask_src   (instr_out.mask_src)
    );

    // Last producer Tracker (used for mem ops, stores do not udpate it)
    assign last_producer_wr_en = do_operation & (~(store_instr | load_instr) | load_instr);
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if(!rstn_i) begin
            last_producer <= '0;
        end else if(last_producer_wr_en) begin
            last_producer[instr_in.dst] <= next_ticket;
        end
    end

    assign is_idle_o = ~valid_in;

endmodule