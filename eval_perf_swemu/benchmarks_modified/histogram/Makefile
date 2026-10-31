ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := histogram

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := main.cc

common.h: $(SRC_DIR)/common.h
	cp $< $@

# kernel.cl and main.cc are locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl common.h soft_math_cl.h

OPTS ?= -n1024

include ../common.mk
