ROOT_DIR := $(VORTEX_HOME)

TARGET ?= opaesim

XRT_SYN_DIR ?= $(VORTEX_HOME)/hw/syn/xilinx/xrt
XRT_DEVICE_INDEX ?= 0

STARTUP_ADDR ?= 0x80000000

# Allow MARCH/MABI override for PNM evaluation (SW emulation configs)
ifeq ($(XLEN),64)
	ifeq ($(EXT_V_ENABLE),1)
		MARCH ?= rv64imafdv_zve64d
		MABI ?= lp64d
	else
		MARCH ?= rv64imafd
		MABI ?= lp64d
	endif
	POCL_CC_FLAGS += POCL_VORTEX_XLEN=64
else
	ifeq ($(EXT_V_ENABLE),1)
		MARCH ?= rv32imafv_zve32f
		MABI ?= ilp32f
	else
		MARCH ?= rv32imaf
		MABI ?= ilp32f
	endif
	POCL_CC_FLAGS += POCL_VORTEX_XLEN=32
endif
VX_CFLAGS += -march=$(MARCH) -mabi=$(MABI)

VORTEX_RT_PATH ?= $(ROOT_DIR)/runtime
VORTEX_KN_PATH ?= $(ROOT_DIR)/kernel
# GPU_and_PNM (Oct 28): soft-IDIV configs model hardware without an integer divider; link the runtime whose vx_spawn divides in
# software (vortex/kernel/softdiv, built with -DVX_SOFT_IDIV) instead of kernel/libvortex.a (hardware div/rem in vx_spawn).
ifneq (,$(findstring -DUSE_SOFT_IDIV,$(CONFIGS)))
VORTEX_KN_PATH := $(ROOT_DIR)/kernel/softdiv
endif

POCL_PATH ?= $(TOOLDIR)/pocl

LLVM_POCL ?= $(TOOLDIR)/llvm-vortex

VX_LIBS += -L$(LIBC_VORTEX)/lib -lm -lc

VX_LIBS += $(LIBCRT_VORTEX)/lib/baremetal/libclang_rt.builtins-riscv$(XLEN).a
#VX_LIBS += -lgcc

VX_CFLAGS  += -O3 -mcmodel=medany --sysroot=$(RISCV_SYSROOT) --gcc-toolchain=$(RISCV_TOOLCHAIN_PATH)
VX_CFLAGS  += -fno-rtti -fno-exceptions -nostartfiles -nostdlib -fdata-sections -ffunction-sections
VX_CFLAGS  += -I$(ROOT_DIR)/hw -I$(VORTEX_HOME)/kernel/include -DXLEN_$(XLEN) -DNDEBUG $(CONFIGS)
VX_CFLAGS  += -Xclang -target-feature -Xclang +vortex
VX_CFLAGS  += -Xclang -target-feature -Xclang +zicond
VX_CFLAGS  += -mllvm -disable-loop-idiom-all	# disable memset/memcpy loop replacement
#VX_CFLAGS += -mllvm -vortex-branch-divergence=0
#VX_CFLAGS += -mllvm -debug -mllvm -print-after-all

VX_LDFLAGS += -Wl,-Bstatic,--gc-sections,-T$(VORTEX_HOME)/kernel/scripts/link$(XLEN).ld,--defsym=STARTUP_ADDR=$(STARTUP_ADDR) $(VORTEX_KN_PATH)/libvortex.a $(VX_LIBS)

VX_BINTOOL += OBJCOPY=$(LLVM_VORTEX)/bin/llvm-objcopy $(VORTEX_HOME)/kernel/scripts/vxbin.py

CXXFLAGS += -std=c++17 -Wall -Wextra -Wfatal-errors
CXXFLAGS += -Wno-deprecated-declarations -Wno-unused-parameter -Wno-narrowing
CXXFLAGS += -pthread
CXXFLAGS += -I$(POCL_PATH)/include
CXXFLAGS += $(CONFIGS)

POCL_CC_FLAGS += LLVM_PREFIX=$(LLVM_VORTEX) POCL_VORTEX_BINTOOL="$(VX_BINTOOL)" POCL_VORTEX_CFLAGS="$(VX_CFLAGS)" POCL_VORTEX_LDFLAGS="$(VX_LDFLAGS)"

# Extract -D flags from CONFIGS so they can be passed to clBuildProgram() at runtime
KERNEL_DEFINES := $(filter -D%,$(CONFIGS))

# Debugging
ifdef DEBUG
	CXXFLAGS += -g -O0
	POCL_CC_FLAGS += POCL_DEBUG=all
else
	CXXFLAGS += -O2 -DNDEBUG
endif

LDFLAGS += -Wl,-rpath,$(LLVM_VORTEX)/lib

ifeq ($(TARGET), fpga)
	OPAE_DRV_PATHS ?= libopae-c.so
else
ifeq ($(TARGET), asesim)
	OPAE_DRV_PATHS ?= libopae-c-ase.so
else
ifeq ($(TARGET), opaesim)
	OPAE_DRV_PATHS ?= libopae-c-sim.so
endif
endif
endif

OBJS := $(addsuffix .o, $(notdir $(SRCS)))

all: $(PROJECT)

# Local file rules first (for benchmarks_modified local overrides)
%.cc.o: %.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.cpp.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.c.o: %.c
	$(CC) $(CXXFLAGS) -c $< -o $@

# Fallback to SRC_DIR (vortex source tree)
%.cc.o: $(SRC_DIR)/%.cc
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.cpp.o: $(SRC_DIR)/%.cpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

%.c.o: $(SRC_DIR)/%.c
	$(CC) $(CXXFLAGS) -c $< -o $@

$(PROJECT): $(OBJS)
	$(CXX) $(CXXFLAGS) $(OBJS) $(LDFLAGS) -L$(VORTEX_RT_PATH) -lvortex -L$(POCL_PATH)/lib -lOpenCL -o $@

$(PROJECT).host: $(OBJS)
	$(CXX) $(CXXFLAGS) $(OBJS) $(LDFLAGS) -lOpenCL -o $@

run-gpu: $(PROJECT).host $(KERNEL_SRCS)
	./$(PROJECT).host $(OPTS)

run-simx: $(PROJECT) $(KERNEL_SRCS)
	LD_LIBRARY_PATH=$(POCL_PATH)/lib:$(VORTEX_RT_PATH):$(ROOT_DIR)/build/runtime:$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=simx VORTEX_KERNEL_DEFINES="$(KERNEL_DEFINES)" ./$(PROJECT) $(OPTS)

run-rtlsim: $(PROJECT) $(KERNEL_SRCS)
	LD_LIBRARY_PATH=$(POCL_PATH)/lib:$(VORTEX_RT_PATH):$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=rtlsim VORTEX_KERNEL_DEFINES="$(KERNEL_DEFINES)" ./$(PROJECT) $(OPTS)

run-opae: $(PROJECT) $(KERNEL_SRCS)
	SCOPE_JSON_PATH=$(VORTEX_RT_PATH)/scope.json OPAE_DRV_PATHS=$(OPAE_DRV_PATHS) LD_LIBRARY_PATH=$(POCL_PATH)/lib:$(VORTEX_RT_PATH):$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=opae ./$(PROJECT) $(OPTS)

run-xrt: $(PROJECT) $(KERNEL_SRCS)
ifeq ($(TARGET), hw)
	SCOPE_JSON_PATH=$(FPGA_BIN_DIR)/scope.json XRT_INI_PATH=$(VORTEX_RT_PATH)/xrt/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_PATH)/lib:$(VORTEX_RT_PATH):$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
else ifeq ($(TARGET), hw_emu)
	SCOPE_JSON_PATH=$(FPGA_BIN_DIR)/scope.json XCL_EMULATION_MODE=$(TARGET) XRT_INI_PATH=$(VORTEX_RT_PATH)/xrt/xrt.ini EMCONFIG_PATH=$(FPGA_BIN_DIR) XRT_DEVICE_INDEX=$(XRT_DEVICE_INDEX) XRT_XCLBIN_PATH=$(FPGA_BIN_DIR)/vortex_afu.xclbin LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_PATH)/lib:$(VORTEX_RT_PATH):$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
else
	SCOPE_JSON_PATH=$(VORTEX_RT_PATH)/scope.json LD_LIBRARY_PATH=$(XILINX_XRT)/lib:$(POCL_PATH)/lib:$(VORTEX_RT_PATH):$(LLVM_VORTEX)/lib:$(LD_LIBRARY_PATH) $(POCL_CC_FLAGS) VORTEX_DRIVER=xrt ./$(PROJECT) $(OPTS)
endif

.depend: $(SRCS)
	$(CXX) $(CXXFLAGS) -MM $^ > .depend;

clean-kernel:
	rm -rf *.dump *.ll

clean-host:
	rm -rf $(PROJECT) $(PROJECT).host *.o *.log .depend

clean: clean-kernel clean-host

ifneq ($(MAKECMDGOALS),clean)
    -include .depend
endif
