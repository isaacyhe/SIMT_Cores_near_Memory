// PNM SPR Evaluation - COMBINED PNM Configuration
// Minimal core with all simplifications applied
//
// Combines: No Cache + 1 Warp + No FP Div + No INT Div
// This represents the most aggressive PNM core design.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// ============================================
// From NO_CACHE config
// ============================================
// Disable L1 caches (I-Cache and D-Cache) and local memory
`define L1_DISABLE
`define LMEM_DISABLE

// ============================================
// From ONE_WARP config
// ============================================
// Single warp - disables warp scheduling
`define NUM_WARPS 1
`define NUM_BARRIERS 1

// ============================================
// From NO_FPDIV config
// ============================================
// Disable FP div/sqrt only (keep FMA, CVT, NCP)
`define FPU_DIVSQRT_DISABLE

// ============================================
// From NO_INTDIV config
// ============================================
// Disable INT div only (keep MUL)
`define IDIV_DISABLE

`endif // VX_CONFIG_OVERRIDE_VH
