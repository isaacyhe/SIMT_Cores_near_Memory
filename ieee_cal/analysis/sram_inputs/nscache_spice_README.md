# SRAM energy and leakage cross-check with NS-Cache and ngspice on ASAP7 (Oct 28 2026)

Approved by the user on Oct 28 ("1/2/3 and then decide"). Everything was downloaded, built and installed under this directory. No sudo was used, nothing was installed system-wide and the git repo was not edited. Local reads stayed inside /home/he/workspace/GPU_and_PNM (the ASAP7 PDK model cards, CDL, Liberty/datasheets and the ORFS setRC.tcl) plus the earlier scratchpad notes in ../sram, ../sram2 and ../sramcal.

Target: ASAP7, TT, 0.7 V, 25 C. Macros are 1RW, 32-bit words, sizes 1024/256/128/64/32/16 words.

## Short answer

1. **Leakage: both tools put the 1024x32 array at about 1 uW, about 130x below pCACTI's 132 uW.**
   - NS-Cache gives 1.05 uW for the whole macro. About 0.79 uW of that is cells, at 24 pW/cell, because NS-Cache uses logic-Vt-like 7 nm devices (15.7 pA/fin NMOS).
   - SPICE on the ASAP7 SRAM-Vt card gives 18 pW per 111 cell and 34 to 36 pW per 122 cell. That puts the 1024x32 cell array at 0.6 to 1.2 uW, with no periphery.
   - GIDL dominates the SRAM-Vt cell: about 75 % in the 111 cell and about 80 % in the 122 cell. Gate leakage is about 10 % (1.6 to 3 pW per cell); the rest is channel subthreshold leakage. This is why the SPICE value is about 1.8x the ../sram2 estimate, which used channel Ioff plus gate leakage only.
2. **The SPICE sanity check FAILED as specified.** Single-fin channel Ioff at Vds = 0.7 V, against Clark et al. 2016 Tables 3/4, with L = 20 nm:

   | | SRAM-Vt | RVT | LVT | SLVT |
   |---|---|---|---|---|
   | NMOS (sim / Clark) | 0.42 pA / 1 pA | 10.3 / 19 pA | 133 / 242 pA | 1368 / 2444 pA |
   | PMOS (sim / Clark) | 3.45 / 4 pA | 17.9 / 23 pA | 183 / 230 pA | 1919 / 2410 pA |
   | Ratio NMOS / PMOS | 0.42 / 0.86 | 0.54 / 0.78 | 0.55 / 0.79 | 0.56 / 0.80 |

   - Idsat is 2 to 7 % low, SS is 61 mV/dec (Clark: 62 to 63) and DIBL is 22 to 25 mV/V (Clark: 19 to 22).
   - The mismatch behaves like a Vth offset. Shifting NMOS Vth by -20 mV and PMOS by -10 mV (`dvtshift`) reproduces Clark's Ioff and Idsat to within about 10 % for RVT and SLVT, and within 20 % for the one-digit SRAM-Vt values (diagnostic run at the card default L = 21 nm).
   - The cause is most likely the model version: the card is BSIM-CMG 107 for HSPICE, and I ran the public 111.0.0 Verilog-A. BSIM-CMG 110.0.0 gives the same NMOS result (within 0.5 %) and PMOS Ioff 7 to 12 % higher, so the 110 to 111 change is not the cause. I could not test 107 because no public 107 Verilog-A was found. Xyce, which has 107 built in, was not built: no cmake or Trilinos here.
   - Per the brief, the SPICE cell numbers are **not to be trusted as exact**.
3. **A second, independent check brackets the truth.** The PDK's own Liberty for INVxp33 (1 fin N/P, l=20n) at TT 0.7 V 25 C, worst state:

   | Flavour | PDK Liberty | Raw card | Shifted card |
   |---|---|---|---|
   | SRAM-Vt | 3.57 pW | 3.74 pW (1.05x) | 3.90 pW (1.09x) |
   | RVT | 17.78 pW | 12.57 pW (0.71x) | 19.74 pW (1.11x) |
   | LVT | 173.5 pW | 127.8 pW (0.74x) | 200.4 pW (1.16x) |
   | SLVT | 1714 pW | 1344 pW (0.78x) | 2022 pW (1.18x) |

   - For **SRAM-Vt, the device that matters for the bitcell, the raw card matches the PDK characterisation within 5 %, GIDL included.** So I take the SRAM-Vt cell leakage as credible to about +/-30 %, although the strict Clark check fails.
4. **Dynamic energy: NS-Cache is high against the one ASAP7 anchor.** For the Vashishtha 8 kB / 64-bit array (forced to 128 x 256 mats with a 4:1 sense-amp mux), NS-Cache gives:
   - read 0.73 pJ and write 0.42 pJ with non-H-tree routing;
   - read 0.50 pJ and write 0.20 pJ with H-tree routing;
   - against the thesis PEX values of 0.23 / 0.25 pJ.

   Its area matches almost exactly: 2265 um^2 against 2267 um^2.
   - NS-Cache 1024x32 raw is read 0.16 to 0.28 pJ and write 0.05 to 0.18 pJ. Calibrated per routing mode with the Vashishtha factors, it becomes read 0.07 to 0.09 pJ and write 0.07 to 0.11 pJ. pCACTI calibrated (../sramcal) gives read 0.099 and write 0.093 pJ. So **the two tools agree within about 30 % for 1024x32 after calibration**.
   - For 16x32, calibrated NS-Cache (read 0.023 to 0.026 pJ) is about 1.7x pCACTI calibrated (0.014 pJ), because NS-Cache carries a larger fixed overhead.
5. **SPICE column read (optional item): 0.44 to 0.55 fJ per 128-cell 122 column per read at 100 mV swing** (bitline plus wordline share).
   - For the Vashishtha array (256 columns discharge per access), that is about 0.12 pJ, roughly half the 0.23 pJ total, which is plausible.
   - It has no extracted junction or coupling caps. The thesis needs 55 ps to reach 115 mV where my netlist needs about 16 ps, which suggests the real bitline cap is 2 to 3x mine. Treat it as a lower bound.

## Downloads (all in their own subdirectories, treated as untrusted)

| What | URL | Version / commit | sha256 |
|---|---|---|---|
| NS-Cache | https://github.com/neurosim/NS-Cache (git clone --depth 1) | v2.1.0, commit 2fdcbf093f806bc9a28964aca8402c42738d58e5 (2026-09-28), tree 4f62bce0f722e458f60ce9fe98eadd7242cf0a11 | git clone, so no tarball hash; built `nsc`: e9909b2b02c4e424f4fd148613c5fe69dbe4185ff1eadc3f68ff2a524516f5d3 |
| ngspice | https://sourceforge.net/projects/ngspice/files/ng-spice-rework/47/ngspice-47.tar.gz/download | ngspice-47 | 894e649651f1838a14095e5a5439e7d3aa63e87ede14d283173fda4fcdef675f (sha1 87a09c69ddc98247654d67e6c10b4096503ad195 matches the SourceForge listing) |
| OpenVAF-reloaded | https://github.com/OpenVAF/OpenVAF-Reloaded/releases/download/v24.0.2mob/openvaf-r-v24.0.2mob-linux-x86_64.tar.gz | v24.0.2mob (2026-08-25), prebuilt binary | b12b7b1726d103e18c2588c3a1f91f8475cf03df8a3bde14d919797d221e3110 (matches the GitHub release digest); binary ca1037be094cbfecb1249a1f220c9c390bc265015dd177ec27800ed365d6ef3a |
| BSIM-CMG 111.0.0 Verilog-A | https://raw.githubusercontent.com/OpenVAF/OpenVAF-Reloaded/b6622cd8befed2ae2293593ff50ee7d5caa21f2c/integration_tests/BSIMCMG/ (11 files) | 111.0.0 (UC Berkeley, 09/12/2019, ECL-2.0) | `dl_bsimcmg/SHA256SUMS`; bsimcmg.va befbba29779f29f2eef5f222f310d6987c19d1ec0224fd9bcd69e95936c4a96e |
| BSIM-CMG 110.0.0 Verilog-A (version cross-check only) | https://github.com/dwarning/VA-Models, code/bsimcmg/vacode110 at commit 1eaf90553d8b30cd584e33e987de6f0e4d13d73e | 110.0.0 (01/01/2016) | `dl_bsimcmg110/SHA256SUMS`; bsimcmg.va f4ead0f9b877c9f6b576ac092732b0f3869c58f3adb0cbc844dea0edb01e6e8f |

Notes on these downloads:
- The official Berkeley BSIM-CMG page (bsim.berkeley.edu/models/bsimcmg/) returned HTTP 401, so I took 111.0.0 from the official OpenVAF-Reloaded repository's integration tests, which carries the Berkeley license and notice.
- VA-Models is maintained by an ngspice developer (Dietmar Warning). It is not the Berkeley site. I used it only for the 110 cross-check.

Inspection before building:
- NS-Cache `src/Makefile` is a plain g++ build. I grepped the sources for system/popen/exec/fork/socket/curl and found nothing.
- ngspice: the official autotools tarball, configured with a prefix inside sram3. bison and flex are absent, but the tarball ships pregenerated parsers.
- OpenVAF is a prebuilt release binary. Its sha256 matches the digest GitHub publishes for the release asset.

## Commands

```
S=/tmp/claude-1000/-home-he-workspace-GPU-and-PNM/27cdfe93-fbe4-4edc-aa3b-66bb289d059e/scratchpad/sram3
# NS-Cache
cd $S/dl_nscache && git clone --depth 1 https://github.com/neurosim/NS-Cache.git
make -C $S/dl_nscache/NS-Cache/src -j8          # gcc 15.2.0; warnings only
$S/scripts/run_nscache.sh                         # writes nscache/cfg/*.cfg and nscache/out/*.txt
python3 -I $S/scripts/parse_nscache.py $S/nscache/out > $S/nscache/nscache_all.tsv
# ngspice
cd $S/build_ngspice && $S/dl_ngspice/ngspice-47/configure --prefix=$S/opt --without-x --with-readline=no --disable-debug CFLAGS=-O2
make -j12 && make install                         # "OSDI features included"; KLU compiled in
# OpenVAF + BSIM-CMG
$S/dl_openvaf/openvaf-r-v24.0.2mob-linux-x86_64/bin/openvaf-r -I $S/dl_bsimcmg -o $S/spice/osdi/bsimcmg.osdi $S/dl_bsimcmg/bsimcmg.va
$S/dl_openvaf/openvaf-r-v24.0.2mob-linux-x86_64/bin/openvaf-r -I $S/dl_bsimcmg110 -o $S/spice/osdi/bsimcmg110.osdi $S/dl_bsimcmg110/bsimcmg.va
# model cards (repo PDK file 7nm_TT_160803.pm, identical to 7nm_TT.pm, sha256 684708ee...f262fc)
python3 -I $S/scripts/convert_cards.py <pdk>/models/hspice/7nm_TT_160803.pm $S/dl_bsimcmg/bsimcmg_parameters.include $S/spice/models/asap7_TT_osdi.lib
# simulations (OMP_NUM_THREADS=1)
$S/scripts/gen_sanity.sh [lib osdi tag inst]      # single-fin Ioff/Idsat; run as v111, v110, v111_L20, v110_L20
$S/scripts/gen_idvg.sh; python3 -I $S/scripts/idvg_metrics.py $S/spice/runs   # SS, DIBL, Vt(cc)
$S/scripts/dvtshift_diag.sh                       # Vth-offset diagnostic
$S/scripts/inv_leak_check.sh                      # INVxp33 vs PDK Liberty
$S/scripts/gen_cell_leak.sh; $S/scripts/cell_leak_decomp.sh
$S/scripts/run_column.sh                          # 128-cell column read
python3 -I $S/scripts/make_results.py $S          # results.tsv
```

## (B) NS-Cache

### What it actually used

From `src/Technology.cpp` at node 7:
- **Vdd is hard-coded to 0.7 V**, so 0.7 V was available exactly.
- Devices: "based on IRDS 2017", FinFET, 2 fins per device, W_eff 107 nm per fin, Lg 22 nm.
- Ioff at 300 K: NMOS 0.147 nA/um (15.7 pA/fin) and PMOS 0.101 nA/um (10.8 pA/fin). These are logic-RVT-like, about ASAP7 RVT level and 10x ASAP7 SRAM-Vt.
- Ion is 562 uA/um, the same for NMOS and PMOS.
- HP roadmap exits at 14 nm and below. LOP and LSTP take the same branch, so the roadmap choice makes no difference.

Other run conditions:
- **Temperature: 300 K (27 C).** 298 K is rejected ("Temperature is out of range", exit 255; see `nscache/test_298K.log`), because the temperature tables start at 300 K.
- Cell: the shipped `SRAM_cell_7nm.cell`. It is 550.88 F^2 = 0.0270 um^2 (TSMC N7 HD-like), aspect ratio 0.4647, 1 F (= 1 fin) for every transistor, MinSenseVoltage 100 mV.
- Cell leakage formula (`Mat.cpp`): 2 inverters plus 1 access device. That gives 24.1 pW/cell at 0.7 V and 300 K.

### Config

The config is generated by `scripts/gen_nscache_cfg.sh`; the exact files are in `nscache/cfg/`.
- Fixed settings: DesignTarget RAM (no tags), ProcessNode 7, Capacity (B) = words x 4, WordWidth 32, DeviceRoadmap LOP, Local/GlobalAggressive wires, InternalSensing true, ForceBank 1x1 (1 active), Temperature 300 K, pruning on.
- Variant "non-H-tree": Routing non-H-tree, RepeatedNone, BufferDesignOptimization balanced.
- Variant "H-tree": Routing H-tree, RepeatedOpt, latency buffers.
- Optimisation targets ReadEDP, ReadDynamicEnergy and ReadLatency were all run. They pick the same design for 256/128/64x32 and nearly the same for 1024x32. ReadEDP is reported.
- Vashishtha array: 8192 B, 64-bit, free organisation, or forced with `-ForceMatSize (Rows x Columns): 128 x 256` and `-ForceMuxSenseAmp: 4`.
- NS-Cache always reports 1 read/write port and has no byte-enable option. Write energy is for a full word.

### Results (ReadEDP; raw outputs in `nscache/out/`, table in `nscache/nscache_all.tsv`)

| macro | routing | read pJ | write pJ | leak uW | read ns | area um^2 | mat / mux |
|---|---|---|---|---|---|---|---|
| 1024x32 | non-H-tree | 0.284 | 0.183 | 1.053 | 0.115 | 1385 | 128x64, L2 mux 2 |
| 1024x32 | H-tree | 0.155 | 0.054 | 1.053 | 0.110 | 1385 | same |
| 256x32 | non-H / H | 0.130 / 0.068 | 0.087 / 0.025 | 0.230 | 0.070 | 319 | 64x32 |
| 128x32 | non-H / H | 0.096 / 0.063 | 0.053 / 0.020 | 0.119 | 0.059 | 171 | 32x32 |
| 64x32 | non-H / H | 0.090 / 0.058 | 0.052 / 0.019 | 0.063 | 0.048 | 99 | 32x16 |
| 32x32 | non-H / H | 0.074 / 0.055 | 0.035 / 0.017 | 0.034 | 0.041 | 56 | 16x16 |
| 16x32 | non-H / H | 0.073 / 0.056 | 0.035 / 0.017 | 0.018 | 0.034 | 35 | 16x8 |
| Vash. 8 kB x64 forced | non-H / H | 0.727 / 0.500 | 0.423 / 0.196 | 1.784 | 0.184 / 0.178 | 2265 | 128x256, SA mux 4 |
| Vash. 8 kB x64 free | non-H / H | 0.521 / 0.193 | 0.326 / 0.109 | 1.96 / 2.09 | 0.134 / 0.154 | 2493 / 2631 | 128x128 / 256x64 |
| Thesis (PEX, ASAP7 122 cell) | | 0.23 | 0.25 | n/a | 0.166 (incl. setup) | 2267 | 128 rows, 4:1 |

Observations:
- The difference between the two routing modes is NS-Cache's "Non-H-Tree Dynamic Energy" term: about 0.13 pJ for 1024x32. With 1 bank, H-tree mode reports the routing term as 0, which undercounts any I/O wiring. Non-H-tree mode charges a bank-edge bus. The truth is probably in between.
- Leakage and area do not depend on the routing mode.
- Leakage per bit for 1024x32 is 32 pW all-in, against 47.5 pW/bit measured for TSMC N3 (NS-Cache README).
- Calibration against Vashishtha with the forced, matched organisation, in the same routing mode:
  - non-H-tree: k_read = 0.32, k_write = 0.59;
  - H-tree: k_read = 0.46, k_write = 1.28.
  - Applied to 1024x32: read 0.090 / 0.071 pJ, write 0.108 / 0.069 pJ.
  - Applied to 16x32: read 0.023 / 0.026 pJ, write 0.021 / 0.022 pJ.
  - The calibration rests on one design point and one published number, and the routing-mode spread of k is large, so treat these as a cross-check, not a replacement.

## (C) ngspice + OpenVAF on the ASAP7 BSIM-CMG cards

### Model setup

- Card: `pdk/asap7/asap7_pdk_r1p7/models/hspice/7nm_TT_160803.pm`, "ASAP TT models v1.0 8/3/16", level 72, version 107, with models `nmos/pmos_{sram,rvt,lvt,slvt}`.
- Conversion (`scripts/convert_cards.py`): each card becomes `.model X bsimcmg_va type=1|0` with all parameters kept except four that the 111 Verilog-A does not have:
  - `version` and `level`;
  - `coremod` (= 0) and `capmod` (= 0), both off-state switches;
  - `nseg` (= 5, only used with NQSMOD = 3).
  - The 110 Verilog-A takes `nseg` but not `coremod` or `capmod`.
- Instance geometry follows the stdcell CDL (`asap7sc7p5t_28/CDL/LVS/*.cdl`: `nmos_rvt w=27.0n l=20n nfin=1`): `nfin=N l=20n`. The card default is l = 21 nm, which gives 7 to 10 % less Ioff.
- Conditions: `.options temp=25 tnom=25`, abstol 1e-18 for DC. gmin = 1e-21 gave identical DC currents.

### Sanity check (single fin, Vds = 0.7 V, Vgs = 0, source and body at the rail; `spice/runs/sanity_*.log`)

Raw values at L = 20 nm, BSIM-CMG 111. Drain current includes GIDL and drain-to-body leakage; source current is channel only.

| device | drain pA | source (channel) pA | Clark Ioff pA | Idsat uA (Clark) |
|---|---|---|---|---|
| nmos_sram | 5.12 | 0.42 | 1 (one significant digit) | 26.5 (28.57) |
| nmos_rvt | 16.6 | 10.3 | 19 | 35.9 (37.85) |
| nmos_lvt | 138 | 133 | 242 | 43.3 (45.19) |
| nmos_slvt | 1373 | 1368 | 2444 | 49.1 (50.79) |
| pmos_sram | 3.45 | 3.41 | 4 | 26.0 (26.90) |
| pmos_rvt | 17.9 | 18.0 | 23 | 31.9 (32.88) |
| pmos_lvt | 183 | 183 | 230 | 38.9 (39.88) |
| pmos_slvt | 1919 | 1919 | 2410 | 44.7 (45.60) |

**Outcome: FAIL.** NMOS channel Ioff is 0.42 to 0.56x Clark and PMOS is 0.78 to 0.86x. Vashishtha's thesis also quotes the ASAP7 RVT compact model as about 20 pA/fin at 21 nm Lg, against my 15.5 pA drain / 9.0 pA channel at 21 nm.

Diagnostics:
- Same with BSIM-CMG 110.0.0 (`sanity_v110*`): NMOS within 0.5 %, PMOS 7 to 12 % higher. The 110 to 111 change is not the cause.
- Id-Vg metrics (`spice/idvg_metrics.tsv`):
  - SS is 60.8 to 61.6 mV/dec (NMOS) against 62.4 to 63.3. PMOS SRAM shows an unphysical 51.6 because GIDL contaminates the drain current near Vg = 0.
  - DIBL is 22 to 25 (NMOS) and 29 to 36 (PMOS) mV/V, against 19 to 22. My Vt definition is constant-current at 100 nA/fin, so the Vt offsets between flavours (for example sram minus rvt = 0.082 V) match Clark's (0.08 V), not their absolute values.
- `dvtshift_diag.sh`: NMOS dvtshift = -0.020 V brings channel Ioff to 0.80 / 19.1 / 2597 pA (SRAM / RVT / SLVT) and Idsat to 28.3 / 37.4 / 50.2 uA. PMOS -0.010 V gives 4.8 / 23.6 / 2509 pA and 26.3 / 32.0 / 44.6 uA. One Vth offset per polarity fixes Ioff and Idsat together, which points to a model-version or implementation offset, not a wrong card.
- PDK Liberty cross-check: see Short answer item 3. Raw is low by 0.71 to 0.78x for RVT/LVT/SLVT, and within 5 % for SRAM-Vt (GIDL included). The shifted card is high by 1.09 to 1.18x. The PDK's own characterisation lies between raw and shifted for every flavour.

### 6T hold leakage (`spice/cell/leak_output.txt`, decomposition in `decomp_output.txt`)

Setup:
- Cells are 111 (PU = PG = PD = 1 fin, Clark 2016 Section 5) and 122 (PU 1, PG 2, PD 2: Vashishtha thesis Table 5.1, and the cell of the local `asap7_sram_0p0` srambank_*_6t122 libraries).
- Bias: WL = 0, BL = BLB = 0.7 V, NMOS body at VSS, PMOS body at VDD, both stored values.
- Power = 0.7 V x (sum of the VDD, BL and BLB currents).

| cell | devices | raw card pW/cell | shifted card pW/cell | raw w/o GIDL | raw w/o GIDL and gate |
|---|---|---|---|---|---|
| 111 | SRAM-Vt | **18.1** | 19.7 | 4.7 | 3.1 |
| 122 | SRAM-Vt | **33.5** | 35.9 | 7.0 | 4.0 |
| 111 | RVT | 45.7 | 67.0 | 28.8 | 26.9 |
| 122 | RVT | 77.9 | 115.5 | 44.6 | 41.5 |

Notes:
- The cell is symmetric, so Q = 1 and Q = 0 agree to within 1 %.
- For SRAM-Vt, GIDL at the drains of the two pass gates (BL high, WL low) and of the off pull-down is about 75 to 80 % of the total. The card deliberately tunes GIDL per flavour (nmos_sram agidl 6e-13 against 1e-12 for RVT; pmos_sram agidl 6e-12 and bgidl 7.65e7), and the SRAM-Vt Liberty match supports it.
- The Vth shift barely changes SRAM-Vt cells, because GIDL dominates them. RVT cells change by 1.5x.
- Cell-array leakage (bits x 18.1 to 35.9 pW): 1024x32 0.59 to 1.18 uW; 256x32 0.15 to 0.29; 128x32 0.074 to 0.147; 64x32 0.037 to 0.074; 32x32 0.019 to 0.037; 16x32 0.009 to 0.018 uW. Periphery is not included. See ../sram2 for a periphery floor of a few tens of nW.

### Column read energy (optional; `spice/column/`, `scripts/gen_column.py`, `run_column.sh`)

Setup:
- 128 cells on BL/BLB. The selected cell stores 0; the 127 unselected cells store 1.
- Precharge and equalise: 2-fin and 1-fin RVT PMOS.
- WL wire cap per cell = 0.27 um x c. BL wire = 128 x 0.108 um = 13.8 um at c = 0.15 / 0.18 / 0.25 fF/um. The geometry is inferred from the thesis array (74.8 x 30.4 um, 84.2 % efficiency, 0.0292 um^2 cell: 0.108 um along the BL, 0.270 um along the WL). The c values are bracketed by the ORFS asap7 setRC values (M2 0.185, M3 0.154 fF/um).
- Pass 1 finds when the BL differential reaches 100 mV; pass 2 sets the WL so that it falls there. The energy is the precharge charge x 0.7 V plus the WL rising charge x 0.7 V.
- Solver: method=gear, reltol 1e-3, abstol 1e-12. Trapezoidal with tight tolerances failed with "timestep too small" at the source edges; see Problems.

| cell | c fF/um | dV at WL fall mV | BL fJ | WL fJ | total fJ/column | full-swing C_BL fF |
|---|---|---|---|---|---|---|
| 122 | 0.15 / 0.18 / 0.25 | 113 / 111 / 110 | 0.37 / 0.40 / 0.47 | 0.065 / 0.069 / 0.078 | 0.44 / 0.47 / 0.55 | 4.8 / 5.2 / 6.0 |
| 111 | 0.15 / 0.18 / 0.25 | 108 / 107 / 106 | 0.26 / 0.29 / 0.36 | 0.042 / 0.046 / 0.055 | 0.30 / 0.33 / 0.41 | 3.3 / 3.5 / 3.8 |

Caveats:
- The 111 runs reuse the 122 cell pitch.
- The ASAP7 cards carry no junction-area or perimeter instance data and no extraction, so the drain and coupling capacitance is low.
- My time to 100 mV is about 16 ps after the WL is fully high. The thesis needs 55 ps for 115 mV, including WL RC. So the real C_BL is probably 2 to 3x mine.
- Treat these as lower bounds. Scaled to the thesis array (256 columns), they give about 0.12 pJ of 0.23 pJ.

## Problems and deviations

- Sanity check failed as stated above. The cause is not resolved; the most likely candidate is BSIM-CMG 107 (card) against 111/110 (VA). No public BSIM-CMG 107 Verilog-A was found, and Xyce, which has 107 built in, was not attempted: it needs cmake and Trilinos, neither of which is present.
- bsim.berkeley.edu returned 401, so BSIM-CMG came from the OpenVAF-Reloaded repo (official) and from VA-Models (ngspice developer) for 110.
- NS-Cache cannot run at 25 C (minimum 300 K). Its devices are generic IRDS-2017 7 nm FinFET, not ASAP7. It has no byte-enable, and its tiny macros (512 bits) are outside its validation range. The routing-mode choice changes energy by up to 2x for small macros.
- ngspice transient with tight tolerances and the trapezoidal method failed: "timestep too small", at source edges in the column netlist. `.nodeset` on 128 latches converged to the metastable point (all nodes at 0.362 V, 139 uA crowbar). `.ic` without `uic`, together with gear at reltol 1e-3, fixed both.
- One Id-Vg sweep with gmin = 1e-21 hung. I killed it and reran with the default gmin; DC operating points with gmin = 1e-21 were identical to the default.
- The column energy depends on assumed wire capacitance and lacks junction caps. See above.
- The nmos_sram Ioff from a DC sweep point (5.57 pA) differed from the operating-point value (5.00 pA) by 10 %. This is numerical noise at the pA level with the sweep's tolerances; the operating-point values are reported.

## Files

- `results.tsv`: all numbers (macro or cell, tool, vdd, read_pJ, write_pJ, leak with unit, access_ns, area_um2, notes)
- `nscache/cfg/*.cfg`, `nscache/out/*.txt`, `nscache/nscache_all.tsv`, `nscache/test_298K.log`
- `spice/models/asap7_TT_osdi.lib` (111) and `asap7_TT_osdi110.lib` (110), converted cards; `spice/cell/asap7_TT_osdi_cal.lib` (shifted, diagnostic only)
- `spice/osdi/bsimcmg.osdi` (ee7591e5fd0d56a8d8d32e8e84b65e5664de4fd7e3f35e945913d001af5c7727) and `bsimcmg110.osdi` (f90955d78cf44aef7a93c1ec379c9877471a810d3e9967344d594d881f427a80)
- `spice/runs/` (sanity and Id-Vg), `spice/diag/`, `spice/inv/`, `spice/cell/`, `spice/column/`: netlists and logs
- `scripts/`: every script used
- `opt/bin/ngspice` (sha256 e1110bfded9b12ee528565c9fdff36ce4db416c0f0dfed0c0bde433ef88030e6); `build_ngspice/` holds the build tree and configure/make logs
