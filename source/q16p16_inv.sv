`default_nettype none

module q16p16_inv #(
    parameter int PIPELINE_STAGES = 32
)(
    input logic clk, n_rst,

    //input interface
    input logic [31:0] divisor,
    input logic valid_i,
    output logic ready_o,

    //output interface
    output logic [31:0] quotient,
    output logic valid_o,
    input logic ready_i
    //consider adding overflow
);

    // ------------------------------------------------------------------------
    // This is a fixed 32-bit Q16.16 reciprocal
    //
    // For raw divisor D:
    //
    //              2^32
    //     Q = ----------------
    //              D
    //
    // The divider generates the 32 quotient bits using one iteration per
    // pipeline stage
    //
    // Therefore:
    //
    //     latency   = PIPELINE_STAGES
    //     throughput = 1 result / cycle
    //
    // PIPELINE_STAGES should normally be 32. It is a parameter primarily
    // so that the structure can be experimented with easily
    // ------------------------------------------------------------------------

    localparam int STAGES = PIPELINE_STAGES;

    //global pipeline stall
    logic stall;

    assign stall   = valid_o && !ready_i;
    assign ready_o = !stall;


    //pipeline state
    logic [31:0] divisor_pipe   [0:STAGES];
    logic [32:0] remainder_pipe [0:STAGES];
    logic [31:0] quotient_pipe  [0:STAGES];
    logic        div_zero_pipe  [0:STAGES];
    logic        valid_pipe     [0:STAGES];

    //input stage
    //the "dividend" is always 1, so the initial remainder is simply 1
    //this is the major simplification compared with a general divider
    always_ff @(posedge clk or negedge n_rst) begin
        if (!n_rst) begin
            divisor_pipe[0]   <= '0;
            remainder_pipe[0] <= '0;
            quotient_pipe[0]  <= '0;
            div_zero_pipe[0]  <= 1'b0;
            valid_pipe[0]     <= 1'b0;
        end
        else if (!stall) begin
            valid_pipe[0] <= valid_i;
            if (valid_i) begin
                divisor_pipe[0]   <= divisor;
                remainder_pipe[0] <= 33'd1;
                quotient_pipe[0]  <= '0;
                div_zero_pipe[0]  <= (divisor == 32'd0);
            end
        end
    end

    //main division pipeline
    genvar i;

    generate
        for (i = 0; i < STAGES; i++) begin : gen_divider

            q16p16_div_iter u_iter (
                .clk        (clk),
                .n_rst      (n_rst),
                .stall      (stall),

                .valid_i    (valid_pipe[i]),
                .divisor_i  (divisor_pipe[i]),
                .remainder_i(remainder_pipe[i]),
                .quotient_i (quotient_pipe[i]),
                .div_zero_i (div_zero_pipe[i]),

                .valid_o    (valid_pipe[i+1]),
                .divisor_o  (divisor_pipe[i+1]),
                .remainder_o(remainder_pipe[i+1]),
                .quotient_o (quotient_pipe[i+1]),
                .div_zero_o (div_zero_pipe[i+1])
            );

        end
    endgenerate

    //output reg
    assign valid_o = valid_pipe[STAGES];
    always_comb begin
        if (div_zero_pipe[STAGES])
            quotient = 32'hFFFF_FFFF;
        else
            quotient = quotient_pipe[STAGES];
    end

endmodule

`default_nettype wire