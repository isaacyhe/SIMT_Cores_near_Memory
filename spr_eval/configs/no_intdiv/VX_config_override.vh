// PNM SPR Evaluation - NO INT DIV Configuration
// Removes only integer division hardware (keeps MUL)
//
// Rationale: Integer division is rarely used in memory-bound
// kernels. MUL is still useful for address calculations.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// Disable only integer DIV (keep MUL)
`define IDIV_DISABLE

// Keep other features at baseline:
// - Caches: ENABLED
// - Warps: 4
// - FPU: Full F extension
// - MUL: ENABLED

`endif // VX_CONFIG_OVERRIDE_VH
