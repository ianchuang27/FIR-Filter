module fir_parallel_l2 #(
`include "fir_params_baseline.svh"
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [IN_W-1:0]       x_in,
    output logic signed [OUT_W-1:0]      y_out
);

// L=2 polyphase coefficient sets:
// phase 0 = even taps, phase 1 = odd taps
`include "fir_l2_phase0.svh"
`include "fir_l2_phase1.svh"

logic signed [IN_W-1:0]  x_delay [0:NTAPS-1];

// Splitting each phase into two smaller sums first
// That shortens the longest add chain a little compared to one long branch sum.
logic signed [ACC_W-1:0] a0_c, a1_c, b0_c, b1_c;
logic signed [ACC_W-1:0] br0_c, br1_c, acc_c, acc_round_c, y_ext_c;
logic signed [OUT_W-1:0] y_c;

integer i;

// Midpoints for the two L=2 branches
localparam int P0M = L2P0_TAPS/2;
localparam int P1M = L2P1_TAPS/2;

localparam logic signed [ACC_W-1:0] OUT_MAX_EXT = (1 <<< (OUT_W-1)) - 1;
localparam logic signed [ACC_W-1:0] OUT_MIN_EXT = -(1 <<< (OUT_W-1));

// Same delay line as the baseline version
always_ff @(posedge clk) begin
    x_delay[0] <= x_in;
    for (i = 1; i < NTAPS; i = i + 1)
        x_delay[i] <= x_delay[i-1];
end

always_comb begin
    a0_c = '0; a1_c = '0;
    b0_c = '0; b1_c = '0;

    // Even-index branch
    for (i = 0; i < P0M; i = i + 1)
        a0_c = a0_c + x_delay[2*i] * COEFFS_L2_P0[i];
    for (i = P0M; i < L2P0_TAPS; i = i + 1)
        a1_c = a1_c + x_delay[2*i] * COEFFS_L2_P0[i];

    // Odd-index branch
    for (i = 0; i < P1M; i = i + 1)
        b0_c = b0_c + x_delay[2*i+1] * COEFFS_L2_P1[i];
    for (i = P1M; i < L2P1_TAPS; i = i + 1)
        b1_c = b1_c + x_delay[2*i+1] * COEFFS_L2_P1[i];

    // Combining the two local sums in each branch, then combine branches
    br0_c = a0_c + a1_c;
    br1_c = b0_c + b1_c;
    acc_c = br0_c + br1_c;

    // Round and shift back to output width
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

    // Final saturation
    if (y_ext_c > OUT_MAX_EXT)
        y_c = OUT_MAX_EXT[OUT_W-1:0];
    else if (y_ext_c < OUT_MIN_EXT)
        y_c = OUT_MIN_EXT[OUT_W-1:0];
    else
        y_c = y_ext_c[OUT_W-1:0];
end

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        y_out <= '0;
    else
        y_out <= y_c;
end

endmodule
