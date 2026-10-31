# Per-macro SRAM energy table (ASAP7 Vortex, FakeRAM replacement)

Built 2026-10-28. Nothing in the git repo was edited. Everything here lives in this directory.

## Files

| File | What it is |
|---|---|
| `sram_energy.tsv` | The table with the columns asked for (macro, words, bits, model, read_pJ, write_pJ, leak_uW, access_ns, area_um2, source_notes) |
| `sram_energy_extended.tsv` | Same macros plus the write split into fixed and per-byte parts, 0.7 V CV^2 scaled pCACTI values, the range across configuration variants, the flop clock-pin energy per cycle, and the flop values under the OpenSTA VDD+VSS convention |
| `xml/ram_<W>x32_main.xml` | The exact pCACTI input used for each table row |
| `xml/ram_<W>x32_{tmplwires,minenergy}.xml` | Sensitivity variants (not used in the table) |
| `reports/` | Stock pCACTI output (detailed report + `pcacti_report.txt` summary) for every xml |
| `reports_instr/` | The same runs with an instrumented build that also prints the hidden components (precharge driver, bitline write, row-decoder write) |
| `pcacti_breakdown_<variant>.tsv` | Parsed per-component breakdown (fJ) for each variant |
| `flop/flop_*.json` | Flop model results with per-net breakdowns, activities, loads and unit energies |
| `scripts/` | `gen_xml.py`, `parse_pcacti.py`, `libparse.py`, `flop_model.py`, `build_table.py` |
| `provenance/` | Rerun that reproduces the earlier `pdk/pcacti/pcacti_report.txt` |
| `pcacti_run/` | A copy of the repo's `cacti` binary and `xmls/` (md5 of the binary matches the repo: aec824bf...) |
| `pcacti_instr/` | A copy of the pCACTI source with print-only instrumentation, plus its build |

## Result

Energies in pJ per access. The pCACTI rows are at pCACTI's own nominal 0.45 V. The flop rows are at 0.7 V. Read the caveats below before mixing them.

| macro | model | read_pJ | write_pJ (full word) | leak_uW | access_ns | area_um2 |
|---|---|---|---|---|---|---|
| 1024x32 | pcacti | 0.1036 | 0.0923 | 132.3 | 0.054 | 302.9 |
| 256x32 | pcacti | 0.0483 | 0.0498 | 33.44 | 0.043 | 92.3 |
| 128x32 | pcacti | 0.0385 | 0.0385 | 14.89 | 0.037 | 50.5 |
| 64x32 | pcacti | 0.0276 | 0.0299 | 7.652 | 0.035 | 28.7 |
| 32x32 | pcacti | 0.0198 | 0.0222 | 3.975 | 0.034 | 17.9 |
| 16x32 | pcacti | 0.0155 | 0.0158 | 2.095 | 0.029 | 13.6 |
| 8x32 | flop | 0.0617 | 0.0696 | 0.113 | ~0.35 (hand estimate) | 139.8 |
| 4x32 | flop | 0.0264 | 0.0561 | 0.055 | ~0.35 (hand estimate) | 67.9 |
| 2x32 | flop | 0.0083 | 0.0487 | 0.026 | ~0.35 (hand estimate) | 31.9 |

Every pCACTI access time is under 0.06 ns and every cycle time is under 0.06 ns (0.33 ns worst case in the min-energy variant), so all fit the 2 ns cycle by a wide margin. These delays are not credible as absolute numbers (see the caveats), but the margin is about 35x.

## pCACTI configuration

Template: `pdk/pcacti/xmls/cache_config_finfet.xml` (md5 07dff90b...). `scripts/gen_xml.py` changes only these fields (the diff for 16x32 is shown in the run log further down):

- `cache_size` = words x 4 B (64 to 4096 B); `block_size` = 4 B; `associativity` = 1; `bus_width` = 32
- `memory_type` = ram (scratch RAM, no tag array; pCACTI reports "cache type: Scratch RAM")
- `uca_bank_count` = 1; ports 1 RW, 0 R, 0 W, 0 single-ended
- `add_ecc` = false (the template has true; FakeRAM has no ECC)
- `print_input_parameters` = true, so the report prints the technology parameters actually used
- main variant: `wire_signalling` = default, `inside_mat` and `outside_mat` = semi-global, `optimize` = ED (as in the template)
- left as in the template: finfet, 0.007 um, super-threshold, 300 K, `xmls/devices/finfet_7nm_std.xml` for cells and periphery, `xmls/sram_cells/finfet_sram_6T1.xml`, conservative projection, RonHo2003 wires, `force_cache_config` false (pCACTI picks the organisation)

What pCACTI actually used (from the `print_input_parameters` dump in `reports/*.detailed.txt`):

- Vdd = 0.45 V for the SRAM cell and the periphery. This comes from `<vdd><super_threshold>0.45` in `finfet_7nm_std.xml`. It is pCACTI's nominal 7 nm FinFET supply, not ASAP7's 0.7 V.
- Vth 0.235 V; I_on_n 1.716 mA/um, I_off_n 68.9 nA/um, I_off_p 104 nA/um (the 300 K entries of the device file)
- Temperature 300 K; 6T cell with 1 fin per transistor, cell 0.105 x 0.063 um (0.0066 um^2)
- FO4 = 1.72 ps
- No `PCACTI_WIRE_*` environment variables were set. The repo's `technology.cc` has a local patch that lets those variables override wire R/C; it was inactive in every run here.

Organisations chosen (Ndwl/Ndbl/Nspd, bitline mux degree): 1024x32 2/2/4 (mux 8), 256x32 1/2/2 (4), 128x32 2/2/2 (4), 64x32 1/2/1 (2), 32x32 and 16x32 1/1/1 (no mux). With 1 bank, the H-tree energy is zero for every macro.

### Sensitivity to configuration

Two variants were run alongside the main one:

- `tmplwires`: the template's wire settings (global/global, Global_10)
- `minenergy`: optimisation NONE, weight 100 on dynamic energy, delay deviation unconstrained

Across the three, read energy varies by up to 13% (128x32, 33.9 to 38.5 fJ) and write energy by up to 11% (128x32). Leakage and area change with the organisation picked (area up to +55% in the template-wires variant at 16x32). The ranges are in `sram_energy_extended.tsv`.

### Breakdown of the earlier sanity run

`pdk/pcacti/pcacti_report.txt` (read 1.00991e-4 nJ = 0.101 pJ, write 0.0837 pJ, leakage 0.132 mW) is reproduced to every printed digit by `provenance/prior_guess_1024x32_tmplwires_ecc.xml`. That configuration is 4096 B (1024x32), 4 B block, direct-mapped RAM, 1 bank, 32-bit bus, template wires (global, Global_10), with `add_ecc` = **true**. So it was the 1024x32 macro with ECC bits added. Without ECC the same configuration gives 0.0978 / 0.0805 pJ. The repo's other sample, `xmls/libcom_sa_7nm.xml` (4 KB, 8-way, 8 B block, 4 banks), gives 0.514 pJ and does not match.

## pCACTI breakdown (main variant, fJ, 0.45 V)

The detailed report lists decoder, wordline, bitline mux, bitlines, sense amp and sub-array output driver. It leaves out the bitline precharge/equalisation driver, which is the gap between the listed parts and the total. I recovered that, and the write-side terms, by adding print statements to a copy of the source (`pcacti_instr/`, Ucache.cc and io.cc only). The instrumented build gives byte-identical stock output for all 18 runs (checked by diffing). Reconstructed totals match the reported totals to within 1e-4 fJ.

| macro | Ndwl/Ndbl/Nspd/blmux | decoder | wordline | bl mux | bitlines (read) | sense amp | sub-array out drv | precharge drv | **read** | bitlines (write) | **write (pCACTI)** |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1024x32 | 2/2/4/8 | 5.20 | 5.97 | 3.16 | 32.21 | 1.56 | 31.88 | 23.61 | **103.6** | 22.43 | **86.28** |
| 256x32 | 1/2/2/4 | 2.06 | 2.99 | 2.58 | 8.73 | 1.56 | 18.53 | 11.80 | **48.25** | 11.85 | **46.83** |
| 128x32 | 2/2/2/4 | 2.05 | 2.20 | 2.58 | 4.96 | 1.56 | 11.86 | 13.27 | **38.48** | 6.55 | **36.31** |
| 64x32 | 1/2/1/2 | 1.44 | 1.10 | 2.33 | 2.63 | 1.56 | 11.86 | 6.64 | **27.56** | 6.55 | **28.82** |
| 32x32 | 1/1/1/1 | 1.22 | 0.55 | 0 | 1.25 | 1.56 | 11.86 | 3.32 | **19.75** | 5.29 | **21.69** |
| 16x32 | 1/1/1/1 | 0.73 | 0.55 | 0 | 0.77 | 1.56 | 8.52 | 3.32 | **15.45** | 2.65 | **15.22** |

How pCACTI builds write energy (uca.cc, lines 223-236):
`write = read - bitlines(read) + bitlines(write) - rowdec(read) + rowdec(write) - senseamp` (the H-tree terms are zero here).
`bitlines(write) = (#columns written = 32) x C_bl x Vdd^2` (mat.cc, line 744 or 753), so it is exactly linear in the number of bits written.

### pCACTI bug: write energy leaves out the wordline

In `decoder.cc`, `power.writeOp.dynamic` for the row decoder is filled in only when the cell is `std_8T` (this branch was added in pCACTI). For the 6T cell used here, it stays 0, so the formula above subtracts the wordline/row-decoder energy and adds nothing back. A 6T write still has to fire the wordline. The table therefore uses `write = pCACTI write + wordline` (0.55 to 6.0 fJ, 2 to 7% of the write energy). The raw pCACTI value is in `write_raw_pcacti_pJ` in the extended TSV.

## Byte-enable writes

Recommended charge for a write that enables b of the 4 bytes:

`E_write(b) = E_fixed + b x E_byte`

- `E_fixed` = decoder + wordline + bitline-mux drivers + precharge driver. These fire once per access whatever the mask.
- `E_byte` = (bitlines(write) + sub-array data driver) / 4. pCACTI computes the bitline write term per written column. The 32 sub-array drivers are per bit, and pCACTI keeps them in the write energy as a stand-in for the data-in drivers.
- With b = 4 this gives back the full-word write in the table exactly (checked in `build_table.py`).

| macro | E_fixed pJ | E_byte pJ | full word pJ |
|---|---|---|---|
| 1024x32 | 0.03794 | 0.01358 | 0.09225 |
| 256x32 | 0.01943 | 0.00760 | 0.04981 |
| 128x32 | 0.02010 | 0.00460 | 0.03851 |
| 64x32 | 0.01151 | 0.00460 | 0.02992 |
| 32x32 | 0.00508 | 0.00429 | 0.02224 |
| 16x32 | 0.00460 | 0.00279 | 0.01577 |

Caveats on this split:

1. Treating the sub-array driver as per byte is my reading of the model; pCACTI itself does not apply a mask. The conservative alternative is to scale only the bitline term: `E_fixed' = E_fixed + outdrv` and `E_byte' = bitlines(write)/4`. For 16x32 that gives 0.0131 + b x 0.00066 pJ.
2. pCACTI charges no read-like swing on the half-selected columns of the active row (masked bytes, and the column-muxed neighbours). Physically those columns do discharge a little. The size of that term is bounded by `bitlines(read)` (0.8 fJ at 16x32, 32 fJ at 1024x32), so masked writes may be slightly underestimated.
3. `E_fixed` does not rise with size at every step (128x32 > 256x32) because pCACTI picks a different organisation (Ndwl = 2 at 128x32 makes the precharge driver energy larger). The totals do rise with size.

If a single number per write is preferred, charge the full-word write. It is the upper bound under pCACTI's own model.

## Flop model for 8x32, 4x32, 2x32

### Library

`pdk/stdcell_libs/asap7/asap7sc7p5t_{SEQ_RVT_TT_nldm_220123, AO_RVT_TT_nldm_211120, INVBUF_RVT_TT_nldm_220122, SIMPLE_RVT_TT_nldm_211120}.lib`. These are byte-identical (by md5) to the ORFS `platforms/asap7/lib/NLDM` copies. PVT_0P7V_25C, nom_voltage 0.7. Units: capacitance in fF, time in ps, leakage in pW. Internal energy is in fF x V^2 = fJ, since the library defines no energy unit and Liberate uses cap x V^2.

### Structure (per macro, N words x 32 bits, 1 RW port, synchronous)

- Storage: N x 32 `DFFHQNx1_ASAP7_75t_R`
- Write enable: one `AO22x1` per bit as a 2:1 mux, `D = we_w & din | we_w_n & Q`. One decoder AND per word (AND2x2 for N = 2, AND3x1 for N = 4, AND4x1 for N = 8, inputs we + address literals). One INVx1 per word makes `we_w_n`. ASAP7 7.5T has no MUX2 cell, so AO22 is the closest 2:1 mux.
- Read: a log2(N)-bit address register (DFFHQNx1) whose outputs drive the select lines (true from QN, complement through INVx1). Per bit, an (N-1)-cell AO22x1 2:1 mux tree.
- The address register is assumed to load only on reads (the read data holds during writes, as SRAM macros do).

### Operating point and loads

- Slew 20 ps on every input (third index of the 7x7 tables: 5, 10, **20**, 40, ...). Loads are computed per net as the sum of the fan-out pin caps plus 0.25 fF of wire per fan-out pin. That wire figure is my assumption, not extracted. Tables are interpolated bilinearly on these loads.
- Net switching: 0.5 x C x V^2 per transition (C V^2 per rise-fall pair). Liberty internal energy excludes the load.
- Internal energy per transition = (rise + fall)/2, averaged over the `when` states.
- Only the VDD-related `internal_power` groups are used. ASAP7 lists an almost mirror-image VSS group for every arc. OpenSTA (`Power.cc`, `findInputInternalPower` / `findOutputInternalPower`) sums both groups. Physically the charge drawn from VDD over a rise-fall cycle equals the charge returned to VSS, so summing both appears to count the internal energy twice. The VDD+VSS numbers are also given (`read_pJ_alt`, `write_pJ_alt`): 21 to 30% higher for accesses and 1.7x higher for clock-pin energy. **Use whichever convention the rest of the energy model uses for standard-cell power.** If the logic power comes from OpenROAD `report_power` with these libs, it uses VDD+VSS.
- D-pin hidden power: the "CLK" (clock high) group (+0.002 fJ per transition), because data launched at the rising edge settles while the clock is high at 500 MHz. The "!CLK" group would give 0.19 fJ per transition, which adds at most 3 fJ to a write.
- Activity from a Monte Carlo run (20,000 operations, seed 12345) with uniformly random addresses and random 32-bit data. Writes are isolated, so `we_w` pulses 0, 1, 0 on every write. Back-to-back writes to the same word would skip the about 21 fJ decoder and `we_n` pulses.

### Unit energies (VDD only, fJ)

| item | value |
|---|---|
| DFFHQNx1 CLK->QN internal per QN transition (load 1.33 fF) | 0.490 |
| DFFHQNx1 D-pin hidden per transition (CLK high / CLK low) | 0.002 / 0.188 |
| DFFHQNx1 CLK pin internal per clock cycle (rise + fall, hold state D = Q) | 0.587 |
| DFFHQNx1 CLK pin cap 0.475 fF x 0.49 V^2 per cycle | 0.233 |
| AO22x1 Y transition caused by A1 (select) / A2 (data) | 0.184 / 0.177 |
| AND4x1 Y per transition at 20.8 fF | 0.203 |
| INVx1 Y per transition at 20.7 fF | 0.049 |
| AO22 input-pin hidden energies (rise and fall nearly cancel) | < 0.001 |

### Worked example: 8x32 write = 69.6 fJ

The expected number of stored bits that change is 16.0 (random data).

| term | arithmetic | fJ |
|---|---|---|
| QN transitions | 16.0 x (0.490 + 0.5 x 1.332 fF x 0.49) | 13.06 |
| D net + D pin | 16.0 x (0.5 x 0.809 x 0.49 + 0.002) | 3.20 |
| enable-mux outputs | 16.0 x 0.185 | 2.95 |
| decoder output pulse | 2 x (0.203 + 0.5 x 20.8 x 0.49) | 10.60 |
| we_n inverter pulse | 2 x (0.049 + 0.5 x 20.7 x 0.49) | 10.24 |
| global we net pulse | 2 x 0.5 x (8 x 0.595 + 8 x 0.25) x 0.49 | 3.31 |
| din bus (fans out to 8 words) | 16.0 x 0.5 x 5.27 x 0.49 | 20.65 |
| read-tree nodes disturbed by the new Q (level 0 sees the write with p = 1/2, level 1 with 1/4, level 2 with 1/8) | 12.0 x (0.177 + 0.5 x 0.659 x 0.49) | 4.06 |
| address inputs | 1.5 x 0.5 x 4.02 x 0.49 | 1.48 |
| total | | **69.6** |

### Worked example: 8x32 read = 61.6 fJ

Each of the 3 address bits toggles with p = 0.5.

| term | arithmetic | fJ |
|---|---|---|
| address register QN drives select level l (C = 80.7 / 40.8 / 20.8 fF) | 0.5 x sum_l (0.50 + 0.5 x C_l x 0.49) | 18.18 |
| select-complement inverters (C = 82.8 / 41.4 / 20.7 fF) | 0.5 x sum_l (0.05 + 0.5 x C_l x 0.49) | 17.83 |
| tree nodes (70.4 node toggles per read from the MC, about 2.2 per bit) | 70.4 x (0.181 + 0.161) | 24.09 |
| address input nets, hidden pin energy | | 1.54 |
| total | | **61.6** |

The 4x32 and 2x32 breakdowns are in `flop/flop_main.json`. The read energy is dominated by the select lines, which fan out to 32 x N/2 mux pins. Write energy shrinks only slowly with N, because the per-word enable nets (32 pins each) and the 16 flop toggles do not depend on N.

### Leakage

Uses the cell `leakage_power` default value (state average) for VDD. For 8x32: 259 DFF x 229.7 pW + 256 AO22 x 109.7 pW (enable) + 224 AO22 x 109.7 pW (tree) + 8 AND4 x 92.1 pW + 11 INV x 51.2 pW = 113.4 nW.

### Area

Raw cell area (no utilisation, no routing): 139.8 / 67.9 / 31.9 um^2. The FakeRAM `fakeram7_{8,4,2}x32_be` placeholders in ORFS (`platforms/asap7/lef`) are 4.18 x 5.76 = 24.1 um^2 each. The flop register files would therefore not fit the FakeRAM footprints (5.8x, 2.8x and 1.3x larger).

### Access time

This is a hand estimate, not STA. DFF clock-to-QN into a buffered select line is about 60 to 100 ps. Adding log2(N) AO22 levels at about 25 to 35 ps each (AO22x1 `cell_rise` is 27 ps at 20 ps slew and 1.44 fF) gives under 0.35 ns. The model assumes unbuffered INVx1 and DFF drivers on 80 fF select lines; that is fine for energy (it is net-cap dominated) but not for timing. Internal energies at loads above the table maximum (46 fF) are extrapolated.

### Clock-pin energy, reported separately

Per clock cycle, without clock gating: (32N + log2N) flops x (0.587 + 0.233) fJ = **212 fJ (8x32), 107 fJ (4x32), 53 fJ (2x32)**. At 500 MHz that is 106 / 53 / 27 uW per instance, which is about 1000x the flop leakage and larger than one access. VDD+VSS convention: 364 / 183 / 91 fJ.

On double counting: the routed layouts contain a FakeRAM macro with a single `clk` pin (0.025 fF in its .lib), not these flops. So the per-design clock floor taken from the routed netlist does **not** contain this energy. It is double counting only if the energy model already adds a per-flop clock cost for the macro flops somewhere else. The opposite risk is real too: if this term is dropped, the flop model is optimistic compared to a real flop implementation. A real flop register file would gate the clock per word (ICG on write), which cuts the idle cost to roughly the ICG and address-register clock load. With gating, a write costs about 32 x 0.82 = 26 fJ of clock-pin energy plus the ICG, and the enable muxes disappear. I have not modelled the gated variant. It is not in `read_pJ`/`write_pJ`.

## Sanity checks

- Monotonic with words, within pCACTI: read 15.5 < 19.8 < 27.6 < 38.5 < 48.3 < 103.6 fJ, write 15.8 < 22.2 < 29.9 < 38.5 < 49.8 < 92.3 fJ. Leakage and area are monotonic too. Write (wordline-corrected) is below read only at 1024x32 and about equal at 128x32, because the bitline write term (full swing on 32 columns) is compared with a read that swings all columns of the row by V_b_sense.
- Monotonic with words, within the flop model: read 8.3 < 26.4 < 61.6 fJ, write 48.7 < 56.1 < 69.6 fJ, leakage and area too.
- **Not monotonic across the model boundary.** The flop 8x32 costs about 4x the pCACTI 16x32 for read (61.6 vs 15.5 fJ) and about 4.4x for write (69.6 vs 15.8 fJ). Even the flop 2x32 write (48.7 fJ) is about 3x the pCACTI 16x32 write. They are within one order of magnitude, but the jump is large. Reasons, roughly in order of size:
  1. Supply voltage: pCACTI runs at 0.45 V and the flops at 0.7 V, a 2.42x CV^2 factor. At 0.7 V the 16x32 numbers would be about 37 fJ read and 38 fJ write (`*_scaled_0p7V` columns). This is first-order only, because the delay and leakage models would also change.
  2. Circuit style: the SRAM swings its bitlines only by V_b_sense on reads, and its decoder drives one wordline. The flop register file swings full-rail select lines that fan out to 128 mux pins (8x32), plus per-word enable nets with 32 pins each.
  3. Device and parasitic assumptions: pCACTI's 7 nm model has FO4 = 1.7 ps and small capacitances (the 1024x32 cycle time of 54 ps is not credible). Its energies are probably optimistic as well, by an unknown factor.
- **Leakage jumps the other way**: pCACTI 16x32 leaks 2.1 uW at 0.45 V, the flop 8x32 leaks 0.11 uW at 0.7 V (19x less). pCACTI's device file has I_off_n = 68.9 nA/um. ASAP7 RVT INVx1 leaks 51 pW at 0.7 V, and the ASAP7 SRAM-Vt INVx1 leaks 10 pW. That suggests the pCACTI leakage corresponds to an LVT/SLVT-class device and is about 1 to 2 orders of magnitude higher than an ASAP7 RVT or SRAM-Vt array. The pCACTI 1024x32 works out to 4 nW per bit.
- **Area**: pCACTI areas are 2.0x to 3.7x smaller than the FakeRAM LEF footprints (1024x32: 303 vs 1112 um^2; 16x32: 13.6 vs 32.1 um^2 in ORFS). That is expected (FakeRAM is a placeholder), but it shows the pCACTI array is not the layout that was routed.

## What looks suspicious or uncertain

1. **0.45 V vs 0.7 V.** Following the decision "pCACTI nominal Vdd", the pCACTI energies are at 0.45 V while the rest of the chip (and the flop rows) is at 0.7 V. pCACTI's 7 nm device file defines only 0.45 V (super) and 0.3 V (near), so there is no 0.7 V entry to switch to. If the model should be at 0.7 V, the extended TSV has a CV^2-scaled column (x2.420), but that is an extrapolation, not a pCACTI result. This choice is the largest single factor in the SRAM energies.
2. **The pCACTI leakage is likely too high** for an ASAP7 RVT design (see above). If the energy model integrates leakage over runtime, the 1024x32 local-memory macros (132 uW each) could dominate. Consider treating the pCACTI leakage as an upper bound.
3. The pCACTI write-energy wordline omission (6T) was corrected by hand. The correction is small but it is a deviation from the raw tool output.
4. The pCACTI organisation is chosen by its optimiser (ED objective), and the chosen organisation changes between sizes. Read energy shifts by up to 13% between objective and wire variants.
5. The flop activity assumes random addresses and data. Real register-file and cache traffic has locality (repeated addresses), and with locality the read select-line energy falls toward 0. The flop numbers are therefore closer to an upper bound for reads.
6. The flop wire allowance (0.25 fF per fan-out pin) is a guess. Using 0.1 or 0.5 fF moves read energy by -18% / +30% and write by -18% / +30%.
7. VDD-only vs VDD+VSS internal power in the ASAP7 liberty (see above). Pick the one that matches the logic-power convention.
8. Mapping history: older `project.v` builds (e.g. `artifact/release/.../vortex_2t_8w_be`) mapped any cache with fewer than 16 sets onto `fakeram7_16x32_be`. Newer `spr_eval/build/*_fpnew_*` builds instantiate `fakeram7_{8,4,2}x32_be`. Check which netlist each energy number belongs to. For the older builds the physical macro is a 16x32, and charging it as a flop register file would not match the layout.
9. The flop access times are hand estimates, and the table interpolations go beyond the characterised load range on the select nets.

## Commands run

All commands were run in this directory tree. `S` = this directory.

```
# copy the binary and data (repo untouched)
mkdir -p $S/pcacti_run && cp pdk/pcacti/cacti $S/pcacti_run/ && cp -r pdk/pcacti/xmls $S/pcacti_run/
# repo sample, does not match the old report
cd $S/pcacti_run && ./cacti -infile xmls/libcom_sa_7nm.xml > libcom_check_detailed.txt
# generate the configs
python3 -I $S/scripts/gen_xml.py xmls/cache_config_finfet.xml $S/xml {main|tmplwires|minenergy}
# stock runs
for f in $S/xml/*.xml; do ./cacti -infile $f > $S/reports/$(basename $f .xml).detailed.txt; cp pcacti_report.txt $S/reports/$(basename $f .xml).summary.txt; done
# reproduce the old report: the 1024x32 tmplwires xml with add_ecc=true
./cacti -infile $S/provenance/prior_guess_1024x32_tmplwires_ecc.xml
# instrumented build (print-only changes to Ucache.cc, io.cc), outputs diffed identical to stock
cp pdk/pcacti/{*.cc,*.h,makefile,cacti.mk} $S/pcacti_instr/ ; (patch via python, see below) ; make -j8
for each xml: $S/pcacti_instr/cacti -infile ... > $S/reports_instr/...
python3 -I $S/scripts/parse_pcacti.py $S/reports_instr {variant} $S/pcacti_breakdown_{variant}.tsv
# flop model (main + sensitivity)
python3 -I $S/scripts/flop_model.py pdk/stdcell_libs/asap7 $S/flop/flop_main.json 20 0.25 VDD
python3 -I $S/scripts/flop_model.py ... {10|40} 0.25 VDD ; ... 20 {0.1|0.5} VDD ; ... 20 0.25 VDD+VSS
python3 -I $S/scripts/build_table.py $S
```

The instrumentation adds two assignments in `Ucache.cc` (`power_bitlines.writeOp`, `power_row_decoders.writeOp` copied into the result struct) and nine `cout` lines tagged `INSTR` in `io.cc::output_UCA`. No model code was changed.

Checksums: repo `cacti` aec824bf5075b07b87bd7edee5803fff; `finfet_7nm_std.xml` 17c98c1a...; `finfet_sram_6T1.xml` 14b660e3...; SEQ lib b5e4b855...; AO lib 018cca52...; INVBUF lib a6f01b9e...; SIMPLE lib 1a2d30af....
