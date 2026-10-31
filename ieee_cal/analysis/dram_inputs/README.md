# HBM2 DRAM energy constants for the per-run model

Scope: HBM2 at 1 Gb/s/pin (DRAM tick 2 ns, 500 MHz), 2 modelled channels, 2 pseudo-channels (PCs) each, 1 KB rows, 32 B transactions. Counts come from the shadow Ramulator (VxCmdStats: ACT, PRE, PREA, RD, WR, REFab per channel and per PC, ticks_run, pc<k>.open_ticks_run). The constants are in `dram_constants.tsv`. Nothing in the git repo was edited.

Sources used (all opened and read; local copies are in the scratchpad `dl_*` folders):
- [O'C17] M. O'Connor, N. Chatterjee, D. Lee, J. Wilson, A. Agrawal, S. W. Keckler, W. J. Dally, "Fine-Grained DRAM: Energy-Efficient DRAM for Extreme Bandwidth Systems", MICRO-50, 2017, doi:10.1145/3123939.3124545. PDF from cs.utexas.edu/users/skeckler/pubs/MICRO_2017_Fine_Grained_DRAM.pdf (14 pages).
- [Ch17] N. Chatterjee, M. O'Connor, D. Lee, D. R. Johnson, S. W. Keckler, M. Rhu, W. J. Dally, "Architecting an Energy-Efficient DRAM System for GPUs", **HPCA 2017** (not MICRO'17), pp. 73-84. The FGDRAM paper builds its energy model on this one.
- [Ol26] A. Olgun, S. Galanopoulos, A. K. Kakolyris, I. E. Yuksel, H. Luo, F. N. Bostanci, O. Mutlu, "Understanding the Power Consumption of Modern High Bandwidth Memory: Experimental Analysis and Modeling Using Real HBM2 DRAM Chips", arXiv:2610.14244v1, 9 Oct 2026. Measured on 36 HBM2 stacks (likely Samsung, 8 GB, 8-high, 2 SIDs) on AMD Alveo U55C boards at 1.2 Gb/s, VDDC+VDDQ (1.2 V) combined, VPP not measured, power-off current subtracted. Artifact: github.com/CMU-SAFARI/HBM-Power at commit c8381f74. It is a preprint, so not peer-reviewed yet.
- DRAMsim3 `configs/HBM2_8Gb_x128.ini` (umd-memsys): IDD values with no stated source. Used only as a cross-check.
- Ramulator2 `HBM2.cpp` in `vortex/third_party/ramulator` and `vortex/sim/common/dram_sim.cpp` (shadow config: nRFC = ceil(350 ns / tick), refi_ticks = 3900 ns / tick).

## 1. O'Connor MICRO'17 numbers: checked

Table 3 "DRAM Energy" (PDF p.10), HBM2 column, quoted exactly:

| Component | HBM2 |
|---|---|
| Row activation (pJ) | 909 |
| Pre-GSA data movement (pJ/b) | 1.51 |
| Post-GSA data movement (pJ/b)* | 1.17 |
| I/O (pJ/b)* | 0.80 |

The footnote says "* at 50% activity". Table 2 gives the configuration: 1 KB row per activate, 2 Gb/s/pin, 16 GB/s per channel, pseudo-channel mode (16 x 64-bit channels per stack). Section 4.2 says what each term covers:
- "The row-activation energy, which is the sum of precharge and activate energies". So **precharge is inside the 909 pJ**.
- "i) traversing the LDLs and MDLs from the row-buffer to the GSAs (pre-GSA), ii) traversing the path from the GSAs to the DRAM I/Os (post-GSA), and iii) traversing the I/O channel between the DRAM and GPU." Pre-GSA does not depend on the data because the LDLs and MDLs are precharged to mid-rail. Post-GSA and I/O depend on toggling.
- Section 2.1 says post-GSA covers the on-die path to the centre stripe, the TSVs, and "a short distance over the base-layer to reach the I/O bumps" (about 9.9 mm in total).

Supporting values in the text: the Fig. 1b total of about 3.97 pJ/bit (PDF p.2), and on p.3 "2.24 pJ/bit" for the on-die path at real toggle rates, "0.3 pJ/bit" for interposer I/O at real toggle rates, an "average of 1.21 pJ/bit of activation energy", and "3.92 pJ/bit ... (including ECC overhead)". At real application toggle rates, therefore, the 50%-activity table values overstate post-GSA plus I/O (1.97 pJ/b in the table against about 2.24 - 1.51 + 0.3 = 1.03 pJ/b implied by the text).

The 3-tier mapping in `gen_dram_est.py` is faithful to these definitions:
- Off-chip GPU on the interposer pays ACT + pre + post + I/O = 3.48 pJ/b.
- Logic-die compute pays ACT + pre + post = 2.68 pJ/b, because the interposer I/O is not crossed.
- Beside-bank compute pays ACT + pre-GSA = 1.51 pJ/b, because it skips the inter-bank bus, TSVs and I/O.

Caveats on the mapping:
- (a) The brief describes "off-chip" as a "logic-die GPU, full path incl. TSV and I/O". If the GPU really sits on the HBM base die, it should not pay the 0.80 interposer I/O term; that term belongs to an off-stack GPU. The script's r = 1.0 tier pays all three terms, which is right only for an off-stack GPU.
- (b) The near-bank tier leaves out the core's own short local wire and any column decode or CSL energy that is not inside pre-GSA. Chatterjee HPCA'17 counts column decode and CSL drive in "column energy" but does not split them out.
- (c) The values are for 2 Gb/s. Per-bit switching energy is roughly independent of data rate (CV^2 per transition), and [Ol26] Finding 6 says per-ACT and per-REF energy "only slightly increases with data rate". Using the values at 1 Gb/s is a mild assumption.
- (d) A 28 nm process is assumed, scaled from a 55 nm Rambus model.

Independent agreement: [Ch17] (PDF p.8) gives row energy of "112 fJ/bit or 1.8nJ for a 2KB row", and 909 pJ / 8192 b = 111 fJ/bit. It gives a toggle-independent column energy of 1.48 pJ/b, against 1.51 for pre-GSA. These come from the same group and the same model, so this is consistency, not independent validation.

## 2. Other constants

- **Precharge (PRE, PREA): 0.** It is inside E_ACT. Adding a PRE energy would double count. Every ACT is closed eventually, and the few rows still open at the end of the run are negligible.
- **RD/WR column energy:** O'Connor has no per-command column constant; the per-bit pre-GSA term *is* the tier-1 column energy. Per 32 B transaction that gives 386.6 pJ near-bank, 686.1 pJ logic-die, and 890.9 pJ off-chip. Reads and writes use the same values.
- **Refresh (per REFab):** derived from [Ol26] Appendix Table 3 "All chips": IDD5B 696.8 mA and IDD2N 272.7 mA, for the whole stack, with the loop running on PC0 of channels 0-7, i.e. 8 PCs.
  - From the artifact's `program_idd5`: one REF per PC every 160 cycles at 600 MHz = 266.7 ns. The comment in that code says "tRFC=350ns = 210 cycles", but the code uses 160.
  - E_REF_PC = (696.8 - 272.7) mA / 8 x 1.2 V x 266.7 ns = **16.96 nJ**. If 350 ns is the true busy time, it is 22.27 nJ.
  - Ramulator REFab covers both PCs, so E_REFab_ch = **33.9 nJ** (range 33.9-44.5 nJ).
  - Appendix Table 5 (16 boards) gives a similar delta (436.6 mA per chip against 424.1).
  - Cross-check with DRAMsim3: (250 - 55) mA x 1.2 V x 260 ns = 60.8 nJ per 128-bit legacy channel.
- **Background, precharge standby:** 272.7 mA per stack at 1.2 Gb/s. Scaled to 1.0 Gb/s with the Table 5 linear fit (IDD2N 186.6 / 285.5 / 374.6 mA per board at 600 / 900 / 1200 MT/s; 1000/1200 ratio 0.833), that is 227.3 mA per stack. Divided across 8 channels, this gives **34.1 mW per channel** (17.0 mW per PC). The range is 23.5-40.9 mW. Cross-check: DRAMsim3 IDD2N of 40 mA x 1.2 V = 48 mW per 128-bit channel at 2 Gb/s.
- **Background, active-standby increment:** per PC with at least one bank open, (IDD3N1 - IDD2N) at 1200 MT/s from Table 5 = (385.7 - 374.6) mA / 2 chips / 8 PCs x 1.2 V = **0.83 mW per PC**. In Table 3 the order is reversed (IDD3N1 231.8 < IDD2N 272.7), so the increment cannot be resolved there; Table 5 uses the same 11 boards for both loops, which is why I used it. Each extra open bank adds 0.15 mW (IDD3N16 - IDD3N1). DRAMsim3 implies 9 mW per PC (15 mA per 128-bit channel), so use that as the high sensitivity case. Either way the open-tick share is small next to the 34 mW per channel baseline.
- **tRFC = 350 ns for 8 Gb dies:** **not confirmed from a primary source.** JESD235D is paywalled. Ramulator's table (160 / 260 / 350 / 450 ns for 2 / 4 / 8 / 16 Gb) agrees with gem5 and gthparch/HBM for 2 Gb and 4 Gb. Every public 8 Gb value I found disagrees: gem5 HBM_1000_4H_1x64 says "use HBM1 4Gb value as a starting point" and uses 260 ns, DRAMsim3 HBM2_8Gb uses 260 ns, and the Olgun loop spaces REFs at 266.7 ns. The 350 ns figure equals the DDR3/DDR4 8 Gb tRFC(1). Confidence is medium. It affects timing only, plus the upper end of the E_REF range.
- **tREFI = 3.9 us:** confirmed. [Ol26] Section 2.2 cites JESD235D. gem5 uses the same value. This is the normal-temperature value.

## 3. Consistency checks

- **ACT from IDD0 against 909 pJ.** The `program_idd0` loop issues one ACT+PRE per PC every 28 cycles (46.7 ns), with the bank open for 21 of those cycles. Over 8 PCs: E = (IDD0 - I_bg) / 8 x 1.2 V x 46.7 ns.
  - With I_bg = 0.75 x IDD3N1 + 0.25 x IDD2N, Table 3 gives **474 pJ**. Using IDD2N alone gives 259 pJ; IDD3N1 alone gives 545 pJ. Table 5 board means give 906 pJ.
  - So the measured value (VDDC+VDDQ, no VPP) lies between 0.26 and 0.91 nJ. 909 pJ sits at the top of that range: an upper-side, not implausible value. Adding VPP would raise the measured numbers.
  - The artifact's own conversion (`IDD_oconnor_50toggle.json`, IDD0 1313.0 mA) against its measured nominal value (1260.6 mA) puts O'Connor's ACT at about 1.7x the measured one.
- **Per-bit read and write against measurement.** (IDD4R - IDD3N16) x 1.2 V / (8 x 64 b x 1.2 Gb/s) = **5.14 pJ/b** for reads on the DRAM side. All-0s data gives 2.87 pJ/b. Writes (IDD4W) give 3.39 pJ/b; that figure is DRAM-side only, since the GPU PHY drives write data.
  - O'Connor's full path of 3.48 pJ/b at 50% toggle is therefore low for reads, by up to 1.5x. [Ol26] reports a 20-23% MAPE for the FGDRAM model against real chips and says that "FGDRAM's published coefficients ... reproduce neither end" of the measured data-pattern range.
- **Against the commonly quoted HBM2 totals of 3.9-7 pJ/bit.** O'Connor gives 3.97 pJ/b including activation. [Ch17] gives 1.48 + 2.85 = 4.33 pJ/b at 50% toggle, before row energy. The measured 5.1 pJ/b for reads plus activation lands inside 3.9-7. I did not find a primary source for the "7 pJ/bit" end of the range.

## 4. Proposed per-run formula

For each modelled channel c with pseudo-channels p, using tick_ns = CORE_PERIOD_PS / 1000 x r_eff, T_run = ticks_run x tick_ns and T_open,p = pc<p>.open_ticks_run x tick_ns:

```
E_DRAM = sum_c [ N_ACT,c * E_ACT                              # 909 pJ, includes precharge; PRE/PREA = 0
               + bits_c * (e_pre + d_post*e_post + d_io*e_io)  # bits = (RD+WR+RDA+WRA) * 256
               + N_REFab,c * E_REFab_ch                         # 33.9 nJ (range 33.9-44.5)
               + P_PRE_SB_ch * T_run                            # 34.1 mW (range 23.5-40.9)
               + sum_p dP_ACT_SB_pc * T_open,p ]                # 0.83 mW (sensitivity 9 mW)
```

Tier flags: off-stack GPU (d_post, d_io) = (1, 1); logic die (1, 0); near-bank (0, 0).

Background and refresh are the same for both placements, because the DRAM device is unchanged. Sanity check on magnitude: one channel idles at about 34 mW of background plus 8.7 mW of refresh (33.9 nJ / 3.9 us), roughly 43 mW. On short runs that floor can be comparable to the dynamic terms, so the current estimate, which omits both, understates the absolute energy. It also compresses the near-bank vs off-chip ratio whenever run time differs.

## 5. Open questions and assumptions (flagged)

1. **Mixed provenance.** E_ACT and the per-bit terms are modelled values from [O'C17]; refresh and background are measured values from [Ol26], which exclude VPP. A fully measured alternative would be E_ACT of about 0.47 nJ and read at 5.1 pJ/b. Neither set is self-consistent with the other. I suggest reporting O'Connor as the primary set and the measured set as a sensitivity band.
2. **8-high vs 4-high.** The Olgun stacks are 8-high (2 SIDs). The model's HBM2_8Gb org has 1 SID (4-high). Background per channel would be lower for 4-high, by an unknown core-die share. Whether one REF refreshes both SIDs is also unknown; if it does, a 4-high stack might need about half of E_REF.
3. **Background allocation.** The model charges 2 channels' share (2/8 of a stack). If the whole stack is powered, multiply by 4. This is a modelling choice to state in the paper.
4. **Rate scaling** from 1.2 to 1.0 Gb/s uses the Table 5 board fit, while the absolute values come from Table 3. Tables 3 and 5 differ in absolute IDD2N (272.7 per chip against 187 per chip), probably because of different board subsets and sessions; the paper does not explain it.
5. **IDD4R bus utilisation** is assumed to be 100%. If the loop ran below full rate, the measured pJ/b is higher.
6. **Toggle rate.** The 50% values overstate typical data (O'Connor's own text gives about 1.03 pJ/b against 1.97 pJ/b for post-GSA plus I/O at real toggles). If the RTL energy campaign can log data toggles, e_post and e_io could be scaled by the measured toggle rate.
7. **Masked writes** are counted as full 32 B (an upper bound, already noted in gen_dram_est.py).
8. **The tRFC value for 8 Gb HBM2** needs JESD235D, Table 68 or the per-density refresh table, to confirm.
9. **The artifact CSV has an `ipp` column** (about 3100-3240 per loop, unit not documented). The paper says VPP is not measured, so I did not use it.

These constants are traceable but not exact. The ACT and background values in particular carry factor-of-about-2 uncertainty.
