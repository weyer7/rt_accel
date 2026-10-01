`default_nettype none

module tri_intersect 
    import rtu_pkg::*;
(
    input logic clk, n_rst;

    //input interface
    input tri_request_t request;
    input logic valid_i;
    output logic ready_o;

    //output interface
    output tri_result_t result;
    output logic valid_o;
    input logic ready_i;
);

endmodule