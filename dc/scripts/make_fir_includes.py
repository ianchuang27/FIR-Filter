import re
from pathlib import Path

# This script reads the MATLAB export files and builds the
# baseline parameter/include files used by the Verilog RTL.

base = Path(".")
summary_path = base / "matlab_exports" / "fir_design_summary.txt"
coeffs_path = base / "matlab_exports" / "coeffs_quantized_int.txt"
params_out = base / "include" / "fir_params_baseline.svh"
coeffs_out = base / "include" / "fir_coeffs_baseline.svh"

summary = summary_path.read_text()


def grab(pattern, name):
    # Pull one integer field out of the MATLAB summary text file.
    # If the field is missing, stop right away so the include files
    # do not get built with the wrong values.
    m = re.search(pattern, summary)
    if not m:
        raise RuntimeError(f"Could not find {name} in {summary_path}")
    return int(m.group(1))


# Read the design settings that matter for the RTL
ntaps = grab(r"Taps\s*:\s*(\d+)", "Taps")
coef_frac = grab(r"Coefficient format\s*:\s*Q1\.(\d+)", "Coefficient format")
in_frac = grab(r"Input format\s*:\s*Q1\.(\d+)", "Input format")
out_frac = grab(r"Output format\s*:\s*Q1\.(\d+)", "Output format")
acc_w = grab(r"Safe accumulator width\s*:\s*(\d+)", "Safe accumulator width")
shift_bits = grab(r"Shift to output\s*:\s*(\d+)", "Shift to output")

# Convert fractional-bit counts into full signed widths
coeff_w = coef_frac + 1
in_w = in_frac + 1
out_w = out_frac + 1

# Load the quantized coefficient file from MATLAB
coeffs = []
for line in coeffs_path.read_text().splitlines():
    line = line.strip()
    if line:
        coeffs.append(int(line))

# Checking so the RTL does not get a broken coefficient file
if len(coeffs) != ntaps:
    raise RuntimeError(
        f"Coefficient count mismatch: summary says {ntaps}, "
        f"but {coeffs_path} contains {len(coeffs)} coefficients"
    )

# Parameter include used by all architectures
params_lines = [
    f"parameter int NTAPS      = {ntaps},",
    f"parameter int IN_W       = {in_w},",
    f"parameter int COEFF_W    = {coeff_w},",
    f"parameter int ACC_W      = {acc_w},",
    f"parameter int OUT_W      = {out_w},",
    f"parameter int SHIFT_BITS = {shift_bits}"
]

params_out.write_text("\n".join(params_lines) + "\n")

# Baseline coefficient include file
with open(coeffs_out, "w") as f:
    f.write("localparam logic signed [COEFF_W-1:0] COEFFS [0:NTAPS-1] = '{\n")
    for i, c in enumerate(coeffs):
        comma = "," if i < len(coeffs) - 1 else ""
        f.write(f"    {c}{comma}\n")
    f.write("};\n")

print(f"Wrote {params_out}")
print(f"Wrote {coeffs_out}")
print(
    f"NTAPS={ntaps}, IN_W={in_w}, COEFF_W={coeff_w}, "
    f"ACC_W={acc_w}, OUT_W={out_w}, SHIFT_BITS={shift_bits}"
)
