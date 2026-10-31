ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := spmv

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := main.cc $(SRC_DIR)/parboil_opencl.c $(SRC_DIR)/args.c $(SRC_DIR)/gpu_info.c $(SRC_DIR)/file.c $(SRC_DIR)/convert_dataset.c $(SRC_DIR)/mmio.c $(SRC_DIR)/ocl.c

CXXFLAGS += -I$(SRC_DIR)

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl

# Usage: -i matrix_file,vector_file [-o output_file]
OPTS ?= -i $(SRC_DIR)/1138_bus.mtx,$(SRC_DIR)/1138_bus.vec

include ../common.mk
