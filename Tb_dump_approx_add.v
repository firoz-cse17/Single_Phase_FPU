`timescale 1ns/1ps
`include "FP_adder_subtractor_approx.v"

module Tb_dump_approx_add;

    reg  [31:0] a, b, expected;
    reg         sub;
    integer fd_in, fd_out, r, total, exact_errors;

    wire [31:0] r_exact, r8, r4, r2;

    fp_adder_subtractor_approx #(.MAX_SHIFT(27)) dut_exact (.a(a), .b(b), .sub(sub), .result(r_exact));
    fp_adder_subtractor_approx #(.MAX_SHIFT(8))  dut8       (.a(a), .b(b), .sub(sub), .result(r8));
    fp_adder_subtractor_approx #(.MAX_SHIFT(4))  dut4       (.a(a), .b(b), .sub(sub), .result(r4));
    fp_adder_subtractor_approx #(.MAX_SHIFT(2))  dut2       (.a(a), .b(b), .sub(sub), .result(r2));

    initial begin
        total = 0;
        exact_errors = 0;
        fd_in  = $fopen("Vector_add.txt", "r");
        fd_out = $fopen("Approx_add.txt", "w");

        while (!$feof(fd_in)) begin
            r = $fscanf(fd_in, "%h %h %d %h\n", a, b, sub, expected);
            if (r == 4) begin
                total = total + 1;
                #1;
                if (r_exact !== expected) exact_errors = exact_errors + 1;
                $fwrite(fd_out, "%h %h %b %h %h %h %h\n", a, b, sub, expected, r8, r4, r2);
            end
        end

        $fclose(fd_in);
        $fclose(fd_out);
        $display("MAX_SHIFT=27 sanity: Total=%0d Errors=%0d (should be 0)", total, exact_errors);
        $display("Dumped %0d rows to approx_add_results.txt", total);
        $finish;
    end
endmodule