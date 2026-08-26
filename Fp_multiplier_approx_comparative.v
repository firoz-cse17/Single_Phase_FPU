// =====================================================================
// fp_multiplier_approx_comp.v
//
// Constant-correction (compensated) truncated-mantissa multiplier.
//
// fp_multiplier_approx.v drops the low (24-MANT_BITS) mantissa bits of
// each operand to zero before multiplying. Because a truncated operand
// is never larger than the true value, this always UNDER-estimates the
// mantissa product -- a systematic (biased) error, not just noise.
//
// This variant appends a single constant '1' bit right after the
// truncation point on each operand instead of dropping straight to
// zero -- i.e. it assumes the discarded low bits average out to
// "half full" rather than "all zero". This is the classic
// constant-correction / "replace the truncated part with a 1"
// technique from the approximate-multiplier literature (used to
// de-bias truncated multipliers at essentially no extra hardware
// cost -- one wider bit per operand instead of a full rounding stage).
//
//   MANT_BITS = 24 : bit-exact with fp_multiplier.v (no compensation needed)
//   MANT_BITS < 24 : compensated approximate multiply
// =====================================================================

module fp_multiplier_approx_comp #(
    parameter MANT_BITS = 24
) (
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg  [31:0] result,
    output reg          overflow,
    output reg          underflow,
    output reg          invalid
);

    localparam DROP = 24 - MANT_BITS;
    // compensated operand width: MANT_BITS kept bits + 1 constant bit
    localparam COMP_W = (DROP >= 1) ? (MANT_BITS + 1) : 24;
    // amount the narrower product must be left-shifted to land back in
    // the standard 48-bit field (one fewer bit dropped than the naive
    // truncated version, since one bit was "recovered" as compensation)
    localparam SHIFT = (DROP >= 1) ? (2 * (DROP - 1)) : 0;

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
    // 2. SPECIAL VALUE CLASSIFICATION  (unchanged, still exact)
    // -----------------------------------------------------------------
    wire a_is_nan  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire b_is_nan  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire a_is_inf  = (exp_a == 8'hFF) && (frac_a == 23'd0);
    wire b_is_inf  = (exp_b == 8'hFF) && (frac_b == 23'd0);
    wire a_is_zero = (exp_a == 8'h00);
    wire b_is_zero = (exp_b == 8'h00);

    // -----------------------------------------------------------------
    // 3. COMPENSATED TRUNCATED MANTISSA MULTIPLY
    // -----------------------------------------------------------------
    wire [23:0] mant_a = {1'b1, frac_a};
    wire [23:0] mant_b = {1'b1, frac_b};

    wire [COMP_W-1:0] mant_a_comp =
        (DROP >= 1) ? {mant_a[23 -: MANT_BITS], 1'b1} : mant_a;
    wire [COMP_W-1:0] mant_b_comp =
        (DROP >= 1) ? {mant_b[23 -: MANT_BITS], 1'b1} : mant_b;

    wire [2*COMP_W-1:0] product_comp = mant_a_comp * mant_b_comp;

    wire [47:0] product = {product_comp, {SHIFT{1'b0}}};

    wire signed [9:0] exp_sum = $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - 10'sd127;

    // -----------------------------------------------------------------
    // 4. NORMALIZE  (identical to the exact / naive-truncated multiplier)
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