`ifndef  _INCL_NPU_DEFINITIONS
  `define _INCL_NPU_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_NPU_DEFINITIONS

// Matrix Arbiter with N requesters
//
// Algorithm: Matrix Priority Arbiter
// - Matrix priorityBits[N][N]: priorityBits[i][j] = 1 means i has higher priority than j
// - Diagonal priorityBits[i][i] is always 0 (not compared to itself)
// - getPermitSignal(reqVec, idx):
// For each competitor i:
// if i <  idx: check ~priorityBits[idx][i] (idx does not have higher priority than i)
// if i >= idx: check priorityBits[i][idx] (does i have higher priority than idx?)
// priTest = priBits & reqVec
// permit = (priTest == 0) → no one is requesting AND has higher priority than idx
// - getGrantIdx: find the first idx where reqVec[idx]=1 && permit
// - updatePriorityBits(target):
// Delete the target row (target.row = 0 → target no longer has priority over anyone)
// Set the target column (i.col[target] = 1 ∀ i≠target → everyone has priority over target)

module cellrv32_npu_matrix_arbiter #(
    parameter int NUM_REQ = 4
) (
    input  logic               clk_i            ,
    input  logic               rstn_i           ,
    // getArbit
    input  logic               getArbit_en_i    ,
    input  logic [NUM_REQ-1:0] getArbit_reqBit_i,
    output logic [NUM_REQ-1:0] getArbit_val_o
);
    // ----------------------------------------------------------------
    // initialize matrix (except the diagonal)
    // ----------------------------------------------------------------
    logic [NUM_REQ-1:0] priorityBits [NUM_REQ-1:0];  // [row][col]

    // ----------------------------------------------------------------
    // Permit Bits — Check if all IDX (gi) is allowed to win based on current priority bits.
    // ----------------------------------------------------------------
    logic [NUM_REQ-1:0] permitBits;
    genvar gi, gj;
    generate
        for (gi = NUM_REQ-1; gi >= 0; gi--) begin : g_permit
            logic [NUM_REQ-1:0] priBits;   
            logic [NUM_REQ-1:0] priTest; 

            always_comb begin
                for (int gj = NUM_REQ-1; gj >= 0; gj--) begin
                    priBits[gj] = (gj < gi) ? ~priorityBits[gi][gj] : priorityBits[gj][gi];
                end
                priTest = priBits & getArbit_reqBit_i;
            end
            assign permitBits[gi] = (priTest == '0);
        end : g_permit
    endgenerate

    // ----------------------------------------------------------------
    // finding winner
    // The result is the HIGHEST index that satisfies the condition.
    // ----------------------------------------------------------------
    logic [$clog2(NUM_REQ)-1:0] grant_idx_comb;
    logic [NUM_REQ-1:0]         grant_val_comb;
    logic                       any_req_comb;

    assign any_req_comb = |getArbit_reqBit_i;

    always_comb begin
        grant_idx_comb = '0;
        if (any_req_comb) begin
            for (int i = NUM_REQ-1; i >= 0; i--) begin
                if (getArbit_reqBit_i[i] && permitBits[i]) begin
                    grant_idx_comb = i[$clog2(NUM_REQ)-1:0];
                end
            end
        end
    end

    always_comb begin
        grant_val_comb = '0;
        if (any_req_comb) begin
            grant_val_comb[grant_idx_comb] = 1'b1;
        end
    end

    assign getArbit_val_o = grant_val_comb;

    // ================================================================
    // Sequential: update priorityBits
    // ================================================================
    always_ff @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            // initialize matrix (except the diagonal)
            for (int i = 0; i < NUM_REQ; i++) begin
              for (int j = 0; j < NUM_REQ; j++) begin
                if (i == j) begin
                    priorityBits[i][j] <= 1'b0;
                end else begin
                    priorityBits[i][j] <= 1'b1;
                end
              end
            end
        end
        else begin
            // --------------------------------------------------------
            //  function updatePriorityBits(target):
            //    1. Clear row target: priorityBits[target][j] <= 0  ∀ j
            //    2. Set column target: priorityBits[i][target] <= 1  ∀ i≠target
            // --------------------------------------------------------
            if (getArbit_en_i && (getArbit_reqBit_i != '0)) begin
                // Clear row of winner
                for (int j = 0; j < NUM_REQ; j++) begin
                  priorityBits[grant_idx_comb][j] <= 1'b0;
                end
                // Set column (except the diagonal)
                for (int i = 0; i < NUM_REQ; i++) begin
                  if (i != grant_idx_comb) begin
                    priorityBits[i][grant_idx_comb] <= 1'b1;
                  end
                end
            end
        end
    end

endmodule


// ================================================================
// Testbench
// ================================================================
module tb_cellrv32_npu_matrix_arbiter;

    localparam int N = 4;

    logic             clk_i, rstn_i;
    initial clk_i = 0;
    always #5 clk_i = ~clk_i;

    logic          arbit_en;
    logic [N-1:0]  arbit_req,  arbit_val;

    cellrv32_npu_matrix_arbiter #(.NUM_REQ(N)) dut (
        .clk_i             (clk_i),
        .rstn_i            (rstn_i),

        .getArbit_en_i     (arbit_en),
        .getArbit_reqBit_i (arbit_req),
        .getArbit_val_o    (arbit_val)
    );

    // ----------------------------------------------------------------
    task automatic do_arbit(input logic [N-1:0] req, output logic [N-1:0] grant);
        @(posedge clk_i);
        arbit_en  = 1'b1;
        arbit_req = req;
        #1;
        grant = arbit_val;
        $display("[ARB ] req=%04b  grant=%04b (winner=%0d)",
                 req, arbit_val, $clog2(arbit_val + 1) - 1);
        @(posedge clk_i);
        arbit_en = 1'b0;
    endtask
    // ----------------------------------------------------------------

    logic [N-1:0] g;

    initial begin
        rstn_i    = 0; arbit_en = 0; arbit_req = '0;
        repeat (3) @(posedge clk_i); rstn_i = 1; @(posedge clk_i);

        $display("\n=== Test 1: Round-robin fairness - all request ===");
        repeat (8) begin
            do_arbit(4'b1111, g);
        end

        $display("\n=== Test 2: Single requester - always win ===");
        do_arbit(4'b0010, g);
        do_arbit(4'b0010, g);
        do_arbit(4'b0010, g);

        $display("\n=== Test 3: No request - return 0 ===");
        do_arbit(4'b0000, g);

        $display("\n=== Test 4: Subset request ===");
        repeat (6) do_arbit(4'b0101, g);

        $display("\n=== Test 5: Reset between tests ===");
        do_arbit(4'b1111, g);
        rstn: begin
            @(posedge clk_i); rstn_i = 0;
            repeat (2) @(posedge clk_i); rstn_i = 1;
        end
        @(posedge clk_i);
        @(posedge clk_i);
        // Arbitrate again after reset
        repeat (4) do_arbit(4'b1111, g);

        repeat (2) @(posedge clk_i);
        $display("\n=== Done ===");
        $finish;
    end

endmodule