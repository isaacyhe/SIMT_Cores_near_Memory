// Quick and dirty reimplementation of DFFHQNx2_ASAP7_75t_R because
// Verialtor doesn't support and has no plans to support 1995 UDP
// tables.
//
// https://github.com/verilator/verilator/issues/5243

module DFFHQNx1_ASAP7_75t_R (QN, D, CLK);
    output reg QN;
    input D, CLK;

    always @(posedge CLK) begin
        QN <= ~D;
    end
endmodule

module DFFHQNx2_ASAP7_75t_R (QN, D, CLK);
    output reg QN;
    input D, CLK;

    always @(posedge CLK) begin
        QN <= ~D;
    end
endmodule

module DFFHQNx3_ASAP7_75t_R (QN, D, CLK);
    output reg QN;
    input D, CLK;

    always @(posedge CLK) begin
        QN <= ~D;
    end
endmodule

// GPU_and_PNM (Oct 31, fpnew netlists): asynchronous set/reset flop, from the liberty ff group of DFFASRHQNx1_ASAP7_75t_R:
// clear = !SETN (IQN -> 0), preset = !RESETN (IQN -> 1), both active -> L (IQN = 0), next_state = !D on CLK rise; QN = IQN.
module DFFASRHQNx1_ASAP7_75t_R (QN, D, CLK, RESETN, SETN);
    output reg QN;
    input D, CLK, RESETN, SETN;

    always @(posedge CLK or negedge SETN or negedge RESETN) begin
        if (!SETN)        QN <= 1'b0;
        else if (!RESETN) QN <= 1'b1;
        else              QN <= ~D;
    end
endmodule
