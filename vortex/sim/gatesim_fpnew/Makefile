# ============================================================================
# gatesim_fpnew (calibration, Oct 31): gate-level activity sim of a routed fpnew layout for the core-switching calibration.
# Harness = sim/rtlsim (energy build) processor.cpp/main.cpp/rtlsim_shim.sv with the GATESIM additions in processor.cpp;
# the DUT `Vortex` is the wrapper Vortex.sv over the routed netlist (Vortex_gl.v = 6_final.v with the top renamed) plus
# behavioural ASAP7 cells (gen_cells.v from the liberty functions) and functional FakeRAM models (fakeram7_be.v).
# GL_DIR holds the per-layout Vortex_gl.v and gen_cells.v. CONFIGS must equal the energy row's rtlsim_configs.
# Produces trace.vcd (window from VX_TRACE_START / VX_TRACE_STOP) whose net names match 6_final.odb for OpenSTA read_vcd.
# ============================================================================
include ../common.mk

DESTDIR ?= $(CURDIR)
CONFIG_FILE = $(DESTDIR)/gatesim_config.stamp
SRC_DIR = $(VORTEX_HOME)/sim/gatesim_fpnew
GL_DIR ?= $(error GL_DIR (directory with Vortex_gl.v and gen_cells.v) is required)

CXXFLAGS += -std=c++17 -Wall -Wextra -Wfatal-errors -Wno-array-bounds
CXXFLAGS += -fPIC -Wno-maybe-uninitialized
CXXFLAGS += -I$(ROOT_DIR)/hw -I$(SW_COMMON_DIR)
CXXFLAGS += -I$(THIRD_PARTY_DIR)/softfloat/source/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/spdlog/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/ext/yaml-cpp/include
CXXFLAGS += -I$(THIRD_PARTY_DIR)/ramulator/src
CXXFLAGS += -I$(DPI_DIR)
CXXFLAGS += -DXLEN_$(XLEN)
CXXFLAGS += $(CONFIGS)

LDFLAGS += $(THIRD_PARTY_DIR)/softfloat/build/Linux-x86_64-GCC/softfloat.a
LDFLAGS += -Wl,-rpath,$(THIRD_PARTY_DIR)/ramulator -L$(THIRD_PARTY_DIR)/ramulator -lramulator

# packages the shim and wrapper need (the DUT itself comes from the netlist)
RTL_PKGS  = $(RTL_DIR)/VX_gpu_pkg.sv $(RTL_DIR)/fpu/VX_fpu_pkg.sv
ifneq (,$(findstring -DFPU_FPNEW, $(CONFIGS)))
	RTL_PKGS += $(THIRD_PARTY_DIR)/cvfpu/src/fpnew_pkg.sv $(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src/cf_math_pkg.sv
endif
RTL_PKGS += $(RTL_DIR)/VX_trace_pkg.sv

# -I SRC_DIR first so the wrapper Vortex.sv shadows hw/rtl/Vortex.sv
RTL_INCLUDE  = -I$(SRC_DIR) -I$(RTL_DIR) -I$(DPI_DIR) -I$(RTL_DIR)/libs
RTL_INCLUDE += -I$(RTL_DIR)/interfaces -I$(RTL_DIR)/core -I$(RTL_DIR)/mem -I$(RTL_DIR)/cache -I$(RTL_DIR)/fpu
RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/include -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src -I$(THIRD_PARTY_DIR)/cvfpu/src

GATE_SRCS  = $(SRC_DIR)/Vortex.sv $(GL_DIR)/Vortex_gl.v $(GL_DIR)/gen_cells.v
GATE_SRCS += $(SRC_DIR)/dff.v $(SRC_DIR)/empty.v $(SRC_DIR)/fakeram7_be.v

SRCS  = $(SW_COMMON_DIR)/util.cpp $(SW_COMMON_DIR)/mem.cpp $(SW_COMMON_DIR)/softfloat_ext.cpp
SRCS += $(SW_COMMON_DIR)/rvfloats.cpp $(SW_COMMON_DIR)/dram_sim.cpp
SRCS += $(DPI_DIR)/util_dpi.cpp $(DPI_DIR)/float_dpi.cpp $(DPI_DIR)/ctr_dpi.cpp
SRCS += $(SRC_DIR)/processor.cpp

TOP = rtlsim_shim

VL_FLAGS  = --exe
VL_FLAGS += --language 1800-2009 --assert
VL_FLAGS += -Wno-fatal                      # gate netlist + cells are machine-generated
VL_FLAGS += -Wno-DECLFILENAME -Wno-REDEFMACRO -Wno-TIMESCALEMOD -Wno-MULTITOP
VL_FLAGS += --x-initial 0 --x-assign 0      # = the energy build's -DVERILATOR_RESET_VALUE=0 zero-init
VL_FLAGS += $(SRC_DIR)/verilator.vlt
VL_FLAGS += -DSIMULATION -DSV_DPI -DXLEN_$(XLEN)
VL_FLAGS += $(CONFIGS)
VL_FLAGS += $(RTL_INCLUDE)
VL_FLAGS += $(RTL_PKGS)
VL_FLAGS += $(GATE_SRCS)
VL_FLAGS += -DNDEBUG                      # as the energy RTL build (non-debug)
VL_FLAGS += --cc $(TOP) --top-module $(TOP)

# VCD always compiled in; dumping only inside the run-time window
VL_FLAGS += --trace --trace-underscore -DVCD_OUTPUT --trace-max-array 1048576
CXXFLAGS += -O1 -DVCD_OUTPUT -DNDEBUG

THREADS ?= $(shell python3 -c 'import multiprocessing as mp; print(mp.cpu_count())')
VL_FLAGS += -j $(THREADS)

ifdef PERF
	VL_FLAGS += -DPERF_ENABLE
	CXXFLAGS += -DPERF_ENABLE
endif

.PHONY: lib force clean
lib: $(DESTDIR)/librtlsim.so
$(DESTDIR)/librtlsim.so: $(SRCS) $(CONFIG_FILE) $(GATE_SRCS)
	verilator --build $(VL_FLAGS) $(SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '-shared $(LDFLAGS)' --MMD --Mdir $@.obj_dir -o $@

$(CONFIG_FILE): force
	@mkdir -p $(@D)
	@printf '%s\n' "$(VL_FLAGS)" > $@.tmp
	@if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else rm $@.tmp; fi

clean:
	rm -rf $(DESTDIR)/librtlsim.so.obj_dir $(DESTDIR)/librtlsim.so
