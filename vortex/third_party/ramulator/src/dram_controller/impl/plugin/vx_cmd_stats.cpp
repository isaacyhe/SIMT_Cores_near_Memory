#include <map>
#include <vector>
#include <fstream>
#include <limits>

#include "base/base.h"
#include "dram/dram.h"
#include "dram_controller/controller.h"
#include "dram_controller/plugin.h"

extern "C" bool vx_phys_refresh_is_enabled();  // false once the end-of-run drain has started (vx_phys_refresh.cpp)

namespace Ramulator {
// CAL energy: passive DRAM command statistics (one instance per channel controller; path given by the host).
// It only observes the command the scheduler issued in each tick, so timing is unchanged. Output per channel:
//   <CMD>=n                 totals for ACT PRE PREA RD WR RDA WRA REFab REFsb
//   pc<k>.<CMD>=n           the same per pseudo-channel, for commands addressed to one pseudo-channel
//   PREA_banks_closed=n     open banks closed by PREA (PREA energy scales with them)
//   ACT_after_PREA=n, ACT_reopen_PREA=n   ACTs to a bank / to the same row a PREA had closed (refresh-induced reopen)
//   REF_to_ACT_min=n        smallest gap in controller ticks from a REFab to the next ACT in this channel (proves nRFC)
//   ticks=n                 controller ticks observed (includes the end-of-run drain)
//   open_ticks=n            ticks with at least one bank open in this channel (active vs precharged standby), incl. drain
//   pc<k>.open_ticks=n      the same per pseudo-channel
//   ticks_run=n, open_ticks_run=n, pc<k>.open_ticks_run=n   the same over the run only (before the end-of-run drain)
//   REF_to_ACT_min=NA       when no REFab was followed by an ACT
class VxCmdStats : public IControllerPlugin, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IControllerPlugin, VxCmdStats, "VxCmdStats", "Vortex DRAM command statistics for energy.")
private:
  IDRAM* m_dram = nullptr;
  std::string m_path;
  std::vector<std::string> m_names = {"ACT", "PRE", "PREA", "RD", "WR", "RDA", "WRA", "REFab", "REFsb"};
  std::map<int, uint64_t> m_count;
  std::map<int, std::map<int, uint64_t>> m_count_pc;  // pc -> cmd -> count
  int c_act = -1, c_pre = -1, c_prea = -1, c_rda = -1, c_wra = -1, c_refab = -1;
  int m_pc_lvl = -1, m_bank_lvl = -1, m_row_lvl = -1;
  std::map<std::vector<int>, int> m_open;            // bank -> open row
  std::map<std::vector<int>, int> m_closed_by_prea;  // bank -> row that the last PREA closed
  uint64_t m_act_after_prea = 0, m_act_reopen_prea = 0, m_prea_banks_closed = 0;
  uint64_t m_tick = 0;
  uint64_t m_open_ticks = 0;
  std::map<int, uint64_t> m_open_ticks_pc;
  uint64_t m_tick_run = 0, m_open_ticks_run = 0;
  std::map<int, uint64_t> m_open_ticks_pc_run;
  uint64_t m_last_ref_tick = 0;
  bool m_ref_seen = false, m_ref_waiting_act = false;
  uint64_t m_ref_to_act_min = std::numeric_limits<uint64_t>::max();
  std::vector<int> bank_key(const AddrVec_t& a) const { return std::vector<int>(a.begin(), a.begin() + m_bank_lvl + 1); }
public:
  void init() override { m_path = param<std::string>("path").desc("Output path prefix").required(); }
  void setup(IFrontEnd* /*frontend*/, IMemorySystem* /*memory_system*/) override {
    m_ctrl = cast_parent<IDRAMController>();
    m_dram = m_ctrl->m_dram;
    for (auto& n : m_names) m_count[m_dram->m_commands(n)] = 0;
    c_act = m_dram->m_commands("ACT"); c_pre = m_dram->m_commands("PRE"); c_prea = m_dram->m_commands("PREA");
    c_rda = m_dram->m_commands("RDA"); c_wra = m_dram->m_commands("WRA"); c_refab = m_dram->m_commands("REFab");
    m_pc_lvl = m_dram->m_levels("pseudochannel"); m_bank_lvl = m_dram->m_levels("bank"); m_row_lvl = m_dram->m_levels("row");
  }
  void update(bool request_found, ReqBuffer::iterator& req_it) override {
    ++m_tick;
    const bool in_run = vx_phys_refresh_is_enabled();
    if (in_run) ++m_tick_run;
    // open-bank time, sampled before this tick's command (state left by previous commands)
    if (!m_open.empty()) {
      ++m_open_ticks;
      if (in_run) ++m_open_ticks_run;
      int last_pc = -2;
      for (auto& kv : m_open) {             // map is ordered by bank key, whose element m_pc_lvl is the pseudo-channel
        int pc = kv.first[m_pc_lvl];
        if (pc != last_pc) { ++m_open_ticks_pc[pc]; if (in_run) ++m_open_ticks_pc_run[pc]; last_pc = pc; }
      }
    }
    if (!request_found) return;
    int c = req_it->command;
    m_count[c]++;
    int pc = req_it->addr_vec[m_pc_lvl];
    if (pc >= 0) m_count_pc[pc][c]++;
    if (c == c_act) {
      if (m_ref_waiting_act) {
        m_ref_to_act_min = std::min(m_ref_to_act_min, m_tick - m_last_ref_tick);
        m_ref_waiting_act = false;
      }
      auto k = bank_key(req_it->addr_vec);
      int row = req_it->addr_vec[m_row_lvl];
      auto p = m_closed_by_prea.find(k);
      if (p != m_closed_by_prea.end()) {
        m_act_after_prea++;
        if (p->second == row) m_act_reopen_prea++;
        m_closed_by_prea.erase(p);
      }
      m_open[k] = row;
    } else if (c == c_pre || c == c_rda || c == c_wra) {
      m_open.erase(bank_key(req_it->addr_vec));
    } else if (c == c_prea) {
      m_prea_banks_closed += m_open.size();
      for (auto& kv : m_open) m_closed_by_prea[kv.first] = kv.second;
      m_open.clear();
    } else if (c == c_refab) {
      m_last_ref_tick = m_tick;
      m_ref_seen = true;
      m_ref_waiting_act = true;
    }
  }
  void finalize() override {
    std::ofstream out(m_path + ".ch" + std::to_string(m_ctrl->m_channel_id));
    for (auto& n : m_names) out << n << "=" << m_count[m_dram->m_commands(n)] << "\n";
    for (auto& pcm : m_count_pc)
      for (auto& n : m_names) out << "pc" << pcm.first << "." << n << "=" << pcm.second[m_dram->m_commands(n)] << "\n";
    out << "PREA_banks_closed=" << m_prea_banks_closed << "\n";
    out << "ACT_after_PREA=" << m_act_after_prea << "\n" << "ACT_reopen_PREA=" << m_act_reopen_prea << "\n";
    if (m_ref_to_act_min == std::numeric_limits<uint64_t>::max()) out << "REF_to_ACT_min=NA\n";
    else out << "REF_to_ACT_min=" << m_ref_to_act_min << "\n";
    out << "ticks=" << m_tick << "\n";
    out << "open_ticks=" << m_open_ticks << "\n";
    for (auto& kv : m_open_ticks_pc) out << "pc" << kv.first << ".open_ticks=" << kv.second << "\n";
    out << "ticks_run=" << m_tick_run << "\n" << "open_ticks_run=" << m_open_ticks_run << "\n";
    for (auto& kv : m_open_ticks_pc_run) out << "pc" << kv.first << ".open_ticks_run=" << kv.second << "\n";
  }
};
}  // namespace Ramulator
