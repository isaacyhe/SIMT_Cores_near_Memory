// Byte-write-enable functional models for the masked fakeram SRAM macros.
//
// Companion to fakeram7_NxM.v (whole-word). These add a per-byte write mask
// (wmask_in) so the cache data RAMs and local memory can do partial/byte writes
// correctly. Used for ALL USE_FAKERAM data RAMs (icache writes all bytes via an
// all-ones mask; dcache masks with line_wren). Power/area/timing come from the
// matching .lib (regenerate the macro with FakeRAM2.0 --write_mask); this .v only
// generates sim activity.
//
// Interface = stock FakeRAM2.0 --write_mask SRAM (clk/ce_in/we_in/wmask_in/
// addr_in/wd_in/rd_out) -- NO separate read-enable. The cache needs a read to
// see pre-write data when it coincides with a write to the same RAM, so the model
// is READ-FIRST: rd_out captures the addressed contents on every enabled cycle,
// before the (masked) write. This is the standard read-first SRAM behavior; no
// special macro feature beyond the byte write mask is required.

module fakeram_be #(
   parameter BITS       = 32,
   parameter WORD_DEPTH = 64,
   parameter ADDR_WIDTH = 6,
   parameter NUM_WMASK  = 4          // byte granularity: BITS/8
) (
   output reg [BITS-1:0]    rd_out,
   input  [ADDR_WIDTH-1:0]  addr_in,
   input                    we_in,
   input  [BITS-1:0]        wd_in,
   input  [NUM_WMASK-1:0]   wmask_in,
   input                    clk,
   input                    ce_in
);
   localparam MASK_W = BITS / NUM_WMASK;   // bits per mask group (8 for byte)
   reg [BITS-1:0] mem [0:WORD_DEPTH-1];
   integer j, b;

   initial begin
      rd_out = {BITS{1'b0}};
      for (j = 0; j < WORD_DEPTH; j = j + 1)
         mem[j] = {BITS{1'b0}};
   end

   always @(posedge clk) begin
      if (ce_in) begin
         rd_out <= mem[addr_in];                  // read-first: pre-write contents every enabled cycle
         if (we_in) begin
            for (b = 0; b < NUM_WMASK; b = b + 1)
               if (wmask_in[b])
                  mem[addr_in][b*MASK_W +: MASK_W] <= wd_in[b*MASK_W +: MASK_W];
         end
      end
   end
endmodule

`define FAKERAM_BE(NAME, DEPTH, AW) \
module NAME (rd_out, addr_in, we_in, wd_in, wmask_in, clk, ce_in); \
   output [31:0] rd_out; input [AW-1:0] addr_in; input we_in; \
   input [31:0] wd_in; input [3:0] wmask_in; input clk; input ce_in; \
   fakeram_be #(.BITS(32), .WORD_DEPTH(DEPTH), .ADDR_WIDTH(AW), .NUM_WMASK(4)) u ( \
      .rd_out(rd_out), .addr_in(addr_in), .we_in(we_in), .wd_in(wd_in), \
      .wmask_in(wmask_in), .clk(clk), .ce_in(ce_in)); \
endmodule

`FAKERAM_BE(fakeram7_16x32_be,   16,  4)
`FAKERAM_BE(fakeram7_32x32_be,   32,  5)
`FAKERAM_BE(fakeram7_64x32_be,   64,  6)
`FAKERAM_BE(fakeram7_128x32_be,  128, 7)
`FAKERAM_BE(fakeram7_256x32_be,  256, 8)
`FAKERAM_BE(fakeram7_512x32_be,  512, 9)
`FAKERAM_BE(fakeram7_1024x32_be, 1024, 10)
