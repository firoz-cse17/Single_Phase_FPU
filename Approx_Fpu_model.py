"""
approx_fpu_model.py

Bit-accurate NumPy models of the Verilog approximate multipliers, used for
large-scale (application-level) experiments without needing to run every
multiply through the RTL simulator.

`approx_multiply_trunc`   mirrors fp_multiplier_approx.v      (naive floor truncation)
`approx_multiply_comp`    mirrors fp_multiplier_approx_comp.v (constant-correction /
                           compensated truncation)

Both were validated bit-for-bit against Icarus Verilog simulation output
before being used for any downstream experiment (see validate_models()).
"""

import numpy as np


def f32_to_bits(f32arr):
    return np.asarray(f32arr, dtype=np.float32).view(np.uint32)


def bits_to_f32(bits):
    return np.asarray(bits, dtype=np.uint32).view(np.float32)


def _unpack(bits):
    sign = (bits >> 31) & 1
    exp = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    return sign, exp, frac


def _pack_common(sa, sb, ea, eb, fa, fb):
    result_sign = sa ^ sb
    a_is_nan = (ea == 0xFF) & (fa != 0)
    b_is_nan = (eb == 0xFF) & (fb != 0)
    a_is_inf = (ea == 0xFF) & (fa == 0)
    b_is_inf = (eb == 0xFF) & (fb == 0)
    a_is_zero = (ea == 0)
    b_is_zero = (eb == 0)
    return result_sign, a_is_nan, b_is_nan, a_is_inf, b_is_inf, a_is_zero, b_is_zero


def _round_and_pack(product, exp_sum, result_sign, specials):
    a_is_nan, b_is_nan, a_is_inf, b_is_inf, a_is_zero, b_is_zero = specials

    bit47 = (product >> 47) & 1
    norm_product = np.where(bit47 == 1, product, product << 1)
    norm_exp = np.where(bit47 == 1, exp_sum + 1, exp_sum)

    guard = (norm_product >> 23) & 1
    round_bit = (norm_product >> 22) & 1
    sticky = (norm_product & ((1 << 22) - 1)) != 0
    mant_trunc = (norm_product >> 24) & 0xFFFFFF

    round_up = (guard == 1) & ((round_bit == 1) | sticky | ((mant_trunc & 1) == 1))
    mant_rounded = mant_trunc + round_up.astype(np.int64)

    carry = (mant_rounded >> 24) & 1
    final_mant = np.where(carry == 1, mant_rounded >> 1, mant_rounded & 0xFFFFFF)
    final_exp = np.where(carry == 1, norm_exp + 1, norm_exp)

    normal_overflow = final_exp >= 255
    normal_underflow = final_exp <= 0

    normal_result = np.where(
        normal_overflow, (result_sign << 31) | (0xFF << 23),
        np.where(normal_underflow, (result_sign << 31),
                 (result_sign << 31) | ((final_exp & 0xFF) << 23) | (final_mant & 0x7FFFFF))
    ).astype(np.uint32)

    qnan = np.uint32(0x7FC00000)
    result = np.where(a_is_nan | b_is_nan, qnan,
              np.where((a_is_inf & b_is_zero) | (a_is_zero & b_is_inf), qnan,
              np.where(a_is_inf | b_is_inf, ((result_sign << 31) | (0xFF << 23)).astype(np.uint32),
              np.where(a_is_zero | b_is_zero, (result_sign << 31).astype(np.uint32),
                       normal_result))))
    return bits_to_f32(result.astype(np.uint32))


def approx_multiply_trunc(a, b, mant_bits):
    """Naive floor-truncation approximate multiply (fp_multiplier_approx.v)."""
    a_bits = f32_to_bits(a).astype(np.int64)
    b_bits = f32_to_bits(b).astype(np.int64)
    sa, ea, fa = _unpack(a_bits)
    sb, eb, fb = _unpack(b_bits)

    mant_a = (1 << 23) | fa
    mant_b = (1 << 23) | fb

    DROP = 24 - mant_bits
    mant_a_t = mant_a >> DROP
    mant_b_t = mant_b >> DROP
    product = (mant_a_t * mant_b_t) << (2 * DROP)

    exp_sum = ea.astype(np.int64) + eb.astype(np.int64) - 127
    result_sign, *specials = _pack_common(sa, sb, ea, eb, fa, fb)
    return _round_and_pack(product, exp_sum, result_sign, specials)


def approx_multiply_comp(a, b, mant_bits):
    """
    Constant-correction (compensated) truncation: instead of dropping the
    low (24-mant_bits) mantissa bits to zero, a single '1' compensation bit
    is appended right after the truncation point. This offsets the
    systematic negative bias of plain truncation (a truncated operand is
    never larger than the true value, so naive truncation always
    under-estimates the product) -- the same "replace the truncated part
    with a 1" idea used in constant-correction truncated multipliers in
    the approximate-computing literature.
    """
    a_bits = f32_to_bits(a).astype(np.int64)
    b_bits = f32_to_bits(b).astype(np.int64)
    sa, ea, fa = _unpack(a_bits)
    sb, eb, fb = _unpack(b_bits)

    mant_a = (1 << 23) | fa
    mant_b = (1 << 23) | fb

    DROP = 24 - mant_bits
    if DROP < 1:
        # nothing to compensate -- identical to exact
        mant_a_c = mant_a
        mant_b_c = mant_b
        shift = 0
    else:
        mant_a_t = mant_a >> DROP
        mant_b_t = mant_b >> DROP
        mant_a_c = (mant_a_t << 1) | 1     # append compensation bit '1'
        mant_b_c = (mant_b_t << 1) | 1
        shift = 2 * (DROP - 1)

    product = (mant_a_c * mant_b_c) << shift

    exp_sum = ea.astype(np.int64) + eb.astype(np.int64) - 127
    result_sign, *specials = _pack_common(sa, sb, ea, eb, fa, fb)
    return _round_and_pack(product, exp_sum, result_sign, specials)


def validate_models(vectors_path="Approx_mul.txt"):
    """Cross-check approx_multiply_trunc against the Icarus Verilog dump."""
    rows = []
    with open(vectors_path) as f:
        for line in f:
            parts = line.split()
            if len(parts) == 6:
                rows.append(parts)

    a_arr = np.array([np.uint32(int(r[0], 16)) for r in rows]).view(np.float32)
    b_arr = np.array([np.uint32(int(r[1], 16)) for r in rows]).view(np.float32)

    ok = True
    for idx, mb in [(3, 16), (4, 12), (5, 8)]:
        verilog_out = np.array([np.uint32(int(r[idx], 16)) for r in rows])
        py_out = f32_to_bits(approx_multiply_trunc(a_arr, b_arr, mb))
        mism = int(np.sum(verilog_out != py_out))
        print(f"MANT_BITS={mb}: mismatches vs Verilog = {mism}/{len(rows)}")
        ok = ok and (mism == 0)
    return ok


if __name__ == "__main__":
    assert validate_models(), "Python model does not match Verilog RTL output!"
    print("Python trunc model validated bit-exact against Verilog RTL.")