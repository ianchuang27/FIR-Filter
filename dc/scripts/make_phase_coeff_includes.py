from pathlib import Path

# This script takes the MATLAB-exported polyphase coefficient text files
# and turns them into .svh include files for the L=2 and L=3 RTL versions.

base = Path(".")
exports = base / "matlab_exports"
include_dir = base / "include"


def read_ints(path):
    # Read one integer coefficient per line
    vals = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line:
            vals.append(int(line))
    return vals


phase_files = [
    ("coeffs_L2_phase0_int.txt", "fir_l2_phase0.svh", "L2P0_TAPS", "COEFFS_L2_P0"),
    ("coeffs_L2_phase1_int.txt", "fir_l2_phase1.svh", "L2P1_TAPS", "COEFFS_L2_P1"),
    ("coeffs_L3_phase0_int.txt", "fir_l3_phase0.svh", "L3P0_TAPS", "COEFFS_L3_P0"),
    ("coeffs_L3_phase1_int.txt", "fir_l3_phase1.svh", "L3P1_TAPS", "COEFFS_L3_P1"),
    ("coeffs_L3_phase2_int.txt", "fir_l3_phase2.svh", "L3P2_TAPS", "COEFFS_L3_P2"),
]

for src_name, out_name, taps_name, coeff_name in phase_files:
    coeffs = read_ints(exports / src_name)
    out_path = include_dir / out_name

    with open(out_path, "w") as f:
        # Number of taps in this phase branch
        f.write(f"localparam int {taps_name} = {len(coeffs)};\n")

        # Coefficient array for this phase branch
        f.write(
            f"localparam logic signed [COEFF_W-1:0] {coeff_name} [0:{taps_name}-1] = '{{\n"
        )
        for i, c in enumerate(coeffs):
            comma = "," if i < len(coeffs) - 1 else ""
            f.write(f"    {c}{comma}\n")
        f.write("};\n")

    print(f"Wrote {out_path}")
