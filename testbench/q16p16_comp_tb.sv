`timescale 10ns/10ps
// `include "rtu_pkg.svh"

module q16p16_comp_tb;
    // import rtu_pkg::*;

    logic clk, n_rst;

    //input interface
    logic [31:0] operand_a;
    logic [31:0] operand_b;
    logic valid_i;
    logic ready_o;

    //output interface
    logic a_gt_b, a_lt_b;
    logic valid_o;
    logic ready_i;

    //expected
    logic a_gt_b_exp, a_lt_b_exp;
    logic valid_o_exp;
    logic ready_o_exp;

    q16p16_comp comper (.*);

    always #5 clk = ~clk;

    task reset_dut();
        begin
            @(negedge clk)
            n_rst = 0;
            #10
            n_rst = 1;
        end
    endtask

    task setup_comp(logic[31:0] a, logic[31:0] b, valid);
        begin
            @(negedge clk);
            valid_i = valid;
            operand_a = a;
            operand_b = b;
            wait(ready_o);
        end
    endtask

    initial begin
        $dumpfile("waves/q16p16_comp.vcd");
        $dumpvars(0, q16p16_comp_tb);
    end

    initial begin
        clk = 0;
        n_rst = 1;
        operand_a = '0;
        operand_b = '0;
        valid_i = '0;
        ready_i = '0;
        #5;

        //reset
        reset_dut();

        //fill pipe
        ready_i = 1;
        setup_comp(1, 2, 1);
        setup_comp(5, 3, 1);
        setup_comp(3, 1, 1);
        setup_comp(3, 2, 1);
        //stall for a bit
        @(negedge clk);
        ready_i = 0;
        repeat(3) @(negedge clk);
        ready_i = 1;
        repeat(3) @(negedge clk);

        //pass numbers while invalid
        setup_comp(1, 1, 0);
        setup_comp(5, 5, 0);
        setup_comp(2, 3, 0);
        //pass a valid number
        setup_comp(1, 1, 1);
        //back to invalid
        setup_comp(3, 3, 0);

        #20
        $finish;
    end

endmodule
