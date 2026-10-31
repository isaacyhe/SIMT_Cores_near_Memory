// PNM SPR Evaluation - NO CACHE Configuration
// Removes all L1 caches and local memory
//
// Rationale: Near-memory cores have low-latency access to memory,
// making caches less beneficial while consuming significant area.

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

// Disable L1 caches (I-Cache and D-Cache)
`define L1_DISABLE

// Keep local memory (scratchpad) - useful for explicit data reuse

// Keep other features at baseline:
// - Warps: 4 (default)
// - FPU: Full
// - ALU: Full M extension

`endif // VX_CONFIG_OVERRIDE_VH
