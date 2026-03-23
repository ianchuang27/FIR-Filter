`timescale 1ns/1ps

module tb_fir_baseline;

    // Match the fixed-point input/output width used by the RTL
    localparam int IN_W  = 16;
    localparam int OUT_W = 16;

    // Basic DUT signals
    logic clk;
    logic rst_n;
    logic signed [IN_W-1:0]  x_in;
    logic signed [OUT_W-1:0] y_out;

    // File handles for MATLAB-generated stimulus / golden output
    integer fin;
    integer fgold;

    // Return values from fscanf
    integer scan_in;
    integer scan_gold;

    // Just to keep track of how many samples were sent in
    integer sample_idx;

    // Temporary integers for file reads
    integer rtl_out_int;
    integer gold_out_int;

    // DUT = baseline FIR version
    fir_baseline dut (
        .clk   (clk),
        .rst_n (rst_n),
        .x_in  (x_in),
        .y_out (y_out)
    );

    // 10 ns clock period
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // Start everything in reset / zero input
        x_in = '0;
        rst_n = 0;
        sample_idx = 0;

        // Open the MATLAB stimulus file and the golden output file
        fin   = $fopen("../matlab/exports/x_input_q15.txt", "r");
        fgold = $fopen("../matlab/exports/y_golden_q15.txt", "r");

        // Stop right away if the stimulus file is missing
        if (fin == 0) begin
            $display("ERROR: could not open x_input_q15.txt");
            $finish;
        end

        // Also stop if the golden output file is missing
        if (fgold == 0) begin
            $display("ERROR: could not open y_golden_q15.txt");
            $finish;
        end

        // Hold reset for a few clocks so the DUT starts clean
        repeat (4) @(posedge clk);
        rst_n = 1;

        // Feed one input sample per clock from the MATLAB text file
        while (!$feof(fin)) begin
            scan_in = $fscanf(fin, "%d\n", rtl_out_int);
            @(posedge clk);
            x_in <= rtl_out_int[IN_W-1:0];
            sample_idx = sample_idx + 1;
        end

        // After all input samples are sent, drive zero
        @(posedge clk);
        x_in <= '0;

        // Give the FIR time to flush the remaining delayed samples through
        repeat (300) @(posedge clk);

        // Close files at the end
        $fclose(fin);
        $fclose(fgold);

        $display("Finished baseline stimulus run.");
        $finish;
    end

endmodule