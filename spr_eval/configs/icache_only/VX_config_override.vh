// PNM SPR Evaluation - I-CACHE ONLY Configuration
// L1 I-Cache at 16KB 4-way (default), D-Cache disabled
// Tests the effect of having only instruction cache

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

`define DCACHE_DISABLE

`endif // VX_CONFIG_OVERRIDE_VH
