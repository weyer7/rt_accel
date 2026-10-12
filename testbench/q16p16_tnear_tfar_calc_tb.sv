`timescale 10ns/10ps
module q16p16_tnear_tfar_calc_tb;
    logic clk = 0, n_rst = 0;

    //interface signals
    logic [31:0] request_tmax_i, request_tmin_i;
    logic [31:0] corner_a, corner_b, ray_origin, inv_dir;
    logic        valid_i, ready_o;

    logic [31:0] request_tmax_o, request_tmin_o;
    logic [31:0] tmin_o, tmax_o;
    logic        valid_o, ready_i;

    q16p16_tnear_tfar_calc tnear_tfar_calc (.*);

    always #5 clk = ~clk;

    //convert real to q16.16 inline
    function automatic logic [31:0] q16p16(input real val);
        return $rtoi(val * 65536.0);
    endfunction

    //q16.16 fixed-point multiplier helper for expected model
    function automatic logic [31:0] q16p16_mult(input logic [31:0] a, input logic [31:0] b);
        logic signed [63:0] product;
        product = $signed(a) * $signed(b);
        return product >>> 16;
    endfunction

    //parallel queues for scoreboard (fully supported by iverilog)
    logic [31:0] exp_tmin_q[$];
    logic [31:0] exp_tmax_q[$];
    logic [31:0] exp_req_min_q[$];
    logic [31:0] exp_req_max_q[$];

    task automatic send_transaction(
        input real a,
        input real b,
        input real origin,
        input real inv,
        input logic [31:0] req_min,
        input logic [31:0] req_max,
        input logic        valid = 1
    );
        logic [31:0] a_fixed, b_fixed, orig_fixed, inv_fixed;
        logic [31:0] t_a, t_b;
        logic [31:0] exp_tmin_val, exp_tmax_val;

        begin
            a_fixed    = q16p16(a);
            b_fixed    = q16p16(b);
            orig_fixed = q16p16(origin);
            inv_fixed  = q16p16(inv);

            //drive before the sampling edge.
            @(negedge clk);

            while (!ready_o) @(negedge clk);

            corner_a       = a_fixed;
            corner_b       = b_fixed;
            ray_origin     = orig_fixed;
            inv_dir        = inv_fixed;
            request_tmin_i = req_min;
            request_tmax_i = req_max;
            valid_i        = valid;

            //calculate expected result before the DUT samples it.
            if (valid) begin
                t_a = q16p16_mult(a_fixed - orig_fixed, inv_fixed);
                t_b = q16p16_mult(b_fixed - orig_fixed, inv_fixed);

                if ($signed(t_a) <= $signed(t_b)) begin
                    exp_tmin_val = t_a;
                    exp_tmax_val = t_b;
                end
                else begin
                    exp_tmin_val = t_b;
                    exp_tmax_val = t_a;
                end

                exp_tmin_q.push_back(exp_tmin_val);
                exp_tmax_q.push_back(exp_tmax_val);
                exp_req_min_q.push_back(req_min);
                exp_req_max_q.push_back(req_max);
            end

            //the DUT samples this transaction at the next posedge.
            @(posedge clk);
            #4
            valid_i = 0;
        end
    endtask

    always @(posedge clk) begin
        logic [31:0] exp_tmin;
        logic [31:0] exp_tmax;
        logic [31:0] exp_rmin;
        logic [31:0] exp_rmax;

        if (n_rst && valid_o && ready_i) begin

            if (exp_tmin_q.size() == 0) begin
                $display("ERROR: DUT produced an output with an empty scoreboard!");
                $display(
                    "  Got: tmin=%h, tmax=%h, req_min=%h, req_max=%h",
                    tmin_o,
                    tmax_o,
                    request_tmin_o,
                    request_tmax_o
                );
                //$fatal;
            end

            exp_tmin = exp_tmin_q.pop_front();
            exp_tmax = exp_tmax_q.pop_front();
            exp_rmin = exp_req_min_q.pop_front();
            exp_rmax = exp_req_max_q.pop_front();

            if (tmin_o !== exp_tmin ||
                tmax_o !== exp_tmax ||
                request_tmin_o !== exp_rmin ||
                request_tmax_o !== exp_rmax) begin

                $display("ERROR Mismatch!");
                $display(
                    "  Expected: tmin=%h, tmax=%h, req_min=%h, req_max=%h",
                    exp_tmin, exp_tmax, exp_rmin, exp_rmax
                );
                $display(
                    "  Got:      tmin=%h, tmax=%h, req_min=%h, req_max=%h",
                    tmin_o, tmax_o, request_tmin_o, request_tmax_o
                );
                //$fatal;
            end
            else begin
                $display(
                    "PASS: tmin=%h tmax=%h request_tmin=%h request_tmax=%h",
                    tmin_o,
                    tmax_o,
                    request_tmin_o,
                    request_tmax_o
                );
            end
        end
    end

    initial begin
        $dumpfile("waves/q16p16_tnear_tfar_calc.vcd");
        $dumpvars(0, q16p16_tnear_tfar_calc_tb);

        //reset sequence
        valid_i = 0; ready_i = 0;
        request_tmax_i = '0; request_tmin_i = '0;
        corner_a = '0; corner_b = '0; ray_origin = '0; inv_dir = '0;
        
        repeat (3) @(negedge clk);
        n_rst = 1; 
        ready_i = 1;
        @(negedge clk);

        // 1. Basic Cases
        send_transaction(1.0, 2.0, 0.0, 1.0, 32'hAAAA_AAAA, 32'hBBBB_BBBB);
        send_transaction(5.0, 3.0, 0.0, 1.0, 32'h1111_1111, 32'h2222_2222);

        // 2. Negative Ray Direction
        send_transaction(1.0, 2.0, 0.0, -1.0, 32'h1234_5678, 32'h8765_4321);

        // 3. Non-zero Ray Origin
        send_transaction(4.0, 6.0, 2.0, 0.5, 32'hDEAD_BEEF, 32'hCAFE_BABE);

        // 4. Fill Pipeline
        send_transaction(1.0, 2.0, 0.0, 1.0, 32'h0000_0001, 32'h0000_0002);
        send_transaction(5.0, 3.0, 0.0, 1.0, 32'h0000_0003, 32'h0000_0004);
        send_transaction(3.0, 1.0, 0.0, 1.0, 32'h0000_0005, 32'h0000_0006);
        send_transaction(3.0, 2.0, 0.0, 1.0, 32'h0000_0007, 32'h0000_0008);

        // 5. Stall Test
        @(negedge clk);
        ready_i = 0;
        repeat (5) @(negedge clk);
        ready_i = 1;
        repeat (5) @(negedge clk);

        // 6. Bubbles (valid = 0 won't add to scoreboard)
        send_transaction(1.0, 1.0, 0.0, 1.0, 32'hAAAA_0001, 32'hBBBB_0001, 0);
        send_transaction(5.0, 5.0, 0.0, 1.0, 32'hAAAA_0002, 32'hBBBB_0002, 0);

        // 7. Valid transaction after bubbles
        send_transaction(7.0, 4.0, 1.0, 0.5, 32'h1234_0001, 32'h5678_0001, 1);

        // 8. Drain Pipeline
        repeat (20) @(negedge clk);

        $display("========================================");
        $display("q16p16_tnear_tfar_calc testbench complete");
        $display("========================================");
        $finish;
    end

endmodule