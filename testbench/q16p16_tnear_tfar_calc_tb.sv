`timescale 10ns/10ps

module q16p16_tnear_tfar_calc_tb;
    logic clk = 0, n_rst = 0;

    // Interface signals
    logic [31:0] request_tmax_i, request_tmin_i;
    logic [31:0] tmin_x, tmax_x;
    logic [31:0] tmin_y, tmax_y;
    logic [31:0] tmin_z, tmax_z;
    logic        valid_i, ready_o;

    logic [31:0] request_tmax_o, request_tmin_o;
    logic [31:0] tnear_o, tfar_o;
    logic        valid_o, ready_i;

    q16p16_tnear_tfar_calc tnear_tfar_calc (.*);

    always #5 clk = ~clk;

    //convert real to q16.16 inline
    function automatic logic [31:0] q16p16(input real val);
        return $rtoi(val * 65536.0);
    endfunction

    //helper functions for expected 3-axis min/max calculation (signed fixed-point)
    function automatic logic [31:0] max3(input logic [31:0] a, b, c);
        logic [31:0] m = ($signed(a) > $signed(b)) ? a : b;
        return ($signed(m) > $signed(c)) ? m : c;
    endfunction

    function automatic logic [31:0] min3(input logic [31:0] a, b, c);
        logic [31:0] m = ($signed(a) < $signed(b)) ? a : b;
        return ($signed(m) < $signed(c)) ? m : c;
    endfunction

    //scoreboard queues
    logic [31:0] exp_tnear_q[$];
    logic [31:0] exp_tfar_q[$];
    logic [31:0] exp_req_min_q[$];
    logic [31:0] exp_req_max_q[$];

    task automatic send_transaction(
        input real x_min, input real x_max,
        input real y_min, input real y_max,
        input real z_min, input real z_max,
        input logic [31:0] req_min,
        input logic [31:0] req_max,
        input logic        valid = 1
    );
        logic [31:0] fx_min, fx_max, fy_min, fy_max, fz_min, fz_max;
        logic [31:0] exp_tnear_val, exp_tfar_val;

        begin
            fx_min = q16p16(x_min); fx_max = q16p16(x_max);
            fy_min = q16p16(y_min); fy_max = q16p16(y_max);
            fz_min = q16p16(z_min); fz_max = q16p16(z_max);

            //drive before sampling edge
            @(negedge clk);
            while (!ready_o) @(negedge clk);

            tmin_x         = fx_min;
            tmax_x         = fx_max;
            tmin_y         = fy_min;
            tmax_y         = fy_max;
            tmin_z         = fz_min;
            tmax_z         = fz_max;
            request_tmin_i = req_min;
            request_tmax_i = req_max;
            valid_i        = valid;

            //calculate expected results: tnear = max(tmin_xyz), tfar = min(tmax_xyz)
            if (valid) begin
                exp_tnear_val = max3(fx_min, fy_min, fz_min);
                exp_tfar_val  = min3(fx_max, fy_max, fz_max);

                exp_tnear_q.push_back(exp_tnear_val);
                exp_tfar_q.push_back(exp_tfar_val);
                exp_req_min_q.push_back(req_min);
                exp_req_max_q.push_back(req_max);
            end

            @(posedge clk);
            #4;
            valid_i = 0;
        end
    endtask

    always @(posedge clk) begin
        logic [31:0] exp_tnear;
        logic [31:0] exp_tfar;
        logic [31:0] exp_rmin;
        logic [31:0] exp_rmax;

        if (n_rst && valid_o && ready_i) begin
            if (exp_tnear_q.size() == 0) begin
                $display("ERROR: DUT produced an output with an empty scoreboard!");
                $display("  Got: tnear=%h, tfar=%h, req_min=%h, req_max=%h", 
                         tnear_o, tfar_o, request_tmin_o, request_tmax_o);
            end

            exp_tnear = exp_tnear_q.pop_front();
            exp_tfar  = exp_tfar_q.pop_front();
            exp_rmin  = exp_req_min_q.pop_front();
            exp_rmax  = exp_req_max_q.pop_front();

            if (tnear_o !== exp_tnear ||
                tfar_o  !== exp_tfar  ||
                request_tmin_o !== exp_rmin ||
                request_tmax_o !== exp_rmax) begin

                $display("ERROR Mismatch!");
                $display("  Expected: tnear=%h, tfar=%h, req_min=%h, req_max=%h", 
                         exp_tnear, exp_tfar, exp_rmin, exp_rmax);
                $display("  Got:      tnear=%h, tfar=%h, req_min=%h, req_max=%h", 
                         tnear_o, tfar_o, request_tmin_o, request_tmax_o);
            end
            else begin
                $display("PASS: tnear=%h tfar=%h request_tmin=%h request_tmax=%h", 
                         tnear_o, tfar_o, request_tmin_o, request_tmax_o);
            end
        end
    end

    initial begin
        $dumpfile("waves/q16p16_tnear_tfar_calc.vcd");
        $dumpvars(0, q16p16_tnear_tfar_calc_tb);

        //reset sequence
        valid_i = 0; ready_i = 0;
        request_tmax_i = '0; request_tmin_i = '0;
        tmin_x = '0; tmax_x = '0;
        tmin_y = '0; tmax_y = '0;
        tmin_z = '0; tmax_z = '0;

        repeat (3) @(negedge clk);
        n_rst = 1;
        ready_i = 1;
        @(negedge clk);

        // 1. Basic Test Cases (X, Y, Z intervals)
        send_transaction(1.0, 5.0, 2.0, 6.0, 0.5, 4.0, 32'hAAAA_AAAA, 32'hBBBB_BBBB);
        send_transaction(0.0, 3.0, 1.0, 4.0, 2.0, 5.0, 32'h1111_1111, 32'h2222_2222);

        // 2. Pipeline Filling
        send_transaction(1.0, 10.0, 2.0, 9.0, 3.0, 8.0, 32'h0000_0001, 32'h0000_0002);
        send_transaction(2.0, 8.0,  1.0, 7.0, 4.0, 6.0, 32'h0000_0003, 32'h0000_0004);

        // 3. Stall Test
        @(negedge clk);
        ready_i = 0;
        repeat (5) @(negedge clk);
        ready_i = 1;
        repeat (5) @(negedge clk);

        // 4. Bubbles (valid = 0)
        send_transaction(0.0, 1.0, 0.0, 1.0, 0.0, 1.0, 32'hAAAA_0001, 32'hBBBB_0001, 0);

        // 5. Drain Pipeline
        repeat (20) @(negedge clk);

        $display("========================================");
        $display("q16p16_tnear_tfar_calc testbench complete");
        $display("========================================");
        $finish;
    end

endmodule