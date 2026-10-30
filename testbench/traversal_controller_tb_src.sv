// `timescale 1ns/1ps
// `include "rtu_pkg.svh"

// // Initial integration testbench for bvh_traversal_controller.
// // Compile this simulation harness directly with a simulator; do not run the
// // testbench or DPI C model through sv2v. Keep sv2v limited to synthesizable RTL.
// module traversal_controller_tb;
//     localparam addr_t BVH_BASE = 32'h1000_0000;
//     localparam addr_t TRI_BASE = 32'h2000_0000;
//     localparam int NODE_BYTES = 32;
//     localparam int TRI_STRIDE = 40; // must match controller parameter
//     localparam int NODE_COUNT = 8;
//     localparam int TRI_COUNT = 8;
//     localparam int MEM_LATENCY = 2;
//     localparam int TRI_MODEL_LATENCY = 2;

//     logic clk = 1'b0;
//     logic rst_n = 1'b0;
//     always #5 clk = ~clk;

//     // Traversal request / result.
//     logic traversal_valid_i;
//     logic traversal_ready_o;
//     traversal_request_t traversal_i;
//     logic traversal_result_valid_o;
//     logic traversal_result_ready_i;
//     traversal_result_t traversal_result_o;
//     logic stack_overflow_o;

//     // Simulated node memory.
//     logic bvh_mem_req_valid_o, bvh_mem_req_ready_i;
//     addr_t bvh_mem_req_addr_o;
//     logic bvh_mem_resp_valid_i, bvh_mem_resp_error_i;
//     bvh_node_t bvh_mem_resp_data_i;

//     // Simulated triangle memory.
//     logic tri_mem_req_valid_o, tri_mem_req_ready_i;
//     addr_t tri_mem_req_addr_o;
//     logic tri_mem_resp_valid_i, tri_mem_resp_error_i;
//     triangle_t tri_mem_resp_data_i;

//     // Real AABB pipeline interface.
//     logic aabb_req_valid_o, aabb_req_ready_i;
//     aabb_request_t aabb_req_o;
//     logic aabb_result_valid_i;
//     aabb_result_t aabb_result_i;

//     // DPI-backed triangle model interface.
//     logic tri_req_valid_o, tri_req_ready_i;
//     tri_request_t tri_req_o;
//     logic tri_result_valid_i;
//     tri_result_t tri_result_i;

//     bvh_node_t node_mem [0:NODE_COUNT-1];
//     triangle_t tri_mem [0:TRI_COUNT-1];
//     logic [NODE_COUNT-1:0] node_present;
//     logic [TRI_COUNT-1:0] tri_present;

//     integer bvh_read_count;
//     integer tri_mem_read_count;
//     integer aabb_request_count;
//     integer tri_intersection_count;

//     traversal_controller #(
//         .STACK_DEPTH(16),
//         .TRIANGLE_STRIDE_BYTES(TRI_STRIDE)
//     ) u_dut (
//         .clk(clk), .rst_n(rst_n),
//         .traversal_valid_i(traversal_valid_i),
//         .traversal_ready_o(traversal_ready_o),
//         .traversal_i(traversal_i),
//         .bvh_mem_req_valid_o(bvh_mem_req_valid_o),
//         .bvh_mem_req_ready_i(bvh_mem_req_ready_i),
//         .bvh_mem_req_addr_o(bvh_mem_req_addr_o),
//         .bvh_mem_resp_valid_i(bvh_mem_resp_valid_i),
//         .bvh_mem_resp_error_i(bvh_mem_resp_error_i),
//         .bvh_mem_resp_data_i(bvh_mem_resp_data_i),
//         .tri_mem_req_valid_o(tri_mem_req_valid_o),
//         .tri_mem_req_ready_i(tri_mem_req_ready_i),
//         .tri_mem_req_addr_o(tri_mem_req_addr_o),
//         .tri_mem_resp_valid_i(tri_mem_resp_valid_i),
//         .tri_mem_resp_error_i(tri_mem_resp_error_i),
//         .tri_mem_resp_data_i(tri_mem_resp_data_i),
//         .aabb_req_valid_o(aabb_req_valid_o),
//         .aabb_req_ready_i(aabb_req_ready_i),
//         .aabb_req_o(aabb_req_o),
//         .aabb_result_valid_i(aabb_result_valid_i),
//         .aabb_result_i(aabb_result_i),
//         .tri_req_valid_o(tri_req_valid_o),
//         .tri_req_ready_i(tri_req_ready_i),
//         .tri_req_o(tri_req_o),
//         .tri_result_valid_i(tri_result_valid_i),
//         .tri_result_i(tri_result_i),
//         .traversal_result_valid_o(traversal_result_valid_o),
//         .traversal_result_ready_i(traversal_result_ready_i),
//         .traversal_result_o(traversal_result_o),
//         .stack_overflow_o(stack_overflow_o)
//     );

//     // Existing verified 10-stage AABB pipeline. Its exact interface matches
//     // the standalone AABB testbench (`request`, `valid_i`, `ready_o`, etc.).
//     q16p16_aabb_intersect u_aabb (
//         .clk(clk),
//         .n_rst(rst_n),
//         .request(aabb_req_o),
//         .valid_i(aabb_req_valid_o),
//         .ready_o(aabb_req_ready_i),
//         .result(aabb_result_i),
//         .valid_o(aabb_result_valid_i),
//         .ready_i(1'b1)
//     );

//     // // Memory responses have fixed, configurable simulation latency. Only one
//     // // read per port may be outstanding, matching the controller's contract.
//     logic bvh_pending_q, tri_mem_pending_q;
//     integer bvh_delay_q, tri_mem_delay_q;
//     bvh_node_t bvh_data_pending_q;
//     logic bvh_error_pending_q;
//     triangle_t tri_data_pending_q;
//     logic tri_mem_error_pending_q;

//     assign bvh_mem_req_ready_i = !bvh_pending_q;
//     assign tri_mem_req_ready_i = !tri_mem_pending_q;

//     function automatic logic bvh_addr_valid(input addr_t addr);
//         integer idx;
//         begin
//             bvh_addr_valid = 1'b0;
//             if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
//                 idx = (addr - BVH_BASE) / NODE_BYTES;
//                 if ((idx >= 0) && (idx < NODE_COUNT))
//                     bvh_addr_valid = node_present[idx];
//             end
//         end
//     endfunction

//     function automatic bvh_node_t bvh_lookup(input addr_t addr);
//         integer idx;
//         begin
//             bvh_lookup = '0;
//             if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
//                 idx = (addr - BVH_BASE) / NODE_BYTES;
//                 if ((idx >= 0) && (idx < NODE_COUNT))
//                     bvh_lookup = node_mem[idx];
//             end
//         end
//     endfunction

//     function automatic logic tri_addr_valid(input addr_t addr);
//         integer idx;
//         begin
//             tri_addr_valid = 1'b0;
//             if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
//                 idx = (addr - TRI_BASE) / TRI_STRIDE;
//                 if ((idx >= 0) && (idx < TRI_COUNT))
//                     tri_addr_valid = tri_present[idx];
//             end
//         end
//     endfunction

//     function automatic triangle_t tri_lookup(input addr_t addr);
//         integer idx;
//         begin
//             tri_lookup = '0;
//             if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
//                 idx = (addr - TRI_BASE) / TRI_STRIDE;
//                 if ((idx >= 0) && (idx < TRI_COUNT))
//                     tri_lookup = tri_mem[idx];
//             end
//         end
//     endfunction

//     always_ff @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             bvh_pending_q       <= 1'b0;
//             bvh_delay_q         <= 0;
//             bvh_data_pending_q  <= '0;
//             bvh_error_pending_q <= 1'b0;
//             bvh_mem_resp_valid_i <= 1'b0;
//             bvh_mem_resp_error_i <= 1'b0;
//             bvh_mem_resp_data_i <= '0;
//             bvh_read_count      <= 0;
//         end else begin
//             bvh_mem_resp_valid_i <= 1'b0;
//             if (bvh_pending_q) begin
//                 if (bvh_delay_q > 1) begin
//                     bvh_delay_q <= bvh_delay_q - 1;
//                 end else begin
//                     bvh_pending_q        <= 1'b0;
//                     bvh_mem_resp_valid_i <= 1'b1;
//                     bvh_mem_resp_error_i <= bvh_error_pending_q;
//                     bvh_mem_resp_data_i  <= bvh_data_pending_q;
//                 end
//             end
//             if (bvh_mem_req_valid_o && bvh_mem_req_ready_i) begin
//                 if (bvh_pending_q)
//                     $fatal(1, "BVH memory accepted overlapping read");
//                 bvh_pending_q       <= 1'b1;
//                 bvh_delay_q         <= MEM_LATENCY;
//                 bvh_data_pending_q  <= bvh_lookup(bvh_mem_req_addr_o);
//                 bvh_error_pending_q <= !bvh_addr_valid(bvh_mem_req_addr_o);
//                 bvh_read_count      <= bvh_read_count + 1;
//             end
//         end
//     end

//     // Triangle interface: accept requests and return misses.
//     logic tri_model_pending_q;
//     integer tri_model_delay_q;

//     assign tri_req_ready_i = !tri_model_pending_q;

//     always_ff @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             tri_model_pending_q    <= 1'b0;
//             tri_model_delay_q      <= 0;
//             tri_result_valid_i     <= 1'b0;
//             tri_result_i           <= '0;
//             tri_intersection_count <= 0;
//         end else begin
//             tri_result_valid_i <= 1'b0;

//             if (tri_model_pending_q) begin
//                 if (tri_model_delay_q > 1) begin
//                     tri_model_delay_q <= tri_model_delay_q - 1;
//                 end else begin
//                     tri_model_pending_q <= 1'b0;
//                     tri_result_valid_i  <= 1'b1;
//                     tri_result_i        <= '0;
//                 end
//             end

//             if (tri_req_valid_o && tri_req_ready_i) begin
//                 tri_model_pending_q    <= 1'b1;
//                 tri_model_delay_q      <= TRI_MODEL_LATENCY;
//                 tri_intersection_count <= tri_intersection_count + 1;
//             end
//         end
//     end

//     always_ff @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             tri_mem_pending_q    <= 1'b0;
//             tri_mem_delay_q      <= 0;
//             tri_data_pending_q   <= '0;
//             tri_mem_error_pending_q <= 1'b0;
//             tri_mem_resp_valid_i <= 1'b0;
//             tri_mem_resp_error_i <= 1'b0;
//             tri_mem_resp_data_i  <= '0;
//             tri_mem_read_count   <= 0;
//         end else begin
//             tri_mem_resp_valid_i <= 1'b0;
//             if (tri_mem_pending_q) begin
//                 if (tri_mem_delay_q > 1) begin
//                     tri_mem_delay_q <= tri_mem_delay_q - 1;
//                 end else begin
//                     tri_mem_pending_q    <= 1'b0;
//                     tri_mem_resp_valid_i <= 1'b1;
//                     tri_mem_resp_error_i <= tri_mem_error_pending_q;
//                     tri_mem_resp_data_i  <= tri_data_pending_q;
//                 end
//             end
//             if (tri_mem_req_valid_o && tri_mem_req_ready_i) begin
//                 if (tri_mem_pending_q)
//                     $fatal(1, "Triangle memory accepted overlapping read");
//                 tri_mem_pending_q       <= 1'b1;
//                 tri_mem_delay_q         <= MEM_LATENCY;
//                 tri_data_pending_q      <= tri_lookup(tri_mem_req_addr_o);
//                 tri_mem_error_pending_q <= !tri_addr_valid(tri_mem_req_addr_o);
//                 tri_mem_read_count      <= tri_mem_read_count + 1;
//             end
//         end
//     end

//     //     // Simulation-only, pure SystemVerilog triangle intersection model.
//     // // Uses real arithmetic for Moller-Trumbore, then converts results to Q16.16.
//     // // Do not synthesize this section or run it through sv2v.

//     // // logic tri_model_pending_q;
//     // // integer tri_model_delay_q;
//     // tri_result_t tri_model_result_q;
//     // tri_result_t tri_model_comb;
//     // tri_result_t tri_model_result_next;
//     // logic tri_model_request_fire;

//     // assign tri_req_ready_i = !tri_model_pending_q;

//     // assign tri_model_request_fire =
//     //     tri_req_valid_o && tri_req_ready_i;

//     // // Q16.16 word to real.
//     // function automatic real q16_to_real(input logic [31:0] x);
//     //     logic signed [31:0] sx;
//     //     begin
//     //         sx = x;
//     //         q16_to_real = $itor(sx) / 65536.0;
//     //     end
//     // endfunction

//     // // Real to Q16.16 word.
//     // function automatic logic [31:0] real_to_q16(input real x);
//     //     integer signed temp;
//     //     begin
//     //         temp = $rtoi(x * 65536.0);
//     //         real_to_q16 = temp;
//     //     end
//     // endfunction

//     // function automatic real vec_dot(
//     //     input real ax, input real ay, input real az,
//     //     input real bx, input real by, input real bz
//     // );
//     //     begin
//     //         vec_dot = ax*bx + ay*by + az*bz;
//     //     end
//     // endfunction

//     // function automatic real cross_x(
//     //     input real ay, input real az,
//     //     input real by, input real bz
//     // );
//     //     begin
//     //         cross_x = ay*bz - az*by;
//     //     end
//     // endfunction

//     // function automatic real cross_y(
//     //     input real az, input real ax,
//     //     input real bz, input real bx
//     // );
//     //     begin
//     //         cross_y = az*bx - ax*bz;
//     //     end
//     // endfunction

//     // function automatic real cross_z(
//     //     input real ax, input real ay,
//     //     input real bx, input real by
//     // );
//     //     begin
//     //         cross_z = ax*by - ay*bx;
//     //     end
//     // endfunction

//     // task automatic evaluate_triangle(
//     //     input tri_request_t req,
//     //     output tri_result_t res
//     // );
//     //     localparam real EPSILON = 1.0e-7;

//     //     real ox, oy, oz;
//     //     real dx, dy, dz;
//     //     real v0x, v0y, v0z;
//     //     real v1x, v1y, v1z;
//     //     real v2x, v2y, v2z;
//     //     real e1x, e1y, e1z;
//     //     real e2x, e2y, e2z;
//     //     real hx, hy, hz;
//     //     real sx, sy, sz;
//     //     real qx, qy, qz;
//     //     real det, inv_det, u, v, t;

//     //     begin
//     //         res = '0;
//     //         res.context_id   = req.context_id;
//     //         res.primitive_id = req.triangle.primitive_id;

//     //         ox = q16_to_real(req.ray.origin.x.data);
//     //         oy = q16_to_real(req.ray.origin.y.data);
//     //         oz = q16_to_real(req.ray.origin.z.data);

//     //         dx = q16_to_real(req.ray.direction.x.data);
//     //         dy = q16_to_real(req.ray.direction.y.data);
//     //         dz = q16_to_real(req.ray.direction.z.data);

//     //         v0x = q16_to_real(req.triangle.vertex1.x.data);
//     //         v0y = q16_to_real(req.triangle.vertex1.y.data);
//     //         v0z = q16_to_real(req.triangle.vertex1.z.data);

//     //         v1x = q16_to_real(req.triangle.vertex2.x.data);
//     //         v1y = q16_to_real(req.triangle.vertex2.y.data);
//     //         v1z = q16_to_real(req.triangle.vertex2.z.data);

//     //         v2x = q16_to_real(req.triangle.vertex3.x.data);
//     //         v2y = q16_to_real(req.triangle.vertex3.y.data);
//     //         v2z = q16_to_real(req.triangle.vertex3.z.data);

//     //         e1x = v1x - v0x;
//     //         e1y = v1y - v0y;
//     //         e1z = v1z - v0z;

//     //         e2x = v2x - v0x;
//     //         e2y = v2y - v0y;
//     //         e2z = v2z - v0z;

//     //         hx = cross_x(dy, dz, e2y, e2z);
//     //         hy = cross_y(dz, dx, e2z, e2x);
//     //         hz = cross_z(dx, dy, e2x, e2y);

//     //         det = vec_dot(e1x, e1y, e1z, hx, hy, hz);

//     //         if ((det > -EPSILON) && (det < EPSILON))
//     //             return;

//     //         inv_det = 1.0 / det;

//     //         sx = ox - v0x;
//     //         sy = oy - v0y;
//     //         sz = oz - v0z;

//     //         u = inv_det * vec_dot(sx, sy, sz, hx, hy, hz);
//     //         if ((u < 0.0) || (u > 1.0))
//     //             return;

//     //         qx = cross_x(sy, sz, e1y, e1z);
//     //         qy = cross_y(sz, sx, e1z, e1x);
//     //         qz = cross_z(sx, sy, e1x, e1y);

//     //         v = inv_det * vec_dot(dx, dy, dz, qx, qy, qz);
//     //         if ((v < 0.0) || ((u + v) > 1.0))
//     //             return;

//     //         t = inv_det * vec_dot(e2x, e2y, e2z, qx, qy, qz);

//     //         if (t < q16_to_real(req.ray.t_min.data))
//     //             return;

//     //         if (t > q16_to_real(req.ray.t_max.data))
//     //             return;

//     //         res.hit          = 1'b1;
//     //         res.t.data       = real_to_q16(t);
//     //         res.u.data       = real_to_q16(u);
//     //         res.v.data       = real_to_q16(v);
//     //         res.facing_front = (det < 0.0);
//     //     end
//     // endtask

//     // // Combinational reference calculation. The result is captured only when
//     // // a triangle request is accepted.
//     // always_comb begin
//     //     evaluate_triangle(tri_req_o, tri_model_comb);
//     // end

//     // // Keep sequential logic limited to reset and register updates.
//     // always_ff @(posedge clk or negedge rst_n) begin
//     //     if (!rst_n) begin
//     //         tri_model_pending_q     <= 1'b0;
//     //         tri_model_delay_q       <= 0;
//     //         tri_model_result_q      <= '0;
//     //         tri_result_valid_i      <= 1'b0;
//     //         tri_result_i            <= '0;
//     //         tri_intersection_count  <= 0;
//     //     end else begin
//     //         tri_result_valid_i <= 1'b0;

//     //         if (tri_model_pending_q) begin
//     //             if (tri_model_delay_q > 1) begin
//     //                 tri_model_delay_q <= tri_model_delay_q - 1;
//     //             end else begin
//     //                 tri_model_pending_q <= 1'b0;
//     //                 tri_result_valid_i  <= 1'b1;
//     //                 tri_result_i        <= tri_model_result_q;
//     //             end
//     //         end

//     //         if (tri_model_request_fire) begin
//     //             if (tri_model_pending_q)
//     //                 $fatal(1, "Triangle model accepted overlapping request");

//     //             tri_model_result_q     <= tri_model_comb;
//     //             tri_model_delay_q      <= TRI_MODEL_LATENCY;
//     //             tri_model_pending_q    <= 1'b1;
//     //             tri_intersection_count <= tri_intersection_count + 1;
//     //         end
//     //     end
//     // end

//     function automatic logic [31:0] q16(input real x);
//         integer signed temp;
//         begin
//             temp = $rtoi(x * 65536.0);
//             q16 = temp;
//         end
//     endfunction

//     function automatic fp32_t fx(input real x);
//         begin fx.data = q16(x); end
//     endfunction

//     function automatic float3_t vec3(input real x, input real y, input real z);
//         float3_t value;
//         begin
//             value.x.data = q16(x);
//             value.y.data = q16(y);
//             value.z.data = q16(z);
//             return value;
//         end
//     endfunction

//     task automatic set_triangle(
//         input integer idx,
//         input logic [15:0] prim,
//         input real z
//     );
//         begin
//             tri_mem[idx] = '0;
//             tri_mem[idx].primitive_id = prim;

//             tri_mem[idx].vertex1.x.data = q16(-1.0);
//             tri_mem[idx].vertex1.y.data = q16(-1.0);
//             tri_mem[idx].vertex1.z.data = q16(z);

//             tri_mem[idx].vertex2.x.data = q16(1.0);
//             tri_mem[idx].vertex2.y.data = q16(-1.0);
//             tri_mem[idx].vertex2.z.data = q16(z);

//             tri_mem[idx].vertex3.x.data = q16(0.0);
//             tri_mem[idx].vertex3.y.data = q16(1.0);
//             tri_mem[idx].vertex3.z.data = q16(z);

//             tri_present[idx] = 1'b1;
//         end
//     endtask

//     task automatic set_node(
//         input integer idx,
//         input real min_x, input real min_y, input real min_z,
//         input real max_x, input real max_y, input real max_z,
//         input logic [31:0] left_first,
//         input logic [31:0] tri_count
//     );
//         begin
//             node_mem[idx] = '0;

//             node_mem[idx].box.corner_a.x.data = q16(min_x);
//             node_mem[idx].box.corner_a.y.data = q16(min_y);
//             node_mem[idx].box.corner_a.z.data = q16(min_z);

//             node_mem[idx].box.corner_b.x.data = q16(max_x);
//             node_mem[idx].box.corner_b.y.data = q16(max_y);
//             node_mem[idx].box.corner_b.z.data = q16(max_z);

//             node_mem[idx].left_first = left_first;
//             node_mem[idx].tri_count = tri_count;

//             node_present[idx] = 1'b1;
//         end
//     endtask

//     task automatic clear_scene;
//         integer i;
//         begin
//             for (i = 0; i < NODE_COUNT; i++) begin
//                 node_mem[i] = '0;
//                 node_present[i] = 1'b0;
//             end
//             for (i = 0; i < TRI_COUNT; i++) begin
//                 tri_mem[i] = '0;
//                 tri_present[i] = 1'b0;
//             end
//         end
//     endtask

//     function automatic traversal_request_t make_request(
//         input addr_t root,
//         input real ox, input real oy, input real oz
//     );
//         traversal_request_t req;
//         begin
//             req = '0;
//             req.ray.ray_id = 16'h1234;
//             req.ray.origin = vec3(ox, oy, oz);
//             req.ray.direction = vec3(0.125, 0.125, 1.0);
//             req.context_id = 8'h2A;
//             req.bvh_root = root;
//             req.inv_direction = vec3(8.0, 8.0, 1.0);
//             req.t_min.data = q16(0.0);
//             req.t_max.data = q16(100.0);
//             return req;
//         end
//     endfunction

//     task automatic run_traversal(
//         input traversal_request_t req,
//         output traversal_result_t res
//     );
//         integer cycle_count;
//         begin
//             cycle_count = 0;
//             @(negedge clk);
//             traversal_i = req;
//             traversal_valid_i = 1'b1;
//             do begin
//                 @(posedge clk);
//                 cycle_count = cycle_count + 1;
//                 if (cycle_count > 1000)
//                     $fatal(1, "Timed out waiting for traversal request acceptance");
//             end while (!traversal_ready_o);
//             @(negedge clk);
//             traversal_valid_i = 1'b0;

//             cycle_count = 0;
//             while (!traversal_result_valid_o) begin
//                 @(negedge clk);
//                 cycle_count = cycle_count + 1;
//                 if (cycle_count > 3000)
//                     $fatal(1, "Timed out waiting for traversal result");
//             end
//             res = traversal_result_o;
//             if (stack_overflow_o)
//                 $fatal(1, "Traversal reported stack overflow");

//             // Allow result handshake to complete; next test may rewrite memory.
//             @(posedge clk);
//             @(negedge clk);
//         end
//     endtask

//     task automatic check_q16(
//         input string field_name,
//         input fp32_t actual,
//         input real expected_real,
//         input integer tolerance_lsb
//     );
//         integer signed actual_s, expected_s;
//         integer signed delta;
//         begin
//             actual_s = $signed(actual.data);
//             expected_s = $signed(q16(expected_real));
//             delta = actual_s - expected_s;
//             if ((delta > tolerance_lsb) || (delta < -tolerance_lsb))
//                 $fatal(1, "%s mismatch: got raw=%0d (%.6f), expected %.6f (raw=%0d)",
//                     field_name, actual_s, $itor(actual_s)/65536.0,
//                     expected_real, expected_s);
//         end
//     endtask

//     task automatic setup_simple_leaf;
//         begin
//             clear_scene();
//             set_triangle(0, 16'd7, 3.0);
//             set_node(0, -2.0, -2.0, 2.0, 2.0, 2.0, 4.0, TRI_BASE, 32'd1);
//         end
//     endtask

//     task automatic setup_two_child_bvh(input logic left_box_hits);
//         begin
//             clear_scene();
//             // Node 0 is internal. tri_count counts all descendant triangles.
//             set_node(0, -2.0, -2.0, 0.0, 2.0, 2.0, 6.0,
//                      BVH_BASE + NODE_BYTES, 32'd2);
//             // Left child: farther triangle at t=5.
//             if (left_box_hits)
//                 set_node(1, -2.0, -2.0, 4.5, 2.0, 2.0, 5.5,
//                          TRI_BASE, 32'd1);
//             else
//                 set_node(1, 4.0, 4.0, 4.5, 6.0, 6.0, 5.5,
//                          TRI_BASE, 32'd1);
//             // Right child: nearer triangle at t=3.
//             set_node(2, -2.0, -2.0, 2.5, 2.0, 2.0, 3.5,
//                      TRI_BASE + TRI_STRIDE, 32'd1);
//             set_triangle(0, 16'd11, 5.0);
//             set_triangle(1, 16'd22, 3.0);
//         end
//     endtask

//     integer bvh_before, tri_mem_before, aabb_before, tri_before;
//     traversal_result_t result;

//     initial begin
//         $dumpfile("waves/traversal_controller.vcd");
//         $dumpvars(0, traversal_controller_tb);
//     end

//     initial begin

//         traversal_valid_i = 1'b0;
//         traversal_i = '0;
//         traversal_result_ready_i = 1'b1;
//         clear_scene();

//         repeat (4) @(negedge clk);
//         rst_n = 1'b1;
//         repeat (3) @(negedge clk);

//         $display("[TEST 1] Single-leaf triangle hit");
//         setup_simple_leaf();
//         bvh_before = bvh_read_count;
//         tri_mem_before = tri_mem_read_count;
//         aabb_before = aabb_request_count;
//         tri_before = tri_intersection_count;
//         run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
//         if (!result.hit || result.primitive_id != 16'd7)
//             $fatal(1, "Single-leaf hit: wrong hit/primitive result");
//         check_q16("hit distance", result.distance, 3.0, 2);
//         check_q16("barycentric u", result.u, 0.25, 2);
//         check_q16("barycentric v", result.v, 0.5, 2);
//         if ((bvh_read_count-bvh_before) != 1 || (tri_mem_read_count-tri_mem_before) != 1 ||
//             (aabb_request_count-aabb_before) != 0 || (tri_intersection_count-tri_before) != 1)
//             $fatal(1, "Single-leaf hit: unexpected memory/intersection request counts");

//         $display("[TEST 2] Single-leaf triangle miss");
//         bvh_before = bvh_read_count;
//         tri_mem_before = tri_mem_read_count;
//         aabb_before = aabb_request_count;
//         tri_before = tri_intersection_count;
//         run_traversal(make_request(BVH_BASE, 8.0, 8.0, 0.0), result);
//         if (result.hit)
//             $fatal(1, "Single-leaf miss: unexpected hit");
//         if ((bvh_read_count-bvh_before) != 1 || (tri_mem_read_count-tri_mem_before) != 1 ||
//             (aabb_request_count-aabb_before) != 0 || (tri_intersection_count-tri_before) != 1)
//             $fatal(1, "Single-leaf miss: unexpected memory/intersection request counts");

//         $display("[TEST 3] Two-child BVH, nearest child first, far child pruned");
//         setup_two_child_bvh(1'b1);
//         bvh_before = bvh_read_count;
//         tri_mem_before = tri_mem_read_count;
//         aabb_before = aabb_request_count;
//         tri_before = tri_intersection_count;
//         run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
//         if (!result.hit || result.primitive_id != 16'd22)
//             $fatal(1, "Two-child traversal: nearest primitive was not returned");
//         check_q16("nearest hit distance", result.distance, 3.0, 2);
//         check_q16("nearest barycentric u", result.u, 0.25, 2);
//         check_q16("nearest barycentric v", result.v, 0.5, 2);
//         if ((aabb_request_count-aabb_before) != 2)
//             $fatal(1, "Two-child traversal: expected exactly two child AABB tests, got %0d",
//                    aabb_request_count-aabb_before);
//         if ((tri_intersection_count-tri_before) != 1)
//             $fatal(1, "Two-child traversal: expected far triangle to be pruned, tri tests=%0d",
//                    tri_intersection_count-tri_before);
//         if ((bvh_read_count-bvh_before) != 4)
//             $fatal(1, "Two-child traversal: expected 4 BVH reads (root, child metadata x2, near node), got %0d",
//                    bvh_read_count-bvh_before);
//         if ((tri_mem_read_count-tri_mem_before) != 1)
//             $fatal(1, "Two-child traversal: expected 1 triangle memory read");

//         $display("[TEST 4] One child AABB miss, other child hits");
//         setup_two_child_bvh(1'b0);
//         bvh_before = bvh_read_count;
//         aabb_before = aabb_request_count;
//         tri_before = tri_intersection_count;
//         run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
//         if (!result.hit || result.primitive_id != 16'd22)
//             $fatal(1, "One-child-hit traversal: wrong result");
//         if ((aabb_request_count-aabb_before) != 2 || (tri_intersection_count-tri_before) != 1)
//             $fatal(1, "One-child-hit traversal: unexpected AABB/triangle request count");

//         $display("[TEST 5] Internal node where both child AABBs miss");
//         setup_two_child_bvh(1'b0);

//         node_mem[2].box.corner_a.x.data = q16(4.0);
//         node_mem[2].box.corner_a.y.data = q16(4.0);
//         node_mem[2].box.corner_a.z.data = q16(2.5);

//         node_mem[2].box.corner_b.x.data = q16(6.0);
//         node_mem[2].box.corner_b.y.data = q16(6.0);
//         node_mem[2].box.corner_b.z.data = q16(3.5);

//         aabb_before = aabb_request_count;
//         tri_before = tri_intersection_count;
//         run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
//         if (result.hit)
//             $fatal(1, "Both-child-miss traversal unexpectedly hit");
//         if ((aabb_request_count-aabb_before) != 2 || (tri_intersection_count-tri_before) != 0)
//             $fatal(1, "Both-child-miss traversal: unexpected AABB/triangle request count");

//         $display("[TEST 6] Empty root leaf");
//         clear_scene();
//         set_node(0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, '0, 32'd0);
//         bvh_before = bvh_read_count;
//         tri_mem_before = tri_mem_read_count;
//         aabb_before = aabb_request_count;
//         tri_before = tri_intersection_count;
//         run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
//         if (result.hit || result.distance.data != 0 || result.primitive_id != 0)
//             $fatal(1, "Empty root did not return a clean miss");
//         if ((bvh_read_count-bvh_before) != 1 || (tri_mem_read_count-tri_mem_before) != 0 ||
//             (aabb_request_count-aabb_before) != 0 || (tri_intersection_count-tri_before) != 0)
//             $fatal(1, "Empty root: unexpected memory/intersection request counts");

//         $display("PASS: all initial BVH traversal integration tests passed");
//         $finish;
//     end

//     // Transaction counters. Count request handshakes, not response cycles.
//     always_ff @(posedge clk or negedge rst_n) begin
//         if (!rst_n) begin
//             aabb_request_count <= 0;
//         end else if (aabb_req_valid_o && aabb_req_ready_i) begin
//             aabb_request_count <= aabb_request_count + 1;
//         end
//     end

// endmodule
