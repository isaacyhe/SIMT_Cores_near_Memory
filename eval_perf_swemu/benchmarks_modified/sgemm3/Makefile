ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := sgemm3

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := main.cc

common.h: $(SRC_DIR)/common.h
	cp $< $@

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl common.h

OPTS ?= -n16

include ../common.mk