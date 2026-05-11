# Phase 2 Validation & Testing Framework

## Pre-Flight Checklist (Before Running)

- [ ] `phase2_main.asm` compiles without errors
  ```bash
  nasm -f bin phase2_main.asm -o nano_vm.com
  echo $?  # Should output 0
  ```

- [ ] Binary size is reasonable (8-16 KB)
  ```bash
  ls -lh nano_vm.com  # Should show size
  ```

- [ ] No undefined labels or forward references
  ```bash
  nasm -f bin phase2_main.asm -l nano_vm.lst  # Check .lst for warnings
  ```

---

## Unit Test Framework (Modular Testing)

### Test 1: System Boot & VGA Mode 13h

**Objective**: Verify that the emulator boots and switches to VGA Mode 13h.

**Steps**:
1. Run `nano_vm.com` in DOSBox
2. Observe: Screen clears and turns black (VGA Mode 13h)
3. Observe: No immediate crash or hang

**Expected Result**: Black screen, no errors

**Failure Modes**:
- White/garbage text on screen → VGA mode switch failed
- System hang → Infinite loop in initialization
- Crash (CPU exception) → Segment/memory error

**Debug**:
```asm
; Add before main_loop:
mov al, 0xFF        ; White pixel
mov [0xA000:0], al  ; Write to VRAM at segment 0xA000:0
; If you see a white pixel, VGA is working
```

---

### Test 2: DXYN (Draw Sprite)

**Objective**: Verify that sprite drawing (DXYN) works with 4:1 scaling.

**Expected Behavior**: IBM Logo (3 characters) rendered in top-left corner

**Steps**:
1. Run emulator
2. Observe screen for white pixels forming a pattern (IBM Logo)
3. Verify pixels are properly scaled 4:1

**Failure Modes**:
- No pixels drawn → VRAM offset calculation wrong
- Pixels in wrong location → Register extraction error (V[X], V[Y])
- Pixels wrong color → Color code wrong
- Pixels not scaled → Scaling math error

**Debug**: Add temporary pixel at fixed location:
```asm
; Hardcode pixel at (10, 10) for debugging
mov di, 10 * VGA_WIDTH + 10
mov al, 0x0F
mov [0xA000:di], al
```

---

### Test 3: Register Arithmetic (0x8XY_ Family)

**Objective**: Verify that all 8XY_ opcodes work correctly, especially V[F] flag setting.

**Test ROM** (hardcoded opcodes):
```
0x6005     V[0] = 5
0x6103     V[1] = 3
0x8014     V[0] += V[1]  (5 + 3 = 8, no carry, V[F] = 0)
0x6205     V[2] = 200
0x6302     V[3] = 55
0x8234     V[2] += V[3]  (200 + 55 = 255, no carry, V[F] = 0)
0x6402     V[4] = 2
0x8144     V[1] += V[4]  (3 + 2 = 5, no carry, V[F] = 0)
0x00E0     CLEAR (halt)
```

**Expected Registers After Execution**:
- V[0] = 8
- V[1] = 5
- V[2] = 255
- V[3] = 55
- V[4] = 2
- V[F] = 0 (no carry)

**How to Debug**:
1. Break after each arithmetic instruction
2. Inspect memory at 0x2F00-0x2F0F (V registers)
3. Verify each register has expected value

**Tool**: Use DOSBox debugger:
```
d 2f00  ; Dump memory at 0x2F00 (V registers)
```

---

### Test 4: Carry Flag (0x8XY4 with Overflow)

**Test ROM**:
```
0x60FF     V[0] = 255
0x6101     V[1] = 1
0x8014     V[0] += V[1]  (255 + 1 = 256 overflow, result = 0, V[F] = 1)
```

**Expected**:
- V[0] = 0 (256 mod 256)
- V[F] = 1 (carry flag set)

**Debug**: Breakpoint after 0x8014, check V[0] and V[F] in memory

---

### Test 5: Borrow Flag (0x8XY5)

**Test ROM**:
```
0x6003     V[0] = 3
0x6105     V[1] = 5
0x8015     V[0] -= V[1]  (3 - 5 = -2, borrow, V[F] = 0)
```

**Expected**:
- V[0] = 254 (256 - 2, i.e., -2 in 8-bit two's complement)
- V[F] = 0 (borrow occurred)

**Logic Check**: CF clear after SUB means no borrow → V[F] = 1. CF set means borrow → V[F] = 0.

---

### Test 6: Shift Right (0x8XY6)

**Test ROM**:
```
0x6037     V[0] = 55 (0b00110111)
0x8006     V[0] >>= 1  (result = 27, LSB = 1, V[F] = 1)
```

**Expected**:
- V[0] = 27 (0b00011011)
- V[F] = 1 (LSB before shift was 1)

---

### Test 7: Shift Left (0x8XYE)

**Test ROM**:
```
0x60B6     V[0] = 182 (0b10110110)
0x800E     V[0] <<= 1  (result = 108, MSB = 1, V[F] = 1)
```

**Expected**:
- V[0] = 108 (0b01101100)
- V[F] = 1 (MSB before shift was 1)

---

### Test 8: Timer Decrement (60Hz via BIOS Tick)

**Objective**: Verify timers decrement at ~60Hz.

**Test ROM**:
```
0x60FF     V[0] = 255
0xF015     DT = V[0]  (Set delay timer to 255)
[INFINITE LOOP: 0x1200 JP 0x200]
```

**Expected Behavior**:
1. Delay timer set to 255
2. After ~4.25 seconds (255/60), delay timer reaches 0
3. Timer should decrement smoothly, approximately 60 times per second

**How to Debug**:
- Add temporary display of timer value every 100 instructions
- Compare elapsed wall-clock time vs. timer decrements
- Should see approximately 60 decrements per second

**Failure Modes**:
- Timer doesn't decrement → BIOS tick reading not working
- Timer decrements too fast → Counter not checking BIOS tick properly
- Timer decrements too slow → Counter threshold wrong (should be 3)

**Manual Verification**:
```
Time: 0s, Timer: 255
Time: 1s, Timer: ~240 (should have decremented ~15 times)
Time: 4s, Timer: ~15
Time: 4.25s, Timer: 0
```

---

### Test 9: Keyboard Input (INT 16h)

**Objective**: Verify that pressing keys on the keyboard updates the keyboard_state array.

**Test ROM**:
```
0x6000     V[0] = 0
0xF029     I = FontAddr(0)  (points to font for digit 0)
[LOOP: 
  0xEX9E    SKP (if key V[X] pressed, skip next)
  0x1200    JP 0x200 (if not pressed, loop back)
  0xD008    Draw sprite at (0, 0)
  0x1200    JP 0x200 (loop forever)
]
```

**Expected Behavior**:
1. Emulator waits for any key press
2. When user presses a key (e.g., '1'), the keyboard_state[0] is set to 1
3. The opcode EX9E detects this and skips the jump, allowing the draw
4. A sprite appears on screen

**Failure Modes**:
- No sprite appears even after pressing keys → Keyboard mapping broken
- Sprite appears on startup → keyboard_state not initialized correctly
- Wrong sprite appears → Key mapping is wrong

**Manual Test**:
1. Run emulator
2. Press '1' key (should be CHIP-8 key 0x01)
3. Observe screen for any change

---

### Test 10: Jump & Call/Return (0x1NNN, 0x2NNN, 0x00EE)

**Test ROM**:
```
0x2206     CALL 0x206  (call subroutine)
0x1208     JP 0x208    (jump to halt if call worked)
[0x206: Subroutine]
0x00EE     RET (return to after call)
[0x208: Halt]
0x1208     JP 0x208 (infinite loop)
```

**Expected Flow**:
1. PC starts at 0x200
2. CALL 0x206 → push PC (0x202) to stack, jump to 0x206
3. RET → pop stack, PC = 0x202
4. JP 0x208 → PC = 0x208
5. Infinite loop at 0x208

**Failure Modes**:
- Program jumps to wrong address → PC calculation wrong
- Stack corrupts → Stack pointer not managed correctly
- Subroutine returns to wrong address → Stack push/pop order wrong

---

### Test 11: Conditional Skips (0x3XNN, 0x4XNN, 0x5XY0, 0x9XY0)

**Test ROM**:
```
0x6005     V[0] = 5
0x3005     SKE V[0], 5  (should skip next)
0x1200     JP 0x200     (should NOT execute)
0x6004     V[0] = 4     (should execute if skip worked)
```

**Expected**: V[0] = 4 (confirming skip worked)

---

### Test 12: Bitwise Operations (0x8XY1, 0x8XY2, 0x8XY3)

**Test ROM**:
```
0x6055     V[0] = 85 (0b01010101)
0x61AA     V[1] = 170 (0b10101010)
0x8011     V[0] |= V[1]  (result = 255, all bits set)
```

**Expected**: V[0] = 255

---

### Test 13: Load & Add I (0xANNN, 0xFX1E)

**Test ROM**:
```
0xA300     I = 0x300
0x6010     V[0] = 16
0xF01E     I += V[0]  (I = 0x300 + 16 = 0x316)
```

**Expected**: I = 0x316

---

### Test 14: BCD Conversion (0xFX33)

**Test ROM**:
```
0x60AD     V[0] = 173 (0xAD)
0xA300     I = 0x300
0xF033     BCD(V[0]) at I  (store 1, 7, 3 at 0x300, 0x301, 0x302)
```

**Expected Memory**:
```
0x2300: 0x01 (hundreds)
0x2301: 0x07 (tens)
0x2302: 0x03 (ones)
```

---

### Test 15: Memory I/O (0xFX55, 0xFX65)

**Test ROM**:
```
0x6001     V[0] = 1
0x6102     V[1] = 2
0x6203     V[2] = 3
0xA300     I = 0x300
0xF255     Store V[0..2] at I  (write 1, 2, 3 to 0x300, 0x301, 0x302)
0xA300     I = 0x300
0x6000     V[0] = 0
0x6100     V[1] = 0
0x6200     V[2] = 0
0xF265     Load V[0..2] from I  (read back 1, 2, 3)
```

**Expected**: V[0] = 1, V[1] = 2, V[2] = 3

---

## Integration Test: Run PONG ROM

**Objective**: Full emulator test with a real game.

**Steps**:
1. Load PONG ROM (source externally)
2. Run emulator: `nano_vm.com`
3. Try to play PONG with keyboard
4. Observe: Paddles respond, ball moves, score updates

**Expected Behavior**:
- Game boots without crash
- Paddles respond to player input (arrow keys or QWERTY)
- Ball moves at consistent speed (60 FPS)
- Collision detection works
- Game is playable

---

## Performance Benchmarking

### Metric 1: Opcodes Per Second

**Measurement**:
```asm
; At main_loop entry, read BIOS tick
; At main_loop exit (after 1000 iterations), read BIOS tick again
; Calculate: opcodes_per_second = 1000 / elapsed_time
```

**Target**: >= 1000 opcodes/sec (conservative)

---

### Metric 2: Frame Rate (FPS)

**Measurement**:
- Count how many times DXYN is executed per second
- Each DXYN = one "frame" in CHIP-8 game context

**Target**: 60 FPS (or close)

---

### Metric 3: Memory Stability

**Objective**: Ensure emulator doesn't corrupt memory over time.

**Test**:
1. Run a ROM that repeatedly writes to memory
2. After 10,000 instructions, verify checksum of CHIP-8 RAM
3. Run for 100,000 instructions, verify again

**Expected**: Checksum unchanged (unless ROM itself modified memory)

---

## Failure Diagnosis Guide

### Symptom: Program crashes or CPU exception

**Checklist**:
- [ ] Segment registers properly initialized (DS, ES, SS)
- [ ] Stack pointer (SP) set to 0xFFFE
- [ ] No buffer overflow (opcode doesn't write beyond 0xFFFE)
- [ ] All jump tables properly sized

### Symptom: Graphics don't appear

**Checklist**:
- [ ] VGA Mode 13h properly initialized (INT 0x10, AX=0x0013)
- [ ] VRAM segment (ES) set to 0xA000
- [ ] VRAM offset calculations correct (Y * 320 + X)
- [ ] Color value correct (0x0F for white)

### Symptom: Keyboard doesn't work

**Checklist**:
- [ ] INT 16h properly called
- [ ] AH = 0x01 for non-blocking check
- [ ] ZF flag checked correctly
- [ ] ASCII codes mapped to CHIP-8 keys
- [ ] keyboard_state array at correct address (0x2F14)

### Symptom: Timers don't decrement

**Checklist**:
- [ ] BIOS segment 0x0040, offset 0x006C accessed correctly
- [ ] Previous tick compared correctly
- [ ] Counter incremented every tick
- [ ] Every 3 ticks, timers decremented

---

## Sign-Off Criteria (Phase 2 Complete)

**All tests PASSED:**
- [ ] System boots without crash
- [ ] All 35 opcodes execute without undefined behavior
- [ ] Arithmetic flags (V[F]) set correctly
- [ ] 60Hz timer synchronization verified
- [ ] Keyboard input maps correctly
- [ ] PONG ROM runs and is playable
- [ ] Memory remains stable under load
- [ ] Performance >= 1000 opcodes/sec

**Documentation Complete:**
- [ ] PHASE2_PLAN.md written
- [ ] PHASE2_IMPLEMENTATION.md written
- [ ] PHASE2_VALIDATION.md (this file) written
- [ ] Code comments explain all critical sections

**Ready for Phase 3: ROM Loading & Optimization**

