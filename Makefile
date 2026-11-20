# Build the serial baseline, the MPI + OpenMP implementation, and the graph generator.
# Binaries go to build/ so the repository root stays clean.

CC ?= gcc
MPICC ?= mpicc
CFLAGS ?= -O3 -std=gnu11
OMPFLAGS ?= -fopenmp -march=native -mtune=native -ftree-vectorize -funroll-loops -flto
BUILD_DIR ?= build

TARGETS := $(BUILD_DIR)/serial $(BUILD_DIR)/parallel $(BUILD_DIR)/graph_generator

.PHONY: all clean plot

all: $(TARGETS)

$(BUILD_DIR):
	mkdir -p $@

$(BUILD_DIR)/serial: serial.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $< -o $@

$(BUILD_DIR)/parallel: src/main.c | $(BUILD_DIR)
	$(MPICC) $(CFLAGS) $(OMPFLAGS) $< -o $@

$(BUILD_DIR)/graph_generator: graph_generator.c | $(BUILD_DIR)
	$(CC) $(CFLAGS) $(OMPFLAGS) $< -o $@

plot:
	python3 scripts/plot_results.py

clean:
	rm -rf $(BUILD_DIR)
