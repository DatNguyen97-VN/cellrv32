package cellrv32_npu_package;
    // Tile Types
    typedef logic [15:0] INT16;
    localparam int NumLayerDimensions = 6;
    typedef logic [4:0] LayerDimension;

    localparam logic [4:0] dimK   = 5'b00000; // Output channels
    localparam logic [4:0] dimC   = 5'b00001; // Input channels
    localparam logic [4:0] dimR   = 5'b00010; // Filter height
    localparam logic [4:0] dimS   = 5'b00011; // Filter width
    localparam logic [4:0] dimY   = 5'b00100; // height feature map
    localparam logic [4:0] dimX   = 5'b00101; // width feature map
    localparam logic [4:0] dimEnd = 5'b00110; // end of dimensions

    // Accelerator Config
    localparam int DistributionBandwidth = 4;
    localparam int CollectionBandwidth   = 4;
    localparam int NumMultSwitches       = 16; //128

    // ==============================================================
    // Distribution Network
    // ==============================================================
    typedef enum logic [1:0] {DS_IDLE, DS_LEFT, DS_RIGHT, DS_BOTH} DS_State;
    typedef DS_State DS_Config;

    /* Sub Tree */
    // Design parameters
    localparam int DN_SubTreeIngressDataFifoDepth    = 4;
    localparam int DN_SubTreeIngressControlFifoDepth = 4;

    localparam int DN_SubTreeEgressDataFifoDepth    = 4;
    localparam int DN_SubTreeEgressControlFifoDepth = 4;

    // Deduced parameters
    localparam int DN_NumSubTrees            = DistributionBandwidth;
    localparam int DN_SubTreeSz              = NumMultSwitches / DN_NumSubTrees;
    localparam int DN_NumSubTreeDistSwitches = DN_SubTreeSz - 1;
    localparam int DN_NumSubTreeLvs          = $clog2(DN_SubTreeSz);
    //localparam int DN_SubTreeID              = $clog2(DN_NumSubTrees) + 4;
    typedef logic [$clog2(DN_NumSubTrees)+4-1:0] DN_SubTreeID;

    // Internal definition
    typedef logic DN_Epoch;
    localparam logic dn_initEpoch = 1'b0;

    // Data Types
    typedef logic [DN_SubTreeSz-1:0] DN_SubTreeDestBits;
    typedef DN_SubTreeDestBits DN_TopSubTreeConfig;
    typedef logic [DN_NumSubTreeDistSwitches-1:0][1:0] DN_SubTreeConfig;
    DN_TopSubTreeConfig dn_topSubtree_nullConfig = '0;

    localparam int DN_SubTreeIngressFifoDepth = 4;
    localparam int DN_SubTreeEngressFifoDepth = 4;
    localparam int DN_IngressFifoDepth        = 4;
    localparam int DN_EgressFifoDepth         = 4;

    typedef logic [NumMultSwitches-1:0] DN_Config;

    // ==============================================================
    // Reduction Network
    // ==============================================================
    typedef logic [1:0] RN_SGRS_Mode;
    typedef logic [3:0] RN_DBRS_Mode;
    typedef logic [1:0] RN_DBRS_SubMode;

    const logic [1:0] rn_dbrs_submode_idle     = 2'b00;
    const logic [1:0] rn_dbrs_submode_addOne   = 2'b01;
    const logic [1:0] rn_dbrs_submode_addTwo   = 2'b10;
    const logic [1:0] rn_dbrs_submode_addThree = 2'b11;

    const logic [1:0] rn_sgrs_mode_idle      = 2'b00;
    const logic [1:0] rn_sgrs_mode_addTwo    = 2'b01;
    const logic [1:0] rn_sgrs_mode_flowLeft  = 2'b10;
    const logic [1:0] rn_sgrs_mode_flowRight = 2'b11;

    localparam int RN_NumLevels  = $clog2(NumMultSwitches); // except root level
    localparam int RN_NumSglRSes = 2 * RN_NumLevels - 1;
    localparam int RN_NumDblRSes = (NumMultSwitches - 1 - RN_NumSglRSes) / 2;

    // Struct RN_SglRSConfig
    typedef struct packed {
      RN_SGRS_Mode mode;
      logic        genOutput;
    } RN_SglRSConfig;

    // Struct RN_DblRSConfig
    typedef struct packed {
      RN_DBRS_Mode mode;
      logic        genOutputL;
      logic        genOutputR;
    } RN_DblRSConfig;

    typedef struct {
      RN_SglRSConfig sglRSNetworkConfig [RN_NumSglRSes-1:0];
      RN_DblRSConfig dblRSNetworkConfig [RN_NumDblRSes-1:0];
    } RN_Config;

    /* ----- Collection Bus ----- */
    localparam int RN_NumColletionBuses = CollectionBandwidth;
    localparam int RN_NumCollectionBusInputPorts = $clog2(2 ** (RN_NumLevels - 1) + RN_NumLevels - 1);

    localparam int RN_CollectionBusIngressFifoDepth = 4;
    localparam int RN_CollectionBusEngressFifoDepth = 2;

    // ==============================================================
    // Configuration Memory
    // ==============================================================
    typedef logic [9:0]  CR_ConfigIdx;
    typedef logic [31:0] CR_ConfigData;

    typedef logic [3:0]  CR_SGRS_ConfigData;
    typedef logic [7:0]  CR_DBRS_ConfigData;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int CR_DBRS_ConfigAddressBound = (RN_NumDblRSes + 1) / 4;
    localparam int CR_SGRS_ConfigAddressBound = (RN_NumSglRSes + 1) / 8 + CR_DBRS_ConfigAddressBound;

    // -------------------------------------------------------------------------
    // Tile info types
    // -------------------------------------------------------------------------
    typedef logic [31:0] CR_TileInfoData;
    typedef logic [5:0]  CR_TileInfoIdx;
    typedef logic [15:0] CR_TileInfo;

    // -------------------------------------------------------------------------
    // TrafficGenStatus enum
    // -------------------------------------------------------------------------
    typedef enum logic [3:0] {
      Idle,
      WeightInitConfig,
      WeightInitData,
      InitWeightTransfer,
      InputInitConfig,
      InitInputTransfer,
      InputInitData,
      SteadyState,
      RowTransition,
      OutputChannelTransition,
      InputChannelTransition,
      FinishState
    } TrafficGenStatus;

    // ==============================================================
    // Multiplier Network
    // ==============================================================
    localparam int MS_IngressFifoDepth = 2;
    localparam int MS_EgressFifoDepth  = 2;

    localparam int MS_WeightFifoDepth = 2;
    localparam int MS_IfMapFifoDepth  = 2;
    localparam int MS_PSumFifoDepth   = 2;
    localparam int MS_FwdFifoDepth    = 2;

    /* Controller Internal */
    typedef enum logic [2:0] { MS_IDLE, MS_INIT_STEADY_VAL, MS_RUN_LEDGE_FIRST, MS_RUN_LEDGE,
                               MS_RUN_MIDDLE_FIRST, MS_RUN_MIDDLE, MS_RUN_REDGE_FIRST, MS_RUN_REDGE } MS_State;
    
    typedef logic [15:0] MS_PSumCount;

    /* Controller Output Signals */
    typedef enum logic [1:0] { MS_IPT_NOTHING, MS_IPT_STATIONARY, MS_IPT_STREAM } MS_IptSelect;

    typedef enum logic [1:0] { MS_FWD_NOTHING, MS_FWD_INPUT, MS_FWD_FWD } MS_FwdSelect;

    typedef enum logic [1:0] { MS_ARG_NOTHING, MS_ARG_INPUT, MS_ARG_FWD } MS_ArgSelect;

    typedef struct packed {
      MS_State     state;
      MS_PSumCount psumCount;
    } MS_Config;

    typedef MS_Config MN_Config [NumMultSwitches-1:0];

endpackage