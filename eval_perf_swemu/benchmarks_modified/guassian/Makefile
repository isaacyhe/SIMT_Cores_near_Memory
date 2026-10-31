ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := guassian

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := $(SRC_DIR)/main.cc clutils.cpp $(SRC_DIR)/utils.cpp

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl

# usage: [-f <input_file>] [-s <size>]
OPTS ?= -q -s 32

include ../common.mk
