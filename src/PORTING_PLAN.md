# NANO-VM 16-Bit Emu8086 Port - Comprehensive Planning Document

## Executive Summary

This document defines the architectural approach for porting NANO-VM from a 64-bit x86_64/Linux implementation to the 16-bit Intel 8086 real-mode environment (emu8086). The port targets a single-segment `.COM` executable with direct hardware manipulation via BIOS/DOS interrupts, replacing all C-library dependencies.

**Key Milestone**: Successful rendering of the IBM Logo ROM at VGA resolution using Mode 13h with 4:1 pixel scaling.

---

## 1. Memory Architecture & Segment Strategy

### 1.1 Memory Map (Single 64KB Segment)

```
Segment: CS = DS = ES = SS = 0x0000 (relative to .COM ORG 100h)

Address Range    Size     Purpose                    Notes
─────────────────────────────────────────────────────────────
0x0000-0x00FF    256B     DOS PSP (Program Segment Prefix)
0x0100           (ORG)    Code + Data Start          Standard .COM entry point
0x0100-0x?       Code     Main loop, opcode handlers (est. 3-5KB)
0x?-0x1FFF       Data     Constants, ROM data, fonts
0x2000-0x5FFF    16KB     CHIP-8 RAM (4KB at 0x200, rest unused for Phase 3)
                          - 0x2000-0x204F: Font data (80B, offset 0x50 in VM space)
                          - 0x2050-0x207F: Font data (5B per character)
                          - 0x2080-0x207F: Stack space (16 * 2B = 32B)
                          - 0x2080+: CHIP-8 registers (16B V0-VF)
                          - 0x2090+: I register, timers, keyboard state
                          - 0x20A0-0x27FF: Program RAM (4KB starting at 0x200 VM address)
0x6000-0xFFFB    ~40KB    Host Stack + Heap (grows downward from SP)
0xFFFE           2B       Host Stack Pointer Init (SP = 0xFFFE at startup)
```

**Critical Constraint**: The host stack MUST NOT collide with CHIP-8 RAM. By initializing `SP = 0xFFFE`, we have a 40KB gap between the VM state (ending at 0x27FF) and the stack base.

### 1.2 Segment Register Management

| Register | Assignment          | Rationale                          |
|----------|---------------------|------------------------------------|
| **CS**   | 0x0000              | Code segment (implicit, ORG 100h)  |
| **DS**   | 0x0000 (permanent)  | Points to CHIP-8 RAM & registers   |
| **ES**   | 0xA000 (video mode) | VGA video memory (320×200, 8-bit)  |
| **SS**   | 0x0000 (implicit)   | Host stack in same segment         |
| **SP**   | 0xFFFE              | Maximum stack size (initialized)   |

**Loading ES for Video Access**:
```asm
mov ax, 0xA000
mov es, ax              ; ES now points to VGA video memory
```

---

## 2. The Big-Endian Fetch Cycle (Pillar A)

### 2.1 The Problem

CHIP-8 opcodes are stored in **Big-Endian** format (high byte first), but the 8086 is **Little-Endian** (low byte first). A naive word load flips the nibbles:

```
ROM contains:  0x12 0x34  (CHIP-8: instruction 1234)
After lodsw:   AX = 0x3412  (Wrong!)
```

### 2.2 The Mandatory Solution

All fetch operations **MUST** immediately swap the bytes:

```asm
; Standard Fetch Cycle (used in decoder.asm)
fetch_opcode:
    mov si, [pc]                ; SI = program counter
    add si, 0x2000              ; Offset into our RAM base
    lodsw                       ; AX = [SI], SI += 2
    xchg ah, al                 ; Swap bytes: AX = big-endian
    mov [last_opcode], ax       ; Cache for debugging
    ret
```

**Verification**: After fetch, AX contains the correctly aligned CHIP-8 opcode for the jump table.

---

## 3. VGA Mode 13h Graphics (Pillar B)

### 3.1 Display Scaling

| Aspect            | CHIP-8      | VGA 13h     | Scaling |
|-------------------|-------------|-------------|---------|
| Width             | 64 pixels   | 320 pixels  | 5× or 4× |
| Height            | 32 pixels   | 200 pixels  | 6.25× or 4× |
| Color Depth       | 1-bit       | 8-bit       | Expansion |
| Total VRAM        | 256B        | 64KB        | 256× |

**Decision: 4:1 Scaling**
- Each CHIP-8 pixel becomes a 4×4 block of VGA pixels
- CHIP-8 (64×32) → VGA (256×128) with black border
- Trade-off: Slightly smaller display, but uniform & efficient

### 3.2 VGA Memory Layout

In Mode 13h, pixel (X, Y) is stored at:
```
Offset = (Y * 320) + X
```

For a 4×4 scaled pixel at CHIP-8 position (CX, CY):

```asm
; Draw 4×4 pixel block for CHIP-8 pixel at (CX, CY)
; AX = color (0x00 = black, 0xFF = white, etc.)
; CX = X coordinate, DX = CY coordinate

scale_x:    mov bx, cx
            shl bx, 2               ; BX = CX * 4 (left edge in VGA space)

scale_y:    mov ax, dx
            shl ax, 2               ; AX = CY * 4 (top edge in VGA space)
            
            ; Draw 4 rows of 4 pixels each
            mov cx, 4               ; 4 rows
.row_loop:
            mov di, [es:0]          ; Current row offset
            add di, [scale_x]       ; Add column offset
            ; Write 4 consecutive bytes to VGA memory
            mov byte [es:di], 0xFF  ; Pixel 1
            mov byte [es:di+1], 0xFF
            mov byte [es:di+2], 0xFF
            mov byte [es:di+3], 0xFF
            add di, 320             ; Next scanline
            loop .row_loop
```

### 3.3 Direct VRAM Writing (No BIOS)

Direct write is essential for 60 FPS. BIOS INT 10h is too slow.

```asm
; Setup for direct video access
mov ax, 0xA000
mov es, ax                          ; ES = VGA segment

; Write pixel at VGA (X, Y)
mov di, (Y * 320) + X
mov byte [es:di], color_value
```

---

## 4. Phase Breakdown & Deliverables

### Phase 1: Environment Hardening (Foundation)
**Objective**: Stable 16-bit environment with memory validation

**Deliverables:**
- [ ] Memory map fully implemented (RAM, registers, stack in single segment)
- [ ] Fetch cycle with Big-Endian correction (lodsw + xchg)
- [ ] VGA Mode 13h initialization (set video mode, configure ES)
- [ ] Opcode dispatch table (jump-based, not if-else chains)
- [ ] Stack overflow/underflow detection (hard fail)
- [ ] Basic register operations (6XNN, ANNN, DXYN ready)

**Checkpoint**: Successfully initialize VM state and render test pattern to VGA

---

### Phase 2: Timing & Input (Synchronization)
**Objective**: 60Hz timer decrement synchronized with real-time

**Deliverables:**
- [ ] BIOS timer tick (0040:006Ch) polling for 60Hz sync
- [ ] Delay timer & sound timer decrement logic
- [ ] Keyboard polling via INT 16h (BIOS keyboard interrupt)
- [ ] Instruction execution loop at stable frequency (500Hz or 60FPS)

**Checkpoint**: IBM Logo renders on display with synchronized timing

---

### Phase 3: Complete Graphics (Visual Output)
**Objective**: Full DXYN sprite rendering with XOR logic

**Deliverables:**
- [ ] Sprite drawing (DXYN) with 4:1 scaling
- [ ] XOR collision detection
- [ ] Display buffer update optimization
- [ ] Collision flag (VF) setting

**Checkpoint**: IBM Logo displays correctly, collision detection works

---

### Phase 4: Full Opcode Implementation (Complete VM)
**Objective**: All 35+ opcodes for any CHIP-8 ROM

**Deliverables:**
- [ ] Remaining opcodes (timers, sound, keyboard input)
- [ ] Random number generator (CXNN)
- [ ] BCD conversion (FX33)
- [ ] Register I/O (FX55, FX65)

**Checkpoint**: Run benchmark ROMs; measure performance

---

## 5. Register Mapping (4 General-Purpose Registers)

The 8086 has only 4 general-purpose 16-bit registers: **AX, BX, CX, DX**. CHIP-8 has 16 8-bit registers (V0-VF).

**Strategy: Memory-Resident Registers**

All CHIP-8 registers (V0-VF, I) are stored in RAM and accessed via **indexed addressing**:

```asm
; Load V3 into a working register
lea rax, [CHIP8_RAM + REGISTERS_OFFSET]  ; RAX = base of registers
mov cl, byte [rax + 3]                  ; CL = V3

; Store result back to V5
mov byte [rax + 5], cl                  ; V5 = result
```

**Working Register Allocation:**
- **AX**: Opcode fetch & intermediate math (primary)
- **BX**: Register values, addresses
- **CX**: Loop counters, register indices (secondary math)
- **DX**: Register values, division remainder

---

## 6. Clock Synchronization Strategy (BIOS Timer Tick)

### 6.1 BIOS Timer Interrupt 0x1C (Auto-Invoke)

The 8086/DOS environment automatically invokes INT 0x1C every ~55ms (18.2 Hz) during idle. The BIOS maintains a 32-bit counter at memory location **0x0040:0x006C**.

```
BIOS Timer Cell (Read-Only):
Segment: 0x0040
Offset:  0x006C (4 bytes, little-endian)
Updated: Every ~55ms (18.2 times per second)
```

### 6.2 Reading the BIOS Clock

```asm
; Save the BIOS timer tick counter on startup
mov ax, 0x0040
mov ds, ax                  ; DS = BIOS data segment
mov eax, [0x006C]          ; EAX = BIOS timer (32-bit)
mov [timer_start_tick], eax ; Save for later comparison

; Later: Check elapsed ticks
mov eax, [0x006C]
sub eax, [timer_last_decrement_tick]
cmp eax, 1                  ; At least 1 tick elapsed? (55ms)
jl .skip_decrement

; Time for 60Hz decrement (rough approximation at 18.2 Hz)
; For proper 60Hz (16.67ms), use more precise timing
```

### 6.3 Precise 60Hz Decrement via Sleep (If Available)

For Phase 2, we can use nanosleep-style timing (if DOS supports it via extenders like CWSDPMI).

Fallback: Synchronize to BIOS ticks (~55ms) for a coarser 18Hz timer.

---

## 7. Keyboard Mapping (INT 16h)

The 8086 BIOS provides INT 0x16 for keyboard input. CHIP-8 has 16 keys (0x0-0xF).

```
CHIP-8 Key  PS/2 Scan Code   Mapping Strategy
──────────  ────────────────  ──────────────────
0           Key X            1 = X
1           Key 1            2 = 1
2           Key 2            3 = 2
3           Key 3            4 = 3
4           Key Q            5 = Q
5           Key W            6 = W
6           Key E            7 = E
7           Key R            8 = R
8           Key A            9 = A
9           Key S            A = S
A           Key D            B = D
B           Key F            C = F
C           Key Z            D = Z
D           Key C            E = C
E           Key V            F = V
F           Key B            (spacebar or other)
```

**Implementation**:

```asm
; Poll keyboard (INT 16h, AH=1 for non-blocking check)
mov ah, 0x01
int 0x16                    ; Sets ZF if no key, otherwise AL = ASCII
                            ; (more detailed in Phase 2)
```

---

## 8. Stack Implementation (16-Level Subroutine Stack)

CHIP-8 stack for return addresses (not the host stack):

```
VM Stack Location:   RAM at offset 0x2080
VM Stack Entries:    16 * 2 bytes = 32 bytes (2-byte return addresses)
VM Stack Pointer:    Stored at RAM offset 0x2090 (1 byte, 0-15)

Stack Usage:
Stack[0] = return address for first CALL
Stack[1] = return address for second CALL
...
Stack[15] = return address for deepest CALL (full)
```

**Hard Constraints**:
- Push: SP < 16 (else stack overflow, hard fail)
- Pop: SP > 0 (else stack underflow, hard fail)

---

## 9. Implementation Checklist (Pre-Coding)

### A. Register Mapping
- [x] 4 working registers (AX, BX, CX, DX) identified
- [x] Memory-resident CHIP-8 registers (V0-VF, I) at 0x2080+
- [x] Stack location: RAM 0x2080, SP at 0x2090
- [x] Opcode cache location: 0x2092

### B. Clock Synchronization
- [x] BIOS timer tick location (0x0040:0x006C) identified
- [x] 60Hz decrement method: BIOS ticks (18.2Hz fallback) or precise sleep
- [x] Timer decrement triggers hard-fail if out of bounds

### C. Keyboard Mapping
- [x] INT 0x16 (BIOS keyboard) chosen as input method
- [x] 16-key map defined (X, 1-3, Q-R, A-F, Z-V, etc.)
- [x] Keyboard state array: 16 bytes at RAM 0x2091+

### D. VGA Graphics
- [x] Mode 13h (320×200, 8-bit) chosen
- [x] ES register set to 0xA000 for direct VRAM access
- [x] 4:1 pixel scaling formula: VGA_offset = (Y*4*320) + (X*4)
- [x] No BIOS INT 10h for pixel writes (too slow)

### E. Memory Safety
- [x] I-register bounds checking (modulo 4096)
- [x] Display buffer bounds (256 bytes)
- [x] Stack overflow/underflow detection
- [x] Register index validation (0-15)

---

## 10. File Structure (Emu8086 Format)

```
NANO-VM-8086/
├── main.asm              (Entry point, initialization, main loop)
├── fetch.asm             (Big-Endian fetch cycle)
├── decoder.asm           (Opcode dispatcher)
├── handlers/
│   ├── control.asm       (00E0, 1NNN, 2NNN, 00EE)
│   ├── registers.asm     (6XNN, 7XNN, 8XY*)
│   ├── memory.asm        (ANNN, FX1E, FX33, FX55, FX65)
│   ├── graphics.asm      (DXYN, display rendering)
│   └── timers.asm        (FX07, FX15, FX18, keyboard)
├── graphics.asm          (VGA Mode 13h, scaling)
├── bios.asm              (BIOS calls, interrupts)
├── defines.inc           (Constants, memory layout)
└── rom_data.inc          (IBM Logo ROM embedded)
```

**Notes**:
- All files use emu8086 `.asm` format (compatible with NASM)
- Single ORG 100h, single segment
- External labels prefixed with `_` for clarity (e.g., `_keyboard_poll`)

---

## 11. Error Handling & Halting

**Hard Failures** (immediate VM halt):
- Stack overflow (SP >= 16 on CALL)
- Stack underflow (SP == 0 on RET)
- Invalid opcode dispatch

**Graceful Exit**:
- Return to DOS with exit code 1 (error) or 0 (success)

---

## 12. Success Criteria (Phase 3 Checkpoint)

By the end of Phase 3, the following must be true:

1. **IBM Logo renders on VGA**: Clear, visible at 4:1 scaling
2. **Synchronized timing**: Display updates at ~60 FPS
3. **No memory corruption**: All accesses are within bounds
4. **No stack violations**: All CALL/RET pairs balanced
5. **Keyboard input works**: Can poll 16 keys via INT 16h
6. **Opcode dispatch is stable**: All Phase 1-3 opcodes execute correctly

---

## 13. Development Constraints

- **Target**: emu8086 IDE with integrated debugger
- **Real hardware**: 8086/8088, 640KB RAM, VGA video card
- **No FPU**: All math integer-only
- **No SIMD**: All operations scalar
- **Interrupt safety**: Minimal; only use BIOS interrupts (0x10, 0x16, 0x1A)

---

## Sign-Off

This plan establishes the architectural foundation for porting NANO-VM to emu8086. All three pillars (Big-Endian fetch, direct VGA access, segment management) are detailed with explicit code patterns and memory layouts.

**Ready to proceed to Phase 1 coding.**

---

**Document Version**: 1.0  
**Date**: 2026-05-11  
**Status**: Planning Complete, Awaiting Phase 1 Implementation
