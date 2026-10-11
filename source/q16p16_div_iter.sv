`default_nettype none

module q16p16_div_iter (
    input  logic        clk,
    input  logic        n_rst,

    // Pipeline control
    input  logic        stall,

    // Transaction
    input  logic        valid_i,
    input  logic [31:0] divisor_i,
    input  logic [32:0] remainder_i,
    input  logic [31:0] quotient_i,
    input  logic        div_zero_i,

    output logic        valid_o,
    output logic [31:0] divisor_o,
    output logic [32:0] remainder_o,
    output logic [31:0] quotient_o,
    output logic        div_zero_o
);

    // ------------------------------------------------------------------------
    // One fixed-dividend division iteration.
    //
    // We are calculating:
    //
    //       2^32 / divisor
    //
    // by generating the 32 fractional quotient bits of:
    //
    //       1 / divisor
    //
    // The incoming remainder is always < divisor for a nonzero divisor.
    // Therefore:
    //
    //       2 * remainder < 2 * divisor
    //
    // and a single subtract is sufficient.
    // ------------------------------------------------------------------------

    logic [33:0] remainder_shifted;
    logic [32:0] remainder_next;
    logic        quotient_bit;

    always_comb begin
        remainder_shifted = {1'b0, remainder_i} << 1;

        if (remainder_shifted >= {2'b00, divisor_i}) begin
            remainder_next = remainder_shifted - {2'b00, divisor_i};
            quotient_bit    = 1'b1;
        end
        else begin
            remainder_next = remainder_shifted[32:0];
            quotient_bit    = 1'b0;
        end

        //division by zero is handled separately. Keeping this datapath
        //deterministic makes the pipeline easy to reason about
        if (div_zero_i) begin
            remainder_next = '0;
            quotient_bit   = 1'b1;
        end
    end

    //registered output
    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            valid_o     <= 1'b0;
            divisor_o   <= '0;
            remainder_o <= '0;
            quotient_o  <= '0;
            div_zero_o  <= 1'b0;
        end
        else if (!stall) begin
            valid_o     <= valid_i;
            if (valid_i) begin
                divisor_o   <= divisor_i;
                remainder_o <= remainder_next;
                quotient_o  <= {quotient_i[30:0], quotient_bit};
                div_zero_o  <= div_zero_i;
            end
        end
    end

endmodule

`default_nettype wire