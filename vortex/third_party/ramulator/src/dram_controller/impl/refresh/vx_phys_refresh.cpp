#include <vector>

#include "base/base.h"
#include "dram_controller/controller.h"
#include "dram_controller/refresh.h"

// GPU_and_PNM (CAL energy): refresh manager for the shadow Ramulator only.
// The stock AllBank manager never fires on HBM2 (no "rank" level), so the timing model issues no refresh. This one
// issues one all-bank REFab per channel (all lower address levels -1, so both pseudo-channels are refreshed) at the
// PHYSICAL interval: refi_ticks = tREFI / DRAM tick period, which is non-integer at most clock ratios, so it uses an
// accumulated-time counter. tRFC is enforced by the DRAM spec (timing nRFC, set in the shadow config).
// vx_phys_refresh_enable(false) stops new refreshes (used while draining at the end of the run).
static bool g_vx_phys_refresh_enabled = true;
extern "C" void vx_phys_refresh_enable(bool enable) { g_vx_phys_refresh_enabled = enable; }
// true until the end-of-run drain starts (DramSim::finalize); stats plugins use it to separate run and drain time
extern "C" bool vx_phys_refresh_is_enabled() { return g_vx_phys_refresh_enabled; }

namespace Ramulator {

class VxPhysRefresh : public IRefreshManager, public Implementation {
  RAMULATOR_REGISTER_IMPLEMENTATION(IRefreshManager, VxPhysRefresh, "VxPhysRefresh", "Physical-rate all-bank refresh per channel (Vortex CAL shadow).")
  private:
    IDRAM* m_dram = nullptr;
    IDRAMController* m_ctrl = nullptr;
    int m_dram_org_levels = -1;
    int m_ref_req_id = -1;
    double m_refi_ticks = 0.0;
    double m_next = 0.0;
    uint64_t m_clk = 0;

  public:
    void init() override {
      m_ctrl = cast_parent<IDRAMController>();
      m_refi_ticks = param<double>("refi_ticks").desc("Refresh interval in DRAM ticks (may be fractional)").required();
      if (m_refi_ticks < 1.0) throw std::runtime_error("VxPhysRefresh: refi_ticks must be >= 1");
    };

    void setup(IFrontEnd* /*frontend*/, IMemorySystem* /*memory_system*/) override {
      m_dram = m_ctrl->m_dram;
      m_dram_org_levels = m_dram->m_levels.size();
      m_ref_req_id = m_dram->m_requests("all-bank-refresh");
      m_next = m_refi_ticks;
    };

    void tick() override {
      ++m_clk;
      if (!g_vx_phys_refresh_enabled) return;
      if (double(m_clk) >= m_next) {
        m_next += m_refi_ticks;
        std::vector<int> addr_vec(m_dram_org_levels, -1);
        addr_vec[0] = m_ctrl->m_channel_id;
        Request req(addr_vec, m_ref_req_id);
        if (!m_ctrl->priority_send(req)) {
          throw std::runtime_error("VxPhysRefresh: failed to send refresh");
        }
      }
    };
};

}  // namespace Ramulator
