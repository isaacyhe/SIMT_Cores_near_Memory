// PNM SPR Evaluation - QUARTER CACHE Configuration
// L1 I-Cache and D-Cache at 4KB 4-way (quarter of default 16KB)
// Tests size sensitivity while keeping associativity constant

`ifndef VX_CONFIG_OVERRIDE_VH
`define VX_CONFIG_OVERRIDE_VH

`define ICACHE_SIZE 4096
`define DCACHE_SIZE 4096

`endif // VX_CONFIG_OVERRIDE_VH
