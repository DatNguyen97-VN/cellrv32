// ##################################################################################################
// # << cellTRNG V2 - A Tiny and Platform-Independent True Random Number Generator for any FPGA >>  #
// # ********************************************************************************************** #
// # neoTRNG Entropy Cell                                                                           #
// #                                                                                                #
// # The cell consists of two ring-oscillators build from inverter chains. The short chain uses     #
// # NUM_INV_S inverters and oscillates at a "high" frequency and the long chain uses NUM_INV_L     #
// # inverters and oscillates at a "low" frequency. The select_i input selects which chain is       #
// # used as data output (data_o).                                                                  #
// #                                                                                                #
// # Each inverter chain is constructed as an "asynchronous" shift register. The single inverters   #
// # are connected via latches that are used to enable/disable the TRNG. Also, these latches are    #
// # used as additional delay element. By using unique enable signals for each latch, the           #
// # synthesis tool cannot "optimize" (=remove) any of the inverters out of the design making the   #
// # design platform-agnostic.                                                                      #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellTRNG_cell #(
    parameter int NUM_INV_S = 0,    // number of inverters in short path
    parameter int NUM_INV_L = 0    // number of inverters in long path
) (
    input  logic clk_i,    // system clock
    input  logic rstn_i,   // global reset line, low-active, async, optional
    input  logic select_i, // delay select
    input  logic enable_i, // enable chain input
    output logic enable_o, // enable chain output
    output logic data_o    // random data
);
   logic [NUM_INV_S-1:0] inv_chain_s;   // short oscillator chain
   logic [NUM_INV_L-1:0] inv_chain_l;   // long oscillator chain
   logic                 feedback;      // cell feedback/output
   logic [NUM_INV_S-1:0] enable_sreg_s; // enable shift register for short chain
   logic [NUM_INV_L-1:0] enable_sreg_l; // enable shift register for long chain
   logic [15:0]          lfsr;          // LFSR - for simulation only!!!

   // Ring Oscillator ---------------------------------------------------------------------------
   // -------------------------------------------------------------------------------------------
   // Each cell provides a short inverter chain (high frequency) and a long oscillator chain (low frequency).
   // The select_i signals defines which chain is used as cell output.
   // NOTE: All signals that control a inverter-latch element have to be registered to ensure a single element
   // is mapped to a single LUT (or LUT + FF(latch-mode)).

   `ifndef IS_SIM // REAL HARDWARE
      /* short oscillator chain */
      always_comb begin : ring_osc_short
         // inverters in short chain
         for (int i = 0; i < NUM_INV_S; ++i) begin
            if (i == NUM_INV_S-1) begin // start with a defined state (latch reset), left-most inverter?
               inv_chain_s[i] = (enable_i && enable_sreg_s[i]) ? ~feedback : 1'b0;
            end else begin
               inv_chain_s[i] = (enable_i && enable_sreg_s[i]) ? ~inv_chain_s[i+1] : 1'b0;
            end
         end
      end : ring_osc_short

      /* long oscillator chain */
      always_comb begin : ring_osc_long
         // inverters in long chain
         for (int j = 0; j < NUM_INV_L; ++j) begin
            if (j == NUM_INV_L-1) begin // start with a defined state (latch reset), left-most inverter?
               inv_chain_l[j] = (enable_i && enable_sreg_l[j]) ? ~feedback : 1'b0;
            end else begin
               inv_chain_l[j] = (enable_i && enable_sreg_l[j]) ? ~inv_chain_l[j+1] : 1'b0;
            end
         end
      end : ring_osc_long

      /* final ROSC output */
      assign feedback = (select_i == 1'b1) ? inv_chain_l[0] : inv_chain_s[0];
      assign data_o   = feedback;
   `else
      // Fake(!) Pseudo-RNG ------------------------------------------------------------------------
      // -------------------------------------------------------------------------------------------
      /* For simulation/debugging only! */
      // notify
      initial begin
          assert (1'b0) else 
          $warning("neoTRNG WARNING: Implementing simulation-only PRNG (LFSR)!");
      end
      //
      always_ff @( posedge clk_i or negedge rstn_i ) begin : sim_lfsr
          if (rstn_i == 1'b0) begin
              lfsr <= '0;
          end else begin
              if (enable_sreg_l[$bits(enable_sreg_l)-1] == 1'b0)
                lfsr <= NUM_INV_S;
              else
                lfsr <= {lfsr[$bits(lfsr)-2 : 0], (lfsr[15] ~^ lfsr[14] ~^ lfsr[13] ~^ lfsr[2])};
          end
      end : sim_lfsr
      //
      assign feedback = lfsr[$bits(lfsr)-1];
      assign data_o   = feedback;
   `endif 

   // Control -----------------------------------------------------------------------------------
   // -------------------------------------------------------------------------------------------
   // Using individual enable signals for each inverter from a shift register to prevent the synthesis tool
   // from removing all but one inverter (since they implement "logical identical functions" (='toggle')).
   // This makes the TRNG platform independent (since we do not need to use primitives to ensure a correct architecture).
   always_ff @( posedge clk_i or negedge rstn_i ) begin : ctrl_unit
     if (rstn_i == 1'b0) begin
        enable_sreg_s <= '0;
        enable_sreg_l <= '0;
     end else begin
        enable_sreg_s <= {enable_sreg_s[$bits(enable_sreg_s)-2 : 0], enable_i};
        enable_sreg_l <= {enable_sreg_l[$bits(enable_sreg_l)-2 : 0], enable_sreg_s[$bits(enable_sreg_s)-1]};
     end
   end : ctrl_unit

   /* output for "enable chain" */
   assign enable_o = enable_sreg_l[$bits(enable_sreg_l)-1];
endmodule