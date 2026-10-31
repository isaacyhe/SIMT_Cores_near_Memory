// PNM SPR Evaluation - NO FP DIV/SQRT Configuration
// Removes only FPU division and square root hardware
//
// Rationale: FP div/sqrt are expensive but rarely used in
// memory-bound PNM workloads. Keep FP add/mul for general use.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// Disable only FP div/sqrt (keep FMA, CVT, NCP)
`define FPU_DIVSQRT_DISABLE

// Keep other features at baseline:
// - Caches: ENABLED
// - Warps: 4
// - FPU FMA/CVT/NCP: ENABLED
// - ALU: Full M extension (MUL/DIV)

`endif // VX_CONFIG_OVERRIDE_VH
