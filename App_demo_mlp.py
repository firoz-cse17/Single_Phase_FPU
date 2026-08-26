"""
app_demo_mlp.py

Application-level evaluation of the approximate multiplier: train a small
MLP classifier normally (float64, exact), then run INFERENCE with the
matrix-multiplications replaced by our RTL-validated approximate multiply
models (naive truncation and compensated truncation), at several
MANT_BITS levels. Additions/accumulations stay exact throughout, matching
the paper's earlier finding that the multiply path is the worthwhile
approximation target, not the add path.

Dataset: sklearn's built-in `digits` (8x8 grayscale handwritten digits,
10 classes) -- chosen because it requires no network access and is a
standard, reproducible small-scale benchmark.
"""

import numpy as np
from sklearn.datasets import load_digits
from sklearn.model_selection import train_test_split
try:
    # preferred import
    from sklearn.neural_network import MLPClassifier
except Exception:
    # some environments / linters may not resolve the submodule; fall back
    # to importing the package and grabbing the attribute
    from sklearn import neural_network
    MLPClassifier = neural_network.MLPClassifier
from sklearn.preprocessing import StandardScaler

from Approx_Fpu_model import approx_multiply_trunc, approx_multiply_comp


def approx_matmul(X, W, multiply_fn, mant_bits):
    """
    X: (N, K) float32, W: (K, M) float32
    Elementwise multiply via `multiply_fn` (bit-accurate approximate
    multiplier model), accumulated with exact float32 addition -- this
    mirrors an FPU where the multiplier is approximated but the adder
    stays exact (the paper's recommended design point).
    """
    N, K = X.shape
    K2, M = W.shape
    assert K == K2

    out = np.zeros((N, M), dtype=np.float32)
    # K is small (<=64 here) so a simple accumulation loop over K is fine;
    # each iteration does one fully-vectorized (N,M) approximate multiply.
    for k in range(K):
        col = X[:, k:k+1].astype(np.float32)          # (N,1)
        row = W[k:k+1, :].astype(np.float32)           # (1,M)
        prod = multiply_fn(np.broadcast_to(col, (N, M)).copy(),
                            np.broadcast_to(row, (N, M)).copy(),
                            mant_bits)
        out = (out + prod).astype(np.float32)          # exact accumulate
    return out


def forward_exact(X, W1, b1, W2, b2):
    h = np.maximum(0.0, X.astype(np.float32) @ W1.astype(np.float32) + b1.astype(np.float32))
    logits = h @ W2.astype(np.float32) + b2.astype(np.float32)
    return logits


def forward_approx(X, W1, b1, W2, b2, multiply_fn, mant_bits):
    h = approx_matmul(X.astype(np.float32), W1.astype(np.float32), multiply_fn, mant_bits)
    h = np.maximum(0.0, (h + b1.astype(np.float32)).astype(np.float32))
    logits = approx_matmul(h, W2.astype(np.float32), multiply_fn, mant_bits)
    logits = (logits + b2.astype(np.float32)).astype(np.float32)
    return logits


def main():
    digits = load_digits()
    X, y = digits.data, digits.target

    scaler = StandardScaler()
    X = scaler.fit_transform(X)

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.25, random_state=42, stratify=y
    )

    clf = MLPClassifier(hidden_layer_sizes=(32,), activation='relu',
                         max_iter=2000, random_state=42)
    clf.fit(X_train, y_train)

    W1, b1 = clf.coefs_[0], clf.intercepts_[0]
    W2, b2 = clf.coefs_[1], clf.intercepts_[1]

    # sklearn baseline (float64) accuracy, for reference
    sklearn_acc = clf.score(X_test, y_test)

    # exact float32 manual forward (this is our true baseline for the
    # hardware comparison, since the approximate models are all float32)
    logits_exact = forward_exact(X_test, W1, b1, W2, b2)
    pred_exact = np.argmax(logits_exact, axis=1)
    acc_exact = np.mean(pred_exact == y_test)

    print(f"sklearn (float64) test accuracy : {sklearn_acc*100:.2f}%")
    print(f"exact float32 manual forward     : {acc_exact*100:.2f}%")
    print()

    results = []
    for mant_bits in [16, 12, 10, 8, 6, 5, 4, 3, 2]:
        logits_t = forward_approx(X_test, W1, b1, W2, b2, approx_multiply_trunc, mant_bits)
        pred_t = np.argmax(logits_t, axis=1)
        acc_t = np.mean(pred_t == y_test)
        mae_t = np.mean(np.abs(logits_t - logits_exact))

        logits_c = forward_approx(X_test, W1, b1, W2, b2, approx_multiply_comp, mant_bits)
        pred_c = np.argmax(logits_c, axis=1)
        acc_c = np.mean(pred_c == y_test)
        mae_c = np.mean(np.abs(logits_c - logits_exact))

        drop_t = (acc_exact - acc_t) * 100
        drop_c = (acc_exact - acc_c) * 100

        print(f"MANT_BITS={mant_bits:2d}  |  trunc: acc={acc_t*100:6.2f}% (drop {drop_t:+.2f}pp) logit-MAE={mae_t:.4f}"
              f"  |  comp: acc={acc_c*100:6.2f}% (drop {drop_c:+.2f}pp) logit-MAE={mae_c:.4f}")

        results.append((mant_bits, acc_t, mae_t, acc_c, mae_c))

    return acc_exact, results


if __name__ == "__main__":
    main()