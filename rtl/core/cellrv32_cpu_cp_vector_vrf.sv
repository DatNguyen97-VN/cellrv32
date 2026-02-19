// ##################################################################################################
// # << CELLRV32 - Vector Register File >>                                                          #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS 
 
module vrf #(
    parameter int VREGS      = 32,
    parameter int ELEMENTS   = 4 ,
    parameter int DATA_WIDTH = 32
) (
    input  logic                                           clk_i     ,
    input  logic                                           reset     ,
    // Element Read Ports
    input  logic [      $clog2(VREGS)-1:0]                 rd_addr_1 ,
    output logic [           ELEMENTS-1:0][DATA_WIDTH-1:0] data_out_1,
    input  logic [      $clog2(VREGS)-1:0]                 rd_addr_2 ,
    output logic [           ELEMENTS-1:0][DATA_WIDTH-1:0] data_out_2,
    // Register Write Port
    input  logic [           ELEMENTS-1:0]                 v_wr_en   ,
    input  logic [      $clog2(VREGS)-1:0]                 v_wr_addr ,
    input  logic [ELEMENTS*DATA_WIDTH-1:0]                 v_wr_data
);

`ifndef _QUARTUS_IGNORE_INCLUDES
    // Internal Signals
    logic [ELEMENTS*DATA_WIDTH-1:0] memory [VREGS-1:0];
	 logic [4:0] add_r;
	assign add_r = |v_wr_en ? v_wr_addr : rd_addr_1;
	
    // Store new Data
    always_ff @(posedge clk_i) begin : memManage
        if (|v_wr_en) begin
            memory[add_r] <= v_wr_data;
        end
		// Read Data
		if (~|v_wr_en) begin
			data_out_1 <= memory[add_r];
		end
        data_out_2 <= memory[rd_addr_2];
    end : memManage
`else // _QUARTUS_IGNORE_INCLUDES
    logic [4:0] add_r;
	assign add_r = |v_wr_en ? v_wr_addr : rd_addr_1;

	// component altsyncram
	altsyncram	altsyncram_component (
				.address_a      (add_r      ),
				.address_b      (rd_addr_2  ),
				.clock0         (clk_i      ),
				.data_a         (v_wr_data  ),
				.data_b         ({256{1'b0}}),
				.wren_a         (|v_wr_en   ),
				.wren_b         (1'b0       ),
				.q_a            (data_out_1 ),
				.q_b            (data_out_2 ),
				.aclr0          (1'b0       ),
				.aclr1          (1'b0       ),
				.addressstall_a (1'b0       ),
				.addressstall_b (1'b0       ),
				.byteena_a      (1'b1       ),
				.byteena_b      (1'b1       ),
				.clock1         (1'b1       ),
				.clocken0       (1'b1       ),
				.clocken1       (1'b1       ),
				.clocken2       (1'b1       ),
				.clocken3       (1'b1       ),
				.eccstatus      (           ),
				.rden_a         (~|v_wr_en  ),
				.rden_b         (1'b1       )
	);
	defparam
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.indata_reg_b = "CLOCK0",
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 32,
		altsyncram_component.numwords_b = 32,
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M9K",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_WITH_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_WITH_NBE_READ",
		altsyncram_component.widthad_a = 5,
		altsyncram_component.widthad_b = 5,
		altsyncram_component.width_a = 256,
		altsyncram_component.width_b = 256,
		altsyncram_component.width_byteena_a = 1,
		altsyncram_component.width_byteena_b = 1,
		altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0";
`endif // _QUARTUS_IGNORE_INCLUDES

endmodule