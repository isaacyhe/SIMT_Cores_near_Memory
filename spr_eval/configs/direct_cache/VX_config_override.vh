// PNM SPR Evaluation - DIRECT-MAPPED CACHE Configuration
// L1 I-Cache and D-Cache at 16KB direct-mapped (1-way)
// Tests associativity sensitivity while keeping size constant

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

`define ICACHE_NUM_WAYS 1
`define DCACHE_NUM_WAYS 1

`endif // VX_CONFIG_OVERRIDE_VH
