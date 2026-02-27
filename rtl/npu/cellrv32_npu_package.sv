package cellrv32_npu_package;
  // TPU parameters
  localparam int BYTE_WIDTH = 8;

  // Activation function types
  localparam int ACTIVATION_BIT_WIDTH = 4;

  typedef enum logic [3:0] {
      NO_ACTIVATION,
      RELU         ,
      RELU6        ,
      CRELU        ,
      ELU          ,
      SELU         ,
      SOFTPLUS     ,
      SOFTSIGN     ,
      DROPOUT      ,
      SIGMOID      ,
      TANH         
  } activation_type_t;

  // Instruction structure
  localparam int BUFFER_ADDRESS_WIDTH      = 24;
  localparam int ACCUMULATOR_ADDRESS_WIDTH = 16;
  localparam int WEIGHT_ADDRESS_WIDTH      = BUFFER_ADDRESS_WIDTH + ACCUMULATOR_ADDRESS_WIDTH;
  localparam int LENGTH_WIDTH              = 32;
  localparam int OP_CODE_WIDTH             = 8;

  typedef logic [BUFFER_ADDRESS_WIDTH-1:0]      BUFFER_ADDRESS_TYPE;
  typedef logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] ACCUMULATOR_ADDRESS_TYPE;
  typedef logic [WEIGHT_ADDRESS_WIDTH-1:0]      WEIGHT_ADDRESS_TYPE;
  typedef logic [LENGTH_WIDTH-1:0]              LENGTH_TYPE;
  typedef logic [OP_CODE_WIDTH-1:0]             OP_CODE_TYPE;

  typedef struct packed {
    logic [OP_CODE_WIDTH-1:0]             opcode;
    logic [LENGTH_WIDTH-1:0]              calc_len;
    logic [ACCUMULATOR_ADDRESS_WIDTH-1:0] acc_addr;
    logic [BUFFER_ADDRESS_WIDTH-1:0]      buff_addr;
  } instruction_t;

  typedef struct packed {
    logic [OP_CODE_WIDTH-1:0]        opcode;
    logic [LENGTH_WIDTH-1:0]         calc_len;
    logic [WEIGHT_ADDRESS_WIDTH-1:0] wei_addr;
  } weight_instruction_t;

  function automatic weight_instruction_t to_weight_instruction(instruction_t instr);
    weight_instruction_t w;
    w.opcode   = instr.opcode;
    w.calc_len = instr.calc_len;
    w.wei_addr = {instr.buff_addr, instr.acc_addr};
    return w;
  endfunction

endpackage