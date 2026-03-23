Testbench / Verification Notes

The MATLAB script generated fixed-point verification vectors for RTL checking.

Input vector:
- ../matlab/exports/x_input_q15.txt

Golden output vector:
- ../matlab/exports/y_golden_q15.txt

These vectors came from the fixed-point MATLAB reference model using:
- input format Q1.15
- coefficient format Q1.21
- accumulator width 39 bits
- output shift 21 bits
- signed rounding
- output saturation

The intended RTL verification flow is:
1. apply x_input_q15.txt to the FIR RTL
2. collect the RTL output samples
3. compare the RTL output against y_golden_q15.txt

The MATLAB test signal uses three tones:
- 0.10 in the passband
- 0.21 near the transition region
- 0.35 in the stopband

This was done so the verification input exercises different parts of the filter response instead of only the passband.