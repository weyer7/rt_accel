`timescale 10ns/10ps
`include "rtu_pkg.svh"

module q16p16_aabb_intersect_tb;

    logic clk = 0, n_rst = 0;

    //interface signals
    aabb_request_t request;
    logic          valid_i;
    logic          ready_o;

    aabb_result_t  result;
    logic          valid_o;
    logic          ready_i;

    q16p16_aabb_intersect u_dut (.*);

    always #5 clk = ~clk;

    //convert real to q16.16 inline
    function automatic logic [31:0] q16p16(input real val);
        integer tmp;
        tmp = $rtoi(val * 65536.0);
        return tmp[31:0];
    endfunction

    //q16.16 fixed-point multiplier helper
    function automatic logic [31:0] q16p16_mult(input logic [31:0] a, input logic [31:0] b);
        logic signed [63:0] product;
        product = $signed(a) *$signed(b);
        return product >>> 16;
    endfunction

    //3-axis helper functions
    function automatic logic [31:0] max3(input logic [31:0] a, input logic [31:0] b, input logic [31:0] c);
        logic [31:0] m;
        m = ($signed(a) >$signed(b)) ? a : b;
        return ($signed(m) >$signed(c)) ? m : c;
    endfunction

    function automatic logic [31:0] min3(input logic [31:0] a, input logic [31:0] b, input logic [31:0] c);
        logic [31:0] m;
        m = ($signed(a) <$signed(b)) ? a : b;
        return ($signed(m) <$signed(c)) ? m : c;
    endfunction

    //scoreboard queues (matching the working reference model pattern)
    logic [7:0]  exp_context_id_q[$];
    logic        exp_hit_q[$];
    logic [31:0] exp_tnear_q[$];
    logic [31:0] exp_tfar_q[$];

    //transaction task
    task automatic send_transaction(
        input real ax, input real ay, input real az, 
        input real bx, input real by, input real bz, 
        input real ox, input real oy, input real oz, 
        input real idx, input real idy, input real idz,
        input real tmin, input real tmax,            
        input logic [7:0] ctx_id,
        input logic valid = 1
    );
        logic [31:0] cax, cay, caz, cbx, cby, cbz;
        logic [31:0] rox, roy, roz, ridx, ridy, ridz;
        logic [31:0] rtmin, rtmax;
        
        logic [31:0] tx_a, tx_b, tmin_x, tmax_x;
        logic [31:0] ty_a, ty_b, tmin_y, tmax_y;
        logic [31:0] tz_a, tz_b, tmin_z, tmax_z;
        logic [31:0] tnear_val, tfar_val;
        logic [31:0] effective_tnear, effective_tfar;
        logic        expected_hit;

        begin
            cax  = q16p16(ax);  cay  = q16p16(ay);  caz  = q16p16(az);
            cbx  = q16p16(bx);  cby  = q16p16(by);  cbz  = q16p16(bz);
            rox  = q16p16(ox);  roy  = q16p16(oy);  roz  = q16p16(oz);
            ridx = q16p16(idx); ridy = q16p16(idy); ridz = q16p16(idz);
            rtmin = q16p16(tmin); rtmax = q16p16(tmax);

            //drive before sampling edge
            @(negedge clk);
            while (!ready_o) @(negedge clk);

            request.context_id           = ctx_id;
            request.ray.origin.x.data    = rox;
            request.ray.origin.y.data    = roy;
            request.ray.origin.z.data    = roz;
            request.ray.inv_direction.x.data = ridx;
            request.ray.inv_direction.y.data = ridy;
            request.ray.inv_direction.z.data = ridz;
            request.ray.t_min.data       = rtmin;
            request.ray.t_max.data       = rtmax;
            request.box.corner_a.x.data  = cax;
            request.box.corner_a.y.data  = cay;
            request.box.corner_a.z.data  = caz;
            request.box.corner_b.x.data  = cbx;
            request.box.corner_b.y.data  = cby;
            request.box.corner_b.z.data  = cbz;
            valid_i                      = valid;

            //calculate expected results and push immediately
            if (valid) begin
                tx_a = q16p16_mult(cax - rox, ridx);
                tx_b = q16p16_mult(cbx - rox, ridx);
                tmin_x = ($signed(tx_a) <=$signed(tx_b)) ? tx_a : tx_b;
                tmax_x = ($signed(tx_a) <=$signed(tx_b)) ? tx_b : tx_a;

                ty_a = q16p16_mult(cay - roy, ridy);
                ty_b = q16p16_mult(cby - roy, ridy);
                tmin_y = ($signed(ty_a) <=$signed(ty_b)) ? ty_a : ty_b;
                tmax_y = ($signed(ty_a) <=$signed(ty_b)) ? ty_b : ty_a;

                tz_a = q16p16_mult(caz - roz, ridz);
                tz_b = q16p16_mult(cbz - roz, ridz);
                tmin_z = ($signed(tz_a) <=$signed(tz_b)) ? tz_a : tz_b;
                tmax_z = ($signed(tz_a) <=$signed(tz_b)) ? tz_b : tz_a;

                tnear_val = max3(tmin_x, tmin_y, tmin_z);
                tfar_val  = min3(tmax_x, tmax_y, tmax_z);

                //expected hit calculation handling internal origins and segment bounds

                //if ray starts inside the box (tnear < 0), effective entry is rtmin (or 0)
                effective_tnear = ($signed(tnear_val) < $signed(rtmin)) ? rtmin : tnear_val;
                effective_tfar  = tfar_val;

                expected_hit = ($signed(effective_tnear) <= $signed(effective_tfar)) && 
                            ($signed(effective_tfar) >= $signed(rtmin)) && 
                            ($signed(effective_tnear) <= $signed(rtmax));

                exp_context_id_q.push_back(ctx_id);
                exp_hit_q.push_back(expected_hit);
                exp_tnear_q.push_back(tnear_val);
                exp_tfar_q.push_back(tfar_val);
            end

            @(posedge clk);
            #4;
            valid_i = 0;
        end
    endtask

    //automated output checker & monitor
    always @(posedge clk) begin
        logic [7:0]  exp_ctx;
        logic        exp_hit;
        logic [31:0] exp_tnear;
        logic [31:0] exp_tfar;

        if (n_rst && valid_o && ready_i) begin
            if (exp_context_id_q.size() == 0) begin
                $display("ERROR: DUT produced an output with an empty scoreboard!");
                $display("  Got: ctx=%0d, hit=%b, tnear=%h, tfar=%h", 
                         result.context_id, result.hit, result.t_near.data, result.t_far.data);
            end

            exp_ctx   = exp_context_id_q.pop_front();
            exp_hit   = exp_hit_q.pop_front();
            exp_tnear = exp_tnear_q.pop_front();
            exp_tfar  = exp_tfar_q.pop_front();

            if (result.context_id !== exp_ctx ||
                result.hit        !== exp_hit ||
                result.t_near.data !== exp_tnear ||
                result.t_far.data  !== exp_tfar) begin

                $display("ERROR Mismatch!");
                $display("  Expected: ctx=%0d, hit=%b, tnear=%h, tfar=%h", 
                         exp_ctx, exp_hit, exp_tnear, exp_tfar);
                $display("  Got:      ctx=%0d, hit=%b, tnear=%h, tfar=%h", 
                         result.context_id, result.hit, result.t_near.data, result.t_far.data);
                //$fatal;
            end
            else begin
                $display("PASS: ctx=%0d hit=%b tnear=%h tfar=%h", 
                         result.context_id, result.hit, result.t_near.data, result.t_far.data);
            end
        end
    end

    initial begin
        $dumpfile("waves/q16p16_aabb_intersect.vcd");
        $dumpvars(0, q16p16_aabb_intersect_tb);

        //reset sequence
        valid_i = 0; ready_i = 0;
        request = '0;

        repeat (3) @(negedge clk);
        n_rst = 1;
        ready_i = 1;
        @(negedge clk);

        // 1. Basic Hit Box
        send_transaction(1.0, 1.0, 1.0,  3.0, 3.0, 3.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h00, 1);

        // 2. Miss Box (Behind ray range)
        send_transaction(-3.0, -3.0, -3.0,  -1.0, -1.0, -1.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h01, 1);

        // 3. Pipeline Filling
        send_transaction(2.0, 2.0, 2.0,  5.0, 5.0, 5.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h02, 1);
        send_transaction(0.5, 0.5, 0.5,  2.0, 2.0, 2.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h03, 1);

        // 4. Stall Test
        @(negedge clk);
        ready_i = 0;
        repeat (5) @(negedge clk);
        ready_i = 1;
        repeat (5) @(negedge clk);

        // 5. Bubble Test
        send_transaction(1.0, 1.0, 1.0,  3.0, 3.0, 3.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'hF0, 0);

        // 6. Ray starts INSIDE the box
        // Box: [0,0,0] to [4,4,4], Ray Origin: [2,2,2], Dir: [1,1,1] (inv: 1,1,1)
        send_transaction(0.0, 0.0, 0.0,  4.0, 4.0, 4.0,  2.0, 2.0, 2.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h04, 1);

        // 7. Ray misses box completely (passing to the side)
        // Box: [1,1,1] to [3,3,3], Ray Origin: [0,5,0], Dir: [1,0,1] (inv: 1,1,1)
        send_transaction(1.0, 1.0, 1.0,  3.0, 3.0, 3.0,  0.0, 5.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h05, 1);

        // 8. Negative coordinate box and ray hit
        // Box: [-3,-3,-3] to [-1,-1,-1], Ray Origin: [-5,-5,-5], Inv: [1,1,1]
        send_transaction(-3.0, -3.0, -3.0,  -1.0, -1.0, -1.0,  -5.0, -5.0, -5.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h06, 1);

        // 9. Miss due to t_max range restriction (Box is too far away)
        // Box: [5,5,5] to [8,8,8], Ray Origin: [0,0,0], tmax = 2.0 (Box starts at t=5)
        send_transaction(5.0, 5.0, 5.0,  8.0, 8.0, 8.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 2.0,  8'h07, 1);

        // 10. Miss due to t_min range restriction (Box is too close / behind t_min)
        // Box: [1,1,1] to [3,3,3], Ray Origin: [0,0,0], tmin = 5.0
        send_transaction(1.0, 1.0, 1.0,  3.0, 3.0, 3.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  5.0, 10.0, 8'h08, 1);

        // 11. Ray traveling along negative axis directions (Negative inverse direction)
        // Box: [-3,-3,-3] to [-1,-1,-1], Ray Origin: [0,0,0], Dir: [-1,-1,-1] (inv: -1,-1,-1)
        send_transaction(-3.0, -3.0, -3.0,  -1.0, -1.0, -1.0,  0.0, 0.0, 0.0,  -1.0, -1.0, -1.0,  0.0, 10.0, 8'h09, 1);

        // 12. Grazing / Corner hit case
        // Box: [2,2,2] to [4,4,4], Ray Origin: [0,0,0], Ray passes right through corner [2,2,2]
        send_transaction(2.0, 2.0, 2.0,  4.0, 4.0, 4.0,  0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'h10, 1);

        // =========================================================================
        // EXTREME & PATHOLOGICAL STRESS TEST CASES
        // =========================================================================

        // 12. Massive Coordinates (Upper range of Q16.16 without overflow)
        // Box: [1000.0, 1000.0, 1000.0] to [2000.0, 2000.0, 2000.0]
        send_transaction(1000.0, 1000.0, 1000.0,  2000.0, 2000.0, 2000.0,  
                         0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 3000.0, 8'hC1, 1);

        // 13. Ultra-Tiny / Sub-Pixel Bounding Box (Precision limit test)
        // Box: [0.001, 0.001, 0.001] to [0.002, 0.002, 0.002], Ray through origin
        send_transaction(0.001, 0.001, 0.001,  0.002, 0.002, 0.002,  
                         0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'hC2, 1);

        // 14. Degenerate Flat Plane Box (X-min equals X-max, zero volume on X)
        // Box: [2.0, 1.0, 1.0] to [2.0, 3.0, 3.0]
        send_transaction(2.0, 1.0, 1.0,  2.0, 3.0, 3.0,  
                         0.0, 2.0, 2.0,  1.0, 1.0, 1.0,  0.0, 10.0, 8'hC3, 1);

        // 15. Ray Traveling Upwards / Negative Y-Axis Intersection
        // Box: [-1.0, -5.0, -1.0] to [1.0, -3.0, 1.0], Ray Origin: [0, 0, 0], Inv Dir: [1, -1, 1]
        send_transaction(-1.0, -5.0, -1.0,  1.0, -3.0, 1.0,  
                         0.0, 0.0, 0.0,  1.0, -1.0, 1.0,  0.0, 10.0, 8'hC4, 1);

        // 16. Astronomical t_max Bound (Ray range goes to infinity conceptually)
        // Box: [50.0, 50.0, 50.0] to [60.0, 60.0, 60.0], tmax = 32767.0 (Max Q16.16 integer part)
        send_transaction(50.0, 50.0, 50.0,  60.0, 60.0, 60.0,  
                         0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  0.0, 32767.0, 8'hC5, 1);

        // 17. Zero-Length Ray Segment (t_min == t_max)
        // Should result in a miss unless the box happens to contain that exact slice
        send_transaction(1.0, 1.0, 1.0,  3.0, 3.0, 3.0,  
                         0.0, 0.0, 0.0,  1.0, 1.0, 1.0,  2.0, 2.0, 8'hC6, 1);

        // 18. Completely Off-Screen / Orthogonal Ray
        // Box: [10, 10, 10] to [20, 20, 20], Ray Origin: [0, 0, 0], Ray moving purely in parallel direction
        send_transaction(10.0, 10.0, 10.0,  20.0, 20.0, 20.0,  
                         0.0, 0.0, 0.0,  0.0, 1.0, 1.0,  0.0, 100.0, 8'hC7, 1);

        // 19. Drain Pipeline
        repeat (35) @(negedge clk);

        $display("========================================");
        $display("q16p16_aabb_intersect testbench complete");
        $display("========================================");
        $finish;
    end

endmodule