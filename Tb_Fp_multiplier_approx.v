`timescale 1ns/1ps
`include "Fp_multiplier_approx.v"

module Tb_approx_mul_sanity;

    reg  [31:0] a, b, expected;
    wire [31:0] result;
    wire        overflow, underflow, invalid;

    integer fd, r, errors, total;

    fp_multiplier_approx #(.MANT_BITS(24)) dut (
        .a(a), .b(b),
        .result(result),
        .overflow(overflow), .underflow(underflow), .invalid(invalid)
    );

    initial begin
        errors = 0; total = 0;
        fd = $fopen("Vector_mul.txt", "r");
        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %h\n", a, b, expected);
            if (r == 3) begin
                total = total + 1;
                #1;
                if (result !== expected) errors = errors + 1;
            end
        end
        $fclose(fd);
        $display("MANT_BITS=24 (should be bit-exact): Total=%0d Errors=%0d", total, errors);
        $finish;
    end
endmodule