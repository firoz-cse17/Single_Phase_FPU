`timescale 1ns/1ps
`include "FP_multiplier_approx.v"

module Tb_dump_approx_mul;

    reg  [31:0] a, b, expected;
    integer fd_in, fd_out, r, total;

    wire [31:0] r16, r12, r8;
    wire ov16, un16, inv16;
    wire ov12, un12, inv12;
    wire ov8,  un8,  inv8;

    fp_multiplier_approx #(.MANT_BITS(16)) dut16 (.a(a), .b(b), .result(r16), .overflow(ov16), .underflow(un16), .invalid(inv16));
    fp_multiplier_approx #(.MANT_BITS(12)) dut12 (.a(a), .b(b), .result(r12), .overflow(ov12), .underflow(un12), .invalid(inv12));
    fp_multiplier_approx #(.MANT_BITS(8))  dut8  (.a(a), .b(b), .result(r8),  .overflow(ov8),  .underflow(un8),  .invalid(inv8));

    initial begin
        total = 0;
        fd_in  = $fopen("Vector_mul.txt", "r");
        fd_out = $fopen("Approx_mul.txt", "w");

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
        $display("Dumped %0d rows to approx_mul_results.txt", total);
        $finish;
    end
endmodule