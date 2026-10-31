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

module VX_alu_unit import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = ""
) (
    input wire              clk,
    input wire              reset,

    // Inputs
    VX_dispatch_if.slave    dispatch_if [`ISSUE_WIDTH],

    // Outputs
    VX_commit_if.master     commit_if [`ISSUE_WIDTH],
    VX_branch_ctl_if.master branch_ctl_if [`NUM_ALU_BLOCKS]
);

    `UNUSED_SPARAM (INSTANCE_ID)
    localparam BLOCK_SIZE   = `NUM_ALU_BLOCKS;
    localparam NUM_LANES    = `NUM_ALU_LANES;
    localparam PARTIAL_BW   = (BLOCK_SIZE != `ISSUE_WIDTH) || (NUM_LANES != `SIMD_WIDTH);
    localparam PE_COUNT     = 1 + `EXT_M_ENABLED;
    localparam PE_SEL_BITS  = `CLOG2(PE_COUNT);
    localparam PE_IDX_INT   = 0;
    localparam PE_IDX_MDV   = PE_IDX_INT + `EXT_M_ENABLED;

    VX_execute_if #(
        .data_t (alu_exe_t)
    ) per_block_execute_if[BLOCK_SIZE]();

    VX_result_if #(
        .data_t (alu_res_t)
    ) per_block_result_if[BLOCK_SIZE]();

    VX_dispatch_unit #(
        .BLOCK_SIZE (BLOCK_SIZE),
        .NUM_LANES  (NUM_LANES),
        .OUT_BUF    (PARTIAL_BW ? 3 : 0)
    ) dispatch_unit (
        .clk        (clk),
        .reset      (reset),
        .dispatch_if(dispatch_if),
        .execute_if (per_block_execute_if)
    );

    for (genvar block_idx = 0; block_idx < BLOCK_SIZE; ++block_idx) begin : g_blocks

        VX_execute_if #(
            .data_t (alu_exe_t)
        ) pe_execute_if[PE_COUNT]();

        VX_result_if#(
            .data_t (alu_res_t)
        ) pe_result_if[PE_COUNT]();

        reg [`UP(PE_SEL_BITS)-1:0] pe_select;
        always @(*) begin
            pe_select = PE_IDX_INT;
            if (`EXT_M_ENABLED && (per_block_execute_if[block_idx].data.op_args.alu.xtype == ALU_TYPE_MULDIV))
                pe_select = PE_IDX_MDV;
        end

`ifndef SYNTHESIS
        // GPU_and_PNM (CAL per-run energy): ALU block operations by type, and active lanes (sim-only)
        wire ctr_fire = per_block_execute_if[block_idx].valid && per_block_execute_if[block_idx].ready;
        wire [ALU_TYPE_BITS-1:0] ctr_xtype = per_block_execute_if[block_idx].data.op_args.alu.xtype;
        VX_sim_ctrs #(
            .N (5), .W (8),
            .NAMES ("alu_arith,alu_branch,alu_muldiv,alu_other,alu_lanes")
        ) sim_ctrs (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'(ctr_fire ? $countones(per_block_execute_if[block_idx].data.tmask) : 0),
                     8'(ctr_fire && ctr_xtype == ALU_TYPE_BITS'(ALU_TYPE_OTHER)),
                     8'(ctr_fire && ctr_xtype == ALU_TYPE_BITS'(ALU_TYPE_MULDIV)),
                     8'(ctr_fire && ctr_xtype == ALU_TYPE_BITS'(ALU_TYPE_BRANCH)),
                     8'(ctr_fire && ctr_xtype == ALU_TYPE_BITS'(ALU_TYPE_ARITH))})
        );
`endif

        VX_pe_switch #(
            .PE_COUNT    (PE_COUNT),
            .NUM_LANES   (NUM_LANES),
            .ARBITER     ("R"),
            .REQ_OUT_BUF (0),
            .RSP_OUT_BUF (PARTIAL_BW ? 1 : 3)
        ) pe_switch (
            .clk            (clk),
            .reset          (reset),
            .pe_sel         (pe_select),
            .execute_in_if  (per_block_execute_if[block_idx]),
            .result_out_if  (per_block_result_if[block_idx]),
            .execute_out_if (pe_execute_if),
            .result_in_if   (pe_result_if)
        );

        VX_alu_int #(
            .INSTANCE_ID (`SFORMATF(("%s-int%0d", INSTANCE_ID, block_idx))),
            .BLOCK_IDX (block_idx),
            .NUM_LANES (NUM_LANES)
        ) alu_int (
            .clk        (clk),
            .reset      (reset),
            .execute_if (pe_execute_if[PE_IDX_INT]),
            .branch_ctl_if (branch_ctl_if[block_idx]),
            .result_if  (pe_result_if[PE_IDX_INT])
        );

    `ifdef EXT_M_ENABLE
        VX_alu_muldiv #(
            .INSTANCE_ID (`SFORMATF(("%s-muldiv%0d", INSTANCE_ID, block_idx))),
            .NUM_LANES (NUM_LANES)
        ) muldiv_unit (
            .clk        (clk),
            .reset      (reset),
            .execute_if (pe_execute_if[PE_IDX_MDV]),
            .result_if  (pe_result_if[PE_IDX_MDV])
        );
    `endif
    end

    VX_gather_unit #(
        .BLOCK_SIZE (BLOCK_SIZE),
        .NUM_LANES  (NUM_LANES),
        .OUT_BUF    (PARTIAL_BW ? 3 : 0)
    ) gather_unit (
        .clk       (clk),
        .reset     (reset),
        .result_if (per_block_result_if),
        .commit_if (commit_if)
    );

`ifndef SYNTHESIS
    // GPU_and_PNM (CAL per-run energy, Oct 27): every-cycle bit changes on this unit's dispatch input (sim-only, no valid
    // qualifier; deterministic with the zero-init energy build). All payload fields but the simulation-only uuid. The shared
    // operand bus before dispatch and the multiply/divide input did not cover the per-unit buses (mlp, kmeans under-predicted).
    for (genvar i = 0; i < `ISSUE_WIDTH; ++i) begin : g_sim_cyc
        wire [$bits(dispatch_if[i].data)-UUID_WIDTH-1:0] tgl_d = {dispatch_if[i].data.wis, dispatch_if[i].data.sid, dispatch_if[i].data.tmask,
            dispatch_if[i].data.PC, dispatch_if[i].data.op_type, dispatch_if[i].data.op_args, dispatch_if[i].data.wb, dispatch_if[i].data.rd,
            dispatch_if[i].data.rs1_data, dispatch_if[i].data.rs2_data, dispatch_if[i].data.rs3_data, dispatch_if[i].data.sop, dispatch_if[i].data.eop};
        reg [$bits(dispatch_if[i].data)-UUID_WIDTH-1:0] tgl_d_q = '0;
        always @(posedge clk) begin
            tgl_d_q <= tgl_d;
        end
        VX_sim_ctrs #(
            .N (1), .W (16),
            .NAMES ("alu_disp_cyc")
        ) sim_cyc (
            .clk   (clk),
            .reset (reset),
            .inc   ({16'($countones(tgl_d ^ tgl_d_q))})
        );
    end
`endif

endmodule
