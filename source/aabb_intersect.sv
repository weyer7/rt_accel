`default_nettype none
`include "rtu_pkg.svh"
module aabb_intersect 
    // import rtu_pkg::*;
(
    input logic clk, n_rst;

    //input interface
    input aabb_request_t request;
    input logic valid_i;
    output logic ready_o;

    //output interface
    output aabb_result_t result;
    output logic valid_o;
    input logic ready_i;
);
    //always ready for now
    assign ready_o = 1;

    //register input
    aabb_request_t request_reg;
    logic request_valid;
    always_ff @(posedge clock, negedge n_rst) begin
        if (!n_rst) begin
            request_reg <= '0;
            request_valid <= '0;
        end else begin
            request_reg <= request;
            request_valid <= valid_i;
        end
    end

    

endmodule