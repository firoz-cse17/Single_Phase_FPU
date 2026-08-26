`timescale 1ns/1ps
`include "Fp_multiplier_approx_comparative.v"

module Tb_dump_comp_mul;

    reg  [31:0] a, b, expected;
    integer fd_in, fd_out, r, total;

    wire [31:0] r16, r12, r8;

    fp_multiplier_approx_comp #(.MANT_BITS(16)) dut16 (.a(a), .b(b), .result(r16));
    fp_multiplier_approx_comp #(.MANT_BITS(12)) dut12 (.a(a), .b(b), .result(r12));
    fp_multiplier_approx_comp #(.MANT_BITS(8))  dut8  (.a(a), .b(b), .result(r8));

    initial begin
        total = 0;
        fd_in  = $fopen("Vector_mul.txt", "r");
        fd_out = $fopen("Approx_mul_comp.txt", "w");

        while (!$feof(fd_in)) begin
            r = $fscanf(fd_in, "%h %h %h\n", a, b, expected);
            if (r == 3) begin
                total = total + 1;
                #1;
                $fwrite(fd_out, "%h %h %h %h %h %h\n", a, b, expected, r16, r12, r8);
            end
        end

        $fclose(fd_in);
        $fclose(fd_out);
        $display("Dumped %0d rows to approx_mul_comp_results.txt", total);
        $finish;
    end
endmodule