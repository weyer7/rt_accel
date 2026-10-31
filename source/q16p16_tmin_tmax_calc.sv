`default_nettype none
`include "rtu_pkg.svh"
`define MULT_OPT

module q16p16_tmin_tmax_calc (
    input logic clk, n_rst,

    //============================
    //input interface
    //============================

    //signals to bypass
    input logic [31:0] request_tmax_i, request_tmin_i,
    //signals to operate on
    input logic [31:0] corner_a, corner_b, //aabb bounds for one dimension
    input logic [31:0] ray_origin, inv_dir,
    input logic dir_eq_zero,
    //handshake
    input logic valid_i,
    output logic ready_o,

    //============================
    //output interface
    //============================

    //bypassed signals
    output logic [31:0] request_tmax_o, request_tmin_o,
    //result signals
    output logic [31:0] tmin_o, tmax_o,
    //handshake
    output logic valid_o,
    input logic ready_i

    //consider adding overflow
);

    //stall logic
    logic stall;
    assign stall = !ready_i && valid_o; //not optimal, but for now stall entire pipe when downstream not ready

    //============================
    // Zero-direction handling
    //============================

    // If direction is zero, the ray is parallel to this slab.
    // If the origin is outside the slab, this axis is a definite miss.
    logic parallel_miss;

    assign parallel_miss = dir_eq_zero &&
                           (($signed(ray_origin) < $signed(corner_a)) ||
                            ($signed(ray_origin) > $signed(corner_b)));

    //============================
    //operations to perform
    //============================
    //1) amo = corner_a - ray_origin
    //2) bmo = corner_b - ray_origin
    //3) t0 = amo * inv_dir
    //4) t1 = bmo * inv_dir
    //5) tmin = max(t0, t1)
    //6) tmax = min(t0, t1)

    //1
    logic [31:0] amo;
    logic amo_valid, t0_ready;
    q16p16_sub a_minus_o_calc (
        .*, 
        .operand_a(corner_a), 
        .operand_b(ray_origin),
        .ready_o(ready_o), 
        .valid_i(valid_i),
        .sum(amo), 
        .valid_o(amo_valid), 
        .ready_i(t0_ready)
    );

    //2
    logic [31:0] bmo;
    logic bmo_valid, t1_ready;
    q16p16_sub b_minus_o_calc (
        .*, 
        .operand_a(corner_b), 
        .operand_b(ray_origin),
        .ready_o(), 
        .valid_i(valid_i),
        .sum(bmo), 
        .valid_o(bmo_valid), 
        .ready_i(t1_ready)
    );

    //bypass reg for signals passing over steps 1 and 2
    //the adders have two pipe stages
    logic [31:0] req_tmax0, req_tmax1;
    logic [31:0] req_tmin0, req_tmin1;
    logic [31:0] inv_dir0, inv_dir1;
    logic parallel_miss0, parallel_miss1;
    logic dir_eq_zero0, dir_eq_zero1;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax0 <= '0;
            req_tmax1 <= '0;
            req_tmin0 <= '0;
            req_tmin1 <= '0;
            inv_dir0 <= '0;
            inv_dir1 <= '0;
            parallel_miss0 <= 1'b0;
            parallel_miss1 <= 1'b0;
            dir_eq_zero0 <= 1'b0;
            dir_eq_zero1 <= 1'b0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax0 <= request_tmax_i;
            req_tmax1 <= req_tmax0;
            req_tmin0 <= request_tmin_i;
            req_tmin1 <= req_tmin0;
            inv_dir0 <= inv_dir;
            inv_dir1 <= inv_dir0;
            parallel_miss0 <= parallel_miss;
            parallel_miss1 <= parallel_miss0;
            dir_eq_zero0 <= dir_eq_zero;
            dir_eq_zero1 <= dir_eq_zero0;
        end
    end

`ifdef MULT_OPT

    //3
    logic [31:0] t0;
    logic t0_valid;
    logic comp_ready;
    q16p16_mult_opt t0_calc (
        .*, 
        .operand_a(amo), 
        .operand_b(inv_dir1),
        .ready_o(t0_ready), 
        .valid_i(amo_valid), 
        .product(t0), 
        .valid_o(t0_valid), 
        .ready_i(comp_ready)
    );

    //4
    logic [31:0] t1;
    logic t1_valid;
    q16p16_mult_opt t1_calc (
        .*, 
        .operand_a(bmo), 
        .operand_b(inv_dir1),
        .ready_o(t1_ready), 
        .valid_i(bmo_valid), 
        .product(t1), 
        .valid_o(), 
        .ready_i(comp_ready)
    );

    //bypass reg for signals passing over steps 3 and 4
    //the multipliers also have two pipe stages
    logic [31:0] req_tmax2, req_tmax3, req_tmax4, req_tmax5,
                 req_tmax6, req_tmax7, req_tmax8, req_tmax9,
                 req_tmax10, req_tmax11, req_tmax12;
    logic [31:0] req_tmin2, req_tmin3, req_tmin4, req_tmin5,
                 req_tmin6, req_tmin7, req_tmin8, req_tmin9,
                 req_tmin10, req_tmin11, req_tmin12;

    logic parallel_miss2, parallel_miss3, parallel_miss4,
          parallel_miss5, parallel_miss6, parallel_miss7,
          parallel_miss8, parallel_miss9, parallel_miss10,
          parallel_miss11, parallel_miss12;

    logic dir_eq_zero2, dir_eq_zero3, dir_eq_zero4,
          dir_eq_zero5, dir_eq_zero6, dir_eq_zero7,
          dir_eq_zero8, dir_eq_zero9, dir_eq_zero10,
          dir_eq_zero11, dir_eq_zero12;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax2 <= '0; 
            req_tmax3 <= '0; 
            req_tmax4 <= '0; 
            req_tmax5 <= '0; 
            req_tmax6 <= '0; 
            req_tmax7 <= '0; 
            req_tmax8 <= '0; 
            req_tmax9 <= '0; 
            req_tmax10 <= '0; 
            req_tmax11 <= '0; 
            req_tmax12 <= '0;

            req_tmin2 <= '0; 
            req_tmin3 <= '0; 
            req_tmin4 <= '0; 
            req_tmin5 <= '0; 
            req_tmin6 <= '0; 
            req_tmin7 <= '0; 
            req_tmin8 <= '0; 
            req_tmin9 <= '0; 
            req_tmin10 <= '0; 
            req_tmin11 <= '0; 
            req_tmin12 <= '0;

            parallel_miss2 <= 1'b0;
            parallel_miss3 <= 1'b0;
            parallel_miss4 <= 1'b0;
            parallel_miss5 <= 1'b0;
            parallel_miss6 <= 1'b0;
            parallel_miss7 <= 1'b0;
            parallel_miss8 <= 1'b0;
            parallel_miss9 <= 1'b0;
            parallel_miss10 <= 1'b0;
            parallel_miss11 <= 1'b0;
            parallel_miss12 <= 1'b0;

            dir_eq_zero2 <= 1'b0;
            dir_eq_zero3 <= 1'b0;
            dir_eq_zero4 <= 1'b0;
            dir_eq_zero5 <= 1'b0;
            dir_eq_zero6 <= 1'b0;
            dir_eq_zero7 <= 1'b0;
            dir_eq_zero8 <= 1'b0;
            dir_eq_zero9 <= 1'b0;
            dir_eq_zero10 <= 1'b0;
            dir_eq_zero11 <= 1'b0;
            dir_eq_zero12 <= 1'b0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax2 <= req_tmax1;
            req_tmax3 <= req_tmax2;
            req_tmax4 <= req_tmax3;
            req_tmax5 <= req_tmax4;
            req_tmax6 <= req_tmax5;
            req_tmax7 <= req_tmax6;
            req_tmax8 <= req_tmax7;
            req_tmax9 <= req_tmax8;
            req_tmax10 <= req_tmax9;
            req_tmax11 <= req_tmax10;
            req_tmax12 <= req_tmax11;

            req_tmin2 <= req_tmin1;
            req_tmin3 <= req_tmin2;
            req_tmin4 <= req_tmin3;
            req_tmin5 <= req_tmin4;
            req_tmin6 <= req_tmin5;
            req_tmin7 <= req_tmin6;
            req_tmin8 <= req_tmin7;
            req_tmin9 <= req_tmin8;
            req_tmin10 <= req_tmin9;
            req_tmin11 <= req_tmin10;
            req_tmin12 <= req_tmin11;

            parallel_miss2 <= parallel_miss1;
            parallel_miss3 <= parallel_miss2;
            parallel_miss4 <= parallel_miss3;
            parallel_miss5 <= parallel_miss4;
            parallel_miss6 <= parallel_miss5;
            parallel_miss7 <= parallel_miss6;
            parallel_miss8 <= parallel_miss7;
            parallel_miss9 <= parallel_miss8;
            parallel_miss10 <= parallel_miss9;
            parallel_miss11 <= parallel_miss10;
            parallel_miss12 <= parallel_miss11;

            dir_eq_zero2 <= dir_eq_zero1;
            dir_eq_zero3 <= dir_eq_zero2;
            dir_eq_zero4 <= dir_eq_zero3;
            dir_eq_zero5 <= dir_eq_zero4;
            dir_eq_zero6 <= dir_eq_zero5;
            dir_eq_zero7 <= dir_eq_zero6;
            dir_eq_zero8 <= dir_eq_zero7;
            dir_eq_zero9 <= dir_eq_zero8;
            dir_eq_zero10 <= dir_eq_zero9;
            dir_eq_zero11 <= dir_eq_zero10;
            dir_eq_zero12 <= dir_eq_zero11;
        end
    end

`else

    //3
    logic [31:0] t0;
    logic t0_valid;
    logic comp_ready;
    q16p16_mult t0_calc (
        .*, 
        .operand_a(amo), 
        .operand_b(inv_dir1),
        .ready_o(t0_ready), 
        .valid_i(amo_valid), 
        .product(t0), 
        .valid_o(t0_valid), 
        .ready_i(comp_ready)
    );

    //4
    logic [31:0] t1;
    logic t1_valid;
    q16p16_mult t1_calc (
        .*, 
        .operand_a(bmo), 
        .operand_b(inv_dir1),
        .ready_o(t1_ready), 
        .valid_i(bmo_valid), 
        .product(t1), 
        .valid_o(), 
        .ready_i(comp_ready)
    );

    //bypass reg for signals passing over steps 3 and 4
    //the multipliers also have two pipe stages
    logic [31:0] req_tmax2, req_tmax3;
    logic [31:0] req_tmin2, req_tmin3;
    logic parallel_miss2, parallel_miss3;
    logic dir_eq_zero2, dir_eq_zero3;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax2 <= '0;
            req_tmax3 <= '0;
            req_tmin2 <= '0;
            req_tmin3 <= '0;
            parallel_miss2 <= 1'b0;
            parallel_miss3 <= 1'b0;
            dir_eq_zero2 <= 1'b0;
            dir_eq_zero3 <= 1'b0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax2 <= req_tmax1;
            req_tmax3 <= req_tmax2;
            req_tmin2 <= req_tmin1;
            req_tmin3 <= req_tmin2;
            parallel_miss2 <= parallel_miss1;
            parallel_miss3 <= parallel_miss2;
            dir_eq_zero2 <= dir_eq_zero1;
            dir_eq_zero3 <= dir_eq_zero2;
        end
    end

`endif

    //5
    logic t0_gt_t1, t0_lt_t1;
    logic comp_valid;
    assign valid_o = comp_valid;

    q16p16_comp compare_times (
        .*, 
        .operand_a(t0), 
        .operand_b(t1),
        .ready_o(comp_ready), 
        .valid_i(t0_valid),
        .a_gt_b(t0_gt_t1), 
        .a_lt_b(t0_lt_t1), 
        .valid_o(comp_valid), 
        .ready_i(ready_i)
    );

    //bypass reg for signals passing over step 5
    //the comparator also has two pipe stages
`ifdef MULT_OPT
    logic [31:0] req_tmax13, req_tmax14;
    logic [31:0] req_tmin13, req_tmin14;
    logic parallel_miss13, parallel_miss14;
    logic dir_eq_zero13, dir_eq_zero14;
`else
    logic [31:0] req_tmax4, req_tmax5;
    logic [31:0] req_tmin4, req_tmin5;
    logic parallel_miss4, parallel_miss5;
    logic dir_eq_zero4, dir_eq_zero5;
`endif

    logic [31:0] t0_0, t0_1;
    logic [31:0] t1_0, t1_1;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
`ifdef MULT_OPT
            req_tmax13 <= '0;
            req_tmax14 <= '0;
            req_tmin13 <= '0;
            req_tmin14 <= '0;
            parallel_miss13 <= 1'b0;
            parallel_miss14 <= 1'b0;
            dir_eq_zero13 <= 1'b0;
            dir_eq_zero14 <= 1'b0;
`else
            req_tmax4 <= '0;
            req_tmax5 <= '0;
            req_tmin4 <= '0;
            req_tmin5 <= '0;
            parallel_miss4 <= 1'b0;
            parallel_miss5 <= 1'b0;
            dir_eq_zero4 <= 1'b0;
            dir_eq_zero5 <= 1'b0;
`endif
            t0_0 <= '0;
            t0_1 <= '0;
            t1_0 <= '0;
            t1_1 <= '0;
        end else if (!stall) begin
            //no gating yet, can add later
`ifdef MULT_OPT
            req_tmax13 <= req_tmax12;
            req_tmax14 <= req_tmax13;
            req_tmin13 <= req_tmin12;
            req_tmin14 <= req_tmin13;
            parallel_miss13 <= parallel_miss12;
            parallel_miss14 <= parallel_miss13;
            dir_eq_zero13 <= dir_eq_zero12;
            dir_eq_zero14 <= dir_eq_zero13;
`else
            req_tmax4 <= req_tmax3;
            req_tmax5 <= req_tmax4;
            req_tmin4 <= req_tmin3;
            req_tmin5 <= req_tmin4;
            parallel_miss4 <= parallel_miss3;
            parallel_miss5 <= parallel_miss4;
            dir_eq_zero4 <= dir_eq_zero3;
            dir_eq_zero5 <= dir_eq_zero4;
`endif
            t0_0 <= t0;
            t0_1 <= t0_0;
            t1_0 <= t1;
            t1_1 <= t1_0;
        end
    end

`ifdef MULT_OPT
    assign request_tmax_o = req_tmax14;
    assign request_tmin_o = req_tmin14;
`else
    assign request_tmax_o = req_tmax5;
    assign request_tmin_o = req_tmin5;
`endif

    //6 (select max based on comp result)
`ifdef MULT_OPT
    assign tmin_o = dir_eq_zero14 ?
                        (parallel_miss14 ? 32'h7fff_ffff : 32'h8000_0000) :
                        (t0_gt_t1 ? t1_1 : t0_1);

    assign tmax_o = dir_eq_zero14 ?
                        (parallel_miss14 ? 32'h8000_0000 : 32'h7fff_ffff) :
                        (t0_gt_t1 ? t0_1 : t1_1);
`else
    assign tmin_o = dir_eq_zero5 ?
                        (parallel_miss5 ? 32'h7fff_ffff : 32'h8000_0000) :
                        (t0_gt_t1 ? t1_1 : t0_1);

    assign tmax_o = dir_eq_zero5 ?
                        (parallel_miss5 ? 32'h8000_0000 : 32'h7fff_ffff) :
                        (t0_gt_t1 ? t0_1 : t1_1);
`endif

endmodule
