// GPU_and_PNM (CAL per-run energy): simulation-only activity counters.
// This file lives in hw/dpi (simulator include path only; the netlist generator never reads it), and every instance in
// the RTL sits inside an own-line `ifndef SYNTHESIS` block, so synthesis and the routed netlists are unaffected.
//
// N counters of increment width W share one snapshot poll. Each counter is 64-bit, starts at 0, is armed once its
// (relayed) reset has been held high for ARM_CYCLES consecutive cycles (relay registers can show a few random reset values
// at power-up before the real reset arrives; a real reset lasts much longer), and increments by inc[i] on every rising
// clock edge while armed and not in reset.
// Counters are cumulative across kernel launches (the device reset does not clear them).
// Snapshots: processor.cpp bumps an epoch (launch boundaries inside reset, trace start/stop); on the next edge every
// group writes its current values tagged with that epoch. A final dump (epoch -1) is written from the final block.
// NAMES is a comma-separated list of N counter names; INFO adds constant key=value pairs (geometry) to the dump.
module VX_sim_ctrs #(
    parameter N = 1,
    parameter W = 1,
    parameter string NAMES = "",
    parameter string INFO  = ""
) (
    input wire                 clk,
    input wire                 reset,
    input wire [N-1:0][W-1:0]  inc
);
`ifndef SYNTHESIS
    import "DPI-C" function int  dpi_ctr_epoch();
    import "DPI-C" function void dpi_ctr(input string scope, input string names, input string info,
                                         input int idx, input longint unsigned value, input int epoch);

    reg [63:0] cnt [N];
    localparam ARM_CYCLES = 8;
    reg        armed = 1'b0;
    reg [3:0]  rst_run = 4'd0;
    int        last_epoch = 0;
    string     scope;

    initial begin
        for (int i = 0; i < N; ++i) cnt[i] = '0;
        scope = $sformatf("%m");
    end

    always @(posedge clk) begin
        int e;
        if (reset) begin
            if (rst_run != 4'(ARM_CYCLES)) rst_run <= rst_run + 4'd1;
            if (rst_run == 4'(ARM_CYCLES - 1)) armed <= 1'b1;
        end else begin
            rst_run <= 4'd0;
        end
        if (!reset && armed) begin
            for (int i = 0; i < N; ++i) cnt[i] <= cnt[i] + 64'(inc[i]);
        end
        e = dpi_ctr_epoch();
        if (e != last_epoch) begin
            for (int i = 0; i < N; ++i) dpi_ctr(scope, NAMES, INFO, i, cnt[i], e);
            last_epoch <= e;
        end
    end

    final begin
        for (int i = 0; i < N; ++i) dpi_ctr(scope, NAMES, INFO, i, cnt[i], -1);
    end
`else
    // never synthesized (instances are guarded); keep the ports used for lint
    wire unused = &{1'b0, clk, reset, inc};
`endif
endmodule
