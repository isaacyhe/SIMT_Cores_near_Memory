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

module VX_issue_slice import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter ISSUE_ID = 0
) (
    `SCOPE_IO_DECL

    input wire              clk,
    input wire              reset,

`ifdef PERF_ENABLE
    output issue_perf_t     issue_perf,
`endif

    VX_decode_if.slave      decode_if,
    VX_writeback_if.slave   writeback_if,
    VX_dispatch_if.master   dispatch_if [NUM_EX_UNITS],
    VX_issue_sched_if.master issue_sched_if
);
    `UNUSED_PARAM (ISSUE_ID)

    VX_ibuffer_if ibuffer_if [PER_ISSUE_WARPS]();
    VX_scoreboard_if scoreboard_if();
    VX_operands_if operands_if();

    VX_ibuffer #(
        .INSTANCE_ID (`SFORMATF(("%s-ibuffer", INSTANCE_ID))),
        .ISSUE_ID (ISSUE_ID)
    ) ibuffer (
        .clk            (clk),
        .reset          (reset),
     `ifdef PERF_ENABLE
        .perf_stalls    (issue_perf.ibf_stalls),
     `endif
        .decode_if      (decode_if),
        .ibuffer_if     (ibuffer_if)
    );

    VX_scoreboard #(
        .INSTANCE_ID (`SFORMATF(("%s-scoreboard", INSTANCE_ID))),
        .ISSUE_ID (ISSUE_ID)
    ) scoreboard (
        .clk            (clk),
        .reset          (reset),
    `ifdef PERF_ENABLE
        .perf_stalls    (issue_perf.scb_stalls),
        .perf_units_uses(issue_perf.units_uses),
        .perf_sfu_uses  (issue_perf.sfu_uses),
    `endif
        .writeback_if   (writeback_if),
        .ibuffer_if     (ibuffer_if),
        .scoreboard_if  (scoreboard_if)
    );

    VX_operands #(
        .INSTANCE_ID (`SFORMATF(("%s-operands", INSTANCE_ID))),
        .ISSUE_ID (ISSUE_ID)
    ) operands (
        .clk            (clk),
        .reset          (reset),
     `ifdef PERF_ENABLE
        .perf_stalls    (issue_perf.opd_stalls),
     `endif
        .writeback_if   (writeback_if),
        .scoreboard_if  (scoreboard_if),
        .operands_if    (operands_if)
    );

    VX_dispatch #(
        .INSTANCE_ID (`SFORMATF(("%s-dispatch", INSTANCE_ID))),
        .ISSUE_ID (ISSUE_ID)
    ) dispatch (
        .clk            (clk),
        .reset          (reset),
    `ifdef PERF_ENABLE
        `UNUSED_PIN     (perf_stalls),
    `endif
        .operands_if    (operands_if),
        .dispatch_if    (dispatch_if)
    );

    // notify scheduler
    assign issue_sched_if.valid = operands_if.valid && operands_if.ready && operands_if.data.sop;
    assign issue_sched_if.wis = operands_if.data.wis;

`ifdef SCOPE
`ifdef DBG_SCOPE_ISSUE
    `SCOPE_IO_SWITCH (1);
    wire decode_fire = decode_if.valid && decode_if.ready;
    wire operands_fire = operands_if.valid && operands_if.ready;
    wire reset_negedge;
    `NEG_EDGE (reset_negedge, reset);
    `SCOPE_TAP_EX (0, 2, 4, 3, (
            UUID_WIDTH + NW_WIDTH + `NUM_THREADS + PC_BITS + EX_BITS + INST_OP_BITS + 1 + NUM_REGS_BITS * 4 +
            UUID_WIDTH + ISSUE_WIS_W + `SIMD_WIDTH + PC_BITS + EX_BITS + INST_OP_BITS + 1 + NUM_REGS_BITS + (3 * `XLEN) +
            UUID_WIDTH + ISSUE_WIS_W + `SIMD_WIDTH + NUM_REGS_BITS + (`SIMD_WIDTH * `XLEN) + 1
        ), {
            decode_if.valid,
            decode_if.ready,
            operands_if.valid,
            operands_if.ready
        }, {
            decode_fire,
            operands_fire,
            writeback_if.valid // ack-free
        }, {
            decode_if.data.uuid,
            decode_if.data.wid,
            decode_if.data.tmask,
            decode_if.data.PC,
            decode_if.data.ex_type,
            decode_if.data.op_type,
            decode_if.data.wb,
            decode_if.data.rd,
            decode_if.data.rs1,
            decode_if.data.rs2,
            decode_if.data.rs3,
            operands_if.data.uuid,
            operands_if.data.wis,
            operands_if.data.tmask,
            operands_if.data.PC,
            operands_if.data.ex_type,
            operands_if.data.op_type,
            operands_if.data.wb,
            operands_if.data.rd,
            operands_if.data.rs1_data[0],
            operands_if.data.rs2_data[0],
            operands_if.data.rs3_data[0],
            writeback_if.data.uuid,
            writeback_if.data.wis,
            writeback_if.data.tmask,
            writeback_if.data.rd,
            writeback_if.data.data,
            writeback_if.data.eop
        },
        reset_negedge, 1'b0, 4096
    );
`else
    `SCOPE_IO_UNUSED(0)
`endif
`endif

`ifdef CHIPSCOPE
`ifdef DBG_SCOPE_ISSUE
    ila_issue ila_issue_inst (
        .clk    (clk),
        .probe0 ({decode_if.valid, decode_if.data, decode_if.ready}),
        .probe1 ({scoreboard_if.valid, scoreboard_if.data, scoreboard_if.ready}),
        .probe2 ({operands_if.valid, operands_if.data, operands_if.ready}),
        .probe3 ({writeback_if.valid, writeback_if.data})
    );
`endif
`endif

`ifdef DBG_TRACE_PIPELINE
    for (genvar i = 0; i < PER_ISSUE_WARPS; ++i) begin : g_ibuffer_trace
        localparam wid = wis_to_wid(ISSUE_WIS_W'(i), ISSUE_ID);
        always @(posedge clk) begin
            if (ibuffer_if[i].valid && ibuffer_if[i].ready) begin
                `TRACE(1, ("%t: %s-ibuffer: wid=%0d, PC=0x%0h, ex=", $time, INSTANCE_ID, wid, to_fullPC(ibuffer_if[i].data.PC)))
                VX_trace_pkg::trace_ex_type(1, ibuffer_if[i].data.ex_type);
                `TRACE(1, (", op="))
                VX_trace_pkg::trace_ex_op(1, ibuffer_if[i].data.ex_type, ibuffer_if[i].data.op_type, ibuffer_if[i].data.op_args);
                `TRACE(1, (", tmask=%b, wb=%b, used_rs=%b, rd=", ibuffer_if[i].data.tmask, ibuffer_if[i].data.wb, ibuffer_if[i].data.used_rs))
                VX_trace_pkg::trace_reg_idx(1, ibuffer_if[i].data.rd);
                `TRACE(1, (", rs1="))
                VX_trace_pkg::trace_reg_idx(1, ibuffer_if[i].data.rs1);
                `TRACE(1, (", rs2="))
                VX_trace_pkg::trace_reg_idx(1, ibuffer_if[i].data.rs2);
                `TRACE(1, (", rs3="))
                VX_trace_pkg::trace_reg_idx(1, ibuffer_if[i].data.rs3);
                `TRACE(1, (", "))
                VX_trace_pkg::trace_op_args(1, ibuffer_if[i].data.ex_type, ibuffer_if[i].data.op_type, ibuffer_if[i].data.op_args);
                `TRACE(1, (" (#%0d)\n", ibuffer_if[i].data.uuid))
            end
        end
    end

    always @(posedge clk) begin
        if (operands_if.valid && operands_if.ready) begin
            `TRACE(1, ("%t: %s-dispatch: wid=%0d, sid=%0d, PC=0x%0h, ex=", $time, INSTANCE_ID, wis_to_wid(operands_if.data.wis, ISSUE_ID), operands_if.data.sid, to_fullPC(operands_if.data.PC)))
            VX_trace_pkg::trace_ex_type(1, operands_if.data.ex_type);
            `TRACE(1, (", op="))
            VX_trace_pkg::trace_ex_op(1, operands_if.data.ex_type, operands_if.data.op_type, operands_if.data.op_args);
            `TRACE(1, (", tmask=%b, wb=%b, rd=%0d, rs1_data=", operands_if.data.tmask, operands_if.data.wb, operands_if.data.rd))
            `TRACE_ARRAY1D(1, "0x%0h", operands_if.data.rs1_data, `SIMD_WIDTH)
            `TRACE(1, (", rs2_data="))
            `TRACE_ARRAY1D(1, "0x%0h", operands_if.data.rs2_data, `SIMD_WIDTH)
            `TRACE(1, (", rs3_data="))
            `TRACE_ARRAY1D(1, "0x%0h", operands_if.data.rs3_data, `SIMD_WIDTH)
            `TRACE(1, (", "))
           VX_trace_pkg::trace_op_args(1, operands_if.data.ex_type, operands_if.data.op_type, operands_if.data.op_args);
            `TRACE(1, (", sop=%b, eop=%b (#%0d)\n", operands_if.data.sop, operands_if.data.eop, operands_if.data.uuid))
        end
    end
`endif

`ifndef SYNTHESIS
    // GPU_and_PNM (CAL per-run energy): issued warp instructions per execution unit and active lanes (sim-only)
    wire ctr_fire = operands_if.valid && operands_if.ready;
    wire [7:0] ctr_lanes = 8'($countones(operands_if.data.tmask));
    wire ctr_is_alu = (operands_if.data.ex_type == EX_BITS'(EX_ALU));
    wire ctr_is_lsu = (operands_if.data.ex_type == EX_BITS'(EX_LSU));
    wire ctr_is_sfu = (operands_if.data.ex_type == EX_BITS'(EX_SFU));
    wire ctr_is_fpu = `EXT_F_ENABLED && (operands_if.data.ex_type == EX_BITS'(EX_FPU));
    wire ctr_sfu_wctl = ctr_is_sfu && inst_sfu_is_wctl(INST_SFU_BITS'(operands_if.data.op_type));
    wire ctr_sfu_csr  = ctr_is_sfu && inst_sfu_is_csr(INST_SFU_BITS'(operands_if.data.op_type));
    wire ctr_sfu_bar  = ctr_is_sfu && (INST_SFU_BITS'(operands_if.data.op_type) == INST_SFU_BAR);
    VX_sim_ctrs #(
        .N (11), .W (8),
        .NAMES ("issue_any,issue_alu,issue_lsu,issue_sfu_wctl,issue_sfu_csr,issue_sfu_bar,issue_fpu,lanes_alu,lanes_lsu,lanes_sfu,lanes_fpu")
    ) sim_ctrs (
        .clk   (clk),
        .reset (reset),
        .inc   ({8'(ctr_fire && ctr_is_fpu ? ctr_lanes : 8'd0),
                 8'(ctr_fire && ctr_is_sfu ? ctr_lanes : 8'd0),
                 8'(ctr_fire && ctr_is_lsu ? ctr_lanes : 8'd0),
                 8'(ctr_fire && ctr_is_alu ? ctr_lanes : 8'd0),
                 8'(ctr_fire && ctr_is_fpu),
                 8'(ctr_fire && ctr_sfu_bar),
                 8'(ctr_fire && ctr_sfu_csr),
                 8'(ctr_fire && ctr_sfu_wctl),
                 8'(ctr_fire && ctr_is_lsu),
                 8'(ctr_fire && ctr_is_alu),
                 8'(ctr_fire)})
    );
    // GPU_and_PNM (CAL per-run energy, Oct 26): data-bus bit flips per transfer (sim-only): at each valid transfer, the bits that
    // differ from the previous transfer on the same bus (what the receiving registers change when they load). Valid-qualified, so
    // invalid/X-assigned values never count. Added after the activity test showed data-dependent switching that event counts miss.
    wire [3*`SIMD_WIDTH*`XLEN-1:0] tgl_opd = {operands_if.data.rs3_data, operands_if.data.rs2_data, operands_if.data.rs1_data};
    reg  [3*`SIMD_WIDTH*`XLEN-1:0] tgl_opd_last = '0;
    always @(posedge clk) begin
        if (ctr_fire) tgl_opd_last <= tgl_opd;
    end
    VX_sim_ctrs #(
        .N (1), .W (16),
        .NAMES ("opd_data_flips")
    ) sim_tgl (
        .clk   (clk),
        .reset (reset),
        .inc   ({16'(ctr_fire ? $countones(tgl_opd ^ tgl_opd_last) : 0)})
    );
    // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
    // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
    reg [3*`SIMD_WIDTH*`XLEN-1:0] tgl_c0_q = '0;
    always @(posedge clk) begin
        tgl_c0_q <= tgl_opd;
    end
    VX_sim_ctrs #(
        .N (1), .W (16),
        .NAMES ("opd_data_cyc")
    ) sim_cyc (
        .clk   (clk),
        .reset (reset),
        .inc   ({16'($countones(tgl_opd ^ tgl_c0_q))})
    );
`endif

endmodule
