`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_npu_package::*;
`endif // _INCL_DEFINITIONS

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
    // getPermitSignal — Check if IDX is allowed to win based on current priority bits.
    // ----------------------------------------------------------------
    function automatic logic getPermitSignal(
        input logic [NUM_REQ-1:0]         reqVec,
        input logic [$clog2(NUM_REQ)-1:0] idx,
        input logic [NUM_REQ-1:0]         pBits [NUM_REQ-1:0]
    );
        logic [NUM_REQ-1:0] priBits;
        logic [NUM_REQ-1:0] priTest;

        for (int i = NUM_REQ-1; i >= 0; i--) begin
            priBits[i] = (i < idx) ? ~pBits[idx][i] : pBits[i][idx];
        end

        priTest = priBits & reqVec;
        return (priTest == '0);
    endfunction

    // ----------------------------------------------------------------
    // getGrantIdx — finding winner
    //   → The result is the HIGHEST index that satisfies the condition.
    // ----------------------------------------------------------------
    function automatic logic [$clog2(NUM_REQ)-1:0] getGrantIdx(
        input logic [NUM_REQ-1:0] reqVec,
        input logic [NUM_REQ-1:0] pBits [NUM_REQ-1:0]
    );
        logic [$clog2(NUM_REQ)-1:0] ret;
        logic permit;

        ret = 0;  // default
        for (int i = NUM_REQ-1; i >= 0; i--) begin
            permit = getPermitSignal(reqVec, i, pBits);
            if (reqVec[i] && permit) begin
              ret = i;
            end
        end
        return ret;
    endfunction

    // ----------------------------------------------------------------
    // Generate an one-hot code from index
    // ----------------------------------------------------------------
    function automatic logic [NUM_REQ-1:0] packGrantIdx(input logic [$clog2(NUM_REQ)-1:0] idx);
        logic [NUM_REQ-1:0] ret;
        ret = '0;
        ret[idx] = 1'b1;
        return ret;
    endfunction

    // ================================================================
    // getArbit
    // ================================================================
    logic [NUM_REQ-1:0]         grant_val_comb;
    logic [$clog2(NUM_REQ)-1:0] grant_idx_comb;

    always_comb begin
        if (getArbit_reqBit_i == '0) begin
            grant_val_comb = '0;
            grant_idx_comb = 0;
        end else begin
            grant_idx_comb = getGrantIdx(getArbit_reqBit_i, priorityBits);
            grant_val_comb = packGrantIdx(grant_idx_comb);
        end
    end

    assign getArbit_val_o = grant_val_comb;

    // ================================================================
    // Sequential: cập nhật priorityBits và inited
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
module tb_mkMatrixArbiter;

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