`timescale 1ns/1ps
`include "Fp_multiplier.v"

module Tb_bulk_mul;

    reg  [31:0] a, b, expected;
    wire [31:0] result;
    wire        overflow, underflow, invalid;

    integer fd, r, errors, total;

    fp_multiplier dut (
        .a(a), .b(b),
        .result(result),
        .overflow(overflow), .underflow(underflow), .invalid(invalid)
    );

    initial begin
        errors = 0;
        total  = 0;
        fd = $fopen("Vector_mul.txt", "r");
        if (fd == 0) begin
            $display("ERROR: could not open Vector_mul.txt");
            $finish;
        end

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %h\n", a, b, expected);
            if (r == 3) begin
                total = total + 1;
                #1;
                if (result !== expected) begin
                    errors = errors + 1;
                    if (errors <= 20)
                        $display("FAIL #%0d  a=%h b=%h  got=%h expected=%h",
                                  total, a, b, result, expected);
                end
            end
        end

        $fclose(fd);
        $display("\nTotal=%0d  Errors=%0d  PassRate=%0.2f%%",
                   total, errors, 100.0 * (total-errors) / total);
        $finish;
    end

endmodule