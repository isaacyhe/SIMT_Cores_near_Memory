// PNM SPR Evaluation - 2-WAY CACHE Configuration
// L1 I-Cache and D-Cache at 16KB 2-way (reduced from default 4-way)
// Tests associativity sensitivity while keeping size constant

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

`define ICACHE_NUM_WAYS 2
`define DCACHE_NUM_WAYS 2

`endif // VX_CONFIG_OVERRIDE_VH
