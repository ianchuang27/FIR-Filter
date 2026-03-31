# FIR Filter Design and Hardware Implementation

This project designs, quantizes, implements, and compares several hardware architectures for a low-pass FIR digital filter. The filter was first designed in MATLAB to satisfy the frequency-response specification, then converted to fixed-point form and implemented in Verilog. Synopsys Design Compiler was used to compare the architectures in terms of timing, area, and power.

## Project Specification

The FIR filter was designed to meet the following requirements:

- Passband edge: 0.20π rad/sample
- Stopband edge: 0.23π rad/sample
- Minimum stopband attenuation: 80 dB

The project also explored multiple hardware architectures for the same filter:

- Baseline direct-form FIR
- Parallel L=2
- Parallel L=3
- Pipelined
- Pipelined + Parallel L=3

## Filter Design Summary

The design began with a 100-tap FIR trial, following the project requirement to start with a 100-tap low-pass filter and increase the number of taps if necessary. That first design did not satisfy the 80 dB stopband attenuation requirement, so the order was increased until the first acceptable floating-point design was found.

### Initial 100-tap Trial
- Order: 99
- Taps: 100
- Passband ripple: 0.141453
- Stopband attenuation: 50.78 dB

### Final Accepted Floating-Point Design
- Order: 231
- Taps: 232
- Passband ripple: 0.004785
- Stopband attenuation: 80.05 dB

This means the final 232-tap design was the first one in the design flow that met the stopband requirement while preserving the intended low-pass response.

## Fixed-Point Design Choices

After the floating-point filter was accepted, the coefficients were quantized and a coefficient-width sweep was performed to find the smallest practical coefficient width that still preserved the specification.

### Final Chosen Formats
- Coefficient format: Q1.21
- Coefficient width: 22 bits signed
- Input format: Q1.15
- Output format: Q1.15
- Accumulator width: 39 bits
- Output shift: 21 bits

The coefficient width was selected from sweep results rather than by assumption. Lower coefficient widths reduced hardware cost, but degraded the stopband attenuation too much. The final 22-bit coefficient format preserved the required attenuation while keeping the quantized response close to the floating-point design.

## Coefficient Width Sweep Summary

| Coefficient Width | Stopband Attenuation | Passband Ripple | Notes |
|---|---:|---:|---|
| 16 bits | 67.98 dB | 0.005146 | Below target |
| 17 bits | 69.51 dB | 0.004886 | Below target |
| 18 bits | 74.08 dB | 0.004830 | Below target |
| 19 bits | 77.09 dB | 0.004796 | Below target |
| 22 bits | Meets 80 dB target | Close to floating-point | Chosen format |

The final quantized design remained very close to the floating-point design. In the final summary, the floating-point filter achieved about 80.0485 dB stopband attenuation and the quantized filter achieved about 80.0462 dB stopband attenuation.

## Overflow Handling and Verification

Overflow handling was considered explicitly in both MATLAB and Verilog.

MATLAB was used to estimate a safe accumulator width from the maximum possible input magnitude and the sum of the absolute quantized coefficient values. This produced a required accumulator width of 39 bits. The output shift was set to 21 bits so the final accumulated result could be returned from the raw product precision back to Q1.15 output format.

A fixed-point integer reference model was then used to simulate:

- signed multiplication
- accumulation
- rounding
- shifting
- output saturation

MATLAB also exported fixed-point verification vectors:

- `x_input_q15.txt`
- `y_golden_q15.txt`

These vectors reflect the same arithmetic assumptions used in the RTL and were used as fixed-point golden references.

## Architecture Overview

All architectures use the same filter coefficients and fixed-point assumptions. The differences in results come from hardware structure rather than from changing the filter itself.

### Baseline
The baseline design is a direct-form FIR implementation. It uses a full delay line, multiplies each stored sample by its corresponding coefficient, and sums all products into one accumulator. This serves as the main reference architecture.

### Parallel L=2
The L=2 design separates the coefficients into even and odd phases. Two branch sums are computed and then combined into the final result. This reduces the local summation depth compared to the baseline.

### Parallel L=3
The L=3 design separates the coefficients into three modulo-3 branches. The branch reductions were organized into smaller local groups to produce a more balanced combinational structure than a single long accumulation chain.

### Pipelined
The pipelined architecture keeps the same filter behavior as the baseline, but inserts registers inside the accumulation path so the sum is spread across multiple stages. This reduces combinational depth per clock cycle and improves timing.

### Pipelined + Parallel L=3
This combined architecture starts from the L=3 structure and adds multiple pipeline cuts within the branch-reduction and final-combine paths. It is the most timing-focused version implemented in the project.

## Hardware Results

All designs were synthesized in Synopsys Design Compiler using the same 10 ns target clock constraint as a common comparison point.

| Architecture | Total Cell Area | Worst Slack @ 10 ns | Est. Min Clock Period | Est. Max Frequency | Dynamic Power |
|---|---:|---:|---:|---:|---:|
| Baseline | 357213 | -46.02 ns | 56.02 ns | 17.85 MHz | 846.4089 uW |
| Parallel L=2 | 185310 | -34.68 ns | 44.68 ns | 22.38 MHz | 2.9167 mW |
| Parallel L=3 | 185172 | -34.60 ns | 44.60 ns | 22.42 MHz | 2.9160 mW |
| Pipelined | 277336 | -11.20 ns | 21.20 ns | 47.17 MHz | 288.7574 uW |
| Pipelined + Parallel L=3 | 249064 | -10.46 ns | 20.46 ns | 48.88 MHz | 3.7255 mW |

Estimated minimum clock period and maximum frequency were computed using:

- `Tmin = Tconstraint + |slack|`
- `fmax = 1 / Tmin`

Even though none of the designs fully met the 10 ns constraint, the common target still allowed a clear and consistent architecture comparison.

## Final Results Summary

### Timing Ranking
1. Pipelined + Parallel L=3
2. Pipelined
3. Parallel L=3
4. Parallel L=2
5. Baseline

### Design Takeaways
- **Best speed:** Pipelined + Parallel L=3
- **Best area:** Parallel L=3
- **Best timing-power balance:** Pipelined
- **Simplest reference implementation:** Baseline

The combined pipelined + parallel L=3 architecture achieved the highest speed, while the pipelined-only design provided the strongest balance between timing improvement and power.

## Project Flow

1. Design the FIR filter in MATLAB
2. Increase filter order until the floating-point design satisfies the spec
3. Quantize coefficients and choose fixed-point formats
4. Estimate accumulator width and output shift
5. Export coefficient files and fixed-point golden vectors
6. Implement multiple FIR architectures in Verilog
7. Synthesize each architecture in Synopsys Design Compiler
8. Compare timing, area, and power tradeoffs

## Repository Structure

- `matlab/` - MATLAB design scripts and exported fixed-point files
- `rtl/` - Verilog source files
- `include/` - generated parameter and coefficient include files
- `scripts/` or `dc/` - Design Compiler setup and synthesis scripts
- `reports/` - timing, area, and power reports
- `documentation/` - final writeup and figures
- `tb/` - verification files and testbench-related material

## Main Files

- MATLAB design script: `matlab/design_and_export_fir.m`
- Final writeup: `documentation/FIR Filter Design Project Writeup.pdf`
- Final synthesis summary: `reports/final_results_table.csv`

## Conclusion

This project shows that FIR implementation results depend heavily on architecture choice, not only on the filter coefficients themselves. MATLAB was used to establish a correct floating-point design and a safe fixed-point arithmetic path, while Verilog and Synopsys Design Compiler were used to study how structure changes timing, area, and power.

The baseline design was the slowest and largest. The L=2 and L=3 parallel versions reduced area and improved timing relative to the baseline. The pipelined architecture delivered a much larger timing improvement and also had the lowest dynamic power, making it the most balanced overall design. The pipelined + parallel L=3 architecture achieved the best speed, but at the cost of the highest dynamic power.
