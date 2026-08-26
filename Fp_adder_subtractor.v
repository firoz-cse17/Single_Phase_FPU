// =====================================================================
// fp_adder_subtractor.v
//
// IEEE-754 single precision (32-bit) floating point ADD / SUB unit.
// Combinational (single-cycle) datapath, round-to-nearest-even.
//
// NOTE (documented simplification, common in approximate-FPU papers):
// subnormal (denormal) inputs are flushed to zero, and results that
// underflow the normal range are flushed to zero. This keeps the
// datapath small and is a standard, explicitly-stated assumption in
// most lightweight FPU implementations.
//
//   op = 0 : result = a + b
//   op = 1 : result = a - b
// =====================================================================

module fp_adder_subtractor (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire        sub,        // 0 = add, 1 = subtract (a - b)

    output reg  [31:0] result,
    output reg          overflow,   // result exponent too large -> +/-Inf
    output reg          underflow,  // result flushed to zero (too small)
    output reg          invalid     // NaN produced from invalid inputs (Inf-Inf, NaN in)
);

    // -----------------------------------------------------------------
    // 1. UNPACK
    // -----------------------------------------------------------------
    wire        sign_a = a[31];
    wire [7:0]  exp_a  = a[30:23];
    wire [22:0] frac_a = a[22:0];

    wire        sign_b = b[31] ^ sub;      // XOR with sub -> effective sign for a-b
    wire [7:0]  exp_b  = b[30:23];
    wire [22:0] frac_b = b[22:0];

    // -----------------------------------------------------------------
    // 2. SPECIAL VALUE CLASSIFICATION
    // -----------------------------------------------------------------
    wire a_is_nan  = (exp_a == 8'hFF) && (frac_a != 23'd0);
    wire b_is_nan  = (exp_b == 8'hFF) && (frac_b != 23'd0);
    wire a_is_inf  = (exp_a == 8'hFF) && (frac_a == 23'd0);
    wire b_is_inf  = (exp_b == 8'hFF) && (frac_b == 23'd0);
    wire a_is_zero = (exp_a == 8'h00);     // flush-to-zero: treats denormals as 0 too
    wire b_is_zero = (exp_b == 8'h00);

    // -----------------------------------------------------------------
    // 3. NORMAL-PATH OPERAND PREP
    // -----------------------------------------------------------------
    wire [23:0] mant_a = {1'b1, frac_a};   // implicit leading 1
    wire [23:0] mant_b = {1'b1, frac_b};

    wire signed [8:0] exp_diff = $signed({1'b0, exp_a}) - $signed({1'b0, exp_b});

    // pick which operand has the larger magnitude (needed so the
    // effective-subtraction case never goes negative)
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
        else begin // exponents equal -> compare mantissas
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
    // 4. ALIGN  (extend with 3 extra bits: Guard, Round, Sticky)
    // -----------------------------------------------------------------
    wire [26:0] mant_large_ext = {mant_large, 3'b000};

    reg  [26:0] mant_small_shifted;
    reg         sticky_from_shift;

    always @(*) begin
        if (shift_amt >= 27) begin
            mant_small_shifted = 27'd0;
            sticky_from_shift  = (mant_small_raw != 24'd0);
        end else begin
            mant_small_shifted = {mant_small_raw, 3'b000} >> shift_amt;
            // OR together every bit that fell off the bottom
            sticky_from_shift  = |(({mant_small_raw, 3'b000}) &
                                    ((27'b1 << shift_amt) - 27'b1));
        end
    end

    wire [26:0] mant_small_aligned = {mant_small_shifted[26:1], mant_small_shifted[0] | sticky_from_shift};

    // -----------------------------------------------------------------
    // 5. ADD / SUBTRACT MANTISSAS
    // -----------------------------------------------------------------
    wire same_sign = (sign_large == sign_small);

    wire [27:0] sum_ext  = {1'b0, mant_large_ext} + {1'b0, mant_small_aligned};
    wire [27:0] diff_ext = {1'b0, mant_large_ext} - {1'b0, mant_small_aligned};

    wire [27:0] raw_result = same_sign ? sum_ext : diff_ext;

    // IEEE-754 default rounding: an exact-zero result from cancelling
    // opposite-sign operands is +0 (only -0 + -0 stays -0, handled
    // separately in the a_is_zero/b_is_zero special-case block below).
    wire        result_sign = (!same_sign && (raw_result == 28'd0)) ? 1'b0 : sign_large;

    // -----------------------------------------------------------------
    // 6. NORMALIZE
    //    same_sign case: at most 1 carry-out bit  -> shift right <=1
    //    diff case      : cancellation may need many left shifts
    // -----------------------------------------------------------------

    // Field layout inside the 28-bit raw_result:
    //   bit27       = carry-out (only ever set by the addition path)
    //   bit26       = implicit '1' position (normal, already-aligned value)
    //   bit25:3     = the 23 fraction bits
    //   bit2:0      = Guard, Round, Sticky
    //
    // leading-zero count of the low 27 bits (bit26:0), range 0..27
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

    reg [27:0] norm_mant;   // normalized, still has 3 LSB = G,R,S
    reg [8:0]  norm_exp;
    reg        norm_zero;
    reg [4:0]  lz;          // leading-zero shift amount (cancellation case)

    always @(*) begin
        norm_zero = (raw_result == 28'd0);

        if (!same_sign) begin
            // possible cancellation -> shift left (bit27 is always 0 here,
            // since a subtraction of two non-negative aligned operands
            // never carries out past bit26)
            if (norm_zero) begin
                norm_mant = 28'd0;
                norm_exp  = 9'd0;
            end else if (raw_result[26]) begin
                // already normalized: implicit '1' already sits at bit26
                norm_mant = raw_result;
                norm_exp  = exp_large;
            end else begin
                // shift left until bit 26 is '1'
                lz = lzc27(raw_result[26:0]);
                norm_mant = raw_result << lz;
                norm_exp  = exp_large - lz;
            end
        end
        else begin
            // addition case: 0 or 1 carry-out into bit 27
            if (raw_result[27]) begin
                // shift right by 1, OR the shifted-out bit into sticky
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
    // 7. ROUND (round-to-nearest-even) using G,R,S bits
    // -----------------------------------------------------------------
    wire        guard_bit  = norm_mant[2];
    wire        round_bit  = norm_mant[1];
    wire        sticky_bit = norm_mant[0];
    wire [23:0] mant_trunc = norm_mant[26:3];   // 24-bit (1 implicit + 23 frac)

    wire round_up = guard_bit & (round_bit | sticky_bit | mant_trunc[0]);

    wire [24:0] mant_rounded = mant_trunc + round_up;

    reg [23:0] final_mant;
    reg [8:0]  final_exp;

    always @(*) begin
        if (mant_rounded[24]) begin
            // rounding caused a carry-out of the implicit bit -> renormalize
            final_mant = mant_rounded[24:1];
            final_exp  = norm_exp + 1'b1;
        end else begin
            final_mant = mant_rounded[23:0];
            final_exp  = norm_exp;
        end
    end

    // -----------------------------------------------------------------
    // 8. PACK + SPECIAL CASES
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
            // Inf + (-Inf) or Inf - Inf -> invalid
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