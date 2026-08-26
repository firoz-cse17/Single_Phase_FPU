"""
compute_error_stats.py

Reads the three raw-result .txt files produced by the Verilog dump
testbenches (tb_dump_approx_mul.v, tb_dump_approx_add.v, tb_dump_comp_mul.v)
and prints the same error-statistics tables used in the paper (Table I,
II, III). Run this in the same folder as the three .txt files.

Usage:
    python compute_error_stats.py
"""

import numpy as np


def h2f(h):
    return np.uint32(int(h, 16)).view(np.float32)


def rel_error_stats(rows, exp_idx, got_idx):
    rel_errs = []
    signed_errs = []
    exact_matches = 0
    for row in rows:
        exp_h, got_h = row[exp_idx], row[got_idx]
        if exp_h == got_h:
            exact_matches += 1
        exp_f = float(h2f(exp_h))
        got_f = float(h2f(got_h))
        if exp_f == 0.0 or not np.isfinite(exp_f) or not np.isfinite(got_f):
            continue
        rel_errs.append(abs(got_f - exp_f) / abs(exp_f))
        signed_errs.append((got_f - exp_f) / abs(exp_f))
    rel_errs = np.array(rel_errs)
    signed_errs = np.array(signed_errs)
    return {
        "exact_matches": exact_matches,
        "total": len(rows),
        "mean_abs_err": rel_errs.mean() * 100,
        "max_abs_err": rel_errs.max() * 100,
        "mean_signed_bias": signed_errs.mean() * 100,
    }


def load_rows(path, ncols):
    rows = []
    with open(path) as f:
        for line in f:
            parts = line.split()
            if len(parts) == ncols:
                rows.append(parts)
    return rows


def main():
    print("=" * 60)
    print("MULTIPLIER: naive truncation (approx_mul_results.txt)")
    print("columns: a  b  exact  MANT16  MANT12  MANT8")
    print("=" * 60)
    rows = load_rows("Approx_mul.txt", 6)
    print(f"Loaded {len(rows)} rows\n")
    for idx, mb in [(3, 16), (4, 12), (5, 8)]:
        s = rel_error_stats(rows, 2, idx)
        print(f"MANT_BITS={mb:2d}  exact_match={s['exact_matches']}/{s['total']}  "
              f"mean|err|={s['mean_abs_err']:.4f}%  max|err|={s['max_abs_err']:.4f}%  "
              f"signed_bias={s['mean_signed_bias']:+.4f}%")

    print()
    print("=" * 60)
    print("ADDER: bounded alignment shifter (approx_add_results.txt)")
    print("columns: a  b  sub  exact  SHIFT8  SHIFT4  SHIFT2")
    print("=" * 60)
    rows = load_rows("Approx_add.txt", 7)
    print(f"Loaded {len(rows)} rows\n")
    for idx, sh in [(4, 8), (5, 4), (6, 2)]:
        s = rel_error_stats(rows, 3, idx)
        print(f"MAX_SHIFT={sh:2d}  exact_match={s['exact_matches']}/{s['total']}  "
              f"mean|err|={s['mean_abs_err']:.4f}%  max|err|={s['max_abs_err']:.4f}%  "
              f"signed_bias={s['mean_signed_bias']:+.4f}%")

    print()
    print("=" * 60)
    print("MULTIPLIER: compensated truncation (approx_mul_comp_results.txt)")
    print("columns: a  b  exact  MANT16  MANT12  MANT8")
    print("=" * 60)
    rows = load_rows("Approx_mul_comp.txt", 6)
    print(f"Loaded {len(rows)} rows\n")
    for idx, mb in [(3, 16), (4, 12), (5, 8)]:
        s = rel_error_stats(rows, 2, idx)
        print(f"MANT_BITS={mb:2d}  exact_match={s['exact_matches']}/{s['total']}  "
              f"mean|err|={s['mean_abs_err']:.4f}%  max|err|={s['max_abs_err']:.4f}%  "
              f"signed_bias={s['mean_signed_bias']:+.4f}%")

    print()
    print("Compare these numbers against Table I / II / III in the paper draft.")


if __name__ == "__main__":
    main()