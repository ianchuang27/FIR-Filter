# FIR Filter Design and Hardware Implementation

This project designs and compares several hardware implementations of a low-pass FIR digital filter. The filter was first designed in MATLAB, then converted into fixed-point form and implemented in Verilog. Synopsys Design Compiler was used to compare the architectures in terms of timing, area, and power.

## Filter Target

The filter was designed with these specs:

- Passband edge: 0.20π rad/sample
- Stopband edge: 0.23π rad/sample
- Stopband attenuation: at least 80 dB

The final floating-point design used 232 taps. After quantization, the final coefficient format was Q1.21, with Q1.15 input and output format.

## Architectures Compared

Five FIR architectures were implemented and synthesized:

- Baseline direct-form FIR
- Parallel L=2
- Parallel L=3
- Pipelined
- Pipelined + Parallel L=3

## Final Results Summary

Final timing ranking:

1. Pipelined + Parallel L=3  
2. Pipelined  
3. Parallel L=3  
4. Parallel L=2  
5. Baseline  

The fastest design was the pipelined + parallel L=3 version.  
The best overall timing-power balance came from the pipelined version.

## Project Flow

1. Design the FIR filter in MATLAB
2. Quantize the coefficients and choose fixed-point formats
3. Export coefficients and golden vectors for RTL use
4. Implement the architectures in Verilog
5. Synthesize each design in Synopsys Design Compiler
6. Compare timing, area, and power results

## Folder Structure

- `matlab/` - MATLAB design script and exported fixed-point files
- `rtl/` - Verilog source files and generated include files
- `dc/` - Design Compiler setup, scripts, logs, netlists, and ddc files
- `reports/` - area, timing, and power reports
- `documentation/` - final writeup and figures
- `tb/` - verification notes and testbench-related files

## Main Files

- MATLAB design script: `matlab/design_and_export_fir.m`
- Final writeup: `documentation/FIR Filter Design Project Writeup.pdf`
- Final synthesis summary: `reports/final_results_table.csv`

## Notes

The 10 ns synthesis target was used as a common comparison point for all architectures. Even though none of the designs fully met that target, the results still showed a clear timing ranking and useful tradeoffs between speed, area, and power.
