module fir_baseline #(
`include "fir_params_baseline.svh"
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [IN_W-1:0]       x_in,
    output logic signed [OUT_W-1:0]      y_out
);

// Full coefficient set for the straight baseline FIR
`include "fir_coeffs_baseline.svh"

// Delay line holds the most recent NTAPS input samples.
// Sample 0 is newest, higher indices are older samples.
logic signed [IN_W-1:0]  x_delay [0:NTAPS-1];

// acc_c        = raw multiply-accumulate result
// acc_round_c  = rounded value before shifting back to output format
// y_ext_c      = shifted result in extended width before saturation
// y_c          = final saturated output in OUT_W bits
logic signed [ACC_W-1:0] acc_c;
logic signed [ACC_W-1:0] acc_round_c;
logic signed [ACC_W-1:0] y_ext_c;
logic signed [OUT_W-1:0] y_c;

integer i;

// Saturation limits after shifting into output format
localparam logic signed [ACC_W-1:0] OUT_MAX_EXT = (1 <<< (OUT_W-1)) - 1;
localparam logic signed [ACC_W-1:0] OUT_MIN_EXT = -(1 <<< (OUT_W-1));

// Delay line update:
// shift old samples down one position and load the new sample at index 0
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < NTAPS; i = i + 1) begin
            x_delay[i] <= '0;
        end
    end else begin
        x_delay[0] <= x_in;
        for (i = 1; i < NTAPS; i = i + 1) begin
            x_delay[i] <= x_delay[i-1];
        end
    end
end

// Straight direct-form FIR:
// multiply each delayed sample by its tap and add everything together
always_comb begin
    acc_c = '0;
    for (i = 0; i < NTAPS; i = i + 1) begin
        acc_c = acc_c + x_delay[i] * COEFFS[i];
    end
end

// Convert the accumulator back to output Q format.
// First do rounding, then arithmetic shift, then saturate.
always_comb begin
    if (SHIFT_BITS > 0) begin
        if (acc_c >= 0)
            acc_round_c = acc_c + (1 <<< (SHIFT_BITS-1));
        else
            acc_round_c = acc_c - (1 <<< (SHIFT_BITS-1));
        y_ext_c = acc_round_c >>> SHIFT_BITS;
    end else begin
        acc_round_c = acc_c;
        y_ext_c = acc_c;
    end

    if (y_ext_c > OUT_MAX_EXT)
        y_c = OUT_MAX_EXT[OUT_W-1:0];
    else if (y_ext_c < OUT_MIN_EXT)
        y_c = OUT_MIN_EXT[OUT_W-1:0];
    else
        y_c = y_ext_c[OUT_W-1:0];
end

// Register the output so timing is measured to a clean endpoint
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        y_out <= '0;
    else
        y_out <= y_c;
end

endmodule
