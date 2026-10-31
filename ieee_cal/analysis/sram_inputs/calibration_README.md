# pCACTI calibration against Vashishtha's ASAP7 8 kB array (Oct 28)
Target (Vashishtha PhD thesis ASU 2019 Sec. 5.6, PEX, TT 0.7 V): 8 kB, 64-bit word, 128 cells/bitline, 4:1 column mux:
read 0.23 pJ, write 0.25 pJ per access.
pCACTI (repo binary md5 aec824bf..., same xml as scratchpad/sram/xml/ram_1024x32_main.xml but cache 8192 B, block 8 B, bus 64,
force_cache_config: Ndwl=1 Ndbl=4 Nspd=2 Ndcm=4 -> subarray height 0.008064 mm = 128 rows x 0.063 um cell, 4:1 mux):
read 0.2417 pJ, write 0.2464 pJ at 0.45 V. (Ndwl=2 variant: 0.2412 / 0.2445.) Free optimisation: 0.1950 / 0.1633 (Ndcm=8, 128 rows).
V^2 scale to 0.7 V: x2.4198 -> read 0.585, write 0.596 pJ.
k_read = 0.23 / 0.585 = 0.393; k_write = 0.25 / 0.596 = 0.419.
Calibrated factor on pCACTI 0.45 V numbers: read 2.42 x 0.393 = 0.951; write 2.42 x 0.419 = 1.014
(i.e. the calibrated 0.7 V values are within 5% of the raw 0.45 V pCACTI values).
Caveat: one published design point; the thesis cell (122, ~0.029 um2) is 4.4x pCACTI's cell area, so the agreement is an empirical
anchor, not a physical match. g.xml grid: g.txt outputs not kept per point (rerun loop in session to reproduce).
