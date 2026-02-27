// ######################################################################################################
// # << CELLRV32 - NPU Control Coordinator >>                                                           #
// # ************************************************************************************************** #
// # This component coordinates all control units.                                                      #
// # The control coordinator dispatches instructions to the appropriate control unit at the right time  #
// # and waits for each unit to be finished before feeding new instructions.                            #
// # ************************************************************************************************** #
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_control_coordinator (
    input  logic                clk_i                     ,
    input  logic                rstn_i                    ,
    input  logic                enable_i                  ,
    input  instruction_t        inst_i                    , // The instruction to be dispatched
    input  logic                inst_en_i                 , // enable for instruction
    output logic                busy_o                    , // One unit is still busy while a new instruction was feeded for this exact unit
    // Weight control unit interface
    input  logic                wei_busy_i                , // busy input for the weight control unit
    input  logic                wei_resource_busy_i       , // Resource busy input for the weight control unit
    output weight_instruction_t wei_inst_o                , // instruction output for the weight control unit
    output logic                wei_inst_en_o             , // instruction enable for the weight control unit
    // Matrix multiply control unit interface
    input  logic                matrix_busy_i             , // busy input for the matrix multiply control unit
    input  logic                matrix_resource_busy_i    , // Resource busy input for the matrix multiply control unit
    output instruction_t        matrix_inst_o             , // instruction output for the matrix multiply control unit
    output logic                matrix_inst_en_o          , // instruction enable for the matrix multiply control unit
    // Activation control unit interface
    input  logic                activation_busy_i         , // busy input for the activation control unit
    input  logic                activation_resource_busy_i, // Resource busy input for the activation control unit
    output instruction_t        activation_inst_o         , // instruction output for the activation control unit
    output logic                activation_inst_en_o      , // instruction enable for the activation control unit
    output logic                syn_o                       // Will be asserted when a synchronize instruction was feeded and all units are finished
);

    // Internal signals
    logic [3:0] en_flags_cs, en_flags_ns;   // Decoded enable_i - 0: WEIGHT, 1: MATRIX, 2: ACTIVATION, 3: SYNCHRONIZE
    instruction_t instruction_cs, instruction_ns;
    logic instruction_en_cs, instruction_en_ns;
    logic instruction_running;

    // Continuous assignments
    assign instruction_ns = inst_i;
    assign instruction_en_ns = inst_en_i;
    assign busy_o = instruction_running;

    // instruction decode process
    always_comb begin
        priority casez (inst_i.opcode)
            8'b1111_1111 : en_flags_ns = 4'b1000; // synchronize
            8'b1???_???? : en_flags_ns = 4'b0100; // activate
            8'b??1?_???? : en_flags_ns = 4'b0010; // matrix_multiply
            8'b????_1??? : en_flags_ns = 4'b0001; // load_weight
            default: begin
                en_flags_ns = 4'b0000; // probably nop
            end
        endcase
    end

    // Running detection process
    always_comb begin
        // Default values
        instruction_running  = 1'b0;
        wei_inst_en_o        = 1'b0;
        matrix_inst_en_o     = 1'b0;
        activation_inst_en_o = 1'b0;
        syn_o                = 1'b0;
        //
        if (instruction_en_cs) begin
            if (en_flags_cs[3]) begin
                // synchronize instruction - wait for unit to be finished
                if (wei_resource_busy_i || matrix_resource_busy_i || activation_resource_busy_i) begin
                    instruction_running = 1'b1;
                end else begin
                    syn_o = 1'b1;
                end
            end else begin
                // Other instructions
                if ((wei_busy_i && en_flags_cs[0]) || // Weight load waits for weight control unit to finish
                    (matrix_busy_i && (en_flags_cs[1] || en_flags_cs[2])) || // Activation waits for matrix multiply to finish
                    (activation_busy_i && en_flags_cs[2])) begin // Activation waits
                    instruction_running = 1'b1;
                end else begin
                    wei_inst_en_o        = en_flags_cs[0];
                    matrix_inst_en_o     = en_flags_cs[1];
                    activation_inst_en_o = en_flags_cs[2];
                end
            end
        end
    end

    // instruction output assignments
    assign wei_inst_o = to_weight_instruction(instruction_cs);
    assign matrix_inst_o = instruction_cs;
    assign activation_inst_o = instruction_cs;

    // Sequential logic
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            en_flags_cs       <= 4'b0000;
            instruction_cs    <= '0;
            instruction_en_cs <= 1'b0;
        end else begin
            if (!instruction_running && enable_i) begin
                en_flags_cs       <= en_flags_ns;
                instruction_cs    <= instruction_ns;
                instruction_en_cs <= instruction_en_ns;
            end
        end
    end

endmodule