// #################################################################################################
// # << CELLRV32 - CPU Co-Processor: Custom (Instructions) Functions Unit >>                        #
// # ********************************************************************************************* #
// # For user-defined custom RISC-V instructions (R3-type, R4-type and R5-type formats).           #
// # See the CPU's documentation for more information.                                             #
// #                                                                                               #
// # NOTE: Take a look at the "software-counterpart" of this CFU example in 'sw/example/demo_cfu'. #
// # ********************************************************************************************* #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  `include "cellrv32_package.svh"
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_cfu #(
    parameter XLEN = 32 // data path width
) (
    /* global control */
    input  logic            clk_i,   // global clock, rising edge
    input  logic            rstn_i,  // global reset, low-active, async
    input  ctrl_bus_t       ctrl_i,  // main control bus
    input  logic            start_i, // trigger operation
    /* data input */
    input  logic [XLEN-1:0] rs1_i,   // rf source 1
    input  logic [XLEN-1:0] rs2_i,   // rf source 2
    input  logic [XLEN-1:0] rs3_i,   // rf source 3
    input  logic [XLEN-1:0] rs4_i,   // rf source 4
    /* result and status */
    output logic [XLEN-1:0] res_o,   // operation result
    output logic            valid_o  // data output valid
);
    
    // CFU controll - do not modify! ------------------------------
    // ------------------------------------------------------------
    typedef struct {
        logic busy; // CFU is busy  
        logic done; // set to '1' when processing is done
        logic [XLEN-1:0] result; // user's processing result (for write-back to register file)
        logic [1:0] rtype;  // instruction type, see constants below  
        logic [2:0] funct3; // "funct3" bit-field from custom instruction 
        logic [6:0] funct7; // funct7" bit-field from custom instruction 
    } control_t;
    control_t control;

    /* instruction format types */
    const logic[1:0] r3type_c  = 2'b00; // R3-type instructions (custom-0 opcode)
    const logic[1:0] r4type_c  = 2'b01; // R4-type instructions (custom-1 opcode)
    const logic[1:0] r5typeA_c = 2'b10; // R5-type instruction A (custom-2 opcode)
    const logic[1:0] r5typeB_c = 2'b11; // R5-type instruction B (custom-3 opcode)
    
    // User Logic -------------------------------------------------
    // ------------------------------------------------------------
    /* multiply-add unit (r4-type instruction example) */
    typedef struct {
        logic [2:0] sreg; // 3 cycles latency = 3 bits in arbitration shift register
        //
        logic done;
        logic [2*XLEN-1:0] opa; 
        logic [2*XLEN-1:0] opb; 
        logic [2*XLEN-1:0] opc; 
        logic [2*XLEN-1:0] mul; 
        logic [2*XLEN-1:0] res; 
    } madd_t;
    madd_t madd;

    // ****************************************************************************************************************************
    // This controller is required to handle the CPU/pipeline interface. Do not modify!
    // ****************************************************************************************************************************
    // CFU Controller ----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : cfu_control
        if (rstn_i == 1'b0) begin
            res_o        <= '0;
            control.busy <= 1'b0;
        end else begin
            res_o <= '0; // default; all CPU co-processor outputs are logically OR-ed
            if (control.busy == 1'b0) begin // idle
                if (start_i == 1'b1) begin
                    control.busy <= 1'b1;
                end
            end else begin // busy
                // processing done? abort if trap (exception)
                if ((control.done == 1'b1) || (ctrl_i.cpu_trap == 1'b1)) begin
                    res_o        <= control.result; // output result for just one cycle, CFU output has to be all-zero otherwise
                    control.busy <= 1'b0;
                end
            end
        end
    end : cfu_control
    
    /* CPU feedback */
    assign valid_o = control.busy & control.done; // set one cycle before result data
    
    /* pack user-defined instruction type/function bits */
    assign control.rtype  = ctrl_i.ir_opcode[6:5];
    assign control.funct3 = ctrl_i.ir_funct3;
    assign control.funct7 = ctrl_i.ir_funct12[11:5];

    // ****************************************************************************************************************************
    // CFU Hardware Documentation and Implementation Notes
    // ****************************************************************************************************************************

    // ----------------------------------------------------------------------------------------
    // CFU Instruction Formats
    // ----------------------------------------------------------------------------------------
    // The CFU supports three instruction types:
    //
    // Up to 1024 RISC-V R3-Type Instructions (RISC-V standard):
    // This format consists of two source registers ('rs1', 'rs2'), a destination register ('rd') and two "immediate" bit-fields
    // ('funct7' and 'funct3').
    //
    // Up to 8 RISC-V R4-Type Instructions (RISC-V standard):
    // This format consists of three source registers ('rs1', 'rs2', 'rs3'), a destination register ('rd') and one "immediate"
    // bit-field ('funct7').
    //
    // Two individual RISC-V R5-Type Instructions (CELLRV32-specific):
    // This format consists of four source registers ('rs1', 'rs2', 'rs3', 'rs4') and a destination register ('rd'). There are
    // no immediate fields.


    // ----------------------------------------------------------------------------------------
    // Input Operands
    // ----------------------------------------------------------------------------------------
    // > rs1_i          (input, 32-bit): source register 1; selected by 'rs1' bit-field
    // > rs2_i          (input, 32-bit): source register 2; selected by 'rs2' bit-field
    // > rs3_i          (input, 32-bit): source register 3; selected by 'rs3' bit-field
    // > rs4_i          (input, 32-bit): source register 4; selected by 'rs4' bit-field
    // > control.rtype  (input,  2-bit): defining the R-type; driven by OPCODE
    // > control.funct3 (input,  3-bit): 3-bit function select / immediate value; driven by instruction word's 'funct3' bit-field
    // > control.funct7 (input,  7-bit): 7-bit function select / immediate value; driven by instruction word's 'funct7' bit-field
    //
    // [NOTE] The set of usable signals depends on the actual R-type of the instruction.
    //
    // The general instruction type is identified by the <control.rtype>.
    // > r3type_c  - R3-type instructions (custom-0 opcode)
    // > r4type_c  - R4-type instructions (custom-1 opcode)
    // > r5typeA_c - R5-type instruction A (custom-2 opcode)
    // > r5typeB_c - R5-type instruction B (custom-3 opcode)
    //
    // The four signals <rs1_i>, <rs2_i>, <rs3_i> and <rs4_i> provide the source operand data read from the CPU's register file.
    // The source registers are adressed by the custom instruction word's 'rs1', 'rs2', 'rs3' and 'rs4' bit-fields.
    //
    // The actual CFU operation can be defined by using the <control.funct3> and/or <control.funct7> signals (if available for a
    // certain R-type instruction). Both signals are directly driven by the according bit-fields of the custom instruction word.
    // These immediates can be used to select the actual function or to provide small literals for certain operations (like shift
    // amounts, offsets, multiplication factors, ...).
    //
    // [NOTE] <rs1_i>, <rs2_i>, <rs3_i> and <rs4_i> are directly driven by the register file (e.g. block RAM). For complex CFU
    //        designs it is recommended to buffer these signals using CFU-internal registers before actually using them.
    //
    // [NOTE] The R4-type instructions and R5-type instruction provide additional source register. When used, this will increase
    //        the hardware requirements of the register file.
    //
    // [NOTE] The CFU cannot cause any kind of exception at all (yet; this feature is planned for the future).


    // ----------------------------------------------------------------------------------------
    // Result Output
    // ----------------------------------------------------------------------------------------
    // > control.result (output, 32-bit): processing result ("data")
    //
    // When the CFU has completed computations, the data send via the <control.result> signal will be written to the CPU's register
    // file. The destination register is addressed by the <rd> bit-field in the instruction word. The CFU result output is registered
    // in the CFU controller (see above) - so do not worry too much about increasing the CPU's critical path with your custom
    // logic.


    // ----------------------------------------------------------------------------------------
    // Processing Control
    // ----------------------------------------------------------------------------------------
    // > rstn_i       (input,  1-bit): asynchronous reset, low-active
    // > clk_i        (input,  1-bit): main clock, triggering on rising edge
    // > start_i      (input,  1-bit): operation trigger (start processing, high for one cycle)
    // > control.done (output, 1-bit): set high when processing is done
    //
    // For pure-combinatorial instructions (completing within 1 clock cycle) <control.done> can be tied to 1. If the CFU requires
    // several clock cycles for internal processing, the <start_i> signal can be used to *start* a new iterative operation. As soon
    // as all internal computations have completed, the <control.done> signal has to be set to indicate completion. This will
    // complete CFU instruction operation and will also write the processing result <control.result> back to the CPU register file.
    //
    // [NOTE] If the <control.done> signal is not set within a bound time window (default = 128 cycles) the CFU operation is
    //        automatically terminated by the hardware and an illegal instruction exception is raised. This feature can also be
    //        be used to implement custom CFU exceptions.


    // ----------------------------------------------------------------------------------------
    // Final Notes
    // ----------------------------------------------------------------------------------------
    // The <control> record provides something like a "keeper" that ensures correct functionality and that also provides a
    // simple-to-use interface hardware designers can start with. However, the control instance adds one additional cycle of
    // latency. Advanced users can remove this default control instance to obtain maximum throughput.
    
    // ****************************************************************************************************************************
    // Actual CFU User Logic Example - replace this with your custom logic
    // ****************************************************************************************************************************

    // Iterative Multiply-Add Unit - Iteration Control ----------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i or negedge rstn_i ) begin : madd_control
        if (rstn_i == 1'b0) begin
            madd.sreg <= '0;
        end else begin
            /* operation trigger */
            if ((control.busy == 1'b0) && // CFU is idle (ready for next operation)
                (start_i == 1'b1) && // CFU is actually triggered by a custom instruction word
                (control.rtype == r4type_c) && // this is a R4-type instruction
                control.funct3[2:1] == 2'b00) begin // trigger only for specific funct3 values
                madd.sreg[0] <= 1'b1;
            end else begin
                madd.sreg[0] <= 1'b0;
            end
            /* simple shift register for tracking operation */
            madd.sreg[$bits(madd.sreg)-1:1] <= madd.sreg[$bits(madd.sreg)-2:0]; // shift left
        end
    end : madd_control

     /* processing has reached last stage (=done) when sreg's MSB is set */
     assign madd.done = madd.sreg[$bits(madd.sreg)-1];

    // Iterative Multiply-Add Unit - Arithmetic Core ---------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_ff @( posedge clk_i ) begin : madd_core
      /* stage 0: buffer input operands */
      madd.opa <= rs1_i;
      madd.opb <= rs2_i;
      madd.opc <= rs3_i;
      /* stage 1: multiply rs1 and rs2 */
      madd.mul <= madd.opa * madd.opb;
      /* stage 2: add rs3 to multiplication result */
      madd.res <= madd.mul + madd.opc;
    end : madd_core

    // Output select -----------------------------------------------------------------------------
    // -------------------------------------------------------------------------------------------
    always_comb begin : out_select
        unique case (control.rtype)
            // ----------------------------------------------------------
            // R3-type instructions
            // ----------------------------------------------------------
            r3type_c : begin
                // This is a simple ALU that implements four pure-combinatorial instructions.
                // The actual function is selected by the "funct3" bit-field of the custom instruction.
                case (control.funct3)
                    3'b000 : begin // funct3 = "000": bit-reversal of rs1
                        control.result = bit_rev_f(rs1_i);
                        control.done   = 1'b1; // pure-combinatorial, so we are done "immediately"
                    end
                    3'b001 : begin // funct3 = "001": XNOR input operands
                        control.result = rs1_i ~^ rs2_i;
                        control.done   = 1'b1; // pure-combinatorial, so we are done "immediately"
                    end
                    default: begin // not implemented
                        control.result = '0;
                        control.done   = 1'b0; // this will cause an illegal instruction exception after timeout
                    end
                endcase
            end
            // ----------------------------------------------------------
            // R4-type instructions
            // ----------------------------------------------------------
            r4type_c : begin
                // This is an iterative multiply-and-add unit that requires several cycles for processing.
                // The actual function is selected by the lowest bit of the "funct3" bit-field.
                case (control.funct3)
                    3'b000 : begin // funct3 = "000": multiply-add low-part result: rs1*rs2+r3 [31:0]
                        control.result = madd.res[31:0];
                        control.done   = madd.done; // iterative, wait for unit to finish
                    end
                    3'b001 : begin // funct3 = "001": multiply-add high-part result: rs1*rs2+r3 [63:32]
                        control.result = madd.res[63:32];
                        control.done   = madd.done; // iterative, wait for unit to finish
                    end
                    default: begin // not implemented
                        control.result = '0;
                        control.done   = 1'b0; // this will cause an illegal instruction exception after timeout
                    end
                endcase
            end
            // ----------------------------------------------------------
            // R5-type instruction A
            // ----------------------------------------------------------
            r5typeA_c : begin
                // No function/immediate bit-fields are available for this instruction type.
                // Hence, there is just one operation that can be implemented.
                control.result = rs1_i & rs2_i & rs3_i & rs4_i; // AND-all
                control.done   = 1'b1; // pure-combinatorial, so we are done "immediately"
            end
            // ----------------------------------------------------------
            // R5-type instruction B
            // ----------------------------------------------------------
            r5typeB_c : begin
                // No function/immediate bit-fields are available for this instruction type.
                // Hence, there is just one operation that can be implemented.
                control.result = rs1_i ^ rs2_i ^ rs3_i ^ rs4_i; // XOR-all
                control.done   = 1'b1; // set high to prevent permanent CPU stall
            end
            default: begin // undefined
                control.result = '0;
                control.done   = 1'b0;
            end
        endcase
    end : out_select
endmodule