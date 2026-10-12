`default_nettype none
`include "rtu_pkg.svh"

module q16p16_aabb_intersect (
    input logic clk, 
    input logic n_rst,

    // Input interface
    input aabb_request_t request,
    input logic valid_i,
    output logic ready_o,

    // Output interface
    output aabb_result_t result,
    output logic valid_o,
    input logic ready_i
);

    // ============================================================
    // Internal Wires & Handshake Signals
    // ============================================================
    
    // Stage 1 -> Stage 2 (Axis tmin/tmax outputs)
    logic [31:0] req_tmax_x, req_tmin_x, tmin_x, tmax_x;
    logic [31:0] req_tmax_y, req_tmin_y, tmin_y, tmax_y;
    logic [31:0] req_tmax_z, req_tmin_z, tmin_z, tmax_z;
    
    logic valid_axis_o, ready_axis_i;
    logic ready_axis_x, ready_axis_y, ready_axis_z;

    // Stage 2 -> Stage 3 (Tnear / Tfar outputs)
    logic [31:0] req_tmax_tfar, req_tmin_tfar;
    logic [31:0] tnear_mid, tfar_mid;
    logic valid_tfar_o, ready_tfar_i;

    // Stage 3 -> Output (Hit calc outputs)
    logic [31:0] tnear_final, tfar_final;
    logic hit_final;
    logic valid_hit_o, ready_hit_i;

    // We can tie the axis ready signals together (or use minimum ready)
    assign ready_axis_i = ready_axis_x & ready_axis_y & ready_axis_z;
    assign ready_o = ready_axis_i;

    // ============================================================
    // Stage 1: Parallel Axis Intersections (X, Y, Z)
    // ============================================================

    // X-Axis Intersect Calculator
    q16p16_tmin_tmax_calc calc_x (
        .clk(clk), .n_rst(n_rst),
        .request_tmax_i(request.ray.t_max.data), 
        .request_tmin_i(request.ray.t_min.data),
        .corner_a(request.box.corner_a.x.data), 
        .corner_b(request.box.corner_b.x.data),
        .ray_origin(request.ray.origin.x.data), 
        .inv_dir(request.ray.inv_direction.x.data),
        .valid_i(valid_i), .ready_o(ready_axis_x),
        .request_tmax_o(req_tmax_x), .request_tmin_o(req_tmin_x),
        .tmin_o(tmin_x), .tmax_o(tmax_x),
        .valid_o(), .ready_i(ready_axis_i)
    );

    // Y-Axis Intersect Calculator
    q16p16_tmin_tmax_calc calc_y (
        .clk(clk), .n_rst(n_rst),
        .request_tmax_i(request.ray.t_max.data), 
        .request_tmin_i(request.ray.t_min.data),
        .corner_a(request.box.corner_a.y.data), 
        .corner_b(request.box.corner_b.y.data),
        .ray_origin(request.ray.origin.y.data), 
        .inv_dir(request.ray.inv_direction.y.data),
        .valid_i(valid_i), .ready_o(ready_axis_y),
        .request_tmax_o(req_tmax_y), .request_tmin_o(req_tmin_y),
        .tmin_o(tmin_y), .tmax_o(tmax_y),
        .valid_o(), .ready_i(ready_axis_i)
    );

    // Z-Axis Intersect Calculator
    q16p16_tmin_tmax_calc calc_z (
        .clk(clk), .n_rst(n_rst),
        .request_tmax_i(request.ray.t_max.data), 
        .request_tmin_i(request.ray.t_min.data),
        .corner_a(request.box.corner_a.z.data), 
        .corner_b(request.box.corner_b.z.data),
        .ray_origin(request.ray.origin.z.data), 
        .inv_dir(request.ray.inv_direction.z.data),
        .valid_i(valid_i), .ready_o(ready_axis_z),
        .request_tmax_o(req_tmax_z), .request_tmin_o(req_tmin_z),
        .tmin_o(tmin_z), .tmax_o(tmax_z),
        .valid_o(valid_axis_o), .ready_i(ready_axis_i)
    );

    // ============================================================
    // Stage 2: Tnear / Tfar Aggregator
    // ============================================================

    q16p16_tnear_tfar_calc tnear_tfar_unit (
        .clk(clk), .n_rst(n_rst),
        .request_tmax_i(req_tmax_x), 
        .request_tmin_i(req_tmin_x),
        .tmin_x(tmin_x), .tmax_x(tmax_x),
        .tmin_y(tmin_y), .tmax_y(tmax_y),
        .tmin_z(tmin_z), .tmax_z(tmax_z),
        .valid_i(valid_axis_o), .ready_o(ready_tfar_i),
        .request_tmax_o(req_tmax_tfar), .request_tmin_o(req_tmin_tfar),
        .tnear_o(tnear_mid), .tfar_o(tfar_mid),
        .valid_o(valid_tfar_o), .ready_i(ready_hit_i)
    );

    // ============================================================
    // Stage 3: AABB Hit and Interval Check
    // ============================================================

    q16p16_aabb_hit_calc hit_calc_unit (
        .clk(clk), .n_rst(n_rst),
        .request_tmax_i(req_tmax_tfar), 
        .request_tmin_i(req_tmin_tfar),
        .tnear_i(tnear_mid), 
        .tfar_i(tfar_mid),
        .valid_i(valid_tfar_o), .ready_o(ready_hit_i),
        .tnear_o(tnear_final), .tfar_o(tfar_final),
        .hit(hit_final),
        .valid_o(valid_o), .ready_i(ready_i)
    );

    // ============================================================
    // Context ID Pipeline & Result Packaging
    // ============================================================
    // Match total pipeline latency to pipe context_id along with the data
    
    // Determine total latency stages across axis, tnear/tfar, and hit calc
    localparam int TOTAL_LATENCY = 10; // Adjust based on internal submodule depths if needed
    
    logic [7:0] context_id_pipe [TOTAL_LATENCY-1:0];
    logic       stall;
    
    assign stall = !ready_i && valid_o;

    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            for (int i = 0; i < TOTAL_LATENCY; i++) begin
                context_id_pipe[i] <= '0;
            end
        end else if (!stall) begin
            context_id_pipe[0] <= request.context_id;
            for (int i = 1; i < TOTAL_LATENCY; i++) begin
                context_id_pipe[i] <= context_id_pipe[i-1];
            end
        end
    end

    // Assign final packaged result
    always_comb begin
        result.context_id  = context_id_pipe[TOTAL_LATENCY-1];
        result.hit         = hit_final;
        result.t_near.data = tnear_final;
        result.t_far.data  = tfar_final;
    end

endmodule
