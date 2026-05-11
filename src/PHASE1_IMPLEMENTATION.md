# NANO-VM Phase 1 - Implementation Guide

## Overview

Phase 1 establishes the foundational 16-bit emu8086 environment and implements the core fetch-decode-execute loop with graphics support. By the end of Phase 1, the IBM Logo ROM should render correctly on a VGA Mode 13h screen.

**Status**: Code complete, ready for testing in emu8086

---

## File Structure

```
phase1_main.asm          - Main program (.COM executable, ORG 100h)
phase1_makefile          - Build system for NASM (16-bit binary output)
PHASE1_IMPLEMENTATION.md - This document
```

---

## Memory Layout (64KB Segment)

| Address Range | Size   | Purpose |
|---|---|---|
| 0x0000-0x00FF | 256B | DOS PSP (Program Segment Prefix) |
| 0x0100        | (ORG) | Code & Data Start |
| 0x0100-0x1FFF | ~7.75KB | Code, ROM data, constants |
| 0x2000-0x204F | 80B | Font data (future use) |
| 0x2050-0x207F | 48B | Stack space |
| 0x2080-0x208F | 16B | Registers V0-VF |
| 0x2090-0x2097 | 8B | VM state (PC, SP, I, timers) |
| 0x2200-0x27FF | 1.5KB | Program RAM (ROM loaded here at offset 0x200) |
| 0x6000-0xFFFE | ~40KB | Host stack (grows down from 0xFFFE) |

**Critical Offset**: CHIP-8 VM address 0x0200 maps to physical address 0x2200 (0x2000 + 0x200).

---

## Segment Discipline

All code assumes a single-segment .COM structure:

- **CS (Code Segment)** = 0x0000 (implicit for .COM)
- **DS (Data Segment)** = 0x0000 (all RAM access via DS:offset)
- **ES (Extra Segment)** = 0xA000 (set during graphics operations for VGA access)
- **SS (Stack Segment)** = 0x0000 (stack in same segment as code/data)
- **SP (Stack Pointer)** = 0xFFFE (maximum value, grows downward)

---

## Key Implementation Details

### 1. The Big-Endian Fetch Cycle (Pillar A)

The `fetch_opcode` routine implements the mandatory byte-swap pattern:

```asm
fetch_opcode:
    mov si, [vm_pc]         ; Load PC
    add si, 0x2000          ; Add VM base offset
    lodsw                   ; AX = [SI], SI += 2 (little-endian load)
    xchg ah, al             ; **CRITICAL**: Swap for big-endian CHIP-8 format
    mov [last_opcode], ax   ; Cache for debugging
    add word [vm_pc], 0x0002; Increment PC
    ret
```

**Why**: CHIP-8 opcodes are stored big-endian (high byte first), but the 8086 loads little-endian (low byte first). The `xchg ah, al` swap corrects this immediately.

**Verification**: After fetch, AX contains the correctly aligned opcode ready for dispatch.

---

### 2. Jump Table Decoder (Pillar C)

The `decode_dispatch` routine maps opcode families (first nibble 0x0-0xF) to handlers:

```asm
decode_dispatch:
    mov cl, 12
    mov bx, ax
    shr bx, cl              ; Extract high nibble to BX
    
    cmp bx, 0x00
    je .op_0nnn_
    cmp bx, 0x01
    je .op_1nnn_
    ; ... 14 more comparisons ...
    cmp bx, 0x0F
    je .op_fnnn_
```

**Phase 1 Coverage**:
- **0x0-0x7**: Stub implementations (jump, call, register ops, etc.)
- **0x8-0xC**: Stub implementations
- **0xD**: `DXYN` - **CRITICAL** - Draw sprite opcode (fully implemented)
- **0xE-0xF**: Stub implementations

The `opcode_draw_sprite` routine extracts X, Y, N from the opcode and calls `draw_sprite_row` for each row.

---

### 3. VGA Mode 13h Graphics (Pillar B)

#### Initialization

```asm
init_vga_mode13h:
    mov al, 0x13            ; VGA Mode 13h (320×200, 8-bit)
    mov ah, 0x00            ; INT 10h function
    int 0x10
    call clear_vga_screen   ; Fill with black
    ret
```

#### Pixel Drawing

The `draw_4x4_block` routine draws a 4×4 white block at VGA coordinates:

```asm
draw_4x4_block:
    mov al, 0xFF            ; Color: white
    mov dh, 4               ; 4 rows
    ; Calculate VGA offset: (Y * 320) + X
    mov di, cx              ; DI = Y
    mov ax, cx
    mov dl, 40              ; Multiply by 320
    mul dl
    mov di, ax
    add di, bx              ; Add X
    ; Write 4 pixels across, 4 rows down
    mov dx, 4
.col_loop:
    mov byte [es:di], 0xFF
    inc di
    dec dx
    jnz .col_loop
```

#### Scaling Formula

- CHIP-8 pixel (CX, CY) → VGA block (CX*4, CY*4) to (CX*4+3, CY*4+3)
- Each CHIP-8 pixel becomes a 4×4 block in VGA space
- Final display: 256×128 pixels (center of 320×200 screen, black border)

---

## Phase 1 Test Case: IBM Logo

The ROM data in `phase1_main.asm` contains the classic IBM Logo sprite:

```asm
rom_data:
    db 0xF0, 0x90, 0x90, 0xF0      ; Row 0
    db 0x90, 0x90, 0x90, 0x90      ; Row 1
    db 0xF0, 0x10, 0xF0, 0x80      ; Row 2
    db 0xF0, 0x80, 0xF0, 0x10      ; Row 3
    db 0x10, 0xF0, 0x10, 0x10      ; Row 4
    db 0x10, 0x10, 0x10, 0x10      ; Row 5
    db 0xF0, 0x90, 0xF0, 0x90      ; Row 6
    db 0xF0, 0x90, 0x90, 0x90      ; Row 7
```

**Expected Behavior**:
1. Load ROM into 0x2200
2. Set PC to 0x200 (VM address)
3. Fetch opcode at 0x200 (maps to physical 0x2200)
4. Decode as CHIP-8 instruction
5. Execute (for Phase 1, only DXYN is fully implemented)
6. Render sprite on VGA screen
7. Loop forever

---

## Building and Testing

### Build

```bash
make -f phase1_makefile
```

Produces: `phase1_nano_vm.com` (~1KB executable)

### Run in emu8086

```bash
make -f phase1_makefile run
```

Or manually:

```bash
emu8086 phase1_nano_vm.com
```

### Expected Output

- VGA screen shows Mode 13h graphics (320×200)
- Black background with white IBM Logo sprite at top-left
- Logo remains displayed (infinite loop in .main_loop)

---

## Known Limitations & TODO

### Phase 1 (Current)

✓ **Complete**:
- .COM executable structure (ORG 100h)
- Memory layout & segment discipline
- VGA Mode 13h initialization
- ROM loading
- Fetch-decode-execute loop
- DXYN sprite drawing
- Graphics rendering

**Stubs** (logic present, not fully implemented):
- Jump instructions (1nnn, Bnnn)
- Register operations (6xkk, 7xkk, 8xy?)
- Conditional skips (3xkk, 4xkk, 5xy0, 9xy0)
- Keyboard input (mapping to CHIP-8 keys)
- Timers (decrement logic present, but not synchronized to 60 Hz)
- Sound (speaker output not implemented)

### Phase 2 (Planned)

- Implement all 16 opcode families
- Full register arithmetic (add, sub, AND, OR, XOR, etc.)
- Keyboard input with BIOS INT 16h
- 60 Hz timer synchronization via BIOS INT 0x08 (timer tick)
- Sound generator (simple beep via INT 0x1A or port 0x61)

### Phase 3 (Planned)

- Optimize graphics rendering (if needed)
- Add debugging utilities (memory viewer, register display)
- Test with real CHIP-8 ROMs (e.g., PONG, BREAKOUT)

---

## Debugging Tips

### Console Output

For debugging in emu8086, use INT 21h (DOS):

```asm
mov ah, 0x02            ; Print character
mov dl, 'A'             ; Character to print
int 0x21
```

However, emu8086 may clear the screen when switching to graphics mode. Use direct memory inspection instead.

### Memory Inspection

- Check `vm_pc` at 0x0100 (offset from segment base)
- Check `vm_registers` at 0x2080
- Check ROM at 0x2200-0x221F

### Register Inspection

The `last_opcode` variable at some offset in .data holds the most recently fetched opcode for post-mortem analysis.

---

## Next Steps

1. **Build and test in emu8086**
2. **Verify VGA Mode 13h initializes correctly**
3. **Check sprite rendering at top-left (0,0)**
4. **If working**: Proceed to Phase 2 (full opcode implementation)
5. **If issues**: Debug memory offsets, segment setup, or graphics write logic

---

## References

- **CHIP-8 Specification**: http://en.wikipedia.org/wiki/CHIP-8
- **VGA Mode 13h**: Standard 320×200 8-bit color graphics mode
- **emu8086 Documentation**: http://emu8086.com/
- **NASM Manual**: https://www.nasm.us/doc/

---

## Author Notes

This Phase 1 implementation prioritizes correctness over optimization. The jump table decoder is straightforward (linear comparisons) and could be optimized to a lookup table in Phase 2 if needed. Graphics rendering uses direct VRAM writes (fastest approach for 60 FPS requirement). All segment discipline follows real-mode DOS conventions to ensure compatibility.
