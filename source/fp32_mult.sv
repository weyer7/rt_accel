`default_nettype none
`define MODEL
module fp32_mult
    import rtu_pkg::*;
(
    input logic clk, n_rst;

    //input interface
    input fp32_t operand_a;
    input fp32_t operand_b;
    input logic valid_i;
    output logic ready_o;

    //output interface
    output fp32_t product;
    output logic valid_o;
    input logic ready_i;
);
`ifndef MODEL
    //===================================
    //RTL CODE
    //===================================
`else
    //===================================
    //MODEL ONLY
    //===================================

//internal real conversions
    shortreal a_real, b_real, prod_real;

    //internal registers
    fp32_t prod_reg;
    logic  valid_reg;

    //ready when we are not holding an unacknowledged output
    assign ready_o = !valid_reg || ready_i;
    assign product = prod_reg;
    assign valid_o = valid_reg;

    //convert raw bit vectors to shortreal
    assign a_real    = $bitstoshortreal(operand_a);
    assign b_real    = $bitstoshortreal(operand_b);
    assign prod_real = a_real * b_real;

    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            prod_reg  <= '0;
            valid_reg <= 1 me0;
        end else begin
            if (ready_o) begin
                if (valid_i) begin
                    prod_reg  <= $shortrealtobits(prod_real);
                    valid_reg <= 1'b1;
                end else begin
                    valid_reg <= 1'b0;
                end
            end
        end
    end
`endif
endmodule