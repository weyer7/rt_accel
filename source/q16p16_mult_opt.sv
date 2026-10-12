`default_nettype none
//specified architecture with 16 8x8 multipliers
//and tree of adders. Had Gemini write RTL (holy this is verbose)
//pipe is 11-deep but critical path is substantially reduced
module q16p16_mult_opt (
    input  logic clk,
    input  logic n_rst,

    // Input interface
    input  logic [31:0] operand_a,
    input  logic [31:0] operand_b,
    input  logic        valid_i,
    output logic        ready_o,

    // Output interface
    output logic [31:0] product,
    output logic        valid_o,
    input  logic        ready_i
);

    // =========================================================================
    // Pipeline control
    // =========================================================================

    logic stall;

    assign stall  = valid_o && !ready_i;
    assign ready_o = !stall;


    // =========================================================================
    // Stage 0
    //
    // Convert signed operands to unsigned magnitudes.
    //
    // We perform the actual multiplication unsigned, then apply the final
    // sign at the end. This allows all 16 partial products to use simple
    // unsigned 8x8 multipliers.
    // =========================================================================

    logic [31:0] a_mag_0;
    logic [31:0] b_mag_0;
    logic        sign_0;
    logic        valid_0;

    logic [31:0] a_mag_comb;
    logic [31:0] b_mag_comb;
    logic        sign_comb;

    assign sign_comb = operand_a[31] ^ operand_b[31];

    assign a_mag_comb = operand_a[31]
                       ? (~operand_a + 32'd1)
                       : operand_a;

    assign b_mag_comb = operand_b[31]
                       ? (~operand_b + 32'd1)
                       : operand_b;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            a_mag_0 <= '0;
            b_mag_0 <= '0;
            sign_0  <= 1'b0;
            valid_0 <= 1'b0;
        end else if (!stall) begin
            if (valid_i) begin
                a_mag_0 <= a_mag_comb;
                b_mag_0 <= b_mag_comb;
                sign_0  <= sign_comb;
            end

            valid_0 <= valid_i;
        end
    end


    // =========================================================================
    // Stage 1
    //
    // 16 independent 8x8 multipliers.
    //
    // A = a0 + a1*256 + a2*256^2 + a3*256^3
    // B = b0 + b1*256 + b2*256^2 + b3*256^3
    //
    // Therefore:
    //
    // A*B = c0
    //      + c1*256
    //      + c2*256^2
    //      + ...
    //      + c6*256^6
    //
    // where each cij is a sum of 8x8 products.
    // =========================================================================

    logic [7:0] a_byte [0:3];
    logic [7:0] b_byte [0:3];

    logic [15:0] pp_1 [0:15];

    logic        sign_1;
    logic        valid_1;

    assign a_byte[0] = a_mag_0[7:0];
    assign a_byte[1] = a_mag_0[15:8];
    assign a_byte[2] = a_mag_0[23:16];
    assign a_byte[3] = a_mag_0[31:24];

    assign b_byte[0] = b_mag_0[7:0];
    assign b_byte[1] = b_mag_0[15:8];
    assign b_byte[2] = b_mag_0[23:16];
    assign b_byte[3] = b_mag_0[31:24];

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            pp_1[0]  <= '0;
            pp_1[1]  <= '0;
            pp_1[2]  <= '0;
            pp_1[3]  <= '0;
            pp_1[4]  <= '0;
            pp_1[5]  <= '0;
            pp_1[6]  <= '0;
            pp_1[7]  <= '0;
            pp_1[8]  <= '0;
            pp_1[9]  <= '0;
            pp_1[10] <= '0;
            pp_1[11] <= '0;
            pp_1[12] <= '0;
            pp_1[13] <= '0;
            pp_1[14] <= '0;
            pp_1[15] <= '0;

            sign_1  <= 1'b0;
            valid_1 <= 1'b0;
        end else if (!stall) begin
            if (valid_0) begin
                pp_1[0]  <= a_byte[0] * b_byte[0];
                pp_1[1]  <= a_byte[0] * b_byte[1];
                pp_1[2]  <= a_byte[0] * b_byte[2];
                pp_1[3]  <= a_byte[0] * b_byte[3];

                pp_1[4]  <= a_byte[1] * b_byte[0];
                pp_1[5]  <= a_byte[1] * b_byte[1];
                pp_1[6]  <= a_byte[1] * b_byte[2];
                pp_1[7]  <= a_byte[1] * b_byte[3];

                pp_1[8]  <= a_byte[2] * b_byte[0];
                pp_1[9]  <= a_byte[2] * b_byte[1];
                pp_1[10] <= a_byte[2] * b_byte[2];
                pp_1[11] <= a_byte[2] * b_byte[3];

                pp_1[12] <= a_byte[3] * b_byte[0];
                pp_1[13] <= a_byte[3] * b_byte[1];
                pp_1[14] <= a_byte[3] * b_byte[2];
                pp_1[15] <= a_byte[3] * b_byte[3];
            end

            sign_1  <= sign_0;
            valid_1 <= valid_0;
        end
    end


    // =========================================================================
    // Stage 2
    //
    // First level of diagonal reduction.
    //
    // Each diagonal is:
    //
    // c0 = p00
    // c1 = p01 + p10
    // c2 = p02 + p11 + p20
    // c3 = p03 + p12 + p21 + p30
    // c4 = p13 + p22 + p31
    // c5 = p23 + p32
    // c6 = p33
    //
    // We do the multi-term diagonals using balanced pairwise additions.
    // =========================================================================

    logic [16:0] d0_2;
    logic [16:0] d1_2;

    logic [16:0] d2_a_2;
    logic [16:0] d2_b_2;

    logic [16:0] d3_a_2;
    logic [16:0] d3_b_2;

    logic [16:0] d4_a_2;
    logic [16:0] d4_b_2;

    logic [16:0] d5_2;
    logic [16:0] d6_2;

    logic sign_2;
    logic valid_2;


    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            d0_2   <= '0;
            d1_2   <= '0;

            d2_a_2 <= '0;
            d2_b_2 <= '0;

            d3_a_2 <= '0;
            d3_b_2 <= '0;

            d4_a_2 <= '0;
            d4_b_2 <= '0;

            d5_2   <= '0;
            d6_2   <= '0;

            sign_2  <= 1'b0;
            valid_2 <= 1'b0;
        end else if (!stall) begin
            if (valid_1) begin
                // c0
                d0_2 <= {1'b0, pp_1[0]};

                // c1
                d1_2 <= {1'b0, pp_1[1]}
                      + {1'b0, pp_1[4]};

                // c2 = p02 + p11 + p20
                d2_a_2 <= {1'b0, pp_1[2]}
                        + {1'b0, pp_1[5]};

                d2_b_2 <= {1'b0, pp_1[8]};

                // c3 = p03 + p12 + p21 + p30
                d3_a_2 <= {1'b0, pp_1[3]}
                        + {1'b0, pp_1[6]};

                d3_b_2 <= {1'b0, pp_1[9]}
                        + {1'b0, pp_1[12]};

                // c4 = p13 + p22 + p31
                d4_a_2 <= {1'b0, pp_1[7]}
                        + {1'b0, pp_1[10]};

                d4_b_2 <= {1'b0, pp_1[13]};

                // c5
                d5_2 <= {1'b0, pp_1[11]}
                      + {1'b0, pp_1[14]};

                // c6
                d6_2 <= {1'b0, pp_1[15]};
            end

            sign_2  <= sign_1;
            valid_2 <= valid_1;
        end
    end


    // =========================================================================
    // Stage 3
    //
    // Finish diagonal reduction.
    //
    // Maximum diagonal value is:
    //
    //     4 * (255 * 255) = 260100
    //
    // which requires only 18 bits.
    // =========================================================================

    logic [17:0] d0_3;
    logic [17:0] d1_3;
    logic [17:0] d2_3;
    logic [17:0] d3_3;
    logic [17:0] d4_3;
    logic [17:0] d5_3;
    logic [17:0] d6_3;

    logic sign_3;
    logic valid_3;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            d0_3 <= '0;
            d1_3 <= '0;
            d2_3 <= '0;
            d3_3 <= '0;
            d4_3 <= '0;
            d5_3 <= '0;
            d6_3 <= '0;

            sign_3  <= 1'b0;
            valid_3 <= 1'b0;
        end else if (!stall) begin
            if (valid_2) begin
                d0_3 <= {1'b0, d0_2};
                d1_3 <= {1'b0, d1_2};

                d2_3 <= {1'b0, d2_a_2}
                      + {1'b0, d2_b_2};

                d3_3 <= {1'b0, d3_a_2}
                      + {1'b0, d3_b_2};

                d4_3 <= {1'b0, d4_a_2}
                      + {1'b0, d4_b_2};

                d5_3 <= {1'b0, d5_2};
                d6_3 <= {1'b0, d6_2};
            end

            sign_3  <= sign_2;
            valid_3 <= valid_2;
        end
    end


    // =========================================================================
    // Carry propagation
    //
    // The diagonals are base-256 digits.
    //
    // For each stage:
    //
    //     value = coefficient + carry
    //
    //     digit  = value[7:0]
    //     carry  = value >> 8
    //
    // This is deliberately pipelined one byte at a time. Every stage only
    // contains a small ~19-bit addition.
    // =========================================================================


    // -------------------------------------------------------------------------
    // Stage 4: coefficient 0
    // -------------------------------------------------------------------------

    logic [7:0]  digit_0_4;
    logic [17:0] carry_4;

    logic [17:0] d1_4;
    logic [17:0] d2_4;
    logic [17:0] d3_4;
    logic [17:0] d4_4;
    logic [17:0] d5_4;
    logic [17:0] d6_4;

    logic sign_4;
    logic valid_4;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            digit_0_4 <= '0;
            carry_4   <= '0;

            d1_4 <= '0;
            d2_4 <= '0;
            d3_4 <= '0;
            d4_4 <= '0;
            d5_4 <= '0;
            d6_4 <= '0;

            sign_4  <= 1'b0;
            valid_4 <= 1'b0;
        end else if (!stall) begin
            if (valid_3) begin
                digit_0_4 <= d0_3[7:0];
                carry_4   <= d0_3 >> 8;

                d1_4 <= d1_3;
                d2_4 <= d2_3;
                d3_4 <= d3_3;
                d4_4 <= d4_3;
                d5_4 <= d5_3;
                d6_4 <= d6_3;
            end

            sign_4  <= sign_3;
            valid_4 <= valid_3;
        end
    end


    // -------------------------------------------------------------------------
    // Stage 5: coefficient 1
    // -------------------------------------------------------------------------

    logic [17:0] coeff_1_5;
    logic [7:0]  digit_1_5;
    logic [17:0] carry_5;

    logic [17:0] d2_5;
    logic [17:0] d3_5;
    logic [17:0] d4_5;
    logic [17:0] d5_5;
    logic [17:0] d6_5;

    logic [7:0] digit_0_5;

    logic sign_5;
    logic valid_5;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            digit_0_5 <= '0;
            digit_1_5 <= '0;
            carry_5   <= '0;

            d2_5 <= '0;
            d3_5 <= '0;
            d4_5 <= '0;
            d5_5 <= '0;
            d6_5 <= '0;

            sign_5  <= 1'b0;
            valid_5 <= 1'b0;
        end else if (!stall) begin
            if (valid_4) begin
                coeff_1_5 = d1_4 + carry_4;

                digit_0_5 <= digit_0_4;
                digit_1_5 <= coeff_1_5[7:0];
                carry_5   <= coeff_1_5 >> 8;

                d2_5 <= d2_4;
                d3_5 <= d3_4;
                d4_5 <= d4_4;
                d5_5 <= d5_4;
                d6_5 <= d6_4;
            end

            sign_5  <= sign_4;
            valid_5 <= valid_4;
        end
    end


    // -------------------------------------------------------------------------
    // Stage 6: coefficient 2
    // -------------------------------------------------------------------------

    logic [17:0] coeff_2_6;

    logic [7:0] digit_0_6;
    logic [7:0] digit_1_6;
    logic [7:0] digit_2_6;

    logic [17:0] carry_6;

    logic [17:0] d3_6;
    logic [17:0] d4_6;
    logic [17:0] d5_6;
    logic [17:0] d6_6;

    logic sign_6;
    logic valid_6;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            digit_0_6 <= '0;
            digit_1_6 <= '0;
            digit_2_6 <= '0;

            carry_6 <= '0;

            d3_6 <= '0;
            d4_6 <= '0;
            d5_6 <= '0;
            d6_6 <= '0;

            sign_6  <= 1'b0;
            valid_6 <= 1'b0;
        end else if (!stall) begin
            if (valid_5) begin
                coeff_2_6 = d2_5 + carry_5;

                digit_0_6 <= digit_0_5;
                digit_1_6 <= digit_1_5;
                digit_2_6 <= coeff_2_6[7:0];

                carry_6 <= coeff_2_6 >> 8;

                d3_6 <= d3_5;
                d4_6 <= d4_5;
                d5_6 <= d5_5;
                d6_6 <= d6_5;
            end

            sign_6  <= sign_5;
            valid_6 <= valid_5;
        end
    end


    // -------------------------------------------------------------------------
    // Stage 7: coefficient 3
    // -------------------------------------------------------------------------

    logic [17:0] coeff_3_7;

    logic [7:0] digit_0_7;
    logic [7:0] digit_1_7;
    logic [7:0] digit_2_7;
    logic [7:0] digit_3_7;

    logic [17:0] carry_7;

    logic [17:0] d4_7;
    logic [17:0] d5_7;
    logic [17:0] d6_7;

    logic sign_7;
    logic valid_7;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            digit_0_7 <= '0;
            digit_1_7 <= '0;
            digit_2_7 <= '0;
            digit_3_7 <= '0;

            carry_7 <= '0;

            d4_7 <= '0;
            d5_7 <= '0;
            d6_7 <= '0;

            sign_7  <= 1'b0;
            valid_7 <= 1'b0;
        end else if (!stall) begin
            if (valid_6) begin
                coeff_3_7 = d3_6 + carry_6;

                digit_0_7 <= digit_0_6;
                digit_1_7 <= digit_1_6;
                digit_2_7 <= digit_2_6;
                digit_3_7 <= coeff_3_7[7:0];

                carry_7 <= coeff_3_7 >> 8;

                d4_7 <= d4_6;
                d5_7 <= d5_6;
                d6_7 <= d6_6;
            end

            sign_7  <= sign_6;
            valid_7 <= valid_6;
        end
    end


    // -------------------------------------------------------------------------
    // Stage 8: coefficient 4
    // -------------------------------------------------------------------------

    logic [17:0] coeff_4_8;

    logic [7:0] digit_0_8;
    logic [7:0] digit_1_8;
    logic [7:0] digit_2_8;
    logic [7:0] digit_3_8;
    logic [7:0] digit_4_8;

    logic [17:0] carry_8;

    logic [17:0] d5_8;
    logic [17:0] d6_8;

    logic sign_8;
    logic valid_8;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            digit_0_8 <= '0;
            digit_1_8 <= '0;
            digit_2_8 <= '0;
            digit_3_8 <= '0;
            digit_4_8 <= '0;

            carry_8 <= '0;

            d5_8 <= '0;
            d6_8 <= '0;

            sign_8  <= 1'b0;
            valid_8 <= 1'b0;
        end else if (!stall) begin
            if (valid_7) begin
                coeff_4_8 = d4_7 + carry_7;

                digit_0_8 <= digit_0_7;
                digit_1_8 <= digit_1_7;
                digit_2_8 <= digit_2_7;
                digit_3_8 <= digit_3_7;
                digit_4_8 <= coeff_4_8[7:0];

                carry_8 <= coeff_4_8 >> 8;

                d5_8 <= d5_7;
                d6_8 <= d6_7;
            end

            sign_8  <= sign_7;
            valid_8 <= valid_7;
        end
    end


    // -------------------------------------------------------------------------
    // Stage 9: coefficient 5
    // -------------------------------------------------------------------------

    logic [17:0] coeff_5_9;

    logic [7:0] digit_0_9;
    logic [7:0] digit_1_9;
    logic [7:0] digit_2_9;
    logic [7:0] digit_3_9;
    logic [7:0] digit_4_9;
    logic [7:0] digit_5_9;

    logic [17:0] carry_9;

    logic [17:0] d6_9;

    logic sign_9;
    logic valid_9;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            digit_0_9 <= '0;
            digit_1_9 <= '0;
            digit_2_9 <= '0;
            digit_3_9 <= '0;
            digit_4_9 <= '0;
            digit_5_9 <= '0;

            carry_9 <= '0;
            d6_9   <= '0;

            sign_9  <= 1'b0;
            valid_9 <= 1'b0;
        end else if (!stall) begin
            if (valid_8) begin
                coeff_5_9 = d5_8 + carry_8;

                digit_0_9 <= digit_0_8;
                digit_1_9 <= digit_1_8;
                digit_2_9 <= digit_2_8;
                digit_3_9 <= digit_3_8;
                digit_4_9 <= digit_4_8;
                digit_5_9 <= coeff_5_9[7:0];

                carry_9 <= coeff_5_9 >> 8;

                d6_9 <= d6_8;
            end

            sign_9  <= sign_8;
            valid_9 <= valid_8;
        end
    end


    // -------------------------------------------------------------------------
    // Stage 10: coefficient 6 + final assembly
    //
    // At this point we have all eight base-256 digits.
    //
    // digit 7 is the final carry from coefficient 6.
    // -------------------------------------------------------------------------

    logic [17:0] coeff_6_comb;
    logic [7:0]  digit_6_comb;
    logic [7:0]  digit_7_comb;

    logic [63:0] magnitude_comb;

    assign coeff_6_comb = d6_9 + carry_9;

    assign digit_6_comb = coeff_6_comb[7:0];
    assign digit_7_comb = coeff_6_comb >> 8;

    assign magnitude_comb = {
        digit_7_comb,
        digit_6_comb,
        digit_5_9,
        digit_4_9,
        digit_3_9,
        digit_2_9,
        digit_1_9,
        digit_0_9
    };


    // =========================================================================
    // Final output register
    // =========================================================================

    logic [63:0] signed_product_comb;

    assign signed_product_comb = sign_9
                               ? (~magnitude_comb + 64'd1)
                               : magnitude_comb;

    always_ff @(posedge clk, negedge n_rst) begin
        if (!n_rst) begin
            product <= '0;
            valid_o <= 1'b0;
        end else if (!stall) begin
            if (valid_9) begin
                // 64-bit integer product -> Q16.16
                product <= signed_product_comb[47:16];
            end

            valid_o <= valid_9;
        end
    end

endmodule
