/* sqrtf - IEEE 754 compliant square root
 * Based on Sun Microsystems fdlibm (Freely Distributable LIBM)
 *
 * ====================================================
 * Copyright (C) 1993 by Sun Microsystems, Inc. All rights reserved.
 *
 * Developed at SunPro, a Sun Microsystems, Inc. business.
 * Permission to use, copy, modify, and distribute this
 * software is freely granted, provided that this notice
 * is preserved.
 * ====================================================
 */

#include <stdint.h>

/* IEEE 754 bit manipulation macros */
typedef union {
    float f;
    uint32_t i;
} float_bits;

#define GET_FLOAT_WORD(iw, xf) do { float_bits _fb; _fb.f = (xf); (iw) = (int32_t)_fb.i; } while(0)
#define SET_FLOAT_WORD(xf, iw) do { float_bits _fb; _fb.i = (uint32_t)(iw); (xf) = _fb.f; } while(0)

/* IEEE 754 special value checks */
#define FLT_UWORD_IS_FINITE(x) ((x) < 0x7f800000)
#define FLT_UWORD_IS_ZERO(x) ((x) == 0)
#define FLT_UWORD_IS_SUBNORMAL(x) ((x) < 0x00800000)

static const volatile float one = 1.0f, tiny = 1.0e-30f;

float __ieee754_sqrtf(float x)
{
    float z;
    uint32_t r, hx;
    int32_t ix, s, q, m, t, i;

    GET_FLOAT_WORD(ix, x);
    hx = ix & 0x7fffffff;

    /* take care of Inf and NaN */
    if (!FLT_UWORD_IS_FINITE(hx))
        return x * x + x;  /* sqrt(NaN)=NaN, sqrt(+inf)=+inf, sqrt(-inf)=sNaN */

    /* take care of zero and -ves */
    if (FLT_UWORD_IS_ZERO(hx)) return x;  /* sqrt(+-0) = +-0 */
    if (ix < 0) return (x - x) / (x - x);  /* sqrt(-ve) = sNaN */

    /* normalize x */
    m = (ix >> 23);
    if (FLT_UWORD_IS_SUBNORMAL(hx)) {  /* subnormal x */
        for (i = 0; (ix & 0x00800000L) == 0; i++) ix <<= 1;
        m -= i - 1;
    }
    m -= 127;  /* unbias exponent */
    ix = (ix & 0x007fffffL) | 0x00800000L;
    if (m & 1)  /* odd m, double x to make it even */
        ix += ix;
    m >>= 1;  /* m = [m/2] */

    /* generate sqrt(x) bit by bit */
    ix += ix;
    q = s = 0;       /* q = sqrt(x) */
    r = 0x01000000L; /* r = moving bit from right to left */

    while (r != 0) {
        t = s + r;
        if (t <= ix) {
            s = t + r;
            ix -= t;
            q += r;
        }
        ix += ix;
        r >>= 1;
    }

    /* use floating add to find out rounding direction */
    if (ix != 0) {
        z = one - tiny;  /* trigger inexact flag */
        if (z >= one) {
            z = one + tiny;
            if (z > one)
                q += 2;
            else
                q += (q & 1);
        }
    }
    ix = (q >> 1) + 0x3f000000L;
    ix += (m << 23);
    SET_FLOAT_WORD(z, ix);
    return z;
}

/* Wrapper for standard name */
float sqrtf(float x) {
    return __ieee754_sqrtf(x);
}
