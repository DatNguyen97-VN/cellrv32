// =============================================================================
// cellrv32_npu_TileMem
// Role: read-only "layer/tile configuration store" of the NPU.
//   - After reset, it walks through layer_info.hex one word per cycle and
//     unpacks it into registers (layer dims, tile sizes, edge sizes, iteration
//     counts, and the mapping summary).
//   - Once loaded (isInited_o = 1), the values are static and are used by the
//     controller FSMs (sliding window, row/channel transitions, traffic gen)
//     as loop bounds and mapping parameters.
// =============================================================================
`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

module cellrv32_npu_TileMem (
  input  logic        clk_i,
  input  logic        rstn_i, // async active-low reset; restarts loading
  // ---- Init status ---------------------------------------------------------
  // High when all words are loaded. 
  output logic        isInited_o,
  // ---- Layer dimensions ----------------------------------------------------
  // K = output channels, C = input channels, R/S = kernel height/width,
  // Y/X = feature-map height/width.
  output logic [31:0] getDimK_o,
  output logic [31:0] getDimC_o,
  output logic [31:0] getDimR_o,
  output logic [31:0] getDimS_o,
  output logic [31:0] getDimY_o,
  output logic [31:0] getDimX_o,
  // ---- Tile sizes ----------------------------------------------------------
  // Portion of each dimension processed at once by the hardware
  // (the layer is split into tiles because the array is finite).
  output logic [31:0] getTileSzK_o,
  output logic [31:0] getTileSzC_o,
  output logic [31:0] getTileSzR_o,
  output logic [31:0] getTileSzS_o,
  output logic [31:0] getTileSzY_o,
  output logic [31:0] getTileSzX_o,
  // ---- Edge sizes ----------------------------------------------------------
  // Size of the last (possibly partial) tile per dimension, used when
  // Dim is not divisible by TileSz. Drives the "isXEdge / isYEdge / ..." logic.
  output logic [31:0] getEdgeK_o,
  output logic [31:0] getEdgeC_o,
  output logic [31:0] getEdgeR_o,
  output logic [31:0] getEdgeS_o,
  output logic [31:0] getEdgeY_o,
  output logic [31:0] getEdgeX_o,
  // ---- Number of iterations ------------------------------------------------
  // Number of tiles per dimension (about ceil(Dim / TileSz)); these are the
  // loop bounds of the nested K / C / Y / X tile loops in the controller.
  output logic [31:0] getNumIterK_o,
  output logic [31:0] getNumIterC_o,
  output logic [31:0] getNumIterR_o,
  output logic [31:0] getNumIterS_o,
  output logic [31:0] getNumIterY_o,
  output logic [31:0] getNumIterX_o,
  // ---- Mapping summary -----------------------------------------------------
  output logic [31:0] getNumMultSwitches_o, // multiplier switches used by this mapping
  output logic [31:0] getNumMappedVNs_o,    // virtual neurons mapped concurrently
  output logic [31:0] getVNSize_o           // multipliers per VN (about R*S*C tile)
);

  localparam int MEM_DEPTH = 2 ** $bits(CR_TileInfoIdx);

  // -------------------------------------------------------------------------
  // ROM initialized
  // -------------------------------------------------------------------------
  CR_TileInfoData tileInfoMem [0:MEM_DEPTH-1];

  initial begin
    $readmemh("layer_info.hex", tileInfoMem);
  end
  // -------------------------------------------------------------------------

  logic inited_r;

  CR_TileInfoIdx pc;
  LayerDimension targetDim;
  CR_TileInfoData rawTileInfo;

  logic [31:0] layerDimSizes [0:NumLayerDimensions-1];
  logic [31:0] dimTileSizes  [0:NumLayerDimensions-1];
  logic [31:0] dimEdgeSizes  [0:NumLayerDimensions-1];
  logic [31:0] dimNumIters   [0:NumLayerDimensions-1];

  logic [31:0] numMultSwitches_r;
  logic [31:0] numMappedVNs_r;
  logic [31:0] vnSz_r;

  // -------------------------------------------------------------------------
  // extract the tile info from the memory
  // -------------------------------------------------------------------------
  always_ff @(posedge clk_i or negedge rstn_i) begin
    if (!rstn_i) begin
      inited_r          <= 1'b0;
      pc                <= '0;
      numMultSwitches_r <= '0;
      numMappedVNs_r    <= '0;
      vnSz_r            <= '0;
      for (int i = 0; i < NumLayerDimensions; i++) begin
        layerDimSizes[i] <= '0;
        dimTileSizes[i]  <= '0;
        dimEdgeSizes[i]  <= '0;
        dimNumIters[i]   <= '0;
      end
    end else if (!inited_r) begin
      targetDim = LayerDimension'(pc >> 1);
      rawTileInfo = tileInfoMem[pc];

      if (targetDim < dimEnd) begin
        if (pc[0]) begin
          // mode == 1: edgeSz + numIters
          dimEdgeSizes[targetDim] <= rawTileInfo[31:16]; // dimsz
          dimNumIters[targetDim]  <= rawTileInfo[15:0];  // tilesz
        end else begin
          // mode == 0: dimSz + tileSz
          layerDimSizes[targetDim] <= rawTileInfo[31:16]; // dimsz
          dimTileSizes[targetDim]  <= rawTileInfo[15:0];  // tilesz
        end
      end else begin
        // targetDim >= dimEnd: numMultSwitches, numMappedVNs, vnSz
        numMultSwitches_r <= rawTileInfo[31:16];        // dimsz
        numMappedVNs_r    <= rawTileInfo[15:0];         // tilesz
        vnSz_r            <= tileInfoMem[pc + 1][15:0]; // tilesz
        inited_r          <= 1'b1;
      end
      // next to mem word
      pc <= pc + 1;
    end
  end

  // -------------------------------------------------------------------------
  // method isInited (no guard)
  // -------------------------------------------------------------------------
  assign isInited_o = inited_r;

  // -------------------------------------------------------------------------
  // Outputs assignments for getDim*, getTileSz*, getEdge*, getNumIter*, getNumMultSwitches, getNumMappedVNs, getVNSize
  // -------------------------------------------------------------------------
  assign getDimK_o = layerDimSizes[dimK];
  assign getDimC_o = layerDimSizes[dimC];
  assign getDimR_o = layerDimSizes[dimR];
  assign getDimS_o = layerDimSizes[dimS];
  assign getDimY_o = layerDimSizes[dimY];
  assign getDimX_o = layerDimSizes[dimX];

  assign getTileSzK_o = dimTileSizes[dimK];
  assign getTileSzC_o = dimTileSizes[dimC];
  assign getTileSzR_o = dimTileSizes[dimR];
  assign getTileSzS_o = dimTileSizes[dimS];
  assign getTileSzY_o = dimTileSizes[dimY];
  assign getTileSzX_o = dimTileSizes[dimX];

  assign getEdgeK_o = dimEdgeSizes[dimK];
  assign getEdgeC_o = dimEdgeSizes[dimC];
  assign getEdgeR_o = dimEdgeSizes[dimR];
  assign getEdgeS_o = dimEdgeSizes[dimS];
  assign getEdgeY_o = dimEdgeSizes[dimY];
  assign getEdgeX_o = dimEdgeSizes[dimX];

  assign getNumIterK_o = dimNumIters[dimK];
  assign getNumIterC_o = dimNumIters[dimC];
  assign getNumIterR_o = dimNumIters[dimR];
  assign getNumIterS_o = dimNumIters[dimS];
  assign getNumIterY_o = dimNumIters[dimY];
  assign getNumIterX_o = dimNumIters[dimX];

  assign getNumMultSwitches_o = numMultSwitches_r;
  assign getNumMappedVNs_o    = numMappedVNs_r;
  assign getVNSize_o          = vnSz_r;

endmodule