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

module VX_alu_muldiv import VX_gpu_pkg::*; #(
    parameter `STRING INSTANCE_ID = "",
    parameter NUM_LANES = 1
) (
    input wire          clk,
    input wire          reset,

    // Inputs
    VX_execute_if.slave execute_if,

    // Outputs
    VX_result_if.master result_if
);
    `UNUSED_SPARAM (INSTANCE_ID)
    localparam PID_BITS  = `CLOG2(`NUM_THREADS / NUM_LANES);
    localparam PID_WIDTH = `UP(PID_BITS);
    localparam TAG_WIDTH = UUID_WIDTH + NW_WIDTH + NUM_LANES + PC_BITS + NUM_REGS_BITS + 1 + PID_WIDTH + 1 + 1;

    `UNUSED_VAR (execute_if.data.rs3_data)

    wire [INST_M_BITS-1:0] muldiv_op = INST_M_BITS'(execute_if.data.op_type);

    wire is_mulx_op = inst_m_is_mulx(muldiv_op);
    wire is_signed_op = inst_m_signed(muldiv_op);
`ifdef XLEN_64
    wire is_alu_w = execute_if.data.op_args.alu.is_w;
`else
    wire is_alu_w = 0;
`endif

    wire [NUM_LANES-1:0][`XLEN-1:0] mul_result_out;
    wire [UUID_WIDTH-1:0] mul_uuid_out;
    wire [NW_WIDTH-1:0] mul_wid_out;
    wire [NUM_LANES-1:0] mul_tmask_out;
    wire [PC_BITS-1:0] mul_PC_out;
    wire [NUM_REGS_BITS-1:0] mul_rd_out;
    wire mul_wb_out;
    wire [PID_WIDTH-1:0] mul_pid_out;
    wire mul_sop_out, mul_eop_out;

    wire mul_valid_in = execute_if.valid && is_mulx_op;
    wire mul_ready_in;
    wire mul_valid_out;
    wire mul_ready_out;

    wire is_mulh_in      = inst_m_is_mulh(muldiv_op);
    wire is_signed_mul_a = inst_m_signed_a(muldiv_op);
    wire is_signed_mul_b = is_signed_op;

`ifdef IMUL_DPI

    wire [NUM_LANES-1:0][`XLEN-1:0] mul_result_tmp;

    wire mul_fire_in = mul_valid_in && mul_ready_in;

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_mul_result_tmp
        reg [`XLEN-1:0] mul_resultl, mul_resulth;
        wire [`XLEN-1:0] mul_in1 = is_alu_w ? (execute_if.data.rs1_data[i] & `XLEN'hFFFFFFFF) : execute_if.data.rs1_data[i];
        wire [`XLEN-1:0] mul_in2 = is_alu_w ? (execute_if.data.rs2_data[i] & `XLEN'hFFFFFFFF) : execute_if.data.rs2_data[i];
        always @(*) begin
            dpi_imul (mul_fire_in, is_signed_mul_a, is_signed_mul_b, mul_in1, mul_in2, mul_resultl, mul_resulth);
        end
        assign mul_result_tmp[i] = is_mulh_in ? mul_resulth : (is_alu_w ? `XLEN'($signed(mul_resultl[31:0])) : mul_resultl);
    end

    VX_shift_register #(
        .DATAW  (1 + TAG_WIDTH + (NUM_LANES * `XLEN)),
        .DEPTH  (`LATENCY_IMUL),
        .RESETW (1)
    ) mul_shift_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (mul_ready_in),
        .data_in  ({mul_valid_in,  execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.PC, execute_if.data.rd, execute_if.data.wb, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop, mul_result_tmp}),
        .data_out ({mul_valid_out, mul_uuid_out,         mul_wid_out,         mul_tmask_out,         mul_PC_out,         mul_rd_out,         mul_wb_out,         mul_pid_out,         mul_sop_out,         mul_eop_out,         mul_result_out})
    );

    assign mul_ready_in = mul_ready_out || ~mul_valid_out;

`else

    wire [NUM_LANES-1:0][2*(`XLEN+1)-1:0] mul_result_tmp;
    wire is_mulh_out;
    wire is_mul_w_out;

`ifdef XLEN_64

    wire [NUM_LANES-1:0][`XLEN:0] mul_in1;
    wire [NUM_LANES-1:0][`XLEN:0] mul_in2;

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_mul_in
        assign mul_in1[i] = is_alu_w ? {{(`XLEN-31){execute_if.data.rs1_data[i][31]}}, execute_if.data.rs1_data[i][31:0]} : {is_signed_mul_a && execute_if.data.rs1_data[i][`XLEN-1], execute_if.data.rs1_data[i]};
        assign mul_in2[i] = is_alu_w ? {{(`XLEN-31){execute_if.data.rs2_data[i][31]}}, execute_if.data.rs2_data[i][31:0]} : {is_signed_mul_b && execute_if.data.rs2_data[i][`XLEN-1], execute_if.data.rs2_data[i]};
    end

    wire mul_strode;
    wire mul_busy;

    VX_elastic_adapter mul_elastic_adapter (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (mul_valid_in),
        .ready_in  (mul_ready_in),
        .valid_out (mul_valid_out),
        .ready_out (mul_ready_out),
        .strobe    (mul_strode),
        .busy      (mul_busy)
    );

    VX_serial_mul #(
        .A_WIDTH (`XLEN+1),
        .LANES   (NUM_LANES),
        .SIGNED  (1)
    ) serial_mul (
        .clk       (clk),
        .reset     (reset),

        .strobe    (mul_strode),
        .busy      (mul_busy),

        .dataa     (mul_in1),
        .datab     (mul_in2),
        .result    (mul_result_tmp)
    );

    reg [TAG_WIDTH+2-1:0] mul_tag_r;
    always @(posedge clk) begin
        if (mul_valid_in && mul_ready_in) begin
            mul_tag_r <= {execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.PC, execute_if.data.rd, execute_if.data.wb, is_mulh_in, is_alu_w, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop};
        end
    end

    assign {mul_uuid_out, mul_wid_out, mul_tmask_out, mul_PC_out, mul_rd_out, mul_wb_out, is_mulh_out, is_mul_w_out, mul_pid_out, mul_sop_out, mul_eop_out} = mul_tag_r;

`else

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_multiplier
        wire [`XLEN:0] mul_in1 = {is_signed_mul_a && execute_if.data.rs1_data[i][`XLEN-1], execute_if.data.rs1_data[i]};
        wire [`XLEN:0] mul_in2 = {is_signed_mul_b && execute_if.data.rs2_data[i][`XLEN-1], execute_if.data.rs2_data[i]};

        VX_multiplier #(
            .A_WIDTH (`XLEN+1),
            .B_WIDTH (`XLEN+1),
            .R_WIDTH (2*(`XLEN+1)),
            .SIGNED  (1),
            .LATENCY (`LATENCY_IMUL)
        ) multiplier (
            .clk    (clk),
            .enable (mul_ready_in),
            .dataa  (mul_in1),
            .datab  (mul_in2),
            .result (mul_result_tmp[i])
        );
    end

    VX_shift_register #(
        .DATAW  (1 + TAG_WIDTH + 1 + 1),
        .DEPTH  (`LATENCY_IMUL),
        .RESETW (1)
    ) mul_shift_reg (
        .clk      (clk),
        .reset    (reset),
        .enable   (mul_ready_in),
        .data_in  ({mul_valid_in,  execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.PC, execute_if.data.rd, execute_if.data.wb, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop, is_mulh_in,  is_alu_w}),
        .data_out ({mul_valid_out, mul_uuid_out,         mul_wid_out,         mul_tmask_out,         mul_PC_out,         mul_rd_out,         mul_wb_out,         mul_pid_out,         mul_sop_out,         mul_eop_out,         is_mulh_out, is_mul_w_out})
    );

    assign mul_ready_in = mul_ready_out || ~mul_valid_out;

`endif

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_mul_result_out
    `ifdef XLEN_64
        assign mul_result_out[i] = is_mulh_out ? mul_result_tmp[i][2*(`XLEN)-1:`XLEN] :
                                                 (is_mul_w_out ? `XLEN'($signed(mul_result_tmp[i][31:0])) :
                                                                 mul_result_tmp[i][`XLEN-1:0]);
    `else
        assign mul_result_out[i] = is_mulh_out ? mul_result_tmp[i][2*(`XLEN)-1:`XLEN] : mul_result_tmp[i][`XLEN-1:0];
        `UNUSED_VAR (is_mul_w_out)
    `endif
    end

`endif

    ///////////////////////////////////////////////////////////////////////////

`ifndef IDIV_DISABLE
    wire [NUM_LANES-1:0][`XLEN-1:0] div_result_out;
    wire [UUID_WIDTH-1:0] div_uuid_out;
    wire [NW_WIDTH-1:0] div_wid_out;
    wire [NUM_LANES-1:0] div_tmask_out;
    wire [PC_BITS-1:0] div_PC_out;
    wire [NUM_REGS_BITS-1:0] div_rd_out;
    wire div_wb_out;
    wire [PID_WIDTH-1:0] div_pid_out;
    wire div_sop_out, div_eop_out;

    wire is_rem_op = inst_m_is_rem(muldiv_op);

    wire div_valid_in = execute_if.valid && ~is_mulx_op;
    wire div_ready_in;
    wire div_valid_out;
    wire div_ready_out;

    wire [NUM_LANES-1:0][`XLEN-1:0] div_in1;
    wire [NUM_LANES-1:0][`XLEN-1:0] div_in2;

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_div_in
    `ifdef XLEN_64
        assign div_in1[i] = is_alu_w ? {{(`XLEN-32){is_signed_op && execute_if.data.rs1_data[i][31]}}, execute_if.data.rs1_data[i][31:0]}: execute_if.data.rs1_data[i];
        assign div_in2[i] = is_alu_w ? {{(`XLEN-32){is_signed_op && execute_if.data.rs2_data[i][31]}}, execute_if.data.rs2_data[i][31:0]}: execute_if.data.rs2_data[i];
    `else
        assign div_in1[i] = execute_if.data.rs1_data[i];
        assign div_in2[i] = execute_if.data.rs2_data[i];
    `endif
    end

`ifdef IDIV_DPI

    wire [NUM_LANES-1:0][`XLEN-1:0] div_result_in;
    wire div_fire_in = div_valid_in && div_ready_in;

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_div_result_in
        reg [`XLEN-1:0] div_quotient, div_remainder;
        always @(*) begin
            dpi_idiv (div_fire_in, is_signed_op, div_in1[i], div_in2[i], div_quotient, div_remainder);
        end
        assign div_result_in[i] = is_rem_op ? (is_alu_w ? `XLEN'($signed(div_remainder[31:0])) : div_remainder) :
                                              (is_alu_w ? `XLEN'($signed(div_quotient[31:0])) : div_quotient);
    end

    VX_shift_register #(
        .DATAW  (1 + TAG_WIDTH + (NUM_LANES * `XLEN)),
        .DEPTH  (`LATENCY_IDIV),
        .RESETW (1)
    ) div_shift_reg (
        .clk(clk),
        .reset    (reset),
        .enable   (div_ready_in),
        .data_in  ({div_valid_in,  execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.PC, execute_if.data.rd, execute_if.data.wb, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop, div_result_in}),
        .data_out ({div_valid_out, div_uuid_out,         div_wid_out,         div_tmask_out,         div_PC_out,         div_rd_out,         div_wb_out,         div_pid_out,         div_sop_out,         div_eop_out,         div_result_out})
    );

    assign div_ready_in = div_ready_out || ~div_valid_out;

`else

    wire [NUM_LANES-1:0][`XLEN-1:0] div_quotient, div_remainder;
    wire is_rem_op_out;
    wire is_div_w_out;
    wire div_strode;
    wire div_busy;

    VX_elastic_adapter div_elastic_adapter (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (div_valid_in),
        .ready_in  (div_ready_in),
        .valid_out (div_valid_out),
        .ready_out (div_ready_out),
        .strobe    (div_strode),
        .busy      (div_busy)
    );

    VX_serial_div #(
        .WIDTHN (`XLEN),
        .WIDTHD (`XLEN),
        .WIDTHQ (`XLEN),
        .WIDTHR (`XLEN),
        .LANES  (NUM_LANES)
    ) serial_div (
        .clk       (clk),
        .reset     (reset),

        .strobe    (div_strode),
        .busy      (div_busy),

        .is_signed (is_signed_op),
        .numer     (div_in1),
        .denom     (div_in2),

        .quotient  (div_quotient),
        .remainder (div_remainder)
    );

    reg [TAG_WIDTH+2-1:0] div_tag_r;
    always @(posedge clk) begin
        if (div_valid_in && div_ready_in) begin
            div_tag_r <= {execute_if.data.uuid, execute_if.data.wid, execute_if.data.tmask, execute_if.data.PC, execute_if.data.rd, execute_if.data.wb, is_rem_op, is_alu_w, execute_if.data.pid, execute_if.data.sop, execute_if.data.eop};
        end
    end

    assign {div_uuid_out, div_wid_out, div_tmask_out, div_PC_out, div_rd_out, div_wb_out, is_rem_op_out, is_div_w_out, div_pid_out, div_sop_out, div_eop_out} = div_tag_r;

    for (genvar i = 0; i < NUM_LANES; ++i) begin : g_div_result_out
    `ifdef XLEN_64
        assign div_result_out[i] = is_rem_op_out ? (is_div_w_out ? `XLEN'($signed(div_remainder[i][31:0])) : div_remainder[i]) :
                                                   (is_div_w_out ? `XLEN'($signed(div_quotient[i][31:0])) : div_quotient[i]);
    `else
        assign div_result_out[i] = is_rem_op_out ? div_remainder[i] : div_quotient[i];
        `UNUSED_VAR (is_div_w_out)
    `endif
    end

`endif // IDIV_DPI

    // can accept new request?
    assign execute_if.ready = is_mulx_op ? mul_ready_in : div_ready_in;

`else
    // Integer DIV hardware removed - tie off signals
    wire [NUM_LANES-1:0][`XLEN-1:0] div_result_out = '0;
    wire [UUID_WIDTH-1:0] div_uuid_out = '0;
    wire [NW_WIDTH-1:0] div_wid_out = '0;
    wire [NUM_LANES-1:0] div_tmask_out = '0;
    wire [PC_BITS-1:0] div_PC_out = '0;
    wire [NUM_REGS_BITS-1:0] div_rd_out = '0;
    wire div_wb_out = 1'b0;
    wire [PID_WIDTH-1:0] div_pid_out = '0;
    wire div_sop_out = 1'b0;
    wire div_eop_out = 1'b0;
    wire div_valid_out = 1'b0;
    wire div_ready_out;
    wire div_ready_in = 1'b1;  // Always ready (drops div requests)
    assign execute_if.ready = is_mulx_op ? mul_ready_in : 1'b1;
    `UNUSED_VAR (div_ready_out)
    `UNUSED_VAR (div_ready_in)
`ifndef SYNTHESIS
    // GPU_and_PNM (Oct 28): soft-IDIV configs must never issue div/rem (the request would be dropped and its writeback never come)
    always @(posedge clk) begin
        if (~reset && execute_if.valid && ~is_mulx_op) begin
            $error("%t: VX_alu_muldiv: integer div/rem issued with IDIV_DISABLE (no divider in hardware)", $time);
        end
    end
`endif
`endif // IDIV_DISABLE

    VX_stream_arb #(
        .NUM_INPUTS (2),
        .DATAW (TAG_WIDTH + (NUM_LANES * `XLEN)),
        .ARBITER ("P"),
        .OUT_BUF (2)
    ) rsp_buf (
        .clk       (clk),
        .reset     (reset),
        .valid_in  ({div_valid_out, mul_valid_out}),
        .ready_in  ({div_ready_out, mul_ready_out}),
        .data_in   ({{div_uuid_out, div_wid_out, div_tmask_out, div_PC_out, div_rd_out, div_wb_out, div_pid_out, div_sop_out, div_eop_out, div_result_out},
                     {mul_uuid_out, mul_wid_out, mul_tmask_out, mul_PC_out, mul_rd_out, mul_wb_out, mul_pid_out, mul_sop_out, mul_eop_out, mul_result_out}}),
        .data_out  ({result_if.data.uuid, result_if.data.wid, result_if.data.tmask, result_if.data.PC, result_if.data.rd, result_if.data.wb, result_if.data.pid, result_if.data.sop, result_if.data.eop, result_if.data.data}),
        .valid_out (result_if.valid),
        .ready_out (result_if.ready),
        `UNUSED_PIN (sel_out)
    );

`ifndef SYNTHESIS
    // GPU_and_PNM (CAL per-run energy): integer multiply/divide operations and serial-divider busy cycles (sim-only)
`ifndef IDIV_DISABLE
`ifdef IDIV_DPI
    wire ctr_div_busy = 1'b0;  // DPI divider model: no serial busy state
`else
    wire ctr_div_busy = div_busy;
`endif
    VX_sim_ctrs #(
        .N (3), .W (1),
        .NAMES ("imul_fire,idiv_fire,idiv_busy_cycles")
    ) sim_ctrs (
        .clk   (clk),
        .reset (reset),
        .inc   ({ctr_div_busy, div_valid_in && div_ready_in, mul_valid_in && mul_ready_in})
    );
`else
    VX_sim_ctrs #(
        .N (1), .W (1),
        .NAMES ("imul_fire")
    ) sim_ctrs (
        .clk   (clk),
        .reset (reset),
        .inc   (mul_valid_in && mul_ready_in)
    );
`endif
    // GPU_and_PNM (CAL per-run energy, Oct 26): operand bit flips at this unit's own input (sim-only), per accepted request:
    // popcount({rs2,rs1} ^ the previous accepted request's operands), separately for the multiplier and the divider. The shared
    // operand-bus counter (opd_data_flips) mixes all units; the activity test left multiply/divide under-predicted (17%).
    wire tgl_mul = mul_valid_in && mul_ready_in;
`ifndef IDIV_DISABLE
    wire tgl_div = div_valid_in && div_ready_in;
`else
    wire tgl_div = 1'b0;
`endif
    wire [2*$bits(execute_if.data.rs1_data)-1:0] tgl_opd = {execute_if.data.rs2_data, execute_if.data.rs1_data};
    reg [2*$bits(execute_if.data.rs1_data)-1:0] tgl_mul_last = '0, tgl_div_last = '0;
    always @(posedge clk) begin
        if (tgl_mul) tgl_mul_last <= tgl_opd;
        if (tgl_div) tgl_div_last <= tgl_opd;
    end
    VX_sim_ctrs #(
        .N (2), .W (16),
        .NAMES ("mul_opd_flips,div_opd_flips")
    ) sim_tgl (
        .clk   (clk),
        .reset (reset),
        .inc   ({16'(tgl_div ? $countones(tgl_opd ^ tgl_div_last) : 0),
                 16'(tgl_mul ? $countones(tgl_opd ^ tgl_mul_last) : 0)})
    );
    // GPU_and_PNM (CAL per-run energy, Oct 26): every-cycle bit changes on the same buses (sim-only, no valid qualifier): the wire
    // toggles themselves, including cycles without a transfer. Deterministic only with the zero-init energy build (sim/rtlsim/Makefile).
    reg [$bits(tgl_opd)-1:0] tgl_c0_q = '0;
    always @(posedge clk) begin
        tgl_c0_q <= tgl_opd;
    end
    VX_sim_ctrs #(
        .N (1), .W (16),
        .NAMES ("mdu_opd_cyc")
    ) sim_cyc (
        .clk   (clk),
        .reset (reset),
        .inc   ({16'($countones(tgl_opd ^ tgl_c0_q))})
    );
`endif

endmodule
