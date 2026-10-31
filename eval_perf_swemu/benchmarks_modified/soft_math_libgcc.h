// Software math using libgcc functions directly
// These are the actual GCC soft-float implementations - production quality
//
// When compiled with RISC-V GCC, these symbols are provided by libgcc.a
// No compiler magic needed - just explicit function calls

#ifndef SOFT_MATH_LIBGCC_H
#define SOFT_MATH_LIBGCC_H

#ifdef __cplusplus
extern "C" {
#endif

// ============================================
// libgcc soft-float functions (IEEE 754 compliant)
// ============================================

// Single-precision division: a / b
float __divsf3(float a, float b);

// Single-precision sqrt (may need libm or custom impl)
// Note: libgcc doesn't provide __sqrtsf2, typically comes from libm
// We provide a fallback using __divsf3 + Newton-Raphson

// Integer division (32-bit)
int __divsi3(int a, int b);
unsigned int __udivsi3(unsigned int a, unsigned int b);

// Integer modulo (32-bit)
int __modsi3(int a, int b);
unsigned int __umodsi3(unsigned int a, unsigned int b);

// ============================================
// Soft sqrt using libgcc division
// libgcc doesn't have sqrt, so we implement using __divsf3
// ============================================
static inline float soft_fsqrt_libgcc(float x) {
    if (x <= 0.0f) return 0.0f;

    // Initial estimate via bit manipulation (no FP ops)
    union { float f; unsigned int i; } conv;
    conv.f = x;
    conv.i = 0x5f375a86 - (conv.i >> 1);  // Fast inverse sqrt estimate
    float y = conv.f;

    // Newton-Raphson using libgcc division
    // y_new = 0.5 * (y + x/y)
    y = 0.5f * (y + __divsf3(x, y));
    y = 0.5f * (y + __divsf3(x, y));
    y = 0.5f * (y + __divsf3(x, y));

    return y;
}

// ============================================
// Wrapper macros for benchmark compatibility
// ============================================

#ifdef USE_SOFT_FDIV
    #define FDIV(a, b) __divsf3((a), (b))
#else
    #define FDIV(a, b) ((a) / (b))
#endif

#ifdef USE_SOFT_FSQRT
    #define FSQRT(x) soft_fsqrt_libgcc(x)
#else
    #define FSQRT(x) __builtin_sqrtf(x)
#endif

#ifdef USE_SOFT_IDIV
    #define IDIV(a, b) __divsi3((a), (b))
    #define UDIV(a, b) __udivsi3((a), (b))
    #define IMOD(a, b) __modsi3((a), (b))
    #define UMOD(a, b) __umodsi3((a), (b))
#else
    #define IDIV(a, b) ((a) / (b))
    #define UDIV(a, b) ((a) / (b))
    #define IMOD(a, b) ((a) % (b))
    #define UMOD(a, b) ((a) % (b))
#endif

#ifdef __cplusplus
}
#endif

#endif // SOFT_MATH_LIBGCC_H
