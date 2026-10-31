ROOT_DIR := $(VORTEX_HOME)
include $(VORTEX_HOME)/config.mk

PROJECT := blackscholes

SRC_DIR := $(VORTEX_HOME)/tests/opencl/$(PROJECT)

SRCS := $(SRC_DIR)/main.cc $(SRC_DIR)/oclUtils.cpp $(SRC_DIR)/shrUtils.cpp $(SRC_DIR)/cmd_arg_reader.cpp oclBlackScholes_launcher.cpp $(SRC_DIR)/oclBlackScholes_gold.cpp

CXXFLAGS += -I$(SRC_DIR)

# kernel.cl is locally modified (soft math macros) - do NOT copy from SRC_DIR
KERNEL_SRCS := kernel.cl

OPTS ?=

include ../common.mk
