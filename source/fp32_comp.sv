`default_nettype none
`ifdef FP
`define MODEL
module fp32_comp
    import rtu_pkg::*;
(
    input logic clk, n_rst;

    //input interface
    input fp32_t operand_a;
    input fp32_t operand_b;
    input logic valid_i;
    output logic ready_o;

    //output interface
    logic a_gt_b, a_lt_b;
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
    shortreal a_real, b_real;

    //internal output registers
    logic gt_reg, lt_reg, eq_reg;
    logic valid_reg;

    //handshake logic
    assign ready_o = !valid_reg || ready_i;
    assign a_gt_b  = gt_reg;
    assign a_lt_b  = lt_reg;
    assign valid_o = valid_reg;

    //convert IEEE-754 bit-pattern vectors to SystemVerilog shortreal
    assign a_real = $bitstoshortreal(operand_a);
    assign b_real = $bitstoshortreal(operand_b);

    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            gt_reg    <= 1'b0;
            lt_reg    <= 1'b0;
            valid_reg <= 1'b0;
        end else begin
            if (ready_o) begin
                if (valid_i) begin
                    gt_reg    <= (a_real > b_real);
                    lt_reg    <= (a_real < b_real);
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