# Phase 2 Implementation Guide - Deep Dive

## What's New in phase2_main.asm

### 1. Complete Opcode Coverage (35 Opcodes)

The `phase2_main.asm` includes **all 35 CHIP-8 opcodes** in a single monolithic file organized into families:

| Family | Opcodes | Count | Status |
|--------|---------|-------|--------|
| 0x0NNN | DISP_CLEAR, FLOW_RET | 2 | ✓ Complete |
| 0x1NNN | FLOW_JMP | 1 | ✓ Complete |
| 0x2NNN | FLOW_CALL | 1 | ✓ Complete |
| 0x3XNN | COND_SKE | 1 | ✓ Complete |
| 0x4XNN | COND_SKNE | 1 | ✓ Complete |
| 0x5XY0 | COND_SKE_VX_VY | 1 | ✓ Complete |
| 0x6XNN | CONST_LD | 1 | ✓ Complete |
| 0x7XNN | CONST_ADD | 1 | ✓ Complete |
| 0x8XY_ | Arithmetic (8 ops) | 8 | ✓ Complete |
| 0x9XY0 | COND_SKNE_VX_VY | 1 | ✓ Complete |
| 0xANNN | REG_LD_I | 1 | ✓ Complete |
| 0xBNNN | FLOW_JMP_V0 | 1 | ✓ Complete |
| 0xCXNN | BITWISE_AND_RAND | 1 | ✓ Complete |
| 0xDXYN | DISP_DRAW | 1 | ✓ Complete |
| 0xEX__ | INPUT_SKP | 2 | ✓ Complete |
| 0xFX__ | TIMERS & MEMORY (8 ops) | 8 | ✓ Complete |
| **TOTAL** | | **35** | **✓ 100%** |

---

### 2. Fetch-Decode-Execute Loop

```asm
main_loop:
    call fetch_opcode       ; Get next opcode from PC
    call check_timers       ; Check 60Hz decrement
    call check_keyboard     ; Poll INT 16h
    call decode_execute     ; Execute opcode
    jmp main_loop
```

**Cycle Time**: ~0.1-0.5ms per instruction (varies by opcode complexity)

---

### 3. The Jump Table Dispatcher

The decoder uses a **16-way jump table** keyed by high nibble:

```asm
decode_table:
    dw  op_0nnn   ; 0x0___
    dw  op_1nnn   ; 0x1___
    dw  op_2nnn   ; 0x2___
    ...
    dw  op_fxnn   ; 0xF___
```

For complex families (like 0x8XY_), a **second-level jump table** dispatches:

```asm
op_8xyn:
    ; Extract N (low nibble)
    and ax, 0x000F
    jmp [ax*2 + op_8_table]

op_8_table:
    dw  .op_8xy0
    dw  .op_8xy1
    ...
    dw  .op_8xye
```

**Advantage**: O(1) dispatch, no linear search

---

### 4. Critical Arithmetic Operations

#### 0x8XY4 (Add with Carry)
```asm
.op_8xy4:   ; V[X] += V[Y], V[F] = carry
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    add al, byte [es:bx + cx]
    jnc .no_carry_4
    mov byte [es:bx + 15], 1   ; Set V[F] = 1
    jmp .set_vx_4
.no_carry_4:
    mov byte [es:bx + 15], 0   ; Set V[F] = 0
.set_vx_4:
    mov byte [es:bx + dx], al
```

**Why this works**: The 8086 `add al, ...` sets the Carry Flag (CF) after 8-bit arithmetic. We check CF with `jnc` (Jump if No Carry) and manually set V[F].

---

#### 0x8XY5 (Subtract without Borrow)
```asm
.op_8xy5:   ; V[X] -= V[Y], V[F] = NOT borrow
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    sub al, byte [es:bx + cx]
    jnc .no_borrow_5
    mov byte [es:bx + 15], 0   ; Borrow occurred: V[F] = 0
    jmp .set_vx_5
.no_borrow_5:
    mov byte [es:bx + 15], 1   ; No borrow: V[F] = 1
```

**Key**: In CHIP-8, V[F] = 0 if borrow, 1 if no borrow. The 8086 `sub` instruction sets CF on borrow.

---

#### 0x8XY6 (Shift Right)
```asm
.op_8xy6:   ; V[X] >>= 1, V[F] = LSB before shift
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    mov cl, al              ; Save LSB
    and cl, 1
    mov byte [es:bx + 15], cl  ; V[F] = LSB
    shr al, 1               ; Right shift
    mov byte [es:bx + dx], al
```

**Key**: Extract LSB before shift, store in V[F]

---

#### 0x8XYE (Shift Left)
```asm
.op_8xye:   ; V[X] <<= 1, V[F] = MSB before shift
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    mov cl, al
    shr cl, 7               ; Extract MSB (bit 7)
    mov byte [es:bx + 15], cl  ; V[F] = MSB
    shl al, 1               ; Left shift
    mov byte [es:bx + dx], al
```

**Key**: MSB is bit 7, extract via `shr cl, 7`

---

### 5. Timer Synchronization (60Hz via BIOS)

```asm
check_timers:
    ; Load current BIOS tick (0x0040:0x006C)
    mov ax, 0x0040
    mov ds, ax
    mov al, byte [0x006C]
    mov ds, 0x0000

    ; Compare with previous tick
    cmp al, byte [es:0x0F12]    ; Previous tick
    je  .no_timer_update

    ; Update and count ticks
    mov byte [es:0x0F12], al
    inc byte [es:0x0F13]

    ; Every 3 BIOS ticks (~60Hz), decrement CHIP-8 timers
    cmp byte [es:0x0F13], 3
    jl  .no_timer_update

    mov byte [es:0x0F13], 0
    dec byte [es:0x0F10]        ; Delay timer
    dec byte [es:0x0F11]        ; Sound timer
```

**Why 3?**
- BIOS timer increments at **18.2Hz** (every 54.9ms)
- CHIP-8 needs 60Hz decrement (every 16.67ms)
- 54.9ms ÷ 3 ≈ 18.3ms ≈ 60Hz

---

### 6. Keyboard Input (INT 16h)

```asm
check_keyboard:
    ; Non-blocking keyboard check
    mov ah, 0x01
    int 0x16
    jz  .no_key_pressed     ; ZF set = no key

    ; Read key and map to CHIP-8 (0x00-0x0F)
    xor ah, ah
    int 0x16                ; AL = ASCII
    
    ; Map ASCII to CHIP-8 key index
    ; Examples: '1' -> 0x01, 'Q' -> 0x04, 'X' -> 0x00
```

**Mapping Reference**:
```
'1' = 0x01    '2' = 0x02    '3' = 0x03    '4' = 0x0C
'Q' = 0x04    'W' = 0x05    'E' = 0x06    'R' = 0x0D
'A' = 0x07    'S' = 0x08    'D' = 0x09    'F' = 0x0E
'Z' = 0x0A    'X' = 0x00    'C' = 0x0B    'V' = 0x0F
```

---

### 7. Draw Sprite (0xDXYN)

```asm
op_dxyn:
    ; Get V[X] (X coord) and V[Y] (Y coord)
    ; Get N (height in pixels)
    ; Get I (sprite address)
    
    ; Scale coordinates for VGA: X *= 4, Y *= 4
    shl dx, 2
    shl cx, 2

    ; For each row of sprite:
    ;   Get byte at (I + row)
    ;   For each bit in byte:
    ;     If bit set, draw pixel at (X + 8-bit)*4, Y + row*4
    ;     Use color 0x0F (white)
```

**4:1 Scaling**: Each CHIP-8 pixel becomes a 4×4 block in VGA Mode 13h

---

### 8. Font Storage (0xFX29)

Fonts are stored at 0x2F50:
```
Digit 0: 0x2F50 - 0x2F54 (5 bytes)
Digit 1: 0x2F55 - 0x2F59 (5 bytes)
...
Digit F: 0x2F7B - 0x2F7F (5 bytes)
```

Each font is 5 bytes (8 pixels wide, but only 4 bits per row in hex).

---

### 9. BCD Conversion (0xFX33)

Converts V[X] (0-255) to decimal and stores:
- Hundreds digit at I
- Tens digit at I+1
- Ones digit at I+2

Example: V[X] = 173 → Store (1, 7, 3)

Implementation: Repeatedly subtract 100, 10, then remainder.

---

## Building Phase 2

```bash
nasm -f bin phase2_main.asm -o nano_vm.com
```

**Output**: `nano_vm.com` (~8-16 KB binary)

---

## Testing Checklist

### Functional Tests
- [ ] Program boots without crash
- [ ] IBM Logo renders correctly (test DXYN)
- [ ] Arithmetic opcodes (8XY4, 8XY5, 8XY6, 8XYE) set V[F] correctly
- [ ] Keyboard input maps correctly (press '1' → V[X] key check works)
- [ ] Timers decrement at ~60Hz (load Tetris, watch gravity behavior)
- [ ] Display clears on 0x00E0
- [ ] Subroutine calls/returns work (0x2NNN/0x00EE)
- [ ] Jump and conditional skips work (0x1NNN, 0x3XNN, 0x4XNN, etc.)

### Performance Tests
- [ ] Single opcode execution < 1ms
- [ ] Main loop maintains ~60 FPS (or close)
- [ ] Memory doesn't corrupt after 1000 instructions

### ROM Tests
- [ ] PONG runs and responds to player input
- [ ] Tetris runs, pieces fall at correct speed, player can rotate

---

## Known Limitations (Phase 2)

1. **Sound Timer**: Decrements but no audio output (hardware limitation)
2. **Keyboard Buffer**: Only latest key press tracked (no queue)
3. **Memory Limit**: 4KB CHIP-8 RAM (standard, but some ROMs use extended)
4. **No Extended Opcodes**: VIP / XO-CHIP features not supported
5. **Font Fixed**: Only standard 16 hex digits (0-F)

---

## What's Next (Phase 3)

Phase 3 will focus on:
- ROM loading from disk (via BIOS INT 21h)
- Sound output via PC speaker
- Performance optimization (reduce cycle overhead)
- Extended opcode support (if needed by ROM)

