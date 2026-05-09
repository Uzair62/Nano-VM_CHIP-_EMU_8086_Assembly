# ============================================================================
# NANO-VM: Build System (Makefile)
#
# Usage:
#   make          - Build the nano-vm executable
#   make clean    - Remove all generated object files and binary
#   make run      - Build and run the emulator
#   make debug    - Build with debugging symbols and run under gdb
# ============================================================================

# Assembler and linker configuration
AS = nasm
ASFLAGS = -f elf64 -g

CC = gcc
LDFLAGS = -lc

# Target executable
TARGET = nano-vm

# Source files (assembly modules)
SOURCES = hardware.asm decoder.asm opcodes.asm graphics.asm main.asm
OBJECTS = $(SOURCES:.asm=.o)

# Default target
.PHONY: all
all: $(TARGET)

# Build the executable
$(TARGET): $(OBJECTS)
	$(CC) -o $@ $^ $(LDFLAGS)
	@echo "✓ Build complete: $(TARGET)"

# Assemble each source file
%.o: %.asm nano-vm.h
	$(AS) $(ASFLAGS) -o $@ $<
	@echo "✓ Assembled: $<"

# Run the emulator
.PHONY: run
run: $(TARGET)
	@echo "Running $(TARGET)..."
	./$(TARGET)

# Run under debugger
.PHONY: debug
debug: $(TARGET)
	@echo "Launching gdb..."
	gdb ./$(TARGET)

# Clean build artifacts
.PHONY: clean
clean:
	rm -f $(OBJECTS) $(TARGET)
	@echo "✓ Cleaned build artifacts"

# Disassemble the binary (useful for verification)
.PHONY: disasm
disasm: $(TARGET)
	objdump -d $(TARGET) | less

# Show memory layout
.PHONY: layout
layout: $(TARGET)
	objdump -h $(TARGET) | grep -E "(Section|\.bss|\.data|\.text)"

# Help target
.PHONY: help
help:
	@echo "Nano-VM Build System"
	@echo ""
	@echo "Targets:"
	@echo "  make          - Build nano-vm executable"
	@echo "  make run      - Build and run"
	@echo "  make debug    - Build with debug symbols and launch gdb"
	@echo "  make clean    - Remove generated files"
	@echo "  make disasm   - Disassemble binary"
	@echo "  make layout   - Show memory layout"
	@echo "  make help     - Show this help message"

.PHONY: .PRECIOUS
.PRECIOUS: $(OBJECTS)
