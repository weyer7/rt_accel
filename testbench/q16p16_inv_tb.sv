`timescale 10ns/10ps
// `include "rtu_pkg.svh"

module q16p16_inv_tb;
    // import rtu_pkg::*;

    logic clk, n_rst;

    //input interface
    logic [31:0] divisor;
    logic valid_i;
    logic ready_o;

    //output interface
    logic [31:0] quotient;
    logic valid_o;
    logic ready_i;

    //expected
    logic [31:0] quotient_exp;
    logic valid_o_exp;
    logic ready_o_exp;

    q16p16_inv inv (.*);

    always #5 clk = ~clk;

    task reset_dut();
        begin
            @(negedge clk)
            n_rst = 0;
            #10
            n_rst = 1;
        end
    endtask

    task setup_inv(logic[31:0] a, valid);
        begin
            @(negedge clk);
            valid_i = valid;
            //convert to integer
            divisor = a << 16;
            wait(ready_o);
        end
    endtask

    initial begin
        $dumpfile("waves/q16p16_inv.vcd");
        $dumpvars(0, q16p16_inv_tb);
    end

    initial begin
        clk = 0;
        n_rst = 1;
        divisor = '0;
        valid_i = '0;
        ready_i = '0;
        #5;

        //reset
        reset_dut();

        //fill pipe
        ready_i = 1;
        setup_inv(1, 1);
        setup_inv(5, 1);
        setup_inv(3, 1);
        setup_inv(3, 1);
        //stall for a bit
        @(negedge clk);
        ready_i = 0;
        repeat(3) @(negedge clk);
        ready_i = 1;
        repeat(3) @(negedge clk);

        //pass numbers while invalid
        setup_inv(1, 0);
        setup_inv(5, 0);
        setup_inv(2, 0);
        //pass a valid number
        setup_inv(1, 1);
        //back to invalid
        setup_inv(3, 0);

        #1000
        $finish;
    end

endmodule
