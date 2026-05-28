package cellrv32_npu_package;
    // Tile Types
    typedef logic [15:0] INT16;
    localparam int NumLayerDimensions = 6;
    typedef logic [4:0] LayerDimension;

    localparam logic [4:0] dimK   = 5'b00000;
    localparam logic [4:0] dimC   = 5'b00001;
    localparam logic [4:0] dimR   = 5'b00010;
    localparam logic [4:0] dimS   = 5'b00011;
    localparam logic [4:0] dimY   = 5'b00100;
    localparam logic [4:0] dimX   = 5'b00101;
    localparam logic [4:0] dimEnd = 5'b00110;

    // Accelerator Config
    localparam int DistributionBandwidth = 16;
    localparam int CollectionBandwidth   = 16;
    localparam int NumMultSwitches       = 128;

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
    localparam int DN_SubTreeEgressControlFifoDepth = 1;

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

    localparam int DN_SubTreeIngressFifoDepth = 16;
    localparam int DN_IngressFifoDepth        = 16;
    localparam int DN_EgressFifoDepth         = 1;

    typedef logic [NumMultSwitches-1:0] DN_Config;

    // ==============================================================
    // RN Types
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

    localparam int RN_NumLevels        = $clog2(NumMultSwitches);
    localparam int RN_NumAdderSwitches = NumMultSwitches - 1;
    localparam int RN_NumSglRSes       = (RN_NumLevels * 2) - 1;
    localparam int RN_NumDblRSes       = (RN_NumAdderSwitches - RN_NumSglRSes) / 2;

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
    localparam int RN_NumCollectionBusInputPorts = NumMultSwitches / RN_NumColletionBuses + 1;

    const int RN_CollectionBusIngressFifoDepth = 4;
    const int RN_CollectionBusEngressFifoDepth = 1;

    // ==============================================================
    // CR types
    // ==============================================================
    typedef logic [9:0]  CR_ConfigIdx;
    typedef logic [31:0] CR_ConfigData;

    typedef logic [3:0]  CR_SGRS_ConfigData;
    typedef logic [7:0]  CR_DBRS_ConfigData;

    // -------------------------------------------------------------------------
    // Parameters
    // -------------------------------------------------------------------------
    localparam int CR_DBRS_ConfigAddressBound = RN_NumDblRSes / 4;
    localparam int CR_SGRS_ConfigAddressBound = RN_NumSglRSes / 8 + CR_DBRS_ConfigAddressBound;

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

    // -------------------------------------------------------------------------
    // function getCR_DBRS_ConfigData
    // fullData[8*configIdx+7 : 8*configIdx]
    // -------------------------------------------------------------------------
    function automatic CR_DBRS_ConfigData getCR_DBRS_ConfigData(
      input CR_ConfigData fullData,
      input logic [5:0]   configIdx
    );
      logic [5:0] baseIdx = 8 * configIdx;
      return fullData[baseIdx +: 8];
    endfunction

    // -------------------------------------------------------------------------
    // function getDBRS_ModeFromRawData
    // truncateLSB: lay 4 bit tren cua 8-bit => [7:4]
    // -------------------------------------------------------------------------
    function automatic RN_DBRS_Mode getDBRS_ModeFromRawData(
      input CR_DBRS_ConfigData rawData
    );
      return rawData[7:4];
    endfunction

    // -------------------------------------------------------------------------
    // function getDBRS_GenOutputL: rawData[3]
    // -------------------------------------------------------------------------
    function automatic logic getDBRS_GenOutputL(
      input CR_DBRS_ConfigData rawData
    );
      return rawData[3];
    endfunction

    // -------------------------------------------------------------------------
    // function getDBRS_GenOutputR: rawData[2]
    // -------------------------------------------------------------------------
    function automatic logic getDBRS_GenOutputR(
      input CR_DBRS_ConfigData rawData
    );
      return rawData[2];
    endfunction

    // -------------------------------------------------------------------------
    // function getCR_SGRS_ConfigData
    // fullData[4*configIdx+3 : 4*configIdx]
    // -------------------------------------------------------------------------
    function automatic CR_SGRS_ConfigData getCR_SGRS_ConfigData(
      input CR_ConfigData fullData,
      input logic [5:0]   configIdx
    );
      logic [5:0] baseIdx = 4 * configIdx;
      return fullData[baseIdx +: 4];
    endfunction

    // -------------------------------------------------------------------------
    // function getSGRS_ModeFromRawData
    // truncateLSB: lay 2 bit tren cua 4-bit => [3:2]
    // -------------------------------------------------------------------------
    function automatic RN_SGRS_Mode getSGRS_ModeFromRawData(
      input CR_SGRS_ConfigData rawData
    );
      return rawData[3:2];
    endfunction

    // -------------------------------------------------------------------------
    // function getSGRS_GenOutput: rawData[1]
    // -------------------------------------------------------------------------
    function automatic logic getSGRS_GenOutput(
      input CR_SGRS_ConfigData rawData
    );
      return rawData[1];
    endfunction

    // -------------------------------------------------------------------------
    // Tile info functions
    // -------------------------------------------------------------------------

    // getTileInfo_DimSz: truncateLSB => lay 16 bit tren => [31:16]
    function automatic CR_TileInfo getTileInfo_DimSz(
      input CR_TileInfoData rawData
    );
      return rawData[31:16];
    endfunction

    // aliases
    function automatic CR_TileInfo getTileInfo_DimEdgeSz(
      input CR_TileInfoData rawData
    );
      return getTileInfo_DimSz(rawData);
    endfunction

    function automatic CR_TileInfo getTileInfo_NumMultSwitches(
      input CR_TileInfoData rawData
    );
      return getTileInfo_DimSz(rawData);
    endfunction

    // getTileInfo_TileSz: truncate => lay 16 bit duoi => [15:0]
    function automatic CR_TileInfo getTileInfo_TileSz(
      input CR_TileInfoData rawData
    );
      return rawData[15:0];
    endfunction

    // aliases
    function automatic CR_TileInfo getTileInfo_DimNumIters(
      input CR_TileInfoData rawData
    );
      return getTileInfo_TileSz(rawData);
    endfunction

    function automatic CR_TileInfo getTileInfo_NumMappedVNs(
      input CR_TileInfoData rawData
    );
      return getTileInfo_TileSz(rawData);
    endfunction

    function automatic CR_TileInfo getTileInfo_VNSize(
      input CR_TileInfoData rawData
    );
      return getTileInfo_TileSz(rawData);
    endfunction

    // ==============================================================
    // MN Types
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

    typedef MS_Config MN_Config [NumMultSwitches];

endpackage