// PNM SPR Evaluation - BASELINE Configuration
// Full Vortex GPU core (reference)
//
// This is the baseline configuration with all features enabled.
// No overrides - uses default VX_config.vh settings.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// Baseline: No changes from default
// - Caches: ENABLED (I-Cache, D-Cache, Local Memory)
// - Warps: 4 (default)
// - FPU: Full (including DIV/SQRT)
// - ALU: Full M extension (MUL/DIV)

`endif // VX_CONFIG_OVERRIDE_VH
