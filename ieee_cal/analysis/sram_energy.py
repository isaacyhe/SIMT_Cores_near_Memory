#!/usr/bin/env python3
"""SRAM macro energy table for the CAL per-run energy model (Oct 28 2026; user decision: calibrated pCACTI + band).

Inputs (copied into sram_inputs/ with their READMEs):
  pcacti_0p45V_extended.tsv  pCACTI (pdk/pcacti, 7 nm FinFET device file, 0.45 V only) per macro: read, write (raw and with the
                             6T wordline-energy fix), write fixed + per-byte split; flop register-file model for 8/4/2 words (ASAP7
                             TT RVT 0.7 V liberty, VDD rail only) incl. clock-pin energy per cycle.
  calib_vashishtha_8kB.xml   pCACTI run on Vashishtha's ASAP7 8 kB / 64-bit array (128 rows, 4:1 mux): read 0.241693 pJ, write
                             0.246405 pJ (raw) at 0.45 V. Target (Vashishtha PhD thesis ASU 2019 Sec. 5.6, PEX, TT 0.7 V):
                             read 0.23 pJ, write 0.25 pJ.
  nscache_spice_results.tsv  NS-Cache v2.1.0 (7 nm, 0.7 V native, not ASAP7) per macro and on the same 8 kB array (band);
                             ngspice/BSIM-CMG 6T hold leakage with the ASAP7 SRAM-Vt / RVT cards.
  leak_estimate.tsv          periphery leakage scaled from pCACTI to ASAP7 RVT (central) / LVT (high).
Model:
  dynamic = pCACTI(0.45 V) x (0.7/0.45)^2 x k, k = thesis / (pCACTI on the thesis array x (0.7/0.45)^2); raw pCACTI writes are used on
  both sides of the write calibration (the wordline fix is not applied to either), so the byte split's fixed part is reduced by it.
  band = the same calibration applied to NS-Cache (non-H-tree, the mode used on the thesis array): [min, max] of the two models.
  leakage = bits x 6T SRAM-Vt hold leakage (SPICE, 111 cell, raw card 18.14 pW) + RVT periphery; low = 111 raw cell only + RVT
  periphery x 0.75; high = 122 cell with the Vth-shifted card (35.89 pW) + LVT periphery.
  flop macros (8/4/2 x 32): flop model as is (already 0.7 V, VDD rail only) + clock-pin energy every busy cycle (user, Oct 28).
"""
import csv, os, sys
H = os.path.dirname(os.path.abspath(__file__))
V2 = (0.7 / 0.45) ** 2
K_R = 0.23 / (0.241693 * V2)
K_W = 0.25 / (0.246405 * V2)
NS_THESIS_R, NS_THESIS_W = 0.7270, 0.4230          # NS-Cache non-H-tree, forced 128 rows / 4:1 mux (nscache_spice_results.tsv)
KN_R, KN_W = 0.23 / NS_THESIS_R, 0.25 / NS_THESIS_W
CELL_C, CELL_HI = 18.14e-6, 35.89e-6               # uW per bit (pW -> uW)

rows = {r['macro']: r for r in csv.DictReader(open(os.path.join(H, 'sram_inputs/pcacti_0p45V_extended.tsv')), delimiter='\t')}
ns = {}
for r in csv.DictReader(open(os.path.join(H, 'sram_inputs/nscache_spice_results.tsv')), delimiter='\t'):
    if r['tool'] == 'NS-Cache ReadEDP non-H-tree' and r['macro_or_cell'].endswith('x32'):
        ns[r['macro_or_cell']] = (float(r['read_pJ']), float(r['write_pJ']))
lk = {}
for l in open(os.path.join(H, 'sram_inputs/leak_estimate.tsv')):
    if l.startswith(('#', 'macro')): continue
    f = l.rstrip('\n').split('\t'); lk[f[0]] = (int(f[1]), float(f[6]), float(f[7]))   # bits, periph RVT, periph LVT

out = []
for m in ('1024x32', '512x32', '256x32', '128x32', '64x32', '32x32', '16x32'):
    r = rows[m]
    rd, wr, wraw = float(r['read_pJ']), float(r['write_pJ']), float(r['write_raw_pcacti_pJ'])
    wfix, wbyte = float(r['write_fixed_pJ']) - (wr - wraw), float(r['write_per_byte_pJ'])
    assert abs(wfix + 4 * wbyte - wraw) < 1e-4 * wraw + 5e-6, (m, wfix + 4 * wbyte, wraw)   # table values are rounded
    R, W, WF, WB = rd * V2 * K_R, wraw * V2 * K_W, wfix * V2 * K_W, wbyte * V2 * K_W
    nr, nw = ns[m][0] * KN_R, ns[m][1] * KN_W
    bits, prvt, plvt = lk[m]
    out.append(dict(macro=m, model='pcacti_cal', read_pJ=R, write_pJ=W, write_fixed_pJ=WF, write_per_byte_pJ=WB,
                    read_lo_pJ=min(R, nr), read_hi_pJ=max(R, nr), write_lo_pJ=min(W, nw), write_hi_pJ=max(W, nw),
                    leak_uW=bits * CELL_C + prvt, leak_lo_uW=bits * CELL_C + 0.75 * prvt, leak_hi_uW=bits * CELL_HI + plvt, clk_pJ_per_cycle=0.0))
for m in ('8x32', '4x32', '2x32'):
    r = rows[m]; R, W = float(r['read_pJ']), float(r['write_pJ'])
    out.append(dict(macro=m, model='flop', read_pJ=R, write_pJ=W, write_fixed_pJ=W, write_per_byte_pJ=0.0,
                    read_lo_pJ=R, read_hi_pJ=R, write_lo_pJ=W, write_hi_pJ=W,
                    leak_uW=float(r['leak_uW']), leak_lo_uW=float(r['leak_uW']), leak_hi_uW=float(r['leak_uW']),
                    clk_pJ_per_cycle=float(r['clk_pins_pJ_per_cycle'])))
cols = list(out[0])
w = csv.writer(open(os.path.join(H, 'sram_energy.tsv'), 'w'), delimiter='\t', lineterminator='\n')
w.writerow(['# sram_energy.py (Oct 28): 0.7 V TT; k_read=%.4f k_write=%.4f (pCACTI x V^2 -> Vashishtha ASAP7 8 kB PEX); NS-Cache band k=%.3f/%.3f' % (K_R, K_W, KN_R, KN_W)])
w.writerow(cols)
for o in out: w.writerow([o[c] if isinstance(o[c], str) else '%.6g' % o[c] for c in cols])
print(open(os.path.join(H, 'sram_energy.tsv')).read())
