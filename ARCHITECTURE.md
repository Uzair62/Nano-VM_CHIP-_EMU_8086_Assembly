# NANO-VM Architecture Guide

A comprehensive technical reference for developers and maintainers of the NANO-VM CHIP-8 emulator.

---

## Table of Contents

1. [Overview](#overview)
2. [Memory Architecture](#memory-architecture)
3. [Register Convention](#register-convention)
4. [The Fetch-Decode-Execute Cycle](#the-fetch-decode-execute-cycle)
5. [Interrupt Reference](#interrupt-reference)
6. [Graphics Pipeline](#graphics-pipeline)
7. [Sound System](#sound-system)
8. [Opcode Dispatch](#opcode-dispatch)

---

## Overview

NANO-VM is a single-segment DOS `.COM` executable that emulates a complete CHIP-8 virtual machine. The architecture is designed around three core pillars:

1. **Big-Endian Fetch Cycle** - Converting CHIP-8 big-endian opcodes to 8086 little-endian execution
2. **VGA Graphics** - Hardware-accelerated Mode 13h rendering with intelligent pixel scaling
3. **Segment Discipline** - Explicit memory management with zero overflow risk

---

## Memory Architecture

### 64KB Segment Layout

```
┌──────────────────────────────────────────────────────┐
│ Segment: 0x0000 (Data Segment)                      │
├──────────────────────────────────────────────────────┤
│ 0x0000 - 0x01FF (512 bytes)                         │
│ Interrupt Vectors & BIOS Data Area                  │
├──────────────────────────────────────────────────────┤
│ 0x0200 - 0x0FFF (3.75 KB)                           │
│ CHIP-8 Program ROM (loaded from disk via INT 21h)  │
├──────────────────────────────────────────────────────┤
│ 0x1000 - 0x1FFF (4 KB)                              │
│ CHIP-8 RAM (program runtime memory)                 │
├──────────────────────────────────────────────────────┤
│ 0x2000 - 0x2FFF (4 KB)                              │
│ VM Registers, Stacks, Work Area                     │
│  - V0-VF: CHIP-8 registers (16 bytes)              │
│  - I: Index register (2 bytes)                      │
│  - DT: Delay timer (1 byte)                         │
│  - ST: Sound timer (1 byte)                         │
│  - Stack: Call stack (256 bytes)                    │
├──────────────────────────────────────────────────────┤
│ 0x3000 - 0xFFFE (52 KB)                             │
│ Host Stack & Safety Buffer                          │
│ (Prevents overflow into program ROM)                │
├──────────────────────────────────────────────────────┤
│ 0xFFFF                                               │
│ Upper limit of segment                              │
└──────────────────────────────────────────────────────┘
```

### Critical Addresses

| Address | Size | Purpose | Access |
|---------|------|---------|--------|
| 0x0200  | 4KB  | CHIP-8 ROM | Read-Only (after load) |
| 0x1000  | 4KB  | CHIP-8 RAM | Read-Write |
| 0x2000  | 16 bytes | V0-VF Registers | Read-Write |
| 0x2010  | 2 bytes | I Register | Read-Write |
| 0x2012  | 1 byte | DT (Delay Timer) | Read-Write |
| 0x2013  | 1 byte | ST (Sound Timer) | Read-Write |
| 0x2014  | 256 bytes | Call Stack | Read-Write |
| 0x2114  | 4KB | Program Stack | Read-Write |

---

## Register Convention

### 8086 General-Purpose Registers

```
AX / AH / AL:  Arithmetic operations, opcode decoding
BX:            Loop counters, address calculations
CX:            Loop counters, bit shifts
DX:            I/O operations, audio frequency
SI:            Instruction pointer, bytecode fetch
DI:            Work register, temporary values
BP:            Frame pointer (optional)
SP:            Stack pointer (maintained by CPU)
```

### Segment Registers

```
CS:  Code Segment   = 0x0000 (always)
DS:  Data Segment   = 0x0000 (main memory)
ES:  Extra Segment  = 0xA000 (VGA video RAM)
SS:  Stack Segment  = 0x0000 (same as data)
```

### CHIP-8 Register Storage

All 16 CHIP-8 registers (V0-VF) are stored in memory at `0x2000 - 0x200F`:

```assembly
V0 at 0x2000
V1 at 0x2001
V2 at 0x2002
...
VF at 0x200F
```

**Why in memory?**
- The 8086 only has 4 general-purpose registers (AX, BX, CX, DX)
- Keeping CHIP-8 registers in RAM avoids constant register shuffling
- Allows atomic access to V[F] (carry/borrow flag) without register conflicts

---

## The Fetch-Decode-Execute Cycle

### Conceptual Flow

```
┌─────────────────┐
│     START       │
└────────┬────────┘
         │
    ┌────▼─────┐
    │  FETCH   │  Load 2-byte opcode from program
    │          │  Address: (SI) in ROM (0x0200-0x0FFF)
    └────┬─────┘
         │
    ┌────▼──────────┐
    │   CONVERT     │  CHIP-8: big-endian [0xAB][0xCD]
    │   BYTE ORDER  │  8086:   little-endian, need [0xCD][0xAB]
    │               │  Solution: lodsw + xchg ah,al
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │   DECODE      │  Extract opcode family (0xN___)
    │   & EXTRACT   │  Extract X, Y, N, KK parameters
    │               │  Build address for jump table
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ JUMP TABLE    │  Dispatch to correct handler
    │ DISPATCH      │  (16 families = 16 jump table entries)
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │   EXECUTE     │  Run the specific opcode handler
    │   OPCODE      │  May take 4-16 CPU cycles
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ CHECK TIMERS  │  Decrement DT, ST if > 0
    │ & SYNC        │  Check 60Hz BIOS tick
    └────┬──────────┘
         │
    └─────┴──────────────┐
                         │
                    ┌────▼─────┐
                    │    END    │
                    │   LOOP    │
                    └──────────┘
```

### Implementation Pattern

```assembly
; --- FETCH CYCLE ---
lodsw                    ; Load word at [DS:SI] into AX, SI += 2
xchg ah, al              ; Swap bytes: AX = 0xCDAB (big-endian fixed)

; --- DECODE CYCLE ---
mov bx, ax               ; BX = opcode for comparison
and al, 0x0F             ; AL = Y (second nibble)
shr bh, 4                ; BH = X (first nibble)
shr ax, 8                ; AH = opcode family (0x8 for 0x8XY0)

; --- DISPATCH CYCLE ---
cmp ah, 0x8              ; Is it 0x8XY_?
je handle_8xy_family     ; Jump to handler

; --- CONTINUE LOOP ---
jmp fetch_cycle          ; Back to start
```

---

## Interrupt Reference

### INT 0x10 - VGA Graphics

Used for Mode 13h initialization:

```assembly
mov al, 0x13             ; Mode 13h (320x200, 8-bit color)
xor ah, ah               ; Function 0 (set mode)
int 0x10                 ; Invoke interrupt
```

**Mode 13h Details:**
- Resolution: 320 × 200 pixels
- Colors: 256 indexed (0-255)
- VRAM Address: 0xA000:0x0000
- VRAM Size: 64KB (320 × 200 bytes)
- Palette: Standard VGA 256-color

### INT 0x16 - Keyboard Input

Polling-based keyboard input for CHIP-8 hexpad:

```assembly
mov ah, 0x01             ; Function: check buffer
int 0x16                 ; Query keyboard
jz no_key                ; If ZF clear, key available

mov ah, 0x00             ; Function: get character
int 0x16                 ; Block until key press
; AL now contains ASCII code
```

**CHIP-8 Hexpad Mapping (QWERTY):**
```
CHIP-8:  1 2 3 C      8086 Key: 1 2 3 4
         4 5 6 D                 Q W E R
         7 8 9 E                 A S D F
         A 0 B F                 Z X C V
```

### INT 0x21 - Disk I/O (DOS)

File operations for ROM loading:

```assembly
; --- OPEN FILE ---
mov ax, 0x3D00           ; Function: open file
mov dx, filename_offset  ; DS:DX = "GAME.CH8"
int 0x21
mov file_handle, ax      ; Save file handle

; --- READ FILE ---
mov ah, 0x3F             ; Function: read file
mov bx, file_handle      ; Handle from above
mov cx, 0x1000           ; Read up to 4KB
mov dx, 0x0200           ; DS:DX = ROM destination (0x0200)
int 0x21
mov bytes_read, ax       ; AX = bytes actually read

; --- CLOSE FILE ---
mov ah, 0x3E             ; Function: close file
mov bx, file_handle
int 0x21
```

### INT 0x08 - System Timer (Interrupt Handler)

Invoked every ~55ms (18.2 Hz nominal on DOS):

```assembly
; --- BIOS TIMER TICK ---
; Read from 0x0040:0x006C (BIOS timer low word)
mov ax, 0x0040
mov ds, ax
mov ax, [0x006C]         ; Load current tick count
cmp ax, [last_tick]      ; Compare with previous
jne timer_tick           ; If changed, 1/18.2 second elapsed

; Update delay timers at 60Hz
; (3 BIOS ticks ≈ 1 CHIP-8 frame)
```

---

## Graphics Pipeline

### VGA Mode 13h Rendering

```
CHIP-8 Display: 64 × 32 pixels
     │
     │ (Scale 4:1)
     ▼
VGA Framebuffer: 256 × 128 region (within 320×200)
     │
     │ (Direct write to 0xA000:0x0000)
     ▼
Monitor Output: 256 × 128 visible area
```

### Pixel Mapping Formula

```
VGA_X = CHIP8_X * 4
VGA_Y = CHIP8_Y * 4

For a 4×4 block of VGA pixels (representing 1 CHIP-8 pixel):
  Offset = (VGA_Y * 320) + VGA_X
```

### VRAM Address Calculation

```assembly
; Given CHIP-8 pixel at (X, Y):
; Calculate VGA offset for top-left of 4×4 block

mov ax, [chip8_y]        ; AX = Y (0-31)
mov bx, 4
mul bx                   ; AX = Y * 4 (VGA row)
mov dx, 320
mul dx                   ; AX = (Y * 4) * 320

mov bx, [chip8_x]        ; BX = X (0-63)
mov cx, 4
mul bx, cx               ; BX = X * 4 (VGA column)

add ax, bx               ; AX = final offset
; Now write to ES:AX (video RAM)
```

---

## Sound System

### PC Speaker Architecture

The PC speaker is controlled by:
- **Port 0x43**: 8253 PIT (Programmable Interval Timer) command
- **Port 0x42**: PIT counter (frequency)
- **Port 0x61**: System port (speaker on/off)

### Frequency Calculation

```
Base frequency = 1,193,180 Hz (8253 oscillator)
Desired frequency = 880 Hz (CHIP-8 standard tone)
Divisor = 1,193,180 / 880 = 1356 (0x054C)

Lower byte (0x4C) → Port 0x42
Upper byte (0x05) → Port 0x42
```

### Enable/Disable Sequence

```assembly
; --- ENABLE PC SPEAKER ---
mov al, 0x03             ; Channel 2, mode 3, 16-bit count
out 0x43, al             ; Write to PIT command port

mov al, 0x4C             ; Frequency divisor low byte
out 0x42, al
mov al, 0x05             ; Frequency divisor high byte
out 0x42, al

mov al, [0x61]           ; Read system port
or al, 0x03              ; Set bits 0 & 1 (speaker + timer)
out 0x61, al             ; Write back

; --- DISABLE PC SPEAKER ---
mov al, [0x61]           ; Read system port
and al, 0xFC             ; Clear bits 0 & 1
out 0x61, al             ; Write back
```

---

## Opcode Dispatch

### Jump Table Structure

```assembly
decode_dispatch:
    ; AH = opcode family (0x0-0xF)
    
    shl ah, 1            ; Convert to byte offset (×2)
    lea bx, [jump_table] ; Load jump table address
    jmp [bx + ax]        ; Indirect jump to handler
    
jump_table:
    dw handle_0nnn       ; 0x0NNN
    dw handle_1nnn       ; 0x1NNN
    dw handle_2nnn       ; 0x2NNN
    dw handle_3xkk       ; 0x3XKK
    dw handle_4xkk       ; 0x4XKK
    dw handle_5xy0       ; 0x5XY0
    dw handle_6xkk       ; 0x6XKK
    dw handle_7xkk       ; 0x7XKK
    dw handle_8xy_       ; 0x8XY_
    dw handle_9xy0       ; 0x9XY0
    dw handle_annn       ; 0xANNN
    dw handle_bnnn       ; 0xBNNN
    dw handle_cxkk       ; 0xCXKK
    dw handle_dxyn       ; 0xDXYN
    dw handle_ex__       ; 0xEX__
    dw handle_fx__       ; 0xFX__
```

### Parameter Extraction

```assembly
; After loading opcode in AX:
; Opcode format: ABCD (4 hex digits)
; AH = 0xAB, AL = 0xCD

handle_opcode:
    ; Extract X (second hex digit)
    mov bl, ah           ; BL = 0xAB
    shr bl, 4            ; BL = 0x0A (X)
    
    ; Extract Y (third hex digit)
    mov cl, al           ; CL = 0xCD
    shr cl, 4            ; CL = 0x0C (Y)
    
    ; Extract N (fourth hex digit)
    mov dl, al           ; DL = 0xCD
    and dl, 0x0F         ; DL = 0x0D (N)
    
    ; Extract KK (last 8 bits)
    ; AL already contains KK (0xCD)
```

---

## Critical Design Decisions

### Decision 1: Single-Segment Architecture
**Why:** The 8086 segment/offset model complicates multi-segment code. A single `.COM` format keeps the architecture simple and avoids far jumps.

**Trade-off:** Limited to 64KB total (code + data + stack), but CHIP-8 emulation only needs ~12KB.

### Decision 2: Memory-Resident CHIP-8 Registers
**Why:** Avoids constant register shuffling between 4 general-purpose registers.

**Trade-off:** Two extra memory reads per opcode, but negligible (8086 L1 cache behavior).

### Decision 3: BIOS Timer Synchronization
**Why:** Avoids reprogram hardware timers (which requires privileged mode).

**Trade-off:** Approximate 60Hz (actually 18.2 × 3.3 ≈ 60Hz), but sufficient for games.

### Decision 4: Jump Table Dispatcher
**Why:** O(1) opcode dispatch with no conditional chains.

**Trade-off:** Fixed 16-entry table (but we only have 16 opcode families anyway).

---

## Testing & Validation

See [PHASE3_VALIDATION.md](PHASE3_VALIDATION.md) for comprehensive test cases and debugging procedures.

---

## Glossary

- **Opcode**: 2-byte instruction in CHIP-8 bytecode
- **Nibble**: 4-bit value (one hex digit)
- **Segment**: 64KB block in 8086 memory model
- **Offset**: Address within a segment
- **PIT**: Programmable Interval Timer (8253 chip)
- **VRAM**: Video RAM (graphics memory at 0xA000)
- **DOS INT**: Interrupt service routine provided by DOS kernel

---

**Last Updated:** 2025-05  
**Version:** 1.0.0 (Gold Master)
