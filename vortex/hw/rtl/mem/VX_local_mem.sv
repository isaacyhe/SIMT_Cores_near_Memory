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

module VX_local_mem import VX_gpu_pkg::*; #(
    parameter `STRING  INSTANCE_ID = "",

    // Size of cache in bytes
    parameter SIZE              = (1024*16*8),

    // Number of Word requests per cycle
    parameter NUM_REQS          = 4,
    // Number of banks
    parameter NUM_BANKS         = 4,

    // Address width
    parameter ADDR_WIDTH        = `CLOG2(SIZE),
    // Size of a word in bytes
    parameter WORD_SIZE         = `XLEN/8,

    // Request tag size
    parameter TAG_WIDTH         = 16,

    // Response buffer
    parameter OUT_BUF           = 0
 ) (
    input wire clk,
    input wire reset,

    // PERF
`ifdef PERF_ENABLE
    output lmem_perf_t lmem_perf,
`endif

    VX_mem_bus_if.slave mem_bus_if [NUM_REQS]
);
    `UNUSED_SPARAM (INSTANCE_ID)

    localparam REQ_SEL_BITS    = `CLOG2(NUM_REQS);
    localparam REQ_SEL_WIDTH   = `UP(REQ_SEL_BITS);
    localparam WORD_WIDTH      = WORD_SIZE * 8;
    localparam NUM_WORDS       = SIZE / WORD_SIZE;
    localparam WORDS_PER_BANK  = NUM_WORDS / NUM_BANKS;
    localparam BANK_ADDR_WIDTH = `CLOG2(WORDS_PER_BANK);
    localparam BANK_SEL_BITS   = `CLOG2(NUM_BANKS);
    localparam BANK_SEL_WIDTH  = `UP(BANK_SEL_BITS);
    localparam REQ_DATAW       = 1 + BANK_ADDR_WIDTH + WORD_SIZE + WORD_WIDTH + TAG_WIDTH;
    localparam RSP_DATAW       = WORD_WIDTH + TAG_WIDTH;

    `STATIC_ASSERT(ADDR_WIDTH == (BANK_ADDR_WIDTH + `CLOG2(NUM_BANKS)), ("invalid parameter"))

    // bank selection

    wire [NUM_REQS-1:0][BANK_SEL_WIDTH-1:0] req_bank_idx;
    if (NUM_BANKS > 1) begin : g_req_bank_idx
        for (genvar i = 0; i < NUM_REQS; ++i) begin : g_req_bank_idxs
            assign req_bank_idx[i] = mem_bus_if[i].req_data.addr[0 +: BANK_SEL_BITS];
        end
    end else begin : g_req_bank_idx_0
        assign req_bank_idx = 0;
    end

    // bank addressing

    wire [NUM_REQS-1:0][BANK_ADDR_WIDTH-1:0] req_bank_addr;
    for (genvar i = 0; i < NUM_REQS; ++i) begin : g_req_bank_addr
        assign req_bank_addr[i] = mem_bus_if[i].req_data.addr[BANK_SEL_BITS +: BANK_ADDR_WIDTH];
        `UNUSED_VAR (mem_bus_if[i].req_data.flags)
    end

    // bank requests dispatch

    wire [NUM_BANKS-1:0]                    per_bank_req_valid;
    wire [NUM_BANKS-1:0]                    per_bank_req_rw;
    wire [NUM_BANKS-1:0][BANK_ADDR_WIDTH-1:0] per_bank_req_addr;
    wire [NUM_BANKS-1:0][WORD_SIZE-1:0]     per_bank_req_byteen;
    wire [NUM_BANKS-1:0][WORD_WIDTH-1:0]    per_bank_req_data;
    wire [NUM_BANKS-1:0][TAG_WIDTH-1:0]     per_bank_req_tag;
    wire [NUM_BANKS-1:0][REQ_SEL_WIDTH-1:0] per_bank_req_idx;
    wire [NUM_BANKS-1:0]                    per_bank_req_ready;

    wire [NUM_BANKS-1:0][REQ_DATAW-1:0]     per_bank_req_data_aos;

    wire [NUM_REQS-1:0]                 req_valid_in;
    wire [NUM_REQS-1:0][REQ_DATAW-1:0]  req_data_in;
    wire [NUM_REQS-1:0]                 req_ready_in;

`ifdef PERF_ENABLE
    wire [PERF_CTR_BITS-1:0] perf_collisions;
`endif

    for (genvar i = 0; i < NUM_REQS; ++i) begin : g_req_data_in
        assign req_valid_in[i] = mem_bus_if[i].req_valid;
        assign req_data_in[i] = {
            mem_bus_if[i].req_data.rw,
            req_bank_addr[i],
            mem_bus_if[i].req_data.data,
            mem_bus_if[i].req_data.byteen,
            mem_bus_if[i].req_data.tag
        };
        assign mem_bus_if[i].req_ready = req_ready_in[i];
    end

    VX_stream_xbar #(
        .NUM_INPUTS  (NUM_REQS),
        .NUM_OUTPUTS (NUM_BANKS),
        .DATAW       (REQ_DATAW),
        .PERF_CTR_BITS (PERF_CTR_BITS),
        .ARBITER     ("P"),
        .OUT_BUF     (3) // output should be registered for the data_store addressing
    ) req_xbar (
        .clk       (clk),
        .reset     (reset),
    `ifdef PERF_ENABLE
        .collisions (perf_collisions),
    `else
        `UNUSED_PIN (collisions),
    `endif
        .valid_in  (req_valid_in),
        .data_in   (req_data_in),
        .sel_in    (req_bank_idx),
        .ready_in  (req_ready_in),
        .valid_out (per_bank_req_valid),
        .data_out  (per_bank_req_data_aos),
        .sel_out   (per_bank_req_idx),
        .ready_out (per_bank_req_ready)
    );

    for (genvar i = 0; i < NUM_BANKS; ++i) begin : g_per_bank_req_data_soa
        assign {
            per_bank_req_rw[i],
            per_bank_req_addr[i],
            per_bank_req_data[i],
            per_bank_req_byteen[i],
            per_bank_req_tag[i]
        } = per_bank_req_data_aos[i];
    end

    // banks access

    wire [NUM_BANKS-1:0]                per_bank_rsp_valid;
    wire [NUM_BANKS-1:0][WORD_WIDTH-1:0] per_bank_rsp_data;
    wire [NUM_BANKS-1:0][REQ_SEL_WIDTH-1:0] per_bank_rsp_idx;
    wire [NUM_BANKS-1:0][TAG_WIDTH-1:0] per_bank_rsp_tag;
    wire [NUM_BANKS-1:0]                per_bank_rsp_ready;

    for (genvar i = 0; i < NUM_BANKS; ++i) begin : g_data_store
        wire bank_rsp_valid, bank_rsp_ready;

    `ifndef SYNTHESIS
        // GPU_and_PNM (CAL per-run energy): local-memory bank activity (sim-only), per FakeRAM macro: 2048-word banks are
        // 2 x 1024x32 (addr[10]), 4096-word banks 4 x 1024x32 (addr[11:10]), smaller banks one macro.
        wire ctr_ce = per_bank_req_valid[i] && per_bank_req_ready[i];
        wire ctr_we = ctr_ce && per_bank_req_rw[i];
        wire [1:0] ctr_m;
        if (WORDS_PER_BANK == 4096) begin : g_ctr_m4
            assign ctr_m = per_bank_req_addr[i][11:10];
        end else if (WORDS_PER_BANK == 2048) begin : g_ctr_m2
            assign ctr_m = {1'b0, per_bank_req_addr[i][10]};
        end else begin : g_ctr_m1
            assign ctr_m = 2'b00;
        end
        VX_sim_ctrs #(
            .N (11), .W (8),
            .NAMES ("lmem_ce,lmem_we,lmem_wr_bytes,lmem_ce_m0,lmem_ce_m1,lmem_ce_m2,lmem_ce_m3,lmem_we_m0,lmem_we_m1,lmem_we_m2,lmem_we_m3"),
            .INFO  ($sformatf("bank=%0d words_per_bank=%0d macros=%0d", i, WORDS_PER_BANK,
                              (WORDS_PER_BANK == 4096) ? 4 : ((WORDS_PER_BANK == 2048) ? 2 : 1)))
        ) sim_ctrs (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'(ctr_we && ctr_m == 2'd3), 8'(ctr_we && ctr_m == 2'd2), 8'(ctr_we && ctr_m == 2'd1), 8'(ctr_we && ctr_m == 2'd0),
                     8'(ctr_ce && ctr_m == 2'd3), 8'(ctr_ce && ctr_m == 2'd2), 8'(ctr_ce && ctr_m == 2'd1), 8'(ctr_ce && ctr_m == 2'd0),
                     8'(ctr_we ? $countones(per_bank_req_byteen[i]) : 0),
                     8'(ctr_we),
                     8'(ctr_ce)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): data-bus bit flips per transfer (sim-only): at each valid transfer, the bits that
        // differ from the previous transfer on the same bus (what the receiving registers change when they load). Valid-qualified, so
        // invalid/X-assigned values never count. Added after the activity test showed data-dependent switching that event counts miss.
        wire tgl_rsp = per_bank_rsp_valid[i] && per_bank_rsp_ready[i];
        reg [WORD_WIDTH-1:0] tgl_wr_last = '0, tgl_rd_last = '0;
        reg [BANK_ADDR_WIDTH-1:0] tgl_addr_last = '0;
        always @(posedge clk) begin
            if (ctr_we)  tgl_wr_last <= per_bank_req_data[i];
            if (tgl_rsp) tgl_rd_last <= per_bank_rsp_data[i];
            if (ctr_ce)  tgl_addr_last <= per_bank_req_addr[i];
        end
        VX_sim_ctrs #(
            .N (3), .W (8),
            .NAMES ("lmem_wdata_flips,lmem_rdata_flips,lmem_addr_flips")
        ) sim_tgl (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'(ctr_ce ? $countones(per_bank_req_addr[i] ^ tgl_addr_last) : 0),
                     8'(tgl_rsp ? $countones(per_bank_rsp_data[i] ^ tgl_rd_last) : 0),
                     8'(ctr_we ? $countones(per_bank_req_data[i] ^ tgl_wr_last) : 0)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
        // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
        reg [WORD_WIDTH-1:0] tgl_c0_q = '0;
        reg [WORD_WIDTH-1:0] tgl_c1_q = '0;
        reg [BANK_ADDR_WIDTH-1:0] tgl_c2_q = '0;
        always @(posedge clk) begin
            tgl_c0_q <= per_bank_req_data[i];
            tgl_c1_q <= per_bank_rsp_data[i];
            tgl_c2_q <= per_bank_req_addr[i];
        end
        VX_sim_ctrs #(
            .N (3), .W (8),
            .NAMES ("lmem_wdata_cyc,lmem_rdata_cyc,lmem_addr_cyc")
        ) sim_cyc (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'($countones(per_bank_req_addr[i] ^ tgl_c2_q)),
                     8'($countones(per_bank_rsp_data[i] ^ tgl_c1_q)),
                     8'($countones(per_bank_req_data[i] ^ tgl_c0_q))})
        );
    `endif

    `ifdef USE_FAKERAM
        // Byte-enable SRAM macro for P&R: per-byte write mask via wmask_in, so byte
        // stores commit only the masked bytes (the whole-word fakeram corrupted lines).
        wire lmem_we_i = per_bank_req_valid[i] && per_bank_req_ready[i] && per_bank_req_rw[i];
        wire lmem_ce_i = per_bank_req_valid[i] && per_bank_req_ready[i];
        if (WORDS_PER_BANK == 256) begin : g_sram
            fakeram7_256x32_be lmem_sram (
                .clk(clk), .ce_in(lmem_ce_i), .we_in(lmem_we_i), .wmask_in(per_bank_req_byteen[i]),
                .addr_in(per_bank_req_addr[i]), .wd_in(per_bank_req_data[i]),
                .rd_out(per_bank_rsp_data[i])
            );
        end else if (WORDS_PER_BANK == 512) begin : g_sram
            fakeram7_512x32_be lmem_sram (
                .clk(clk), .ce_in(lmem_ce_i), .we_in(lmem_we_i), .wmask_in(per_bank_req_byteen[i]),
                .addr_in(per_bank_req_addr[i]), .wd_in(per_bank_req_data[i]),
                .rd_out(per_bank_rsp_data[i])
            );
        end else if (WORDS_PER_BANK == 1024) begin : g_sram
            fakeram7_1024x32_be lmem_sram (
                .clk(clk), .ce_in(lmem_ce_i), .we_in(lmem_we_i), .wmask_in(per_bank_req_byteen[i]),
                .addr_in(per_bank_req_addr[i]), .wd_in(per_bank_req_data[i]),
                .rd_out(per_bank_rsp_data[i])
            );
        end else if (WORDS_PER_BANK == 2048) begin : g_sram
            // Split into 2 × 1024x32 to avoid the tall 2048x32 macro (532µm)
            wire bank_sel = per_bank_req_addr[i][10]; // MSB selects upper/lower half
            wire [WORD_WIDTH-1:0] rd_lo, rd_hi;
            fakeram7_1024x32_be lmem_sram_lo (
                .clk(clk), .ce_in(lmem_ce_i && ~bank_sel), .we_in(lmem_we_i && ~bank_sel), .wmask_in(per_bank_req_byteen[i]),
                .addr_in(per_bank_req_addr[i][9:0]), .wd_in(per_bank_req_data[i]),
                .rd_out(rd_lo)
            );
            fakeram7_1024x32_be lmem_sram_hi (
                .clk(clk), .ce_in(lmem_ce_i && bank_sel), .we_in(lmem_we_i && bank_sel), .wmask_in(per_bank_req_byteen[i]),
                .addr_in(per_bank_req_addr[i][9:0]), .wd_in(per_bank_req_data[i]),
                .rd_out(rd_hi)
            );
            reg bank_sel_r;
            always @(posedge clk) bank_sel_r <= bank_sel;
            assign per_bank_rsp_data[i] = bank_sel_r ? rd_hi : rd_lo;
        end else if (WORDS_PER_BANK == 4096) begin : g_sram
            // Single-bank scratchpad (1-thread cores): 4 x 1024x32, addr[11:10] selects the quarter
            wire [1:0] qsel = per_bank_req_addr[i][11:10];
            wire [3:0][WORD_WIDTH-1:0] rd_q;
            for (genvar q = 0; q < 4; ++q) begin : g_q
                fakeram7_1024x32_be lmem_sram_q (
                    .clk(clk), .ce_in(lmem_ce_i && (qsel == q)), .we_in(lmem_we_i && (qsel == q)), .wmask_in(per_bank_req_byteen[i]),
                    .addr_in(per_bank_req_addr[i][9:0]), .wd_in(per_bank_req_data[i]),
                    .rd_out(rd_q[q])
                );
            end
            reg [1:0] qsel_r;
            always @(posedge clk) qsel_r <= qsel;
            assign per_bank_rsp_data[i] = rd_q[qsel_r];
        end
    `else
        VX_sp_ram #(
            .DATAW (WORD_WIDTH),
            .SIZE  (WORDS_PER_BANK),
            .WRENW (WORD_SIZE),
            .OUT_REG (1),
            .RDW_MODE ("R")
        ) lmem_store (
            .clk   (clk),
            .reset (reset),
            .read  (per_bank_req_valid[i] && per_bank_req_ready[i] && ~per_bank_req_rw[i]),
            .write (per_bank_req_valid[i] && per_bank_req_ready[i] && per_bank_req_rw[i]),
            .wren  (per_bank_req_byteen[i]),
            .addr  (per_bank_req_addr[i]),
            .wdata (per_bank_req_data[i]),
            .rdata (per_bank_rsp_data[i])
        );
    `endif

        // read-during-write hazard detection
        reg [BANK_ADDR_WIDTH-1:0] last_wr_addr;
        reg last_wr_valid;
        always @(posedge clk) begin
            if (reset) begin
                last_wr_valid <= 0;
            end else begin
                last_wr_valid <= per_bank_req_valid[i] && per_bank_req_ready[i] && per_bank_req_rw[i];
            end
            last_wr_addr <= per_bank_req_addr[i];
        end
        wire is_rdw_hazard = last_wr_valid && ~per_bank_req_rw[i] && (per_bank_req_addr[i] == last_wr_addr);

        // drop write response
        assign bank_rsp_valid = per_bank_req_valid[i] && ~per_bank_req_rw[i] && ~is_rdw_hazard;
        assign per_bank_req_ready[i] = (bank_rsp_ready || per_bank_req_rw[i]) && ~is_rdw_hazard;

        // register BRAM output
        VX_pipe_buffer #(
            .DATAW (REQ_SEL_WIDTH + TAG_WIDTH)
        ) bram_buf (
            .clk       (clk),
            .reset     (reset),
            .valid_in  (bank_rsp_valid),
            .ready_in  (bank_rsp_ready),
            .data_in   ({per_bank_req_idx[i], per_bank_req_tag[i]}),
            .data_out  ({per_bank_rsp_idx[i], per_bank_rsp_tag[i]}),
            .valid_out (per_bank_rsp_valid[i]),
            .ready_out (per_bank_rsp_ready[i])
        );
    end

    // bank responses gather

    wire [NUM_BANKS-1:0][RSP_DATAW-1:0] per_bank_rsp_data_aos;

    for (genvar i = 0; i < NUM_BANKS; ++i) begin : g_per_bank_rsp_data_aos
        assign per_bank_rsp_data_aos[i] = {per_bank_rsp_data[i], per_bank_rsp_tag[i]};
    end

    wire [NUM_REQS-1:0]                 rsp_valid_out;
    wire [NUM_REQS-1:0][RSP_DATAW-1:0]  rsp_data_out;
    wire [NUM_REQS-1:0]                 rsp_ready_out;

    VX_stream_xbar #(
        .NUM_INPUTS  (NUM_BANKS),
        .NUM_OUTPUTS (NUM_REQS),
        .DATAW       (RSP_DATAW),
        .ARBITER     ("P"), // this priority arbiter has negligeable impact om performance
        .OUT_BUF     (OUT_BUF)
    ) rsp_xbar (
        .clk       (clk),
        .reset     (reset),
        `UNUSED_PIN (collisions),
        .sel_in    (per_bank_rsp_idx),
        .valid_in  (per_bank_rsp_valid),
        .data_in   (per_bank_rsp_data_aos),
        .ready_in  (per_bank_rsp_ready),
        .valid_out (rsp_valid_out),
        .data_out  (rsp_data_out),
        .ready_out (rsp_ready_out),
        `UNUSED_PIN (sel_out)
    );

    for (genvar i = 0; i < NUM_REQS; ++i) begin : g_mem_bus_if
        assign mem_bus_if[i].rsp_valid = rsp_valid_out[i];
        assign mem_bus_if[i].rsp_data  = rsp_data_out[i];
        assign rsp_ready_out[i] = mem_bus_if[i].rsp_ready;
    end

`ifdef PERF_ENABLE
    // per cycle: reads, writes
    wire [`CLOG2(NUM_REQS+1)-1:0] perf_reads_per_cycle;
    wire [`CLOG2(NUM_REQS+1)-1:0] perf_writes_per_cycle;
    wire [`CLOG2(NUM_REQS+1)-1:0] perf_crsp_stall_per_cycle;

    wire [NUM_REQS-1:0] req_rw;
    for (genvar i = 0; i < NUM_REQS; ++i) begin : g_req_rw
        assign req_rw[i] = mem_bus_if[i].req_data.rw;
    end

    wire [NUM_REQS-1:0] perf_reads_per_req, perf_writes_per_req;
    wire [NUM_REQS-1:0] perf_crsp_stall_per_req = rsp_valid_out & ~rsp_ready_out;

    `BUFFER(perf_reads_per_req, req_valid_in & req_ready_in & ~req_rw);
    `BUFFER(perf_writes_per_req, req_valid_in & req_ready_in & req_rw);

    `POP_COUNT(perf_reads_per_cycle, perf_reads_per_req);
    `POP_COUNT(perf_writes_per_cycle, perf_writes_per_req);
    `POP_COUNT(perf_crsp_stall_per_cycle, perf_crsp_stall_per_req);

    reg [PERF_CTR_BITS-1:0] perf_reads;
    reg [PERF_CTR_BITS-1:0] perf_writes;
    reg [PERF_CTR_BITS-1:0] perf_crsp_stalls;

    always @(posedge clk) begin
        if (reset) begin
            perf_reads       <= '0;
            perf_writes      <= '0;
            perf_crsp_stalls <= '0;
        end else begin
            perf_reads       <= perf_reads  + PERF_CTR_BITS'(perf_reads_per_cycle);
            perf_writes      <= perf_writes + PERF_CTR_BITS'(perf_writes_per_cycle);
            perf_crsp_stalls <= perf_crsp_stalls + PERF_CTR_BITS'(perf_crsp_stall_per_cycle);
        end
    end

    assign lmem_perf.reads       = perf_reads;
    assign lmem_perf.writes      = perf_writes;
    assign lmem_perf.bank_stalls = perf_collisions;
    assign lmem_perf.crsp_stalls = perf_crsp_stalls;

`endif

`ifdef DBG_TRACE_MEM

    wire [NUM_BANKS-1:0][TAG_WIDTH-UUID_WIDTH-1:0] per_bank_req_tag_value;
    wire [NUM_BANKS-1:0][`UP(UUID_WIDTH)-1:0] per_bank_req_uuid;

    wire [NUM_BANKS-1:0][TAG_WIDTH-UUID_WIDTH-1:0] per_bank_rsp_tag_value;
    wire [NUM_BANKS-1:0][`UP(UUID_WIDTH)-1:0] per_bank_rsp_uuid;

    for (genvar i = 0; i < NUM_BANKS; ++i) begin : g_per_bank_req_uuid
        assign per_bank_req_tag_value[i] = per_bank_req_tag[i][TAG_WIDTH-UUID_WIDTH-1:0];
        assign per_bank_rsp_tag_value[i] = per_bank_rsp_tag[i][TAG_WIDTH-UUID_WIDTH-1:0];
        if (UUID_WIDTH != 0) begin : g_uuid
            assign per_bank_req_uuid[i] = per_bank_req_tag[i][TAG_WIDTH-1 -: UUID_WIDTH];
            assign per_bank_rsp_uuid[i] = per_bank_rsp_tag[i][TAG_WIDTH-1 -: UUID_WIDTH];
        end else begin : g_no_uuid
            assign per_bank_req_uuid[i] = 0;
            assign per_bank_rsp_uuid[i] = 0;
        end
    end

    for (genvar i = 0; i < NUM_REQS; ++i) begin : g_req_trace
        always @(posedge clk) begin
            if (mem_bus_if[i].req_valid && mem_bus_if[i].req_ready) begin
                if (mem_bus_if[i].req_data.rw) begin
                    `TRACE(2, ("%t: %s core-wr-req[%0d]: addr=0x%0h, byteen=0x%h, data=0x%h, tag=0x%0h (#%0d)\n",
                        $time, INSTANCE_ID, i, mem_bus_if[i].req_data.addr, mem_bus_if[i].req_data.byteen, mem_bus_if[i].req_data.data, mem_bus_if[i].req_data.tag.value, mem_bus_if[i].req_data.tag.uuid))
                end else begin
                    `TRACE(2, ("%t: %s core-rd-req[%0d]: addr=0x%0h, tag=0x%0h (#%0d)\n",
                        $time, INSTANCE_ID, i, mem_bus_if[i].req_data.addr, mem_bus_if[i].req_data.tag.value, mem_bus_if[i].req_data.tag.uuid))
                end
            end
            if (mem_bus_if[i].rsp_valid && mem_bus_if[i].rsp_ready) begin
                `TRACE(2, ("%t: %s core-rd-rsp[%0d]: data=0x%h, tag=0x%0h (#%0d)\n",
                    $time, INSTANCE_ID, i, mem_bus_if[i].rsp_data.data, mem_bus_if[i].rsp_data.tag.value, mem_bus_if[i].rsp_data.tag.uuid))
            end
        end
    end

    for (genvar i = 0; i < NUM_BANKS; ++i) begin : g_bank_trace
        always @(posedge clk) begin
            if (per_bank_req_valid[i] && per_bank_req_ready[i]) begin
                if (per_bank_req_rw[i]) begin
                    `TRACE(2, ("%t: %s bank-wr-req[%0d]: addr=0x%0h, byteen=0x%h, data=0x%h, tag=0x%0h (#%0d)\n",
                        $time, INSTANCE_ID, i, per_bank_req_addr[i], per_bank_req_byteen[i], per_bank_req_data[i], per_bank_req_tag_value[i], per_bank_req_uuid[i]))
                end else begin
                    `TRACE(2, ("%t: %s bank-rd-req[%0d]: addr=0x%0h, tag=0x%0h (#%0d)\n",
                        $time, INSTANCE_ID, i, per_bank_req_addr[i], per_bank_req_tag_value[i], per_bank_req_uuid[i]))
                end
            end
            if (per_bank_rsp_valid[i] && per_bank_rsp_ready[i]) begin
                `TRACE(2, ("%t: %s bank-rd-rsp[%0d]: data=0x%h, tag=0x%0h (#%0d)\n",
                    $time, INSTANCE_ID, i, per_bank_rsp_data[i], per_bank_rsp_tag_value[i], per_bank_rsp_uuid[i]))
            end
        end
    end

`endif

endmodule
