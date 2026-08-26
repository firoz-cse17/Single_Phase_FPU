// =====================================================================
// fpu_top.v
//
// Standalone single-precision FPU core: ADD, SUB, MUL.
// Combinational (single-cycle) — this module is intentionally kept as
// a self-contained, CPU-independent unit (own operand/result ports,
// no coupling to any particular processor's control signals) so it
// can be characterized and synthesized on its own.
//
//   fpu_op = 2'b00 : result = a + b
//   fpu_op = 2'b01 : result = a - b
//   fpu_op = 2'b10 : result = a * b
//   fpu_op = 2'b11 : reserved (drives result = 0)
// =====================================================================

`include "fp_adder_subtractor.v"
`include "fp_multiplier.v"

module fpu_top (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [1:0]  fpu_op,

    output reg  [31:0] result,
    output reg          overflow,
    output reg          underflow,
    output reg          invalid
);

    localparam FPU_ADD = 2'b00;
    localparam FPU_SUB = 2'b01;
    localparam FPU_MUL = 2'b10;

    wire [31:0] add_result, mul_result;
    wire        add_overflow, add_underflow, add_invalid;
    wire        mul_overflow, mul_underflow, mul_invalid;

    fp_adder_subtractor u_add_sub (
        .a(a), .b(b),
        .sub(fpu_op[0]),          // 0 for FPU_ADD, 1 for FPU_SUB
        .result(add_result),
        .overflow(add_overflow), .underflow(add_underflow), .invalid(add_invalid)
    );

    fp_multiplier u_mul (
        .a(a), .b(b),
        .result(mul_result),
        .overflow(mul_overflow), .underflow(mul_underflow), .invalid(mul_invalid)
    );

    always @(*) begin
        case (fpu_op)
            FPU_ADD, FPU_SUB: begin
                result    = add_result;
                overflow  = add_overflow;
                underflow = add_underflow;
                invalid   = add_invalid;
            end
            FPU_MUL: begin
                result    = mul_result;
                overflow  = mul_overflow;
                underflow = mul_underflow;
                invalid   = mul_invalid;
            end
            default: begin
                result    = 32'd0;
                overflow  = 1'b0;
                underflow = 1'b0;
                invalid   = 1'b0;
            end
        endcase
    end

endmodule