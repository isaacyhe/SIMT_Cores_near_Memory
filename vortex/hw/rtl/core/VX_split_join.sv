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

module VX_split_join import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter OUT_REG = 0
) (
    input  wire                     clk,
    input  wire                     reset,
    input  wire                     valid,
    input  wire [NW_WIDTH-1:0]      wid,
    input  split_t                  split,
    input  join_t                   sjoin,
    input  wire [NW_WIDTH-1:0]      stack_wid,
    output wire                     join_valid,
    output wire                     join_is_dvg,
    output wire                     join_is_else,
    output wire [NW_WIDTH-1:0]      join_wid,
    output wire [`NUM_THREADS-1:0]  join_tmask,
    output wire [PC_BITS-1:0]       join_pc,
    output wire [DV_STACK_SIZEW-1:0] stack_ptr
);
    `UNUSED_SPARAM (INSTANCE_ID)

    wire split_valid = valid && split.valid;
    wire sjoin_valid = valid && sjoin.valid;

    if (NT_BITS != 0) begin : g_enable
        wire [`NUM_WARPS-1:0][DV_STACK_SIZEW-1:0] ipdom_wr_ptr;
        wire [`NUM_THREADS-1:0] ipdom_tmask;
        wire [PC_BITS-1:0] ipdom_pc;
        wire ipdom_idx;

        wire [(`NUM_THREADS + PC_BITS)-1:0] ipdom_d0 = {split.then_tmask | split.else_tmask, PC_BITS'(0)};
        wire [(`NUM_THREADS + PC_BITS)-1:0] ipdom_d1 = {split.else_tmask, split.next_pc};

        wire sjoin_is_dvg = (sjoin.stack_ptr != ipdom_wr_ptr[wid]);

        wire ipdom_push = split_valid && split.is_dvg;
        wire ipdom_pop  = sjoin_valid && sjoin_is_dvg;

        VX_ipdom_stack #(
            .WIDTH (`NUM_THREADS + PC_BITS),
            .DEPTH (DV_STACK_SIZE)
        ) ipdom_stack (
            .clk   (clk),
            .reset (reset),
            .wid   (wid),
            .d0    (ipdom_d0),
            .d1    (ipdom_d1),
            .push  (ipdom_push),
            .pop   (ipdom_pop),
            .rd_ptr(sjoin.stack_ptr),
            .q_val ({ipdom_tmask, ipdom_pc}),
            .q_idx (ipdom_idx),
            .wr_ptr(ipdom_wr_ptr),
            `UNUSED_PIN (empty),
            `UNUSED_PIN (full)
        );
`ifndef SYNTHESIS
        // GPU_and_PNM (CAL per-run energy): IPDOM stack pushes and pops (each a stack RAM access) (sim-only)
        VX_sim_ctrs #(
            .N (2), .W (1),
            .NAMES ("ipdom_push,ipdom_pop")
        ) sim_ctrs (
            .clk   (clk),
            .reset (reset),
            .inc   ({ipdom_pop, ipdom_push})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): IPDOM stack data bit flips (sim-only): pushed entry {d1,d0} vs the previous
        // push, popped entry (q_val, read in the pop cycle) vs the previous pop. The stack and its output register carried ~40%
        // of the scheduler's toggles in the activity test, and divergent workloads (histogram) were under-predicted.
        reg [2*(`NUM_THREADS + PC_BITS)-1:0] tgl_push_last = '0;
        reg [(`NUM_THREADS + PC_BITS)-1:0] tgl_pop_last = '0;
        always @(posedge clk) begin
            if (ipdom_push) tgl_push_last <= {ipdom_d1, ipdom_d0};
            if (ipdom_pop)  tgl_pop_last  <= {ipdom_tmask, ipdom_pc};
        end
        VX_sim_ctrs #(
            .N (2), .W (8),
            .NAMES ("ipdom_push_flips,ipdom_pop_flips")
        ) sim_tgl (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'(ipdom_pop ? $countones({ipdom_tmask, ipdom_pc} ^ tgl_pop_last) : 0),
                     8'(ipdom_push ? $countones({ipdom_d1, ipdom_d0} ^ tgl_push_last) : 0)})
        );
        // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
        // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
        reg [2*(`NUM_THREADS + PC_BITS)-1:0] tgl_c0_q = '0;
        reg [(`NUM_THREADS + PC_BITS)-1:0] tgl_c1_q = '0;
        always @(posedge clk) begin
            tgl_c0_q <= {ipdom_d1, ipdom_d0};
            tgl_c1_q <= {ipdom_tmask, ipdom_pc};
        end
        VX_sim_ctrs #(
            .N (2), .W (8),
            .NAMES ("ipdom_d_cyc,ipdom_q_cyc")
        ) sim_cyc (
            .clk   (clk),
            .reset (reset),
            .inc   ({8'($countones({ipdom_tmask, ipdom_pc} ^ tgl_c1_q)),
                     8'($countones({ipdom_d1, ipdom_d0} ^ tgl_c0_q))})
        );
`endif


        VX_pipe_register #(
            .DATAW  (1 + NW_WIDTH + 1 +  1 + `NUM_THREADS + PC_BITS),
            .RESETW (1),
            .DEPTH  (OUT_REG)
        ) pipe_reg (
            .clk      (clk),
            .reset    (reset),
            .enable   (1'b1),
            .data_in  ({sjoin_valid, wid,      sjoin_is_dvg, ~ipdom_idx,   ipdom_tmask, ipdom_pc}),
            .data_out ({join_valid,  join_wid, join_is_dvg,  join_is_else, join_tmask,  join_pc})
        );

        assign stack_ptr = ipdom_wr_ptr[stack_wid];

    end else begin : g_disable

        `UNUSED_VAR (clk)
        `UNUSED_VAR (reset)
        `UNUSED_VAR (split)
        `UNUSED_VAR (sjoin)
        `UNUSED_VAR (wid)
        `UNUSED_VAR (stack_wid)
        `UNUSED_VAR (split_valid)
        assign join_valid = sjoin_valid;
        assign join_wid = wid;
        assign join_is_dvg = 0;
        assign join_is_else = 0;
        assign join_tmask = 1'b1;
        assign join_pc = '0;
        assign stack_ptr = '0;
        
    end

endmodule
