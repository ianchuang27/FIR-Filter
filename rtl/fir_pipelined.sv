module fir_pipelined #(
`include "fir_params_baseline.svh"
)(
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic signed [IN_W-1:0]       x_in,
    output logic signed [OUT_W-1:0]      y_out
);

// Full coefficient set, same taps as baseline.
// Difference here is only how the long sum is split across pipeline stages.
`include "fir_coeffs_baseline.svh"

logic signed [IN_W-1:0]  x_delay [0:NTAPS-1];

// First stage: split the full FIR into 8 local sums
logic signed [ACC_W-1:0] s0_c, s1_c, s2_c, s3_c, s4_c, s5_c, s6_c, s7_c;
logic signed [ACC_W-1:0] s0_r, s1_r, s2_r, s3_r, s4_r, s5_r, s6_r, s7_r;

// Second stage: pair up the 8 sums into 4 bigger sums
logic signed [ACC_W-1:0] p0_c, p1_c, p2_c, p3_c;
logic signed [ACC_W-1:0] p0_r, p1_r, p2_r, p3_r;

// Third stage: final combine before output scaling
logic signed [ACC_W-1:0] acc_c, acc_r;
logic signed [ACC_W-1:0] acc_round_c, y_ext_c;
logic signed [OUT_W-1:0] y_c;

integer i;

// Each local group holds about 1/8 of the taps
localparam int G = NTAPS/8;

localparam logic signed [ACC_W-1:0] OUT_MAX_EXT = (1 <<< (OUT_W-1)) - 1;
localparam logic signed [ACC_W-1:0] OUT_MIN_EXT = -(1 <<< (OUT_W-1));

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < NTAPS; i = i + 1)
            x_delay[i] <= '0;
    end else begin
        x_delay[0] <= x_in;
        for (i = 1; i < NTAPS; i = i + 1)
            x_delay[i] <= x_delay[i-1];
    end
end

// Stage 1:
// break the full FIR into 8 shorter MAC sections
always_comb begin
    s0_c = '0; s1_c = '0; s2_c = '0; s3_c = '0;
    s4_c = '0; s5_c = '0; s6_c = '0; s7_c = '0;

    for (i = 0; i < G; i = i + 1)
        s0_c = s0_c + x_delay[i] * COEFFS[i];
    for (i = G; i < 2*G; i = i + 1)
        s1_c = s1_c + x_delay[i] * COEFFS[i];
    for (i = 2*G; i < 3*G; i = i + 1)
        s2_c = s2_c + x_delay[i] * COEFFS[i];
    for (i = 3*G; i < 4*G; i = i + 1)
        s3_c = s3_c + x_delay[i] * COEFFS[i];
    for (i = 4*G; i < 5*G; i = i + 1)
        s4_c = s4_c + x_delay[i] * COEFFS[i];
    for (i = 5*G; i < 6*G; i = i + 1)
        s5_c = s5_c + x_delay[i] * COEFFS[i];
    for (i = 6*G; i < 7*G; i = i + 1)
        s6_c = s6_c + x_delay[i] * COEFFS[i];
    for (i = 7*G; i < NTAPS; i = i + 1)
        s7_c = s7_c + x_delay[i] * COEFFS[i];
end

// Register stage after the first local sums
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        s0_r <= '0; s1_r <= '0; s2_r <= '0; s3_r <= '0;
        s4_r <= '0; s5_r <= '0; s6_r <= '0; s7_r <= '0;
    end else begin
        s0_r <= s0_c; s1_r <= s1_c; s2_r <= s2_c; s3_r <= s3_c;
        s4_r <= s4_c; s5_r <= s5_c; s6_r <= s6_c; s7_r <= s7_c;
    end
end

// Stage 2:
// combine the 8 sums into 4 larger sums
always_comb begin
    p0_c = s0_r + s1_r;
    p1_c = s2_r + s3_r;
    p2_c = s4_r + s5_r;
    p3_c = s6_r + s7_r;
end

// Register stage after the 4 intermediate sums
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        p0_r <= '0; p1_r <= '0; p2_r <= '0; p3_r <= '0;
    end else begin
        p0_r <= p0_c; p1_r <= p1_c; p2_r <= p2_c; p3_r <= p3_c;
    end
end

// Stage 3:
// final sum of the 4 pipelined branches
always_comb begin
    acc_c = p0_r + p1_r + p2_r + p3_r;
end

// Register before output scaling/saturation
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        acc_r <= '0;
    else
        acc_r <= acc_c;
end

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
