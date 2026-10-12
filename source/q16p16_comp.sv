`default_nettype none
`include "rtu_pkg.svh"
module q16p16_comp (
    input logic clk, n_rst,

    //input interface
    input logic [31:0] operand_a,
    input logic [31:0] operand_b,
    input logic valid_i,
    output logic ready_o,

    //output interface
    output logic a_gt_b, a_lt_b,
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

    //integer compare
    logic a_gt_b_next, a_lt_b_next;
    assign a_gt_b_next = $signed(a_reg) > $signed(b_reg) ? 1 : 0;
    assign a_lt_b_next = $signed(a_reg) < $signed(b_reg) ? 1 : 0;

    //output register
    always_ff @(posedge clk, negedge n_rst) begin
        if(!n_rst) begin
            a_gt_b <= 0;
            a_lt_b <= 0;
            valid_o <= '0;
        end else if (!stall) begin
            if (valid_i_reg) begin
                a_gt_b <= a_gt_b_next;
                a_lt_b <= a_lt_b_next;
            end
            valid_o <= valid_i_reg;
        end
    end

endmodule