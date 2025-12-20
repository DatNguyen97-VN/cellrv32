// ##################################################################################################
// # << CELLRV32 - CPU Co-Processor: Vector (CPU Base ISA) >>                                       #
// # ********************************************************************************************** #
// # VECTOR_FP_ALU = false (default) : Enable floating-point lanes                                  #
// # VECTOR_FXP_ALU = false (default) : Enable fixed-point lanes                                    #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_vector #(
	parameter int VECTOR_REGISTERS   = 32,  // Number of architectural vector registers
    parameter int VECTOR_LANES       = 8,   // Number of SIMD lanes (width of vector datapath)
    parameter int VECTOR_ACTIVE_LN   = 4,   // Number of lanes actively used (for masking/active-lanes)
    parameter int DATA_WIDTH         = 32,  // Width of each lane element in bits
    parameter int ADDR_WIDTH         = 32,  // Address width used by memory ops
    parameter int MEM_MICROOP_WIDTH  = 7,   // Width of micro-op encoding for memory ops
    parameter int MICROOP_WIDTH      = 5,   // Generic micro-op width (execution encoding)
    parameter int VECTOR_TICKET_BITS = 4,   // Bits for in-flight ticket IDs (dependency tracking)
    parameter int VECTOR_REQ_WIDTH   = 256, // Width (bits) of request payload to cache
    parameter int FWD_POINT_A        = 1,   // Forwarding point A (index / stage identifier)
    parameter int FWD_POINT_B        = 3,   // Forwarding point B (index / stage identifier)
    parameter int VECTOR_FP_ALU      = 1,   // Enable floating-point lanes
    parameter int VECTOR_FXP_ALU     = 0    // Enable fixed-point lanes
) (
	input  logic           clk_i,           // System clock
	input  logic           rstn_i,          // Active-low asynchronous reset
	output logic           vector_idle_o,   // Indicates the entire vector unit is idle
	// Instruction In
	input  logic           valid_in,        // Indicates a valid vector instruction is available
	output logic           pop,             // Acknowledges instruction consumption from upstream queue
    input  ctrl_bus_t      ctrl_i,          // main control bus
    /* RF Data Inputs */
    input  logic [DATA_WIDTH-1:0] rs1_i,    // RF source 1
    input  logic [DATA_WIDTH-1:0] rs2_i,    // RF source 2
	// Cache Request Interface
	output logic           mem_req_valid_o, // Memory request valid signal to cache/memory subsystem
	output vector_mem_req  mem_req_o,       // Memory request payload
	input  logic           cache_ready_i,   // Indicates cache/memory interface is ready to accept requests
	// Cache Response Interface
	input  logic           mem_resp_valid_i,// Indicates a valid memory response
	input  vector_mem_resp mem_resp_i,      // Memory response payload from cache/memory
	// Result and Status
	output logic		   valid_o          // Indicates a valid vector instruction has completed execution
);

    // Idle stage
	logic vrrm_idle;
	logic vis_idle;
	logic vex_idle;
	logic vmu_idle;
	logic finished;

	assign vector_idle_o = vrrm_idle & vis_idle & vex_idle & vmu_idle & rstn_i;
	//////////////////////////////////////////////////
	//                 vRRM STAGE                   //
	//////////////////////////////////////////////////
    to_vector               instr_in;
	memory_remapped_v_instr m_instr_out;
	remapped_v_instr        instr_remapped;
	logic                   r_valid;
	logic                   m_valid;
	logic                   ready;
	logic                   m_ready_r;

    /* controller */
    enum logic[1:0] { S_IDLE, S_PUSH, S_BUSY, S_DONE } state;

    // Co-Processor Controller -------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : coprocessor_ctrl
        if (!rstn_i) begin
            instr_in <= '0;
        end else begin
			//
            case (state)
                S_IDLE: begin
                    if (valid_in) begin
                        // convert vector control bus + RF data inputs to vector pipeline
                        instr_in.valid       <= valid_in;
                        instr_in.dst         <= ctrl_i.rf_rd;
                        instr_in.src1        <= ctrl_i.rf_rs1;
                        instr_in.src2        <= ctrl_i.rf_rs2;
						instr_in.immediate   <= ctrl_i.rf_rs1;
                        instr_in.data1       <= rs1_i;
                        instr_in.data2       <= rs2_i;
                        instr_in.ir_funct12  <= ctrl_i.ir_funct12;
						instr_in.ir_funct3   <= ctrl_i.ir_funct3;
                        instr_in.microop     <= ctrl_i.ir_opcode;
                        instr_in.use_mask    <= 2'b00;
                        // next state
                        state                <= S_PUSH;
                    end
					// auto reconfigure
                    instr_in.maxvl       <= ctrl_i.alu_vlmax;
                    instr_in.vl          <= ctrl_i.alu_vl;
					instr_in.reconfigure <= ctrl_i.alu_reconfig;
					//
					valid_o <= 1'b0;
                end
				// data into pipeline
                S_PUSH: begin
					instr_in.valid <= 1'b0;
					//
                    if (!vis_idle) begin
                        state <= S_BUSY;
                    end
                end
				// wait for completion
				S_BUSY: begin
					if (finished) begin
						state <= S_DONE;
					end
				end
                S_DONE: begin
					valid_o <= 1'b1;
                    state   <= S_IDLE;
                end
                default: begin // undefined
                    state <= S_IDLE;
                end
            endcase
        end
    end

	vrrm #(
		.VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
		.VECTOR_LANES      (VECTOR_LANES      ),
		.VECTOR_TICKET_BITS(VECTOR_TICKET_BITS)
	) vrrm (
		.clk_i      (clk_i         ),
		.rstn_i     (rstn_i        ),
		.is_idle_o  (vrrm_idle     ), // Idle stage
		//Instruction in
		.valid_in   (instr_in.valid), // Valid handshake between stages
		.instr_in   (instr_in      ), // Original decoded instruction
		.pop_instr  (pop           ), // Pop handshake
		//Instruction out
		.valid_o    (r_valid       ), // Valid handshake between stages
		.instr_out  (instr_remapped), // Instruction with physical register mapping applied
		.ready_i    (ready         ), // Ready handshake
		//Memory Instruction Out
		.m_valid_o  (m_valid       ), // Valid handshake between stages
		.m_instr_out(m_instr_out   ), // Memory instruction after remapping
		.m_ready_i  (m_ready_r     )  // Ready handshake
	);

	// ================================================
	//           vRR/vIS PIPELINE REGISTER          
	// ================================================
	remapped_v_instr        instr_remapped_o;
	logic                   r_valid_o;
	logic                   i_ready;
	memory_remapped_v_instr m_instr_out_r;
	logic                   m_valid_r;
	logic                   m_r_ready;

	cellrv32_fifo #(
         .FIFO_DEPTH (1),                     // number of fifo entries; has to be a power of two; min 1
         .FIFO_WIDTH ($bits(instr_remapped)), // size of data elements in fifo
         .FIFO_RSYNC (0),                     // we NEED to read data asynchronously
         .FIFO_SAFE  (0),                     // no safe access required (ensured by FIFO-external control)
         .FIFO_GATE  (0)                      // no output gate required
     ) vRR_vIS_buffer_inst (
         /* control */
         .clk_i   (clk_i),                    // clock, rising edge
         .rstn_i  (rstn_i),                   // async reset, low-active
         .clear_i (1'b0),                     // sync reset, high-active
         .half_o  (    ),                     // at least half full
         /* write port */
         .wdata_i (instr_remapped),           // write data: Remapped instruction input to vIS stage
         .we_i    (r_valid),                  // write enable
         .free_o  (ready),                    // at least one entry is free when set, Valid handshake between REGISER and ISSUE Stages
         /* read port */
         .re_i    (i_ready),                  // read enable
         .rdata_o (instr_remapped_o),         // read data: Remapped instruction output to vIS stage
         .avail_o (r_valid_o)                 // data available when set, Valid handshake between REGISER and ISSUE Stages
     );

	//////////////////////////////////////////////////
	//           vRR/vMU PIPELINE REGISTER          //
	//////////////////////////////////////////////////
	cellrv32_fifo #(
         .FIFO_DEPTH (1),                  // number of fifo entries; has to be a power of two; min 1
         .FIFO_WIDTH ($bits(m_instr_out)), // size of data elements in fifo
         .FIFO_RSYNC (0),                  // we NEED to read data asynchronously
         .FIFO_SAFE  (0),                  // no safe access required (ensured by FIFO-external control)
         .FIFO_GATE  (0)                   // no output gate required
     ) vRR_vMU_buffer_inst (
         /* control */
         .clk_i   (clk_i),                 // clock, rising edge
         .rstn_i  (rstn_i),                // async reset, low-active
         .clear_i (1'b0),                  // sync reset, high-active
         .half_o  (    ),                  // at least half full
         /* write port */
         .wdata_i (m_instr_out),           // write data: Remapped instruction input to vMU stage
         .we_i    (m_valid),               // write enable
         .free_o  (m_ready_r),             // at least one entry is free when set, Valid handshake between REGISER and MEMORY Stages
         /* read port */
         .re_i    (m_r_ready),             // read enable
         .rdata_o (m_instr_out_r),         // read data: Remapped instruction output to vMU stage
         .avail_o (m_valid_r)              // data available when set, Valid handshake between REGISER and MEMORY Stages
     ); 

	//////////////////////////////////////////////////
	//                 MEMORY UNIT                  //
	//////////////////////////////////////////////////
	logic                                unlock_en        ;
	logic [$clog2(VECTOR_REGISTERS)-1:0] unlock_reg_a     ;
	logic [$clog2(VECTOR_REGISTERS)-1:0] unlock_reg_b     ;
	logic [      VECTOR_TICKET_BITS-1:0] unlock_ticket    ;
	logic [            VECTOR_LANES-1:0] mem_wrtbck_en    ;
	logic [$clog2(VECTOR_REGISTERS)-1:0] mem_wrtbck_reg   ;
	logic [ VECTOR_LANES*DATA_WIDTH-1:0] mem_wrtbck_data  ;
	logic [      VECTOR_TICKET_BITS-1:0] mem_wrtbck_ticket;
	logic [$clog2(VECTOR_REGISTERS)-1:0] mem_addr_0       ;
	logic [ VECTOR_LANES*DATA_WIDTH-1:0] mem_data_0       ;
	logic                                mem_pending_0    ;
	logic [      VECTOR_TICKET_BITS-1:0] mem_ticket_0     ;
	logic [$clog2(VECTOR_REGISTERS)-1:0] mem_addr_1       ;
	logic [ VECTOR_LANES*DATA_WIDTH-1:0] mem_data_1       ;
	logic                                mem_pending_1    ;
	logic [      VECTOR_TICKET_BITS-1:0] mem_ticket_1     ;
	logic [$clog2(VECTOR_REGISTERS)-1:0] mem_addr_2       ;
	logic [ VECTOR_LANES*DATA_WIDTH-1:0] mem_data_2       ;
	logic                                mem_pending_2    ;
	logic [      VECTOR_TICKET_BITS-1:0] mem_ticket_2     ;

	logic [3:0][$clog2(VECTOR_REGISTERS)-1:0] mem_prb_reg   ;
	logic [3:0]                               mem_prb_locked;
	logic [3:0][      VECTOR_TICKET_BITS-1:0] mem_prb_ticket;

	vmu #(
		.REQ_DATA_WIDTH    (VECTOR_REQ_WIDTH  ),
		.VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
		.VECTOR_LANES      (VECTOR_LANES      ),
		.DATA_WIDTH        (DATA_WIDTH        ),
		.ADDR_WIDTH        (ADDR_WIDTH        ),
		.MICROOP_WIDTH     (MEM_MICROOP_WIDTH ),
		.VECTOR_TICKET_BITS(VECTOR_TICKET_BITS)
	) vmu (
		.clk                (clk_i            ),
		.rst_n              (rstn_i           ),
		.vmu_idle_o         (vmu_idle         ),
		//Instruction Input Interface
		.valid_in           (m_valid_r        ),
		.instr_in           (m_instr_out_r    ),
		.ready_o            (m_r_ready        ),
		//Cache Interface (OUT)
		.mem_req_valid_o    (mem_req_valid_o  ),
		.mem_req_o          (mem_req_o        ),
		.cache_ready_i      (cache_ready_i    ),
		//Cache Interface (IN)
		.mem_resp_valid_i   (mem_resp_valid_i ),
		.mem_resp_i         (mem_resp_i       ),
		//RF Interface - Loads
		.rd_addr_0_o        (mem_addr_0       ),
		.rd_data_0_i        (mem_data_0       ),
		.rd_pending_0_i     (mem_pending_0    ),
		.rd_ticket_0_i      (mem_ticket_0     ),
		//RF Interface - Stores
		.rd_addr_1_o        (mem_addr_1       ),
		.rd_data_1_i        (mem_data_1       ),
		.rd_pending_1_i     (mem_pending_1    ),
		.rd_ticket_1_i      (mem_ticket_1     ),
		.rd_addr_2_o        (mem_addr_2       ),
		.rd_data_2_i        (mem_data_2       ),
		.rd_pending_2_i     (mem_pending_2    ),
		.rd_ticket_2_i      (mem_ticket_2     ),
		//RF Writeback Interface
		.wrtbck_en_o        (mem_wrtbck_en    ),
		.wrtbck_reg_o       (mem_wrtbck_reg   ),
		.wrtbck_data_o      (mem_wrtbck_data  ),
		.wrtbck_ticket_o    (mem_wrtbck_ticket),
		//RF Writeback Probing Interface
		.wrtbck_prb_reg_o   (mem_prb_reg      ),
		.wrtbck_prb_locked_i(mem_prb_locked   ),
		.wrtbck_prb_ticket_i(mem_prb_ticket   ),
		//Unlock Interface
		.unlock_en_o        (unlock_en        ),
		.unlock_reg_a_o     (unlock_reg_a     ),
		.unlock_reg_b_o     (unlock_reg_b     ),
		.unlock_ticket_o    (unlock_ticket    )
	);

	// ================================================
	//                 ISSUE STAGE                  
	// ================================================
	logic [            VECTOR_LANES-1:0]                 frw_a_en     ;
	logic [$clog2(VECTOR_REGISTERS)-1:0]                 frw_a_addr   ;
	logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] frw_a_data   ;
	logic [      VECTOR_TICKET_BITS-1:0]                 frw_a_ticket ;
	logic [            VECTOR_LANES-1:0]                 frw_b_en     ;
	logic [$clog2(VECTOR_REGISTERS)-1:0]                 frw_b_addr   ;
	logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] frw_b_data   ;
	logic [      VECTOR_TICKET_BITS-1:0]                 frw_b_ticket ;
	logic [            VECTOR_LANES-1:0]                 wrtbck_en    ;
	logic [$clog2(VECTOR_REGISTERS)-1:0]                 wrtbck_addr  ;
	logic [            VECTOR_LANES-1:0][DATA_WIDTH-1:0] wrtbck_data  ;
	logic [      VECTOR_TICKET_BITS-1:0]                 wrtbck_ticket;
	logic                                                iss_valid    ;
	logic                                                iss_ex_ready ;
	to_vector_exec                    [VECTOR_LANES-1:0] iss_to_exec_data;
	to_vector_exec_info                                  iss_to_exec_info;


	vis #(
		.VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
		.VECTOR_LANES      (VECTOR_LANES      ),
		.DATA_WIDTH        (DATA_WIDTH        ),
		.VECTOR_TICKET_BITS(VECTOR_TICKET_BITS)
	) vis (
		.clk_i            (clk_i           ),
		.rstn_i          (rstn_i           ),
		.is_idle_o       (vis_idle         ),
		.exec_finished_o (finished         ),
		//Instruction in
		.valid_in        (r_valid_o        ),
		.instr_in        (instr_remapped_o ),
		.ready_o         (i_ready          ),
		//Instruction out
		.valid_o         (iss_valid        ),
		.data_to_exec    (iss_to_exec_data ),
		.info_to_exec    (iss_to_exec_info ),
		.ready_i         (iss_ex_ready     ),
		//Memory Unit read port
		.mem_addr_0      (mem_addr_0       ),
		.mem_data_0      (mem_data_0       ),
		.mem_pending_0   (mem_pending_0    ),
		.mem_ticket_0    (mem_ticket_0     ),
		.mem_addr_1      (mem_addr_1       ),
		.mem_data_1      (mem_data_1       ),
		.mem_pending_1   (mem_pending_1    ),
		.mem_ticket_1    (mem_ticket_1     ),
		.mem_addr_2      (mem_addr_2       ),
		.mem_data_2      (mem_data_2       ),
		.mem_pending_2   (mem_pending_2    ),
		.mem_ticket_2    (mem_ticket_2     ),
		//Memory Unit Probing port
		.mem_prb_reg_i   (mem_prb_reg      ),
		.mem_prb_locked_o(mem_prb_locked   ),
		.mem_prb_ticket_o(mem_prb_ticket   ),
		//Memory Unit write port
		.mem_wr_en       (mem_wrtbck_en    ),
		.mem_wr_ticket   (mem_wrtbck_ticket),
		.mem_wr_addr     (mem_wrtbck_reg   ),
		.mem_wr_data     (mem_wrtbck_data  ),
		// Unlock Ports
		.unlock_en       (unlock_en        ),
		.unlock_reg_a    (unlock_reg_a     ),
		.unlock_reg_b    (unlock_reg_b     ),
		.unlock_ticket   (unlock_ticket    ),
		//Forward Point #1
		.frw_a_en        (frw_a_en         ),
		.frw_a_addr      (frw_a_addr       ),
		.frw_a_data      (frw_a_data       ),
		.frw_a_ticket    (frw_a_ticket     ),
		//Forward Point #2
		.frw_b_en        (frw_b_en         ),
		.frw_b_addr      (frw_b_addr       ),
		.frw_b_data      (frw_b_data       ),
		.frw_b_ticket    (frw_b_ticket     ),
		//Writeback (from EX)
		.wr_en           (wrtbck_en        ),
		.wr_addr         (wrtbck_addr      ),
		.wr_data         (wrtbck_data      ),
		.wr_ticket       (wrtbck_ticket    )
	);

	// ================================================
	//           vIS/vEX PIPELINE REGISTER          
	to_vector_exec [ VECTOR_LANES-1:0] exec_data_o;
	to_vector_exec_info                exec_info_o;
	logic exec_valid, exec_ready;

	cellrv32_fifo #(
         .FIFO_DEPTH (1),                       // number of fifo entries; has to be a power of two; min 1
         .FIFO_WIDTH ($bits(iss_to_exec_data)), // size of data elements in fifo
         .FIFO_RSYNC (0),                       // we NEED to read data asynchronously
         .FIFO_SAFE  (0),                       // no safe access required (ensured by FIFO-external control)
         .FIFO_GATE  (0)                        // no output gate required
	) vIS_vEX_data_buffer_inst (
         /* control */
         .clk_i   (clk_i),                      // clock, rising edge
         .rstn_i  (rstn_i),                     // async reset, low-active
         .clear_i (1'b0),                       // sync reset, high-active
         .half_o  (    ),                       // at least half full
         /* write port */
         .wdata_i (iss_to_exec_data),           // write data: Remapped instruction input to vEX stage
         .we_i    (iss_valid),                  // write enable
         .free_o  (iss_ex_ready),               // at least one entry is free when set, Valid handshake between vIS and vEX Stages
         /* read port */
         .re_i    (exec_ready),                 // read enable
         .rdata_o (exec_data_o),                // read data: Remapped instruction output to vEX stage
         .avail_o (exec_valid)                  // data available when set, Valid handshake between vIS and vEX Stages
     ); 
	
	cellrv32_fifo #(
         .FIFO_DEPTH (1),                       // number of fifo entries; has to be a power of two; min 1
         .FIFO_WIDTH ($bits(iss_to_exec_info)), // size of data elements in fifo
         .FIFO_RSYNC (0),                       // we NEED to read data asynchronously
         .FIFO_SAFE  (0),                       // no safe access required (ensured by FIFO-external control)
         .FIFO_GATE  (0)                        // no output gate required
	) vIS_vEX_info_buffer_inst (
         /* control */
         .clk_i   (clk_i),                      // clock, rising edge
         .rstn_i  (rstn_i),                     // async reset, low-active
         .clear_i (1'b0),                       // sync reset, high-active
         .half_o  (    ),                       // at least half full
         /* write port */
         .wdata_i (iss_to_exec_info),           // write data: Remapped instruction input to vEX stage
         .we_i    (iss_valid),                  // write enable
         .free_o  ( ),                          // at least one entry is free when set, Valid handshake between vIS and vEX Stages
         /* read port */
         .re_i    (exec_ready),                 // read enable
         .rdata_o (exec_info_o),                // read data: Remapped instruction output to vEX stage
         .avail_o ( )                           // data available when set, Valid handshake between vIS and vEX Stages
     ); 
	//////////////////////////////////////////////////
	//                   EX STAGE                   //
	//////////////////////////////////////////////////
	vex #(
		.VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
		.VECTOR_LANES      (VECTOR_LANES      ),
		.ADDR_WIDTH        (ADDR_WIDTH        ),
		.DATA_WIDTH        (DATA_WIDTH        ),
		.MICROOP_WIDTH     (MICROOP_WIDTH     ),
		.VECTOR_TICKET_BITS(VECTOR_TICKET_BITS),
		.FWD_POINT_A       (FWD_POINT_A       ),
		.FWD_POINT_B       (FWD_POINT_B       ),
		.VECTOR_FP_ALU     (VECTOR_FP_ALU     ),
		.VECTOR_FXP_ALU    (VECTOR_FXP_ALU    )
	) vex (
		.clk         (clk_i        ),
		.rst_n       (rstn_i       ),
		.vex_idle_o  (vex_idle     ),
		//Issue Interface
		.valid_i     (exec_valid   ),
		.exec_data_i (exec_data_o  ),
		.exec_info_i (exec_info_o  ),
		.ready_o     (exec_ready   ),
		//Forward Point #1
		.frw_a_en    (frw_a_en     ),
		.frw_a_addr  (frw_a_addr   ),
		.frw_a_data  (frw_a_data   ),
		.frw_a_ticket(frw_a_ticket ),
		//Forward Point #2
		.frw_b_en    (frw_b_en     ),
		.frw_b_addr  (frw_b_addr   ),
		.frw_b_data  (frw_b_data   ),
		.frw_b_ticket(frw_b_ticket ),
		//Writeback
		.wr_en       (wrtbck_en    ),
		.wr_addr     (wrtbck_addr  ),
		.wr_data     (wrtbck_data  ),
		.wr_ticket   (wrtbck_ticket)
	);

endmodule