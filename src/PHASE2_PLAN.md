# Phase 2: Logic & Synchronization - Detailed Implementation Plan

## Executive Summary

Phase 1 established the hardware foundation: `.COM` executable, VGA Mode 13h graphics, and the fetch-decode-execute loop. Phase 2 focuses on **logic** (all 35 CHIP-8 opcodes) and **timing** (60Hz synchronization + keyboard input) to create a functional emulator capable of running PONG or Tetris.

---

## Part 1: Complete Opcode Implementation (35 Opcodes)

### Family 0x0NNN - System Calls (2 opcodes)
- **0x00E0** - DISP_CLEAR: Clear the 64×32 display
- **0x00EE** - FLOW_RET: Return from subroutine (pop PC from stack)

### Family 0x1NNN - Flow Control (1 opcode)
- **0x1NNN** - FLOW_JMP: Jump to address NNN

### Family 0x2NNN - Subroutines (1 opcode)
- **0x2NNN** - FLOW_CALL: Call subroutine at NNN (push return address to stack)

### Family 0x3XNN - Conditional Skips (1 opcode)
- **0x3XNN** - COND_SKE_VX_NN: Skip next instruction if V[X] == NN

### Family 0x4XNN - Conditional Skips (1 opcode)
- **0x4XNN** - COND_SKNE_VX_NN: Skip next instruction if V[X] != NN

### Family 0x5XY0 - Conditional Skips (1 opcode)
- **0x5XY0** - COND_SKE_VX_VY: Skip next instruction if V[X] == V[Y]

### Family 0x6XNN - Register Load (1 opcode)
- **0x6XNN** - CONST_LD_VX_NN: Load NN into V[X]

### Family 0x7XNN - Arithmetic (1 opcode)
- **0x7XNN** - CONST_ADD_VX_NN: Add NN to V[X]

### Family 0x8XY_ - Arithmetic & Bitwise (8 opcodes) **[CRITICAL]**
- **0x8XY0** - REG_LD_VX_VY: Set V[X] = V[Y]
- **0x8XY1** - BITWISE_OR_VX_VY: Set V[X] = V[X] | V[Y]
- **0x8XY2** - BITWISE_AND_VX_VY: Set V[X] = V[X] & V[Y]
- **0x8XY3** - BITWISE_XOR_VX_VY: Set V[X] = V[X] ^ V[Y]
- **0x8XY4** - MATH_ADD_VX_VY: Set V[X] = V[X] + V[Y], V[F] = carry ✓ **CF handling**
- **0x8XY5** - MATH_SUB_VX_VY: Set V[X] = V[X] - V[Y], V[F] = NOT borrow ✓ **CF handling**
- **0x8XY6** - BITWISE_SHR_VX: Set V[X] = V[X] >> 1, V[F] = LSB before shift
- **0x8XY7** - MATH_SUBN_VX_VY: Set V[X] = V[Y] - V[X], V[F] = NOT borrow ✓ **CF handling**

### Family 0x8XYE (Shift Left) (1 opcode)
- **0x8XYE** - BITWISE_SHL_VX: Set V[X] = V[X] << 1, V[F] = MSB before shift

### Family 0x9XY0 - Conditional Skip (1 opcode)
- **0x9XY0** - COND_SKNE_VX_VY: Skip next instruction if V[X] != V[Y]

### Family 0xANNN - Index Register (1 opcode)
- **0xANNN** - REG_LD_I_NNN: Set I = NNN

### Family 0xBNNN - Jump with Offset (1 opcode)
- **0xBNNN** - FLOW_JMP_V0_NNN: Jump to NNN + V[0]

### Family 0xCXNN - Random (1 opcode)
- **0xCXNN** - BITWISE_AND_VX_RAND: Set V[X] = random(0-255) & NN

### Family 0xDXYN - Draw Sprite (1 opcode) **[CRITICAL]**
- **0xDXYN** - DISP_DRAW_VX_VY_N: Draw N-byte sprite at (V[X], V[Y]) ✓ **Already implemented**

### Family 0xEX__ - Keyboard Input (2 opcodes)
- **0xEX9E** - INPUT_SKP_VX: Skip if key in V[X] is pressed
- **0xEXA1** - INPUT_SKNP_VX: Skip if key in V[X] is NOT pressed

### Family 0xFX__ - Timers, Memory, Font (8 opcodes)
- **0xFX07** - TIME_LD_VX_DT: Set V[X] = Delay Timer
- **0xFX15** - TIME_LD_DT_VX: Set Delay Timer = V[X]
- **0xFX18** - TIME_LD_ST_VX: Set Sound Timer = V[X]
- **0xFX1E** - MEM_ADD_I_VX: Set I = I + V[X]
- **0xFX29** - MEM_LD_F_VX: Set I = Font address for digit V[X]
- **0xFX33** - MEM_LD_B_VX: Store BCD representation of V[X] at I, I+1, I+2
- **0xFX55** - MEM_LD_MEM_VX: Store registers V[0] through V[X] starting at memory address I
- **0xFX65** - MEM_LD_VX_MEM: Read registers V[0] through V[X] from memory starting at I

---

## Part 2: 60Hz Timer Synchronization

### Current State
- Fetch-decode-execute loop runs **as fast as CPU allows** (millions of cycles/sec)
- CHIP-8 programs expect exactly **60Hz decrement** for delay and sound timers

### BIOS Timer Tick Approach
The BIOS maintains a tick counter at **segment 0x0040, offset 0x006C**:
- Incremented **18.2 times per second** (~54.9ms per tick)
- Only **3 increments per CHIP-8 timer decrement** = ~60Hz (54.9ms / 3 ≈ 18.3ms per decrement)

### Implementation Strategy
1. **Sample the BIOS tick at program start** → store in `bios_tick_prev`
2. **After each opcode execution**, check if `BIOS_TICK - bios_tick_prev >= 3`
3. **If true**, decrement both delay_timer and sound_timer, reset counter
4. **Sound effects**: If `sound_timer > 0`, emit beep (optional for Phase 2)

### Pseudo-code
```asm
check_timers:
    ; Load current BIOS tick
    mov ax, 0x0040
    mov es, ax
    mov al, byte [es:0x006C]    ; AL = current BIOS tick (0-255)
    
    ; Compare with previous tick
    cmp al, byte [bios_tick_prev]
    je  .no_decrement
    
    mov byte [bios_tick_prev], al
    inc byte [timer_decrement_count]
    
    ; Every 3 ticks, decrement CHIP-8 timers
    cmp byte [timer_decrement_count], 3
    jne .no_decrement
    
    mov byte [timer_decrement_count], 0
    
    ; Decrement delay_timer
    cmp byte [delay_timer], 0
    je  .skip_delay
    dec byte [delay_timer]
.skip_delay:
    
    ; Decrement sound_timer
    cmp byte [sound_timer], 0
    je  .no_decrement
    dec byte [sound_timer]
    
.no_decrement:
    ret
```

---

## Part 3: Keyboard Mapping via INT 16h

### CHIP-8 Keypad Layout
The CHIP-8 has a 16-key hexadecimal keypad:
```
1 2 3 C
4 5 6 D
7 8 9 E
A 0 B F
```

### IBM PC Keyboard Mapping
Map common keys to CHIP-8 hex pad:
```
'1' = 0x01    '2' = 0x02    '3' = 0x03    '4' = 0x0C
'Q' = 0x04    'W' = 0x05    'E' = 0x06    'R' = 0x0D
'A' = 0x07    'S' = 0x08    'D' = 0x09    'F' = 0x0E
'Z' = 0x0A    'X' = 0x00    'C' = 0x0B    'V' = 0x0F
```

### INT 16h Approach
- **INT 16h, AH=01h**: Non-blocking check for keypress
- **ZF flag**: Set if no key pressed, clear if key available
- **AL/AH**: Scan code and ASCII code of pressed key
- **Advantages**: Doesn't block main loop, ideal for game emulation

### Implementation Pattern
```asm
check_keyboard:
    mov ah, 0x01           ; Non-blocking check
    int 0x16               ; BIOS keyboard interrupt
    jz  .no_key_pressed    ; ZF set = no key
    
    ; Key is pressed - read it
    mov ah, 0x00
    int 0x16               ; Get key into AL/AH
    
    ; AL = ASCII, AH = scan code
    ; Map scan code or ASCII to CHIP-8 key (0x00-0x0F)
    ; Update keyboard_state array
    
.no_key_pressed:
    ret
```

### Keyboard State Array
**Location**: `keyboard_state` at 0x2000 + offset
**Structure**: 16 bytes, one per CHIP-8 key
- `keyboard_state[0x00]` through `keyboard_state[0x0F]`
- **0x00** = key not pressed
- **0x01** = key pressed

---

## Part 4: Memory Layout Update (Phase 2)

```
0x0000 - 0x00FF     CODE (.COM header, interrupt vectors)
0x0100 - 0x01FF     CODE (program entry)
0x0200 - 0x1FFF     CODE (main fetch-decode-execute)
0x2000 - 0x2EFF     CHIP-8 RAM (4096 bytes)
0x2F00 - 0x2F0F     CHIP-8 V[0..15] registers (16 bytes)
0x2F10 - 0x2F11     delay_timer, sound_timer (2 bytes)
0x2F12              bios_tick_prev (1 byte)
0x2F13              timer_decrement_count (1 byte)
0x2F14 - 0x2F23     keyboard_state[0x00..0x0F] (16 bytes)
0x2F24 - 0x2F25     Index Register (I) (2 bytes)
0x2F26 - 0x2F27     Program Counter (PC) (2 bytes)
0x2F28 - 0x2F29     Stack Pointer (SP) (2 bytes)
0x2F2A - 0x2F49     Stack (16 entries × 2 bytes = 32 bytes)
0x2F50 - 0x2F6F     Font Data (16 characters × 5 bytes = 80 bytes)
0x3000 - 0xEFFF     CHIP-8 ROM (holds loaded game)
0xF000 - 0xFFFE     .COM Stack (grows downward from 0xFFFE)
```

---

## Part 5: Critical Implementation Notes

### 8XY4 (Add with Carry)
- **Problem**: 8086 ADC sets CF after **16-bit** addition, but we need 8-bit
- **Solution**: 
  ```asm
  mov al, byte [V_X]      ; V[X]
  add al, byte [V_Y]      ; Add V[Y]
  jnc .no_carry           ; Jump if no carry
  mov byte [V_F], 0x01    ; Set V[F] = 1 (carry occurred)
  jmp .done
  .no_carry:
  mov byte [V_F], 0x00    ; Set V[F] = 0
  .done:
  mov byte [V_X], al      ; Store result
  ```

### 8XY5 (Subtract with Borrow)
- **Problem**: 8086 SBB is for **16-bit**, but we need 8-bit subtraction with correct V[F]
- **Solution**:
  ```asm
  mov al, byte [V_X]      ; V[X]
  sub al, byte [V_Y]      ; Subtract V[Y]
  mov byte [V_X], al      ; Store result
  jnc .no_borrow          ; Jump if NO borrow (carry clear)
  mov byte [V_F], 0x00    ; V[F] = 0 (borrow occurred)
  jmp .done
  .no_borrow:
  mov byte [V_F], 0x01    ; V[F] = 1 (no borrow)
  .done:
  ```

### 8XY6 (Shift Right)
- LSB goes to V[F], then right shift by 1
- Example: V[X] = 0b00110110 (54) → V[F] = 0, V[X] = 0b00011011 (27)

### 8XYE (Shift Left)
- MSB goes to V[F], then left shift by 1
- Example: V[X] = 0b10110110 (182) → V[F] = 1, V[X] = 0b01101100 (108)

### CXN (Random AND)
- Use **BIOS Timer Tick** as seed: `mov al, byte [0x0040:0x006C]`
- Pseudo-random: not cryptographically secure, but sufficient for games
- Then AND with NN and store in V[X]

### Font Storage (0xFX29)
- 16 hex digits (0-F), each 5 bytes high
- **Location**: 0x2F50 (80 bytes total)
- I register points to start of 5-byte sprite for digit V[X]

### BCD Conversion (0xFX33)
- V[X] = value (0-255)
- Store hundreds digit at I
- Store tens digit at I+1
- Store ones digit at I+2
- Example: V[X] = 173 → (I)=1, (I+1)=7, (I+2)=3

---

## Part 6: Phase 2 Milestone

A **fully functional** Phase 2 checkpoint will:
1. ✓ Execute all 35 CHIP-8 opcodes without undefined behavior
2. ✓ Pass keyboard input from INT 16h to opcode handlers
3. ✓ Decrement timers at exactly 60Hz (or close approximation)
4. ✓ Run **PONG** or **Tetris** ROM to completion
5. ✓ Display sprite graphics correctly with 4:1 VGA scaling
6. ✓ Support player control (arrow keys or QWERTY mapping)

### Test ROM: PONG
- Simple 2-player game
- Minimal RAM usage (~2KB)
- Real-time input handling
- Timer-dependent gameplay

### Test ROM: Tetris
- More complex sprite handling
- Random number generation
- Longer gameplay session
- Full keyboard mapping required

---

## Part 7: Phase 2 Deliverables Checklist

- [ ] phase2_main.asm: Full opcode implementation
- [ ] phase2_keyboard.asm: INT 16h keyboard handler (modular)
- [ ] phase2_timers.asm: 60Hz BIOS tick handler (modular)
- [ ] PHASE2_IMPLEMENTATION.md: Detailed coding guide
- [ ] PHASE2_VALIDATION.md: Test checklist
- [ ] Makefile update: phase2 target
- [ ] Test PONG/Tetris: Both roms run successfully

---

## Summary of Changes from Phase 1 → Phase 2

| Component | Phase 1 | Phase 2 |
|-----------|---------|---------|
| Opcodes | 1 (DXYN) | 35 (all) |
| Timers | Stub | 60Hz sync via BIOS tick |
| Keyboard | Stub | INT 16h polling |
| Memory | 4KB CHIP-8 RAM | +256 bytes system state |
| Test | IBM Logo | PONG / Tetris |
| Status | Hardware proven | Logic & timing proven |

