// `default_nettype none

// module aabb_intersect 
//     import rtu_pkg::*;
// (
//     input logic clk, n_rst;

//     //input interface
//     input aabb_request_t request;
//     input logic valid_i;
//     output logic ready_o;

//     //output interface
//     output aabb_result_t result;
//     output logic valid_o;
//     input logic ready_i;
// );
//     //always ready for now
//     assign ready_o = 1;

//     //register input
//     aabb_request_t request_reg;
//     logic request_valid;
//     always_ff @(posedge clock, negedge n_rst) begin
//         if (!n_rst) begin
//             request_reg <= '0;
//             request_valid <= '0;
//         end else begin
//             request_reg <= request;
//             request_valid <= valid_i;
//         end
//     end

//     //calculate x tmin and tmax
//     fp32_t inv_direction_x;
//     assign inv_direction_x = request.ray.inv.direction.x;
//     fp32_t t0_x, t1_x;
//     fp32_sub(
//         .*,
//         .operand_a(request.aabb.corner_a.y), .operand_b(aabb_request.ray.origin.y), .sum(t0_x),
//         .valid_i(), .ready_o(),
//         .valid_o(), .ready_i()
//     );

// endmodule