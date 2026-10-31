ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := kmeans

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := main.cc $(SRC_DIR)/read_input.c $(SRC_DIR)/rmse.c $(SRC_DIR)/kmeans_clustering.c $(SRC_DIR)/cluster.c $(SRC_DIR)/getopt.c

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl

# usage: -f<features> -p<points>
OPTS ?= -f100 -p100

include ../common.mk
