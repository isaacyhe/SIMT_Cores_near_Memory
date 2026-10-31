// Software math using libgcc/compiler-rt functions directly
// For OpenCL kernels compiled via POCL → LLVM → RISC-V
//
// These extern declarations resolve at link time against:
//   libclang_rt.builtins-riscv32.a (or riscv64)
//
// If this doesn't work in your OpenCL setup, use soft_math_cl.h instead

#ifndef SOFT_MATH_CL_LIBGCC_H
#define SOFT_MATH_CL_LIBGCC_H

// ============================================
// Extern declarations for compiler-rt/libgcc functions
// These are resolved at link time
// ============================================

// Single-precision float operations
extern float __divsf3(float a, float b);
extern float __mulsf3(float a, float b);
extern float __addsf3(float a, float b);
extern float __subsf3(float a, float b);

// Integer division (32-bit)
extern int __divsi3(int a, int b);
extern unsigned int __udivsi3(unsigned int a, unsigned int b);
extern int __modsi3(int a, int b);
extern unsigned int __umodsi3(unsigned int a, unsigned int b);

// ============================================
// Sqrt: compiler-rt doesn't provide __sqrtsf2
// Use Newton-Raphson with __divsf3 for division
// ============================================
inline float soft_fsqrt_libgcc(float x) {
    if (x <= 0.0f) return 0.0f;

    // Fast inverse sqrt initial estimate
    union { float f; unsigned int i; } conv;
    conv.f = x;
    conv.i = 0x5F375A86u - (conv.i >> 1);
    float y = conv.f;

    // Newton-Raphson using __divsf3 for division
    y = 0.5f * (y + __divsf3(x, y));
    y = 0.5f * (y + __divsf3(x, y));
    y = 0.5f * (y + __divsf3(x, y));

    return y;
}

// ============================================
// Wrapper macros
// ============================================

#ifdef USE_SOFT_FDIV
    #define FDIV(a, b) __divsf3((a), (b))
#else
    #define FDIV(a, b) ((a) / (b))
#endif

#ifdef USE_SOFT_FSQRT
    #define FSQRT(x) soft_fsqrt_libgcc(x)
#else
    #define FSQRT(x) sqrt(x)
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

#endif // SOFT_MATH_CL_LIBGCC_H
