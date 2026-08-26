// =====================================================================
// fp_adder_subtractor_approx.v
//
// Configurable-precision approximate IEEE-754 single-precision
// add/sub unit. Identical structure to fp_adder_subtractor.v, except
// the mantissa-alignment shifter is bounded to MAX_SHIFT bits instead
// of the full 27-bit range. When the true exponent difference exceeds
// MAX_SHIFT, the smaller operand is dropped entirely (its contribution
// is already small in that regime -- this bounds the shifter's mux
// depth/width in hardware, directly reducing area).
//
//   MAX_SHIFT = 27 : bit-exact with fp_adder_subtractor.v
//   MAX_SHIFT < 27 : approximate (accuracy/area trade-off)
// =====================================================================

module fp_adder_subtractor_approx #(
    parameter MAX_SHIFT = 27      // 0..27, largest alignment shift the
                                   // hardware will actually perform
) (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        sub,

    output reg  [31:0] result,
    output reg          overflow,
    output reg          underflow,
    output reg          invalid
);

    // -----------------------------------------------------------------
    // 1. UNPACK  (unchanged)
    // -----------------------------------------------------------------
    wire        sign_a = a[31];
    wire [7:0]  exp_a  = a[30:23];
    wire [22:0] frac_a = a[22:0];

    wire        sign_b = b[31] ^ sub;
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] frac_b = b[22:0];

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
    // 3. NORMAL-PATH OPERAND PREP  (unchanged)
    // -----------------------------------------------------------------
    wire [23:0] mant_a = {1'b1, frac_a};
    wire [23:0] mant_b = {1'b1, frac_b};

    wire signed [8:0] exp_diff = $signed({1'b0, exp_a}) - $signed({1'b0, exp_b});

    reg        sign_large, sign_small;
    reg [7:0]  exp_large;
    reg [23:0] mant_large, mant_small_raw;
    reg [8:0]  shift_amt;

    always @(*) begin
        if (exp_diff > 0) begin
            sign_large = sign_a;  exp_large = exp_a;  mant_large     = mant_a;
            sign_small = sign_b;                      mant_small_raw = mant_b;
            shift_amt  = exp_diff;
        end
        else if (exp_diff < 0) begin
            sign_large = sign_b;  exp_large = exp_b;  mant_large     = mant_b;
            sign_small = sign_a;                      mant_small_raw = mant_a;
            shift_amt  = -exp_diff;
        end
        else begin
            if (mant_a >= mant_b) begin
                sign_large = sign_a;  exp_large = exp_a;  mant_large     = mant_a;
                sign_small = sign_b;                      mant_small_raw = mant_b;
            end else begin
                sign_large = sign_b;  exp_large = exp_b;  mant_large     = mant_b;
                sign_small = sign_a;                      mant_small_raw = mant_a;
            end
            shift_amt = 9'd0;
        end
    end

    // -----------------------------------------------------------------
    // 4. ALIGN -- APPROXIMATION POINT
    //    Real hardware only implements a shifter for 0..MAX_SHIFT.
    //    Any true shift beyond MAX_SHIFT means the small operand's
    //    contribution is below the shifter's resolution, so it is
    //    dropped (treated as zero) instead of being computed exactly.
    // -----------------------------------------------------------------
    wire [26:0] mant_large_ext = {mant_large, 3'b000};

    // narrow the shift-amount signal to just enough bits to represent
    // 0..MAX_SHIFT -- this is what actually lets synthesis shrink the
    // barrel shifter's mux tree for MAX_SHIFT < 27 (declaring it as a
    // full 5-bit value regardless of MAX_SHIFT would let the tool
    // build the full-range shifter every time).
    localparam SHIFT_BITS = $clog2(MAX_SHIFT + 1);

    wire beyond_range = (shift_amt > MAX_SHIFT);
    wire [SHIFT_BITS-1:0] clamped_shift = beyond_range ? {SHIFT_BITS{1'b0}} : shift_amt[SHIFT_BITS-1:0];

    reg  [26:0] mant_small_shifted;
    reg         sticky_from_shift;

    always @(*) begin
        if (beyond_range) begin
            mant_small_shifted = 27'd0;
            sticky_from_shift  = 1'b0;     // dropped, not even counted as sticky
        end
        else begin
            mant_small_shifted = {mant_small_raw, 3'b000} >> clamped_shift;
            sticky_from_shift  = |(({mant_small_raw, 3'b000}) &
                                    ((27'b1 << clamped_shift) - 27'b1));
        end
    end

    wire [26:0] mant_small_aligned = {mant_small_shifted[26:1], mant_small_shifted[0] | sticky_from_shift};

    // -----------------------------------------------------------------
    // 5. ADD / SUBTRACT MANTISSAS  (unchanged)
    // -----------------------------------------------------------------
    wire same_sign = (sign_large == sign_small);

    wire [27:0] sum_ext  = {1'b0, mant_large_ext} + {1'b0, mant_small_aligned};
    wire [27:0] diff_ext = {1'b0, mant_large_ext} - {1'b0, mant_small_aligned};

    wire [27:0] raw_result = same_sign ? sum_ext : diff_ext;

    wire result_sign = (!same_sign && (raw_result == 28'd0)) ? 1'b0 : sign_large;

    // -----------------------------------------------------------------
    // 6. NORMALIZE  (unchanged)
    // -----------------------------------------------------------------
    function [4:0] lzc27;
        input [26:0] v;
        integer i;
        begin
            lzc27 = 27;
            for (i = 26; i >= 0; i = i - 1)
                if (v[i] && (lzc27 == 27))
                    lzc27 = 26 - i;
        end
    endfunction

    reg [27:0] norm_mant;
    reg [8:0]  norm_exp;
    reg        norm_zero;
    reg [4:0]  lz;

    always @(*) begin
        norm_zero = (raw_result == 28'd0);

        if (!same_sign) begin
            if (norm_zero) begin
                norm_mant = 28'd0;
                norm_exp  = 9'd0;
            end else if (raw_result[26]) begin
                norm_mant = raw_result;
                norm_exp  = exp_large;
            end else begin
                lz = lzc27(raw_result[26:0]);
                norm_mant = raw_result << lz;
                norm_exp  = exp_large - lz;
            end
        end
        else begin
            if (raw_result[27]) begin
                norm_mant = {1'b0, raw_result[27:1]};
                norm_mant[0] = norm_mant[0] | raw_result[0];
                norm_exp  = exp_large + 1'b1;
            end else begin
                norm_mant = raw_result;
                norm_exp  = exp_large;
            end
        end
    end

    // -----------------------------------------------------------------
    // 7. ROUND  (unchanged)
    // -----------------------------------------------------------------
    wire        guard_bit  = norm_mant[2];
    wire        round_bit  = norm_mant[1];
    wire        sticky_bit = norm_mant[0];
    wire [23:0] mant_trunc = norm_mant[26:3];

    wire round_up = guard_bit & (round_bit | sticky_bit | mant_trunc[0]);
    wire [24:0] mant_rounded = mant_trunc + round_up;

    reg [23:0] final_mant;
    reg [8:0]  final_exp;

    always @(*) begin
        if (mant_rounded[24]) begin
            final_mant = mant_rounded[24:1];
            final_exp  = norm_exp + 1'b1;
        end else begin
            final_mant = mant_rounded[23:0];
            final_exp  = norm_exp;
        end
    end

    // -----------------------------------------------------------------
    // 8. PACK + SPECIAL CASES  (unchanged)
    // -----------------------------------------------------------------
    wire normal_overflow  = (final_exp >= 9'd255);
    wire normal_underflow = (final_exp <= 9'd0) || norm_zero;

    wire [31:0] normal_result =
        normal_overflow  ? {result_sign, 8'hFF, 23'd0}                 :
        normal_underflow ? {result_sign, 31'd0}                        :
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
        else if (a_is_inf && b_is_inf && (sign_a != sign_b)) begin
            result  = qnan;
            invalid = 1'b1;
        end
        else if (a_is_inf) begin
            result = {sign_a, 8'hFF, 23'd0};
        end
        else if (b_is_inf) begin
            result = {sign_b, 8'hFF, 23'd0};
        end
        else if (a_is_zero && b_is_zero) begin
            result = {(sign_a & sign_b), 31'd0};
        end
        else if (a_is_zero) begin
            result = {sign_b, exp_b, frac_b};
        end
        else if (b_is_zero) begin
            result = {sign_a, exp_a, frac_a};
        end
        else begin
            result    = normal_result;
            overflow  = normal_overflow;
            underflow = normal_underflow && !normal_overflow;
        end
    end

endmodule