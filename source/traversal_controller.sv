module traversal_controller (
	clk,
	rst_n,
	traversal_valid_i,
	traversal_ready_o,
	traversal_i,
	bvh_mem_req_valid_o,
	bvh_mem_req_ready_i,
	bvh_mem_req_addr_o,
	bvh_mem_resp_valid_i,
	bvh_mem_resp_error_i,
	bvh_mem_resp_data_i,
	tri_mem_req_valid_o,
	tri_mem_req_ready_i,
	tri_mem_req_addr_o,
	tri_mem_resp_valid_i,
	tri_mem_resp_error_i,
	tri_mem_resp_data_i,
	aabb_req_valid_o,
	aabb_req_ready_i,
	aabb_req_o,
	aabb_result_valid_i,
	aabb_result_i,
	tri_req_valid_o,
	tri_req_ready_i,
	tri_req_o,
	tri_result_valid_i,
	tri_result_i,
	traversal_result_valid_o,
	traversal_result_ready_i,
	traversal_result_o,
	stack_overflow_o
);
	reg _sv2v_0;
	parameter signed [31:0] STACK_DEPTH = 16;
	parameter signed [31:0] TRIANGLE_STRIDE_BYTES = 40;
	input wire clk;
	input wire rst_n;
	input wire traversal_valid_i;
	output reg traversal_ready_o;
	input wire [439:0] traversal_i;
	output reg bvh_mem_req_valid_o;
	input wire bvh_mem_req_ready_i;
	output reg [31:0] bvh_mem_req_addr_o;
	input wire bvh_mem_resp_valid_i;
	input wire bvh_mem_resp_error_i;
	input wire [255:0] bvh_mem_resp_data_i;
	output reg tri_mem_req_valid_o;
	input wire tri_mem_req_ready_i;
	output reg [31:0] tri_mem_req_addr_o;
	input wire tri_mem_resp_valid_i;
	input wire tri_mem_resp_error_i;
	input wire [303:0] tri_mem_resp_data_i;
	output reg aabb_req_valid_o;
	input wire aabb_req_ready_i;
	output reg [551:0] aabb_req_o;
	input wire aabb_result_valid_i;
	input wire [72:0] aabb_result_i;
	output reg tri_req_valid_o;
	input wire tri_req_ready_i;
	output reg [663:0] tri_req_o;
	input wire tri_result_valid_i;
	input wire [121:0] tri_result_i;
	output reg traversal_result_valid_o;
	input wire traversal_result_ready_i;
	output reg [112:0] traversal_result_o;
	output reg stack_overflow_o;
	localparam signed [31:0] STACK_PTR_WIDTH = $clog2(STACK_DEPTH + 1);
	localparam signed [31:0] BVH_NODE_BYTES = 32;
	reg [4:0] state_q;
	reg [4:0] state_d;
	reg [7:0] context_id_q;
	reg [7:0] context_id_d;
	reg [31:0] bvh_root_q;
	reg [31:0] bvh_root_d;
	reg [95:0] ray_origin_q;
	reg [95:0] ray_origin_d;
	reg [95:0] ray_direction_q;
	reg [95:0] ray_direction_d;
	reg [95:0] ray_inv_direction_q;
	reg [95:0] ray_inv_direction_d;
	reg [31:0] ray_t_min_q;
	reg [31:0] ray_t_min_d;
	reg [63:0] stack_q [0:STACK_DEPTH - 1];
	reg [63:0] stack_d [0:STACK_DEPTH - 1];
	reg [STACK_PTR_WIDTH - 1:0] stack_ptr_q;
	reg [STACK_PTR_WIDTH - 1:0] stack_ptr_d;
	reg [31:0] current_node_addr_q;
	reg [31:0] current_node_addr_d;
	reg [31:0] current_t_near_q;
	reg [31:0] current_t_near_d;
	reg [255:0] current_node_q;
	reg [255:0] current_node_d;
	reg [255:0] left_child_q;
	reg [255:0] left_child_d;
	reg [255:0] right_child_q;
	reg [255:0] right_child_d;
	reg left_hit_q;
	reg left_hit_d;
	reg right_hit_q;
	reg right_hit_d;
	reg [31:0] left_t_near_q;
	reg [31:0] left_t_near_d;
	reg [31:0] right_t_near_q;
	reg [31:0] right_t_near_d;
	reg [31:0] tri_addr_q;
	reg [31:0] tri_addr_d;
	reg [31:0] tri_index_q;
	reg [31:0] tri_index_d;
	reg [303:0] current_triangle_q;
	reg [303:0] current_triangle_d;
	reg [121:0] pending_tri_result_q;
	reg [121:0] pending_tri_result_d;
	reg best_hit_q;
	reg best_hit_d;
	reg best_facing_front_q;
	reg best_facing_front_d;
	reg [15:0] best_primitive_id_q;
	reg [15:0] best_primitive_id_d;
	reg [31:0] best_t_q;
	reg [31:0] best_t_d;
	reg [31:0] best_u_q;
	reg [31:0] best_u_d;
	reg [31:0] best_v_q;
	reg [31:0] best_v_d;
	reg stack_overflow_q;
	reg stack_overflow_d;
	reg cmp_valid_i;
	wire cmp_ready_o;
	wire cmp_a_gt_b;
	wire cmp_a_lt_b;
	wire cmp_valid_o;
	reg cmp_ready_i;
	reg [31:0] cmp_operand_a;
	reg [31:0] cmp_operand_b;
	q16p16_comp u_q16p16_comp(
		.clk(clk),
		.n_rst(rst_n),
		.operand_a(cmp_operand_a),
		.operand_b(cmp_operand_b),
		.valid_i(cmp_valid_i),
		.ready_o(cmp_ready_o),
		.a_gt_b(cmp_a_gt_b),
		.a_lt_b(cmp_a_lt_b),
		.valid_o(cmp_valid_o),
		.ready_i(cmp_ready_i)
	);
	function automatic [31:0] negate_word;
		input reg [31:0] value;
		reg [31:0] bits;
		begin
			bits = value;
			bits = ~bits + 32'd1;
			negate_word = bits;
		end
	endfunction
	always @(*) begin : p_next
		integer i;
		if (_sv2v_0)
			;
		state_d = state_q;
		context_id_d = context_id_q;
		bvh_root_d = bvh_root_q;
		ray_origin_d = ray_origin_q;
		ray_direction_d = ray_direction_q;
		ray_inv_direction_d = ray_inv_direction_q;
		ray_t_min_d = ray_t_min_q;
		stack_ptr_d = stack_ptr_q;
		current_node_addr_d = current_node_addr_q;
		current_t_near_d = current_t_near_q;
		current_node_d = current_node_q;
		left_child_d = left_child_q;
		right_child_d = right_child_q;
		left_hit_d = left_hit_q;
		right_hit_d = right_hit_q;
		left_t_near_d = left_t_near_q;
		right_t_near_d = right_t_near_q;
		tri_addr_d = tri_addr_q;
		tri_index_d = tri_index_q;
		current_triangle_d = current_triangle_q;
		pending_tri_result_d = pending_tri_result_q;
		best_hit_d = best_hit_q;
		best_facing_front_d = best_facing_front_q;
		best_primitive_id_d = best_primitive_id_q;
		best_t_d = best_t_q;
		best_u_d = best_u_q;
		best_v_d = best_v_q;
		stack_overflow_d = stack_overflow_q;
		for (i = 0; i < STACK_DEPTH; i = i + 1)
			stack_d[i] = stack_q[i];
		traversal_ready_o = state_q == 5'd0;
		bvh_mem_req_valid_o = 1'b0;
		bvh_mem_req_addr_o = current_node_addr_q;
		tri_mem_req_valid_o = 1'b0;
		tri_mem_req_addr_o = tri_addr_q;
		aabb_req_valid_o = 1'b0;
		aabb_req_o = 1'sb0;
		tri_req_valid_o = 1'b0;
		tri_req_o = 1'sb0;
		traversal_result_valid_o = state_q == 5'd26;
		traversal_result_o = 1'sb0;
		traversal_result_o[112] = best_hit_q;
		traversal_result_o[111-:16] = (best_hit_q ? best_primitive_id_q : {16 {1'sb0}});
		traversal_result_o[95-:32] = (best_hit_q ? (best_facing_front_q ? best_t_q : negate_word(best_t_q)) : {32 {1'sb0}});
		traversal_result_o[63-:32] = (best_hit_q ? best_u_q : {32 {1'sb0}});
		traversal_result_o[31-:32] = (best_hit_q ? best_v_q : {32 {1'sb0}});
		stack_overflow_o = stack_overflow_q;
		cmp_valid_i = 1'b0;
		cmp_ready_i = 1'b0;
		cmp_operand_a = 1'sb0;
		cmp_operand_b = 1'sb0;
		case (state_q)
			5'd6: begin
				bvh_mem_req_valid_o = 1'b1;
				bvh_mem_req_addr_o = current_node_addr_q;
			end
			5'd8: begin
				bvh_mem_req_valid_o = 1'b1;
				bvh_mem_req_addr_o = current_node_q[63-:32];
			end
			5'd10: begin
				bvh_mem_req_valid_o = 1'b1;
				bvh_mem_req_addr_o = current_node_q[63-:32] + BVH_NODE_BYTES;
			end
			default:
				;
		endcase
		if (state_q == 5'd19)
			tri_mem_req_valid_o = 1'b1;
		aabb_req_o[551-:8] = context_id_q;
		aabb_req_o[543-:96] = ray_origin_q;
		aabb_req_o[447-:96] = ray_direction_q;
		aabb_req_o[351-:96] = ray_inv_direction_q;
		aabb_req_o[255-:32] = ray_t_min_q;
		aabb_req_o[223-:32] = best_t_q;
		tri_req_o[663-:8] = context_id_q;
		tri_req_o[655-:96] = ray_origin_q;
		tri_req_o[559-:96] = ray_direction_q;
		tri_req_o[463-:96] = ray_inv_direction_q;
		tri_req_o[367-:32] = ray_t_min_q;
		tri_req_o[335-:32] = best_t_q;
		tri_req_o[303-:304] = current_triangle_q;
		case (state_q)
			5'd12: begin
				aabb_req_valid_o = 1'b1;
				aabb_req_o[191-:192] = left_child_q[255-:192];
			end
			5'd13: begin
				aabb_req_valid_o = 1'b1;
				aabb_req_o[191-:192] = right_child_q[255-:192];
			end
			5'd21: tri_req_valid_o = 1'b1;
			default:
				;
		endcase
		case (state_q)
			5'd4: begin
				cmp_valid_i = 1'b1;
				cmp_operand_a = best_t_q;
				cmp_operand_b = current_t_near_q;
			end
			5'd5: cmp_ready_i = 1'b1;
			5'd17: begin
				cmp_valid_i = 1'b1;
				cmp_operand_a = left_t_near_q;
				cmp_operand_b = right_t_near_q;
			end
			5'd18: cmp_ready_i = 1'b1;
			5'd23: begin
				cmp_valid_i = 1'b1;
				cmp_operand_a = pending_tri_result_q[96-:32];
				cmp_operand_b = best_t_q;
			end
			5'd24: cmp_ready_i = 1'b1;
			default:
				;
		endcase
		case (state_q)
			5'd0:
				if (traversal_valid_i && traversal_ready_o) begin
					context_id_d = traversal_i[199-:8];
					bvh_root_d = traversal_i[191-:32];
					ray_origin_d = traversal_i[391-:96];
					ray_direction_d = traversal_i[295-:96];
					ray_inv_direction_d = traversal_i[159-:96];
					ray_t_min_d = traversal_i[63-:32];
					stack_ptr_d = 1'sb0;
					best_hit_d = 1'b0;
					best_facing_front_d = 1'b0;
					best_primitive_id_d = 1'sb0;
					best_t_d = traversal_i[31-:32];
					best_u_d = 1'sb0;
					best_v_d = 1'sb0;
					stack_overflow_d = 1'b0;
					state_d = 5'd1;
				end
			5'd1: begin
				stack_d[0][63-:32] = bvh_root_q;
				stack_d[0][31-:32] = ray_t_min_q;
				stack_ptr_d = {{STACK_PTR_WIDTH - 1 {1'b0}}, 1'b1};
				state_d = 5'd2;
			end
			5'd2:
				if (stack_ptr_q == 0)
					state_d = 5'd26;
				else begin
					current_node_addr_d = stack_q[stack_ptr_q - 1'b1][63-:32];
					current_t_near_d = stack_q[stack_ptr_q - 1'b1][31-:32];
					stack_ptr_d = stack_ptr_q - 1'b1;
					state_d = 5'd3;
				end
			5'd3: state_d = 5'd4;
			5'd4:
				if (cmp_ready_o)
					state_d = 5'd5;
			5'd5:
				if (cmp_valid_o)
					state_d = (cmp_a_lt_b ? 5'd2 : 5'd6);
			5'd6:
				if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
					state_d = 5'd7;
			5'd7:
				if (bvh_mem_resp_valid_i) begin
					if (bvh_mem_resp_error_i)
						state_d = 5'd2;
					else begin
						current_node_d = bvh_mem_resp_data_i;
						if (bvh_mem_resp_data_i[31-:32] > 32'd1)
							state_d = 5'd8;
						else if (bvh_mem_resp_data_i[31-:32] == 0)
							state_d = 5'd2;
						else begin
							tri_addr_d = bvh_mem_resp_data_i[63-:32];
							tri_index_d = 1'sb0;
							state_d = 5'd19;
						end
					end
				end
			5'd8:
				if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
					state_d = 5'd9;
			5'd9:
				if (bvh_mem_resp_valid_i) begin
					if (bvh_mem_resp_error_i)
						state_d = 5'd2;
					else begin
						left_child_d = bvh_mem_resp_data_i;
						state_d = 5'd10;
					end
				end
			5'd10:
				if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
					state_d = 5'd11;
			5'd11:
				if (bvh_mem_resp_valid_i) begin
					if (bvh_mem_resp_error_i)
						state_d = 5'd2;
					else begin
						right_child_d = bvh_mem_resp_data_i;
						state_d = 5'd12;
					end
				end
			5'd12:
				if (aabb_req_valid_o && aabb_req_ready_i)
					state_d = 5'd13;
			5'd13:
				if (aabb_req_valid_o && aabb_req_ready_i)
					state_d = 5'd14;
			5'd14:
				if (aabb_result_valid_i) begin
					left_hit_d = aabb_result_i[64];
					left_t_near_d = aabb_result_i[63-:32];
					state_d = 5'd15;
				end
			5'd15:
				if (aabb_result_valid_i) begin
					right_hit_d = aabb_result_i[64];
					right_t_near_d = aabb_result_i[63-:32];
					state_d = 5'd16;
				end
			5'd16:
				if (left_hit_q && right_hit_q)
					state_d = 5'd17;
				else if (left_hit_q || right_hit_q) begin
					if (stack_ptr_q < STACK_DEPTH) begin
						if (left_hit_q) begin
							stack_d[stack_ptr_q][63-:32] = current_node_q[63-:32];
							stack_d[stack_ptr_q][31-:32] = left_t_near_q;
						end
						else begin
							stack_d[stack_ptr_q][63-:32] = current_node_q[63-:32] + BVH_NODE_BYTES;
							stack_d[stack_ptr_q][31-:32] = right_t_near_q;
						end
						stack_ptr_d = stack_ptr_q + 1'b1;
					end
					else
						stack_overflow_d = 1'b1;
					state_d = 5'd2;
				end
				else
					state_d = 5'd2;
			5'd17:
				if (cmp_ready_o)
					state_d = 5'd18;
			5'd18:
				if (cmp_valid_o) begin
					if (stack_ptr_q <= (STACK_DEPTH - 2)) begin
						if (cmp_a_lt_b) begin
							stack_d[stack_ptr_q][63-:32] = current_node_q[63-:32] + BVH_NODE_BYTES;
							stack_d[stack_ptr_q][31-:32] = right_t_near_q;
							stack_d[stack_ptr_q + 1'b1][63-:32] = current_node_q[63-:32];
							stack_d[stack_ptr_q + 1'b1][31-:32] = left_t_near_q;
						end
						else begin
							stack_d[stack_ptr_q][63-:32] = current_node_q[63-:32];
							stack_d[stack_ptr_q][31-:32] = left_t_near_q;
							stack_d[stack_ptr_q + 1'b1][63-:32] = current_node_q[63-:32] + BVH_NODE_BYTES;
							stack_d[stack_ptr_q + 1'b1][31-:32] = right_t_near_q;
						end
						stack_ptr_d = stack_ptr_q + 2'd2;
					end
					else
						stack_overflow_d = 1'b1;
					state_d = 5'd2;
				end
			5'd19:
				if (tri_mem_req_valid_o && tri_mem_req_ready_i)
					state_d = 5'd20;
			5'd20:
				if (tri_mem_resp_valid_i) begin
					if (tri_mem_resp_error_i)
						state_d = 5'd25;
					else begin
						current_triangle_d = tri_mem_resp_data_i;
						state_d = 5'd21;
					end
				end
			5'd21:
				if (tri_req_valid_o && tri_req_ready_i)
					state_d = 5'd22;
			5'd22:
				if (tri_result_valid_i) begin
					if (tri_result_i[113]) begin
						pending_tri_result_d = tri_result_i;
						state_d = 5'd23;
					end
					else
						state_d = 5'd25;
				end
			5'd23:
				if (cmp_ready_o)
					state_d = 5'd24;
			5'd24:
				if (cmp_valid_o) begin
					if (cmp_a_lt_b) begin
						best_hit_d = 1'b1;
						best_t_d = pending_tri_result_q[96-:32];
						best_primitive_id_d = pending_tri_result_q[112-:16];
						best_u_d = pending_tri_result_q[64-:32];
						best_v_d = pending_tri_result_q[32-:32];
						best_facing_front_d = pending_tri_result_q[0];
					end
					state_d = 5'd25;
				end
			5'd25:
				if ((tri_index_q + 1) < current_node_q[31-:32]) begin
					tri_index_d = tri_index_q + 1'b1;
					tri_addr_d = tri_addr_q + TRIANGLE_STRIDE_BYTES;
					state_d = 5'd19;
				end
				else
					state_d = 5'd2;
			5'd26:
				if (traversal_result_ready_i)
					state_d = 5'd0;
			default: begin
				state_d = 5'd0;
				stack_ptr_d = 1'sb0;
			end
		endcase
	end
	always @(posedge clk or negedge rst_n) begin : p_regs
		integer i;
		if (!rst_n) begin
			state_q <= 5'd0;
			context_id_q <= 1'sb0;
			bvh_root_q <= 1'sb0;
			ray_origin_q <= 1'sb0;
			ray_direction_q <= 1'sb0;
			ray_inv_direction_q <= 1'sb0;
			ray_t_min_q <= 1'sb0;
			stack_ptr_q <= 1'sb0;
			current_node_addr_q <= 1'sb0;
			current_t_near_q <= 1'sb0;
			current_node_q <= 1'sb0;
			left_child_q <= 1'sb0;
			right_child_q <= 1'sb0;
			left_hit_q <= 1'b0;
			right_hit_q <= 1'b0;
			left_t_near_q <= 1'sb0;
			right_t_near_q <= 1'sb0;
			tri_addr_q <= 1'sb0;
			tri_index_q <= 1'sb0;
			current_triangle_q <= 1'sb0;
			pending_tri_result_q <= 1'sb0;
			best_hit_q <= 1'b0;
			best_facing_front_q <= 1'b0;
			best_primitive_id_q <= 1'sb0;
			best_t_q <= 1'sb0;
			best_u_q <= 1'sb0;
			best_v_q <= 1'sb0;
			stack_overflow_q <= 1'b0;
			for (i = 0; i < STACK_DEPTH; i = i + 1)
				stack_q[i] <= 1'sb0;
		end
		else begin
			state_q <= state_d;
			context_id_q <= context_id_d;
			bvh_root_q <= bvh_root_d;
			ray_origin_q <= ray_origin_d;
			ray_direction_q <= ray_direction_d;
			ray_inv_direction_q <= ray_inv_direction_d;
			ray_t_min_q <= ray_t_min_d;
			stack_ptr_q <= stack_ptr_d;
			current_node_addr_q <= current_node_addr_d;
			current_t_near_q <= current_t_near_d;
			current_node_q <= current_node_d;
			left_child_q <= left_child_d;
			right_child_q <= right_child_d;
			left_hit_q <= left_hit_d;
			right_hit_q <= right_hit_d;
			left_t_near_q <= left_t_near_d;
			right_t_near_q <= right_t_near_d;
			tri_addr_q <= tri_addr_d;
			tri_index_q <= tri_index_d;
			current_triangle_q <= current_triangle_d;
			pending_tri_result_q <= pending_tri_result_d;
			best_hit_q <= best_hit_d;
			best_facing_front_q <= best_facing_front_d;
			best_primitive_id_q <= best_primitive_id_d;
			best_t_q <= best_t_d;
			best_u_q <= best_u_d;
			best_v_q <= best_v_d;
			stack_overflow_q <= stack_overflow_d;
			for (i = 0; i < STACK_DEPTH; i = i + 1)
				stack_q[i] <= stack_d[i];
		end
	end
	initial begin
		if (STACK_DEPTH < 2)
			$display("Error [%0t] source/traversal_controller_src.sv:648:13 - traversal_controller.<unnamed_block>.<unnamed_block>\n msg: ", $time, "bvh_traversal_controller: STACK_DEPTH must be >= 2");
		if (TRIANGLE_STRIDE_BYTES <= 0)
			$display("Error [%0t] source/traversal_controller_src.sv:650:13 - traversal_controller.<unnamed_block>.<unnamed_block>\n msg: ", $time, "bvh_traversal_controller: TRIANGLE_STRIDE_BYTES must be positive");
	end
	initial _sv2v_0 = 0;
endmodule
