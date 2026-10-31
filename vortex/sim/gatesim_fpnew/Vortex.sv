// AUTO: gate-level wrapper presenting the RTL `Vortex` SV array-port signature
// expected by rtlsim_shim, bridging to the flattened gate netlist `Vortex_gl`
// (which has flat scalar ports). Baseline config => VX_MEM_PORTS == 1.
`include "VX_define.vh"

module Vortex import VX_gpu_pkg::*; (
    // Clock
    input  wire                             clk,
    input  wire                             reset,

    // Memory request
    output wire                             mem_req_valid [VX_MEM_PORTS],
    output wire                             mem_req_rw [VX_MEM_PORTS],
    output wire [VX_MEM_BYTEEN_WIDTH-1:0]   mem_req_byteen [VX_MEM_PORTS],
    output wire [VX_MEM_ADDR_WIDTH-1:0]     mem_req_addr [VX_MEM_PORTS],
    output wire [VX_MEM_DATA_WIDTH-1:0]     mem_req_data [VX_MEM_PORTS],
    output wire [VX_MEM_TAG_WIDTH-1:0]      mem_req_tag [VX_MEM_PORTS],
    input  wire                             mem_req_ready [VX_MEM_PORTS],

    // Memory response
    input wire                              mem_rsp_valid [VX_MEM_PORTS],
    input wire [VX_MEM_DATA_WIDTH-1:0]      mem_rsp_data [VX_MEM_PORTS],
    input wire [VX_MEM_TAG_WIDTH-1:0]       mem_rsp_tag [VX_MEM_PORTS],
    output wire                             mem_rsp_ready [VX_MEM_PORTS],

    // DCR write request
    input  wire                             dcr_wr_valid,
    input  wire [VX_DCR_ADDR_WIDTH-1:0]     dcr_wr_addr,
    input  wire [VX_DCR_DATA_WIDTH-1:0]     dcr_wr_data,

    // Status
    output wire                             busy
);
    // VX_MEM_PORTS == 1 for baseline: bridge unpacked-array element [0] to the
    // gate netlist's flat ports. A config that changes VX_MEM_PORTS would trip
    // a width mismatch here -- an intentional build-time guard.
    Vortex_gl gl (
        .clk            (clk),
        .reset          (reset),

        .mem_req_valid  (mem_req_valid[0]),
        .mem_req_rw     (mem_req_rw[0]),
        .mem_req_byteen (mem_req_byteen[0]),
        .mem_req_addr   (mem_req_addr[0]),
        .mem_req_data   (mem_req_data[0]),
        .mem_req_tag    (mem_req_tag[0]),
        .mem_req_ready  (mem_req_ready[0]),

        .mem_rsp_valid  (mem_rsp_valid[0]),
        .mem_rsp_data   (mem_rsp_data[0]),
        .mem_rsp_tag    (mem_rsp_tag[0]),
        .mem_rsp_ready  (mem_rsp_ready[0]),

        .dcr_wr_valid   (dcr_wr_valid),
        .dcr_wr_addr    (dcr_wr_addr),
        .dcr_wr_data    (dcr_wr_data),

        .busy           (busy)
    );
endmodule
