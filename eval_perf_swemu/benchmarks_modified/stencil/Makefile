ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := stencil

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := main.cc $(SRC_DIR)/args.c $(SRC_DIR)/parboil_opencl.c $(SRC_DIR)/ocl.c $(SRC_DIR)/gpu_info.c $(SRC_DIR)/file.c

CXXFLAGS += -I$(SRC_DIR)

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl

# Usage: #nx #ny #nz #iter -i input_file [-o output_file]
OPTS ?= 32 32 8 1 -i $(SRC_DIR)/32x32x8.bin

include ../common.mk
