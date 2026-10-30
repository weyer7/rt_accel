// `timescale 1ns/1ps
// `include "rtu_pkg.svh"

// // Single-active-ray BVH traversal controller (phases 1-4).
// //
// // Numeric representation:
// //   * Default build: Q16.16 words, compared only by q16p16_comp.
// //   * `FP build: fp32_t stores IEEE-754 words. Replace/bypass the fixed-point
// //     comparator with an IEEE-754 comparator before enabling that build.
// //
// // BVH encoding follows the software model:
// //   * tri_count > 1: internal node; children at left_first and left_first+32.
// //   * tri_count == 1: one-triangle leaf; left_first is triangle address.
// //   * tri_count == 0: empty leaf.
// // This encoding requires leaves to contain at most one triangle because
// // tri_count on internal nodes counts every descendant triangle.
// //
// // All request/response interfaces are latency tolerant. Each port has at most
// // one transaction outstanding in this single-context version.
// module traversal_controller #(
//     parameter int STACK_DEPTH = 16,
//     // Typical padded C layout is 40 bytes; use 38 for tightly packed records.
//     parameter int TRIANGLE_STRIDE_BYTES = 40
// ) (
//     input  logic clk,
//     input  logic rst_n,

//     input  logic               traversal_valid_i,
//     output logic               traversal_ready_o,
//     input  traversal_request_t traversal_i,

//     // BVH-node memory: return a complete node record per response.
//     output logic  bvh_mem_req_valid_o,
//     input  logic  bvh_mem_req_ready_i,
//     output addr_t bvh_mem_req_addr_o,
//     input  logic  bvh_mem_resp_valid_i,
//     input  logic  bvh_mem_resp_error_i,
//     input  bvh_node_t bvh_mem_resp_data_i,

//     // Triangle memory: return a complete triangle record per response.
//     output logic  tri_mem_req_valid_o,
//     input  logic  tri_mem_req_ready_i,
//     output addr_t tri_mem_req_addr_o,
//     input  logic  tri_mem_resp_valid_i,
//     input  logic  tri_mem_resp_error_i,
//     input  triangle_t tri_mem_resp_data_i,

//     // AABB intersection unit.
//     output logic         aabb_req_valid_o,
//     input  logic         aabb_req_ready_i,
//     output aabb_request_t aabb_req_o,
//     input  logic         aabb_result_valid_i,
//     input  aabb_result_t aabb_result_i,

//     // Triangle intersection unit.
//     output logic      tri_req_valid_o,
//     input  logic      tri_req_ready_i,
//     output tri_request_t tri_req_o,
//     input  logic      tri_result_valid_i,
//     input  tri_result_t tri_result_i,

//     // Explicit hit flag works with fixed point (where infinity is unavailable).
//     output logic              traversal_result_valid_o,
//     input  logic              traversal_result_ready_i,
//     output traversal_result_t traversal_result_o,

//     // Sticky until the next accepted traversal.
//     output logic stack_overflow_o
// );

//     localparam int STACK_PTR_WIDTH = $clog2(STACK_DEPTH + 1);
//     localparam int BVH_NODE_BYTES  = 32 /*$bits(bvh_node_t) / 8*/;

//     typedef enum logic [4:0] {
//         ST_IDLE,
//         ST_PUSH_ROOT,
//         ST_POP_STACK,
//         ST_CHECK_TNEAR,
//         ST_CMP_TNEAR_REQ,

//         ST_CMP_TNEAR_WAIT,
//         ST_NODE_REQ,
//         ST_NODE_WAIT,
//         ST_LEFT_CHILD_REQ,
//         ST_LEFT_CHILD_WAIT,
        
//         ST_RIGHT_CHILD_REQ,
//         ST_RIGHT_CHILD_WAIT,
//         ST_AABB_LEFT_REQ,
//         ST_AABB_LEFT_WAIT,
//         ST_AABB_RIGHT_REQ,
        
//         ST_AABB_RIGHT_WAIT,
//         ST_PUSH_CHILDREN,
//         ST_CMP_CHILD_REQ,
//         ST_CMP_CHILD_WAIT,
//         ST_TRI_MEM_REQ,
        
//         ST_TRI_MEM_WAIT,
//         ST_TRI_REQ,
//         ST_TRI_WAIT,
//         ST_CMP_TRI_REQ,
//         ST_CMP_TRI_WAIT,
        
//         ST_TRI_NEXT,
//         ST_RESULT
//     } state_t;

//     state_t state_q, state_d;

//     // Persistent active-ray state. These registers can later be replaced with
//     // context-memory reads/writes without changing the traversal sequencing.
//     logic [7:0] context_id_q, context_id_d;
//     addr_t bvh_root_q, bvh_root_d;
//     float3_t ray_origin_q, ray_origin_d;
//     float3_t ray_direction_q, ray_direction_d;
//     float3_t ray_inv_direction_q, ray_inv_direction_d;
//     fp32_t ray_t_min_q, ray_t_min_d;

//     bvh_stack_entry_t stack_q [0:STACK_DEPTH-1];
//     bvh_stack_entry_t stack_d [0:STACK_DEPTH-1];
//     logic [STACK_PTR_WIDTH-1:0] stack_ptr_q, stack_ptr_d;

//     addr_t current_node_addr_q, current_node_addr_d;
//     fp32_t current_t_near_q, current_t_near_d;
//     bvh_node_t current_node_q, current_node_d;
//     bvh_node_t left_child_q, left_child_d;
//     bvh_node_t right_child_q, right_child_d;
//     logic left_hit_q, left_hit_d;
//     logic right_hit_q, right_hit_d;
//     fp32_t left_t_near_q, left_t_near_d;
//     fp32_t right_t_near_q, right_t_near_d;

//     addr_t tri_addr_q, tri_addr_d;
//     logic [31:0] tri_index_q, tri_index_d;
//     triangle_t current_triangle_q, current_triangle_d;
//     tri_result_t pending_tri_result_q, pending_tri_result_d;

//     logic best_hit_q, best_hit_d;
//     logic best_facing_front_q, best_facing_front_d;
//     primitive_id_t best_primitive_id_q, best_primitive_id_d;
//     fp32_t best_t_q, best_t_d;
//     fp32_t best_u_q, best_u_d;
//     fp32_t best_v_q, best_v_d;
//     logic stack_overflow_q, stack_overflow_d;

//     // Shared, handshaked Q16.16 comparator. The request operands are selected
//     // by state; only one comparison can be outstanding at a time.
//     logic cmp_valid_i, cmp_ready_o;
//     logic cmp_a_gt_b, cmp_a_lt_b;
//     logic cmp_valid_o, cmp_ready_i;
//     logic [31:0] cmp_operand_a, cmp_operand_b;

//     q16p16_comp u_q16p16_comp (
//         .clk       (clk),
//         .n_rst     (rst_n),
//         .operand_a (cmp_operand_a),
//         .operand_b (cmp_operand_b),
//         .valid_i   (cmp_valid_i),
//         .ready_o   (cmp_ready_o),
//         .a_gt_b    (cmp_a_gt_b),
//         .a_lt_b    (cmp_a_lt_b),
//         .valid_o   (cmp_valid_o),
//         .ready_i   (cmp_ready_i)
//     );

//     // Two's-complement negation for current Q16.16 representation. Under `FP,
//     // sign-bit inversion is the IEEE-754 negation operation.
//     function automatic fp32_t negate_word(input fp32_t value);
//         logic [31:0] bits;
//         begin
//             bits = value;
// `ifdef FP
//             bits[31] = ~bits[31];
// `else
//             bits = (~bits) + 32'd1;
// `endif
//             negate_word = bits;
//         end
//     endfunction

//     // All next-state calculations, state transitions and output decodes are
//     // combinational. No register is assigned in this block.
//     always_comb begin : p_next
//         integer i;

//         state_d                 = state_q;
//         context_id_d            = context_id_q;
//         bvh_root_d              = bvh_root_q;
//         ray_origin_d            = ray_origin_q;
//         ray_direction_d         = ray_direction_q;
//         ray_inv_direction_d     = ray_inv_direction_q;
//         ray_t_min_d             = ray_t_min_q;
//         stack_ptr_d             = stack_ptr_q;
//         current_node_addr_d     = current_node_addr_q;
//         current_t_near_d        = current_t_near_q;
//         current_node_d          = current_node_q;
//         left_child_d            = left_child_q;
//         right_child_d           = right_child_q;
//         left_hit_d              = left_hit_q;
//         right_hit_d             = right_hit_q;
//         left_t_near_d           = left_t_near_q;
//         right_t_near_d          = right_t_near_q;
//         tri_addr_d              = tri_addr_q;
//         tri_index_d             = tri_index_q;
//         current_triangle_d      = current_triangle_q;
//         pending_tri_result_d    = pending_tri_result_q;
//         best_hit_d              = best_hit_q;
//         best_facing_front_d     = best_facing_front_q;
//         best_primitive_id_d     = best_primitive_id_q;
//         best_t_d                = best_t_q;
//         best_u_d                = best_u_q;
//         best_v_d                = best_v_q;
//         stack_overflow_d        = stack_overflow_q;
//         for (i = 0; i < STACK_DEPTH; i++)
//             stack_d[i] = stack_q[i];

//         // Default outputs: request channels idle and payloads deterministic.
//         traversal_ready_o          = (state_q == ST_IDLE);
//         bvh_mem_req_valid_o        = 1'b0;
//         bvh_mem_req_addr_o         = current_node_addr_q;
//         tri_mem_req_valid_o        = 1'b0;
//         tri_mem_req_addr_o         = tri_addr_q;
//         aabb_req_valid_o           = 1'b0;
//         aabb_req_o                 = '0;
//         tri_req_valid_o            = 1'b0;
//         tri_req_o                  = '0;
//         traversal_result_valid_o   = (state_q == ST_RESULT);
//         traversal_result_o         = '0;
//         traversal_result_o.hit     = best_hit_q;
//         traversal_result_o.primitive_id = best_hit_q ? best_primitive_id_q : '0;
//         traversal_result_o.distance = best_hit_q ?
//             (best_facing_front_q ? best_t_q : negate_word(best_t_q)) : '0;
//         traversal_result_o.u       = best_hit_q ? best_u_q : '0;
//         traversal_result_o.v       = best_hit_q ? best_v_q : '0;
//         stack_overflow_o            = stack_overflow_q;

//         cmp_valid_i    = 1'b0;
//         cmp_ready_i    = 1'b0;
//         cmp_operand_a  = '0;
//         cmp_operand_b  = '0;

//         // Memory request payloads are driven from registered state and remain
//         // stable throughout a request state until valid/ready handshakes.
//         case (state_q)
//             ST_NODE_REQ: begin
//                 bvh_mem_req_valid_o = 1'b1;
//                 bvh_mem_req_addr_o  = current_node_addr_q;
//             end
//             ST_LEFT_CHILD_REQ: begin
//                 bvh_mem_req_valid_o = 1'b1;
//                 bvh_mem_req_addr_o  = current_node_q.left_first;
//             end
//             ST_RIGHT_CHILD_REQ: begin
//                 bvh_mem_req_valid_o = 1'b1;
//                 bvh_mem_req_addr_o  = current_node_q.left_first + BVH_NODE_BYTES;
//             end
//             default: begin end
//         endcase

//         if (state_q == ST_TRI_MEM_REQ)
//             tri_mem_req_valid_o = 1'b1;

//         // Both accelerators get the current best distance as t_max.
//         aabb_req_o.context_id        = context_id_q;
//         aabb_req_o.ray.origin        = ray_origin_q;
//         aabb_req_o.ray.direction     = ray_direction_q;
//         aabb_req_o.ray.inv_direction = ray_inv_direction_q;
//         aabb_req_o.ray.t_min         = ray_t_min_q;
//         aabb_req_o.ray.t_max         = best_t_q;
//         tri_req_o.context_id         = context_id_q;
//         tri_req_o.ray.origin         = ray_origin_q;
//         tri_req_o.ray.direction      = ray_direction_q;
//         tri_req_o.ray.inv_direction  = ray_inv_direction_q;
//         tri_req_o.ray.t_min          = ray_t_min_q;
//         tri_req_o.ray.t_max          = best_t_q;
//         tri_req_o.triangle           = current_triangle_q;

//         case (state_q)
//             ST_AABB_LEFT_REQ: begin
//                 aabb_req_valid_o = 1'b1;
//                 aabb_req_o.box = left_child_q.box;
//             end
//             ST_AABB_RIGHT_REQ: begin
//                 aabb_req_valid_o = 1'b1;
//                 aabb_req_o.box = right_child_q.box;
//             end
//             ST_TRI_REQ: tri_req_valid_o = 1'b1;
//             default: begin end
//         endcase

//         // Comparison operands and handshake control for the shared comparator.
//         case (state_q)
//             ST_CMP_TNEAR_REQ: begin
//                 cmp_valid_i   = 1'b1;
//                 cmp_operand_a = best_t_q;
//                 cmp_operand_b = current_t_near_q;
//             end
//             ST_CMP_TNEAR_WAIT: cmp_ready_i = 1'b1;

//             ST_CMP_CHILD_REQ: begin
//                 cmp_valid_i   = 1'b1;
//                 cmp_operand_a = left_t_near_q;
//                 cmp_operand_b = right_t_near_q;
//             end
//             ST_CMP_CHILD_WAIT: cmp_ready_i = 1'b1;

//             ST_CMP_TRI_REQ: begin
//                 cmp_valid_i   = 1'b1;
//                 cmp_operand_a = pending_tri_result_q.t;
//                 cmp_operand_b = best_t_q;
//             end
//             ST_CMP_TRI_WAIT: cmp_ready_i = 1'b1;
//             default: begin end
//         endcase

//         // Main traversal FSM.
//         case (state_q)
//             ST_IDLE: begin
//                 if (traversal_valid_i && traversal_ready_o) begin
//                     context_id_d        = traversal_i.context_id;
//                     bvh_root_d          = traversal_i.bvh_root;
//                     ray_origin_d        = traversal_i.ray.origin;
//                     ray_direction_d     = traversal_i.ray.direction;
//                     ray_inv_direction_d = traversal_i.inv_direction;
//                     ray_t_min_d         = traversal_i.t_min;
//                     stack_ptr_d         = '0;
//                     best_hit_d          = 1'b0;
//                     best_facing_front_d = 1'b0;
//                     best_primitive_id_d = '0;
//                     best_t_d            = traversal_i.t_max;
//                     best_u_d             = '0;
//                     best_v_d             = '0;
//                     stack_overflow_d    = 1'b0;
//                     state_d             = ST_PUSH_ROOT;
//                 end
//             end

//             ST_PUSH_ROOT: begin
//                 stack_d[0].node_addr = bvh_root_q;
//                 stack_d[0].t_near    = ray_t_min_q;
//                 stack_ptr_d          = {{(STACK_PTR_WIDTH-1){1'b0}}, 1'b1};
//                 state_d              = ST_POP_STACK;
//             end

//             ST_POP_STACK: begin
//                 if (stack_ptr_q == 0) begin
//                     state_d = ST_RESULT;
//                 end else begin
//                     current_node_addr_d = stack_q[stack_ptr_q - 1'b1].node_addr;
//                     current_t_near_d    = stack_q[stack_ptr_q - 1'b1].t_near;
//                     stack_ptr_d         = stack_ptr_q - 1'b1;
//                     state_d              = ST_CHECK_TNEAR;
//                 end
//             end

//             ST_CHECK_TNEAR: state_d = ST_CMP_TNEAR_REQ;

//             ST_CMP_TNEAR_REQ: begin
//                 if (cmp_ready_o)
//                     state_d = ST_CMP_TNEAR_WAIT;
//             end

//             ST_CMP_TNEAR_WAIT: begin
//                 if (cmp_valid_o) begin
//                     // best_t < t_near means this stack entry cannot improve hit.
//                     state_d = cmp_a_lt_b ? ST_POP_STACK : ST_NODE_REQ;
//                 end
//             end

//             ST_NODE_REQ: begin
//                 if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
//                     state_d = ST_NODE_WAIT;
//             end

//             ST_NODE_WAIT: begin
//                 if (bvh_mem_resp_valid_i) begin
//                     if (bvh_mem_resp_error_i) begin
//                         state_d = ST_POP_STACK;
//                     end else begin
//                         current_node_d = bvh_mem_resp_data_i;
//                         if (bvh_mem_resp_data_i.tri_count > 32'd1)
//                             state_d = ST_LEFT_CHILD_REQ;
//                         else if (bvh_mem_resp_data_i.tri_count == 0)
//                             state_d = ST_POP_STACK;
//                         else begin
//                             tri_addr_d  = bvh_mem_resp_data_i.left_first;
//                             tri_index_d = '0;
//                             state_d     = ST_TRI_MEM_REQ;
//                         end
//                     end
//                 end
//             end

//             ST_LEFT_CHILD_REQ: begin
//                 if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
//                     state_d = ST_LEFT_CHILD_WAIT;
//             end

//             ST_LEFT_CHILD_WAIT: begin
//                 if (bvh_mem_resp_valid_i) begin
//                     if (bvh_mem_resp_error_i) begin
//                         state_d = ST_POP_STACK;
//                     end else begin
//                         left_child_d = bvh_mem_resp_data_i;
//                         state_d      = ST_RIGHT_CHILD_REQ;
//                     end
//                 end
//             end

//             ST_RIGHT_CHILD_REQ: begin
//                 if (bvh_mem_req_valid_o && bvh_mem_req_ready_i)
//                     state_d = ST_RIGHT_CHILD_WAIT;
//             end

//             ST_RIGHT_CHILD_WAIT: begin
//                 if (bvh_mem_resp_valid_i) begin
//                     if (bvh_mem_resp_error_i) begin
//                         state_d = ST_POP_STACK;
//                     end else begin
//                         right_child_d = bvh_mem_resp_data_i;
//                         state_d       = ST_AABB_LEFT_REQ;
//                     end
//                 end
//             end

//             ST_AABB_LEFT_REQ: begin
//                 if (aabb_req_valid_o && aabb_req_ready_i)
//                     state_d = ST_AABB_LEFT_WAIT;
//             end

//             ST_AABB_LEFT_WAIT: begin
//                 if (aabb_result_valid_i) begin
//                     left_hit_d    = aabb_result_i.hit;
//                     left_t_near_d = aabb_result_i.t_near;
//                     state_d       = ST_AABB_RIGHT_REQ;
//                 end
//             end

//             ST_AABB_RIGHT_REQ: begin
//                 if (aabb_req_valid_o && aabb_req_ready_i)
//                     state_d = ST_AABB_RIGHT_WAIT;
//             end

//             ST_AABB_RIGHT_WAIT: begin
//                 if (aabb_result_valid_i) begin
//                     right_hit_d    = aabb_result_i.hit;
//                     right_t_near_d = aabb_result_i.t_near;
//                     state_d        = ST_PUSH_CHILDREN;
//                 end
//             end

//             ST_PUSH_CHILDREN: begin
//                 if (left_hit_q && right_hit_q) begin
//                     state_d = ST_CMP_CHILD_REQ;
//                 end else if (left_hit_q || right_hit_q) begin
//                     if (stack_ptr_q < STACK_DEPTH) begin
//                         if (left_hit_q) begin
//                             stack_d[stack_ptr_q].node_addr = current_node_q.left_first;
//                             stack_d[stack_ptr_q].t_near    = left_t_near_q;
//                         end else begin
//                             stack_d[stack_ptr_q].node_addr = current_node_q.left_first + BVH_NODE_BYTES;
//                             stack_d[stack_ptr_q].t_near    = right_t_near_q;
//                         end
//                         stack_ptr_d = stack_ptr_q + 1'b1;
//                     end else begin
//                         stack_overflow_d = 1'b1;
//                     end
//                     state_d = ST_POP_STACK;
//                 end else begin
//                     state_d = ST_POP_STACK;
//                 end
//             end

//             ST_CMP_CHILD_REQ: begin
//                 if (cmp_ready_o)
//                     state_d = ST_CMP_CHILD_WAIT;
//             end

//             ST_CMP_CHILD_WAIT: begin
//                 if (cmp_valid_o) begin
//                     if (stack_ptr_q <= STACK_DEPTH - 2) begin
//                         // Push far first, near second so nearer is popped first.
//                         if (cmp_a_lt_b) begin
//                             stack_d[stack_ptr_q].node_addr       = current_node_q.left_first + BVH_NODE_BYTES;
//                             stack_d[stack_ptr_q].t_near          = right_t_near_q;
//                             stack_d[stack_ptr_q + 1'b1].node_addr = current_node_q.left_first;
//                             stack_d[stack_ptr_q + 1'b1].t_near    = left_t_near_q;
//                         end else begin
//                             stack_d[stack_ptr_q].node_addr       = current_node_q.left_first;
//                             stack_d[stack_ptr_q].t_near          = left_t_near_q;
//                             stack_d[stack_ptr_q + 1'b1].node_addr = current_node_q.left_first + BVH_NODE_BYTES;
//                             stack_d[stack_ptr_q + 1'b1].t_near    = right_t_near_q;
//                         end
//                         stack_ptr_d = stack_ptr_q + 2'd2;
//                     end else begin
//                         stack_overflow_d = 1'b1;
//                     end
//                     state_d = ST_POP_STACK;
//                 end
//             end

//             ST_TRI_MEM_REQ: begin
//                 if (tri_mem_req_valid_o && tri_mem_req_ready_i)
//                     state_d = ST_TRI_MEM_WAIT;
//             end

//             ST_TRI_MEM_WAIT: begin
//                 if (tri_mem_resp_valid_i) begin
//                     if (tri_mem_resp_error_i) begin
//                         state_d = ST_TRI_NEXT;
//                     end else begin
//                         current_triangle_d = tri_mem_resp_data_i;
//                         state_d            = ST_TRI_REQ;
//                     end
//                 end
//             end

//             ST_TRI_REQ: begin
//                 if (tri_req_valid_o && tri_req_ready_i)
//                     state_d = ST_TRI_WAIT;
//             end

//             ST_TRI_WAIT: begin
//                 if (tri_result_valid_i) begin
//                     if (tri_result_i.hit) begin
//                         pending_tri_result_d = tri_result_i;
//                         state_d = ST_CMP_TRI_REQ;
//                     end else begin
//                         state_d = ST_TRI_NEXT;
//                     end
//                 end
//             end

//             ST_CMP_TRI_REQ: begin
//                 if (cmp_ready_o)
//                     state_d = ST_CMP_TRI_WAIT;
//             end

//             ST_CMP_TRI_WAIT: begin
//                 if (cmp_valid_o) begin
//                     if (cmp_a_lt_b) begin
//                         best_hit_d          = 1'b1;
//                         best_t_d            = pending_tri_result_q.t;
//                         best_primitive_id_d = pending_tri_result_q.primitive_id;
//                         best_u_d            = pending_tri_result_q.u;
//                         best_v_d            = pending_tri_result_q.v;
//                         best_facing_front_d = pending_tri_result_q.facing_front;
//                     end
//                     state_d = ST_TRI_NEXT;
//                 end
//             end

//             ST_TRI_NEXT: begin
//                 if ((tri_index_q + 1) < current_node_q.tri_count) begin
//                     tri_index_d = tri_index_q + 1'b1;
//                     tri_addr_d  = tri_addr_q + TRIANGLE_STRIDE_BYTES;
//                     state_d     = ST_TRI_MEM_REQ;
//                 end else begin
//                     state_d = ST_POP_STACK;
//                 end
//             end

//             ST_RESULT: begin
//                 if (traversal_result_ready_i)
//                     state_d = ST_IDLE;
//             end

//             default: begin
//                 state_d     = ST_IDLE;
//                 stack_ptr_d = '0;
//             end
//         endcase
//     end

//     // Sequential block contains only reset values and q <= d register updates.
//     always_ff @(posedge clk or negedge rst_n) begin : p_regs
//         integer i;
//         if (!rst_n) begin
//             state_q                 <= ST_IDLE;
//             context_id_q            <= '0;
//             bvh_root_q              <= '0;
//             ray_origin_q            <= '0;
//             ray_direction_q         <= '0;
//             ray_inv_direction_q     <= '0;
//             ray_t_min_q             <= '0;
//             stack_ptr_q             <= '0;
//             current_node_addr_q     <= '0;
//             current_t_near_q        <= '0;
//             current_node_q          <= '0;
//             left_child_q            <= '0;
//             right_child_q           <= '0;
//             left_hit_q              <= 1'b0;
//             right_hit_q             <= 1'b0;
//             left_t_near_q           <= '0;
//             right_t_near_q          <= '0;
//             tri_addr_q              <= '0;
//             tri_index_q             <= '0;
//             current_triangle_q      <= '0;
//             pending_tri_result_q    <= '0;
//             best_hit_q              <= 1'b0;
//             best_facing_front_q     <= 1'b0;
//             best_primitive_id_q     <= '0;
//             best_t_q                <= '0;
//             best_u_q                <= '0;
//             best_v_q                <= '0;
//             stack_overflow_q        <= 1'b0;
//             for (i = 0; i < STACK_DEPTH; i++)
//                 stack_q[i] <= '0;
//         end else begin
//             state_q                 <= state_d;
//             context_id_q            <= context_id_d;
//             bvh_root_q              <= bvh_root_d;
//             ray_origin_q            <= ray_origin_d;
//             ray_direction_q         <= ray_direction_d;
//             ray_inv_direction_q     <= ray_inv_direction_d;
//             ray_t_min_q             <= ray_t_min_d;
//             stack_ptr_q             <= stack_ptr_d;
//             current_node_addr_q     <= current_node_addr_d;
//             current_t_near_q        <= current_t_near_d;
//             current_node_q          <= current_node_d;
//             left_child_q            <= left_child_d;
//             right_child_q           <= right_child_d;
//             left_hit_q              <= left_hit_d;
//             right_hit_q             <= right_hit_d;
//             left_t_near_q           <= left_t_near_d;
//             right_t_near_q          <= right_t_near_d;
//             tri_addr_q              <= tri_addr_d;
//             tri_index_q             <= tri_index_d;
//             current_triangle_q      <= current_triangle_d;
//             pending_tri_result_q    <= pending_tri_result_d;
//             best_hit_q              <= best_hit_d;
//             best_facing_front_q     <= best_facing_front_d;
//             best_primitive_id_q     <= best_primitive_id_d;
//             best_t_q                <= best_t_d;
//             best_u_q                <= best_u_d;
//             best_v_q                <= best_v_d;
//             stack_overflow_q        <= stack_overflow_d;
//             for (i = 0; i < STACK_DEPTH; i++)
//                 stack_q[i] <= stack_d[i];
//         end
//     end

// `ifndef SYNTHESIS
//     initial begin
//         if (STACK_DEPTH < 2)
//             $error("bvh_traversal_controller: STACK_DEPTH must be >= 2");
//         if (TRIANGLE_STRIDE_BYTES <= 0)
//             $error("bvh_traversal_controller: TRIANGLE_STRIDE_BYTES must be positive");
//         if ($bits(bvh_node_t) != 256)
//             $error("bvh_traversal_controller: bvh_node_t must be 256 bits");
//     end
// `endif

// endmodule
