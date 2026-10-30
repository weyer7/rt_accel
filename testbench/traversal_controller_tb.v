// module traversal_controller_tb;
// 	reg _sv2v_0;
// 	localparam [31:0] BVH_BASE = 32'h10000000;
// 	localparam [31:0] TRI_BASE = 32'h20000000;
// 	localparam signed [31:0] NODE_BYTES = 32;
// 	localparam signed [31:0] TRI_STRIDE = 40;
// 	localparam signed [31:0] NODE_COUNT = 8;
// 	localparam signed [31:0] TRI_COUNT = 8;
// 	localparam signed [31:0] MEM_LATENCY = 2;
// 	localparam signed [31:0] TRI_MODEL_LATENCY = 2;
// 	reg clk = 1'b0;
// 	reg rst_n = 1'b0;
// 	always #(5) clk = ~clk;
// 	reg traversal_valid_i;
// 	wire traversal_ready_o;
// 	reg [439:0] traversal_i;
// 	wire traversal_result_valid_o;
// 	reg traversal_result_ready_i;
// 	wire [112:0] traversal_result_o;
// 	wire stack_overflow_o;
// 	wire bvh_mem_req_valid_o;
// 	wire bvh_mem_req_ready_i;
// 	wire [31:0] bvh_mem_req_addr_o;
// 	reg bvh_mem_resp_valid_i;
// 	reg bvh_mem_resp_error_i;
// 	reg [255:0] bvh_mem_resp_data_i;
// 	wire tri_mem_req_valid_o;
// 	wire tri_mem_req_ready_i;
// 	wire [31:0] tri_mem_req_addr_o;
// 	reg tri_mem_resp_valid_i;
// 	reg tri_mem_resp_error_i;
// 	reg [303:0] tri_mem_resp_data_i;
// 	wire aabb_req_valid_o;
// 	wire aabb_req_ready_i;
// 	wire [551:0] aabb_req_o;
// 	wire aabb_result_valid_i;
// 	wire [72:0] aabb_result_i;
// 	wire tri_req_valid_o;
// 	wire tri_req_ready_i;
// 	wire [663:0] tri_req_o;
// 	reg tri_result_valid_i;
// 	reg [121:0] tri_result_i;
// 	reg [255:0] node_mem [0:7];
// 	reg [303:0] tri_mem [0:7];
// 	reg [7:0] node_present;
// 	reg [7:0] tri_present;
// 	integer bvh_read_count;
// 	integer tri_mem_read_count;
// 	integer aabb_request_count;
// 	integer tri_intersection_count;
// 	traversal_controller #(
// 		.STACK_DEPTH(16),
// 		.TRIANGLE_STRIDE_BYTES(TRI_STRIDE)
// 	) u_dut(
// 		.clk(clk),
// 		.rst_n(rst_n),
// 		.traversal_valid_i(traversal_valid_i),
// 		.traversal_ready_o(traversal_ready_o),
// 		.traversal_i(traversal_i),
// 		.bvh_mem_req_valid_o(bvh_mem_req_valid_o),
// 		.bvh_mem_req_ready_i(bvh_mem_req_ready_i),
// 		.bvh_mem_req_addr_o(bvh_mem_req_addr_o),
// 		.bvh_mem_resp_valid_i(bvh_mem_resp_valid_i),
// 		.bvh_mem_resp_error_i(bvh_mem_resp_error_i),
// 		.bvh_mem_resp_data_i(bvh_mem_resp_data_i),
// 		.tri_mem_req_valid_o(tri_mem_req_valid_o),
// 		.tri_mem_req_ready_i(tri_mem_req_ready_i),
// 		.tri_mem_req_addr_o(tri_mem_req_addr_o),
// 		.tri_mem_resp_valid_i(tri_mem_resp_valid_i),
// 		.tri_mem_resp_error_i(tri_mem_resp_error_i),
// 		.tri_mem_resp_data_i(tri_mem_resp_data_i),
// 		.aabb_req_valid_o(aabb_req_valid_o),
// 		.aabb_req_ready_i(aabb_req_ready_i),
// 		.aabb_req_o(aabb_req_o),
// 		.aabb_result_valid_i(aabb_result_valid_i),
// 		.aabb_result_i(aabb_result_i),
// 		.tri_req_valid_o(tri_req_valid_o),
// 		.tri_req_ready_i(tri_req_ready_i),
// 		.tri_req_o(tri_req_o),
// 		.tri_result_valid_i(tri_result_valid_i),
// 		.tri_result_i(tri_result_i),
// 		.traversal_result_valid_o(traversal_result_valid_o),
// 		.traversal_result_ready_i(traversal_result_ready_i),
// 		.traversal_result_o(traversal_result_o),
// 		.stack_overflow_o(stack_overflow_o)
// 	);
// 	q16p16_aabb_intersect u_aabb(
// 		.clk(clk),
// 		.n_rst(rst_n),
// 		.request(aabb_req_o),
// 		.valid_i(aabb_req_valid_o),
// 		.ready_o(aabb_req_ready_i),
// 		.result(aabb_result_i),
// 		.valid_o(aabb_result_valid_i),
// 		.ready_i(1'b1)
// 	);
// 	reg bvh_pending_q;
// 	reg tri_mem_pending_q;
// 	integer bvh_delay_q;
// 	integer tri_mem_delay_q;
// 	reg [255:0] bvh_data_pending_q;
// 	reg bvh_error_pending_q;
// 	reg [303:0] tri_data_pending_q;
// 	reg tri_mem_error_pending_q;
// 	assign bvh_mem_req_ready_i = !bvh_pending_q;
// 	assign tri_mem_req_ready_i = !tri_mem_pending_q;
// 	function automatic bvh_addr_valid;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			bvh_addr_valid = 1'b0;
// 			if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
// 				idx = (addr - BVH_BASE) / NODE_BYTES;
// 				if ((idx >= 0) && (idx < NODE_COUNT))
// 					bvh_addr_valid = node_present[idx];
// 			end
// 		end
// 	endfunction
// 	function automatic [255:0] bvh_lookup;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			bvh_lookup = 1'sb0;
// 			if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
// 				idx = (addr - BVH_BASE) / NODE_BYTES;
// 				if ((idx >= 0) && (idx < NODE_COUNT))
// 					bvh_lookup = node_mem[idx];
// 			end
// 		end
// 	endfunction
// 	function automatic tri_addr_valid;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			tri_addr_valid = 1'b0;
// 			if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
// 				idx = (addr - TRI_BASE) / TRI_STRIDE;
// 				if ((idx >= 0) && (idx < TRI_COUNT))
// 					tri_addr_valid = tri_present[idx];
// 			end
// 		end
// 	endfunction
// 	function automatic [303:0] tri_lookup;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			tri_lookup = 1'sb0;
// 			if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
// 				idx = (addr - TRI_BASE) / TRI_STRIDE;
// 				if ((idx >= 0) && (idx < TRI_COUNT))
// 					tri_lookup = tri_mem[idx];
// 			end
// 		end
// 	endfunction
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n) begin
// 			bvh_pending_q <= 1'b0;
// 			bvh_delay_q <= 0;
// 			bvh_data_pending_q <= 1'sb0;
// 			bvh_error_pending_q <= 1'b0;
// 			bvh_mem_resp_valid_i <= 1'b0;
// 			bvh_mem_resp_error_i <= 1'b0;
// 			bvh_mem_resp_data_i <= 1'sb0;
// 			bvh_read_count <= 0;
// 		end
// 		else begin
// 			bvh_mem_resp_valid_i <= 1'b0;
// 			if (bvh_pending_q) begin
// 				if (bvh_delay_q > 1)
// 					bvh_delay_q <= bvh_delay_q - 1;
// 				else begin
// 					bvh_pending_q <= 1'b0;
// 					bvh_mem_resp_valid_i <= 1'b1;
// 					bvh_mem_resp_error_i <= bvh_error_pending_q;
// 					bvh_mem_resp_data_i <= bvh_data_pending_q;
// 				end
// 			end
// 			if (bvh_mem_req_valid_o && bvh_mem_req_ready_i) begin
// 				if (bvh_pending_q) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:197:21 - traversal_controller_tb.<unnamed_block>.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "BVH memory accepted overlapping read");
// 					$finish(1);
// 				end
// 				bvh_pending_q <= 1'b1;
// 				bvh_delay_q <= MEM_LATENCY;
// 				bvh_data_pending_q <= bvh_lookup(bvh_mem_req_addr_o);
// 				bvh_error_pending_q <= !bvh_addr_valid(bvh_mem_req_addr_o);
// 				bvh_read_count <= bvh_read_count + 1;
// 			end
// 		end
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n) begin
// 			tri_mem_pending_q <= 1'b0;
// 			tri_mem_delay_q <= 0;
// 			tri_data_pending_q <= 1'sb0;
// 			tri_mem_error_pending_q <= 1'b0;
// 			tri_mem_resp_valid_i <= 1'b0;
// 			tri_mem_resp_error_i <= 1'b0;
// 			tri_mem_resp_data_i <= 1'sb0;
// 			tri_mem_read_count <= 0;
// 		end
// 		else begin
// 			tri_mem_resp_valid_i <= 1'b0;
// 			if (tri_mem_pending_q) begin
// 				if (tri_mem_delay_q > 1)
// 					tri_mem_delay_q <= tri_mem_delay_q - 1;
// 				else begin
// 					tri_mem_pending_q <= 1'b0;
// 					tri_mem_resp_valid_i <= 1'b1;
// 					tri_mem_resp_error_i <= tri_mem_error_pending_q;
// 					tri_mem_resp_data_i <= tri_data_pending_q;
// 				end
// 			end
// 			if (tri_mem_req_valid_o && tri_mem_req_ready_i) begin
// 				if (tri_mem_pending_q) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:231:21 - traversal_controller_tb.<unnamed_block>.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Triangle memory accepted overlapping read");
// 					$finish(1);
// 				end
// 				tri_mem_pending_q <= 1'b1;
// 				tri_mem_delay_q <= MEM_LATENCY;
// 				tri_data_pending_q <= tri_lookup(tri_mem_req_addr_o);
// 				tri_mem_error_pending_q <= !tri_addr_valid(tri_mem_req_addr_o);
// 				tri_mem_read_count <= tri_mem_read_count + 1;
// 			end
// 		end
// 	reg tri_model_pending_q;
// 	integer tri_model_delay_q;
// 	reg [121:0] tri_model_result_q;
// 	reg [121:0] tri_model_comb;
// 	wire [121:0] tri_model_result_next;
// 	wire tri_model_request_fire;
// 	assign tri_req_ready_i = !tri_model_pending_q;
// 	assign tri_model_request_fire = tri_req_valid_o && tri_req_ready_i;
// 	function automatic real q16_to_real;
// 		input reg [31:0] x;
// 		reg signed [31:0] sx;
// 		begin
// 			sx = x;
// 			q16_to_real = $itor(sx) / 65536.0;
// 		end
// 	endfunction
// 	function automatic [31:0] real_to_q16;
// 		input real x;
// 		integer signed temp;
// 		begin
// 			temp = $rtoi(x * 65536.0);
// 			real_to_q16 = temp;
// 		end
// 	endfunction
// 	function automatic real vec_dot;
// 		input real ax;
// 		input real ay;
// 		input real az;
// 		input real bx;
// 		input real by;
// 		input real bz;
// 		vec_dot = ((ax * bx) + (ay * by)) + (az * bz);
// 	endfunction
// 	function automatic real cross_x;
// 		input real ay;
// 		input real az;
// 		input real by;
// 		input real bz;
// 		cross_x = (ay * bz) - (az * by);
// 	endfunction
// 	function automatic real cross_y;
// 		input real az;
// 		input real ax;
// 		input real bz;
// 		input real bx;
// 		cross_y = (az * bx) - (ax * bz);
// 	endfunction
// 	function automatic real cross_z;
// 		input real ax;
// 		input real ay;
// 		input real bx;
// 		input real by;
// 		cross_z = (ax * by) - (ay * bx);
// 	endfunction
// 	task automatic evaluate_triangle;
// 		input reg [663:0] req;
// 		output reg [121:0] res;
// 		localparam real EPSILON = 1.0e-7;
// 		real ox;
// 		real oy;
// 		real oz;
// 		real dx;
// 		real dy;
// 		real dz;
// 		real v0x;
// 		real v0y;
// 		real v0z;
// 		real v1x;
// 		real v1y;
// 		real v1z;
// 		real v2x;
// 		real v2y;
// 		real v2z;
// 		real e1x;
// 		real e1y;
// 		real e1z;
// 		real e2x;
// 		real e2y;
// 		real e2z;
// 		real hx;
// 		real hy;
// 		real hz;
// 		real sx;
// 		real sy;
// 		real sz;
// 		real qx;
// 		real qy;
// 		real qz;
// 		real det;
// 		real inv_det;
// 		real u;
// 		real v;
// 		real t;
// 		reg [1:0] _sv2v_jump;
// 		begin
// 			_sv2v_jump = 2'b00;
// 			res = 1'sb0;
// 			res[121-:8] = req[663-:8];
// 			res[112-:16] = req[303-:16];
// 			ox = q16_to_real(req[655-:32]);
// 			oy = q16_to_real(req[623-:32]);
// 			oz = q16_to_real(req[591-:32]);
// 			dx = q16_to_real(req[559-:32]);
// 			dy = q16_to_real(req[527-:32]);
// 			dz = q16_to_real(req[495-:32]);
// 			v0x = q16_to_real(req[287-:32]);
// 			v0y = q16_to_real(req[255-:32]);
// 			v0z = q16_to_real(req[223-:32]);
// 			v1x = q16_to_real(req[191-:32]);
// 			v1y = q16_to_real(req[159-:32]);
// 			v1z = q16_to_real(req[127-:32]);
// 			v2x = q16_to_real(req[95-:32]);
// 			v2y = q16_to_real(req[63-:32]);
// 			v2z = q16_to_real(req[31-:32]);
// 			e1x = v1x - v0x;
// 			e1y = v1y - v0y;
// 			e1z = v1z - v0z;
// 			e2x = v2x - v0x;
// 			e2y = v2y - v0y;
// 			e2z = v2z - v0z;
// 			hx = cross_x(dy, dz, e2y, e2z);
// 			hy = cross_y(dz, dx, e2z, e2x);
// 			hz = cross_z(dx, dy, e2x, e2y);
// 			det = vec_dot(e1x, e1y, e1z, hx, hy, hz);
// 			if ((det > -EPSILON) && (det < EPSILON))
// 				_sv2v_jump = 2'b11;
// 			if (_sv2v_jump == 2'b00) begin
// 				inv_det = 1.0 / det;
// 				sx = ox - v0x;
// 				sy = oy - v0y;
// 				sz = oz - v0z;
// 				u = inv_det * vec_dot(sx, sy, sz, hx, hy, hz);
// 				if ((u < 0.0) || (u > 1.0))
// 					_sv2v_jump = 2'b11;
// 				if (_sv2v_jump == 2'b00) begin
// 					qx = cross_x(sy, sz, e1y, e1z);
// 					qy = cross_y(sz, sx, e1z, e1x);
// 					qz = cross_z(sx, sy, e1x, e1y);
// 					v = inv_det * vec_dot(dx, dy, dz, qx, qy, qz);
// 					if ((v < 0.0) || ((u + v) > 1.0))
// 						_sv2v_jump = 2'b11;
// 					if (_sv2v_jump == 2'b00) begin
// 						t = inv_det * vec_dot(e2x, e2y, e2z, qx, qy, qz);
// 						if (t < q16_to_real(req[367-:32]))
// 							_sv2v_jump = 2'b11;
// 						if (_sv2v_jump == 2'b00) begin
// 							if (t > q16_to_real(req[335-:32]))
// 								_sv2v_jump = 2'b11;
// 							if (_sv2v_jump == 2'b00) begin
// 								res[113] = 1'b1;
// 								res[96-:32] = real_to_q16(t);
// 								res[64-:32] = real_to_q16(u);
// 								res[32-:32] = real_to_q16(v);
// 								res[0] = det < 0.0;
// 							end
// 						end
// 					end
// 				end
// 			end
// 		end
// 	endtask
// 	always @(*) begin
// 		if (_sv2v_0)
// 			;
// 		evaluate_triangle(tri_req_o, tri_model_comb);
// 	end
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n) begin
// 			tri_model_pending_q <= 1'b0;
// 			tri_model_delay_q <= 0;
// 			tri_model_result_q <= 1'sb0;
// 			tri_result_valid_i <= 1'b0;
// 			tri_result_i <= 1'sb0;
// 			tri_intersection_count <= 0;
// 		end
// 		else begin
// 			tri_result_valid_i <= 1'b0;
// 			if (tri_model_pending_q) begin
// 				if (tri_model_delay_q > 1)
// 					tri_model_delay_q <= tri_model_delay_q - 1;
// 				else begin
// 					tri_model_pending_q <= 1'b0;
// 					tri_result_valid_i <= 1'b1;
// 					tri_result_i <= tri_model_result_q;
// 				end
// 			end
// 			if (tri_model_request_fire) begin
// 				if (tri_model_pending_q) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:435:21 - traversal_controller_tb.<unnamed_block>.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Triangle model accepted overlapping request");
// 					$finish(1);
// 				end
// 				tri_model_result_q <= tri_model_comb;
// 				tri_model_delay_q <= TRI_MODEL_LATENCY;
// 				tri_model_pending_q <= 1'b1;
// 				tri_intersection_count <= tri_intersection_count + 1;
// 			end
// 		end
// 	function automatic [31:0] q16;
// 		input real x;
// 		integer signed temp;
// 		begin
// 			temp = $rtoi(x * 65536.0);
// 			q16 = temp;
// 		end
// 	endfunction
// 	function automatic [31:0] fx;
// 		input real x;
// 		fx[31-:32] = q16(x);
// 	endfunction
// 	function automatic [95:0] vec3;
// 		input real x;
// 		input real y;
// 		input real z;
// 		reg [95:0] value;
// 		begin
// 			value[95-:32] = fx(x);
// 			value[63-:32] = fx(y);
// 			value[31-:32] = fx(z);
// 			vec3 = value;
// 		end
// 	endfunction
// 	task automatic set_triangle;
// 		input integer idx;
// 		input reg [15:0] prim;
// 		input real z;
// 		begin
// 			tri_mem[idx] = 1'sb0;
// 			tri_mem[idx][303-:16] = prim;
// 			tri_mem[idx][287-:32] = fx(-1.0);
// 			tri_mem[idx][255-:32] = fx(-1.0);
// 			tri_mem[idx][223-:32] = fx(z);
// 			tri_mem[idx][191-:32] = fx(1.0);
// 			tri_mem[idx][159-:32] = fx(-1.0);
// 			tri_mem[idx][127-:32] = fx(z);
// 			tri_mem[idx][95-:32] = fx(0.0);
// 			tri_mem[idx][63-:32] = fx(1.0);
// 			tri_mem[idx][31-:32] = fx(z);
// 			tri_present[idx] = 1'b1;
// 		end
// 	endtask
// 	task automatic set_node;
// 		input integer idx;
// 		input real min_x;
// 		input real min_y;
// 		input real min_z;
// 		input real max_x;
// 		input real max_y;
// 		input real max_z;
// 		input reg [31:0] left_first;
// 		input reg [31:0] tri_count;
// 		begin
// 			node_mem[idx] = 1'sb0;
// 			node_mem[idx][255-:32] = fx(min_x);
// 			node_mem[idx][223-:32] = fx(min_y);
// 			node_mem[idx][191-:32] = fx(min_z);
// 			node_mem[idx][159-:32] = fx(max_x);
// 			node_mem[idx][127-:32] = fx(max_y);
// 			node_mem[idx][95-:32] = fx(max_z);
// 			node_mem[idx][63-:32] = left_first;
// 			node_mem[idx][31-:32] = tri_count;
// 			node_present[idx] = 1'b1;
// 		end
// 	endtask
// 	task automatic clear_scene;
// 		integer i;
// 		begin
// 			for (i = 0; i < NODE_COUNT; i = i + 1)
// 				begin
// 					node_mem[i] = 1'sb0;
// 					node_present[i] = 1'b0;
// 				end
// 			for (i = 0; i < TRI_COUNT; i = i + 1)
// 				begin
// 					tri_mem[i] = 1'sb0;
// 					tri_present[i] = 1'b0;
// 				end
// 		end
// 	endtask
// 	function automatic [439:0] make_request;
// 		input reg [31:0] root;
// 		input real ox;
// 		input real oy;
// 		input real oz;
// 		reg [439:0] req;
// 		begin
// 			req = 1'sb0;
// 			req[439-:16] = 16'h1234;
// 			req[391-:96] = vec3(ox, oy, oz);
// 			req[295-:96] = vec3(0.125, 0.125, 1.0);
// 			req[199-:8] = 8'h2a;
// 			req[191-:32] = root;
// 			req[159-:96] = vec3(8.0, 8.0, 1.0);
// 			req[63-:32] = fx(0.0);
// 			req[31-:32] = fx(100.0);
// 			make_request = req;
// 		end
// 	endfunction
// 	task automatic run_traversal;
// 		input reg [439:0] req;
// 		output reg [112:0] res;
// 		integer cycle_count;
// 		begin
// 			cycle_count = 0;
// 			@(negedge clk)
// 				;
// 			traversal_i = req;
// 			traversal_valid_i = 1'b1;
// 			begin : sv2v_autoblock_1
// 				reg sv2v_do_while;
// 				sv2v_do_while = 1;
// 				while (sv2v_do_while || !traversal_ready_o) begin
// 					sv2v_do_while = 0;
// 					@(posedge clk)
// 						;
// 					cycle_count = cycle_count + 1;
// 					if (cycle_count > 1000) begin
// 						$display("Fatal [%0t] testbench/traversal_controller_tb.sv:564:21 - traversal_controller_tb.run_traversal.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Timed out waiting for traversal request acceptance");
// 						$finish(1);
// 					end
// 				end
// 			end
// 			@(negedge clk)
// 				;
// 			traversal_valid_i = 1'b0;
// 			cycle_count = 0;
// 			while (!traversal_result_valid_o) begin
// 				@(negedge clk)
// 					;
// 				cycle_count = cycle_count + 1;
// 				if (cycle_count > 3000) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:574:21 - traversal_controller_tb.run_traversal.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Timed out waiting for traversal result");
// 					$finish(1);
// 				end
// 			end
// 			res = traversal_result_o;
// 			if (stack_overflow_o) begin
// 				$display("Fatal [%0t] testbench/traversal_controller_tb.sv:578:17 - traversal_controller_tb.run_traversal.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Traversal reported stack overflow");
// 				$finish(1);
// 			end
// 			@(posedge clk)
// 				;
// 			@(negedge clk)
// 				;
// 		end
// 	endtask
// 	task automatic check_q16;
// 		input string field_name;
// 		input reg [31:0] actual;
// 		input real expected_real;
// 		input integer tolerance_lsb;
// 		integer signed actual_s;
// 		integer signed expected_s;
// 		integer signed delta;
// 		begin
// 			actual_s = $signed(actual[31-:32]);
// 			expected_s = $signed(q16(expected_real));
// 			delta = actual_s - expected_s;
// 			if ((delta > tolerance_lsb) || (delta < -tolerance_lsb)) begin
// 				$display("Fatal [%0t] testbench/traversal_controller_tb.sv:599:17 - traversal_controller_tb.check_q16.<unnamed_block>.<unnamed_block>\n msg: ", $time, "%s mismatch: got raw=%0d (%.6f), expected %.6f (raw=%0d)", field_name, actual_s, $itor(actual_s) / 65536.0, expected_real, expected_s);
// 				$finish(1);
// 			end
// 		end
// 	endtask
// 	task automatic setup_simple_leaf;
// 		begin
// 			clear_scene;
// 			set_triangle(0, 16'd7, 3.0);
// 			set_node(0, -2.0, -2.0, 2.0, 2.0, 2.0, 4.0, TRI_BASE, 32'd1);
// 		end
// 	endtask
// 	task automatic setup_two_child_bvh;
// 		input reg left_box_hits;
// 		begin
// 			clear_scene;
// 			set_node(0, -2.0, -2.0, 0.0, 2.0, 2.0, 6.0, BVH_BASE + NODE_BYTES, 32'd2);
// 			if (left_box_hits)
// 				set_node(1, -2.0, -2.0, 4.5, 2.0, 2.0, 5.5, TRI_BASE, 32'd1);
// 			else
// 				set_node(1, 4.0, 4.0, 4.5, 6.0, 6.0, 5.5, TRI_BASE, 32'd1);
// 			set_node(2, -2.0, -2.0, 2.5, 2.0, 2.0, 3.5, TRI_BASE + TRI_STRIDE, 32'd1);
// 			set_triangle(0, 16'd11, 5.0);
// 			set_triangle(1, 16'd22, 3.0);
// 		end
// 	endtask
// 	integer bvh_before;
// 	integer tri_mem_before;
// 	integer aabb_before;
// 	integer tri_before;
// 	reg [112:0] result;
// 	initial begin
// 		$dumpfile("waves/traversal_controller.vcd");
// 		$dumpvars(0, traversal_controller_tb);
// 	end
// 	initial begin
// 		traversal_valid_i = 1'b0;
// 		traversal_i = 1'sb0;
// 		traversal_result_ready_i = 1'b1;
// 		clear_scene;
// 		repeat (4) @(negedge clk)
// 			;
// 		rst_n = 1'b1;
// 		repeat (3) @(negedge clk)
// 			;
// 		$display("[TEST 1] Single-leaf triangle hit");
// 		setup_simple_leaf;
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (!result[112] || (result[111-:16] != 16'd7)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:661:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf hit: wrong hit/primitive result");
// 			$finish(1);
// 		end
// 		check_q16("hit distance", result[95-:32], 3.0, 2);
// 		check_q16("barycentric u", result[63-:32], 0.25, 2);
// 		check_q16("barycentric v", result[31-:32], 0.5, 2);
// 		if (((((bvh_read_count - bvh_before) != 1) || ((tri_mem_read_count - tri_mem_before) != 1)) || ((aabb_request_count - aabb_before) != 0)) || ((tri_intersection_count - tri_before) != 1)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:667:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf hit: unexpected memory/intersection request counts");
// 			$finish(1);
// 		end
// 		$display("[TEST 2] Single-leaf triangle miss");
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, 8.0, 8.0, 0.0), result);
// 		if (result[112]) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:676:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf miss: unexpected hit");
// 			$finish(1);
// 		end
// 		if (((((bvh_read_count - bvh_before) != 1) || ((tri_mem_read_count - tri_mem_before) != 1)) || ((aabb_request_count - aabb_before) != 0)) || ((tri_intersection_count - tri_before) != 1)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:679:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf miss: unexpected memory/intersection request counts");
// 			$finish(1);
// 		end
// 		$display("[TEST 3] Two-child BVH, nearest child first, far child pruned");
// 		setup_two_child_bvh(1'b1);
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (!result[112] || (result[111-:16] != 16'd22)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:689:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: nearest primitive was not returned");
// 			$finish(1);
// 		end
// 		check_q16("nearest hit distance", result[95-:32], 3.0, 2);
// 		check_q16("nearest barycentric u", result[63-:32], 0.25, 2);
// 		check_q16("nearest barycentric v", result[31-:32], 0.5, 2);
// 		if ((aabb_request_count - aabb_before) != 2) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:694:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected exactly two child AABB tests, got %0d", aabb_request_count - aabb_before);
// 			$finish(1);
// 		end
// 		if ((tri_intersection_count - tri_before) != 1) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:697:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected far triangle to be pruned, tri tests=%0d", tri_intersection_count - tri_before);
// 			$finish(1);
// 		end
// 		if ((bvh_read_count - bvh_before) != 4) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:700:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected 4 BVH reads (root, child metadata x2, near node), got %0d", bvh_read_count - bvh_before);
// 			$finish(1);
// 		end
// 		if ((tri_mem_read_count - tri_mem_before) != 1) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:703:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected 1 triangle memory read");
// 			$finish(1);
// 		end
// 		$display("[TEST 4] One child AABB miss, other child hits");
// 		setup_two_child_bvh(1'b0);
// 		bvh_before = bvh_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (!result[112] || (result[111-:16] != 16'd22)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:712:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "One-child-hit traversal: wrong result");
// 			$finish(1);
// 		end
// 		if (((aabb_request_count - aabb_before) != 2) || ((tri_intersection_count - tri_before) != 1)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:714:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "One-child-hit traversal: unexpected AABB/triangle request count");
// 			$finish(1);
// 		end
// 		$display("[TEST 5] Internal node where both child AABBs miss");
// 		setup_two_child_bvh(1'b0);
// 		node_mem[2][255-:32] = fx(4.0);
// 		node_mem[2][223-:32] = fx(4.0);
// 		node_mem[2][191-:32] = fx(2.5);
// 		node_mem[2][159-:32] = fx(6.0);
// 		node_mem[2][127-:32] = fx(6.0);
// 		node_mem[2][95-:32] = fx(3.5);
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (result[112]) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:731:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Both-child-miss traversal unexpectedly hit");
// 			$finish(1);
// 		end
// 		if (((aabb_request_count - aabb_before) != 2) || ((tri_intersection_count - tri_before) != 0)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:733:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Both-child-miss traversal: unexpected AABB/triangle request count");
// 			$finish(1);
// 		end
// 		$display("[TEST 6] Empty root leaf");
// 		clear_scene;
// 		set_node(0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1'sb0, 32'd0);
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if ((result[112] || (result[95-:32] != 0)) || (result[111-:16] != 0)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:744:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Empty root did not return a clean miss");
// 			$finish(1);
// 		end
// 		if (((((bvh_read_count - bvh_before) != 1) || ((tri_mem_read_count - tri_mem_before) != 0)) || ((aabb_request_count - aabb_before) != 0)) || ((tri_intersection_count - tri_before) != 0)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:747:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Empty root: unexpected memory/intersection request counts");
// 			$finish(1);
// 		end
// 		$display("PASS: all initial BVH traversal integration tests passed");
// 		$finish;
// 	end
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n)
// 			aabb_request_count <= 0;
// 		else if (aabb_req_valid_o && aabb_req_ready_i)
// 			aabb_request_count <= aabb_request_count + 1;
// 	initial _sv2v_0 = 0;
// endmodule
// module traversal_controller_tb;
// 	reg _sv2v_0;
// 	localparam [31:0] BVH_BASE = 32'h10000000;
// 	localparam [31:0] TRI_BASE = 32'h20000000;
// 	localparam signed [31:0] NODE_BYTES = 32;
// 	localparam signed [31:0] TRI_STRIDE = 40;
// 	localparam signed [31:0] NODE_COUNT = 8;
// 	localparam signed [31:0] TRI_COUNT = 8;
// 	localparam signed [31:0] MEM_LATENCY = 2;
// 	localparam signed [31:0] TRI_MODEL_LATENCY = 2;
// 	reg clk = 1'b0;
// 	reg rst_n = 1'b0;
// 	always #(5) clk = ~clk;
// 	reg traversal_valid_i;
// 	wire traversal_ready_o;
// 	reg [439:0] traversal_i;
// 	wire traversal_result_valid_o;
// 	reg traversal_result_ready_i;
// 	wire [112:0] traversal_result_o;
// 	wire stack_overflow_o;
// 	wire bvh_mem_req_valid_o;
// 	wire bvh_mem_req_ready_i;
// 	wire [31:0] bvh_mem_req_addr_o;
// 	reg bvh_mem_resp_valid_i;
// 	reg bvh_mem_resp_error_i;
// 	reg [255:0] bvh_mem_resp_data_i;
// 	wire tri_mem_req_valid_o;
// 	wire tri_mem_req_ready_i;
// 	wire [31:0] tri_mem_req_addr_o;
// 	reg tri_mem_resp_valid_i;
// 	reg tri_mem_resp_error_i;
// 	reg [303:0] tri_mem_resp_data_i;
// 	wire aabb_req_valid_o;
// 	wire aabb_req_ready_i;
// 	wire [551:0] aabb_req_o;
// 	wire aabb_result_valid_i;
// 	wire [72:0] aabb_result_i;
// 	wire tri_req_valid_o;
// 	wire tri_req_ready_i;
// 	wire [663:0] tri_req_o;
// 	reg tri_result_valid_i;
// 	reg [121:0] tri_result_i;
// 	reg [255:0] node_mem [0:7];
// 	reg [303:0] tri_mem [0:7];
// 	reg [7:0] node_present;
// 	reg [7:0] tri_present;
// 	integer bvh_read_count;
// 	integer tri_mem_read_count;
// 	integer aabb_request_count;
// 	integer tri_intersection_count;
// 	traversal_controller #(
// 		.STACK_DEPTH(16),
// 		.TRIANGLE_STRIDE_BYTES(TRI_STRIDE)
// 	) u_dut(
// 		.clk(clk),
// 		.rst_n(rst_n),
// 		.traversal_valid_i(traversal_valid_i),
// 		.traversal_ready_o(traversal_ready_o),
// 		.traversal_i(traversal_i),
// 		.bvh_mem_req_valid_o(bvh_mem_req_valid_o),
// 		.bvh_mem_req_ready_i(bvh_mem_req_ready_i),
// 		.bvh_mem_req_addr_o(bvh_mem_req_addr_o),
// 		.bvh_mem_resp_valid_i(bvh_mem_resp_valid_i),
// 		.bvh_mem_resp_error_i(bvh_mem_resp_error_i),
// 		.bvh_mem_resp_data_i(bvh_mem_resp_data_i),
// 		.tri_mem_req_valid_o(tri_mem_req_valid_o),
// 		.tri_mem_req_ready_i(tri_mem_req_ready_i),
// 		.tri_mem_req_addr_o(tri_mem_req_addr_o),
// 		.tri_mem_resp_valid_i(tri_mem_resp_valid_i),
// 		.tri_mem_resp_error_i(tri_mem_resp_error_i),
// 		.tri_mem_resp_data_i(tri_mem_resp_data_i),
// 		.aabb_req_valid_o(aabb_req_valid_o),
// 		.aabb_req_ready_i(aabb_req_ready_i),
// 		.aabb_req_o(aabb_req_o),
// 		.aabb_result_valid_i(aabb_result_valid_i),
// 		.aabb_result_i(aabb_result_i),
// 		.tri_req_valid_o(tri_req_valid_o),
// 		.tri_req_ready_i(tri_req_ready_i),
// 		.tri_req_o(tri_req_o),
// 		.tri_result_valid_i(tri_result_valid_i),
// 		.tri_result_i(tri_result_i),
// 		.traversal_result_valid_o(traversal_result_valid_o),
// 		.traversal_result_ready_i(traversal_result_ready_i),
// 		.traversal_result_o(traversal_result_o),
// 		.stack_overflow_o(stack_overflow_o)
// 	);
// 	q16p16_aabb_intersect u_aabb(
// 		.clk(clk),
// 		.n_rst(rst_n),
// 		.request(aabb_req_o),
// 		.valid_i(aabb_req_valid_o),
// 		.ready_o(aabb_req_ready_i),
// 		.result(aabb_result_i),
// 		.valid_o(aabb_result_valid_i),
// 		.ready_i(1'b1)
// 	);
// 	reg bvh_pending_q;
// 	reg tri_mem_pending_q;
// 	integer bvh_delay_q;
// 	integer tri_mem_delay_q;
// 	reg [255:0] bvh_data_pending_q;
// 	reg bvh_error_pending_q;
// 	reg [303:0] tri_data_pending_q;
// 	reg tri_mem_error_pending_q;
// 	assign bvh_mem_req_ready_i = !bvh_pending_q;
// 	assign tri_mem_req_ready_i = !tri_mem_pending_q;
// 	function automatic bvh_addr_valid;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			bvh_addr_valid = 1'b0;
// 			if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
// 				idx = (addr - BVH_BASE) / NODE_BYTES;
// 				if ((idx >= 0) && (idx < NODE_COUNT))
// 					bvh_addr_valid = node_present[idx];
// 			end
// 		end
// 	endfunction
// 	function automatic [255:0] bvh_lookup;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			bvh_lookup = 1'sb0;
// 			if ((addr >= BVH_BASE) && (((addr - BVH_BASE) % NODE_BYTES) == 0)) begin
// 				idx = (addr - BVH_BASE) / NODE_BYTES;
// 				if ((idx >= 0) && (idx < NODE_COUNT))
// 					bvh_lookup = node_mem[idx];
// 			end
// 		end
// 	endfunction
// 	function automatic tri_addr_valid;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			tri_addr_valid = 1'b0;
// 			if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
// 				idx = (addr - TRI_BASE) / TRI_STRIDE;
// 				if ((idx >= 0) && (idx < TRI_COUNT))
// 					tri_addr_valid = tri_present[idx];
// 			end
// 		end
// 	endfunction
// 	function automatic [303:0] tri_lookup;
// 		input reg [31:0] addr;
// 		integer idx;
// 		begin
// 			tri_lookup = 1'sb0;
// 			if ((addr >= TRI_BASE) && (((addr - TRI_BASE) % TRI_STRIDE) == 0)) begin
// 				idx = (addr - TRI_BASE) / TRI_STRIDE;
// 				if ((idx >= 0) && (idx < TRI_COUNT))
// 					tri_lookup = tri_mem[idx];
// 			end
// 		end
// 	endfunction
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n) begin
// 			bvh_pending_q <= 1'b0;
// 			bvh_delay_q <= 0;
// 			bvh_data_pending_q <= 1'sb0;
// 			bvh_error_pending_q <= 1'b0;
// 			bvh_mem_resp_valid_i <= 1'b0;
// 			bvh_mem_resp_error_i <= 1'b0;
// 			bvh_mem_resp_data_i <= 1'sb0;
// 			bvh_read_count <= 0;
// 		end
// 		else begin
// 			bvh_mem_resp_valid_i <= 1'b0;
// 			if (bvh_pending_q) begin
// 				if (bvh_delay_q > 1)
// 					bvh_delay_q <= bvh_delay_q - 1;
// 				else begin
// 					bvh_pending_q <= 1'b0;
// 					bvh_mem_resp_valid_i <= 1'b1;
// 					bvh_mem_resp_error_i <= bvh_error_pending_q;
// 					bvh_mem_resp_data_i <= bvh_data_pending_q;
// 				end
// 			end
// 			if (bvh_mem_req_valid_o && bvh_mem_req_ready_i) begin
// 				if (bvh_pending_q) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:197:21 - traversal_controller_tb.<unnamed_block>.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "BVH memory accepted overlapping read");
// 					$finish(1);
// 				end
// 				bvh_pending_q <= 1'b1;
// 				bvh_delay_q <= MEM_LATENCY;
// 				bvh_data_pending_q <= bvh_lookup(bvh_mem_req_addr_o);
// 				bvh_error_pending_q <= !bvh_addr_valid(bvh_mem_req_addr_o);
// 				bvh_read_count <= bvh_read_count + 1;
// 			end
// 		end
// 	reg tri_model_pending_q;
// 	integer tri_model_delay_q;
// 	assign tri_req_ready_i = !tri_model_pending_q;
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n) begin
// 			tri_model_pending_q <= 1'b0;
// 			tri_model_delay_q <= 0;
// 			tri_result_valid_i <= 1'b0;
// 			tri_result_i <= 1'sb0;
// 			tri_intersection_count <= 0;
// 		end
// 		else begin
// 			tri_result_valid_i <= 1'b0;
// 			if (tri_model_pending_q) begin
// 				if (tri_model_delay_q > 1)
// 					tri_model_delay_q <= tri_model_delay_q - 1;
// 				else begin
// 					tri_model_pending_q <= 1'b0;
// 					tri_result_valid_i <= 1'b1;
// 					tri_result_i <= 1'sb0;
// 				end
// 			end
// 			if (tri_req_valid_o && tri_req_ready_i) begin
// 				tri_model_pending_q <= 1'b1;
// 				tri_model_delay_q <= TRI_MODEL_LATENCY;
// 				tri_intersection_count <= tri_intersection_count + 1;
// 			end
// 		end
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n) begin
// 			tri_mem_pending_q <= 1'b0;
// 			tri_mem_delay_q <= 0;
// 			tri_data_pending_q <= 1'sb0;
// 			tri_mem_error_pending_q <= 1'b0;
// 			tri_mem_resp_valid_i <= 1'b0;
// 			tri_mem_resp_error_i <= 1'b0;
// 			tri_mem_resp_data_i <= 1'sb0;
// 			tri_mem_read_count <= 0;
// 		end
// 		else begin
// 			tri_mem_resp_valid_i <= 1'b0;
// 			if (tri_mem_pending_q) begin
// 				if (tri_mem_delay_q > 1)
// 					tri_mem_delay_q <= tri_mem_delay_q - 1;
// 				else begin
// 					tri_mem_pending_q <= 1'b0;
// 					tri_mem_resp_valid_i <= 1'b1;
// 					tri_mem_resp_error_i <= tri_mem_error_pending_q;
// 					tri_mem_resp_data_i <= tri_data_pending_q;
// 				end
// 			end
// 			if (tri_mem_req_valid_o && tri_mem_req_ready_i) begin
// 				if (tri_mem_pending_q) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:265:21 - traversal_controller_tb.<unnamed_block>.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Triangle memory accepted overlapping read");
// 					$finish(1);
// 				end
// 				tri_mem_pending_q <= 1'b1;
// 				tri_mem_delay_q <= MEM_LATENCY;
// 				tri_data_pending_q <= tri_lookup(tri_mem_req_addr_o);
// 				tri_mem_error_pending_q <= !tri_addr_valid(tri_mem_req_addr_o);
// 				tri_mem_read_count <= tri_mem_read_count + 1;
// 			end
// 		end
// 	function automatic [31:0] q16;
// 		input real x;
// 		integer signed temp;
// 		begin
// 			temp = $rtoi(x * 65536.0);
// 			q16 = temp;
// 		end
// 	endfunction
// 	function automatic [31:0] fx;
// 		input real x;
// 		fx[31-:32] = q16(x);
// 	endfunction
// 	function automatic [95:0] vec3;
// 		input real x;
// 		input real y;
// 		input real z;
// 		reg [95:0] value;
// 		begin
// 			value[95-:32] = q16(x);
// 			value[63-:32] = q16(y);
// 			value[31-:32] = q16(z);
// 			vec3 = value;
// 		end
// 	endfunction
// 	task automatic set_triangle;
// 		input integer idx;
// 		input reg [15:0] prim;
// 		input real z;
// 		begin
// 			tri_mem[idx] = 1'sb0;
// 			tri_mem[idx][303-:16] = prim;
// 			tri_mem[idx][287-:32] = q16(-1.0);
// 			tri_mem[idx][255-:32] = q16(-1.0);
// 			tri_mem[idx][223-:32] = q16(z);
// 			tri_mem[idx][191-:32] = q16(1.0);
// 			tri_mem[idx][159-:32] = q16(-1.0);
// 			tri_mem[idx][127-:32] = q16(z);
// 			tri_mem[idx][95-:32] = q16(0.0);
// 			tri_mem[idx][63-:32] = q16(1.0);
// 			tri_mem[idx][31-:32] = q16(z);
// 			tri_present[idx] = 1'b1;
// 		end
// 	endtask
// 	task automatic set_node;
// 		input integer idx;
// 		input real min_x;
// 		input real min_y;
// 		input real min_z;
// 		input real max_x;
// 		input real max_y;
// 		input real max_z;
// 		input reg [31:0] left_first;
// 		input reg [31:0] tri_count;
// 		begin
// 			node_mem[idx] = 1'sb0;
// 			node_mem[idx][255-:32] = q16(min_x);
// 			node_mem[idx][223-:32] = q16(min_y);
// 			node_mem[idx][191-:32] = q16(min_z);
// 			node_mem[idx][159-:32] = q16(max_x);
// 			node_mem[idx][127-:32] = q16(max_y);
// 			node_mem[idx][95-:32] = q16(max_z);
// 			node_mem[idx][63-:32] = left_first;
// 			node_mem[idx][31-:32] = tri_count;
// 			node_present[idx] = 1'b1;
// 		end
// 	endtask
// 	task automatic clear_scene;
// 		integer i;
// 		begin
// 			for (i = 0; i < NODE_COUNT; i = i + 1)
// 				begin
// 					node_mem[i] = 1'sb0;
// 					node_present[i] = 1'b0;
// 				end
// 			for (i = 0; i < TRI_COUNT; i = i + 1)
// 				begin
// 					tri_mem[i] = 1'sb0;
// 					tri_present[i] = 1'b0;
// 				end
// 		end
// 	endtask
// 	function automatic [439:0] make_request;
// 		input reg [31:0] root;
// 		input real ox;
// 		input real oy;
// 		input real oz;
// 		reg [439:0] req;
// 		begin
// 			req = 1'sb0;
// 			req[439-:16] = 16'h1234;
// 			req[391-:96] = vec3(ox, oy, oz);
// 			req[295-:96] = vec3(0.125, 0.125, 1.0);
// 			req[199-:8] = 8'h2a;
// 			req[191-:32] = root;
// 			req[159-:96] = vec3(8.0, 8.0, 1.0);
// 			req[63-:32] = q16(0.0);
// 			req[31-:32] = q16(100.0);
// 			make_request = req;
// 		end
// 	endfunction
// 	task automatic run_traversal;
// 		input reg [439:0] req;
// 		output reg [112:0] res;
// 		integer cycle_count;
// 		begin
// 			cycle_count = 0;
// 			@(negedge clk)
// 				;
// 			traversal_i = req;
// 			traversal_valid_i = 1'b1;
// 			begin : sv2v_autoblock_1
// 				reg sv2v_do_while;
// 				sv2v_do_while = 1;
// 				while (sv2v_do_while || !traversal_ready_o) begin
// 					sv2v_do_while = 0;
// 					@(posedge clk)
// 						;
// 					cycle_count = cycle_count + 1;
// 					if (cycle_count > 1000) begin
// 						$display("Fatal [%0t] testbench/traversal_controller_tb.sv:598:21 - traversal_controller_tb.run_traversal.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Timed out waiting for traversal request acceptance");
// 						$finish(1);
// 					end
// 				end
// 			end
// 			@(negedge clk)
// 				;
// 			traversal_valid_i = 1'b0;
// 			cycle_count = 0;
// 			while (!traversal_result_valid_o) begin
// 				@(negedge clk)
// 					;
// 				cycle_count = cycle_count + 1;
// 				if (cycle_count > 3000) begin
// 					$display("Fatal [%0t] testbench/traversal_controller_tb.sv:608:21 - traversal_controller_tb.run_traversal.<unnamed_block>.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Timed out waiting for traversal result");
// 					$finish(1);
// 				end
// 			end
// 			res = traversal_result_o;
// 			if (stack_overflow_o) begin
// 				$display("Fatal [%0t] testbench/traversal_controller_tb.sv:612:17 - traversal_controller_tb.run_traversal.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Traversal reported stack overflow");
// 				$finish(1);
// 			end
// 			@(posedge clk)
// 				;
// 			@(negedge clk)
// 				;
// 		end
// 	endtask
// 	task automatic check_q16;
// 		input string field_name;
// 		input reg [31:0] actual;
// 		input real expected_real;
// 		input integer tolerance_lsb;
// 		integer signed actual_s;
// 		integer signed expected_s;
// 		integer signed delta;
// 		begin
// 			actual_s = $signed(actual[31-:32]);
// 			expected_s = $signed(q16(expected_real));
// 			delta = actual_s - expected_s;
// 			if ((delta > tolerance_lsb) || (delta < -tolerance_lsb)) begin
// 				$display("Fatal [%0t] testbench/traversal_controller_tb.sv:633:17 - traversal_controller_tb.check_q16.<unnamed_block>.<unnamed_block>\n msg: ", $time, "%s mismatch: got raw=%0d (%.6f), expected %.6f (raw=%0d)", field_name, actual_s, $itor(actual_s) / 65536.0, expected_real, expected_s);
// 				$finish(1);
// 			end
// 		end
// 	endtask
// 	task automatic setup_simple_leaf;
// 		begin
// 			clear_scene;
// 			set_triangle(0, 16'd7, 3.0);
// 			set_node(0, -2.0, -2.0, 2.0, 2.0, 2.0, 4.0, TRI_BASE, 32'd1);
// 		end
// 	endtask
// 	task automatic setup_two_child_bvh;
// 		input reg left_box_hits;
// 		begin
// 			clear_scene;
// 			set_node(0, -2.0, -2.0, 0.0, 2.0, 2.0, 6.0, BVH_BASE + NODE_BYTES, 32'd2);
// 			if (left_box_hits)
// 				set_node(1, -2.0, -2.0, 4.5, 2.0, 2.0, 5.5, TRI_BASE, 32'd1);
// 			else
// 				set_node(1, 4.0, 4.0, 4.5, 6.0, 6.0, 5.5, TRI_BASE, 32'd1);
// 			set_node(2, -2.0, -2.0, 2.5, 2.0, 2.0, 3.5, TRI_BASE + TRI_STRIDE, 32'd1);
// 			set_triangle(0, 16'd11, 5.0);
// 			set_triangle(1, 16'd22, 3.0);
// 		end
// 	endtask
// 	integer bvh_before;
// 	integer tri_mem_before;
// 	integer aabb_before;
// 	integer tri_before;
// 	reg [112:0] result;
// 	initial begin
// 		$dumpfile("waves/traversal_controller.vcd");
// 		$dumpvars(0, traversal_controller_tb);
// 	end
// 	initial begin
// 		traversal_valid_i = 1'b0;
// 		traversal_i = 1'sb0;
// 		traversal_result_ready_i = 1'b1;
// 		clear_scene;
// 		repeat (4) @(negedge clk)
// 			;
// 		rst_n = 1'b1;
// 		repeat (3) @(negedge clk)
// 			;
// 		$display("[TEST 1] Single-leaf triangle hit");
// 		setup_simple_leaf;
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (!result[112] || (result[111-:16] != 16'd7)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:695:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf hit: wrong hit/primitive result");
// 			$finish(1);
// 		end
// 		check_q16("hit distance", result[95-:32], 3.0, 2);
// 		check_q16("barycentric u", result[63-:32], 0.25, 2);
// 		check_q16("barycentric v", result[31-:32], 0.5, 2);
// 		if (((((bvh_read_count - bvh_before) != 1) || ((tri_mem_read_count - tri_mem_before) != 1)) || ((aabb_request_count - aabb_before) != 0)) || ((tri_intersection_count - tri_before) != 1)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:701:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf hit: unexpected memory/intersection request counts");
// 			$finish(1);
// 		end
// 		$display("[TEST 2] Single-leaf triangle miss");
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, 8.0, 8.0, 0.0), result);
// 		if (result[112]) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:710:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf miss: unexpected hit");
// 			$finish(1);
// 		end
// 		if (((((bvh_read_count - bvh_before) != 1) || ((tri_mem_read_count - tri_mem_before) != 1)) || ((aabb_request_count - aabb_before) != 0)) || ((tri_intersection_count - tri_before) != 1)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:713:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Single-leaf miss: unexpected memory/intersection request counts");
// 			$finish(1);
// 		end
// 		$display("[TEST 3] Two-child BVH, nearest child first, far child pruned");
// 		setup_two_child_bvh(1'b1);
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (!result[112] || (result[111-:16] != 16'd22)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:723:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: nearest primitive was not returned");
// 			$finish(1);
// 		end
// 		check_q16("nearest hit distance", result[95-:32], 3.0, 2);
// 		check_q16("nearest barycentric u", result[63-:32], 0.25, 2);
// 		check_q16("nearest barycentric v", result[31-:32], 0.5, 2);
// 		if ((aabb_request_count - aabb_before) != 2) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:728:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected exactly two child AABB tests, got %0d", aabb_request_count - aabb_before);
// 			$finish(1);
// 		end
// 		if ((tri_intersection_count - tri_before) != 1) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:731:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected far triangle to be pruned, tri tests=%0d", tri_intersection_count - tri_before);
// 			$finish(1);
// 		end
// 		if ((bvh_read_count - bvh_before) != 4) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:734:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected 4 BVH reads (root, child metadata x2, near node), got %0d", bvh_read_count - bvh_before);
// 			$finish(1);
// 		end
// 		if ((tri_mem_read_count - tri_mem_before) != 1) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:737:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Two-child traversal: expected 1 triangle memory read");
// 			$finish(1);
// 		end
// 		$display("[TEST 4] One child AABB miss, other child hits");
// 		setup_two_child_bvh(1'b0);
// 		bvh_before = bvh_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (!result[112] || (result[111-:16] != 16'd22)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:746:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "One-child-hit traversal: wrong result");
// 			$finish(1);
// 		end
// 		if (((aabb_request_count - aabb_before) != 2) || ((tri_intersection_count - tri_before) != 1)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:748:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "One-child-hit traversal: unexpected AABB/triangle request count");
// 			$finish(1);
// 		end
// 		$display("[TEST 5] Internal node where both child AABBs miss");
// 		setup_two_child_bvh(1'b0);
// 		node_mem[2][255-:32] = q16(4.0);
// 		node_mem[2][223-:32] = q16(4.0);
// 		node_mem[2][191-:32] = q16(2.5);
// 		node_mem[2][159-:32] = q16(6.0);
// 		node_mem[2][127-:32] = q16(6.0);
// 		node_mem[2][95-:32] = q16(3.5);
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if (result[112]) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:765:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Both-child-miss traversal unexpectedly hit");
// 			$finish(1);
// 		end
// 		if (((aabb_request_count - aabb_before) != 2) || ((tri_intersection_count - tri_before) != 0)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:767:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Both-child-miss traversal: unexpected AABB/triangle request count");
// 			$finish(1);
// 		end
// 		$display("[TEST 6] Empty root leaf");
// 		clear_scene;
// 		set_node(0, -1.0, -1.0, -1.0, 1.0, 1.0, 1.0, 1'sb0, 32'd0);
// 		bvh_before = bvh_read_count;
// 		tri_mem_before = tri_mem_read_count;
// 		aabb_before = aabb_request_count;
// 		tri_before = tri_intersection_count;
// 		run_traversal(make_request(BVH_BASE, -0.375, -0.375, 0.0), result);
// 		if ((result[112] || (result[95-:32] != 0)) || (result[111-:16] != 0)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:778:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Empty root did not return a clean miss");
// 			$finish(1);
// 		end
// 		if (((((bvh_read_count - bvh_before) != 1) || ((tri_mem_read_count - tri_mem_before) != 0)) || ((aabb_request_count - aabb_before) != 0)) || ((tri_intersection_count - tri_before) != 0)) begin
// 			$display("Fatal [%0t] testbench/traversal_controller_tb.sv:781:13 - traversal_controller_tb.<unnamed_block>.<unnamed_block>\n msg: ", $time, "Empty root: unexpected memory/intersection request counts");
// 			$finish(1);
// 		end
// 		$display("PASS: all initial BVH traversal integration tests passed");
// 		$finish;
// 	end
// 	always @(posedge clk or negedge rst_n)
// 		if (!rst_n)
// 			aabb_request_count <= 0;
// 		else if (aabb_req_valid_o && aabb_req_ready_i)
// 			aabb_request_count <= aabb_request_count + 1;
// 	initial _sv2v_0 = 0;
// endmodule
