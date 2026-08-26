// =====================================================================
// fp_multiplier.v
//
// IEEE-754 single precision (32-bit) floating point MULTIPLIER.
// Combinational (single-cycle) datapath, round-to-nearest-even.
//
// Same documented simplification as fp_adder_subtractor.v: subnormal
// (denormal) inputs are treated as zero, and results that underflow
// the normal range are flushed to zero.
// =====================================================================

module fp_multiplier (
    input  wire [31:0] a,
    input  wire [31:0] b,

    output reg  [31:0] result,
    output reg          overflow,
    output reg          underflow,
    output reg          invalid
);

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
    // 2. SPECIAL VALUE CLASSIFICATION
    // -----------------------------------------------------------------
    wire a_is_nan  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire b_is_nan  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire a_is_inf  = (exp_a == 8'hFF) && (frac_a == 23'd0);
    wire b_is_inf  = (exp_b == 8'hFF) && (frac_b == 23'd0);
    wire a_is_zero = (exp_a == 8'h00);   // flush-to-zero
    wire b_is_zero = (exp_b == 8'h00);

    // -----------------------------------------------------------------
    // 3. MANTISSA MULTIPLY  (24 x 24 -> 48 bits)
    // -----------------------------------------------------------------
    wire [23:0] mant_a = {1'b1, frac_a};
    wire [23:0] mant_b = {1'b1, frac_b};

    wire [47:0] product = mant_a * mant_b;

    // Tentative (unbiased-removed) exponent: exp_a + exp_b - 127
    wire signed [9:0] exp_sum = $signed({2'b0, exp_a}) + $signed({2'b0, exp_b}) - 10'sd127;

    // -----------------------------------------------------------------
    // 4. NORMALIZE
    //    product is either 1x.xxxx... (bit47=1) or 01.xxxx... (bit46=1)
    //    since both inputs are normalized (mant in [1,2)), product in [1,4)
    // -----------------------------------------------------------------
    reg [47:0] norm_product;
    reg signed [9:0] norm_exp;

    always @(*) begin
        if (product[47]) begin
            // product in [2,4) -> shift right 1, exponent + 1
            norm_product = product;             // keep as-is; extraction below accounts for offset
            norm_exp     = exp_sum + 10'sd1;
        end else begin
            // product in [1,2) -> already normalized, bit46 is implicit '1'
            norm_product = product << 1;        // align so implicit '1' is always at bit47
            norm_exp     = exp_sum;
        end
    end

    // After the shift above, norm_product[47] is always the implicit '1'.
    // The 23 fraction bits are norm_product[46:24]; everything below
    // (norm_product[23:0]) is used to form guard/round/sticky.
    wire        guard_bit  = norm_product[23];
    wire        round_bit  = norm_product[22];
    wire        sticky_bit = |norm_product[21:0];
    wire [23:0] mant_trunc = norm_product[47:24];   // 1 implicit + 23 fraction

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
    // 5. PACK + SPECIAL CASES
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
            // 0 * Inf -> invalid
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