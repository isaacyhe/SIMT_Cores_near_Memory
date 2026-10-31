// GPU_and_PNM (CAL per-run energy): host API for the simulation-only activity counters (see ctr_dpi.cpp).
#pragma once
#include <cstdint>

void vx_ctr_snapshot(const char* tag, uint64_t core_cycle);  // open a new snapshot epoch; RTL groups dump on the next edge
void vx_ctr_total(const char* key, uint64_t value);           // host-side totals
void vx_ctr_close();                                          // END marker and close (after the RTL final dump)
