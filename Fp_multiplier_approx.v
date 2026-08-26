// =====================================================================
// fp_multiplier_approx.v
//
// Configurable-precision approximate IEEE-754 single-precision
// multiplier. Identical structure to fp_multiplier.v, except the
// 24x24-bit mantissa multiply is replaced with a narrower
// MANT_BITS x MANT_BITS multiply on the truncated (top-MSB) mantissa
// bits. The dropped low-order mantissa bits are treated as zero.
//
// This is the paper's core approximate-computing knob: a genuinely
// smaller multiplier is synthesized for MANT_BITS < 24 (fewer partial
// products / smaller multiplier tree -> lower area & power), at the
// cost of a bounded, measurable increase in numerical error.
//
//   MANT_BITS = 24 : bit-exact with fp_multiplier.v
//   MANT_BITS < 24 : approximate (accuracy/area trade-off)
// =====================================================================

module fp_multiplier_approx #(
    parameter MANT_BITS = 24     // 1..24, number of mantissa MSBs kept
) (
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg  [31:0] result,
    output reg          overflow,
    output reg          underflow,
    output reg          invalid
);

    localparam DROP = 24 - MANT_BITS;   // low-order mantissa bits dropped

    // -----------------------------------------------------------------
    // 1. UNPACK
    // -----------------------------------------------------------------
    wire        sign_a = a[31];
    wire [7:0]  exp_a  = a[30:23];
    wire [22:0] frac_a = a[22:0];

    wire        sign_b = b[31];
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] frac_b = b[22:0];

    wire result_sign = sign_a ^ sign_b;

    // -----------------------------------------------------------------
    // 2. SPECIAL VALUE CLASSIFICATION  (unchanged from exact version --
    //    special cases are still handled exactly, only the normal-path
    //    mantissa multiply is approximated)
    // -----------------------------------------------------------------
    wire a_is_nan  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire b_is_nan  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire a_is_inf  = (exp_a == 8'hFF) && (frac_a == 23'd0);
    wire b_is_inf  = (exp_b == 8'hFF) && (frac_b == 23'd0);
    wire a_is_zero = (exp_a == 8'h00);
    wire b_is_zero = (exp_b == 8'h00);

    // -----------------------------------------------------------------
    // 3. TRUNCATED MANTISSA MULTIPLY (MANT_BITS x MANT_BITS -> 2*MANT_BITS)
    // -----------------------------------------------------------------
    wire [23:0] mant_a = {1'b1, frac_a};
    wire [23:0] mant_b = {1'b1, frac_b};

    wire [MANT_BITS-1:0] mant_a_trunc = mant_a[23 -: MANT_BITS];
    wire [MANT_BITS-1:0] mant_b_trunc = mant_b[23 -: MANT_BITS];

    wire [2*MANT_BITS-1:0] product_trunc = mant_a_trunc * mant_b_trunc;

    // Re-align the narrow product back into the standard 48-bit field
    // (as if the dropped low bits of each input had been multiplied by
    // zero) so the rest of the pipeline is untouched.
    wire [47:0] product = {product_trunc, {2*DROP{1'b0}}};

    wire signed [9:0] exp_sum = $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - 10'sd127;

    // -----------------------------------------------------------------
    // 4. NORMALIZE  (identical to the exact multiplier)
    // -----------------------------------------------------------------
    reg [47:0] norm_product;
    reg signed [9:0] norm_exp;

    always @(*) begin
        if (product[47]) begin
            norm_product = product;
            norm_exp     = exp_sum + 10'sd1;
        end else begin
            norm_product = product << 1;
            norm_exp     = exp_sum;
        end
    end

    wire        guard_bit  = norm_product[23];
    wire        round_bit  = norm_product[22];
    wire        sticky_bit = |norm_product[21:0];
    wire [23:0] mant_trunc = norm_product[47:24];

    wire round_up = guard_bit & (round_bit | sticky_bit | mant_trunc[0]);
    wire [24:0] mant_rounded = mant_trunc + round_up;

    reg [23:0]       final_mant;
    reg signed [9:0] final_exp;

    always @(*) begin
        if (mant_rounded[24]) begin
            final_mant = mant_rounded[24:1];
            final_exp  = norm_exp + 10'sd1;
        end else begin
            final_mant = mant_rounded[23:0];
            final_exp  = norm_exp;
        end
    end

    // -----------------------------------------------------------------
    // 5. PACK + SPECIAL CASES  (unchanged)
    // -----------------------------------------------------------------
    wire normal_overflow  = (final_exp >= 10'sd255);
    wire normal_underflow = (final_exp <= 10'sd0);

    wire [31:0] normal_result =
        normal_overflow  ? {result_sign, 8'hFF, 23'd0}               :
        normal_underflow ? {result_sign, 31'd0}                      :
                            {result_sign, final_exp[7:0], final_mant[22:0]};

    wire [31:0] qnan = 32'h7FC00000;

    always @(*) begin
        overflow  = 1'b0;
        underflow = 1'b0;
        invalid   = 1'b0;

        if (a_is_nan || b_is_nan) begin
            result  = qnan;
            invalid = 1'b1;
        end
        else if ((a_is_inf && b_is_zero) || (a_is_zero && b_is_inf)) begin
            result  = qnan;
            invalid = 1'b1;
        end
        else if (a_is_inf || b_is_inf) begin
            result = {result_sign, 8'hFF, 23'd0};
        end
        else if (a_is_zero || b_is_zero) begin
            result = {result_sign, 31'd0};
        end
        else begin
            result    = normal_result;
            overflow  = normal_overflow;
            underflow = normal_underflow && !normal_overflow;
        end
    end

endmodule