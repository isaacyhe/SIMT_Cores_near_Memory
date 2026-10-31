// PNM SPR Evaluation - NO NUMERIC DIVIDERS Configuration
// Removes FP div/sqrt and INT div (keeps FP FMA and INT MUL)
//
// Rationale: Division operations are expensive and rarely used.
// Keep multiply operations for general computation.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// Disable FP div/sqrt (keep FMA, CVT, NCP)
`define FPU_DIVSQRT_DISABLE

// Disable INT div (keep MUL)
`define IDIV_DISABLE

// Keep other features at baseline:
// - Caches: ENABLED
// - Warps: 4
// - FPU FMA/CVT/NCP: ENABLED
// - MUL: ENABLED

`endif // VX_CONFIG_OVERRIDE_VH
