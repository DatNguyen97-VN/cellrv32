package cellrv32_npu_package;
  // Activation function types
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
    
endpackage