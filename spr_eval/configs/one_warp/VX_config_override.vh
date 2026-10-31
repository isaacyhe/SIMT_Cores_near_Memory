// PNM SPR Evaluation - ONE WARP Configuration
// Reduces warp count from 4 to 1
//
// Rationale: Near-memory cores don't need latency hiding via
// warp scheduling since memory access latency is already low.
// Removing warp scheduling logic reduces control complexity.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// Single warp - disables warp scheduling
`define NUM_WARPS 1

// Adjust barriers accordingly
`define NUM_BARRIERS 1

// Keep other features at baseline:
// - Caches: ENABLED
// - FPU: Full
// - ALU: Full M extension

`endif // VX_CONFIG_OVERRIDE_VH
