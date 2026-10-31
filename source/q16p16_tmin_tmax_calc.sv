`default_nettype none
`include "rtu_pkg.svh"

module q16p16_tmin_tmax_calc (
    input logic clk, n_rst,

    // Input interface
    input logic [31:0] request_tmax_i, request_tmin_i,
    input logic [31:0] corner_a, corner_b,
    input logic [31:0] ray_origin, inv_dir,
    input logic dir_eq_zero,
    input logic valid_i,
    output logic ready_o,

    // Output interface
    output logic [31:0] request_tmax_o, request_tmin_o,
    output logic [31:0] tmin_o, tmax_o,
    output logic valid_o,
    input logic ready_i
);

    //============================================================
    // Pipeline configuration
    //============================================================

    localparam int ADD_LATENCY  = 2;
    localparam int MULT_LATENCY = 11;
    localparam int COMP_LATENCY = 2;

    localparam int PIPE_LATENCY =
        ADD_LATENCY + MULT_LATENCY + COMP_LATENCY;

    // The parallel-slab comparators have already consumed
    // COMP_LATENCY cycles when their results enter this pipeline.
    localparam int PARALLEL_FLAG_STAGES =
        PIPE_LATENCY - COMP_LATENCY;

    //============================================================
    // Handshake
    //============================================================

    logic stall;
    logic input_valid;

    assign stall = !ready_i && valid_o;

    //============================================================
    // Parallel-slab detection
    //============================================================

    // origin < corner_a means the ray is outside the lower bound.
    logic origin_lt_a;
    logic origin_lt_a_ready;

    q16p16_comp origin_vs_a (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(ray_origin),
        .operand_b(corner_a),
        .ready_o(origin_lt_a_ready),
        .valid_i(input_valid),
        .a_gt_b(),
        .a_lt_b(origin_lt_a),
        .valid_o(),
        .ready_i(!stall)
    );

    // origin > corner_b means the ray is outside the upper bound.
    logic origin_gt_b;
    logic origin_gt_b_ready;

    q16p16_comp origin_vs_b (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(ray_origin),
        .operand_b(corner_b),
        .ready_o(origin_gt_b_ready),
        .valid_i(input_valid),
        .a_gt_b(origin_gt_b),
        .a_lt_b(),
        .valid_o(),
        .ready_i(!stall)
    );

    // Accept an input only when all parallel pipelines can accept it.
    logic sub_a_ready, sub_b_ready;

    assign ready_o = sub_a_ready &
                     sub_b_ready &
                     origin_lt_a_ready &
                     origin_gt_b_ready;

    assign input_valid = valid_i && ready_o;

    //============================================================
    // Subtraction: corner - origin
    //============================================================

    logic [31:0] amo, bmo;
    logic amo_valid, bmo_valid;
    logic t0_ready, t1_ready;

    q16p16_sub a_minus_o_calc (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(corner_a),
        .operand_b(ray_origin),
        .ready_o(sub_a_ready),
        .valid_i(input_valid),
        .sum(amo),
        .valid_o(amo_valid),
        .ready_i(t0_ready)
    );

    q16p16_sub b_minus_o_calc (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(corner_b),
        .operand_b(ray_origin),
        .ready_o(sub_b_ready),
        .valid_i(input_valid),
        .sum(bmo),
        .valid_o(bmo_valid),
        .ready_i(t1_ready)
    );

    //============================================================
    // Multiplication: (corner - origin) * inverse direction
    //============================================================

    logic [31:0] inv_dir0, inv_dir1;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            inv_dir0 <= '0;
            inv_dir1 <= '0;
        end else if (!stall) begin
            inv_dir0 <= inv_dir;
            inv_dir1 <= inv_dir0;
        end
    end

    logic [31:0] t0, t1;
    logic t0_valid, t1_valid;
    logic comp_ready;

    q16p16_mult_opt t0_calc (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(amo),
        .operand_b(inv_dir1),
        .ready_o(t0_ready),
        .valid_i(amo_valid),
        .product(t0),
        .valid_o(t0_valid),
        .ready_i(comp_ready)
    );

    q16p16_mult_opt t1_calc (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(bmo),
        .operand_b(inv_dir1),
        .ready_o(t1_ready),
        .valid_i(bmo_valid),
        .product(t1),
        .valid_o(t1_valid),
        .ready_i(comp_ready)
    );

    //============================================================
    // Final comparison: determine the near and far values
    //============================================================

    logic t0_gt_t1, t0_lt_t1;
    logic comp_valid;

    q16p16_comp compare_times (
        .clk(clk),
        .n_rst(n_rst),
        .operand_a(t0),
        .operand_b(t1),
        .ready_o(comp_ready),
        .valid_i(t0_valid),
        .a_gt_b(t0_gt_t1),
        .a_lt_b(t0_lt_t1),
        .valid_o(comp_valid),
        .ready_i(ready_i)
    );

    assign valid_o = comp_valid;

    // The comparison takes COMP_LATENCY cycles. Delay the multiplier
    // outputs by the same amount so the values align with its result.
    logic [31:0] t0_pipe [0:COMP_LATENCY-1];
    logic [31:0] t1_pipe [0:COMP_LATENCY-1];

    //============================================================
    // Bypass pipelines
    //============================================================

    logic [31:0] req_tmax_pipe [0:PIPE_LATENCY-1];
    logic [31:0] req_tmin_pipe [0:PIPE_LATENCY-1];

    logic dir_eq_zero_pipe [0:PIPE_LATENCY-1];

    logic parallel_miss_pipe [0:PARALLEL_FLAG_STAGES-1];

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin

            // Request bypass
            for (int i = 0; i < PIPE_LATENCY; i++) begin
                req_tmax_pipe[i] <= '0;
                req_tmin_pipe[i] <= '0;
                dir_eq_zero_pipe[i] <= 1'b0;
            end

            // Parallel-miss bypass
            for (int i = 0; i < PARALLEL_FLAG_STAGES; i++) begin
                parallel_miss_pipe[i] <= 1'b0;
            end

            // Multiplier result alignment
            for (int i = 0; i < COMP_LATENCY; i++) begin
                t0_pipe[i] <= '0;
                t1_pipe[i] <= '0;
            end

        end else if (!stall) begin

            // Request and direction bypass
            req_tmax_pipe[0] <= request_tmax_i;
            req_tmin_pipe[0] <= request_tmin_i;
            dir_eq_zero_pipe[0] <= dir_eq_zero;

            for (int i = 1; i < PIPE_LATENCY; i++) begin
                req_tmax_pipe[i] <= req_tmax_pipe[i-1];
                req_tmin_pipe[i] <= req_tmin_pipe[i-1];
                dir_eq_zero_pipe[i] <= dir_eq_zero_pipe[i-1];
            end

            // The two q16p16_comp instances have already performed
            // the outside-slab comparisons.
            parallel_miss_pipe[0] <= origin_lt_a || origin_gt_b;

            for (int i = 1; i < PARALLEL_FLAG_STAGES; i++) begin
                parallel_miss_pipe[i] <= parallel_miss_pipe[i-1];
            end

            // Align t0/t1 with the final comparator outputs.
            t0_pipe[0] <= t0;
            t1_pipe[0] <= t1;

            for (int i = 1; i < COMP_LATENCY; i++) begin
                t0_pipe[i] <= t0_pipe[i-1];
                t1_pipe[i] <= t1_pipe[i-1];
            end
        end
    end

    //============================================================
    // Output selection
    //============================================================

    assign request_tmax_o = req_tmax_pipe[PIPE_LATENCY-1];
    assign request_tmin_o = req_tmin_pipe[PIPE_LATENCY-1];

    // Parallel rays either miss the slab or impose no interval
    // restriction on the intersection.
    assign tmin_o = dir_eq_zero_pipe[PIPE_LATENCY-1] ?
                    (parallel_miss_pipe[PARALLEL_FLAG_STAGES-1] ?
                        32'h7fff_ffff : 32'h8000_0000) :
                    (t0_gt_t1 ? t1_pipe[COMP_LATENCY-1] :
                                t0_pipe[COMP_LATENCY-1]);

    assign tmax_o = dir_eq_zero_pipe[PIPE_LATENCY-1] ?
                    (parallel_miss_pipe[PARALLEL_FLAG_STAGES-1] ?
                        32'h8000_0000 : 32'h7fff_ffff) :
                    (t0_gt_t1 ? t0_pipe[COMP_LATENCY-1] :
                                t1_pipe[COMP_LATENCY-1]);

endmodule