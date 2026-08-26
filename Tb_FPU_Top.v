`timescale 1ns/1ps
`include "fpu_top.v"

module tb_fpu_top;

    reg  [31:0] a, b;
    reg  [1:0]  fpu_op;
    wire [31:0] result;
    wire        overflow, underflow, invalid;

    integer errors;

    fpu_top dut (
        .a(a), .b(b), .fpu_op(fpu_op),
        .result(result),
        .overflow(overflow), .underflow(underflow), .invalid(invalid)
    );

    task check(input [31:0] va, input [31:0] vb, input [1:0] op, input [31:0] expected, input [200*8-1:0] name);
        begin
            a = va; b = vb; fpu_op = op;
            #1;
            if (result !== expected) begin
                errors = errors + 1;
                $display("FAIL  %0s : got=%h expected=%h", name, result, expected);
            end else begin
                $display("PASS  %0s : result=%h", name, result);
            end
        end
    endtask

    initial begin
        errors = 0;

        check(32'h3FC00000, 32'h40100000, 2'b00, 32'h40700000, "ADD 1.5+2.25");
        check(32'h40400000, 32'h40400000, 2'b01, 32'h00000000, "SUB 3.0-3.0");
        check(32'h40000000, 32'h40400000, 2'b10, 32'h40C00000, "MUL 2.0*3.0");
        check(32'hBF800000, 32'h40000000, 2'b10, 32'hC0000000, "MUL -1.0*2.0");

        if (errors == 0)
            $display("\n*** ALL TESTS PASSED ***");
        else
            $display("\n*** %0d TEST(S) FAILED ***", errors);

        $finish;
    end

endmodule