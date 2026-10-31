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

// reset all GPRs in debug mode
`ifdef SIMULATION
`ifndef NDEBUG
`define GPR_RESET
`endif
`endif

module VX_opc_unit import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter NUM_BANKS = 4,
    parameter OUT_BUF   = 3
) (
    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output wire [PERF_CTR_BITS-1:0] perf_stalls,
`endif

    VX_writeback_if.slave   writeback_if,
    VX_scoreboard_if.slave  scoreboard_if,
    VX_operands_if.master   operands_if
);
    `UNUSED_SPARAM (INSTANCE_ID)

    localparam REQ_SEL_WIDTH    = SRC_OPD_WIDTH;
    localparam BANK_SEL_BITS    = `CLOG2(NUM_BANKS);
    localparam BANK_SEL_WIDTH   = `UP(BANK_SEL_BITS);
    localparam BANK_DATA_WIDTH  = `XLEN * `SIMD_WIDTH;
    localparam BANK_DATA_SIZE   = BANK_DATA_WIDTH / 8;

    localparam PER_OPC_WARPS    = PER_ISSUE_WARPS / `NUM_OPCS;
    localparam PER_OPC_NW_BITS  = `CLOG2(PER_OPC_WARPS);
    localparam BANK_SIZE        = (NUM_REGS * SIMD_COUNT * PER_OPC_WARPS) / NUM_BANKS;
    localparam BANK_ADDR_WIDTH  = `CLOG2(BANK_SIZE);

    localparam REG_REM_BITS     = NUM_REGS_BITS - BANK_SEL_BITS;

    localparam META_DATAW       = UUID_WIDTH + ISSUE_WIS_W + SIMD_IDX_W + `SIMD_WIDTH + PC_BITS + 1 + EX_BITS + INST_OP_BITS + INST_ARGS_BITS + NUM_REGS_BITS + 1 + 1;
    localparam OUT_DATAW        = $bits(operands_t);

    `UNUSED_VAR (writeback_if.data.sop)

    wire [NUM_SRC_OPDS-1:0] src_valid;
    wire [NUM_SRC_OPDS-1:0] req_valid_in, req_ready_in;
    wire [NUM_SRC_OPDS-1:0][REG_REM_BITS-1:0] req_addr_in;
    wire [NUM_SRC_OPDS-1:0][BANK_SEL_WIDTH-1:0] req_bank_idx;

    wire [NUM_BANKS-1:0] gpr_rd_valid, gpr_rd_ready;
    wire [NUM_BANKS-1:0] gpr_rd_valid_st1, gpr_rd_valid_st2;
    wire [NUM_BANKS-1:0][REG_REM_BITS-1:0] gpr_rd_reg, gpr_rd_reg_st1;
    wire [NUM_BANKS-1:0][`SIMD_WIDTH-1:0][`XLEN-1:0] gpr_rd_data_st2;
    wire [NUM_BANKS-1:0][REQ_SEL_WIDTH-1:0] gpr_rd_opd, gpr_rd_opd_st1, gpr_rd_opd_st2;

    wire [`SIMD_WIDTH-1:0] simd_out;
    wire [SIMD_IDX_W-1:0] simd_pid;
    wire simd_sop, simd_eop;

    wire pipe_ready_in;
    wire pipe_valid_st1, pipe_ready_st1;
    wire pipe_valid_st2, pipe_ready_st2;
    wire [META_DATAW-1:0] pipe_mdata, pipe_mdata_st1, pipe_mdata_st2;

    reg [NUM_SRC_OPDS-1:0][(`SIMD_WIDTH * `XLEN)-1:0] opd_buffer_st2, opd_buffer_n_st2;

    reg [NUM_SRC_OPDS-1:0] opd_fetched_st1;

    reg has_collision;
    wire has_collision_st1;

    wire [NUM_SRC_OPDS-1:0][NUM_REGS_BITS-1:0] src_regs;
    assign src_regs = {scoreboard_if.data.rs3, scoreboard_if.data.rs2, scoreboard_if.data.rs1};

    for (genvar i = 0; i < NUM_SRC_OPDS; ++i) begin : g_gpr_rd_reg
        assign req_addr_in[i] = src_regs[i][NUM_REGS_BITS-1 -: REG_REM_BITS];
    end

    for (genvar i = 0; i < NUM_SRC_OPDS; ++i) begin : g_req_bank_idx
        if (NUM_BANKS != 1) begin : g_bn
            assign req_bank_idx[i] = src_regs[i][BANK_SEL_BITS-1:0];
        end else begin : g_b1
            assign req_bank_idx[i] = '0;
        end
    end

    for (genvar i = 0; i < NUM_SRC_OPDS; ++i) begin : g_src_valid
        assign src_valid[i] = scoreboard_if.data.used_rs[i] && (src_regs[i] != 0) && ~opd_fetched_st1[i];
    end

    assign req_valid_in = {NUM_SRC_OPDS{scoreboard_if.valid}} & src_valid;

    VX_stream_xbar #(
        .NUM_INPUTS  (NUM_SRC_OPDS),
        .NUM_OUTPUTS (NUM_BANKS),
        .DATAW       (REG_REM_BITS),
        .ARBITER     ("P"), // use priority arbiter
        .OUT_BUF     (0)    // no output buffering
    ) req_xbar (
        .clk       (clk),
        .reset     (reset),
        `UNUSED_PIN(collisions),
        .valid_in  (req_valid_in),
        .data_in   (req_addr_in),
        .sel_in    (req_bank_idx),
        .ready_in  (req_ready_in),
        .valid_out (gpr_rd_valid),
        .data_out  (gpr_rd_reg),
        .sel_out   (gpr_rd_opd),
        .ready_out (gpr_rd_ready)
    );

    assign gpr_rd_ready = {NUM_BANKS{pipe_ready_in}};

    always @(*) begin
        has_collision = 0;
        for (integer i = 0; i < NUM_SRC_OPDS; ++i) begin
            for (integer j = 1; j < (NUM_SRC_OPDS-i); ++j) begin
                has_collision |= src_valid[i]
                              && src_valid[j+i]
                              && (req_bank_idx[i] == req_bank_idx[j+i]);
            end
        end
    end

    wire opd_last_fetch = pipe_ready_in && ~has_collision;

    // simd iterator (skip requests with inactive threads)
    VX_nz_iterator #(
        .DATAW (`SIMD_WIDTH),
        .N     (SIMD_COUNT)
    ) simd_iter (
        .clk     (clk),
        .reset   (reset),
        .valid_in(scoreboard_if.valid),
        .data_in (scoreboard_if.data.tmask),
        .next    (opd_last_fetch),
        `UNUSED_PIN (valid_out),
        .data_out(simd_out),
        .pid     (simd_pid),
        .sop     (simd_sop),
        .eop     (simd_eop)
    );

    assign pipe_mdata = {
        scoreboard_if.data.uuid,
        scoreboard_if.data.wis,
        simd_pid,
        simd_out,
        scoreboard_if.data.PC,
        scoreboard_if.data.wb,
        scoreboard_if.data.ex_type,
        scoreboard_if.data.op_type,
        scoreboard_if.data.op_args,
        scoreboard_if.data.rd,
        simd_sop,
        simd_eop
    };

    assign scoreboard_if.ready = opd_last_fetch && simd_eop;

    wire pipe_fire_st1 = pipe_valid_st1 && pipe_ready_st1;
    wire pipe_fire_st2 = pipe_valid_st2 && pipe_ready_st2;

    VX_pipe_buffer #(
        .DATAW  (NUM_BANKS + META_DATAW + 1 + NUM_BANKS * (REG_REM_BITS + REQ_SEL_WIDTH)),
        .RESETW (1)
    ) pipe_reg1 (
        .clk      (clk),
        .reset    (reset),
        .valid_in (scoreboard_if.valid),
        .ready_in (pipe_ready_in),
        .data_in  ({gpr_rd_valid,     pipe_mdata,     has_collision,     gpr_rd_reg,     gpr_rd_opd}),
        .data_out ({gpr_rd_valid_st1, pipe_mdata_st1, has_collision_st1, gpr_rd_reg_st1, gpr_rd_opd_st1}),
        .valid_out(pipe_valid_st1),
        .ready_out(pipe_ready_st1)
    );

    wire [NUM_SRC_OPDS-1:0] req_fire_in = req_valid_in & req_ready_in;

    always @(posedge clk) begin
        if (reset || opd_last_fetch) begin
            opd_fetched_st1 <= '0;
        end else begin
            opd_fetched_st1 <= opd_fetched_st1 | req_fire_in;
        end
    end

    wire pipe_valid2_st1 = pipe_valid_st1 && ~has_collision_st1;

    VX_pipe_buffer #(
        .DATAW  (NUM_BANKS * (1 + REQ_SEL_WIDTH) + META_DATAW),
        .RESETW (1)
    ) pipe_reg2 (
        .clk      (clk),
        .reset    (reset),
        .valid_in (pipe_valid2_st1),
        .ready_in (pipe_ready_st1),
        .data_in  ({gpr_rd_valid_st1, gpr_rd_opd_st1, pipe_mdata_st1}),
        .data_out ({gpr_rd_valid_st2, gpr_rd_opd_st2, pipe_mdata_st2}),
        .valid_out(pipe_valid_st2),
        .ready_out(pipe_ready_st2)
    );

    always @(*) begin
        opd_buffer_n_st2 = opd_buffer_st2;
        for (integer b = 0; b < NUM_BANKS; ++b) begin
            if (gpr_rd_valid_st2[b]) begin
                opd_buffer_n_st2[gpr_rd_opd_st2[b]] = gpr_rd_data_st2[b];
            end
        end
    end

    always @(posedge clk) begin
        if (reset || pipe_fire_st2) begin
            opd_buffer_st2 <= '0; // clear on reset or when data is sent out
        end else begin
            opd_buffer_st2 <= opd_buffer_n_st2;
        end
    end

    wire [BANK_ADDR_WIDTH-1:0] gpr_wr_addr;
    if (SIMD_COUNT != 1) begin : g_gpr_wr_addr_sid
        wire [PER_OPC_NW_BITS + REG_REM_BITS-1:0] tmp;
        `CONCAT(tmp, writeback_if.data.wis[ISSUE_WIS_W-1 -: PER_OPC_NW_BITS],
              writeback_if.data.rd[NUM_REGS_BITS-1 -: REG_REM_BITS], PER_OPC_NW_BITS, REG_REM_BITS)
        assign gpr_wr_addr = {writeback_if.data.sid, tmp};
    end else begin : g_gpr_wr_addr
        `CONCAT(gpr_wr_addr, writeback_if.data.wis[ISSUE_WIS_W-1 -: PER_OPC_NW_BITS],
              writeback_if.data.rd[NUM_REGS_BITS-1 -: REG_REM_BITS], PER_OPC_NW_BITS, REG_REM_BITS)
    end

    wire [BANK_SEL_WIDTH-1:0] gpr_wr_bank_idx;
    if (NUM_BANKS != 1) begin : g_gpr_wr_bank_idx_bn
        assign gpr_wr_bank_idx = writeback_if.data.rd[BANK_SEL_BITS-1:0];
    end else begin : g_gpr_wr_bank_idx_b1
        assign gpr_wr_bank_idx = '0;
    end

    wire [BANK_DATA_SIZE-1:0] gpr_wr_byteen;
    for (genvar i = 0; i < `SIMD_WIDTH; ++i) begin : g_gpr_wr_byteen
        assign gpr_wr_byteen[i*XLENB+:XLENB] = {XLENB{writeback_if.data.tmask[i]}};
    end

    // GPR banks
    for (genvar b = 0; b < NUM_BANKS; ++b) begin : g_gpr_rams
        wire gpr_wr_enabled;
        if (BANK_SEL_BITS != 0) begin : g_gpr_wr_enabled_bn
            assign gpr_wr_enabled = writeback_if.valid && (gpr_wr_bank_idx == BANK_SEL_BITS'(b));
        end else begin : g_gpr_wr_enabled_b1
            assign gpr_wr_enabled = writeback_if.valid;
        end

        wire [BANK_ADDR_WIDTH-1:0] gpr_rd_addr;
        if (SIMD_COUNT != 1) begin : g_gpr_rd_addr_sid
            wire [PER_OPC_NW_BITS + REG_REM_BITS-1:0] tmp;
            `CONCAT(tmp, pipe_mdata_st1[META_DATAW-UUID_WIDTH-1 -: PER_OPC_NW_BITS],
                gpr_rd_reg_st1[b], PER_OPC_NW_BITS, REG_REM_BITS)
            assign gpr_rd_addr = {pipe_mdata_st1[META_DATAW-UUID_WIDTH-ISSUE_WIS_W-1 -: SIMD_IDX_W], tmp};
        end else begin : g_gpr_rd_addr
            `CONCAT(gpr_rd_addr, pipe_mdata_st1[META_DATAW-UUID_WIDTH-1 -: PER_OPC_NW_BITS],
                gpr_rd_reg_st1[b], PER_OPC_NW_BITS, REG_REM_BITS)
        end

        VX_dp_ram #(
            .DATAW (BANK_DATA_WIDTH),
            .SIZE  (BANK_SIZE),
            .WRENW (BANK_DATA_SIZE),
         `ifdef GPR_RESET
            .RESET_RAM (1),
         `endif
            .OUT_REG (1),
            .RDW_MODE ("R")
        ) gpr_ram (
            .clk   (clk),
            .reset (reset),
            .read  (pipe_fire_st1),
            .wren  (gpr_wr_byteen),
            .write (gpr_wr_enabled),
            .waddr (gpr_wr_addr),
            .wdata (writeback_if.data.data),
            .raddr (gpr_rd_addr),
            .rdata (gpr_rd_data_st2[b])
        );
    end

    // output buffer
    VX_elastic_buffer #(
        .DATAW   (OUT_DATAW),
        .SIZE    (`TO_OUT_BUF_SIZE(OUT_BUF)),
        .OUT_REG (`TO_OUT_BUF_REG(OUT_BUF))
    ) out_buf (
        .clk      (clk),
        .reset    (reset),
        .valid_in (pipe_valid_st2),
        .ready_in (pipe_ready_st2),
        .data_in  ({pipe_mdata_st2[META_DATAW-1:2], // remove sop/eop
                    opd_buffer_n_st2, // operand data
                    pipe_mdata_st2[1:0]}), // sop/eop
        .data_out ({
            operands_if.data.uuid,
            operands_if.data.wis,
            operands_if.data.sid,
            operands_if.data.tmask,
            operands_if.data.PC,
            operands_if.data.wb,
            operands_if.data.ex_type,
            operands_if.data.op_type,
            operands_if.data.op_args,
            operands_if.data.rd,
            operands_if.data.rs3_data,
            operands_if.data.rs2_data,
            operands_if.data.rs1_data,
            operands_if.data.sop,
            operands_if.data.eop
        }),
        .valid_out(operands_if.valid),
        .ready_out(operands_if.ready)
    );

`ifdef PERF_ENABLE
    reg [PERF_CTR_BITS-1:0] collisions_r;
    always @(posedge clk) begin
        if (reset) begin
            collisions_r <= '0;
        end else begin
            collisions_r <= collisions_r + PERF_CTR_BITS'(scoreboard_if.valid && pipe_ready_in && has_collision);
        end
    end
    assign perf_stalls = collisions_r;
`endif

`ifndef SYNTHESIS
    // GPU_and_PNM (CAL per-run energy): register-file activity (sim-only). Every bank is read when pipe_fire_st1 is
    // high; gpr_bank_reads_useful counts the banks that carried a requested operand; writes are per warp and per lane.
    VX_sim_ctrs #(
        .N (4), .W (8),
        .NAMES ("gpr_read_cycles,gpr_bank_reads_useful,gpr_writes,gpr_write_lanes"),
        .INFO  ($sformatf("num_banks=%0d bank_size=%0d bank_data_width=%0d", NUM_BANKS, BANK_SIZE, BANK_DATA_WIDTH))
    ) sim_ctrs (
        .clk   (clk),
        .reset (reset),
        .inc   ({8'(writeback_if.valid ? $countones(writeback_if.data.tmask) : 0),
                 8'(writeback_if.valid),
                 8'(pipe_fire_st1 ? $countones(gpr_rd_valid_st1) : 0),
                 8'(pipe_fire_st1)})
    );
    // GPU_and_PNM (CAL per-run energy, Oct 26): data-bus bit flips per transfer (sim-only): at each valid transfer, the bits that
    // differ from the previous transfer on the same bus (what the receiving registers change when they load). Valid-qualified, so
    // invalid/X-assigned values never count. Added after the activity test showed data-dependent switching that event counts miss.
    reg [`SIMD_WIDTH-1:0][`XLEN-1:0] tgl_wb_last = '0;
    always @(posedge clk) begin
        if (writeback_if.valid) tgl_wb_last <= writeback_if.data.data;
    end
    VX_sim_ctrs #(
        .N (1), .W (16),
        .NAMES ("wb_data_flips")
    ) sim_tgl (
        .clk   (clk),
        .reset (reset),
        .inc   ({16'(writeback_if.valid ? $countones(writeback_if.data.data ^ tgl_wb_last) : 0)})
    );
    // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
    // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
    reg [$bits(writeback_if.data.data)-1:0] tgl_c0_q = '0;
    always @(posedge clk) begin
        tgl_c0_q <= writeback_if.data.data;
    end
    VX_sim_ctrs #(
        .N (1), .W (16),
        .NAMES ("wb_data_cyc")
    ) sim_cyc (
        .clk   (clk),
        .reset (reset),
        .inc   ({16'($countones(writeback_if.data.data ^ tgl_c0_q))})
    );
`endif

endmodule
