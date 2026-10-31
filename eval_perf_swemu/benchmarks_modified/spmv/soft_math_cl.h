// Software emulation for FP div/sqrt and INT div - OpenCL version
// FP: Uses bit manipulation for initial estimates (self-contained, no external deps)
// INT: Uses compiler-rt builtins (linked via POCL_VORTEX_LDFLAGS)
//
// Activated by: -DUSE_SOFT_FDIV, -DUSE_SOFT_FSQRT, -DUSE_SOFT_IDIV

#ifndef SOFT_MATH_CL_H
#define SOFT_MATH_CL_H

// ============================================
// Software Float Division (Newton-Raphson)
// ============================================
inline float soft_fdiv(float a, float b) {
    volatile float vb = b;
    union { float f; unsigned int i; } conv;
    conv.f = vb;
    conv.i = 0x7EF311C3u - conv.i;
    float x = conv.f;
    x = x * (2.0f - vb * x);
    x = x * (2.0f - vb * x);
    x = x * (2.0f - vb * x);
    return a * x;
}

// ============================================
// Software Float Square Root (Newton-Raphson)
// ============================================
inline float soft_fsqrt(float x) {
    if (x <= 0.0f) return 0.0f;
    union { float f; unsigned int i; } conv;
    conv.f = x;
    conv.i = 0x5F375A86u - (conv.i >> 1);
    volatile float y = conv.f;
    float xhalf = 0.5f * x;
    y = y * (1.5f - xhalf * y * y);
    y = y * (1.5f - xhalf * y * y);
    y = y * (1.5f - xhalf * y * y);
    return x * y;
}

// ============================================
// Software Unsigned Integer Division (binary long division)
// ============================================
inline unsigned int soft_udiv(unsigned int n, unsigned int d) {
    if (d == 0) return 0;
    unsigned int q = 0, r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) { r -= d; q |= (1u << i); }
    }
    return q;
}

inline unsigned int soft_umod(unsigned int n, unsigned int d) {
    if (d == 0) return 0;
    unsigned int r = 0;
    for (int i = 31; i >= 0; i--) {
        r = (r << 1) | ((n >> i) & 1u);
        if (r >= d) r -= d;
    }
    return r;
}

inline int soft_idiv(int a, int b) {
    if (b == 0) return 0;
    unsigned int ua = (a < 0) ? (unsigned int)(-a) : (unsigned int)a;
    unsigned int ub = (b < 0) ? (unsigned int)(-b) : (unsigned int)b;
    unsigned int q = soft_udiv(ua, ub);
    return ((a ^ b) < 0) ? -(int)q : (int)q;
}

inline int soft_imod(int a, int b) {
    if (b == 0) return 0;
    unsigned int ua = (a < 0) ? (unsigned int)(-a) : (unsigned int)a;
    unsigned int ub = (b < 0) ? (unsigned int)(-b) : (unsigned int)b;
    unsigned int r = soft_umod(ua, ub);
    return (a < 0) ? -(int)r : (int)r;
}

// ============================================
// Macros
// ============================================
#ifdef USE_SOFT_FDIV
    #define FDIV(a, b) soft_fdiv((a), (b))
#else
    #define FDIV(a, b) ((a) / (b))
#endif

#ifdef USE_SOFT_FSQRT
    #define FSQRT(x) soft_fsqrt(x)
#else
    #define FSQRT(x) sqrt(x)
#endif

#ifdef USE_SOFT_IDIV
    #define IDIV(a, b) soft_idiv((a), (b))
    #define UDIV(a, b) soft_udiv((a), (b))
    #define IMOD(a, b) soft_imod((a), (b))
    #define UMOD(a, b) soft_umod((a), (b))
#else
    #define IDIV(a, b) ((a) / (b))
    #define UDIV(a, b) ((a) / (b))
    #define IMOD(a, b) ((a) % (b))
    #define UMOD(a, b) ((a) % (b))
#endif

#endif // SOFT_MATH_CL_H
