`timescale 1ns/1ps
`include "fp_adder_subtractor.v"

module tb_fp_adder_subtractor;

    reg  [31:0] a, b;
    reg         sub;
    wire [31:0] result;
    wire        overflow, underflow, invalid;

    integer errors;

    fp_adder_subtractor dut (
        .a(a), .b(b), .sub(sub),
        .result(result),
        .overflow(overflow), .underflow(underflow), .invalid(invalid)
    );

    task check(input [31:0] va, input [31:0] vb, input s, input [31:0] expected, input [200*8-1:0] name);
        begin
            a = va; b = vb; sub = s;
            #1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL  %0s : a=%h b=%h sub=%b  got=%h  expected=%h",
                          name, va, vb, s, result, expected);
            end else begin
                $display("PASS  %0s : result=%h", name, result);
            end
        end
    endtask

    initial begin
        errors = 0;

        // 1.5 + 2.25 = 3.75
        check(32'h3FC00000, 32'h40100000, 1'b0, 32'h40700000, "1.5+2.25");

        // 1.0 - 1.0 = 0.0
        check(32'h3F800000, 32'h3F800000, 1'b1, 32'h00000000, "1.0-1.0");

        // 2.0 - 3.0 = -1.0
        check(32'h40000000, 32'h40400000, 1'b1, 32'hBF800000, "2.0-3.0");

        // -1.0 + 1.0 = 0.0  (+0 by convention)
        check(32'hBF800000, 32'h3F800000, 1'b0, 32'h00000000, "-1.0+1.0");

        // 0.1 + 0.2 ~= 0.3  (single precision rounding)
        check(32'h3DCCCCCD, 32'h3E4CCCCD, 1'b0, 32'h3E99999A, "0.1+0.2");

        // 100.0 + 0.0001
        check(32'h42C80000, 32'h38D1B717, 1'b0, 32'h42C8000D, "100.0+0.0001");

        // Inf + 5.0 = Inf
        check(32'h7F800000, 32'h40A00000, 1'b0, 32'h7F800000, "Inf+5.0");

        // Inf - Inf = NaN
        check(32'h7F800000, 32'h7F800000, 1'b1, 32'h7FC00000, "Inf-Inf");

        // 5.0 + NaN = NaN
        check(32'h40A00000, 32'h7FC00000, 1'b0, 32'h7FC00000, "5.0+NaN");

        // 3.0 - 3.0 = 0.0
        check(32'h40400000, 32'h40400000, 1'b1, 32'h00000000, "3.0-3.0");

        // -2.5 + -2.5 = -5.0
        check(32'hC0200000, 32'hC0200000, 1'b0, 32'hC0A00000, "-2.5+-2.5");

        // large + small causing many-bit left shift (cancellation)
        // 7.0 - 6.999999523... (adjacent floats) should not blow up
        check(32'h40E00000, 32'h40DFFFFF, 1'b1, 32'h35000000, "7.0-6.9999995");

        if (errors == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** %0d TEST(S) FAILED ***", errors);

        $finish;
    end

endmodule