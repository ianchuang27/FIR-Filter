module fir_pipe_parallel_l3 #(
`include "fir_params_baseline.svh"
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [IN_W-1:0]       x_in,
    output logic signed [OUT_W-1:0]      y_out
);

// L=3 polyphase coefficient sets
`include "fir_l3_phase0.svh"
`include "fir_l3_phase1.svh"
`include "fir_l3_phase2.svh"

logic signed [IN_W-1:0]  x_delay [0:NTAPS-1];

// Local quarter-branch sums for each phase
logic signed [ACC_W-1:0] p00_c,p01_c,p02_c,p03_c;
logic signed [ACC_W-1:0] p10_c,p11_c,p12_c,p13_c;
logic signed [ACC_W-1:0] p20_c,p21_c,p22_c,p23_c;

// First registered reduction inside each phase branch
logic signed [ACC_W-1:0] a0_c, a1_c, b0_c, b1_c, c0_c, c1_c;
logic signed [ACC_W-1:0] a0_r, a1_r, b0_r, b1_r, c0_r, c1_r;

// Second registered reduction: one sum per phase branch
logic signed [ACC_W-1:0] br0_c, br1_c, br2_c;
logic signed [ACC_W-1:0] br0_r, br1_r, br2_r;

// Final pipelined combine across the 3 branches
logic signed [ACC_W-1:0] pair01_c, pair01_r;
logic signed [ACC_W-1:0] acc_c, acc_r;

// Output scaling/saturation
logic signed [ACC_W-1:0] acc_round_c, y_ext_c;
logic signed [OUT_W-1:0] y_c;

integer i;

localparam int G0 = (L3P0_TAPS+3)/4;
localparam int G1 = (L3P1_TAPS+3)/4;
localparam int G2 = (L3P2_TAPS+3)/4;

localparam logic signed [ACC_W-1:0] OUT_MAX_EXT = (1 <<< (OUT_W-1)) - 1;
localparam logic signed [ACC_W-1:0] OUT_MIN_EXT = -(1 <<< (OUT_W-1));

always_ff @(posedge clk) begin
    x_delay[0] <= x_in;
    for (i = 1; i < NTAPS; i = i + 1)
        x_delay[i] <= x_delay[i-1];
end

// Build quarter-size local sums inside each L=3 phase branch
always_comb begin
    p00_c='0; p01_c='0; p02_c='0; p03_c='0;
    p10_c='0; p11_c='0; p12_c='0; p13_c='0;
    p20_c='0; p21_c='0; p22_c='0; p23_c='0;

    for (i = 0; i < L3P0_TAPS; i = i + 1) begin
        if (i < G0)           p00_c = p00_c + x_delay[3*i] * COEFFS_L3_P0[i];
        else if (i < 2*G0)    p01_c = p01_c + x_delay[3*i] * COEFFS_L3_P0[i];
        else if (i < 3*G0)    p02_c = p02_c + x_delay[3*i] * COEFFS_L3_P0[i];
        else                  p03_c = p03_c + x_delay[3*i] * COEFFS_L3_P0[i];
    end

    for (i = 0; i < L3P1_TAPS; i = i + 1) begin
        if (i < G1)           p10_c = p10_c + x_delay[3*i+1] * COEFFS_L3_P1[i];
        else if (i < 2*G1)    p11_c = p11_c + x_delay[3*i+1] * COEFFS_L3_P1[i];
        else if (i < 3*G1)    p12_c = p12_c + x_delay[3*i+1] * COEFFS_L3_P1[i];
        else                  p13_c = p13_c + x_delay[3*i+1] * COEFFS_L3_P1[i];
    end

    for (i = 0; i < L3P2_TAPS; i = i + 1) begin
        if (i < G2)           p20_c = p20_c + x_delay[3*i+2] * COEFFS_L3_P2[i];
        else if (i < 2*G2)    p21_c = p21_c + x_delay[3*i+2] * COEFFS_L3_P2[i];
        else if (i < 3*G2)    p22_c = p22_c + x_delay[3*i+2] * COEFFS_L3_P2[i];
        else                  p23_c = p23_c + x_delay[3*i+2] * COEFFS_L3_P2[i];
    end

    // Pair the local sums inside each branch
    a0_c = p00_c + p01_c;
    a1_c = p02_c + p03_c;

    b0_c = p10_c + p11_c;
    b1_c = p12_c + p13_c;

    c0_c = p20_c + p21_c;
    c1_c = p22_c + p23_c;
end

// First pipeline cut inside the phase branches
always_ff @(posedge clk) begin
    a0_r <= a0_c;
    a1_r <= a1_c;
    b0_r <= b0_c;
    b1_r <= b1_c;
    c0_r <= c0_c;
    c1_r <= c1_c;
end

// Finish each phase branch
always_comb begin
    br0_c = a0_r + a1_r;
    br1_c = b0_r + b1_r;
    br2_c = c0_r + c1_r;
end

// Second pipeline cut: register the 3 completed branches
always_ff @(posedge clk) begin
    br0_r <= br0_c;
    br1_r <= br1_c;
    br2_r <= br2_c;
end

// Combine two branches first so the final combine is shorter
always_comb begin
    pair01_c = br0_r + br1_r;
end

always_ff @(posedge clk) begin
    pair01_r <= pair01_c;
end

// Final combine with the third branch
always_comb begin
    acc_c = pair01_r + br2_r;
end

always_ff @(posedge clk) begin
    acc_r <= acc_c;
end

// Convert the accumulator back into output format
always_comb begin
    if (SHIFT_BITS > 0) begin
        if (acc_r >= 0)
            acc_round_c = acc_r + (1 <<< (SHIFT_BITS-1));
        else
            acc_round_c = acc_r - (1 <<< (SHIFT_BITS-1));
        y_ext_c = acc_round_c >>> SHIFT_BITS;
    end else begin
        acc_round_c = acc_r;
        y_ext_c = acc_r;
    end

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
