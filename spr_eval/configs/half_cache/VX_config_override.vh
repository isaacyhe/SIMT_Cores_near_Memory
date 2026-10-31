// PNM SPR Evaluation - HALF CACHE Configuration
// L1 I-Cache and D-Cache at 8KB 4-way (half of default 16KB)
// Tests size sensitivity while keeping associativity constant

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

`define ICACHE_SIZE 8192
`define DCACHE_SIZE 8192

`endif // VX_CONFIG_OVERRIDE_VH
