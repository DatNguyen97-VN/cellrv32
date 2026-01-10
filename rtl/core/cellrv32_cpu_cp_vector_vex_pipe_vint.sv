// ##################################################################################################
// # << CELLRV32 - Vector Integer Unit >>                                                           #
// # ********************************************************************************************** #
`ifndef  _INCL_DEFINITIONS
  `define _INCL_DEFINITIONS
  import cellrv32_package::*;
`endif // _INCL_DEFINITIONS

module cellrv32_cpu_cp_vector_vex_pipe_vint #(
    parameter int DATA_WIDTH         = 32 ,
    parameter int MICROOP_WIDTH      = 5  ,
    parameter int VECTOR_REGISTERS   = 32 ,
    parameter int VECTOR_LANES       = 8  ,
    parameter int VECTOR_LANE_NUM    = 1  ,
    parameter int EX1_W              = 160,
    parameter int EX2_W              = 96 ,
    parameter int EX3_W              = 96 ,
    parameter int EX4_W              = 32
) (
    input  logic                                           clk            ,
    input  logic                                           rst_n          ,
    input  logic                                           valid_i        ,
    input  logic [                         DATA_WIDTH-1:0] data_a_ex1_i   ,
    input  logic [                         DATA_WIDTH-1:0] data_b_ex1_i   ,
    input  logic [                                    5:0] funct6_i       ,
    input  logic [                                    2:0] funct3_i       ,
    input  logic                                           mask_i         ,
    input  logic [                                    6:0] vl_i           ,
    input  logic                                           is_rdc_i       ,
    // Reduction Tree Inputs
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex1_i ,
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex2_i ,
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex3_i ,
    input  logic [                         DATA_WIDTH-1:0] rdc_data_ex4_i ,
    // Result Ex1 Out
    output logic                                           ready_res_ex1_o,
    output logic [                              EX1_W-1:0] result_ex1_o   ,
    // EX2 Data In
    input  logic [                              EX1_W-1:0] data_ex2_i     ,
    input  logic                                           mask_ex2_i     ,
    // Result EX2 Out
    output logic                                           ready_res_ex2_o,
    output logic [                              EX2_W-1:0] result_ex2_o   ,
    // EX3 Data In
    input  logic [                              EX2_W-1:0] data_ex3_i     ,
    input  logic                                           mask_ex3_i     ,
    // Result EX3 Out
    output logic                                           ready_res_ex3_o,
    output logic [                              EX3_W-1:0] result_ex3_o   ,
    // EX4 Data In
    input  logic [                              EX3_W-1:0] data_ex4_i     ,
    input  logic                                           mask_ex4_i     ,
    // Result EX4 Out
    output logic [                                    5:0] rdc_op_ex4_o   ,
    output logic                                           ready_res_ex4_o,
    output logic [                              EX4_W-1:0] result_ex4_o
);

    localparam int PARTIAL_SUM_W   = DATA_WIDTH + 8            ;
    localparam int DIV_CALC_CYCLES = 4                         ;
    localparam int DIV_BIT_GROUPS  = DATA_WIDTH/DIV_CALC_CYCLES;

    logic [DATA_WIDTH-1:0] data_a_u_ex1 ;
    logic [DATA_WIDTH-1:0] data_b_u_ex1 ;
    logic [DATA_WIDTH-1:0] data_a_s_ex1 ;
    logic [DATA_WIDTH-1:0] data_b_s_ex1 ;
    logic [DATA_WIDTH-1:0] data_a_wu_ex1;
    logic [DATA_WIDTH-1:0] data_b_wu_ex1;

    logic valid_int_ex1;
    logic valid_mul_ex1;
    logic valid_mul_ex2;
    logic valid_mul_ex3;
    logic valid_div_ex1;
    logic valid_div_ex2;
    logic valid_div_ex3;
    logic valid_div_ex4;
    logic is_multi_cycle;
    logic is_single_cycle;

    logic [EX1_W-1:0] result_int_ex1;

    logic [EX1_W-1:0] result_mul_ex1;
    logic [EX2_W-1:0] result_mul_ex2;
    logic [EX3_W-1:0] result_mul_ex3;

    logic [EX1_W-1:0] result_div_ex1;
    logic [EX2_W-1:0] result_div_ex2;
    logic [EX3_W-1:0] result_div_ex3;
    logic [EX4_W-1:0] result_div_ex4;

    logic [EX1_W-1:0] result_rdc_ex1;
    logic [EX2_W-1:0] result_rdc_ex2;
    logic [EX3_W-1:0] result_rdc_ex3;
    logic [EX4_W-1:0] result_rdc_ex4;

    assign data_a_u_ex1 = $unsigned(data_a_ex1_i);
    assign data_b_u_ex1 = $unsigned(data_b_ex1_i);

    assign data_a_s_ex1 = $signed(data_a_ex1_i);
    assign data_b_s_ex1 = $signed(data_b_ex1_i);

    assign data_a_wu_ex1 = {{16{1'b0}},data_a_u_ex1[15:0]};
    assign data_b_wu_ex1 = {{16{1'b0}},data_b_u_ex1[15:0]};

    assign is_multi_cycle = (funct3_i == funct3_opmvv_c) || (funct3_i == funct3_opmvx_c) ? 1'b1 : 1'b0;
    assign is_single_cycle = ~is_multi_cycle & valid_i;

    //================================================
    // INT Section (no mul/div)
    //================================================
    logic [DATA_WIDTH-1:0] result_int;
    always_comb begin
        case (funct6_i)
            // vadd.vv, vadd.vx, vadd.vi
            funct6_vadd_c : begin
                result_int    = data_a_u_ex1 + data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vsub.vv, vsub.vx
            funct6_vsub_c : begin
                result_int    = data_b_u_ex1 - data_a_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vrsub.vx, vrsub.vi
            funct6_vrsub_c : begin
                result_int    = data_a_u_ex1 - data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vand.vv, vand.vx, vand.vi
            funct6_vand_c : begin
                result_int    = data_a_u_ex1 & data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vor.vv, vor.vx, vor.vi
            funct6_vor_c : begin
                result_int    = data_a_u_ex1 | data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vxor.vv, vxor.vx, vxor.vi
            funct6_vxor_c : begin
                result_int    = data_a_u_ex1 ^ data_b_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vsll.vv, vsll.vx, vsll.vi
            funct6_vsll_c : begin
                result_int    = data_b_u_ex1 << data_a_u_ex1[4:0];
                valid_int_ex1 = is_single_cycle;
            end
            // vsrl.vv, vsrl.vx, vsrl.vi
            funct6_vsrl_c : begin
                result_int    = data_b_u_ex1 >> data_a_u_ex1[4:0];
                valid_int_ex1 = is_single_cycle;
            end
            // vsra.vv, vsra.vx, vsra.vi
            funct6_vsra_c : begin
                result_int    = $signed(data_b_ex1_i) >>> data_a_u_ex1[4:0];
                valid_int_ex1 = is_single_cycle;
            end
            // vminu.vv, vminu.vx
            funct6_vminu_c : begin
                result_int    = (data_b_u_ex1 < data_a_u_ex1) ? data_b_u_ex1 : data_a_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vmin.vv, vmin.vx
            funct6_vmin_c : begin
                result_int    = ($signed(data_b_ex1_i) < $signed(data_a_ex1_i)) ? data_b_ex1_i : data_a_ex1_i;
                valid_int_ex1 = is_single_cycle;
            end
            // vmaxu.vv, vmaxu.vx
            funct6_vmaxu_c : begin
                result_int    = (data_b_u_ex1 > data_a_u_ex1) ? data_b_u_ex1 : data_a_u_ex1;
                valid_int_ex1 = is_single_cycle;
            end
            // vmax.vv, vmax.vx
            funct6_vmax_c : begin
                result_int    = ($signed(data_b_ex1_i) > $signed(data_a_ex1_i)) ? data_b_ex1_i : data_a_ex1_i;
                valid_int_ex1 = is_single_cycle;
            end
            // vmv.v.v, vmv.v.x, vmv.v.i
            funct6_vmv_c : begin
                result_int    = data_a_ex1_i;
                valid_int_ex1 = is_single_cycle;
            end
            // unknown funct6
            default : begin
                result_int    = 'x;
                valid_int_ex1 = 1'b0;
            end
        endcase
    end
    assign result_int_ex1 = {{EX1_W-DATA_WIDTH{1'b0}},result_int};
    //================================================
    // MUL Section
    //================================================
    logic                    diff_type      ;
    logic                    upper_part     ;
    logic                    upper_part_ex2 ;
    logic                    upper_part_ex3 ;
    logic                    sign_mul_ex1   ;
    logic                    sign_ex2       ;
    logic                    sign_ex3       ;
    logic                    valid_mul      ;

    assign valid_mul = is_multi_cycle & valid_i;

    always_comb begin
        case (funct6_i)
            funct6_vmul_c : begin
                // VMUL
                sign_mul_ex1  = 1'b1;
                valid_mul_ex1 = valid_mul;
                diff_type     = 1'b0;
                upper_part    = 1'b0;
            end
            funct6_vmulh_c : begin
                // VMULH
                sign_mul_ex1  = 1'b1;
                valid_mul_ex1 = valid_mul;
                diff_type     = 1'b0;
                upper_part    = 1'b1;
            end
            funct6_vmulhsu_c : begin
                // VMULHSU
                sign_mul_ex1  = 1'b0;
                valid_mul_ex1 = valid_mul;
                diff_type     = 1'b1;
                upper_part    = 1'b1;
            end
            funct6_vmulhu_c : begin
                // VMULHU
                sign_mul_ex1  = 1'b0;
                valid_mul_ex1 = valid_mul;
                diff_type     = 1'b0;
                upper_part    = 1'b1;
            end
            default : begin
                sign_mul_ex1  = 1'bx;
                valid_mul_ex1 = 1'b0;
                diff_type     = 1'bx;
                upper_part    = 1'bx;
            end
        endcase
    end

    // ===============================================
    // MUL: EX1
    // ===============================================
    logic [DATA_WIDTH-1+8:0] part_1, part_2, part_3, part_4;
    logic [  DATA_WIDTH-1:0] data_a, data_b;

    assign data_a         = (sign_mul_ex1 && data_a_ex1_i[31]) ? ~data_a_ex1_i + 1'b1 : data_a_ex1_i;
    assign data_b         = ((sign_mul_ex1 || (funct6_i == funct6_vmulhsu_c)) && data_b_ex1_i[31]) ? ~data_b_ex1_i + 1'b1 : data_b_ex1_i;
    
    //Create Partial Products
    assign part_1         = data_a * data_b[07:00];
    assign part_2         = data_a * data_b[15:08];
    assign part_3         = data_a * data_b[23:16];
    assign part_4         = data_a * data_b[31:24];
    assign result_mul_ex1 = {part_4, part_3, part_2, part_1};

    // Sign and Upper part for next stage
    always_ff @(posedge clk) begin
        if (valid_mul_ex1) begin
            sign_ex2       <= diff_type ? data_b_ex1_i[31] : sign_mul_ex1 & (data_a_ex1_i[31] ^ data_b_ex1_i[31]);
            upper_part_ex2 <= upper_part;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_mul_ex2 <= 0;
        end else begin
            valid_mul_ex2 <= valid_mul_ex1;
        end
    end

    // ===============================================
    // MUL: EX2
    // ===============================================
    logic [2*DATA_WIDTH-1:0] extended_1,extended_2,extended_3,extended_4;
    logic [DATA_WIDTH-1+8:0] part_1_ex2, part_2_ex2, part_3_ex2, part_4_ex2;
    logic [2*DATA_WIDTH-1:0] extended_sum;

    assign part_1_ex2   = data_ex2_i[0               +: PARTIAL_SUM_W];
    assign part_2_ex2   = data_ex2_i[PARTIAL_SUM_W   +: PARTIAL_SUM_W];
    assign part_3_ex2   = data_ex2_i[2*PARTIAL_SUM_W +: PARTIAL_SUM_W];
    assign part_4_ex2   = data_ex2_i[3*PARTIAL_SUM_W +: PARTIAL_SUM_W];
    assign extended_1   = {{24{1'b0}}, part_1_ex2};
    assign extended_2   = {{16{1'b0}}, part_2_ex2, {08{1'b0}}};
    assign extended_3   = {{08{1'b0}}, part_3_ex2, {16{1'b0}}};
    assign extended_4   = {part_4_ex2, {24{1'b0}}};
    assign extended_sum = extended_1 + extended_2 + extended_3 + extended_4;

    assign result_mul_ex2 = {{EX2_W-2*DATA_WIDTH{1'b0}}, extended_sum};

    always_ff @(posedge clk) begin
        if (valid_mul_ex2) begin
            sign_ex3       <= sign_ex2;
            upper_part_ex3 <= upper_part_ex2;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_mul_ex3 <= 0;
        end else begin
            valid_mul_ex3 <= valid_mul_ex2;
        end
    end

    // ===============================================
    // MUL:EX3
    // ===============================================
    logic [2*DATA_WIDTH-1:0] result_ex3_temp;
    logic [2*DATA_WIDTH-1:0] result_mul_wide;

    assign result_ex3_temp = data_ex3_i[0 +: 2*DATA_WIDTH];
    assign result_mul_wide = sign_ex3 ?  ~result_ex3_temp + 1'b1 : result_ex3_temp;
    assign result_mul_ex3  = upper_part_ex3 ? {{EX3_W-DATA_WIDTH{1'b0}},result_mul_wide[DATA_WIDTH +: DATA_WIDTH]} :
                                              {{EX3_W-DATA_WIDTH{1'b0}},result_mul_wide[0          +: DATA_WIDTH]};
    // ================================================
    // DIV Section
    // ================================================
    logic sign_div_ex1, is_rem_ex1;
    logic sign_div_ex2, sign_res_div_ex2, is_rem_ex2;
    logic sign_div_ex3, sign_res_div_ex3, is_rem_ex3;
    logic sign_div_ex4, sign_res_div_ex4, is_rem_ex4;
    logic valid_div;

    assign valid_div = is_multi_cycle & valid_i;

    always_comb begin
        case (funct6_i)
            funct6_vdiv_c : begin
                // VDIV
                valid_div_ex1 = valid_div;
                sign_div_ex1  = 1'b1;
                is_rem_ex1    = 1'b0;
            end
            funct6_vdivu_c : begin
                // VDIVU
                valid_div_ex1 = valid_div;
                sign_div_ex1  = 1'b0;
                is_rem_ex1    = 1'b0;
            end
            funct6_vrem_c : begin
                // VREM
                valid_div_ex1 = valid_div;
                sign_div_ex1  = 1'b1;
                is_rem_ex1    = 1'b1;
            end
            funct6_vremu_c : begin
                // VREMU
                valid_div_ex1 = valid_div;
                sign_div_ex1  = 1'b0;
                is_rem_ex1    = 1'b1;
            end
            default : begin
                valid_div_ex1 = 1'b0;
                sign_div_ex1  = 1'bx;
                is_rem_ex1    = 1'bx;
            end
        endcase
    end

    // ===============================================
    // DIV: EX1 Non-restoring Division
    // ===============================================
    logic [DATA_WIDTH-1:0] dividend, divider;
    logic [DATA_WIDTH-1:0] remainder_init_ex1, quotient_init_ex1, divider_init_ex1;
    logic [DATA_WIDTH-1:0] remainder_ex1, quotient_ex1;
    logic [  DATA_WIDTH:0] diff_ex1;

    assign dividend = data_b_ex1_i;
    assign divider  = data_a_ex1_i;

    assign quotient_init_ex1  = (sign_div_ex1 && dividend[31]) ? ~dividend + 1'b1 : dividend;
    assign remainder_init_ex1 = '0;
    assign divider_init_ex1   = (sign_div_ex1 && divider[31])  ? ~divider + 1'b1 : divider;

    always_comb begin : division_ex1
        remainder_ex1 = {remainder_init_ex1[DATA_WIDTH-2:0], quotient_init_ex1[DATA_WIDTH-1]};
        quotient_ex1  = quotient_init_ex1 << 1;
        diff_ex1      = remainder_ex1 - divider_init_ex1;
        //
        if(diff_ex1[DATA_WIDTH] == 1) begin
            quotient_ex1[0] = 0;
        end else begin
            quotient_ex1[0] = 1;
            remainder_ex1   = remainder_ex1 - divider_init_ex1;
        end
        //
        repeat (DIV_BIT_GROUPS-1) begin
            remainder_ex1 = {remainder_ex1[DATA_WIDTH-2:0], quotient_ex1[DATA_WIDTH-1]};
            quotient_ex1  = quotient_ex1 << 1;
            diff_ex1      = remainder_ex1 - divider_init_ex1;
            if(diff_ex1[DATA_WIDTH] == 1) begin
                quotient_ex1[0] = 0;
            end else begin
                quotient_ex1[0] = 1;
                remainder_ex1   = remainder_ex1 - divider_init_ex1;
            end
        end
    end : division_ex1

    assign result_div_ex1 = {{EX1_W-3*DATA_WIDTH{1'b0}}, quotient_ex1, remainder_ex1, divider_init_ex1};

    always_ff @(posedge clk) begin
        if (valid_div_ex1) begin
            sign_div_ex2     <= sign_div_ex1 & dividend[31];
            sign_res_div_ex2 <= sign_div_ex1 & (dividend[31] ^ divider[31]);
            is_rem_ex2       <= is_rem_ex1;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_div_ex2 <= 0;
        end else begin
            valid_div_ex2 <= valid_div_ex1;
        end
    end
    // ===============================================
    // DIV: EX2 Non-restoring Division
    // ===============================================
    logic [DATA_WIDTH-1:0] remainder_init_ex2, quotient_init_ex2, divider_init_ex2;
    logic [DATA_WIDTH-1:0] remainder_ex2, quotient_ex2;
    logic [  DATA_WIDTH:0] diff_ex2;

    assign divider_init_ex2   = data_ex2_i[0            +: DATA_WIDTH];
    assign remainder_init_ex2 = data_ex2_i[DATA_WIDTH   +: DATA_WIDTH];
    assign quotient_init_ex2  = data_ex2_i[2*DATA_WIDTH +: DATA_WIDTH];

    always_comb begin : division_ex2
        remainder_ex2 = {remainder_init_ex2[DATA_WIDTH-2:0], quotient_init_ex2[DATA_WIDTH-1]};
        quotient_ex2  = quotient_init_ex2 << 1;
        diff_ex2      = remainder_ex2 - divider_init_ex2;
        //
        if(diff_ex2[DATA_WIDTH] == 1) begin
            quotient_ex2[0] = 0;
        end else begin
            quotient_ex2[0] = 1;
            remainder_ex2   = remainder_ex2 - divider_init_ex2;
        end
        //
        repeat (DIV_BIT_GROUPS-1) begin
            remainder_ex2 = {remainder_ex2[DATA_WIDTH-2:0], quotient_ex2[DATA_WIDTH-1]};
            quotient_ex2  = quotient_ex2 << 1;
            diff_ex2      = remainder_ex2 - divider_init_ex2;
            if(diff_ex2[DATA_WIDTH] == 1) begin
                quotient_ex2[0] = 0;
            end else begin
                quotient_ex2[0] = 1;
                remainder_ex2   = remainder_ex2 - divider_init_ex2;
            end
        end
    end : division_ex2

    assign result_div_ex2 = {{EX2_W-3*DATA_WIDTH{1'b0}}, quotient_ex2, remainder_ex2, divider_init_ex2};

    always_ff @(posedge clk) begin
        if (valid_div_ex2) begin
            sign_div_ex3     <= sign_div_ex2;
            sign_res_div_ex3 <= sign_res_div_ex2;
            is_rem_ex3       <= is_rem_ex2;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_div_ex3 <= 0;
        end else begin
            valid_div_ex3 <= valid_div_ex2;
        end
    end
    // ===============================================
    // DIV: EX3 Non-restoring Division
    // ===============================================
    logic [DATA_WIDTH-1:0] remainder_init_ex3, quotient_init_ex3, divider_init_ex3;
    logic [DATA_WIDTH-1:0] remainder_ex3, quotient_ex3;
    logic [  DATA_WIDTH:0] diff_ex3;

    assign divider_init_ex3   = data_ex3_i[0            +: DATA_WIDTH];
    assign remainder_init_ex3 = data_ex3_i[DATA_WIDTH   +: DATA_WIDTH];
    assign quotient_init_ex3  = data_ex3_i[2*DATA_WIDTH +: DATA_WIDTH];

    always_comb begin : division_ex3
        remainder_ex3 = {remainder_init_ex3[DATA_WIDTH-2:0], quotient_init_ex3[DATA_WIDTH-1]};
        quotient_ex3  = quotient_init_ex3 << 1;
        diff_ex3      = remainder_ex3 - divider_init_ex3;
        //
        if(diff_ex3[DATA_WIDTH] == 1) begin
            quotient_ex3[0] = 0;
        end else begin
            quotient_ex3[0] = 1;
            remainder_ex3   = remainder_ex3 - divider_init_ex3;
        end
        //
        repeat (DIV_BIT_GROUPS-1) begin
            remainder_ex3 = {remainder_ex3[DATA_WIDTH-2:0], quotient_ex3[DATA_WIDTH-1]};
            quotient_ex3  = quotient_ex3 << 1 ;
            diff_ex3      = remainder_ex3 - divider_init_ex3;
            if(diff_ex3[DATA_WIDTH] == 1) begin
                quotient_ex3[0] = 0;
            end else begin
                quotient_ex3[0] = 1;
                remainder_ex3   = remainder_ex3 - divider_init_ex3;
            end
        end
    end : division_ex3

    assign result_div_ex3 = {{EX3_W-3*DATA_WIDTH{1'b0}}, quotient_ex3, remainder_ex3, divider_init_ex3};

    always_ff @(posedge clk) begin
        if (valid_div_ex3) begin
            sign_div_ex4     <= sign_div_ex3;
            sign_res_div_ex4 <= sign_res_div_ex3;
            is_rem_ex4       <= is_rem_ex3;
        end
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            valid_div_ex4 <= 0;
        end else begin
            valid_div_ex4 <= valid_div_ex3;
        end
    end
    // ===============================================
    // DIV: EX4 Non-restoring Division
    // ===============================================
    logic [DATA_WIDTH-1:0] remainder_init_ex4, quotient_init_ex4, divider_init_ex4;
    logic [DATA_WIDTH-1:0] remainder_ex4, quotient_ex4;
    logic [DATA_WIDTH-1:0] remainder_final, result_final;
    logic [  DATA_WIDTH:0] diff_ex4;

    assign divider_init_ex4   = data_ex4_i[0            +: DATA_WIDTH];
    assign remainder_init_ex4 = data_ex4_i[DATA_WIDTH   +: DATA_WIDTH];
    assign quotient_init_ex4  = data_ex4_i[2*DATA_WIDTH +: DATA_WIDTH];

    always_comb begin : division_ex4
        remainder_ex4 = {remainder_init_ex4[DATA_WIDTH-2:0], quotient_init_ex4[DATA_WIDTH-1]};
        quotient_ex4  = quotient_init_ex4 << 1;
        diff_ex4      = remainder_ex4 - divider_init_ex4;
        //
        if(diff_ex4[DATA_WIDTH] == 1) begin
            quotient_ex4[0] = 0;
        end else begin
            quotient_ex4[0] = 1;
            remainder_ex4   = remainder_ex4 - divider_init_ex4;
        end
        //
        repeat (DIV_BIT_GROUPS-1) begin
            remainder_ex4 = {remainder_ex4[DATA_WIDTH-2:0], quotient_ex4[DATA_WIDTH-1]};
            quotient_ex4  = quotient_ex4 << 1;
            diff_ex4      = remainder_ex4 - divider_init_ex4;
            if(diff_ex4[DATA_WIDTH] == 1) begin
                quotient_ex4[0] = 0;
            end else begin
                quotient_ex4[0] = 1;
                remainder_ex4   = remainder_ex4 - divider_init_ex4;
            end
        end
    end : division_ex4

    assign remainder_final = sign_div_ex4     ? ~remainder_ex4 + 1'b1 : remainder_ex4;
    assign result_final    = sign_res_div_ex4 ? ~quotient_ex4 + 1'b1  : quotient_ex4;
    assign result_div_ex4  = is_rem_ex4       ? {{EX4_W-DATA_WIDTH{1'b0}}, remainder_final} :
                                                {{EX4_W-DATA_WIDTH{1'b0}}, result_final};


    //================================================
    // Reduction Tree Section
    //================================================
    // Lane 0 ─┐
    //      ├─ EX1 ─┐
    // Lane 1 ─┘    │
    //              ├─ EX2 ─┐
    // Lane 2 ─┐    │       │
    //      ├─ EX1 ─┘       │
    // Lane 3 ─┘            ├─ EX3 ─────┬──── EX4 ===> Final Result
    //                      │           │ 
    // Lane 4 ─┐            │           │ 
    //      ├─ EX1 ─┐       │           │ 
    // Lane 5 ─┘    │       │           │ 
    //              ├─ EX2 ─┘           │ 
    // Lane 6 ─┐    │                   │ 
    //      ├─ EX1 ─┘                   │ 
    // Lane 7 ─┘                        │ 
    // .....   ─────────────────────────┘

    // ===============================================
    // RDC:EX1
    // ===============================================
    logic [$clog2(VECTOR_REGISTERS*VECTOR_LANES):0] vl_ex2, vl_ex3, vl_ex4;
    logic [                         DATA_WIDTH-1:0] tree_result_ex1, tree_result_ex2;
    logic [                         DATA_WIDTH-1:0] tree_result_ex3, tree_result_ex4;
    logic [                                    5:0] rdc_op_ex1, rdc_op_ex2, rdc_op_ex3, rdc_op_ex4;

    logic active_rdc_ex1, active_rdc_ex2, active_rdc_ex3, active_rdc_ex4;
    logic valid_rdc_ex1, valid_rdc_ex2, valid_rdc_ex3, valid_rdc_ex4;

    generate if (!VECTOR_LANE_NUM[0]) begin: g_rdc_ex1
        logic odd_rdc_override;
        // If the vector has an odd number of elements,
        // the last lane has no pairs to merge.
        assign odd_rdc_override = ((vl_i - 1) == VECTOR_LANE_NUM);
        always_comb begin
            case (funct6_i)
                funct6_vredsum_c : begin
                    // VRADD
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i + rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredsum_c;
                end
                funct6_vredand_c : begin
                    // VRAND
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i & rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredand_c;
                end
                funct6_vredor_c : begin
                    // VROR
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i | rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredor_c;
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i : (data_b_ex1_i ^ rdc_data_ex1_i);
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredxor_c;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      (data_b_u_ex1 < rdc_data_ex1_i) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredminu_c;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      ($signed(data_b_ex1_i) < $signed(rdc_data_ex1_i)) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredmin_c;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      (data_b_u_ex1 > rdc_data_ex1_i) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredmaxu_c;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex1 = odd_rdc_override ? data_b_ex1_i :
                                      ($signed(data_b_ex1_i) > $signed(rdc_data_ex1_i)) ? data_b_ex1_i : rdc_data_ex1_i;
                    active_rdc_ex1  = is_rdc_i;
                    valid_rdc_ex1   = valid_i & ((vl_i <= 'd2) | (vl_i > 'd2 & VECTOR_LANES == 2));
                    rdc_op_ex1      = funct6_vredmax_c;
                end
                default : begin
                    tree_result_ex1 = 'x;
                    active_rdc_ex1  = 1'b0;
                    valid_rdc_ex1   = 1'b0;
                    rdc_op_ex1      = 'x;
                end
            endcase
        end

        assign result_rdc_ex1 = {{EX1_W-DATA_WIDTH{1'b0}}, tree_result_ex1};
        always_ff @(posedge clk) begin
            if (active_rdc_ex1) begin
                rdc_op_ex2 <= rdc_op_ex1;
            end
        end

    end else begin: g_rdc_ex1_stubs
        assign active_rdc_ex1 = 1'b0;
        assign valid_rdc_ex1  = 1'b0;
    end endgenerate
    // ===============================================
    // RDC:EX2
    // ===============================================
    generate if (VECTOR_LANES > 2 & VECTOR_LANE_NUM[1:0] == 2'b00) begin: g_rdc_ex2
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                active_rdc_ex2 <= 1'b0;
            end else begin
                active_rdc_ex2 <= active_rdc_ex1;
                vl_ex2         <= vl_i;
            end
        end

        assign valid_rdc_ex2  = active_rdc_ex2 & (
                                (vl_ex2 <= 'd4)  |
                                (vl_ex2 > 'd4 & VECTOR_LANES == 4));
        // EX2 outputs
        always_comb begin
            case (rdc_op_ex2)
                funct6_vredsum_c : begin
                    // VRADD
                    tree_result_ex2 = data_ex2_i[0 +: DATA_WIDTH] + rdc_data_ex2_i;
                end
                funct6_vredand_c : begin
                    // VRAND
                    tree_result_ex2 = data_ex2_i[0 +: DATA_WIDTH] & rdc_data_ex2_i;
                end
                funct6_vredor_c : begin
                    // VROR
                    tree_result_ex2 = data_ex2_i[0 +: DATA_WIDTH] | rdc_data_ex2_i;
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    tree_result_ex2 = data_ex2_i[0 +: DATA_WIDTH] ^ rdc_data_ex2_i;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex2 = (data_ex2_i[0 +: DATA_WIDTH] < rdc_data_ex2_i) ? data_ex2_i[0 +: DATA_WIDTH] : rdc_data_ex2_i;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex2 = ($signed(data_ex2_i[0 +: DATA_WIDTH]) < $signed(rdc_data_ex2_i)) ? data_ex2_i[0 +: DATA_WIDTH] : rdc_data_ex2_i;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex2 = (data_ex2_i[0 +: DATA_WIDTH] > rdc_data_ex2_i) ? data_ex2_i[0 +: DATA_WIDTH] : rdc_data_ex2_i;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex2 = ($signed(data_ex2_i[0 +: DATA_WIDTH]) > $signed(rdc_data_ex2_i)) ? data_ex2_i[0 +: DATA_WIDTH] : rdc_data_ex2_i;
                end
                default : begin
                    tree_result_ex2 = 'x;
                end
            endcase
        end

        assign result_rdc_ex2 = {{EX2_W-DATA_WIDTH{1'b0}}, tree_result_ex2};

        always_ff @(posedge clk) begin
            if (active_rdc_ex2) begin
                rdc_op_ex3 <= rdc_op_ex2;
            end
        end

    end else begin: g_rdc_ex2_stubs
        assign active_rdc_ex2 = 1'b0;
        assign valid_rdc_ex2  = 1'b0;
    end endgenerate
    // ===============================================
    // RDC:EX3
    // ===============================================
    generate if (VECTOR_LANES > 4 & VECTOR_LANE_NUM[2:0] == 3'b000) begin: g_rdc_ex3
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                active_rdc_ex3 <= 0;
            end else begin
                active_rdc_ex3 <= active_rdc_ex2;
                vl_ex3         <= vl_ex2;
            end
        end

        assign valid_rdc_ex3  = active_rdc_ex3 & (
                                (vl_ex3 <= 'd8)  |
                                (vl_ex3 > 'd8 & VECTOR_LANES == 8));
        // EX3 outputs
        always_comb begin
            case (rdc_op_ex3)
                funct6_vredsum_c : begin
                    // VRADD
                    tree_result_ex3 = data_ex3_i[0 +: DATA_WIDTH] + rdc_data_ex3_i;
                end
                funct6_vredand_c: begin
                    // VRAND
                    tree_result_ex3 = data_ex3_i[0 +: DATA_WIDTH] & rdc_data_ex3_i;
                end
                funct6_vredor_c: begin
                    // VROR
                    tree_result_ex3 = data_ex3_i[0 +: DATA_WIDTH] | rdc_data_ex3_i;
                end
                funct6_vredxor_c: begin
                    // VRXOR
                    tree_result_ex3 = data_ex3_i[0 +: DATA_WIDTH] ^ rdc_data_ex3_i;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex3 = (data_ex3_i[0 +: DATA_WIDTH] < rdc_data_ex3_i) ? data_ex3_i[0 +: DATA_WIDTH] : rdc_data_ex3_i;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex3 = ($signed(data_ex3_i[0 +: DATA_WIDTH]) < $signed(rdc_data_ex3_i)) ? data_ex3_i[0 +: DATA_WIDTH] : rdc_data_ex3_i;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex3 = (data_ex3_i[0 +: DATA_WIDTH] > rdc_data_ex3_i) ? data_ex3_i[0 +: DATA_WIDTH] : rdc_data_ex3_i;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex3 = ($signed(data_ex3_i[0 +: DATA_WIDTH]) > $signed(rdc_data_ex3_i)) ? data_ex3_i[0 +: DATA_WIDTH] : rdc_data_ex3_i;
                end
                default : begin
                    tree_result_ex3 = 'x;
                end
            endcase
        end

        assign result_rdc_ex3 = {{EX3_W-DATA_WIDTH{1'b0}}, tree_result_ex3};

        always_ff @(posedge clk) begin
            if (active_rdc_ex3) begin
                rdc_op_ex4 <= rdc_op_ex3;
            end
        end

    end else begin: g_rdc_ex3_stubs
        assign active_rdc_ex3 = 1'b0;
        assign valid_rdc_ex3  = 1'b0;
    end endgenerate
    // ===============================================
    // RDC:EX4
    // ===============================================
    generate if (VECTOR_LANES > 8 & VECTOR_LANE_NUM[3:0] == 4'b0000) begin: g_rdc_ex4
        always_ff @(posedge clk or negedge rst_n) begin
            if(!rst_n) begin
                active_rdc_ex4 <= 0;
            end else begin
                active_rdc_ex4 <= active_rdc_ex3;
                vl_ex4         <= vl_ex3;
            end
        end
        // EX4 outputs
        assign valid_rdc_ex4  = active_rdc_ex4 & (
                                (vl_ex4 <= 'd16)  |
                                (vl_ex4 > 'd16 & VECTOR_LANES == 16));

        always_comb begin
            case (rdc_op_ex4)
                funct6_vredsum_c  : begin
                    // VRADD
                    tree_result_ex4 = data_ex4_i[0 +: DATA_WIDTH] + rdc_data_ex4_i;
                end
                funct6_vredand_c : begin
                    // VRAND
                    tree_result_ex4 = data_ex4_i[0 +: DATA_WIDTH] & rdc_data_ex4_i;
                end
                funct6_vredor_c : begin
                    // VROR
                    tree_result_ex4 = data_ex4_i[0 +: DATA_WIDTH] | rdc_data_ex4_i;
                end
                funct6_vredxor_c : begin
                    // VRXOR
                    tree_result_ex4 = data_ex4_i[0 +: DATA_WIDTH] ^ rdc_data_ex4_i;
                end
                funct6_vredminu_c : begin
                    // VRMINU
                    tree_result_ex4 = (data_ex4_i[0 +: DATA_WIDTH] < rdc_data_ex4_i) ? data_ex4_i[0 +: DATA_WIDTH] : rdc_data_ex4_i;
                end
                funct6_vredmin_c : begin
                    // VRMIN
                    tree_result_ex4 = ($signed(data_ex4_i[0 +: DATA_WIDTH]) < $signed(rdc_data_ex4_i)) ? data_ex4_i[0 +: DATA_WIDTH] : rdc_data_ex4_i;
                end
                funct6_vredmaxu_c : begin
                    // VRMAXU
                    tree_result_ex4 = (data_ex4_i[0 +: DATA_WIDTH] > rdc_data_ex4_i) ? data_ex4_i[0 +: DATA_WIDTH] : rdc_data_ex4_i;
                end
                funct6_vredmax_c : begin
                    // VRMAX
                    tree_result_ex4 = ($signed(data_ex4_i[0 +: DATA_WIDTH]) > $signed(rdc_data_ex4_i)) ? data_ex4_i[0 +: DATA_WIDTH] : rdc_data_ex4_i;
                end
                default : begin
                    tree_result_ex4 = 'x;
                end
            endcase
        end
        
        assign result_rdc_ex4 = {{EX4_W-DATA_WIDTH{1'b0}}, tree_result_ex4};

    end else begin: g_rdc_ex4_stubs
        assign active_rdc_ex4 = 1'b0;
    end endgenerate


    //================================================
    // Outputs
    //================================================

    // EX1 Out
    assign ready_res_ex1_o = valid_int_ex1  | valid_rdc_ex1;   //indicate ready result
    assign result_ex1_o    = active_rdc_ex1 ? result_rdc_ex1 :
                             ~mask_i        ? '0             :
                             valid_int_ex1  ? result_int_ex1 :
                             valid_mul_ex1  ? result_mul_ex1 :
                             valid_div_ex1  ? result_div_ex1 : 'x;
    // EX2 Out
    assign ready_res_ex2_o = valid_rdc_ex2;                   //indicate ready result
    assign result_ex2_o    = active_rdc_ex2 ? result_rdc_ex2 :
                             ~mask_ex2_i    ? '0             :
                             valid_mul_ex2  ? result_mul_ex2 :
                             valid_div_ex2  ? result_div_ex2 : 'x;
    // EX3 Out
    assign ready_res_ex3_o = valid_mul_ex3  | valid_rdc_ex3;   //indicate ready result
    assign result_ex3_o    = active_rdc_ex3 ? result_rdc_ex3 :
                             ~mask_ex3_i    ? '0             :
                             valid_mul_ex3  ? result_mul_ex3 :
                             valid_div_ex3  ? result_div_ex3 : 'x;
    // EX4 Out
    assign rdc_op_ex4_o    = rdc_op_ex4;
    assign ready_res_ex4_o = valid_div_ex4  | valid_rdc_ex4;   //indicate ready result
    assign result_ex4_o    = active_rdc_ex4 ? result_rdc_ex4 :
                             ~mask_ex4_i    ? '0             : result_div_ex4;
    
    // EX5 Out
    //assign rdc_op_ex5_o    = rdc_op_ex5;
    //assign ready_res_ex5_o = valid_div_ex5  | valid_rdc_ex5;   //indicate ready result
    //assign result_ex5_o    = active_rdc_ex5 ? result_rdc_ex5 :
    //                         ~mask_ex5_i    ? '0             : result_div_ex5;

endmodule