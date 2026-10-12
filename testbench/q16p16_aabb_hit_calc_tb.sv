`timescale 10ns/10ps

module q16p16_aabb_hit_calc_tb;
    logic clk = 0, n_rst = 0;

    //interface signals
    logic [31:0] request_tmax_i, request_tmin_i;
    logic [31:0] tnear_i, tfar_i;
    logic        valid_i, ready_o;

    logic [31:0] tnear_o, tfar_o;
    logic        hit;
    logic        valid_o, ready_i;

    q16p16_aabb_hit_calc u_dut (.*);

    always #5 clk = ~clk;

    //convert real to q16.16 inline
    function automatic logic [31:0] q16p16(input real val);
        return $rtoi(val * 65536.0);
    endfunction

    //scoreboard queues
    logic [31:0] exp_tnear_q[$];
    logic [31:0] exp_tfar_q[$];
    logic        exp_hit_q[$];

    task automatic send_transaction(
        input real req_min,
        input real req_max,
        input real tnear,
        input real tfar,
        input logic valid = 1
    );
        logic [31:0] rmin_f, rmax_f, tnear_f, tfar_f;
        logic        expected_hit;

        begin
            rmin_f  = q16p16(req_min);
            rmax_f  = q16p16(req_max);
            tnear_f = q16p16(tnear);
            tfar_f  = q16p16(tfar);

            //drive before sampling edge
            @(negedge clk);
            while (!ready_o) @(negedge clk);

            request_tmin_i = rmin_f;
            request_tmax_i = rmax_f;
            tnear_i        = tnear_f;
            tfar_i         = tfar_f;
            valid_i        = valid;

            //calculate expected results matching DUT logic
            if (valid) begin
                expected_hit = (tnear_f <= tfar_f) && (tfar_f >= rmin_f) && (tnear_f <= rmax_f);

                exp_tnear_q.push_back(tnear_f);
                exp_tfar_q.push_back(tfar_f);
                exp_hit_q.push_back(expected_hit);
            end

            @(posedge clk);
            #4;
            valid_i = 0;
        end
    endtask

    always @(posedge clk) begin
        logic [31:0] exp_tnear;
        logic [31:0] exp_tfar;
        logic        exp_hit;

        if (n_rst && valid_o && ready_i) begin
            if (exp_hit_q.size() == 0) begin
                $display("ERROR: DUT produced an output with an empty scoreboard!");
                $display("  Got: hit=%b, tnear=%h, tfar=%h", hit, tnear_o, tfar_o);
            end else begin
                exp_tnear = exp_tnear_q.pop_front();
                exp_tfar  = exp_tfar_q.pop_front();
                exp_hit   = exp_hit_q.pop_front();

                if (tnear_o !== exp_tnear ||
                    tfar_o  !== exp_tfar  ||
                    hit     !== exp_hit) begin

                    $display("ERROR Mismatch!");
                    $display("  Expected: hit=%b, tnear=%h, tfar=%h", exp_hit, exp_tnear, exp_tfar);
                    $display("  Got:      hit=%b, tnear=%h, tfar=%h", hit, tnear_o, tfar_o);
                end
                else begin
                    $display("PASS: hit=%b tnear=%h tfar=%h", hit, tnear_o, tfar_o);
                end
            end
        end
    end

    initial begin
        $dumpfile("waves/q16p16_aabb_hit_calc.vcd");
        $dumpvars(0, q16p16_aabb_hit_calc_tb);

        //reset sequence
        valid_i = 0; ready_i = 0;
        request_tmax_i = '0; request_tmin_i = '0;
        tnear_i = '0; tfar_i = '0;

        repeat (3) @(negedge clk);
        n_rst = 1;
        ready_i = 1;
        @(negedge clk);

        // 1. Basic Hit Case ([1.0, 3.0] overlaps [0.0, 5.0])
        send_transaction(0.0, 5.0, 1.0, 3.0);

        // 2. Miss Case: tnear > tfar
        send_transaction(0.0, 5.0, 3.0, 1.0);

        // 3. Miss Case: Box behind ray range
        send_transaction(2.0, 5.0, 0.5, 1.5);

        // 4. Miss Case: Box ahead of ray range
        send_transaction(0.0, 2.0, 3.0, 4.0);

        // 5. Pipeline Filling & Boundary
        send_transaction(1.0, 4.0, 1.0, 4.0);

        // 6. Stall Test
        @(negedge clk);
        ready_i = 0;
        repeat (5) @(negedge clk);
        ready_i = 1;
        repeat (5) @(negedge clk);

        // 7. Bubbles (valid = 0)
        send_transaction(0.0, 5.0, 2.0, 3.0, 0);

        // 8. Drain Pipeline
        repeat (20) @(negedge clk);

        $display("========================================");
        $display("q16p16_aabb_hit_calc testbench complete");
        $display("========================================");
        $finish;
    end

endmodule