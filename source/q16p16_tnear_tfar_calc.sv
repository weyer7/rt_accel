`default_nettype none
`include "rtu_pkg.svh"
module q16p16_tnear_tfar_calc (
    input logic clk, n_rst,

    //============================
    //input interface
    //============================

    //signals to bypass
    input logic [31:0] request_tmax_i, request_tmin_i,
    //signals to operate on
    input logic [31:0] tmin_x, tmax_x,
    input logic [31:0] tmin_y, tmax_y,
    input logic [31:0] tmin_z, tmax_z,
    //handshake
    input logic valid_i,
    output logic ready_o,

    //============================
    //output interface
    //============================

    //bypassed signals
    output logic [31:0] request_tmax_o, request_tmin_o,
    //result signals
    output logic [31:0] tnear_o, tfar_o,
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
    //1) compare mimimums (x,y) (x,z) (y,z)
    //2) compare maximums (x,y) (x,z) (y,z)
    //3) select t_near based on max(tmin_x, tmin_y, tmin_z)
    //4) select t_far based on min(tmax_x, tmax_y, tmax_z)

    //1

    //x, y
    logic xmin_gt_ymin;
    logic comp_valid;
    assign valid_o = comp_valid;
    q16p16_comp compare_xy_min (.*, .operand_a(tmin_x), .operand_b(tmin_y),
        .ready_o(ready_o), .valid_i(valid_i),
        .a_gt_b(xmin_gt_ymin), .a_lt_b(), .valid_o(comp_valid), .ready_i(ready_i)
    );

    //x, z
    logic xmin_gt_zmin;
    q16p16_comp compare_xz_min (.*, .operand_a(tmin_x), .operand_b(tmin_z),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(xmin_gt_zmin), .a_lt_b(), .valid_o(), .ready_i(ready_i)
    );

    //y, z
    logic ymin_gt_zmin;
    q16p16_comp compare_yz_min (.*, .operand_a(tmin_y), .operand_b(tmin_z),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(ymin_gt_zmin), .a_lt_b(), .valid_o(), .ready_i(ready_i)
    );

    //2

    //x, y
    logic xmax_gt_ymax;
    q16p16_comp compare_xy_max (.*, .operand_a(tmax_x), .operand_b(tmax_y),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(xmax_gt_ymax), .a_lt_b(), .valid_o(), .ready_i(ready_i)
    );

    //x, z
    logic xmax_gt_zmax;
    q16p16_comp compare_xz_max (.*, .operand_a(tmax_x), .operand_b(tmax_z),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(xmax_gt_zmax), .a_lt_b(), .valid_o(), .ready_i(ready_i)
    );

    //y, z
    logic ymax_gt_zmax;
    q16p16_comp compare_yz_max (.*, .operand_a(tmax_y), .operand_b(tmax_z),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(ymax_gt_zmax), .a_lt_b(), .valid_o(), .ready_i(ready_i)
    );


    //bypass reg for signals passing over steps 1 and 2
    //the comparators have two pipe stages
    logic [31:0] req_tmax0, req_tmax1;
    logic [31:0] req_tmin0, req_tmin1;
    logic[31:0] tmin_x_0, tmin_x_1, tmax_x_0, tmax_x_1, tmin_y_0, tmin_y_1, tmax_y_0, tmax_y_1, tmin_z_0, tmin_z_1, tmax_z_0, tmax_z_1;
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            req_tmax0 <= '0;
            req_tmax1 <= '0;
            req_tmin0 <= '0;
            req_tmin1 <= '0;
            tmin_x_0 <= '0;
            tmin_x_1 <= '0;
            tmax_x_0 <= '0;
            tmax_x_1 <= '0;
            tmin_y_0 <= '0;
            tmin_y_1 <= '0;
            tmax_y_0 <= '0;
            tmax_y_1 <= '0;
            tmin_z_0 <= '0;
            tmin_z_1 <= '0;
            tmax_z_0 <= '0;
            tmax_z_1 <= '0;
        end else if (!stall) begin
            //no gating yet, can add later
            req_tmax0 <= request_tmax_i;
            req_tmax1 <= req_tmax0;
            req_tmin0 <= request_tmin_i;
            req_tmin1 <= req_tmin0;
            tmin_x_0 <= tmin_x;
            tmin_x_1 <= tmin_x_0;
            tmax_x_0 <= tmax_x;
            tmax_x_1 <= tmax_x_0;
            tmin_y_0 <= tmin_y;
            tmin_y_1 <= tmin_y_0;
            tmax_y_0 <= tmax_y;
            tmax_y_1 <= tmax_y_0;
            tmin_z_0 <= tmin_z;
            tmin_z_1 <= tmin_z_0;
            tmax_z_0 <= tmax_z;
            tmax_z_1 <= tmax_z_0;
        end
    end

    //3 max(tmin_x, tmin_y, tmin_z)
    always_comb begin
        if (xmin_gt_ymin && xmin_gt_zmin) tnear_o = tmin_x_1;
        else if (!xmin_gt_ymin && ymin_gt_zmin) tnear_o = tmin_y_1;
        else /*if (!xmin_gt_zmin && !ymin_gt_zmin)*/ tnear_o = tmin_z_1;
    end

    //4 min(tmax_x, tmax_y, tmax_z)
    always_comb begin
        if (!xmax_gt_ymax && !xmax_gt_zmax) tfar_o = tmax_x_1;
        else if (xmax_gt_ymax && !ymax_gt_zmax) tfar_o = tmax_y_1;
        else /*if (xmax_gt_zmax && ymax_gt_zmax)*/ tfar_o = tmax_z_1;
    end

    assign request_tmax_o = req_tmax1;
    assign request_tmin_o = req_tmin1;

endmodule
