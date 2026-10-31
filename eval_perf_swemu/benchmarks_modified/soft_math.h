// Software emulation for FP div/sqrt and INT div
// Used for PNM performance evaluation - models SW library overhead
//
// These replace hardware div/sqrt with iterative software implementations
// to measure performance impact of removing divider hardware.

#ifndef SOFT_MATH_H
#define SOFT_MATH_H

// ============================================
// Software Float Division (Newton-Raphson)
// Models ~15x slowdown vs hardware fdiv
// ============================================
inline float soft_fdiv(float a, float b) {
    // Newton-Raphson division: a/b = a * (1/b)
    // Initial estimate using bit manipulation
    union { float f; unsigned int i; } conv;
    conv.f = b;
    conv.i = 0x7EF311C3 - conv.i;  // Initial 1/b estimate
    float x = conv.f;

    // 3 Newton-Raphson iterations for float precision
    x = x * (2.0f - b * x);
    x = x * (2.0f - b * x);
    x = x * (2.0f - b * x);

    return a * x;
}

// ============================================
// Software Float Square Root (Newton-Raphson)
// Models ~15x slowdown vs hardware fsqrt
// ============================================
inline float soft_fsqrt(float x) {
    if (x <= 0.0f) return 0.0f;

    // Initial estimate using bit manipulation (fast inverse sqrt trick)
    union { float f; unsigned int i; } conv;
    conv.f = x;
    conv.i = 0x5f3759df - (conv.i >> 1);  // Initial 1/sqrt(x) estimate
    float y = conv.f;

    // 3 Newton-Raphson iterations for sqrt
    y = y * (1.5f - 0.5f * x * y * y);
    y = y * (1.5f - 0.5f * x * y * y);
    y = y * (1.5f - 0.5f * x * y * y);

    return x * y;  // sqrt(x) = x * (1/sqrt(x))
}

// ============================================
// Software Integer Division (shift-subtract)
// Models ~5x slowdown vs hardware idiv
// ============================================
inline int soft_idiv(int dividend, int divisor) {
    if (divisor == 0) return 0;

    int sign = 1;
    if (dividend < 0) { dividend = -dividend; sign = -sign; }
    if (divisor < 0) { divisor = -divisor; sign = -sign; }

    unsigned int udividend = (unsigned int)dividend;
    unsigned int udivisor = (unsigned int)divisor;
    unsigned int quotient = 0;

    // Binary long division
    for (int i = 31; i >= 0; i--) {
        if ((udividend >> i) >= udivisor) {
            quotient |= (1u << i);
            udividend -= (udivisor << i);
        }
    }

    return sign * (int)quotient;
}

inline int soft_imod(int dividend, int divisor) {
    return dividend - soft_idiv(dividend, divisor) * divisor;
}

inline unsigned int soft_udiv(unsigned int dividend, unsigned int divisor) {
    if (divisor == 0) return 0;

    unsigned int quotient = 0;
    for (int i = 31; i >= 0; i--) {
        if ((dividend >> i) >= divisor) {
            quotient |= (1u << i);
            dividend -= (divisor << i);
        }
    }
    return quotient;
}

inline unsigned int soft_umod(unsigned int dividend, unsigned int divisor) {
    return dividend - soft_udiv(dividend, divisor) * divisor;
}

#endif // SOFT_MATH_H
