// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

`include "VX_define.vh"

module VX_mem_unit import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = ""
) (
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output lmem_perf_t      lmem_perf,
    output coalescer_perf_t coalescer_perf,
`endif

    VX_lsu_mem_if.slave     lsu_mem_if [`NUM_LSU_BLOCKS],
    VX_mem_bus_if.master    dcache_bus_if [DCACHE_NUM_REQS]
);
    VX_lsu_mem_if #(
        .NUM_LANES (`NUM_LSU_LANES),
        .DATA_SIZE (LSU_WORD_SIZE),
        .TAG_WIDTH (LSU_TAG_WIDTH)
    ) lsu_dcache_if[`NUM_LSU_BLOCKS]();

`ifdef LMEM_ENABLE

    `STATIC_ASSERT(`IS_DIVISBLE((1 << `LMEM_LOG_SIZE), `MEM_BLOCK_SIZE), ("invalid parameter"))
    `STATIC_ASSERT(0 == (`LMEM_BASE_ADDR % (1 << `LMEM_LOG_SIZE)), ("invalid parameter"))

    localparam LMEM_ADDR_WIDTH = `LMEM_LOG_SIZE - `CLOG2(LSU_WORD_SIZE);

    VX_lsu_mem_if #(
        .NUM_LANES (`NUM_LSU_LANES),
        .DATA_SIZE (LSU_WORD_SIZE),
        .TAG_WIDTH (LSU_TAG_WIDTH)
    ) lsu_lmem_if[`NUM_LSU_BLOCKS]();

    for (genvar i = 0; i < `NUM_LSU_BLOCKS; ++i) begin : g_lmem_switches
        VX_lmem_switch #(
            .GLOBAL_OUT_BUF(1),
            .LOCAL_OUT_BUF(1),
            .RSP_OUT_BUF  (1),
            .ARBITER      ("P")
        ) lmem_switch (
            .clk          (clk),
            .reset        (reset),
            .lsu_in_if    (lsu_mem_if[i]),
            .global_out_if(lsu_dcache_if[i]),
            .local_out_if (lsu_lmem_if[i])
        );
    end

    VX_lsu_mem_if #(
        .NUM_LANES (`NUM_LSU_LANES),
        .DATA_SIZE (LSU_WORD_SIZE),
        .TAG_WIDTH (LMEM_TAG_WIDTH)
    ) lmem_arb_if[1]();

    VX_lsu_mem_arb #(
        .NUM_INPUTS (`NUM_LSU_BLOCKS),
        .NUM_OUTPUTS(1),
        .NUM_LANES  (`NUM_LSU_LANES),
        .DATA_SIZE  (LSU_WORD_SIZE),
        .TAG_WIDTH  (LSU_TAG_WIDTH),
        .TAG_SEL_IDX(0),
        .ARBITER    ("R"),
        .REQ_OUT_BUF(0),
        .RSP_OUT_BUF(2)
    ) lmem_arb (
        .clk        (clk),
        .reset      (reset),
        .bus_in_if  (lsu_lmem_if),
        .bus_out_if (lmem_arb_if)
    );

    VX_mem_bus_if #(
        .DATA_SIZE (LSU_WORD_SIZE),
        .TAG_WIDTH (LMEM_TAG_WIDTH)
    ) lmem_adapt_if[`NUM_LSU_LANES]();

    VX_lsu_adapter #(
        .NUM_LANES    (`NUM_LSU_LANES),
        .DATA_SIZE    (LSU_WORD_SIZE),
        .TAG_WIDTH    (LMEM_TAG_WIDTH),
        .TAG_SEL_BITS (LMEM_TAG_WIDTH - UUID_WIDTH),
        .ARBITER      ("P"),
        .REQ_OUT_BUF  (3),
        .RSP_OUT_BUF  (0)
    ) lmem_adapter (
        .clk        (clk),
        .reset      (reset),
        .lsu_mem_if (lmem_arb_if[0]),
        .mem_bus_if (lmem_adapt_if)
    );

    VX_local_mem #(
        .INSTANCE_ID(`SFORMATF(("%s-lmem", INSTANCE_ID))),
        .SIZE       (1 << `LMEM_LOG_SIZE),
        .NUM_REQS   (`NUM_LSU_LANES),
        .NUM_BANKS  (`LMEM_NUM_BANKS),
        .WORD_SIZE  (LSU_WORD_SIZE),
        .ADDR_WIDTH (LMEM_ADDR_WIDTH),
        .TAG_WIDTH  (LMEM_TAG_WIDTH),
        .OUT_BUF    (3)
    ) local_mem (
        .clk        (clk),
        .reset      (reset),
    `ifdef PERF_ENABLE
        .lmem_perf  (lmem_perf),
    `endif
        .mem_bus_if (lmem_adapt_if)
    );

`else

`ifdef PERF_ENABLE
    assign lmem_perf = '0;
`endif

    for (genvar i = 0; i < `NUM_LSU_BLOCKS; ++i) begin : g_lsu_dcache_if
        `ASSIGN_VX_MEM_BUS_IF (lsu_dcache_if[i], lsu_mem_if[i]);
    end

`endif

    VX_lsu_mem_if #(
        .NUM_LANES (DCACHE_CHANNELS),
        .DATA_SIZE (DCACHE_WORD_SIZE),
        .TAG_WIDTH (DCACHE_TAG_WIDTH)
    ) dcache_coalesced_if[`NUM_LSU_BLOCKS]();

`ifdef PERF_ENABLE
    wire [`NUM_LSU_BLOCKS-1:0][PERF_CTR_BITS-1:0] per_block_coalescer_misses;
    wire [PERF_CTR_BITS-1:0] coalescer_misses;
    VX_reduce_tree #(
        .IN_W (PERF_CTR_BITS),
        .N    (`NUM_LSU_BLOCKS),
        .OP   ("+")
    ) coalescer_reduce (
        .data_in  (per_block_coalescer_misses),
        .data_out (coalescer_misses)
    );
    `BUFFER(coalescer_perf.misses, coalescer_misses);
`endif

    if ((`NUM_LSU_LANES > 1) && (LSU_WORD_SIZE != DCACHE_WORD_SIZE)) begin : g_enabled

        for (genvar i = 0; i < `NUM_LSU_BLOCKS; ++i) begin : g_coalescers
            VX_mem_coalescer #(
                .INSTANCE_ID    (`SFORMATF(("%s-coalescer%0d", INSTANCE_ID, i))),
                .NUM_REQS       (`NUM_LSU_LANES),
                .DATA_IN_SIZE   (LSU_WORD_SIZE),
                .DATA_OUT_SIZE  (DCACHE_WORD_SIZE),
                .ADDR_WIDTH     (LSU_ADDR_WIDTH),
                .FLAGS_WIDTH    (MEM_FLAGS_WIDTH),
                .TAG_WIDTH      (LSU_TAG_WIDTH),
                .UUID_WIDTH     (UUID_WIDTH),
                .QUEUE_SIZE     (`LSUQ_OUT_SIZE),
                .PERF_CTR_BITS  (PERF_CTR_BITS)
            ) mem_coalescer (
                .clk            (clk),
                .reset          (reset),

            `ifdef PERF_ENABLE
                .misses         (per_block_coalescer_misses[i]),
            `else
                `UNUSED_PIN (misses),
            `endif

                // Input request
                .in_req_valid   (lsu_dcache_if[i].req_valid),
                .in_req_mask    (lsu_dcache_if[i].req_data.mask),
                .in_req_rw      (lsu_dcache_if[i].req_data.rw),
                .in_req_byteen  (lsu_dcache_if[i].req_data.byteen),
                .in_req_addr    (lsu_dcache_if[i].req_data.addr),
                .in_req_flags   (lsu_dcache_if[i].req_data.flags),
                .in_req_data    (lsu_dcache_if[i].req_data.data),
                .in_req_tag     (lsu_dcache_if[i].req_data.tag),
                .in_req_ready   (lsu_dcache_if[i].req_ready),

                // Input response
                .in_rsp_valid   (lsu_dcache_if[i].rsp_valid),
                .in_rsp_mask    (lsu_dcache_if[i].rsp_data.mask),
                .in_rsp_data    (lsu_dcache_if[i].rsp_data.data),
                .in_rsp_tag     (lsu_dcache_if[i].rsp_data.tag),
                .in_rsp_ready   (lsu_dcache_if[i].rsp_ready),

                // Output request
                .out_req_valid  (dcache_coalesced_if[i].req_valid),
                .out_req_mask   (dcache_coalesced_if[i].req_data.mask),
                .out_req_rw     (dcache_coalesced_if[i].req_data.rw),
                .out_req_byteen (dcache_coalesced_if[i].req_data.byteen),
                .out_req_addr   (dcache_coalesced_if[i].req_data.addr),
                .out_req_flags  (dcache_coalesced_if[i].req_data.flags),
                .out_req_data   (dcache_coalesced_if[i].req_data.data),
                .out_req_tag    (dcache_coalesced_if[i].req_data.tag),
                .out_req_ready  (dcache_coalesced_if[i].req_ready),

                // Output response
                .out_rsp_valid  (dcache_coalesced_if[i].rsp_valid),
                .out_rsp_mask   (dcache_coalesced_if[i].rsp_data.mask),
                .out_rsp_data   (dcache_coalesced_if[i].rsp_data.data),
                .out_rsp_tag    (dcache_coalesced_if[i].rsp_data.tag),
                .out_rsp_ready  (dcache_coalesced_if[i].rsp_ready)
            );
        end

    end else begin : g_passthru

        for (genvar i = 0; i < `NUM_LSU_BLOCKS; ++i) begin : g_dcache_coalesced_if
            `ASSIGN_VX_MEM_BUS_IF (dcache_coalesced_if[i], lsu_dcache_if[i]);
        `ifdef PERF_ENABLE
            assign per_block_coalescer_misses[i] = '0;
        `endif
        end

    end

    for (genvar i = 0; i < `NUM_LSU_BLOCKS; ++i) begin : g_dcache_adapters

        VX_mem_bus_if #(
            .DATA_SIZE (DCACHE_WORD_SIZE),
            .TAG_WIDTH (DCACHE_TAG_WIDTH)
        ) dcache_bus_tmp_if[DCACHE_CHANNELS]();

        VX_lsu_adapter #(
            .NUM_LANES    (DCACHE_CHANNELS),
            .DATA_SIZE    (DCACHE_WORD_SIZE),
            .TAG_WIDTH    (DCACHE_TAG_WIDTH),
            .TAG_SEL_BITS (DCACHE_TAG_WIDTH - UUID_WIDTH),
            .ARBITER      ("P"),
            .REQ_OUT_BUF  (0),
            .RSP_OUT_BUF  (0)
        ) dcache_adapter (
            .clk        (clk),
            .reset      (reset),
            .lsu_mem_if (dcache_coalesced_if[i]),
            .mem_bus_if (dcache_bus_tmp_if)
        );

        for (genvar j = 0; j < DCACHE_CHANNELS; ++j) begin : g_dcache_bus_if
            `ASSIGN_VX_MEM_BUS_IF (dcache_bus_if[i * DCACHE_CHANNELS + j], dcache_bus_tmp_if[j]);
        end

    end

`ifndef SYNTHESIS
    // GPU_and_PNM (CAL per-run energy): LSU memory requests per block (sim-only): warp requests and active lanes, split
    // read/write, and lanes addressed to local memory.
    for (genvar i = 0; i < `NUM_LSU_BLOCKS; ++i) begin : g_sim_ctrs
        wire ctr_fire = lsu_mem_if[i].req_valid && lsu_mem_if[i].req_ready;
        wire ctr_rw = lsu_mem_if[i].req_data.rw;
        wire [`NUM_LSU_LANES-1:0] ctr_local;
        for (genvar l = 0; l < `NUM_LSU_LANES; ++l) begin : g_local
        `ifdef LMEM_ENABLE
            assign ctr_local[l] = lsu_mem_if[i].req_data.flags[l][MEM_REQ_FLAG_LOCAL];
        `else
            assign ctr_local[l] = 1'b0;
        `endif
        end
        wire [7:0] ctr_lanes = 8'($countones(lsu_mem_if[i].req_data.mask));
        VX_sim_ctrs #(
            .N (5), .W (8),
            .NAMES ("lsu_req_rd,lsu_req_wr,lsu_lanes_rd,lsu_lanes_wr,lsu_lanes_local")
        ) sim_ctrs (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'(ctr_fire ? $countones(lsu_mem_if[i].req_data.mask & ctr_local) : 0),
                     8'(ctr_fire && ctr_rw ? ctr_lanes : 8'd0),
                     8'(ctr_fire && !ctr_rw ? ctr_lanes : 8'd0),
                     8'(ctr_fire && ctr_rw),
                     8'(ctr_fire && !ctr_rw)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): LSU data-bus bit flips per transfer (sim-only), same rule as the other
        // sim_tgl groups: request addresses (every request), store data (writes), load-response data (responses). Added after
        // the activity test left the LSU (and histogram, with random bin addresses) under-predicted.
        wire tgl_wr  = ctr_fire && ctr_rw;
        wire tgl_rsp = lsu_mem_if[i].rsp_valid && lsu_mem_if[i].rsp_ready;
        reg [$bits(lsu_mem_if[i].req_data.addr)-1:0] tgl_addr_last = '0;
        reg [$bits(lsu_mem_if[i].req_data.data)-1:0] tgl_wdata_last = '0;
        reg [$bits(lsu_mem_if[i].rsp_data.data)-1:0] tgl_rdata_last = '0;
        always @(posedge clk) begin
            if (ctr_fire) tgl_addr_last  <= lsu_mem_if[i].req_data.addr;
            if (tgl_wr)   tgl_wdata_last <= lsu_mem_if[i].req_data.data;
            if (tgl_rsp)  tgl_rdata_last <= lsu_mem_if[i].rsp_data.data;
        end
        VX_sim_ctrs #(
            .N (3), .W (16),
            .NAMES ("lsu_addr_flips,lsu_wdata_flips,lsu_rdata_flips")
        ) sim_tgl (
            .clk   (clk),
            .reset (reset),
            .inc   ({16'(tgl_rsp ? $countones(lsu_mem_if[i].rsp_data.data ^ tgl_rdata_last) : 0),
                     16'(tgl_wr ? $countones(lsu_mem_if[i].req_data.data ^ tgl_wdata_last) : 0),
                     16'(ctr_fire ? $countones(lsu_mem_if[i].req_data.addr ^ tgl_addr_last) : 0)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
        // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
        reg [$bits(lsu_mem_if[i].req_data.addr)-1:0] tgl_c0_q = '0;
        reg [$bits(lsu_mem_if[i].req_data.data)-1:0] tgl_c1_q = '0;
        reg [$bits(lsu_mem_if[i].rsp_data.data)-1:0] tgl_c2_q = '0;
        always @(posedge clk) begin
            tgl_c0_q <= lsu_mem_if[i].req_data.addr;
            tgl_c1_q <= lsu_mem_if[i].req_data.data;
            tgl_c2_q <= lsu_mem_if[i].rsp_data.data;
        end
        VX_sim_ctrs #(
            .N (3), .W (16),
            .NAMES ("lsu_addr_cyc,lsu_wdata_cyc,lsu_rdata_cyc")
        ) sim_cyc (
            .clk   (clk),
            .reset (reset),
            .inc   ({16'($countones(lsu_mem_if[i].rsp_data.data ^ tgl_c2_q)),
                     16'($countones(lsu_mem_if[i].req_data.data ^ tgl_c1_q)),
                     16'($countones(lsu_mem_if[i].req_data.addr ^ tgl_c0_q))})
        );
    `ifdef LMEM_ENABLE
        // GPU_and_PNM (CAL per-run energy, Oct 26): the same flips on the local-memory side of the switch (lsu_lmem_if: switch
        // output, arbiter, adapter buffers), which toggled ~3x its usual rate on bs and left the LSU under-predicted there.
        wire tgl_l_fire = lsu_lmem_if[i].req_valid && lsu_lmem_if[i].req_ready;
        wire tgl_l_wr   = tgl_l_fire && lsu_lmem_if[i].req_data.rw;
        wire tgl_l_rsp  = lsu_lmem_if[i].rsp_valid && lsu_lmem_if[i].rsp_ready;
        reg [$bits(lsu_lmem_if[i].req_data.addr)-1:0] tgl_l_addr_last = '0;
        reg [$bits(lsu_lmem_if[i].req_data.data)-1:0] tgl_l_wdata_last = '0;
        reg [$bits(lsu_lmem_if[i].rsp_data.data)-1:0] tgl_l_rdata_last = '0;
        always @(posedge clk) begin
            if (tgl_l_fire) tgl_l_addr_last  <= lsu_lmem_if[i].req_data.addr;
            if (tgl_l_wr)   tgl_l_wdata_last <= lsu_lmem_if[i].req_data.data;
            if (tgl_l_rsp)  tgl_l_rdata_last <= lsu_lmem_if[i].rsp_data.data;
        end
        VX_sim_ctrs #(
            .N (3), .W (16),
            .NAMES ("lpath_addr_flips,lpath_wdata_flips,lpath_rdata_flips")
        ) sim_tgl_lmem (
            .clk   (clk),
            .reset (reset),
            .inc   ({16'(tgl_l_rsp ? $countones(lsu_lmem_if[i].rsp_data.data ^ tgl_l_rdata_last) : 0),
                     16'(tgl_l_wr ? $countones(lsu_lmem_if[i].req_data.data ^ tgl_l_wdata_last) : 0),
                     16'(tgl_l_fire ? $countones(lsu_lmem_if[i].req_data.addr ^ tgl_l_addr_last) : 0)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
        // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
        reg [$bits(lsu_lmem_if[i].req_data.addr)-1:0] tgl_lc0_q = '0;
        reg [$bits(lsu_lmem_if[i].req_data.data)-1:0] tgl_lc1_q = '0;
        reg [$bits(lsu_lmem_if[i].rsp_data.data)-1:0] tgl_lc2_q = '0;
        always @(posedge clk) begin
            tgl_lc0_q <= lsu_lmem_if[i].req_data.addr;
            tgl_lc1_q <= lsu_lmem_if[i].req_data.data;
            tgl_lc2_q <= lsu_lmem_if[i].rsp_data.data;
        end
        VX_sim_ctrs #(
            .N (3), .W (16),
            .NAMES ("lpath_addr_cyc,lpath_wdata_cyc,lpath_rdata_cyc")
        ) sim_cyc_lmem (
            .clk   (clk),
            .reset (reset),
            .inc   ({16'($countones(lsu_lmem_if[i].rsp_data.data ^ tgl_lc2_q)),
                     16'($countones(lsu_lmem_if[i].req_data.data ^ tgl_lc1_q)),
                     16'($countones(lsu_lmem_if[i].req_data.addr ^ tgl_lc0_q))})
        );
    `endif
    end
`endif

endmodule
