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

`include "VX_cache_define.vh"

module VX_cache_data import VX_gpu_pkg::*; #(
    // Size of cache in bytes
    parameter CACHE_SIZE        = 1024,
    // Size of line inside a bank in bytes
    parameter LINE_SIZE         = 16,
    // Number of banks
    parameter NUM_BANKS         = 1,
    // Number of associative ways
    parameter NUM_WAYS          = 1,
    // Size of a word in bytes
    parameter WORD_SIZE         = 1,
    // Enable cache writeable
    parameter WRITE_ENABLE      = 1,
    // Enable cache writeback
    parameter WRITEBACK         = 0,
    // Enable dirty bytes on writeback
    parameter DIRTY_BYTES       = 0
) (
    input wire                          clk,
    input wire                          reset,
    // inputs
    input wire                          init,
    input wire                          fill,
    input wire                          flush,
    input wire                          read,
    input wire                          write,
    input wire [`CS_LINE_SEL_BITS-1:0]  line_idx,
    input wire [`CS_WAY_SEL_WIDTH-1:0]  evict_way,
    input wire [NUM_WAYS-1:0]           tag_matches,
    input wire [`CS_WORDS_PER_LINE-1:0][`CS_WORD_WIDTH-1:0] fill_data,
    input wire [`CS_WORD_WIDTH-1:0]     write_word,
    input wire [WORD_SIZE-1:0]          write_byteen,
    input wire [`UP(`CS_WORD_SEL_BITS)-1:0] word_idx,
    input wire [`CS_WAY_SEL_WIDTH-1:0]  way_idx_r,
    // outputs
    output wire [`CS_LINE_WIDTH-1:0]    read_data,
    output wire [LINE_SIZE-1:0]         evict_byteen
);
    `UNUSED_PARAM (WORD_SIZE)

    wire [`CS_WORDS_PER_LINE-1:0][WORD_SIZE-1:0] write_mask;
    for (genvar i = 0; i < `CS_WORDS_PER_LINE; ++i) begin : g_write_mask
        wire word_en = (`CS_WORDS_PER_LINE == 1) || (word_idx == i);
        assign write_mask[i] = write_byteen & {WORD_SIZE{word_en}};
    end

    if (DIRTY_BYTES != 0) begin : g_dirty_bytes

        wire [NUM_WAYS-1:0][LINE_SIZE-1:0] byteen_rdata;

        for (genvar i = 0; i < NUM_WAYS; ++i) begin : g_byteen_store
            wire [LINE_SIZE-1:0] byteen_wdata = {LINE_SIZE{write}}; // only asserted on writes
            wire [LINE_SIZE-1:0] byteen_wren = {LINE_SIZE{init || fill || flush}} | write_mask;
            wire byteen_write = ((fill || flush) && ((NUM_WAYS == 1) || (evict_way == i)))
                             || (write && tag_matches[i])
                             || init;
            wire byteen_read  = fill || flush;

            VX_sp_ram #(
                .DATAW (LINE_SIZE),
                .WRENW (LINE_SIZE),
                .SIZE  (`CS_LINES_PER_BANK),
                .OUT_REG (1),
                .RDW_MODE ("R")
            ) byteen_store (
                .clk   (clk),
                .reset (reset),
                .read  (byteen_read),
                .write (byteen_write),
                .wren  (byteen_wren),
                .addr  (line_idx),
                .wdata (byteen_wdata),
                .rdata (byteen_rdata[i])
            );
        end

        assign evict_byteen = byteen_rdata[way_idx_r];

    end else begin : g_no_dirty_bytes
        `UNUSED_VAR (init)
        `UNUSED_VAR (flush)
        assign evict_byteen = '1; // update whole line
    end

    wire [NUM_WAYS-1:0][`CS_WORDS_PER_LINE-1:0][`CS_WORD_WIDTH-1:0] line_rdata;

    for (genvar i = 0; i < NUM_WAYS; ++i) begin : g_data_store

        localparam WRENW = WRITE_ENABLE ? LINE_SIZE : 1;

        wire [`CS_WORDS_PER_LINE-1:0][`CS_WORD_WIDTH-1:0] line_wdata;
        wire [WRENW-1:0] line_wren;

        if (WRITE_ENABLE) begin : g_wren
            assign line_wdata = fill ? fill_data : {`CS_WORDS_PER_LINE{write_word}};
            assign line_wren  = {LINE_SIZE{fill}} | write_mask;
        end else begin : g_no_wren
            `UNUSED_VAR (write_word)
            `UNUSED_VAR (write_mask)
            assign line_wdata = fill_data;
            assign line_wren  = 1'b1;
        end

        wire line_write = (fill && ((NUM_WAYS == 1) || (evict_way == i)))
                       || (write && tag_matches[i] && WRITE_ENABLE);

        wire line_read = read || ((fill || flush) && WRITEBACK);

    `ifndef SYNTHESIS
        // GPU_and_PNM (CAL per-run energy): data-array activity of this way (sim-only). Under USE_FAKERAM each way is
        // CS_LINE_WIDTH/32 column macros sharing ce = line_read || line_write and we = line_write.
        // Written 32-bit columns (macros whose byte mask is non-zero) and written bytes per line write.
        localparam CTR_NCOLS = `CS_LINE_WIDTH / 32;
        reg [7:0] ctr_wr_cols, ctr_wr_bytes;
        if (WRITE_ENABLE != 0) begin : g_ctr_wren
            always @(*) begin
                ctr_wr_cols = '0;
                for (integer c = 0; c < CTR_NCOLS; ++c) ctr_wr_cols += 8'(| line_wren[(c * 4) +: 4]);
                if (!line_write) ctr_wr_cols = '0;
                ctr_wr_bytes = line_write ? 8'($countones(line_wren)) : 8'd0;
            end
        end else begin : g_ctr_full
            always @(*) begin  // full-line writes (fills only): every column and byte
                ctr_wr_cols  = line_write ? 8'(CTR_NCOLS) : 8'd0;
                ctr_wr_bytes = line_write ? 8'(LINE_SIZE) : 8'd0;
            end
        end
        VX_sim_ctrs #(
            .N (6), .W (8),
            .NAMES ("data_ce_cycles,data_we_cycles,data_fill_writes,data_write_hits,data_wr_cols,data_wr_bytes"),
            .INFO  ($sformatf("way=%0d num_ways=%0d lines_per_bank=%0d line_size=%0d num_cols=%0d write_enable=%0d word_size=%0d",
                              i, NUM_WAYS, `CS_LINES_PER_BANK, LINE_SIZE, `CS_LINE_WIDTH / 32, WRITE_ENABLE, WORD_SIZE))
        ) sim_ctrs (
            .clk   (clk),
            .reset (reset),
            .inc   ({ctr_wr_bytes,
                     ctr_wr_cols,
                     8'(write && tag_matches[i] && (WRITE_ENABLE != 0)),
                     8'(fill && ((NUM_WAYS == 1) || (evict_way == i))),
                     8'(line_write),
                     8'(line_read || line_write)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 27): every-cycle bit changes on this way's data-array ports (sim-only, no
        // qualifier; zero-init energy build): write data, read output, byte-enable mask. The full-signal (net-level) check
        // found these wrapper nets the largest and most variable dcache contributor, uncovered by the bank-level counters.
        reg [$bits(line_wdata)-1:0] tgl_w_q = '0;
        reg [$bits(line_rdata[i])-1:0] tgl_r_q = '0;
        reg [$bits(line_wren)-1:0] tgl_m_q = '0;
        always @(posedge clk) begin
            tgl_w_q <= line_wdata;
            tgl_r_q <= line_rdata[i];
            tgl_m_q <= line_wren;
        end
        VX_sim_ctrs #(
            .N (3), .W (16),
            .NAMES ("dway_wdata_cyc,dway_rdata_cyc,dway_wren_cyc")
        ) sim_cyc (
            .clk   (clk),
            .reset (reset),
            .inc   ({16'($countones(line_wren ^ tgl_m_q)),
                     16'($countones(line_rdata[i] ^ tgl_r_q)),
                     16'($countones(line_wdata ^ tgl_w_q))})
        );
    `endif

    `ifdef USE_FAKERAM
        // Read-during-write byte-enable fakeram for ALL cache data RAMs. The model is
        // read-first on the stock SRAM interface (rd_out captures pre-write contents on
        // every enabled cycle), so a read coinciding with a fill/write to the same RAM
        // gets the old data -- no separate read-enable port needed (FakeRAM2.0
        // --write_mask interface). The line is split into 32-bit RAM columns
        // (CS_WORD_WIDTH can exceed 32 for coalesced dcaches). Byte-maskable caches
        // (WRITE_ENABLE) mask with line_wren (per-byte); full-line caches write all bytes.
        localparam NUM_COLS = `CS_LINE_WIDTH / 32;
        wire [`CS_LINE_WIDTH-1:0] wdata_flat = line_wdata;
        wire [`CS_LINE_WIDTH-1:0] rdata_flat;
        assign line_rdata[i] = rdata_flat;
        wire [LINE_SIZE-1:0] col_wmask;
        if (WRITE_ENABLE) begin : g_wmask
            assign col_wmask = line_wren;
        end else begin : g_wmask
            `UNUSED_VAR (line_wren)
            assign col_wmask = {LINE_SIZE{1'b1}};
        end
        if (`CS_LINES_PER_BANK >= 256) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_256x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 128) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_128x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 64) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_64x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 32) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_32x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 16) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_16x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 8) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_8x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 4) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_4x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else if (`CS_LINES_PER_BANK >= 2) begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_2x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end else begin : g_sram_chunk
            for (genvar c = 0; c < NUM_COLS; ++c) begin : g_col
                fakeram7_16x32_be cache_data_sram (
                    .clk(clk), .ce_in(line_read || line_write), .we_in(line_write),
                    .wmask_in(col_wmask[c*4 +: 4]), .addr_in(line_idx),
                    .wd_in(wdata_flat[c*32 +: 32]), .rd_out(rdata_flat[c*32 +: 32]));
            end
        end
    `else
        VX_sp_ram #(
            .DATAW (`CS_LINE_WIDTH),
            .SIZE  (`CS_LINES_PER_BANK),
            .WRENW (WRENW),
            .OUT_REG (1),
            .RDW_MODE ("R")
        ) data_store (
            .clk   (clk),
            .reset (reset),
            .read  (line_read),
            .write (line_write),
            .wren  (line_wren),
            .addr  (line_idx),
            .wdata (line_wdata),
            .rdata (line_rdata[i])
        );
    `endif
    end

    assign read_data = line_rdata[way_idx_r];

endmodule
