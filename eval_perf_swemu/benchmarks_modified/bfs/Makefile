ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := bfs

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := main.cc

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl

OPTS ?= $(SRC_DIR)/graph4k.txt

include ../common.mk
