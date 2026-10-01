`default_nettype none
`define MODEL
module fp32_inv
    import rtu_pkg::*;
(
    input logic clk, n_rst;

    //input interface
    input fp32_t divisor;
    input logic valid_i;
    output logic ready_o;

    //output interface
    output fp32_t quotient;
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
    shortreal div_real, res_real;

    //internal registers
    fp32_t quot_reg;
    logic  valid_reg;

    //ready when we are not holding an unacknowledged output
    assign ready_o  = !valid_reg || ready_i;
    assign quotient = quot_reg;
    assign valid_o  = valid_reg;

    //convert raw bit vectors to shortreal
    assign div_real = $bitstoshortreal(divisor);
    assign res_real = 1.0f / div_real;

    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            quot_reg  <= '0;
            valid_reg <= 1'b0;
        end else begin
            if (ready_o) begin
                if (valid_i) begin
                    quot_reg  <= $shortrealtobits(res_real);
                    valid_reg <= 1'b1;
                end else begin
                    valid_reg <= 1'b0;
                end
            end
        end
    end
`endif
endmodule