`timescale 1ns/1ps
`include "fp_multiplier.v"

module tb_fp_multiplier;

    reg  [31:0] a, b;
    wire [31:0] result;
    wire        overflow, underflow, invalid;

    integer errors;

    fp_multiplier dut (
        .a(a), .b(b),
        .result(result),
        .overflow(overflow), .underflow(underflow), .invalid(invalid)
    );

    task check(input [31:0] va, input [31:0] vb, input [31:0] expected, input [200*8-1:0] name);
        begin
            a = va; b = vb;
            #1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL  %0s : a=%h b=%h  got=%h  expected=%h", name, va, vb, result, expected);
            end else begin
                $display("PASS  %0s : result=%h", name, result);
            end
        end
    endtask

    initial begin
        errors = 0;

        check(32'h40000000, 32'h40400000, 32'h40C00000, "2.0*3.0=6.0");
        check(32'hBF800000, 32'h40000000, 32'hC0000000, "-1.0*2.0=-2.0");
        check(32'h3F800000, 32'h3F800000, 32'h3F800000, "1.0*1.0=1.0");
        check(32'h00000000, 32'h40A00000, 32'h00000000, "0.0*5.0=0.0");
        check(32'h80000000, 32'h40A00000, 32'h80000000, "-0.0*5.0=-0.0");
        check(32'h7F800000, 32'h40A00000, 32'h7F800000, "Inf*5.0=Inf");
        check(32'h7F800000, 32'hC0A00000, 32'hFF800000, "Inf*-5.0=-Inf");
        check(32'h7F800000, 32'h00000000, 32'h7FC00000, "Inf*0.0=NaN");
        check(32'h40A00000, 32'h7FC00000, 32'h7FC00000, "5.0*NaN=NaN");

        if (errors == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** %0d TEST(S) FAILED ***", errors);

        $finish;
    end

endmodule