// CAL extension (Oct 2026): scalar 8-warp core, caches and scratchpad removed
`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH
`define NUM_THREADS 1
`define NUM_WARPS 8
`define L1_DISABLE
`define LMEM_DISABLE
`endif // VX_CONFIG_OVERRIDE_VH
