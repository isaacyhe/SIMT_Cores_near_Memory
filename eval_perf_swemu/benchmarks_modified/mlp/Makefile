ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := mlp

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := $(SRC_DIR)/main.cc

kernel.cl: $(SRC_DIR)/kernel.cl
	cp $< $@

KERNEL_SRCS := kernel.cl

OPTS ?= -n256 -m128 -l2

include ../common.mk
