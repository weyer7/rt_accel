`default_nettype none
`ifdef FP
`define MODEL
module fp32_add
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
`ifndef MODEL
    //===================================
    //RTL CODE
    //===================================

    //===================================
    //STAGE 1
    //===================================
    logic [23:0] mantissa_a, mantissa_b;
    logic [7:0] delta_e;

    assign mantissa_a = !operand_a.exponent ? {1'b0, operand_a.mantissa} : {1'b1, operand_a.mantissa};
    assign mantissa_b = !operand_b.exponent ? {1'b0, operand_b.mantissa} : {1'b1, operand_b.mantissa};
    assign delta_e = operand_a.exponent - operand_b.exponent;

    //===================================
    //STAGE 2
    //===================================
    logic a_larger;
    always_comb begin
        if (operand_a.exponent == operand_b.exponent) {

        }
    end
`else
    //===================================
    //MODEL ONLY
    //===================================

    //internal real conversions
    shortreal a_real, b_real, sum_real;
    
    //internal registers
    fp32_t sum_reg;
    logic  valid_reg;

    //ready when we are not holding an unacknowledged output
    assign ready_o = !valid_reg || ready_i;
    assign sum     = sum_reg;
    assign valid_o = valid_reg;

    //convert raw bit vectors to shortreal (IEEE 754 float)
    assign a_real = $bitstoshortreal(operand_a);
    assign b_real = $bitstoshortreal(operand_b);
    assign sum_real = a_real + b_real;

    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            sum_reg   <= '0;
            valid_reg <= 1'b0;
        end else begin
            //handshake logic
            if (ready_o) begin
                if (valid_i) begin
                    sum_reg   <= $shortrealtobits(sum_real);
                    valid_reg <= 1'b1;
                end else begin
                    valid_reg <= 1'b0;
                end
            end
        end
    end
`endif
endmodule
`endif