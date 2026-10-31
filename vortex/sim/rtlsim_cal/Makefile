include ../common.mk

DESTDIR ?= $(CURDIR)

CONFIG_FILE = $(DESTDIR)/rtlsim_config.stamp
# rtlsim_cal (Oct 31): sim/rtlsim/Makefile with SRC_DIR here; harness = gatesim_fpnew/processor.cpp (run-time trace-window snapshots, no VCD without VCD_OUTPUT)
SRC_DIR = $(VORTEX_HOME)/sim/rtlsim_cal

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
LDFLAGS += -Wl,-rpath,$(THIRD_PARTY_DIR)/ramulator  -L$(THIRD_PARTY_DIR)/ramulator -lramulator

# control RTL debug tracing states
DBG_TRACE_FLAGS += -DDBG_TRACE_PIPELINE
DBG_TRACE_FLAGS += -DDBG_TRACE_MEM
DBG_TRACE_FLAGS += -DDBG_TRACE_CACHE
DBG_TRACE_FLAGS += -DDBG_TRACE_AFU
DBG_TRACE_FLAGS += -DDBG_TRACE_SCOPE
DBG_TRACE_FLAGS += -DDBG_TRACE_GBAR
DBG_TRACE_FLAGS += -DDBG_TRACE_TCU

DBG_FLAGS += -DDEBUG_LEVEL=$(DEBUG) -DVCD_OUTPUT $(DBG_TRACE_FLAGS)

RTL_PKGS = $(RTL_DIR)/VX_gpu_pkg.sv $(RTL_DIR)/fpu/VX_fpu_pkg.sv

FPU_INCLUDE = -I$(RTL_DIR)/fpu
ifneq (,$(findstring -DFPU_FPNEW, $(CONFIGS)))
	# fpu_div_sqrt_mvp/hdl/*.sv are passed explicitly (as upstream Vortex does) so the file-scope
	# `import defs_div_sqrt_mvp::*;` in control_mvp.sv resolves; Verilator parses -I/-y-discovered files in a separate scope.
	RTL_PKGS += $(THIRD_PARTY_DIR)/cvfpu/src/fpnew_pkg.sv $(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src/cf_math_pkg.sv $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/defs_div_sqrt_mvp.sv \
	            $(addprefix $(THIRD_PARTY_DIR)/cvfpu/src/fpu_div_sqrt_mvp/hdl/,control_mvp.sv iteration_div_sqrt_mvp.sv norm_div_sqrt_mvp.sv nrbd_nrsc_mvp.sv preprocess_mvp.sv div_sqrt_top_mvp.sv div_sqrt_mvp_wrapper.sv)
	FPU_INCLUDE += -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/include -I$(THIRD_PARTY_DIR)/cvfpu/src/common_cells/src -I$(THIRD_PARTY_DIR)/cvfpu/src
	# T-Head FP32 div/sqrt (default divider, see VX_fpu_fpnew.sv); file names match module names
	FPU_INCLUDE += $(addprefix -I$(THIRD_PARTY_DIR)/cvfpu/vendor/opene906/E906_RTL_FACTORY/gen_rtl/,fdsu/rtl fpu/rtl clk/rtl)
endif
RTL_INCLUDE = -I$(SRC_DIR) -I$(RTL_DIR) -I$(DPI_DIR) -I$(RTL_DIR)/libs -I$(RTL_DIR)/interfaces -I$(RTL_DIR)/core -I$(RTL_DIR)/mem -I$(RTL_DIR)/cache $(FPU_INCLUDE)

# Add V extension sources
ifneq (,$(findstring -DEXT_V_ENABLE, $(CONFIGS)))
	RTL_PKGS += $(RTL_DIR)/vpu/VX_vpu_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/vpu
endif

# Add TCU extension sources
ifneq (,$(findstring -DEXT_TCU_ENABLE, $(CONFIGS)))
	RTL_PKGS += $(RTL_DIR)/tcu/VX_tcu_pkg.sv
	RTL_INCLUDE += -I$(RTL_DIR)/tcu
	RTL_INCLUDE += -I$(RTL_DIR)/tcu/bhf
	RTL_INCLUDE += -I$(THIRD_PARTY_DIR)/hardfloat/source/RISCV
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/fNToRecFN.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/addRecFN.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/bsg_hardfloat_pkg.sv
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/HardFloat_primitives.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/HardFloat_rawFN.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/isSigNaNRecFN.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/mulRecFN.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/recFNToFN.v
	RTL_PKGS += $(THIRD_PARTY_DIR)/hardfloat/source/recFNToRecFN.v
endif

RTL_PKGS += $(RTL_DIR)/VX_trace_pkg.sv

SRCS = $(SW_COMMON_DIR)/util.cpp $(SW_COMMON_DIR)/mem.cpp $(SW_COMMON_DIR)/softfloat_ext.cpp $(SW_COMMON_DIR)/rvfloats.cpp $(SW_COMMON_DIR)/dram_sim.cpp
SRCS += $(DPI_DIR)/util_dpi.cpp $(DPI_DIR)/float_dpi.cpp
SRCS += $(DPI_DIR)/ctr_dpi.cpp  # GPU_and_PNM: sim-only activity counters (VX_sim_ctrs.sv)
SRCS += $(SRC_DIR)/processor.cpp

TOP = rtlsim_shim

VL_FLAGS = --exe
VL_FLAGS += --language 1800-2009 --assert -Wall -Wpedantic
VL_FLAGS += -Wno-DECLFILENAME -Wno-REDEFMACRO
VL_FLAGS += --x-initial unique --x-assign unique
# GPU_and_PNM (CAL energy, Oct 26): with -DVERILATOR_RESET_VALUE=0 in CONFIGS (set by the energy runs only), initial values are 0
# (processor.cpp randReset) and so are explicit X assignments (--x-assign 0; the later flag wins). Seeded random values otherwise
# reach the data buses (never-written GPRs, inactive lanes, 'x don't-cares) and move the data-bus flip counters by up to 85%
# with the seed or with any RTL edit; cycles are unaffected (checked on 8 workloads).
# How explicit X assignments become 0 depends on the Verilator version (Oct 27):
#  - 5.032 (local host): --x-assign unique draws a runtime random value per assignment (VL_RAND_RESET_ASSIGN ignores randReset),
#    so --x-assign 0 is added.
#  - 5.020 (cloud artifact container): unique X values are set once at construction by VL_RAND_RESET_*, which randReset(0) makes
#    0 (no runtime random calls in the generated code); --x-assign 0 and --x-assign fast make that build's 16t_8w model
#    segfault, so the flag is not added. Same result on both: every X is 0.
#  - any other version: refused until its X handling is checked.
ifneq (,$(findstring -DVERILATOR_RESET_VALUE=0,$(CONFIGS)))
VL_VERSION := $(shell verilator --version 2>/dev/null | awk '{print $$2}')
ifeq ($(VL_VERSION),5.032)
VL_FLAGS += --x-assign 0
else ifeq ($(VL_VERSION),5.020)
else
$(error zero-init energy build: Verilator $(VL_VERSION) not validated (X handling checked for 5.020 and 5.032 only))
endif
endif
VL_FLAGS += verilator.vlt
VL_FLAGS += -DSIMULATION -DSV_DPI
VL_FLAGS += -DXLEN_$(XLEN)
VL_FLAGS += $(CONFIGS)
VL_FLAGS += $(RTL_INCLUDE)
VL_FLAGS += $(RTL_PKGS)
VL_FLAGS += --cc $(TOP) --top-module $(TOP)

# Extract RTL directories from include directories
RTL_DIRS := $(patsubst -I%,%,$(filter -I%,$(RTL_INCLUDE)))

# Discover RTL source files from source directories
RTL_SRCS := $(shell find $(RTL_DIRS) -type f \( -name '*.v' -o -name '*.vh' -o -name '*.sv' -o -name '*.vi' \))

# Enable Verilator multithreaded simulation
# GPU_and_PNM (Oct 27): at most 16 Verilator/make threads. On 192-CPU cloud nodes, -j 192 made Verilator 5.020 abort with
# "Internal Error: attempted to destroy locked Thread Pool" (both attempts of one build); the local host has 16 CPUs.
# The thread count does not change Verilator's output.
THREADS ?= $(shell python3 -c 'import multiprocessing as mp; print(min(16, mp.cpu_count()))')
VL_FLAGS += -j $(THREADS)
#VL_FLAGS += --threads $(THREADS)

# Debugging
ifdef DEBUG
	VL_FLAGS += --trace --trace-structs --trace-underscore --trace-max-array 1048576 $(DBG_FLAGS)
	CXXFLAGS += -g -O0 $(DBG_FLAGS)
else
	VL_FLAGS += -DNDEBUG
	CXXFLAGS += -O2 -DNDEBUG
endif

# Enable perf counters
ifdef PERF
	VL_FLAGS += -DPERF_ENABLE
	CXXFLAGS += -DPERF_ENABLE
endif

PROJECT := rtlsim

.PHONY: all force clean clean-lib clean-exe

all: $(DESTDIR)/$(PROJECT)

$(DESTDIR)/$(PROJECT): $(SRCS) $(SRC_DIR)/main.cpp $(CONFIG_FILE) $(RTL_SRCS)
	verilator --build $(VL_FLAGS) $(SRCS) $(SRC_DIR)/main.cpp -CFLAGS '$(CXXFLAGS) -DSTARTUP_ADDR=0x80000000' -LDFLAGS '$(LDFLAGS)' --MMD --Mdir $@.obj_dir -o $@

$(DESTDIR)/lib$(PROJECT).so: $(SRCS) $(CONFIG_FILE) $(RTL_SRCS)
	verilator --build $(VL_FLAGS) $(SRCS) -CFLAGS '$(CXXFLAGS)' -LDFLAGS '-shared $(LDFLAGS)' --MMD --Mdir $@.obj_dir -o $@

# updates the timestamp when flags changed.
$(CONFIG_FILE): force
	@mkdir -p $(@D)
	@printf '%s\n' "$(VL_FLAGS)" > $@.tmp
	@if ! cmp -s $@.tmp $@; then \
	  mv $@.tmp $@; \
	else \
	  rm $@.tmp; \
	fi

clean-lib:
	rm -rf $(DESTDIR)/lib$(PROJECT).so.obj_dir
	rm -f $(DESTDIR)/lib$(PROJECT).so

clean-exe:
	rm -rf $(DESTDIR)/$(PROJECT).obj_dir
	rm -f $(DESTDIR)/$(PROJECT)

clean: clean-lib clean-exe