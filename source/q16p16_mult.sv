`default_nettype none
module q16p16_mult
    // import rtu_pkg::*;
(
    input logic clk, n_rst,

    //input interface
    input logic [31:0] operand_a,
    input logic [31:0] operand_b,
    input logic valid_i,
    output logic ready_o,

    //output interface
    output logic [31:0] product,
    output logic valid_o,
    input logic ready_i
    //consider adding overflow
);
    
    //stall logic
    logic stall;
    assign stall = !ready_i && valid_o; //not optimal, but for now stall entire pipe when downstream not ready

    //input register and logic
    assign ready_o = !stall;
    logic [31:0] a_reg, b_reg;
    logic valid_i_reg; //0 if this is a buble
    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            a_reg <= '0;
            b_reg <= '0;
            valid_i_reg <= '0;
        end else if (!stall) begin
            if (valid_i) begin //saves power
                a_reg <= operand_a;
                b_reg <= operand_b;
            end
            valid_i_reg <= valid_i;
        end
    end

    //integer multiply
    logic [63:0] product_unshifted;
    assign product_unshifted = {32'b0, a_reg} * {32'b0, b_reg};

    //right shift
    logic [31:0] product_next;
    assign product_next = product_unshifted >> 16;

    //output register
    always_ff @(posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            product <= '0;
            valid_o <= '0;
        end else if (!stall) begin
            if (valid_i_reg) begin
                product <= product_next;
            end
            valid_o <= valid_i_reg;
        end
    end

endmodule