// ##################################################################################################
// # << CELLRV32 - Custom Functions Subsystem (CFS) >>                                              #
// # ********************************************************************************************** #
// # Intended for tightly-coupled, application-specific custom co-processors. This module provides  #
// # 64x 32-bit memory-mapped interface registers, one interrupt request signal and custom IO       #
// # conduits for processor-external or chip-external interface.                                    #
// #                                                                                                #
// # NOTE: This is just an example/illustration template. Modify/replace this file to implement     #
// #       your own custom design logic.                                                            #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cfs #(
    parameter logic[31:0] CFS_CONFIG = 32'h00000000, // custom CFS configuration generic
    parameter int CFS_IN_SIZE    = 32,  // size of CFS input conduit in bits
    parameter int CFS_OUT_SIZE   = 32,  // size of CFS output conduit in bits
    parameter int io_size_c      = 512, // IO address space size in bytes, fixed!
    parameter int cfs_size_c     = 64*4 // module's address space in bytes
)(
    /* host access */
    input  logic                    clk_i,       // global clock line
    input  logic                    rstn_i,      // global reset line, low-active, use as async
    input  logic                    priv_i,      // current CPU privilege mode
    input  logic [31:0]             addr_i,      // address
    input  logic                    rden_i,      // read enable
    input  logic                    wren_i,      // word write enable
    input  logic [31:0]             data_i,      // data in
    output logic [31:0]             data_o,      // data out
    output logic                    ack_o,       // transfer acknowledge
    output logic                    err_o,       // transfer error
    /* clock generator */
    output logic                    clkgen_en_o, // enable clock generator
    input  logic [7:0]              clkgen_i,    // "clock" inputs
    // interrupt //
    output logic                    irq_o,       // interrupt request
    /* custom io (conduits) */
    input  logic [CFS_IN_SIZE-1:0]  cfs_in_i,    // custom inputs
    output logic [CFS_OUT_SIZE-1:0] cfs_out_o    // custom outputs
);
    // IO space: module base address --
    // WARNING: Do not modify the CFS base address or the CFS' occupied address
    // space as this might cause access collisions with other processor modules.
    localparam int hi_abb_c = $clog2(io_size_c) - 1; // high address boundary bit
    localparam int lo_abb_c = $clog2(cfs_size_c); // low address boundary bit

    /* access control */
    logic acc_en; // module access enable
    logic [31:0] addr; // access address
    logic wren; // word write access
    logic rden; // read enable
    
    /* default CFS interface registers */
    typedef logic [31:0] cfs_regs_t [0:3]; // just implement 4 registers for this example
    cfs_regs_t cfs_reg_wr; // interface registers for WRITE accesses
    cfs_regs_t cfs_reg_rd; // interface registers for READ accesses
    
    // Access Control ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // This logic is required to handle the CPU accesses - DO NOT MODIFY!
    assign acc_en = (addr_i[hi_abb_c : lo_abb_c] == cfs_base_c[hi_abb_c : lo_abb_c]) ?
                    1'b1 : 1'b0;
    // word aligned
    assign addr = {cfs_base_c[31 : lo_abb_c], addr_i[lo_abb_c-1 : 2], 2'b00}; 
    // only full-word write accesses are supported
    assign wren = acc_en & wren_i;
    // read accesses always return a full 32-bit word
    assign rden = acc_en & rden_i;
    
    // CFS Generics ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // In it's default version the CFS provides three configuration generics:
    // > CFS_IN_SIZE  - configures the size (in bits) of the CFS input conduit cfs_in_i
    // > CFS_OUT_SIZE - configures the size (in bits) of the CFS output conduit cfs_out_o
    // > CFS_CONFIG   - is a blank 32-bit generic. It is intended as a "generic conduit" to propagate
    //                  custom configuration flags from the top entity down to this module.
    
    // CFS IOs --------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // By default, the CFS provides two IO signals (cfs_in_i and cfs_out_o) that are available at the processor's top entity.
    // These are intended as "conduits" to propagate custom signals from this module and the processor top entity.

    assign cfs_out_o = '0; // not used for this minimal example

    // Reset System ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // The CFS can be reset using the global rstn_i signal. This signal should be used as asynchronous reset and is active-low.
    // Note that rstn_i can be asserted by a processor-external reset, the on-chip debugger and also by the watchdog.
    //
    // Most default peripheral devices of the CELLRV32 do NOT use a dedicated hardware reset at all. Instead, these units are
    // reset by writing ZERO to a specific "control register" located right at the beginning of the device's address space
    // (so this register is cleared at first). The crt0 start-up code writes ZERO to every single address in the processor's
    // IO space - including the CFS. Make sure that this initial clearing does not cause any unintended CFS actions.


    // Clock System ---------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // The processor top unit implements a clock generator providing 8 "derived clocks".
    // Actually, these signals should not be used as direct clock signals, but as *clock enable* signals.
    // clkgen_i is always synchronous to the main system clock (clk_i).
    //
    // The following clock dividers are available:
    // > clkgen_i(clk_div2_c)    -> MAIN_CLK/2
    // > clkgen_i(clk_div4_c)    -> MAIN_CLK/4
    // > clkgen_i(clk_div8_c)    -> MAIN_CLK/8
    // > clkgen_i(clk_div64_c)   -> MAIN_CLK/64
    // > clkgen_i(clk_div128_c)  -> MAIN_CLK/128
    // > clkgen_i(clk_div1024_c) -> MAIN_CLK/1024
    // > clkgen_i(clk_div2048_c) -> MAIN_CLK/2048
    // > clkgen_i(clk_div4096_c) -> MAIN_CLK/4096
    //
    // For instance, if you want to drive a clock process at MAIN_CLK/8 clock speed you can use the following construct:
    //
    //   if (rstn_i = '0') then -- async and low-active reset (if required at all)
    //   ...
    //   elsif rising_edge(clk_i) then -- always use the main clock for all clock processes
    //     if (clkgen_i(clk_div8_c) = '1') then -- the div8 "clock" is actually a clock enable
    //       ...
    //     end if;
    //   end if;
    //
    // The clkgen_i input clocks are available when at least one IO/peripheral device (for example UART0) requires the clocks
    // generated by the clock generator. The CFS can enable the clock generator by itself by setting the clkgen_en_o signal high.
    // The CFS cannot ensure to deactivate the clock generator by setting the clkgen_en_o signal low as other peripherals might
    // still keep the generator activated. Make sure to deactivate the CFS's clkgen_en_o if no clocks are required in here to
    // reduce dynamic power consumption.

    assign clkgen_en_o = 1'b0; // not used for this minimal example


    // Interrupt ------------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // The CFS features a single interrupt signal, which is connected to the CPU's "fast interrupt" channel 1 (FIRQ1).
    // The interrupt is triggered by a one-cycle high-level. After triggering, the interrupt appears as "pending" in the CPU's
    // mip CSR ready to trigger execution of the according interrupt handler. It is the task of the application to programmer
    // to enable/clear the CFS interrupt using the CPU's mie and mip registers when required.

    assign irq_o = 1'b0; // not used for this minimal example

    // Read/Write Access ----------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    // Here we are reading/writing from/to the interface registers of the module and generate the CPU access handshake (bus response).
    //
    // The CFS provides up to 64 memory-mapped 32-bit interface registers. For instance, these could be used to provide a
    // <control register> for global control of the unit, a <data register> for reading/writing from/to a data FIFO, a
    // <command register> for issuing commands and a <status register> for status information.
    //
    // Following the interface protocol, each read or write access has to be acknowledged in the following cycle using the ack_o
    // signal (or even later if the module needs additional time). If no ACK is generated at all, the bus access will time out
    // and cause a bus access fault exception. The current CPU privilege level is available via the 'priv_i' signal (0 = user mode,
    // 1 = machine mode), which can be used to constrain access to certain registers or features to privileged software only.
    //
    // This module also provides an optional ERROR signal to indicate a faulty access operation (for example when accessing an
    // unused, read-only or "locked" CFS register address). This signal may only be set when the module is actually accessed
    // and is set INSTEAD of the ACK signal. Setting the ERR signal will raise a bus access exception with a "Device Error" qualifier
    // that can be handled by the application software. Note that the current privilege level should not be exposed to software to
    // maintain full virtualization. Hence, CFS-based "privilege escalation" should trigger a bus access exception (e.g. by setting 'err_o').

    assign err_o = 1'b0; // Tie to zero if not explicitly used.

    // Host access example: Read and write access to the interface registers + bus transfer acknowledge. This example only
    // implements four physical r/w register (the four lowest CFS registers). The remaining addresses of the CFS are not associated
    // with any physical registers - any access to those is simply ignored but still acknowledged. Only full-word write accesses are
    // supported (and acknowledged) by this example. Sub-word write access will not alter any CFS register state and will cause
    // a "bus store access" exception (with a "Device Timeout" qualifier as not ACK is generated in that case).
    
    always_ff @( posedge clk_i or negedge rstn_i ) begin : host_access
        if (rstn_i == 1'b0) begin
            cfs_reg_wr[0] <= '0;
            cfs_reg_wr[1] <= '0;
            cfs_reg_wr[2] <= '0;
            cfs_reg_wr[3] <= '0;
            //
            ack_o  <= 1'b0;
            data_o <= '0;
        end else begin
            // synchronous interface for read and write accesses
            // transfer/access acknowledge
            // default: required for the CPU to check the CFS is answering a bus read OR write request;
            // all read and write accesses (to any cfs_reg, even if there is no according physical register implemented) will succeed.
            ack_o <= rden | wren;
      
            /* write access */
            if (wren) begin // full-word write access, high for one cycle if there is an actual write access
                if (addr == cfs_reg0_addr_c) begin // make sure to use the internal "addr" signal for the read/write interface
                    cfs_reg_wr[0] <= data_i; // some physical register, for example: control register
                end
                if (addr == cfs_reg1_addr_c) begin 
                    cfs_reg_wr[1] <= data_i; // some physical register, for example: data in/out fifo
                end
                if (addr == cfs_reg2_addr_c) begin 
                    cfs_reg_wr[2] <= data_i; // some physical register, for example: command fifo
                end 
                if (addr == cfs_reg3_addr_c) begin 
                    cfs_reg_wr[3] <= data_i; // some physical register, for example: status register
                end
            end

            /* read access */
            data_o <= '0; // the output HAS TO BE ZERO if there is no actual read access
            if (rden) begin // the read access is always 32-bit wide, high for one cycle if there is an actual read access
                // make sure to use the internal 'addr' signal for the read/write interface
                case (addr)
                    cfs_reg0_addr_c : data_o <= cfs_reg_rd[0];
                    cfs_reg1_addr_c : data_o <= cfs_reg_rd[1];
                    cfs_reg2_addr_c : data_o <= cfs_reg_rd[2];
                    cfs_reg3_addr_c : data_o <= cfs_reg_rd[3];
                    default: begin
                        data_o <= '0;
                    end
                endcase
            end
        end
    end : host_access

    // CFS Function Core -------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------

    // This is where the actual functionality can be implemented.
    // The logic below is just a very simple example that transforms data
    // from an input register into data in an output register.

    assign cfs_reg_rd[0] = bin_to_gray_f(cfs_reg_wr[0]); // convert binary to gray code
    assign cfs_reg_rd[1] = gray_to_bin_f(cfs_reg_wr[1]); // convert gray to binary code
    assign cfs_reg_rd[2] = bit_rev_f(cfs_reg_wr[2]);     // bit reversal
    assign cfs_reg_rd[3] = bswap32_f(cfs_reg_wr[3]);     // byte swap (endianness conversion)

endmodule