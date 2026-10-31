// GPU_and_PNM (CAL per-run energy): host side of the simulation-only activity counters (VX_sim_ctrs.sv).
// Output goes to $VX_CTR_FILE (nothing is written when it is unset). Line formats:
//   H vx_ctr 1 pid=<pid>                      header, once
//   E <epoch> <tag> <core_cycle>              snapshot epoch opened by the host (launch boundary, trace start/stop)
//   C <epoch|F> <scope> <name> <value>        counter value at a snapshot (F = final dump)
//   I <scope> <info>                          constant geometry info of a counter group (written with the final dump)
//   T <key> <value>                           host-side totals (core ticks, DRAM ticks, ...)
//   END                                       written once after the final dump
#include <cstdio>
#include <cstdlib>
#include <cstdint>
#include <cstring>
#include <string>
#include <unistd.h>
#include "ctr_dpi.h"

namespace {
FILE* g_file = nullptr;
bool  g_tried = false;
int   g_epoch = 0;
bool  g_closed = false;

FILE* out() {
  if (!g_tried) {
    g_tried = true;
    const char* path = getenv("VX_CTR_FILE");
    if (path && *path) {
      g_file = fopen(path, "w");
      if (!g_file) { fprintf(stderr, "error: cannot open VX_CTR_FILE=%s\n", path); std::abort(); }
      fprintf(g_file, "H vx_ctr 1 pid=%d\n", (int)getpid());
    }
  }
  return g_closed ? nullptr : g_file;
}

std::string name_at(const char* names, int idx) {
  const char* p = names;
  for (int i = 0; i < idx && p; ++i) { p = strchr(p, ','); if (p) ++p; }
  if (!p) return "ctr" + std::to_string(idx);
  const char* e = strchr(p, ',');
  return e ? std::string(p, e - p) : std::string(p);
}
}  // namespace

extern "C" int dpi_ctr_epoch() { return g_epoch; }

extern "C" void dpi_ctr(const char* scope, const char* names, const char* info, int idx,
                        unsigned long long value, int epoch) {
  FILE* f = out();
  if (!f) return;
  if (epoch < 0) {
    if (idx == 0 && info && *info) fprintf(f, "I %s %s\n", scope, info);
    fprintf(f, "C F %s %s %llu\n", scope, name_at(names, idx).c_str(), value);
  } else {
    fprintf(f, "C %d %s %s %llu\n", epoch, scope, name_at(names, idx).c_str(), value);
  }
}

void vx_ctr_snapshot(const char* tag, uint64_t core_cycle) {
  ++g_epoch;
  FILE* f = out();
  if (f) fprintf(f, "E %d %s %llu\n", g_epoch, tag, (unsigned long long)core_cycle);
}

void vx_ctr_total(const char* key, uint64_t value) {
  FILE* f = out();
  if (f) fprintf(f, "T %s %llu\n", key, (unsigned long long)value);
}

void vx_ctr_close() {
  FILE* f = out();
  if (f) { fprintf(f, "END\n"); fclose(f); }
  g_closed = true;
}
