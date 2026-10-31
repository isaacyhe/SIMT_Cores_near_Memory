ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := nw

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := $(SRC_DIR)/main.cc

kernel.cl: $(SRC_DIR)/kernel.cl
	cp $< $@

KERNEL_SRCS := kernel.cl

OPTS ?= -n128 -p2

include ../common.mk
