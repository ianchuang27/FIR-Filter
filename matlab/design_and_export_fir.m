% matlab/design_and_export_fir.m
clear; clc; close all;

% Main script for the FIR part of the project.
% Does the floating-point design first, then checks fixed-point choices,
% then writes out the files needed for the RTL side.

% Filter specs from the project
wp  = 0.20;      % passband edge, normalized to Nyquist
ws  = 0.23;      % stopband edge, normalized to Nyquist
Ast = 80;        % stopband attenuation target in dB
N0  = 99;        % start here: order 99 means 100 taps

% firpm weights
% stopband is weighted more heavily so the script pushes harder there
weight_pb = 1;
weight_sb = 50;

% frequency grid for response checks
nFreq = 16384;

% fixed-point choices used later for the hardware model
Bin  = 16;       % input format Q1.15
Bout = 16;       % output format Q1.15

% try a few coefficient widths and keep the smallest one that still works
Bcoef_candidates = 16:24;

% length of test vector for the fixed-point reference run
Nsamp = 512;

% figure out where to save everything
script_path = mfilename('fullpath');
if isempty(script_path)
    base_dir = pwd;
else
    base_dir = fileparts(script_path);
end

fig_dir = fullfile(base_dir, 'figures');
out_dir = fullfile(base_dir, 'exports');

if ~exist(fig_dir, 'dir')
    mkdir(fig_dir);
end
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

% Start with the initial order, then keep increasing until the stopband
% finally hits the target.
N = N0;
b = firpm(N, [0 wp ws 1], [1 1 0 0], [weight_pb weight_sb]);

[pass_ripple, stop_attn, w, Hdb, Hmag] = measure_response(b, wp, ws, nFreq);

fprintf('Initial design: order = %d, taps = %d\n', N, N+1);
fprintf('Passband ripple = %.6f\n', pass_ripple);
fprintf('Stopband attenuation = %.2f dB\n', stop_attn);

while stop_attn < Ast
    N = N + 2;   % keep order odd so the number of taps stays even
    b = firpm(N, [0 wp ws 1], [1 1 0 0], [weight_pb weight_sb]);

    [pass_ripple, stop_attn, w, Hdb, Hmag] = measure_response(b, wp, ws, nFreq);
end

fprintf('\nFinal accepted floating-point design:\n');
fprintf('Order = %d\n', N);
fprintf('Taps  = %d\n', N+1);
fprintf('Passband ripple = %.6f\n', pass_ripple);
fprintf('Stopband attenuation = %.2f dB\n', stop_attn);

% Save floating-point coefficients too, mainly for reference
write_float_vector(fullfile(out_dir, 'coeffs_float.txt'), b(:));

% Save the unquantized response plot
figure;
plot(w/pi, Hdb, 'LineWidth', 1.5); grid on;
xlabel('\omega/\pi');
ylabel('Magnitude (dB)');
title(sprintf('Unquantized FIR Response, %d taps', N+1));
xline(wp, '--r', 'wp');
xline(ws, '--r', 'ws');
ylim([-140 5]);
saveas(gcf, fullfile(fig_dir, 'response_unquantized.png'));

% Sweep coefficient widths.
% For each width, quantize the taps, re-check the response, and also
% estimate how wide the accumulator would need to be.
numSweeps = numel(Bcoef_candidates);

stop_attn_vec    = zeros(numSweeps, 1);
pass_ripple_vec  = zeros(numSweeps, 1);
acc_bits_vec     = zeros(numSweeps, 1);
shift_bits_vec   = zeros(numSweeps, 1);
sum_abs_coef_vec = zeros(numSweeps, 1);

best_idx = [];
best_bq_int = [];
best_bq = [];

for ii = 1:numSweeps
    Bcoef = Bcoef_candidates(ii);

    [bq_int_i, bq_i, pass_ripple_q_i, stop_attn_q_i] = ...
        quantize_and_measure(b, Bcoef, wp, ws, nFreq);

    stop_attn_vec(ii)   = stop_attn_q_i;
    pass_ripple_vec(ii) = pass_ripple_q_i;

    % Worst-case accumulator estimate:
    % biggest input magnitude times sum of absolute quantized coefficients
    sum_abs_coeff_i = sum(abs(int64(bq_int_i)));
    max_acc_abs_i   = int64(2^(Bin-1) - 1) * sum_abs_coeff_i;
    acc_bits_i      = signed_bits_required(max_acc_abs_i);

    acc_bits_vec(ii)     = acc_bits_i;
    shift_bits_vec(ii)   = (Bin - 1) + (Bcoef - 1) - (Bout - 1);
    sum_abs_coef_vec(ii) = double(sum_abs_coeff_i);

    fprintf('\nCoefficient sweep: Bcoef = %d bits\n', Bcoef);
    fprintf('  Quantized stopband attenuation = %.2f dB\n', stop_attn_q_i);
    fprintf('  Quantized passband ripple      = %.6f\n', pass_ripple_q_i);
    fprintf('  Required accumulator width     = %d bits\n', acc_bits_i);

    % Keep the first width that still clears the stopband target
    if isempty(best_idx) && (stop_attn_q_i >= Ast)
        best_idx = ii;
        best_bq_int = bq_int_i;
        best_bq = bq_i;
    end
end

% If none of the tested widths clear the target, take the best stopband
% result that came out of the sweep.
if isempty(best_idx)
    [~, best_idx] = max(stop_attn_vec);
    best_Bcoef = Bcoef_candidates(best_idx);

    [best_bq_int, best_bq, ~, ~] = ...
        quantize_and_measure(b, best_Bcoef, wp, ws, nFreq);

    fprintf('\nWARNING: No coefficient width in the sweep met %.2f dB.\n', Ast);
    fprintf('Choosing best available width: %d bits\n', best_Bcoef);
else
    best_Bcoef = Bcoef_candidates(best_idx);
end

Bcoef = best_Bcoef;
bq_int = best_bq_int;
bq = best_bq;

% Recompute final quantized response using the chosen coefficient width
[Hq, wq] = freqz(bq, 1, nFreq);
Hqmag = abs(Hq);
Hqdb  = 20*log10(Hqmag + 1e-12);

pass_ripple_q = max(abs(Hqmag(wq/pi <= wp) - 1));
stop_attn_q   = -max(Hqdb(wq/pi >= ws));

% Final accumulator width and output shift
sum_abs_coeff = sum(abs(int64(bq_int)));
max_acc_abs   = int64(2^(Bin-1) - 1) * sum_abs_coeff;
ACC_BITS      = signed_bits_required(max_acc_abs);
SHIFT_BITS    = (Bin - 1) + (Bcoef - 1) - (Bout - 1);

fprintf('\nChosen quantized design:\n');
fprintf('Coefficient format = Q1.%d\n', Bcoef-1);
fprintf('Quantized stopband attenuation = %.2f dB\n', stop_attn_q);
fprintf('Quantized passband ripple      = %.6f\n', pass_ripple_q);
fprintf('Safe accumulator width         = %d bits\n', ACC_BITS);
fprintf('Accumulator-to-output shift    = %d bits\n', SHIFT_BITS);

% Save the full sweep so it can go in the report later
sweep_tbl = table( ...
    Bcoef_candidates(:), ...
    pass_ripple_vec(:), ...
    stop_attn_vec(:), ...
    acc_bits_vec(:), ...
    shift_bits_vec(:), ...
    sum_abs_coef_vec(:), ...
    'VariableNames', {'Bcoef_bits','PassRipple','StopAttn_dB','AccBits','ShiftBits','SumAbsCoeffInt'} ...
    );

writetable(sweep_tbl, fullfile(out_dir, 'quantization_sweep.csv'));

% Save the final quantized coefficient file used by the hardware
write_int_vector(fullfile(out_dir, 'coeffs_quantized_int.txt'), bq_int(:));
write_int_vector(fullfile(out_dir, sprintf('coeffs_q1_%d_int.txt', Bcoef-1)), bq_int(:));

% Split the same coefficients into L=2 polyphase sets
h0_L2 = bq_int(1:2:end);
h1_L2 = bq_int(2:2:end);

write_int_vector(fullfile(out_dir, 'coeffs_L2_phase0_int.txt'), h0_L2(:));
write_int_vector(fullfile(out_dir, 'coeffs_L2_phase1_int.txt'), h1_L2(:));

% Split the same coefficients into L=3 polyphase sets
h0_L3 = bq_int(1:3:end);
h1_L3 = bq_int(2:3:end);
h2_L3 = bq_int(3:3:end);

write_int_vector(fullfile(out_dir, 'coeffs_L3_phase0_int.txt'), h0_L3(:));
write_int_vector(fullfile(out_dir, 'coeffs_L3_phase1_int.txt'), h1_L3(:));
write_int_vector(fullfile(out_dir, 'coeffs_L3_phase2_int.txt'), h2_L3(:));

% Plot floating-point vs quantized response on one graph
figure;
plot(w/pi,  Hdb,  'LineWidth', 1.5); hold on;
plot(wq/pi, Hqdb, '--', 'LineWidth', 1.2); grid on;
xlabel('\omega/\pi');
ylabel('Magnitude (dB)');
title(sprintf('Unquantized vs Quantized FIR Response (Coeff Q1.%d)', Bcoef-1));
legend('Unquantized', 'Quantized', 'Location', 'SouthWest');
xline(wp, '--r', 'wp');
xline(ws, '--r', 'ws');
ylim([-140 5]);
saveas(gcf, fullfile(fig_dir, 'response_compare.png'));

% Plot the final quantized response by itself too
figure;
plot(wq/pi, Hqdb, 'LineWidth', 1.5); grid on;
xlabel('\omega/\pi');
ylabel('Magnitude (dB)');
title(sprintf('Quantized FIR Response (Coeff Q1.%d)', Bcoef-1));
xline(wp, '--r', 'wp');
xline(ws, '--r', 'ws');
ylim([-140 5]);
saveas(gcf, fullfile(fig_dir, 'response_quantized.png'));

% Test signal for the fixed-point reference model
n = 0:Nsamp-1;

% Three tones:
% 0.10 stays in the passband
% 0.21 sits near the transition band
% 0.35 lands in the stopband
x = 0.5*sin(2*pi*0.10*n) + ...
    0.3*sin(2*pi*0.21*n) + ...
    0.2*sin(2*pi*0.35*n);

scale_in  = 2^(Bin-1);
scale_out = 2^(Bout-1);

% Convert input into signed Q1.15 integers
x_int = sat_signed(round(x * scale_in), Bin);
x_q   = x_int / scale_in;

% Run a software model of the exact fixed-point FIR arithmetic that the
% hardware is supposed to follow.
[y_int, max_abs_acc_seen, acc_sat_count, out_sat_count] = ...
    fir_fixed_reference(x_int, bq_int, Bin, Bcoef, Bout, ACC_BITS);

y_q = double(y_int) / scale_out;

fprintf('\nFixed-point reference run:\n');
fprintf('Input format                 = Q1.%d\n', Bin-1);
fprintf('Coefficient format          = Q1.%d\n', Bcoef-1);
fprintf('Output format               = Q1.%d\n', Bout-1);
fprintf('Accumulator width used      = %d bits\n', ACC_BITS);
fprintf('Largest |accumulator| seen  = %d\n', max_abs_acc_seen);
fprintf('Accumulator saturations     = %d\n', acc_sat_count);
fprintf('Output saturations          = %d\n', out_sat_count);

% Export input and golden output for the testbench side
write_int_vector(fullfile(out_dir, 'x_input_q15.txt'), x_int(:));
write_int_vector(fullfile(out_dir, 'y_golden_q15.txt'), y_int(:));

% Write a summary text file so the important design numbers are all in one place
summary_file = fullfile(out_dir, 'fir_design_summary.txt');
fid = fopen(summary_file, 'w');

fprintf(fid, 'FIR DESIGN SUMMARY\n');
fprintf(fid, '==================\n\n');

fprintf(fid, 'Floating-point design\n');
fprintf(fid, '  Order                    : %d\n', N);
fprintf(fid, '  Taps                     : %d\n', N+1);
fprintf(fid, '  Passband ripple          : %.8f\n', pass_ripple);
fprintf(fid, '  Stopband attenuation     : %.4f dB\n\n', stop_attn);

fprintf(fid, 'Chosen quantized design\n');
fprintf(fid, '  Coefficient format       : Q1.%d\n', Bcoef-1);
fprintf(fid, '  Quantized passband ripple: %.8f\n', pass_ripple_q);
fprintf(fid, '  Quantized stopband attn  : %.4f dB\n', stop_attn_q);
fprintf(fid, '  Input format             : Q1.%d\n', Bin-1);
fprintf(fid, '  Output format            : Q1.%d\n', Bout-1);
fprintf(fid, '  Product fractional bits  : %d\n', (Bin-1)+(Bcoef-1));
fprintf(fid, '  Safe accumulator width   : %d bits\n', ACC_BITS);
fprintf(fid, '  Shift to output          : %d bits\n\n', SHIFT_BITS);

fprintf(fid, 'Overflow handling\n');
fprintf(fid, '  Worst-case |acc| bound   : %d\n', max_acc_abs);
fprintf(fid, '  Largest |acc| seen       : %d\n', max_abs_acc_seen);
fprintf(fid, '  Accumulator saturations  : %d\n', acc_sat_count);
fprintf(fid, '  Output saturations       : %d\n\n', out_sat_count);

fprintf(fid, 'Generated files\n');
fprintf(fid, '  coeffs_float.txt\n');
fprintf(fid, '  coeffs_quantized_int.txt\n');
fprintf(fid, '  coeffs_L2_phase0_int.txt\n');
fprintf(fid, '  coeffs_L2_phase1_int.txt\n');
fprintf(fid, '  coeffs_L3_phase0_int.txt\n');
fprintf(fid, '  coeffs_L3_phase1_int.txt\n');
fprintf(fid, '  coeffs_L3_phase2_int.txt\n');
fprintf(fid, '  x_input_q15.txt\n');
fprintf(fid, '  y_golden_q15.txt\n');
fprintf(fid, '  quantization_sweep.csv\n');

fclose(fid);

fprintf('\nDone. Outputs written to:\n%s\n', out_dir);

% ---------------- local functions ----------------

function [pass_ripple, stop_attn, w, Hdb, Hmag] = measure_response(b, wp, ws, nFreq)
    [H, w] = freqz(b, 1, nFreq);
    Hmag = abs(H);
    Hdb  = 20*log10(Hmag + 1e-12);

    pass_idx = (w/pi <= wp);
    stop_idx = (w/pi >= ws);

    pass_ripple = max(abs(Hmag(pass_idx) - 1));
    stop_attn   = -max(Hdb(stop_idx));
end

function [bq_int, bq, pass_ripple_q, stop_attn_q] = quantize_and_measure(b, Bcoef, wp, ws, nFreq)
    scale_coef = 2^(Bcoef-1);
    bq_int = sat_signed(round(b * scale_coef), Bcoef);
    bq = bq_int / scale_coef;

    [pass_ripple_q, stop_attn_q] = measure_response(bq, wp, ws, nFreq);
end

function y = sat_signed(x, bits)
    xmax = 2^(bits-1) - 1;
    xmin = -2^(bits-1);
    y = min(max(x, xmin), xmax);
end

function bits = signed_bits_required(max_abs_val)
    if double(max_abs_val) <= 0
        bits = 2;
    else
        bits = ceil(log2(double(max_abs_val) + 1)) + 1;
    end
end

function [y_int, max_abs_acc_seen, acc_sat_count, out_sat_count] = ...
    fir_fixed_reference(x_int, h_int, Bin, Bcoef, Bout, ACC_BITS)

    x_int = int64(x_int(:));
    h_int = int64(h_int(:));

    Ns = length(x_int);
    Nt = length(h_int);

    y_int = zeros(Ns, 1, 'int64');
    delay = zeros(Nt, 1, 'int64');

    acc_max = int64(2^(ACC_BITS-1) - 1);
    acc_min = int64(-2^(ACC_BITS-1));

    out_max = int64(2^(Bout-1) - 1);
    out_min = int64(-2^(Bout-1));

    shift_bits = (Bin - 1) + (Bcoef - 1) - (Bout - 1);

    acc_sat_count = 0;
    out_sat_count = 0;
    max_abs_acc_seen = int64(0);

    for n = 1:Ns
        % shift the delay line and load the new sample
        delay(2:end) = delay(1:end-1);
        delay(1) = x_int(n);

        acc = int64(0);

        % integer MAC loop, same basic idea as the RTL
        for k = 1:Nt
            prod_term = delay(k) * h_int(k);
            acc = acc + prod_term;

            if acc > acc_max
                acc = acc_max;
                acc_sat_count = acc_sat_count + 1;
            elseif acc < acc_min
                acc = acc_min;
                acc_sat_count = acc_sat_count + 1;
            end
        end

        if abs(acc) > max_abs_acc_seen
            max_abs_acc_seen = abs(acc);
        end

        % round and shift back to output format
        y_n = round_shift_signed(acc, shift_bits);

        % final output saturation
        if y_n > out_max
            y_n = out_max;
            out_sat_count = out_sat_count + 1;
        elseif y_n < out_min
            y_n = out_min;
            out_sat_count = out_sat_count + 1;
        end

        y_int(n) = y_n;
    end
end

function y = round_shift_signed(x, shift_bits)
    x = int64(x);

    if shift_bits <= 0
        y = bitshift(x, -shift_bits);
        return;
    end

    denom = int64(2^shift_bits);
    half  = int64(2^(shift_bits-1));

    if x >= 0
        y = idivide(x + half, denom, 'floor');
    else
        y = -idivide((-x) + half, denom, 'floor');
    end
end

function write_int_vector(filename, vec)
    fid = fopen(filename, 'w');
    if fid == -1
        error('Could not open file for writing: %s', filename);
    end
    vec = int64(vec(:));
    fprintf(fid, '%d\n', vec);
    fclose(fid);
end

function write_float_vector(filename, vec)
    fid = fopen(filename, 'w');
    if fid == -1
        error('Could not open file for writing: %s', filename);
    end
    vec = vec(:);
    fprintf(fid, '%.18g\n', vec);
    fclose(fid);
end