`default_nettype none
`ifdef FP
module fp32_sub
    import rtu_pkg::*;
(
    input logic clk, n_rst;

    //input interface
    input fp32_t operand_a;
    input fp32_t operand_b;
    input logic valid_i;
    output logic ready_o;

    //output interface
    output fp32_t sum;
    output logic valid_o;
    input logic ready_i;
);
    //invert sign of second operand
    fp32_add(.*, .operand_b({~operand_b[31], operand_b[30:0]}));
endmodule
`endif