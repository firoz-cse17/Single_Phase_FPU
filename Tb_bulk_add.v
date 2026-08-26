`timescale 1ns/1ps
`include "fp_adder_subtractor.v"

module tb_bulk_add;

    reg  [31:0] a, b, expected;
    reg         sub;
    wire [31:0] result;
    wire        overflow, underflow, invalid;

    integer fd, r, errors, total;

    fp_adder_subtractor dut (
        .a(a), .b(b), .sub(sub),
        .result(result),
        .overflow(overflow), .underflow(underflow), .invalid(invalid)
    );

    initial begin
        errors = 0;
        total  = 0;
        fd = $fopen("vectors_add.txt", "r");
        if (fd == 0) begin
            $display("ERROR: could not open vectors_add.txt");
            $finish;
        end

        while (!$feof(fd)) begin
            r = $fscanf(fd, "%h %h %d %h\n", a, b, sub, expected);
            if (r == 4) begin
                total = total + 1;
                #1;
                if (result !== expected) begin
                    errors = errors + 1;
                    if (errors <= 20)
                        $display("FAIL #%0d  a=%h b=%h sub=%b  got=%h expected=%h",
                                  total, a, b, sub, result, expected);
                end
            end
        end

        $fclose(fd);
        $display("\nTotal=%0d  Errors=%0d  PassRate=%0.2f%%",
                   total, errors, 100.0 * (total-errors) / total);
        $finish;
    end

endmodule