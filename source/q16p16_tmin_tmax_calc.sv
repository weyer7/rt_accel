`default_nettype none
`include "rtu_pkg.svh"
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

    //no input register
    // assign ready_o = !stall;

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
    logic[31:0] amo;
    logic amo_valid, t0_ready;
    q16p16_sub a_minus_o_calc (.*, .operand_a(corner_a), .operand_b(ray_origin),
        .ready_o(ready_o), .valid_i(valid_i),
        .sum(amo), .valid_o(amo_valid), .ready_i(t0_ready)
    );

    //2
    logic[31:0] bmo;
    logic bmo_valid, t1_ready;
    q16p16_sub b_minus_o_calc (.*, .operand_a(corner_b), .operand_b(ray_origin),
        .ready_o(), .valid_i(valid_i),
        .sum(bmo), .valid_o(bmo_valid), .ready_i(t1_ready)
    );

    //bypass reg for signals passing over steps 1 and 2
    //the adders have two pipe stages
    logic [31:0] req_tmax0, req_tmax1;
    logic [31:0] req_tmin0, req_tmin1;
    logic [31:0] inv_dir0, inv_dir1;
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax0 <= '0;
            req_tmax1 <= '0;
            req_tmin0 <= '0;
            req_tmin1 <= '0;
            inv_dir0 <= '0;
            inv_dir1 <= '0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax0 <= request_tmax_i;
            req_tmax1 <= req_tmax0;
            req_tmin0 <= request_tmin_i;
            req_tmin1 <= req_tmin0;
            inv_dir0 <= inv_dir;
            inv_dir1 <= inv_dir0;
        end
    end

    //3
    logic [31:0] t0;
    logic t0_valid;
    logic comp_ready;
    q16p16_mult t0_calc (.*, .operand_a(amo), .operand_b(inv_dir1),
        .ready_o(t0_ready), .valid_i(amo_valid), 
        .product(t0), .valid_o(t0_valid), .ready_i(comp_ready)
    );

    //4
    logic [31:0] t1;
    logic t1_valid;
    q16p16_mult t1_calc (.*, .operand_a(bmo), .operand_b(inv_dir1),
        .ready_o(t1_ready), .valid_i(bmo_valid), 
        .product(t1), .valid_o(), .ready_i(comp_ready)
    );

    //bypass reg for signals passing over steps 3 and 4
    //the multipliers also have two pipe stages
    logic [31:0] req_tmax2, req_tmax3;
    logic [31:0] req_tmin2, req_tmin3;
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax2 <= '0;
            req_tmax3 <= '0;
            req_tmin2 <= '0;
            req_tmin3 <= '0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax2 <= req_tmax1;
            req_tmax3 <= req_tmax2;
            req_tmin2 <= req_tmin1;
            req_tmin3 <= req_tmin2;
        end
    end

    //5
    logic t0_gt_t1, t0_lt_t1;
    logic comp_valid;
    assign valid_o = comp_valid;
    q16p16_comp compare_times (.*, .operand_a(t0), .operand_b(t1),
    .ready_o(comp_ready), .valid_i(t0_valid),
    .a_gt_b(t0_gt_t1), .a_lt_b(t0_lt_t1), .valid_o(comp_valid), .ready_i(ready_i)
    );

    //bypass reg for signals passing over step 5
    //the comparator also has two pipe stages
    logic [31:0] req_tmax4, req_tmax5;
    logic [31:0] req_tmin4, req_tmin5;
    logic [31:0] t0_0, t0_1;
    logic [31:0] t1_0, t1_1;
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax4 <= '0;
            req_tmax5 <= '0;
            req_tmin4 <= '0;
            req_tmin5 <= '0;
            t0_0 <= '0;
            t0_1 <= '0;
            t1_0 <= '0;
            t1_1 <= '0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax4 <= req_tmax3;
            req_tmax5 <= req_tmax4;
            req_tmin4 <= req_tmin3;
            req_tmin5 <= req_tmin4;
            t0_0 <= t0;
            t0_1 <= t0_0;
            t1_0 <= t1;
            t1_1 <= t1_0;
        end
    end

    assign request_tmax_o = req_tmax5;
    assign request_tmin_o = req_tmin5;

    //6 (select max based on comp result)
    assign tmin_o = t0_gt_t1 ? t1_1 : t0_1; //select min
    assign tmax_o = t0_gt_t1 ? t0_1 : t1_1; //select max

endmodule
