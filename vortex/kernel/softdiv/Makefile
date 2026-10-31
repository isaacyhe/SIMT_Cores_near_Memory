# Soft-IDIV runtime library (GPU_and_PNM, Oct 28): the CAL soft-IDIV configs (no_intdiv, no_numeric, combined_pnm, combined_pnm_lmem)
# model hardware without an integer divider, so the kernel runtime must not execute div/rem. Same sources, compiler and flags as
# ../Makefile plus -DVX_SOFT_IDIV (vx_spawn.c: software division through VX_UDIV/VX_UMOD). Output: kernel/softdiv/libvortex.a,
# linked instead of kernel/libvortex.a when CONFIGS contains -DUSE_SOFT_IDIV (eval_perf_swemu/benchmarks_modified/common.mk).
# Build: make -C vortex/kernel/softdiv VORTEX_HOME=<repo>/vortex TOOLDIR=<repo>/toolchain
ROOT_DIR := $(realpath ../..)
include $(ROOT_DIR)/config.mk

ifeq ($(XLEN),64)
CFLAGS += -march=rv64imafd -mabi=lp64d
else
CFLAGS += -march=rv32imaf -mabi=ilp32f
endif

INC_DIR := $(VORTEX_HOME)/kernel/include
SRC_DIR := $(VORTEX_HOME)/kernel/src

CC  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc
AR  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-gcc-ar
DP  = $(RISCV_TOOLCHAIN_PATH)/bin/$(RISCV_PREFIX)-objdump

CFLAGS += -O3 -mcmodel=medany -fno-exceptions -fdata-sections -ffunction-sections
CFLAGS += -I$(INC_DIR) -I$(ROOT_DIR)/hw
CFLAGS += -DXLEN_$(XLEN)
CFLAGS += -DVX_SOFT_IDIV

PROJECT := libvortex

SRCS = $(SRC_DIR)/vx_start.S $(SRC_DIR)/vx_syscalls.c $(SRC_DIR)/vx_print.S $(SRC_DIR)/tinyprintf.c $(SRC_DIR)/vx_print.c $(SRC_DIR)/vx_spawn.c $(SRC_DIR)/vx_serial.S $(SRC_DIR)/vx_perf.c

OBJS = $(addsuffix .o, $(notdir $(SRCS)))

all: $(PROJECT).a $(PROJECT).dump

$(PROJECT).dump: $(PROJECT).a
	$(DP) -D $(PROJECT).a > $(PROJECT).dump

%.S.o: $(SRC_DIR)/%.S
	$(CC) $(CFLAGS) -c $< -o $@

%.c.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

$(PROJECT).a: $(OBJS)
	$(AR) rcs $@ $^

clean:
	rm -rf *.a *.o *.dump
