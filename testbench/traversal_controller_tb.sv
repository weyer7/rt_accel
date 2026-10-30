`timescale 1ns/1ps
`include "rtu_pkg.svh"

/*

Initial integration testbench for bvh_traversal_controller.
Prototyped with ChatGPT
Will add file parsing in the future to accept BVH files and compare
RTL with software reference (similar to 437 test environment)
*/
module traversal_controller_tb;
    localparam addr_t BVH_BASE = 32'h1000_0000;
    localparam addr_t TRI_BASE = 32'h2000_0000;
    localparam int NODE_BYTES = 32;
    localparam int TRI_STRIDE = 40; // must match controller parameter
    localparam int NODE_COUNT = 8;
    localparam int TRI_COUNT = 8;
    localparam int MEM_LATENCY = 2;
    localparam int TRI_MODEL_LATENCY = 2;
    localparam int DEBUG_LEVEL = 1; // 0=quiet, 1=transaction trace

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    // Traversal request / result.
    logic traversal_valid_i;
    logic traversal_ready_o;
    traversal_request_t traversal_i;
    logic traversal_result_valid_o;
    logic traversal_result_ready_i;
    traversal_result_t traversal_result_o;
    logic stack_overflow_o;

    // Simulated node memory.
    logic bvh_mem_req_valid_o, bvh_mem_req_ready_i;
    addr_t bvh_mem_req_addr_o;
    logic bvh_mem_resp_valid_i, bvh_mem_resp_error_i;
    bvh_node_t bvh_mem_resp_data_i;

    // Simulated triangle memory.
    logic tri_mem_req_valid_o, tri_mem_req_ready_i;
    addr_t tri_mem_req_addr_o;
    logic tri_mem_resp_valid_i, tri_mem_resp_error_i;
    triangle_t tri_mem_resp_data_i;

    // Real AABB pipeline interface.
    logic aabb_req_valid_o, aabb_req_ready_i;
    aabb_request_t aabb_req_o;
    logic aabb_result_valid_i;
    aabb_result_t aabb_result_i;

    // Simulation-only triangle intersection model interface.
    logic tri_req_valid_o, tri_req_ready_i;
    tri_request_t tri_req_o;
    logic tri_result_valid_i;
    tri_result_t tri_result_i;

    bvh_node_t node_mem [0:NODE_COUNT-1];
    triangle_t tri_mem [0:TRI_COUNT-1];
    logic [NODE_COUNT-1:0] node_present;
    logic [TRI_COUNT-1:0] tri_present;

    integer bvh_read_count;
    integer tri_mem_read_count;
    integer aabb_request_count;
    integer tri_intersection_count;
    integer test_case;
    integer error_count;
    integer bvh_before, tri_mem_before, aabb_before, tri_before;
    traversal_result_t result;
    traversal_request_t test_req;

    traversal_controller #(
        .STACK_DEPTH(16),
        .TRIANGLE_STRIDE_BYTES(TRI_STRIDE)
    ) u_dut (
        .clk(clk), .rst_n(rst_n),
        .traversal_valid_i(traversal_valid_i),
        .traversal_ready_o(traversal_ready_o),
        .traversal_i(traversal_i),
        .bvh_mem_req_valid_o(bvh_mem_req_valid_o),
        .bvh_mem_req_ready_i(bvh_mem_req_ready_i),
        .bvh_mem_req_addr_o(bvh_mem_req_addr_o),
        .bvh_mem_resp_valid_i(bvh_mem_resp_valid_i),
        .bvh_mem_resp_error_i(bvh_mem_resp_error_i),
        .bvh_mem_resp_data_i(bvh_mem_resp_data_i),
        .tri_mem_req_valid_o(tri_mem_req_valid_o),
        .tri_mem_req_ready_i(tri_mem_req_ready_i),
        .tri_mem_req_addr_o(tri_mem_req_addr_o),
        .tri_mem_resp_valid_i(tri_mem_resp_valid_i),
        .tri_mem_resp_error_i(tri_mem_resp_error_i),
        .tri_mem_resp_data_i(tri_mem_resp_data_i),
        .aabb_req_valid_o(aabb_req_valid_o),
        .aabb_req_ready_i(aabb_req_ready_i),
        .aabb_req_o(aabb_req_o),
        .aabb_result_valid_i(aabb_result_valid_i),
        .aabb_result_i(aabb_result_i),
        .tri_req_valid_o(tri_req_valid_o),
        .tri_req_ready_i(tri_req_ready_i),
        .tri_req_o(tri_req_o),
        .tri_result_valid_i(tri_result_valid_i),
        .tri_result_i(tri_result_i),
        .traversal_result_valid_o(traversal_result_valid_o),
        .traversal_result_ready_i(traversal_result_ready_i),
        .traversal_result_o(traversal_result_o),
        .stack_overflow_o(stack_overflow_o)
    );

    // Existing verified 10-stage AABB pipeline. Its exact interface matches
    // the standalone AABB testbench (`request`, `valid_i`, `ready_o`, etc.).
    q16p16_aabb_intersect u_aabb (
        .clk(clk),
        .n_rst(rst_n),
        .request(aabb_req_o),
        .valid_i(aabb_req_valid_o),
        .ready_o(aabb_req_ready_i),
        .result(aabb_result_i),
        .valid_o(aabb_result_valid_i),
        .ready_i(1'b1)
    );

    // // Memory responses have fixed, configurable simulation latency. Only one
    // // read per port may be outstanding, matching the controller's contract.
    logic bvh_pending_q, tri_mem_pending_q;
    integer bvh_delay_q, tri_mem_delay_q;
    bvh_node_t bvh_data_pending_q;
    logic bvh_error_pending_q;
    triangle_t tri_data_pending_q;
    logic tri_mem_error_pending_q;

    assign bvh_mem_req_ready_i = !bvh_pending_q;
    assign tri_mem_req_ready_i = !tri_mem_pending_q;

    function automatic logic bvh_addr_valid(input addr_t addr);
        integer idx;
        begin
            bvh_addr_valid = 1'b0;
            if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
                idx = (addr - BVH_BASE) / NODE_BYTES;
                if ((idx >= 0) && (idx < NODE_COUNT))
                    bvh_addr_valid = node_present[idx];
            end
        end
    endfunction

    function automatic bvh_node_t bvh_lookup(input addr_t addr);
        integer idx;
        begin
            bvh_lookup = '0;
            if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
                idx = (addr - BVH_BASE) / NODE_BYTES;
                if ((idx >= 0) && (idx < NODE_COUNT))
                    bvh_lookup = node_mem[idx];
            end
        end
    endfunction

    function automatic logic tri_addr_valid(input addr_t addr);
        integer idx;
        begin
            tri_addr_valid = 1'b0;
            if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
                idx = (addr - TRI_BASE) / TRI_STRIDE;
                if ((idx >= 0) && (idx < TRI_COUNT))
                    tri_addr_valid = tri_present[idx];
            end
        end
    endfunction

    function automatic triangle_t tri_lookup(input addr_t addr);
        integer idx;
        begin
            tri_lookup = '0;
            if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
                idx = (addr - TRI_BASE) / TRI_STRIDE;
                if ((idx >= 0) && (idx < TRI_COUNT))
                    tri_lookup = tri_mem[idx];
            end
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bvh_pending_q       <= 1'b0;
            bvh_delay_q         <= 0;
            bvh_data_pending_q  <= '0;
            bvh_error_pending_q <= 1'b0;
            bvh_mem_resp_valid_i <= 1'b0;
            bvh_mem_resp_error_i <= 1'b0;
            bvh_mem_resp_data_i <= '0;
            bvh_read_count      <= 0;
        end else begin
            bvh_mem_resp_valid_i <= 1'b0;
            if (bvh_pending_q) begin
                if (bvh_delay_q > 1) begin
                    bvh_delay_q <= bvh_delay_q - 1;
                end else begin
                    bvh_pending_q        <= 1'b0;
                    bvh_mem_resp_valid_i <= 1'b1;
                    bvh_mem_resp_error_i <= bvh_error_pending_q;
                    bvh_mem_resp_data_i  <= bvh_data_pending_q;
                end
            end
            if (bvh_mem_req_valid_o && bvh_mem_req_ready_i) begin
                bvh_pending_q       <= 1'b1;
                bvh_delay_q         <= MEM_LATENCY;
                bvh_data_pending_q  <= bvh_lookup(bvh_mem_req_addr_o);
                bvh_error_pending_q <= !bvh_addr_valid(bvh_mem_req_addr_o);
                bvh_read_count      <= bvh_read_count + 1;
            end
        end
    end

    // Simulation-only triangle intersection model. One request may be
    // outstanding; the result is returned after TRI_MODEL_LATENCY cycles.
    logic tri_model_pending_q;
    integer tri_model_delay_q;
    tri_result_t tri_model_result_q;
    tri_result_t tri_model_comb;
    logic tri_model_request_fire;

    assign tri_req_ready_i = !tri_model_pending_q;
    assign tri_model_request_fire = tri_req_valid_o && tri_req_ready_i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tri_mem_pending_q    <= 1'b0;
            tri_mem_delay_q      <= 0;
            tri_data_pending_q   <= '0;
            tri_mem_error_pending_q <= 1'b0;
            tri_mem_resp_valid_i <= 1'b0;
            tri_mem_resp_error_i <= 1'b0;
            tri_mem_resp_data_i  <= '0;
            tri_mem_read_count   <= 0;
        end else begin
            tri_mem_resp_valid_i <= 1'b0;
            if (tri_mem_pending_q) begin
                if (tri_mem_delay_q > 1) begin
                    tri_mem_delay_q <= tri_mem_delay_q - 1;
                end else begin
                    tri_mem_pending_q    <= 1'b0;
                    tri_mem_resp_valid_i <= 1'b1;
                    tri_mem_resp_error_i <= tri_mem_error_pending_q;
                    tri_mem_resp_data_i  <= tri_data_pending_q;
                end
            end
            if (tri_mem_req_valid_o && tri_mem_req_ready_i) begin
                tri_mem_pending_q       <= 1'b1;
                tri_mem_delay_q         <= MEM_LATENCY;
                tri_data_pending_q      <= tri_lookup(tri_mem_req_addr_o);
                tri_mem_error_pending_q <= !tri_addr_valid(tri_mem_req_addr_o);
                tri_mem_read_count      <= tri_mem_read_count + 1;
            end
        end
    end

    // Q16.16 word to real.
    function automatic real q16_to_real(input logic [31:0] x);
        logic signed [31:0] sx;
        begin
            sx = x;
            q16_to_real = $itor(sx) / 65536.0;
        end
    endfunction

    // Real to Q16.16 word.
    function automatic logic [31:0] real_to_q16(input real x);
        integer signed temp;
        begin
            temp = $rtoi(x * 65536.0);
            real_to_q16 = temp;
        end
    endfunction

    function automatic real vec_dot(
        input real ax, input real ay, input real az,
        input real bx, input real by, input real bz
    );
        begin
            vec_dot = ax*bx + ay*by + az*bz;
        end
    endfunction

    function automatic real cross_x(
        input real ay, input real az,
        input real by, input real bz
    );
        begin
            cross_x = ay*bz - az*by;
        end
    endfunction

    function automatic real cross_y(
        input real az, input real ax,
        input real bz, input real bx
    );
        begin
            cross_y = az*bx - ax*bz;
        end
    endfunction

    function automatic real cross_z(
        input real ax, input real ay,
        input real bx, input real by
    );
        begin
            cross_z = ax*by - ay*bx;
        end
    endfunction

    // Software reference for the triangle-intersection interface.
    // Uses Moller-Trumbore in real arithmetic; the DUT-facing values remain
    // Q16.16. The nested checks avoid task early-return syntax for Icarus.
    task automatic evaluate_triangle(
        input tri_request_t req,
        output tri_result_t res
    );
        real ox, oy, oz;
        real dx, dy, dz;
        real v0x, v0y, v0z;
        real v1x, v1y, v1z;
        real v2x, v2y, v2z;
        real e1x, e1y, e1z;
        real e2x, e2y, e2z;
        real hx, hy, hz;
        real sx, sy, sz;
        real qx, qy, qz;
        real det, inv_det, u, v, t;
        begin
            res = '0;
            res.context_id   = req.context_id;
            res.primitive_id = req.triangle.primitive_id;

            ox = q16_to_real(req.ray.origin.x.data);
            oy = q16_to_real(req.ray.origin.y.data);
            oz = q16_to_real(req.ray.origin.z.data);

            dx = q16_to_real(req.ray.direction.x.data);
            dy = q16_to_real(req.ray.direction.y.data);
            dz = q16_to_real(req.ray.direction.z.data);

            v0x = q16_to_real(req.triangle.vertex1.x.data);
            v0y = q16_to_real(req.triangle.vertex1.y.data);
            v0z = q16_to_real(req.triangle.vertex1.z.data);

            v1x = q16_to_real(req.triangle.vertex2.x.data);
            v1y = q16_to_real(req.triangle.vertex2.y.data);
            v1z = q16_to_real(req.triangle.vertex2.z.data);

            v2x = q16_to_real(req.triangle.vertex3.x.data);
            v2y = q16_to_real(req.triangle.vertex3.y.data);
            v2z = q16_to_real(req.triangle.vertex3.z.data);

            e1x = v1x - v0x;
            e1y = v1y - v0y;
            e1z = v1z - v0z;

            e2x = v2x - v0x;
            e2y = v2y - v0y;
            e2z = v2z - v0z;

            hx = cross_x(dy, dz, e2y, e2z);
            hy = cross_y(dz, dx, e2z, e2x);
            hz = cross_z(dx, dy, e2x, e2y);

            det = vec_dot(e1x, e1y, e1z, hx, hy, hz);

            // Reject degenerate or nearly parallel ray/triangle pairs.
            if ((det <= -1.0e-7) || (det >= 1.0e-7)) begin
                inv_det = 1.0 / det;

                sx = ox - v0x;
                sy = oy - v0y;
                sz = oz - v0z;

                u = inv_det * vec_dot(sx, sy, sz, hx, hy, hz);

                if ((u >= 0.0) && (u <= 1.0)) begin
                    qx = cross_x(sy, sz, e1y, e1z);
                    qy = cross_y(sz, sx, e1z, e1x);
                    qz = cross_z(sx, sy, e1x, e1y);

                    v = inv_det * vec_dot(dx, dy, dz, qx, qy, qz);

                    if ((v >= 0.0) && ((u + v) <= 1.0)) begin
                        t = inv_det * vec_dot(e2x, e2y, e2z, qx, qy, qz);

                        if ((t >= q16_to_real(req.ray.t_min.data)) &&
                            (t <= q16_to_real(req.ray.t_max.data))) begin
                            res.hit          = 1'b1;
                            res.t.data       = real_to_q16(t);
                            res.u.data       = real_to_q16(u);
                            res.v.data       = real_to_q16(v);
                            res.facing_front = (det < 0.0);
                        end
                    end
                end
            end
        end
    endtask

    // Re-evaluate the currently presented request; the sequential model only
    // captures this value when the request handshake occurs.
    always @* begin
        evaluate_triangle(tri_req_o, tri_model_comb);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tri_model_pending_q    <= 1'b0;
            tri_model_delay_q      <= 0;
            tri_model_result_q     <= '0;
            tri_result_valid_i     <= 1'b0;
            tri_result_i           <= '0;
            tri_intersection_count <= 0;
        end else begin
            tri_result_valid_i <= 1'b0;

            if (tri_model_pending_q) begin
                if (tri_model_delay_q > 1) begin
                    tri_model_delay_q <= tri_model_delay_q - 1;
                end else begin
                    tri_model_pending_q <= 1'b0;
                    tri_result_valid_i  <= 1'b1;
                    tri_result_i        <= tri_model_result_q;
                end
            end

            if (tri_model_request_fire) begin
                tri_model_result_q     <= tri_model_comb;
                tri_model_pending_q    <= 1'b1;
                tri_model_delay_q      <= TRI_MODEL_LATENCY;
                tri_intersection_count <= tri_intersection_count + 1;
            end
        end
    end

    function automatic logic [31:0] /*fp32_t*/ q16(input real x);
        integer signed temp;
        begin
            temp = $rtoi(x * 65536.0);
            q16 = temp;
        end
    endfunction

    function automatic logic [31:0] /*fp32_t*/ fx(input real x);
        begin fx = q16(x); end
    endfunction

    function automatic float3_t vec3(input real x, input real y, input real z);
        float3_t value;
        begin
            value.x.data = q16(x);
            value.y.data = q16(y);
            value.z.data = q16(z);
            return value;
        end
    endfunction

    task automatic set_triangle(
        input integer idx,
        input logic [15:0] prim,
        input real z
    );
        triangle_t temp;
        begin
            temp = '0;

            temp.primitive_id = prim;

            temp.vertex1.x.data = q16(-1.0);
            temp.vertex1.y.data = q16(-1.0);
            temp.vertex1.z.data = q16(z);

            temp.vertex2.x.data = q16(1.0);
            temp.vertex2.y.data = q16(-1.0);
            temp.vertex2.z.data = q16(z);

            temp.vertex3.x.data = q16(0.0);
            temp.vertex3.y.data = q16(1.0);
            temp.vertex3.z.data = q16(z);

            tri_mem[idx] = temp;
            tri_present[idx] = 1'b1;
        end
    endtask

    task automatic set_node(
        input integer idx,
        input real min_x, input real min_y, input real min_z,
        input real max_x, input real max_y, input real max_z,
        input addr_t left_first,
        input logic [31:0] tri_count
    );
        bvh_node_t temp;
        begin
            temp = '0;

            temp.box.corner_a.x.data = q16(min_x);
            temp.box.corner_a.y.data = q16(min_y);
            temp.box.corner_a.z.data = q16(min_z);

            temp.box.corner_b.x.data = q16(max_x);
            temp.box.corner_b.y.data = q16(max_y);
            temp.box.corner_b.z.data = q16(max_z);

            temp.left_first = left_first;
            temp.tri_count = tri_count;

            node_mem[idx] = temp;
            node_present[idx] = 1'b1;
        end
    endtask

    // Human-readable scene dump. This is also a useful validation hook when
    // node/triangle arrays are later populated by a file parser.
    task automatic dump_scene(input string label);
        integer i;
        bvh_node_t node_temp;
        triangle_t tri_temp;
        begin
            $display("[SCENE] %s", label);
            for (i = 0; i < NODE_COUNT; i = i + 1) begin
                if (node_present[i]) begin
                    node_temp = node_mem[i];
                    $display("[SCENE] node[%0d] addr=%08h leaf=%0b tri_count=%0d left_first=%08h boxMin=(%.4f,%.4f,%.4f) boxMax=(%.4f,%.4f,%.4f)",
                        i, BVH_BASE + i*NODE_BYTES,
                        (node_temp.tri_count != 0),
                        node_temp.tri_count, node_temp.left_first,
                        q16_to_real(node_temp.box.corner_a.x.data),
                        q16_to_real(node_temp.box.corner_a.y.data),
                        q16_to_real(node_temp.box.corner_a.z.data),
                        q16_to_real(node_temp.box.corner_b.x.data),
                        q16_to_real(node_temp.box.corner_b.y.data),
                        q16_to_real(node_temp.box.corner_b.z.data));
                end
            end
            for (i = 0; i < TRI_COUNT; i = i + 1) begin
                if (tri_present[i]) begin
                    tri_temp = tri_mem[i];
                    $display("[SCENE] tri[%0d] addr=%08h prim=%0d v0=(%.4f,%.4f,%.4f) v1=(%.4f,%.4f,%.4f) v2=(%.4f,%.4f,%.4f)",
                        i, TRI_BASE + i*TRI_STRIDE, tri_temp.primitive_id,
                        q16_to_real(tri_temp.vertex1.x.data),
                        q16_to_real(tri_temp.vertex1.y.data),
                        q16_to_real(tri_temp.vertex1.z.data),
                        q16_to_real(tri_temp.vertex2.x.data),
                        q16_to_real(tri_temp.vertex2.y.data),
                        q16_to_real(tri_temp.vertex2.z.data),
                        q16_to_real(tri_temp.vertex3.x.data),
                        q16_to_real(tri_temp.vertex3.y.data),
                        q16_to_real(tri_temp.vertex3.z.data));
                end
            end
        end
    endtask

    task automatic clear_scene;
        integer i;
        begin
            for (i = 0; i < NODE_COUNT; i++) begin
                node_mem[i] = '0;
                node_present[i] = 1'b0;
            end
            for (i = 0; i < TRI_COUNT; i++) begin
                tri_mem[i] = '0;
                tri_present[i] = 1'b0;
            end
        end
    endtask

    function automatic traversal_request_t make_request(
        input addr_t root,
        input real ox, input real oy, input real oz
    );
        traversal_request_t req;
        begin
            req = '0;
            req.ray.ray_id = 16'h1234;
            req.ray.origin = vec3(ox, oy, oz);
            req.ray.direction = vec3(0.125, 0.125, 1.0);
            req.context_id = 8'h2A;
            req.bvh_root = root;
            req.inv_direction = vec3(8.0, 8.0, 1.0);
            req.t_min.data = q16(0.0);
            req.t_max.data = q16(100.0);
            return req;
        end
    endfunction

    task automatic run_traversal(
        input traversal_request_t req,
        output traversal_result_t res
    );
        integer cycle_count;
        begin
            cycle_count = 0;
            @(negedge clk);
            traversal_i = req;
            traversal_valid_i = 1'b1;
            do begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                if (cycle_count > 1000)
                    $fatal(1, "[TEST %0d] Timed out waiting for traversal request acceptance", test_case);
            end while (!traversal_ready_o);
            @(negedge clk);
            traversal_valid_i = 1'b0;

            cycle_count = 0;
            while (!traversal_result_valid_o) begin
                @(negedge clk);
                cycle_count = cycle_count + 1;
                if (cycle_count > 3000)
                    $fatal(1, "[TEST %0d] Timed out waiting for traversal result", test_case);
            end
            res = traversal_result_o;
            if (stack_overflow_o)
                $fatal(1, "[TEST %0d] Traversal reported stack overflow", test_case);

            // Allow result handshake to complete; next test may rewrite memory.
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    task automatic check_q16(
        input string field_name,
        input fp32_t actual,
        input real expected_real,
        input integer tolerance_lsb
    );
        integer signed actual_s, expected_s;
        integer signed delta;
        begin
            actual_s = $signed(actual.data);
            expected_s = $signed(q16(expected_real));
            delta = actual_s - expected_s;
            if ((delta > tolerance_lsb) || (delta < -tolerance_lsb)) begin
                error_count = error_count + 1;
                $display("[FAIL][TEST %0d] %s mismatch: got raw=%0d (%.6f), expected %.6f (raw=%0d)",
                    test_case, field_name, actual_s, $itor(actual_s)/65536.0,
                    expected_real, expected_s);
            end
        end
    endtask

    task automatic check_condition(input logic condition, input string message);
        begin
            if (!condition) begin
                error_count = error_count + 1;
                $display("[FAIL][TEST %0d] %s", test_case, message);
            end
        end
    endtask

    task automatic report_test_summary(input string label, input traversal_result_t res);
        begin
            $display("[SUMMARY][TEST %0d] %s: hit=%0b prim=%0d t=%.6f u=%.6f v=%.6f | BVH=%0d TRI_MEM=%0d AABB=%0d TRI_TEST=%0d",
                test_case, label, res.hit, res.primitive_id,
                q16_to_real(res.distance.data), q16_to_real(res.u.data),
                q16_to_real(res.v.data), bvh_read_count-bvh_before,
                tri_mem_read_count-tri_mem_before,
                aabb_request_count-aabb_before,
                tri_intersection_count-tri_before);
        end
    endtask

    // Transaction-level trace. This observes the existing AABB pipeline; it
    // does not modify or replace it. Set DEBUG_LEVEL=0 to silence the trace.
    always @(posedge clk) begin
        if (rst_n && (DEBUG_LEVEL > 0)) begin
            if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
                $display("[%0t][TEST %0d] BVH_REQ  addr=%08h", $time, test_case, bvh_mem_req_addr_o);

            if (bvh_mem_resp_valid_i)
                $display("[%0t][TEST %0d] BVH_RESP err=%0b tri_count=%0d left_first=%08h",
                    $time, test_case, bvh_mem_resp_error_i,
                    bvh_mem_resp_data_i.tri_count, bvh_mem_resp_data_i.left_first);

            if (tri_mem_req_valid_o && tri_mem_req_ready_i)
                $display("[%0t][TEST %0d] TRI_MEM_REQ addr=%08h", $time, test_case, tri_mem_req_addr_o);

            if (tri_mem_resp_valid_i)
                $display("[%0t][TEST %0d] TRI_MEM_RESP err=%0b prim=%0d",
                    $time, test_case, tri_mem_resp_error_i, tri_mem_resp_data_i.primitive_id);

            if (aabb_req_valid_o && aabb_req_ready_i)
                $display("[%0t][TEST %0d] AABB_REQ ctx=%0d O=(%.4f,%.4f,%.4f) invD=(%.4f,%.4f,%.4f) boxMin=(%.4f,%.4f,%.4f) boxMax=(%.4f,%.4f,%.4f)",
                    $time, test_case, aabb_req_o.context_id,
                    q16_to_real(aabb_req_o.ray.origin.x.data),
                    q16_to_real(aabb_req_o.ray.origin.y.data),
                    q16_to_real(aabb_req_o.ray.origin.z.data),
                    q16_to_real(aabb_req_o.ray.inv_direction.x.data),
                    q16_to_real(aabb_req_o.ray.inv_direction.y.data),
                    q16_to_real(aabb_req_o.ray.inv_direction.z.data),
                    q16_to_real(aabb_req_o.box.corner_a.x.data),
                    q16_to_real(aabb_req_o.box.corner_a.y.data),
                    q16_to_real(aabb_req_o.box.corner_a.z.data),
                    q16_to_real(aabb_req_o.box.corner_b.x.data),
                    q16_to_real(aabb_req_o.box.corner_b.y.data),
                    q16_to_real(aabb_req_o.box.corner_b.z.data));

            if (aabb_result_valid_i)
                $display("[%0t][TEST %0d] AABB_RESP ctx=%0d hit=%0b tNear=%.6f tFar=%.6f",
                    $time, test_case, aabb_result_i.context_id, aabb_result_i.hit,
                    q16_to_real(aabb_result_i.t_near.data),
                    q16_to_real(aabb_result_i.t_far.data));

            if (tri_req_valid_o && tri_req_ready_i)
                $display("[%0t][TEST %0d] TRI_REQ ctx=%0d prim=%0d O=(%.4f,%.4f,%.4f) D=(%.4f,%.4f,%.4f) tMin=%.4f tMax=%.4f modelHit=%0b modelT=%.6f u=%.6f v=%.6f",
                    $time, test_case, tri_req_o.context_id,
                    tri_req_o.triangle.primitive_id,
                    q16_to_real(tri_req_o.ray.origin.x.data),
                    q16_to_real(tri_req_o.ray.origin.y.data),
                    q16_to_real(tri_req_o.ray.origin.z.data),
                    q16_to_real(tri_req_o.ray.direction.x.data),
                    q16_to_real(tri_req_o.ray.direction.y.data),
                    q16_to_real(tri_req_o.ray.direction.z.data),
                    q16_to_real(tri_req_o.ray.t_min.data),
                    q16_to_real(tri_req_o.ray.t_max.data),
                    tri_model_comb.hit, q16_to_real(tri_model_comb.t.data),
                    q16_to_real(tri_model_comb.u.data),
                    q16_to_real(tri_model_comb.v.data));

            if (tri_result_valid_i)
                $display("[%0t][TEST %0d] TRI_RESP ctx=%0d hit=%0b prim=%0d t=%.6f u=%.6f v=%.6f",
                    $time, test_case, tri_result_i.context_id,
                    tri_result_i.hit, tri_result_i.primitive_id,
                    q16_to_real(tri_result_i.t.data),
                    q16_to_real(tri_result_i.u.data),
                    q16_to_real(tri_result_i.v.data));

            if (traversal_result_valid_o && traversal_result_ready_i)
                $display("[%0t][TEST %0d] TRAVERSAL_RESP hit=%0b prim=%0d t=%.6f u=%.6f v=%.6f",
                    $time, test_case, traversal_result_o.hit,
                    traversal_result_o.primitive_id,
                    q16_to_real(traversal_result_o.distance.data),
                    q16_to_real(traversal_result_o.u.data),
                    q16_to_real(traversal_result_o.v.data));
        end
    end

    task automatic setup_simple_leaf;
        begin
            clear_scene();
            set_triangle(0, 16'd7, 3.0);
            set_node(0, -2.0, -2.0, 2.0, 2.0, 2.0, 4.0, TRI_BASE, 32'd1);
        end
    endtask

    task automatic setup_two_child_bvh(input logic left_box_hits);
        begin
            clear_scene();
            // Node 0 is internal. tri_count counts all descendant triangles.
            set_node(0, -2.0, -2.0, 0.0, 2.0, 2.0, 6.0,
                     BVH_BASE + NODE_BYTES, 32'd2);
            // Left child: farther triangle at t=5.
            if (left_box_hits)
                set_node(1, -2.0, -2.0, 4.5, 2.0, 2.0, 5.5,
                         TRI_BASE, 32'd1);
            else
                set_node(1, 4.0, 4.0, 4.5, 6.0, 6.0, 5.5,
                         TRI_BASE, 32'd1);
            // Right child: nearer triangle at t=3.
            set_node(2, -2.0, -2.0, 2.5, 2.0, 2.0, 3.5,
                     TRI_BASE + TRI_STRIDE, 32'd1);
            set_triangle(0, 16'd11, 5.0);
            set_triangle(1, 16'd22, 3.0);
        end
    endtask

    task reset_counts();
        begin
            aabb_request_count = 0;
            tri_intersection_count = 0;
        end
    endtask

    initial begin
        $dumpfile("waves/traversal_controller.vcd");
        $dumpvars(0, traversal_controller_tb);
    end

    initial begin
        test_case = 0;
        error_count = 0;
        traversal_valid_i = 1'b0;
        traversal_i = '0;
        traversal_result_ready_i = 1'b1;
        clear_scene();

        repeat (4) @(negedge clk);
        rst_n = 1'b1;
        repeat (3) @(negedge clk);

        // ------------------------------------------------------------
        // TEST 1: One triangle, direct hit.
        // ------------------------------------------------------------
        $display("\n[TEST 1] Single-leaf triangle hit");
        test_case = 1;
        reset_counts();
        setup_simple_leaf();
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(result.hit && (result.primitive_id == 16'd7),
                        "Expected hit on primitive 7");
        check_q16("hit distance", result.distance, 3.0, 2);
        check_q16("barycentric u", result.u, 0.25, 2);
        check_q16("barycentric v", result.v, 0.5, 2);
        check_condition((bvh_read_count-bvh_before) == 1 &&
                        (tri_mem_read_count-tri_mem_before) == 1 &&
                        (aabb_request_count-aabb_before) == 0 &&
                        (tri_intersection_count-tri_before) == 1,
                        "Unexpected BVH/triangle/AABB transaction counts");
        report_test_summary("single triangle hit", result);

        // ------------------------------------------------------------
        // TEST 2: Ray misses the single root-leaf triangle.
        // ------------------------------------------------------------
        $display("\n[TEST 2] Single-leaf ray miss");
        test_case = 2;
        reset_counts();
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, 8.0, 8.0, 0.0), result);
        check_condition(!result.hit, "Expected a miss");
        check_condition((bvh_read_count-bvh_before) == 1 &&
                        (tri_mem_read_count-tri_mem_before) == 1 &&
                        (aabb_request_count-aabb_before) == 0 &&
                        (tri_intersection_count-tri_before) == 1,
                        "Unexpected BVH/triangle/AABB transaction counts");
        report_test_summary("single triangle miss", result);

        // ------------------------------------------------------------
        // TEST 3: Both child boxes intersect. Near child is node 2 / prim 22.
        // This currently exposes the reported far-child-first result.
        // ------------------------------------------------------------
        $display("\n[TEST 3] Two intersecting children; closest hit must win");
        test_case = 3;
        reset_counts();
        setup_two_child_bvh(1'b1);
        if (DEBUG_LEVEL > 1)
            dump_scene("two intersecting children");
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(result.hit && (result.primitive_id == 16'd22),
                        "Expected nearer primitive 22 (z=3), not farther primitive 11 (z=5)");
        check_q16("nearest hit distance", result.distance, 3.0, 2);
        check_q16("nearest barycentric u", result.u, 0.25, 2);
        check_q16("nearest barycentric v", result.v, 0.5, 2);
        check_condition((aabb_request_count-aabb_before) == 2,
                        "Expected two child AABB requests");
        check_condition((tri_intersection_count-tri_before) == 1,
                        "Expected only the near triangle to be tested after pruning");
        check_condition((bvh_read_count-bvh_before) == 4,
                        "Expected four BVH reads (root, two child metadata reads, selected leaf)");
        check_condition((tri_mem_read_count-tri_mem_before) == 1,
                        "Expected one triangle memory read");
        report_test_summary("two intersecting children", result);

        // ------------------------------------------------------------
        // TEST 4: Left child misses; right child intersects.
        // ------------------------------------------------------------
        $display("\n[TEST 4] Left child AABB miss; right child hit");
        test_case = 4;
        reset_counts();
        setup_two_child_bvh(1'b0);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(result.hit && (result.primitive_id == 16'd22),
                        "Expected right-child primitive 22");
        check_condition((aabb_request_count-aabb_before) == 2,
                        "Expected two child AABB requests");
        check_condition((tri_intersection_count-tri_before) == 1,
                        "Expected only the intersecting child's triangle test");
        report_test_summary("one child miss", result);

        // ------------------------------------------------------------
        // TEST 5: Both child AABBs miss.
        // ------------------------------------------------------------
        $display("\n[TEST 5] Both child AABBs miss");
        test_case = 5;
        reset_counts();
        setup_two_child_bvh(1'b0);
        set_node(2, 4.0, 4.0, 2.5, 6.0, 6.0, 3.5,
                 TRI_BASE + TRI_STRIDE, 32'd1);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(!result.hit, "Expected miss when both child boxes miss");
        check_condition((aabb_request_count-aabb_before) == 2,
                        "Expected two child AABB requests");
        check_condition((tri_intersection_count-tri_before) == 0 &&
                        (tri_mem_read_count-tri_mem_before) == 0,
                        "No triangle should be fetched or tested when both child boxes miss");
        report_test_summary("both children miss", result);

        // ------------------------------------------------------------
        // TEST 6: Empty root leaf.
        // ------------------------------------------------------------
        $display("\n[TEST 6] Empty root leaf");
        test_case = 6;
        reset_counts();
        clear_scene();
        set_node(0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, '0, 32'd0);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(!result.hit && (result.distance.data == 0) &&
                        (result.primitive_id == 0),
                        "Empty root should return a clean miss");
        check_condition((bvh_read_count-bvh_before) == 1 &&
                        (tri_mem_read_count-tri_mem_before) == 0 &&
                        (aabb_request_count-aabb_before) == 0 &&
                        (tri_intersection_count-tri_before) == 0,
                        "Unexpected transactions for empty root");
        report_test_summary("empty root", result);

        // ------------------------------------------------------------
        // TEST 7: Ray crosses the leaf AABB but misses the actual triangle.
        // This isolates the triangle software model from BVH box culling.
        // ------------------------------------------------------------
        $display("\n[TEST 7] Ray inside leaf bounds but outside triangle");
        test_case = 7;
        reset_counts();
        setup_simple_leaf();
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, 0.9, 0.9, 0.0), result);
        check_condition(!result.hit,
                        "Ray should pass the leaf bounds but miss the triangle");
        check_condition((tri_intersection_count-tri_before) == 1 &&
                        (tri_mem_read_count-tri_mem_before) == 1,
                        "Expected exactly one triangle fetch and test");
        report_test_summary("triangle miss inside leaf bounds", result);

        // ------------------------------------------------------------
        // TEST 8: Triangle hit is beyond ray.t_max and must be rejected.
        // ------------------------------------------------------------
        $display("\n[TEST 8] Triangle hit clipped by t_max");
        test_case = 8;
        reset_counts();
        setup_simple_leaf();
        test_req = make_request(BVH_BASE, -0.375, -0.375, 0.0);
        test_req.t_max.data = q16(2.0);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(test_req, result);
        check_condition(!result.hit, "Triangle at t=3 must be rejected when t_max=2");
        check_condition((tri_intersection_count-tri_before) == 1,
                        "Expected one triangle intersection request");
        report_test_summary("t_max clipping", result);

        // ------------------------------------------------------------
        // TEST 9: Triangle hit is before ray.t_min and must be rejected.
        // ------------------------------------------------------------
        $display("\n[TEST 9] Triangle hit clipped by t_min");
        test_case = 9;
        reset_counts();
        setup_simple_leaf();
        test_req = make_request(BVH_BASE, -0.375, -0.375, 0.0);
        test_req.t_min.data = q16(3.5);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(test_req, result);
        check_condition(!result.hit, "Triangle at t=3 must be rejected when t_min=3.5");
        check_condition((tri_intersection_count-tri_before) == 1,
                        "Expected one triangle intersection request");
        report_test_summary("t_min clipping", result);

/*
        // ------------------------------------------------------------
        // TEST 10: Two triangles in one leaf, stored far-to-near.
        // This checks closest-hit replacement within a single leaf.
        // ------------------------------------------------------------
        $display("\n[TEST 10] Two triangles in one leaf, far-to-near order");
        test_case = 10;
        reset_counts();
        clear_scene();
        set_triangle(0, 16'd11, 5.0);
        set_triangle(1, 16'd22, 3.0);
        set_node(0, -2.0, -2.0, 0.0, 2.0, 2.0, 6.0, TRI_BASE, 32'd2);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(result.hit && (result.primitive_id == 16'd22),
                        "Expected nearer primitive 22 after testing both triangles");
        check_q16("closest distance", result.distance, 3.0, 2);
        check_condition((tri_intersection_count-tri_before) == 2,
                        "Expected both leaf triangles to be tested");
        check_condition((tri_mem_read_count-tri_mem_before) == 2,
                        "Expected two triangle memory reads");
        report_test_summary("two triangles far-to-near", result);

        // ------------------------------------------------------------
        // TEST 11: Two triangles in one leaf, stored near-to-far.
        // A farther later triangle must not replace the closest hit.
        // ------------------------------------------------------------
        $display("\n[TEST 11] Two triangles in one leaf, near-to-far order");
        test_case = 11;
        reset_counts();
        clear_scene();
        set_triangle(0, 16'd22, 3.0);
        set_triangle(1, 16'd11, 5.0);
        set_node(0, -2.0, -2.0, 0.0, 2.0, 2.0, 6.0, TRI_BASE, 32'd2);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
        check_condition(result.hit && (result.primitive_id == 16'd22),
                        "Farther primitive 11 must not replace nearer primitive 22");
        check_q16("closest distance", result.distance, 3.0, 2);
        report_test_summary("two triangles near-to-far", result);
*/

        // ------------------------------------------------------------
        // TEST 12: A ray parallel to the triangle plane must not hit.
        // ------------------------------------------------------------
        $display("\n[TEST 12] Ray parallel to triangle plane");
        test_case = 12;
        reset_counts();
        setup_simple_leaf();
        test_req = make_request(BVH_BASE, -0.375, -0.375, 0.0);
        test_req.ray.direction = vec3(1.0, 0.0, 0.0);
        test_req.inv_direction = vec3(1.0, 0.0, 0.0);
        bvh_before = bvh_read_count;
        tri_mem_before = tri_mem_read_count;
        aabb_before = aabb_request_count;
        tri_before = tri_intersection_count;
        run_traversal(test_req, result);
        check_condition(!result.hit, "Ray parallel to triangle plane should miss");
        report_test_summary("parallel ray", result);

        if (error_count == 0)
            $display("\nPASS: all traversal integration checks passed");
        else
            $display("\nFAIL: %0d traversal integration check(s) failed", error_count);
        $finish;
    end

    // Transaction counters. Count request handshakes, not response cycles.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            aabb_request_count <= 0;
        end else if (aabb_req_valid_o && aabb_req_ready_i) begin
            aabb_request_count <= aabb_request_count + 1;
        end
    end

endmodule
