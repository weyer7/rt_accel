`default_nettype none
`include "rtu_pkg.svh"
module q16p16_aabb_hit_calc (
    input logic clk, n_rst,

    //============================
    //input interface
    //============================

    //signals to operate on
    input logic [31:0] request_tmax_i, request_tmin_i,
    input logic [31:0] tnear_i, tfar_i,
    //handshake
    input logic valid_i,
    output logic ready_o,

    //============================
    //output interface
    //============================

    //result signals
    output logic [31:0] tnear_o, tfar_o,
    output logic hit,
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
    //1) compare tmin_i to tmax_i
    //2) compare tnear_i to tmax_i
    //3) compare tfar to tmin_i
    //4) calculate aabb hit based on steps 1-3

    //1
    logic tnear_gt_tfar, tnear_lt_tfar;
    logic comp_valid;
    assign valid_o = comp_valid;
    q16p16_comp compare_tnear_tfar (.*, .operand_a(tnear_i), .operand_b(tfar_i),
        .ready_o(ready_o), .valid_i(valid_i),
        .a_gt_b(tnear_gt_tfar), .a_lt_b(tnear_lt_tfar), .valid_o(comp_valid), .ready_i(ready_i)
    );

    //2
    logic tnear_gt_tmax, tnear_lt_tmax;
    q16p16_comp compare_tnear_tmax (.*, .operand_a(tnear_i), .operand_b(request_tmax_i),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(tnear_gt_tmax), .a_lt_b(tnear_lt_tmax), .valid_o(), .ready_i(ready_i)
    );

    //3
    logic tfar_gt_tmin, tfar_lt_tmin;
    q16p16_comp compare_tfar_tmin (.*, .operand_a(tfar_i), .operand_b(request_tmin_i),
        .ready_o(), .valid_i(valid_i),
        .a_gt_b(tfar_gt_tmin), .a_lt_b(tfar_lt_tmin), .valid_o(), .ready_i(ready_i)
    );


    //bypass reg for signals passing over steps 1 and 2
    //the comparators have two pipe stages
    logic [31:0] tnear0, tnear1;
    logic [31:0] tfar0, tfar1;
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            tnear0 <= '0;
            tnear1 <= '0;
            tfar0 <= '0;
            tfar1 <= '0;
        end else if (!stall) begin
            //no gating yet, can add later
            tnear0 <= tnear_i;
            tnear1 <= tnear0;
            tfar0 <= tfar_i;
            tfar1 <= tfar0;
        end
    end

    //4 calculate hit (tnear_gt_tfar, tnear_gt_tmax, tfar_gt_tmin)
    always_comb begin
        if (
            !tnear_gt_tfar && //tnear <= tfar
            !tfar_lt_tmin && //tfar >= tmin
            !tnear_gt_tmax//tnear <= tmax
        ) begin
            hit = 1;
        end else begin
            hit = 0;
        end
    end

    assign tnear_o = tnear1;
    assign tfar_o = tfar1;

endmodule
