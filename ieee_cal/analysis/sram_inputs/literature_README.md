# SRAM energy and leakage at 0.7 V for ASAP7 (replacing pCACTI at 0.45 V)

Written 2026-10-28. Research only: nothing was downloaded, built or run except text extraction (pdftotext) and two small Python calculators in `scripts/`. Nothing in the git repo was edited. Local reads stayed inside /home/he/workspace/GPU_and_PNM.

Target: ASAP7, RVT logic, TT, 25 C, 0.7 V; 1RW macros of 1024/256/128/64/32/16 words x 32 bits, byte-enable write, 500 MHz.
Reference: the pCACTI runs at 0.45 V in `../sram/` (1024x32: read 0.104 pJ, write 0.092 pJ, leakage 132 uW; 16x32: read 0.016 pJ, leakage 2.1 uW).

## Short answer

1. No public tool models ASAP7 devices at 0.7 V out of the box. The closest options are FN-CACTI (14 nm FinFET devices with ASAP7 wires, 0.2 to 0.8 V), NS-Cache (foundry-calibrated 7 nm FinFET, validated against TSMC N7/N5/N3, needs a download) and SPICE on the ASAP7 BSIM-CMG models, which are already in the repo (needs a simulator install).
2. **pCACTI's leakage is about 200x too high for an ASAP7 array.** Per bit it is 3.4 nW in the cell alone. ASAP7's own SRAM-Vt devices give 6 to 17 pW per 6T cell, and RVT devices give 43 to 85 pW. Silicon HD SRAM macros sit around 26 to 48 pW/bit all-in (TSMC N3). The 1024x32 macro comes out at roughly 0.5 to 0.6 uW, not 132 uW. A pessimistic RVT-cell/LVT-periphery bound is about 5.5 uW.
3. For dynamic energy, the one solid published ASAP7 anchor is Vashishtha's 8 kB array, PEX-extracted at TT and 0.7 V: **read 0.23 pJ, write 0.25 pJ per 64-bit access** (3.6 / 3.9 fJ/bit). pCACTI scaled by V^2 to 0.7 V gives 0.25 pJ for a 4 kB 32-bit read (7.8 fJ/bit), so it is probably high by up to about 2x, not low. Bracket: 0.5x to 1.0x the V^2-scaled pCACTI.
4. Recommended path (no download): keep pCACTI for the size and organisation dependence of dynamic energy. Scale to 0.7 V by V^2 and calibrate it with one extra pCACTI run of the Vashishtha 8 kB configuration. Replace pCACTI leakage completely with a bottom-up ASAP7 estimate (bits x cell leakage + periphery). Details are in the recommendation section.

## 1. Tools

| Tool | Devices / node | Vdd | Fits 7 nm at 0.7 V? | Maturity | Citation |
|---|---|---|---|---|---|
| pCACTI (in repo) | 7 nm FinFET from TCAD (Lphy 7 nm, h_fin 14 nm, Ioff_n 68.9 nA/um) | file `finfet_7nm_std.xml` defines only 0.45 V (super-threshold) and 0.30 V (near-threshold) | No 0.7 V entry; device far leakier than ASAP7 | Released 2014 to 2016, no updates | Shafaei, Wang, Lin, Pedram, "FinCACTI: Architectural analysis and modeling of caches with deeply-scaled FinFET devices", ISVLSI 2014 (pCACTI is the SPORT-lab release built on it) |
| FinCACTI | Same 7 nm TCAD FinFET (Synopsys Sentaurus, Verilog-A); 6T and 8T cells, 1-fin to multi-fin | Super- and near-threshold sets; the JLPEA 2015 follow-up says "multiple supply voltages ... from near-threshold to super-threshold". I could not open the paper PDFs (404/SSL errors), so I did not confirm the exact values beyond what pCACTI's device file holds | Same device as pCACTI | Academic, 2014 | Shafaei et al., ISVLSI 2014; Shafaei et al., "A Cross-Layer Framework for Designing and Optimizing Deeply-Scaled FinFET-Based Cache Memories", JLPEA 5(3):165, 2015 |
| FN-CACTI | **14 nm** commercial-calibrated FinFET and NC-FinFET (Lphy 20 nm, fin pitch 42 nm, h_fin 42 nm); **ASAP7 wire data** option (`-interconnects - "ASAP7"`, wire node 7 nm) | Discrete 0.2 to 0.8 V in 0.1 V steps (configs README says DVS 0.3 to 0.8 V); FinFET at 0.7 V: Vth 0.24 V, Ion_n 508 uA/um, **Ioff_n 5.34 nA/um** | Runs at 0.7 V with ASAP7 wires, but devices and cell geometry are 14 nm. Ioff per fin about 0.49 nA (W_eff 92 nm), still about 25x ASAP7 RVT and 500x ASAP7 SRAM-Vt | Small academic repo (35 commits, no license file), patches pCACTI | Ravipati, Kedia, van Santen, Henkel, Panda, Amrouch, "FN-CACTI: Advanced CACTI for FinFET and NC-FinFET Technologies", IEEE TVLSI (CITATION.cff: Oct 2021; Panda lab page: Mar 2022; volume not verified) |
| NS-Cache | Built on DESTINY + NeuroSim V1.4. FinFET 14/10/7/5/3 nm (2 fins/device at 7 nm), nanosheet 2/1 nm; PTM at 22 nm and above. Device models validated against foundry data / IRDS, calibrated with Sentaurus TCAD | Not listed on the README | Closest to a validated 7 nm model. Validation: N7 74 kb macro (ISSCC 2018) speed -13.5 %, area -4.7 %; N3 360 kb (JSSC 2024) leakage +4 %, read/write energy +17 %/+23 %. No N7 energy or leakage validation. Not ASAP7, and small macros (512 bits) are outside the validated range | Active (v2.1.0, Sept 2026), "work in progress", CC BY-NC 4.0 | Waqar et al., "Optimization and Benchmarking of Monolithically Stackable Gain Cell Memory for Last-Level Cache", IEEE Trans. Computers, 2025, DOI 10.1109/TC.2025.3625490; github.com/neurosim/NS-Cache |
| CACTI 7 (HP) | Planar ITRS. README: 90/65/45/32 nm (the code also carries the 22 nm projections from CACTI 6.5) | Per node ITRS | No | Mature | Balasubramonian, Kahng, Muralimanohar, Shafiee, Srinivas, "CACTI 7: New Tools for Interconnect Exploration in Innovative Off-Chip Memories", ACM TACO 14(2), 2017 |
| CACTI-P | Planar, smallest 22 nm | ITRS | No | Mature, old | Li, Chen, Ahn, Muralimanohar, Jouppi, et al., "CACTI-P: Architecture-level modeling for SRAM-based structures with advanced leakage reduction techniques", ICCAD 2011 |
| NVSim / DESTINY | Planar, 22 to 180 nm (DESTINY docs and DATE 2015 paper) | ITRS/PTM | No | Mature | Dong, Xu, Xie, Jouppi, NVSim, IEEE TCAD 2012; Poremba, Mittal, Li, Vetter, Xie, DESTINY, DATE 2015 |
| OpenRAM | Official technologies: freepdk45, scn4m_subm, scn3me_subm, sky130, gf180mcu (github VLSIDA/OpenRAM `technology/`). No ASAP7. One unofficial fork claims "ASAP 7nm" without provenance | PDK nominal | No without a port (needs ASAP7 bitcell + BSIM-CMG simulation) | Mature for supported PDKs | Guthaus et al., "OpenRAM: An Open-Source Memory Compiler", ICCAD 2016 |
| Open-SRAM-Compiler-ASAP7nmPDK (github Samcooper01) | ASAP7 models via OpenVAF/ngspice, OpenROAD SRAM leaf cells | 0.7 V | Yes in principle | Very young (9 commits, 0 stars), wire RC left out, only one reference size characterised | No paper |

### FN-CACTI local copy (`pdk/FN-CACTI`)

- `configs.tgz` is **not** a git-LFS pointer. It is a real 30 KB POSIX tar (`file` says so; `tar -tvf` lists `configs/2MB_fin.cfg`, `2MB_nc.cfg`, `128KB_cam_fin.cfg`, `128KB_cam_nc.cfg`, `README`, dated April 2023).
- The configs describe **technology node 0.014 (14 nm)**, **wire technology node 0.007** with `interconnects "ASAP7"`, operating voltage 0.7 V, a DVS list of 0.3 to 0.7 V, 300 K, 2 MB 16-way L3 with a 37-bit tag, and ECC on.
- The configs README says "Tool supports 14nm technology node" and "DVS support for voltages ranging from 0.3V-0.8V".
- The device data is hard-coded in the patch (`technology.cc` and `io.cc`). There are no device XML files: the patch script deletes pCACTI's `xmls/` directory. The 6T cell is fixed at 1 fin per device with a 20 nm Lphy.
- Building it means `fncacti_patch.sh`: extract `pcacti.tgz` from sportlab.usc.edu, apply the 731 KB context diff, `make`. The repo's own pCACTI source (`pdk/pcacti/*.cc`) carries a local `technology.cc` patch, so the diff may not apply cleanly to it. A pristine `pcacti.tgz` would likely have to be downloaded, which needs the user's approval.
- Code issue: in the patched `io.cc` the Ioff selection uses `else if(vdd = 0.7)`, an assignment (patch lines 4494 to 4543, both the FinFET and NC-FinFET branches). Any Vdd other than 0.8 V gets the 0.7 V Ioff, and `vdd` is overwritten to 0.7. This does no harm for a 0.7 V run but breaks the DVS sweep. `technology.cc` uses `==` correctly.

## 2. Published 7 nm (and nearby) SRAM data

### ASAP7 itself

- **Clark et al., "ASAP7: A 7-nm finFET predictive process design kit", Microelectronics Journal 53 (2016) 105-115** (local copy: `pdk/asap7/asap7_pdk_r1p7/docs/mej_paper_asap7.pdf`), p.113, Tables 3 and 4: TT, 25 C, per fin, Vdd 0.7 V:

  | | SRAM | RVT | LVT | SLVT |
  |---|---|---|---|---|
  | NMOS Ioff (nA) | 0.001 | 0.019 | 0.242 | 2.444 |
  | PMOS Ioff (nA) | 0.004 | 0.023 | 0.230 | 2.410 |
  | NMOS Idsat (uA) | 28.57 | 37.85 | 45.19 | 50.79 |
  | NMOS Vtsat (V) | 0.25 | 0.17 | 0.10 | 0.04 |

  p.112, Section 6.1: the SRAM devices get "very low leakage via both a work function change and the removal of the LDD implant". p.110: a separate SRAM Vth selection layer "forces devices to have SRAM characteristics" in the bitcell, so **ASAP7 bitcells are SRAM-Vt by construction**. Sections 5.2 and Fig. 7 describe the 111, 112 and 123 bitcells (the 111 cell is 8 fins tall). The SRAM Ioff has a single significant digit (0.001 nA), so treat it as about 0.5 to 1.5 pA.
- **Vashishtha, "Predictive Process Design Kits for the 7 nm and 5 nm Technology Nodes", PhD dissertation, Arizona State University, Dec 2019**, Section 5.6, pp.77-78 (after Vashishtha, Vangala, Sharma, Clark, "Robust 7-nm SRAM design on a predictive PDK", ISCAS 2017, pp.5-8):
  - Array: 8 kB (64 kbit), 64-bit words, 128 cells per bitline, 4 columns per sense amp (Section 5.4), area 2267 um^2 (74.8 x 30.4 um), 84.2 % cell-area efficiency. That implies about 0.029 um^2 per cell, against pCACTI's 0.0066 um^2.
  - The preferred cell is 122 (Section 5.3.3, Table 5.1). It uses negative-bitline write assist.
  - PEX-extracted at TT and 0.7 V: **access time 166 ps; energy 0.23 pJ per read and 0.25 pJ per write** at 2 GHz (Fig. 5.9).
  - No leakage figure is given.
  - Table 5.1 also gives read SNM, hold SNM and write margin for the 111/112/122/123 cells, at 0.5 V and 25 C, with hold at 350 mV.
- **ICCAD 2017 invited paper** (Vashishtha, Vangala, Clark, "ASAP7 predictive design kit development and cell design technology co-optimization"): its slides list the 111 6T cell under cell-level DTCO. I found no energy or leakage numbers in it.
- **Open-SRAM-Compiler-ASAP7nmPDK** (GitHub README, no paper): 2 KB block (16,384 cells), 0.7 V, TT, simulated on the extracted netlist without wire RC: read 0.615 pJ, idle 773 nW (47 pW/bit all-in), 243 ps read latency. Word width, fin counts and cell Vt are not stated. Low maturity: treat it as weak evidence.

### Commercial silicon (none of it is TSMC N7 leakage, which I could not find in open sources)

- TSMC N7: Chang et al., "A 7nm 256Mb SRAM in high-k metal-gate FinFET technology with write-assist circuitry for low-VMIN applications", ISSCC 2017, paper 12.1, pp.206-207. HD 6T cell 0.027 um^2 (Fig. 12.1.1(a)), working down to 0.5 V. The leakage and energy numbers are behind the paywall; I did not see them.
- TSMC N3 (NS-Cache README validation table, citing a 2024 JSSC N3 360 kb macro): leakage **49.8 uW/Mbit (47.5 pW/bit)**, read/write 10.5 / 11 pJ per Mbit (as written there; the units are ambiguous).
- TSMC N3: Aoyagi, Nii, Yabuuchi, ..., Chang, "A 3-nm FinFET 563-kbit 35.5-Mbit/mm^2 Dual-Rail SRAM With 3.89-pJ/Access High Energy Efficient and 27.5-uW/Mbit One-Cycle Latency Low-Leakage Mode", IEEE JSSC 2026, pp.1466-1476, DOI 10.1109/JSSC.2025.3639747. Figures from the title and abstract: **27.5 uW/Mbit (26 pW/bit) standby at 25 C** in the low-leakage mode, 3.89 pJ/access, 6.94 pJ/access/Mbit at 85 C. I could not read the supply voltage or word width.
- Samsung: ISSCC 2017 paper 12.2 (authors not verified) ("A 7nm FinFET SRAM macro using EUV lithography for peripheral repair analysis"), and Renesas/TSMC (Yokoyama et al., VLSI Circuits 2020, 29.2 Mb/mm^2 7 nm HD SRAM): no leakage or energy numbers were visible in the open abstracts.

### Local ASAP7 data that looked useful but is not

- `pdk/asap7/asap7_sram_0p0/generated/LIB/srambank_*_6t122.lib` (36 libs, `mk_SRAM_lib.py`, 0.7 V, 25 C):
  - `area : 0` and `cell_leakage_power : 0`.
  - The clk `internal_power` is identical in all 36 sizes: read (`!write`) 1.816 pJ VDD / 2.475 pJ VSS, write 0.187 / 0.133 pJ (capacitive unit pF, so pJ).
  - These are size-independent placeholders. Do not use them as per-size data. At most they show that someone characterised an ASAP7 6t122 bank at about 1.8 pJ per read.
- `pdk/FakeRAM2.0/utils/class_memory.py` hard-codes `standby_leakage_per_bank_mW = 0.1289` and `pin_dynamic_power_mW = 0.0013449` for every size. Every `fakeram7_*` lib therefore carries the same 128.9 uW (essentially the pCACTI 1024x32 number) and 1.345 pJ on the clock.

## 3. Local leakage data and the per-bit estimate

ASAP7 7.5-track standard cells at TT, 0.7 V, 25 C (`pdk/asap7/asap7sc7p5t_28/Datasheet/text/*_TT_*.txt.gz` "Max" column, which equals the VDD state value; RVT also checked against `pdk/stdcell_libs/asap7/*.lib`). Values are in pW:

| Cell (fins N/P) | SRAM-Vt | RVT | LVT | SLVT |
|---|---|---|---|---|
| INVxp33 (1/1) | 3.57 | 17.8 | 173 | 1714 |
| INVx1 (3/3) | 10.7 | 53.3 | 520 | 5143 |
| DHLx1 avg | 21.4* | 95.3* | 927* | 9407* |

*The datasheet "Avg" is halved by the zero VSS rows. The RVT lib state-average values are 17.06 pW for INVxp33, 51.2 for INVx1, 229.7 for DFFHQNx1 and 190.6 for DHLx1.

The INVxp33 value is about 0.7 V x Ioff of one fin, in line with MEJ Table 3 (RVT 19 to 23 pA, so 13 to 16 pW). The extra part is gate leakage (`igcmod = 1` in `models/hspice/7nm_TT_160803.pm`, which has `nmos_sram`/`pmos_sram` models).

**6T hold leakage per bit** (WL low, BLs precharged high). Three devices are off with full Vds: one PU, one PD and one PG.

| Cell | Pure Ioff (MEJ Tables 3/4) | Off-fins x INVxp33 (includes gate leakage) |
|---|---|---|
| SRAM-Vt 111 | 4.2 pW | 10.3 pW |
| SRAM-Vt 122 | 5.6 pW | 17.2 pW |
| RVT 111 | 42.7 pW | 51.2 pW |
| RVT 122 | 69.3 pW | 85.3 pW |

pCACTI's own cell: (2 x 68.9 + 104) nA/um x 0.0315 um x 0.45 V = **3.43 nW/bit**. That is 112 of the 132 uW in the 1024x32 macro, and 85 % of its leakage in every macro. pCACTI's off-fin leakage (1.22 nW at 0.45 V) is about 72x ASAP7 RVT and about 350x ASAP7 SRAM-Vt at 0.7 V, so the device is SLVT-class.

### Estimated macro leakage at 0.7 V (`leak_estimate.tsv`, `scripts/leak_estimate.py`)

Method:
- Cell = bits x SRAM-Vt 122 cell, using the geometric middle of 5.6 and 17.2, which is 9.8 pW.
- Periphery = (pCACTI total minus pCACTI cell) x (ASAP7 RVT off-fin / pCACTI off-fin).
- High bound: RVT 122 cell plus LVT periphery.

| macro | pCACTI 0.45 V (uW) | central (uW) | low (uW) | high (uW) | pCACTI / central |
|---|---|---|---|---|---|
| 1024x32 | 132.3 | 0.60 | 0.46 | 5.5 | ~220x |
| 256x32 | 33.4 | 0.155 | 0.12 | 1.43 | ~215x |
| 128x32 | 14.9 | 0.052 | 0.035 | 0.47 | ~290x |
| 64x32 | 7.65 | 0.029 | 0.020 | 0.26 | ~265x |
| 32x32 | 3.98 | 0.017 | 0.012 | 0.15 | ~240x |
| 16x32 | 2.10 | 0.010 | 0.008 | 0.09 | ~215x |

Caveats:
- The periphery split by subtraction is fragile: it depends on the organisation pCACTI picked (128x32 has an oddly small periphery).
- A bottom-up periphery floor uses ASAP7 RVT parts per column: sense amp, write driver, output latch and a WL driver per row. At about 0.3 to 0.5 nW per column that is roughly 15 to 40 nW per macro. It would raise the small macros (16x32 to roughly 0.03 to 0.05 uW) more than the large ones.
- All-in silicon numbers (26 to 48 pW/bit for TSMC N3; 47 pW/bit for the ASAP7 open compiler) would give 0.9 to 1.6 uW for 1024x32 and 13 to 25 nW for 16x32.
- So a defensible all-in range is **10 to 50 pW/bit plus a periphery floor of a few tens of nW**. Every estimate is two orders of magnitude below pCACTI.

## 4. Dynamic energy at 0.7 V

`energy_brackets.tsv`:

| macro | pCACTI 0.45 V read / write (pJ) | V^2-scaled to 0.7 V (x2.42) read / write | bracket 0.5x to 1.0x of V^2-scaled, read |
|---|---|---|---|
| 1024x32 | 0.104 / 0.092 | 0.251 / 0.223 | 0.125 to 0.251 |
| 256x32 | 0.048 / 0.050 | 0.117 / 0.121 | 0.058 to 0.117 |
| 128x32 | 0.038 / 0.039 | 0.093 / 0.093 | 0.047 to 0.093 |
| 64x32 | 0.028 / 0.030 | 0.067 / 0.072 | 0.033 to 0.067 |
| 32x32 | 0.020 / 0.022 | 0.048 / 0.054 | 0.024 to 0.048 |
| 16x32 | 0.015 / 0.016 | 0.037 / 0.038 | 0.019 to 0.037 |

Why the bracket points down:
- Vashishtha's ASAP7 8 kB/64-bit array costs 3.6 fJ/bit read and 3.9 fJ/bit write at 0.7 V (PEX).
- The V^2-scaled pCACTI 4 kB/32-bit macro costs 7.8 fJ/bit.
- A pCACTI 8 kB/64-bit macro would likely land near 0.4 to 0.5 pJ at 0.7 V. That is my extrapolation, not a run, and would mean pCACTI is high by about 2x.

Evidence pointing the other way:
- The ASAP7 cell is about 4.4x the area of pCACTI's cell (longer wires per cell). Pure V^2 scaling ignores that, but pCACTI's small device and ASAP7's larger one partly cancel in ways only a run can settle.
- The weak anchors are higher: the open ASAP7 compiler's 0.615 pJ for 2 KB, and the placeholder 1.8 pJ in the asap7_sram_0p0 libs.

The Vashishtha number is the only peer-reviewed-lineage, PEX-based ASAP7 figure, so I weight it highest. Its accounting boundary (whether clock buffers and input latches are included) is not stated.

## 5. Recommendation

**Path A (no download, recommended): pCACTI shape, ASAP7 anchors.**
1. Dynamic energy: keep the pCACTI per-macro numbers (organisation and size dependence), multiply by (0.7/0.45)^2 = 2.42, then multiply by a calibration factor k.
   - To get k, run the repo pCACTI once on the Vashishtha array: 8192 B RAM, 8 B block (64-bit), 1 bank, 1 RW port, and `force_cache_config` true with an organisation giving 128 rows per subarray and a 4:1 column mux. Then k = 0.23 pJ / (2.42 x pCACTI read), and the same for write with 0.25 pJ.
   - This uses the already-built local binary (seconds). I did not run it because my brief excluded running tools.
   - Until then, use the 0.5x to 1.0x bracket above, and state that the anchor is a single PEX design point.
2. Leakage: **drop pCACTI leakage**. Use bits x 10 pW (SRAM-Vt 6T, range 5.6 to 17 pW) plus periphery (central column above, or a bottom-up floor of about 15 to 40 nW per macro from ASAP7 RVT cells). Report the RVT-cell/LVT-periphery high bound as a sensitivity.
   - At 500 MHz, even the high bound for 1024x32 (5.5 uW) is about 1 % of a macro accessed every cycle (0.25 pJ x 500 MHz = 125 uW), so leakage stops being a dominant term.
3. Write: keep the existing fixed-plus-per-byte split from `../sram/sram_energy_extended.tsv`, scaled by the same 2.42 x k.

Tradeoffs: this needs no new tool and is traceable to two citable ASAP7 sources (MEJ 2016 Tables 3/4; the Vashishtha 2019 thesis / ISCAS 2017). The dynamic-energy calibration rests on one design point, and the periphery leakage is an estimate.

**Path B (needs approval to download and build): NS-Cache.** This is the most credible open 7 nm FinFET array model (TSMC-validated for area/speed at N7, and for leakage/energy at N3). It would give an independent read/write/leakage estimate per macro. Downsides: CC BY-NC, work-in-progress, unknown Vdd handling, not ASAP7 devices, and tiny macros (512 bits) are outside its validation set.

**Path C (needs approval to install ngspice + OpenVAF, or Xyce): SPICE on ASAP7.** Simulate the 6T hold leakage with `nmos_sram`/`pmos_sram` from the repo's `7nm_TT_160803.pm`, plus a bitline/wordline column with ASAP7 cell-pitch wire caps. This replaces the per-bit leakage estimate with a direct number and checks the bitline energy. It is the most ASAP7-faithful option, at the cost of hours of setup.

**Not recommended as primary: FN-CACTI.** It runs natively at 0.7 V with ASAP7 wires, but its devices and cell are 14 nm, its leakage is still about 25 to 500x ASAP7, and building it probably needs a pristine pCACTI download (plus the `vdd = 0.7` bug if anyone sweeps Vdd). At best it is a second opinion on dynamic energy at 0.7 V.

## Files

- `leak_estimate.tsv`, `scripts/leak_estimate.py`: leakage split and estimates
- `energy_brackets.tsv`: V^2-scaled pCACTI energies and the bracket
- `scripts/asap7_sram_lib_power.py`: parser showing the asap7_sram_0p0 libs are size-independent
- `mej.txt`: text of the local ASAP7 MEJ paper; `dl_thesis/vashishtha.txt` and `dl_gaincell/gaincell.txt`: text extracted from PDFs fetched during the web search (untrusted downloads, read only)

## Sources

- https://github.com/marg-tools/FN-CACTI ; FN-CACTI TVLSI listing https://publications.iith.ac.in/publication/fn-cacti-advanced-cacti-for-finfet-and-nc-finfet-technologies
- https://github.com/neurosim/NS-Cache
- https://github.com/VLSIDA/OpenRAM/tree/stable/technology
- https://github.com/HewlettPackard/cacti
- DESTINY: https://past.date-conference.com/proceedings-archive/2015/html/0733.html
- FinCACTI: https://coldflux.usc.edu/~massoud/Papers/FinCACTI-isvlsi14.pdf (404 when fetched); JLPEA 2015 https://mdpi.com/2079-9268/5/3/165
- Vashishtha dissertation: https://d1rbsgppyrdqq4.cloudfront.net/s3fs-public/c7/220511/Vashishtha_asu_0010E_19583.pdf
- ICCAD 2017 ASAP7 tutorial: https://asap.asu.edu/wp-content/uploads/sites/47/2021/11/iccad17_asu_asap7_171115c.pdf
- Open ASAP7 SRAM compiler: https://github.com/Samcooper01/Open-SRAM-Compiler-ASAP7nmPDK
- TSMC N7 256Mb ISSCC 2017: https://dblp.uni-trier.de/rec/conf/isscc/ChangCCSCFLLHLL17.html
- TSMC N3 563 kb JSSC: https://sscs.ieee.org/tag/one-cycle-latency-low-leakage-access-mode-1-clm/
- Gain-cell / NS-Cache TC paper: https://arxiv.org/pdf/2503.06304
