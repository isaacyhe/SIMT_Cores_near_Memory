ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := gather

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := $(SRC_DIR)/main.cc

common.h: $(SRC_DIR)/common.h
	cp $< $@

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl common.h

OPTS ?= -n1024

include ../common.mk
