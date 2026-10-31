// Copyright © 2019-2023
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include "dram_sim.h"
#include "util.h"
#include <fstream>

DISABLE_WARNING_PUSH
DISABLE_WARNING_UNUSED_PARAMETER
DISABLE_WARNING_MISSING_FIELD_INITIALIZERS
#include <base/base.h>
#include <base/request.h>
#include <base/config.h>
#include <frontend/frontend.h>
#include <memory_system/memory_system.h>
DISABLE_WARNING_POP
#include <cstdlib>
#include <cmath>
#include <deque>

// GPU_and_PNM (CAL energy): shadow refresh switch exported by libramulator (vx_phys_refresh.cpp)
extern "C" void vx_phys_refresh_enable(bool enable);

using namespace vortex;

class DramSim::Impl {
private:
	struct mem_req_t {
		uint64_t addr;
		bool is_write;
		ResponseCallback callback;
		void* arg;
		uint64_t line;     // GPU_and_PNM: Vortex line index (addr / cpu_channel_size_)
		uint32_t sub;      // sub-request index within the line
		uint64_t byteen;   // line byte enables (writes)
	};
	struct shadow_req_t {
		uint64_t addr;
		bool is_write;
	};

	Ramulator::IFrontEnd* ramulator_frontend_;
	Ramulator::IMemorySystem* ramulator_memorysystem_;
	uint32_t cpu_channel_size_;
	uint64_t cpu_cycles_;
	uint32_t scaled_dram_cycles_;
	static const uint32_t tick_cycles_ = 1000;
	static const uint32_t dram_channel_size_ = 16; // 128 bits
	std::queue<mem_req_t> pending_reqs_;

	// GPU_and_PNM (CAL energy, enabled by VX_DRAM_CMDSTATS=<path prefix>): a non-inflated SHADOW Ramulator.
	// Same DRAM and clock ratio as the timing model, but (1) physical addresses: each Vortex line is two 32 B transactions
	// (org channel_width 128 = one HBM2 pseudo-channel burst, 1 KB rows), lines interleaved across channels and kept in one
	// row, instead of the timing model's aliased 4 x 16 B stream; (2) physical-rate refresh (VxPhysRefresh, nRFC in the
	// spec); (3) fully byte-masked write transactions are skipped. It is fed when the timing model accepts a line's
	// sub-requests and never answers the core, so performance comes only from the timing model.
	std::string stats_prefix_;
	Ramulator::IFrontEnd* shadow_frontend_ = nullptr;
	Ramulator::IMemorySystem* shadow_memorysystem_ = nullptr;
	std::deque<shadow_req_t> shadow_queue_;
	uint32_t shadow_ch_bits_ = 0;
	static const uint32_t shadow_tx_size_ = 32;
	uint64_t n_timing_rd_ = 0, n_timing_wr_ = 0;          // sub-requests accepted by the timing model
	uint64_t n_lines_rd_ = 0, n_lines_wr_ = 0;            // Vortex lines accepted (sub-request 0)
	uint64_t n_shadow_rd_ = 0, n_shadow_wr_ = 0;          // transactions accepted by the shadow
	uint64_t n_shadow_masked_ = 0;                        // write transactions skipped (no byte enabled)
	uint64_t shadow_backlog_max_ = 0, shadow_backlog_sum_ = 0;
	uint64_t dram_ticks_ = 0;
	double r_eff_ = 1.0;
	double tick_ns_ = 2.0;
	bool shadow_mirror_ = false;   // VX_DRAM_SHADOW_MODE=mirror: timing addresses/refresh/feed (plumbing gate only)
	bool finalized_ = false;

	uint64_t shadow_addr(uint64_t line, uint32_t j) const {
		const uint64_t C = 1ull << shadow_ch_bits_;
		uint64_t t = (line & (C - 1)) | (uint64_t(j) << shadow_ch_bits_) | ((line >> shadow_ch_bits_) << (shadow_ch_bits_ + 1));
		return t * shadow_tx_size_;
	}

	void shadow_enqueue(const mem_req_t& req) {
		if (shadow_mirror_) { shadow_queue_.push_back({req.addr, req.is_write}); return; }
		// timing sub-requests are 16 B, shadow transactions 32 B: feed transaction j when sub-request 2j is accepted
		const uint32_t per_tx = shadow_tx_size_ / dram_channel_size_;
		if (req.sub % per_tx != 0) return;
		uint32_t j = req.sub / per_tx;
		if (req.is_write) {
			uint64_t m = (shadow_tx_size_ >= 64) ? ~0ull : (((1ull << shadow_tx_size_) - 1) << (j * shadow_tx_size_));
			if ((req.byteen & m) == 0) { ++n_shadow_masked_; return; }
		}
		shadow_queue_.push_back({shadow_addr(req.line, j), req.is_write});
	}

	void shadow_tick() {
		while (!shadow_queue_.empty()) {
			auto& q = shadow_queue_.front();
			auto type = q.is_write ? Ramulator::Request::Type::Write : Ramulator::Request::Type::Read;
			if (!shadow_frontend_->receive_external_requests(type, q.addr, 0, nullptr)) break;
			if (q.is_write) ++n_shadow_wr_; else ++n_shadow_rd_;
			shadow_queue_.pop_front();
		}
		shadow_backlog_sum_ += shadow_queue_.size();
		if (shadow_queue_.size() > shadow_backlog_max_) shadow_backlog_max_ = shadow_queue_.size();
		shadow_memorysystem_->tick();
	}

	void handle_pending_requests() {
		if (pending_reqs_.empty())
			return;
		auto& req = pending_reqs_.front();
		auto req_type = req.is_write ? Ramulator::Request::Type::Write : Ramulator::Request::Type::Read;
		std::function<void(Ramulator::Request&)> callback = nullptr;
		if (req.callback) {
			callback = [req_callback = std::move(req.callback), req_arg = std::move(req.arg)](Ramulator::Request& /*dram_req*/) {
				req_callback(req_arg);
			};
		}
		if (ramulator_frontend_->receive_external_requests(req_type, req.addr, 0, callback)) {
			if (req.is_write) ++n_timing_wr_; else ++n_timing_rd_;
			if (req.sub == 0) { if (req.is_write) ++n_lines_wr_; else ++n_lines_rd_; }
			if (shadow_memorysystem_) this->shadow_enqueue(req);
			if (req.is_write) {
				// Ramulator does not handle write responses, so we fire the callback ourselves.
				if (req.callback) {
					req.callback(req.arg);
				}
			}
			pending_reqs_.pop();
		}
	}

public:
	Impl(uint32_t num_channels, uint32_t channel_size, float clock_ratio) {
		// Base Ramulator config (built by a function so the shadow gets an independent copy; yaml-cpp nodes alias and
		// YAML::Clone is not exported by the bundled yaml-cpp)
		auto build_config = [&](bool with_trace) -> YAML::Node {
			YAML::Node dram_config;
			dram_config["Frontend"]["impl"] = "GEM5";
			dram_config["MemorySystem"]["impl"] = "GenericDRAM";
			dram_config["MemorySystem"]["clock_ratio"] = 1;
			dram_config["MemorySystem"]["DRAM"]["impl"] = "HBM2";
			dram_config["MemorySystem"]["DRAM"]["org"]["preset"] = "HBM2_8Gb";
			dram_config["MemorySystem"]["DRAM"]["org"]["density"] = 8192;
			dram_config["MemorySystem"]["DRAM"]["org"]["channel"] = num_channels;
			dram_config["MemorySystem"]["DRAM"]["timing"]["preset"] = "HBM2_2Gbps";
	#ifndef MEM_LAT_SCALE
	#define MEM_LAT_SCALE 1
	#endif
	#ifndef MEM_BW_SCALE
	#define MEM_BW_SCALE 1
	#endif
			// Decoupled proximity (CAL extension). MEM_CLOCK_RATIO speeds up the DRAM clock, which shortens
			// every timing and the data burst together. MEM_LAT_SCALE multiplies the latency-class timings
			// (row/column access, write recovery, refresh, activation limits) so that, combined with the faster
			// clock, access latency in core cycles stays where it was; MEM_BW_SCALE multiplies the burst and
			// column-to-column timings so that bus bandwidth in core cycles stays where it was. Both default to 1,
			// which leaves the HBM2_2Gbps preset untouched. Base values are the preset's (HBM2.cpp).
			if (MEM_LAT_SCALE != 1 || MEM_BW_SCALE != 1) {
				auto T = dram_config["MemorySystem"]["DRAM"]["timing"];
				const int L = MEM_LAT_SCALE, B = MEM_BW_SCALE;
				T["nCL"] = 7 * L;  T["nRCDRD"] = 7 * L;  T["nRCDWR"] = 7 * L;  T["nRP"] = 7 * L;  T["nRAS"] = 17 * L;
				T["nRC"] = 19 * L; T["nWR"] = 8 * L;     T["nRTPS"] = 2 * L;   T["nRTPL"] = 3 * L; T["nCWL"] = 2 * L;
				T["nRRDS"] = 2 * L; T["nRRDL"] = 3 * L;  T["nWTRS"] = 3 * L;   T["nWTRL"] = 4 * L; T["nRTW"] = 3 * L;
				T["nFAW"] = 15 * L; T["nRFCSB"] = 160 * L; T["nREFI"] = 3900 * L; T["nRREFD"] = 8 * L;
				T["nRFC"] = 350 * L; T["nREFISB"] = 350 * L; // HBM2 8Gb: tRFC 350 ns at tCK 1 ns (the preset derives both from its table)
				T["nBL"] = 4 * B;   T["nCCDS"] = 1 * B;  T["nCCDL"] = 2 * B;
			}
			dram_config["MemorySystem"]["Controller"]["impl"] = "Generic";
			dram_config["MemorySystem"]["Controller"]["Scheduler"]["impl"] = "FRFCFS";
			dram_config["MemorySystem"]["Controller"]["RefreshManager"]["impl"] = "AllBank";
			dram_config["MemorySystem"]["Controller"]["RowPolicy"]["impl"] = "OpenRowPolicy";
			if (with_trace && getenv("VX_DRAM_TRACE")) {   // Ramulator command trace only on request (GB-scale, and racy across parallel runs)
				YAML::Node draw_plugin;
				draw_plugin["ControllerPlugin"]["impl"] = "TraceRecorder";
				draw_plugin["ControllerPlugin"]["path"] = "./trace/ramulator.log";
				dram_config["MemorySystem"]["Controller"]["plugins"].push_back(draw_plugin);
			}
			dram_config["MemorySystem"]["AddrMapper"]["impl"] = "RoBaRaCoCh";
			return dram_config;
		};
		YAML::Node dram_config = build_config(true);
		cpu_channel_size_ = channel_size;
		scaled_dram_cycles_ = static_cast<uint64_t>(clock_ratio * tick_cycles_);
		r_eff_ = double(scaled_dram_cycles_) / tick_cycles_;   // one DRAM tick = r_eff core cycles = core_period * r_eff
	#ifndef CORE_PERIOD_PS
	#define CORE_PERIOD_PS 2000   // core clock period of the design's layout (16t_8w: 3000, 333 1/3 MHz; Oct 27)
	#endif
		tick_ns_ = CORE_PERIOD_PS / 1000.0 * r_eff_;            // physical DRAM tick (2 r_eff ns at 500 MHz)
		YAML::Node shadow_config;
		if (const char* cs = getenv("VX_DRAM_CMDSTATS")) {   // CAL energy: per-run command counts (see VxCmdStats) + shadow
			stats_prefix_ = cs;
			shadow_config = build_config(false);               // independent copy, no trace plugin
			YAML::Node stats_plugin;
			stats_plugin["ControllerPlugin"]["impl"] = "VxCmdStats";
			stats_plugin["ControllerPlugin"]["path"] = stats_prefix_ + ".timing";
			dram_config["MemorySystem"]["Controller"]["plugins"].push_back(stats_plugin);
			const char* mode = getenv("VX_DRAM_SHADOW_MODE");
			shadow_mirror_ = (mode && std::string(mode) == "mirror");
			if (!shadow_mirror_) {
				// shadow: physical addresses (32 B transactions, 1 KB rows), physical refresh
				shadow_config["MemorySystem"]["DRAM"]["org"]["channel_width"] = 128;
				shadow_config["MemorySystem"]["DRAM"]["timing"]["nRFC"] = (int)std::ceil(350.0 / tick_ns_);   // tRFC 350 ns
				shadow_config["MemorySystem"]["Controller"]["RefreshManager"]["impl"] = "VxPhysRefresh";
				shadow_config["MemorySystem"]["Controller"]["RefreshManager"]["refi_ticks"] = 3900.0 / tick_ns_; // tREFI 3.9 us
			}
			YAML::Node shadow_plugin;
			shadow_plugin["ControllerPlugin"]["impl"] = "VxCmdStats";
			shadow_plugin["ControllerPlugin"]["path"] = stats_prefix_ + ".shadow";
			shadow_config["MemorySystem"]["Controller"]["plugins"].push_back(shadow_plugin);
			uint32_t nc = num_channels; while (nc > 1) { nc >>= 1; ++shadow_ch_bits_; }
			if ((1u << shadow_ch_bits_) != num_channels) { std::cerr << "error: shadow needs a power-of-2 channel count" << std::endl; std::abort(); }
		}

		ramulator_frontend_ = Ramulator::Factory::create_frontend(dram_config);
		ramulator_memorysystem_ = Ramulator::Factory::create_memory_system(dram_config);
		ramulator_frontend_->connect_memory_system(ramulator_memorysystem_);
		ramulator_memorysystem_->connect_frontend(ramulator_frontend_);

		if (!stats_prefix_.empty()) {
			shadow_frontend_ = Ramulator::Factory::create_frontend(shadow_config);
			shadow_memorysystem_ = Ramulator::Factory::create_memory_system(shadow_config);
			shadow_frontend_->connect_memory_system(shadow_memorysystem_);
			shadow_memorysystem_->connect_frontend(shadow_frontend_);
		}
		this->reset();
	}

	~Impl() { this->finalize(); }

	// Write statistics once (destructor, or the processor's finalize/atexit path). Idempotent.
	void finalize() {
		if (finalized_) return;
		finalized_ = true;
		if (stats_prefix_.empty()) {
			std::ofstream nullstream("ramulator.stats.log");
			auto original_buf = std::cout.rdbuf();
			std::cout.rdbuf(nullstream.rdbuf());
			ramulator_frontend_->finalize();
			ramulator_memorysystem_->finalize();
			std::cout.rdbuf(original_buf);
			return;
		}
		// CAL energy: drain both models (no new refresh), so every accepted request is issued and counted, then write
		// stats per instance. Ticks before the drain are the run's DRAM time; drain ticks are reported separately.
		const uint64_t ticks_run = dram_ticks_;
		vx_phys_refresh_enable(false);
		uint64_t drain = 0;
		const uint64_t cap = 50000000ull;
		while (drain < cap && (!pending_reqs_.empty() || ramulator_memorysystem_->vx_outstanding() != 0
		                       || !shadow_queue_.empty() || shadow_memorysystem_->vx_outstanding() != 0)) {
			this->handle_pending_requests();
			ramulator_memorysystem_->tick();
			this->shadow_tick();
			++drain;
		}
		const bool drained = (drain < cap);
		{
			std::ofstream out(stats_prefix_ + ".summary");
			out << "shadow_mode=" << (shadow_mirror_ ? "mirror" : "physical") << "\n" << "r_eff=" << r_eff_ << "\n" << "dram_ticks_run=" << ticks_run << "\n" << "drain_ticks=" << drain << "\n"
			    << "drained=" << (drained ? 1 : 0) << "\n"
			    << "timing_sub_rd=" << n_timing_rd_ << "\n" << "timing_sub_wr=" << n_timing_wr_ << "\n"
			    << "lines_rd=" << n_lines_rd_ << "\n" << "lines_wr=" << n_lines_wr_ << "\n"
			    << "shadow_tx_rd=" << n_shadow_rd_ << "\n" << "shadow_tx_wr=" << n_shadow_wr_ << "\n"
			    << "shadow_tx_masked=" << n_shadow_masked_ << "\n"
			    << "shadow_backlog_max=" << shadow_backlog_max_ << "\n" << "shadow_backlog_sum=" << shadow_backlog_sum_ << "\n"
			    << "shadow_refi_ticks=" << (3900.0 / tick_ns_) << "\n" << "shadow_nrfc=" << (int)std::ceil(350.0 / tick_ns_) << "\n" << "core_period_ps=" << CORE_PERIOD_PS << "\n"
			    << "END\n";
		}
		auto finalize_to = [](Ramulator::IFrontEnd* fe, Ramulator::IMemorySystem* ms, const std::string& path) {
			std::ofstream statstream(path);
			auto original_buf = std::cout.rdbuf();
			std::cout.rdbuf(statstream.rdbuf());
			fe->finalize();
			ms->finalize();
			std::cout.rdbuf(original_buf);
		};
		finalize_to(ramulator_frontend_, ramulator_memorysystem_, stats_prefix_ + ".timing.stats");
		finalize_to(shadow_frontend_, shadow_memorysystem_, stats_prefix_ + ".shadow.stats");
		if (!drained) { std::cerr << "error: DRAM drain did not finish" << std::endl; }
	}

	void reset() {
		cpu_cycles_ = 0;
	}

	void tick() {
		cpu_cycles_ += tick_cycles_;
		while (cpu_cycles_ >= scaled_dram_cycles_) {
			this->handle_pending_requests();
			ramulator_memorysystem_->tick();
			if (shadow_memorysystem_) this->shadow_tick();
			++dram_ticks_;
			cpu_cycles_ -= scaled_dram_cycles_;
		}
	}

	void send_request(uint64_t addr, bool is_write, ResponseCallback response_cb, void* arg, uint64_t byteen) {
		const uint64_t line = addr / cpu_channel_size_;
		// enqueue the request
		if (cpu_channel_size_ > dram_channel_size_) {
			uint32_t n = cpu_channel_size_ / dram_channel_size_;
			for (uint32_t i = 0; i < n; ++i) {
				uint64_t dram_byte_addr = (addr / cpu_channel_size_) * dram_channel_size_ + (i * dram_channel_size_);
				if (i == 0) {
					pending_reqs_.push({dram_byte_addr, is_write, response_cb, arg, line, i, byteen});
				} else {
					pending_reqs_.push({dram_byte_addr, is_write, nullptr, nullptr, line, i, byteen});
				}
			}
		} else if (cpu_channel_size_ < dram_channel_size_) {
			uint64_t dram_byte_addr = (addr / cpu_channel_size_) * dram_channel_size_;
			pending_reqs_.push({dram_byte_addr, is_write, response_cb, arg, line, 0, byteen});
		} else {
			uint64_t dram_byte_addr = addr;
			pending_reqs_.push({dram_byte_addr, is_write, response_cb, arg, line, 0, byteen});
		}
	}
};

///////////////////////////////////////////////////////////////////////////////

DramSim::DramSim(uint32_t num_channels, uint32_t channel_size, float clock_ratio)
	: impl_(new Impl(num_channels, channel_size, clock_ratio))
{}

DramSim::~DramSim() {
  delete impl_;
}

void DramSim::finalize() {
  impl_->finalize();
}

void DramSim::reset() {
  impl_->reset();
}

void DramSim::tick() {
  impl_->tick();
}

void DramSim::send_request(uint64_t addr, bool is_write, ResponseCallback callback, void* arg, uint64_t byteen) {
  impl_->send_request(addr, is_write, callback, arg, byteen);
}