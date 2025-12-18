// ##################################################################################################
// # << CELLRV32 - Vector Memory Unit >>                                                            #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS
 
module vmu #(
    parameter int REQ_DATA_WIDTH     = 256,
    parameter int VECTOR_REGISTERS   = 32 ,
    parameter int VECTOR_LANES       = 8  ,
    parameter int DATA_WIDTH         = 32 ,
    parameter int ADDR_WIDTH         = 32 ,
    parameter int MICROOP_WIDTH      = 5  ,
    parameter int VECTOR_TICKET_BITS = 4
) (
    input  logic                                                              clk                ,
    input  logic                                                              rst_n              ,
    output logic                                                              vmu_idle_o         ,
    //Instruction In
    input  logic                                                              valid_in           ,
    input  memory_remapped_v_instr                                            instr_in           ,
    output logic                                                              ready_o            ,
    //Cache Interface (OUT)
    output logic                                                              mem_req_valid_o    ,
    output vector_mem_req                                                     mem_req_o          ,
    //Cache Interface (IN)
    input  logic                                                              cache_ready_i      ,
    input  logic                                                              mem_resp_valid_i   ,
    input  vector_mem_resp                                                    mem_resp_i         ,
    //RF Interface - Loads
    output logic [$clog2(VECTOR_REGISTERS)-1:0]                               rd_addr_0_o        ,
    input  logic [ VECTOR_LANES*DATA_WIDTH-1:0]                               rd_data_0_i        ,
    input  logic                                                              rd_pending_0_i     ,
    input  logic [      VECTOR_TICKET_BITS-1:0]                               rd_ticket_0_i      ,
    //RF Interface - Stores
    output logic [$clog2(VECTOR_REGISTERS)-1:0]                               rd_addr_1_o        ,
    input  logic [ VECTOR_LANES*DATA_WIDTH-1:0]                               rd_data_1_i        ,
    input  logic                                                              rd_pending_1_i     ,
    input  logic [      VECTOR_TICKET_BITS-1:0]                               rd_ticket_1_i      ,
    output logic [$clog2(VECTOR_REGISTERS)-1:0]                               rd_addr_2_o        ,
    input  logic [ VECTOR_LANES*DATA_WIDTH-1:0]                               rd_data_2_i        ,
    input  logic                                                              rd_pending_2_i     ,
    input  logic [      VECTOR_TICKET_BITS-1:0]                               rd_ticket_2_i      ,
    //RF Writeback Interface
    output logic [            VECTOR_LANES-1:0]                               wrtbck_en_o        ,
    output logic [$clog2(VECTOR_REGISTERS)-1:0]                               wrtbck_reg_o       ,
    output logic [ VECTOR_LANES*DATA_WIDTH-1:0]                               wrtbck_data_o      ,
    output logic [      VECTOR_TICKET_BITS-1:0]                               wrtbck_ticket_o    ,
    //RF Writeback Probing Interface
    output logic [                         3:0][$clog2(VECTOR_REGISTERS)-1:0] wrtbck_prb_reg_o   ,
    input  logic [                         3:0]                               wrtbck_prb_locked_i,
    input  logic [                         3:0][      VECTOR_TICKET_BITS-1:0] wrtbck_prb_ticket_i,
    //Unlock Interface
    output logic                                                              unlock_en_o        ,
    output logic [$clog2(VECTOR_REGISTERS)-1:0]                               unlock_reg_a_o     ,
    output logic [$clog2(VECTOR_REGISTERS)-1:0]                               unlock_reg_b_o     ,
    output logic [      VECTOR_TICKET_BITS-1:0]                               unlock_ticket_o
);

    //=======================================================
    // WIRES
    //=======================================================
    logic                                load_unlock_en    ;
    logic [$clog2(VECTOR_REGISTERS)-1:0] load_unlock_reg_a ;
    logic [$clog2(VECTOR_REGISTERS)-1:0] load_unlock_reg_b ;
    logic [      VECTOR_TICKET_BITS-1:0] load_unlock_ticket;
    logic [              ADDR_WIDTH-1:0] load_start_addr   ;
    logic [              ADDR_WIDTH-1:0] load_end_addr     ;
    logic [              ADDR_WIDTH-1:0] load_req_addr     ;
    logic [           MICROOP_WIDTH-1:0] load_req_microop  ;
    logic [      $clog2(VECTOR_LANES):0] load_req_ticket   ;
    logic [            VECTOR_LANES-1:0] ld_wb_en          ;
    logic [$clog2(VECTOR_REGISTERS)-1:0] ld_wb_reg         ;
    logic [ VECTOR_LANES*DATA_WIDTH-1:0] ld_wb_data        ;
    logic [      VECTOR_TICKET_BITS-1:0] ld_wb_ticket      ;

    logic                                store_unlock_en    ;
    logic [$clog2(VECTOR_REGISTERS)-1:0] store_unlock_reg_a ;
    logic [$clog2(VECTOR_REGISTERS)-1:0] store_unlock_reg_b ;
    logic [      VECTOR_TICKET_BITS-1:0] store_unlock_ticket;
    logic [              ADDR_WIDTH-1:0] store_start_addr   ;
    logic [              ADDR_WIDTH-1:0] store_end_addr     ;
    logic [              ADDR_WIDTH-1:0] store_req_addr     ;
    logic [           MICROOP_WIDTH-1:0] store_req_microop  ;
    logic [  $clog2(REQ_DATA_WIDTH/8):0] store_req_size     ;
    logic [          REQ_DATA_WIDTH-1:0] store_req_data     ;

    logic [1:0] is_busy     ;
    logic       is_load     ;
    logic       is_store    ;
    logic       is_reconf   ;
    logic       push_load   ;
    logic       push_store  ;
    logic       load_ready  ;
    logic       store_ready ;
    logic       load_starts ;
    logic       store_starts;
    logic       load_ends   ;
    logic       store_ends  ;

    logic       ld_request;
    logic       st_request;

    //Create the ready out signal
    assign ready_o = valid_in & ((is_load & load_ready) | (is_store & store_ready));

    assign vmu_idle_o = ~|is_busy;

    //Pick the Outputs
    assign unlock_en_o     = load_unlock_en | store_unlock_en;
    assign unlock_reg_a_o  = load_unlock_en ? load_unlock_reg_a  : store_unlock_reg_a;
    assign unlock_reg_b_o  = load_unlock_en ? load_unlock_reg_b  : store_unlock_reg_b;
    assign unlock_ticket_o = load_unlock_en ? load_unlock_ticket : store_unlock_ticket;

    assign mem_req_valid_o = ld_request | st_request;

    assign mem_req_o.address = ld_request ? load_req_addr  : store_req_addr;
    assign mem_req_o.microop = ld_request ? opcode_vload_c : opcode_vstore_c;
    assign mem_req_o.ticket  = load_req_ticket;
    assign mem_req_o.data    = store_req_data;

    assign wrtbck_en_o     = ld_wb_en;
    assign wrtbck_reg_o    = ld_wb_reg;
    assign wrtbck_data_o   = ld_wb_data;
    assign wrtbck_ticket_o = ld_wb_ticket;

    //Push the instruction to the correct engine
    assign is_load   = ~instr_in.reconfigure & (instr_in.microop[6:4] == 3'b000);
    assign is_store  = ~instr_in.reconfigure & (instr_in.microop[6:4] == 3'b010);
    assign is_reconf =  instr_in.reconfigure;

    always_comb begin
        if(is_reconf) begin
            push_load  = valid_in & load_ready & store_ready;
            push_store = valid_in & load_ready & store_ready;
        end else begin
            push_load  = valid_in & is_load  & load_ready;
            push_store = valid_in & is_store & store_ready;
        end
    end

    // ---------------------------------------------------------------
    // LOAD ENGINE
    // ---------------------------------------------------------------
    vmu_ld_eng #(
        .REQ_DATA_WIDTH    (REQ_DATA_WIDTH    ),
        .VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
        .VECTOR_LANES      (VECTOR_LANES      ),
        .DATA_WIDTH        (DATA_WIDTH        ),
        .ADDR_WIDTH        (ADDR_WIDTH        ),
        .MICROOP_WIDTH     (MICROOP_WIDTH     ),
        .VECTOR_TICKET_BITS(VECTOR_TICKET_BITS)
    ) vmu_ld_eng (
        .clk_i                (clk                   ),
        .rstn_i               (rst_n                 ),
        //input Interface
        .valid_in             (push_load             ),
        .instr_in             (instr_in              ),
        .ready_o              (load_ready            ),
        //RF read Interface (for indexed stride)
        .rd_addr_o            (rd_addr_0_o           ),
        .rd_data_i            (rd_data_0_i           ),
        .rd_pending_i         (rd_pending_0_i        ),
        .rd_ticket_i          (rd_ticket_0_i         ),
        //RF write Interface
        .wrtbck_grant_i       (1'b1                  ),
        .wrtbck_req_o         (                      ),
        .wrtbck_en_o          (ld_wb_en              ),
        .wrtbck_reg_o         (ld_wb_reg             ),
        .wrtbck_data_o        (ld_wb_data            ),
        .wrtbck_ticket_o      (ld_wb_ticket          ),
        //RF Writeback Probing Interface
        .wrtbck_prb_reg_a_o   (wrtbck_prb_reg_o[0]   ),
        .wrtbck_prb_locked_a_i(wrtbck_prb_locked_i[0]),
        .wrtbck_prb_ticket_a_i(wrtbck_prb_ticket_i[0]),
        .wrtbck_prb_reg_b_o   (wrtbck_prb_reg_o[1]   ),
        .wrtbck_prb_locked_b_i(wrtbck_prb_locked_i[1]),
        .wrtbck_prb_ticket_b_i(wrtbck_prb_ticket_i[1]),
        //Unlock Interface
        .unlock_en_o          (load_unlock_en        ),
        .unlock_reg_a_o       (load_unlock_reg_a     ),
        .unlock_reg_b_o       (load_unlock_reg_b     ),
        .unlock_ticket_o      (load_unlock_ticket    ),
        //Request Interface
        .grant_i              (cache_ready_i         ),
        .req_en_o             (ld_request            ),
        .req_addr_o           (load_req_addr         ),
        .req_microop_o        (load_req_microop      ),
        .req_size_o           (                      ),
        .req_ticket_o         (load_req_ticket       ),
        // Incoming Data from Cache
        .resp_valid_i         (mem_resp_valid_i      ),
        .resp_ticket_i        (mem_resp_i.ticket     ),
        .resp_data_i          (mem_resp_i.data       ),
        //Sync Interface
        .is_busy_o            (is_busy[0]            ),
        .start_addr_o         (load_start_addr       ),
        .end_addr_o           (load_end_addr         )
    );

    // ---------------------------------------------------------------
    // STORE ENGINE
    // ---------------------------------------------------------------
    vmu_st_eng #(
        .REQ_DATA_WIDTH    (REQ_DATA_WIDTH    ),
        .VECTOR_REGISTERS  (VECTOR_REGISTERS  ),
        .VECTOR_LANES      (VECTOR_LANES      ),
        .DATA_WIDTH        (DATA_WIDTH        ),
        .ADDR_WIDTH        (ADDR_WIDTH        ),
        .MICROOP_WIDTH     (MICROOP_WIDTH     ),
        .VECTOR_TICKET_BITS(VECTOR_TICKET_BITS)
    ) vmu_st_eng (
        .clk                (clk                ),
        .rst_n              (rst_n              ),
        //Input Interface
        .valid_in           (push_store         ),
        .instr_in           (instr_in           ),
        .ready_o            (store_ready        ),
        //RF Interface (per vreg)
        .rd_addr_1_o        (rd_addr_1_o        ),
        .rd_data_1_i        (rd_data_1_i        ),
        .rd_pending_1_i     (rd_pending_1_i     ),
        .rd_ticket_1_i      (rd_ticket_1_i      ),
        //RF Interface (for indexed stride)
        .rd_addr_2_o        (rd_addr_2_o        ),
        .rd_data_2_i        (rd_data_2_i        ),
        .rd_pending_2_i     (rd_pending_2_i     ),
        .rd_ticket_2_i      (rd_ticket_2_i      ),
        //Unlock Interface
        .unlock_en_o        (store_unlock_en    ),
        .unlock_reg_a_o     (store_unlock_reg_a ),
        .unlock_reg_b_o     (store_unlock_reg_b ),
        .unlock_ticket_o    (store_unlock_ticket),
        //Request Interface
        .req_en_o           (st_request         ),
        .grant_i            (cache_ready_i      ),
        .req_addr_o         (store_req_addr     ),
        .req_microop_o      (store_req_microop  ),
        .req_size_o         (store_req_size     ),
        .req_data_o         (store_req_data     ),
        //Sync Interface
        .is_busy_o          (is_busy[1]         ),
        .start_addr_o       (store_start_addr   ),
        .end_addr_o         (store_end_addr     )
    );

endmodule