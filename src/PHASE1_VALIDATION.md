# NANO-VM Phase 1 - Validation Checklist

## Build Verification

### Compilation

- [ ] `make -f phase1_makefile` completes without errors
- [ ] `phase1_nano_vm.com` is generated (~1-2 KB)
- [ ] No NASM assembly errors or warnings
- [ ] Binary starts with correct .COM header structure

### Binary Size Check

```bash
make -f phase1_makefile size
```

Expected output: Binary < 5 KB (includes code, data, and ROM)

---

## Runtime Verification (emu8086)

### Step 1: Launch

```bash
emu8086 phase1_nano_vm.com
```

### Step 2: Initial State

Expected observations:
- [ ] CPU starts at CS:IP = 0000:0100 (standard .COM entry)
- [ ] emu8086 window shows emulation in progress
- [ ] No immediate crash or hang (allow up to 2 seconds for initialization)

### Step 3: Graphics Mode Initialization

Expected observations:
- [ ] Screen transitions to VGA Mode 13h (320×200 graphics, black background)
- [ ] No snow/corruption in video memory
- [ ] Screen remains stable (not flickering rapidly)

### Step 4: IBM Logo Rendering

Expected observations:
- [ ] White pixels appear in upper-left corner (position 0,0)
- [ ] Pixels form recognizable pattern (roughly square shape, 32×32 pixels on screen)
- [ ] Logo remains static (program is in infinite loop)

**Logo should look similar to**:
```
████  ████
█  █  █  █
████  █   █
█     ███ █
█     █   █
█     █   █
█     █   █
████  ████
```

(Each character represents a 4×4 VGA pixel block)

### Step 5: Stability Check

- [ ] Program runs for 30+ seconds without crashing
- [ ] CPU usage is stable (not spiking)
- [ ] No memory corruption visible (other parts of screen remain black)

---

## Detailed Verification Points

### Memory Layout

Inspect memory using emu8086 debugger:

**VM State Region (starting at 0x2000)**:
```
Offset  Content              Expected Value
─────────────────────────────────────────────
0x2000  vm_pc (2 bytes)      0x0202 (after first fetch/increment)
0x2002  vm_sp (1 byte)       0x00   (stack empty)
0x2004  vm_i_register        0x0000 (usually unchanged)
0x2006  vm_delay_timer       0x00   (decremented each frame)
0x2007  vm_sound_timer       0x00
0x2008  vm_registers[0-15]   All 0x00 (registers cleared)
```

**ROM Data Region (0x2200-0x221F)**:
```
0x2200  F0 90 90 F0 90 90 90 90 F0 10 F0 80 F0 80 F0 10
0x2210  10 F0 10 10 10 10 10 10 F0 90 F0 90 F0 90 90 90
```

(Should match `rom_data` in phase1_main.asm)

### VGA Video Memory

Inspect memory at segment 0xA000 (VGA memory):

**Expected Pattern** (first DXYN draw):
- [ ] Pixels 0x0000-0x013F (top-left 320×32 pixels) contain white (0xFF) in pattern
- [ ] Rest of screen (0x0140+) remains black (0x00)

**Pixel Block Calculation**:
- CHIP-8 sprite is 8 pixels × 8 rows
- Each CHIP-8 pixel = 4×4 VGA pixels
- Total VGA area: 32×32 pixels (0x0-0x1F X, 0x0-0x1F Y)

---

## Opcode Execution Trace

For detailed debugging, add console output in `opcode_draw_sprite`:

```asm
; Add after extracting X, Y, N:
mov ah, 0x02
mov dl, 'D'
int 0x21
; ... repeat for other debug points
```

Expected execution sequence:
1. Fetch opcode at 0x2200: 0xD000 (draw at V0, V0)
2. Decode: Family 0xD, extract x=0, y=0, n=0
3. Draw: 8 rows × 8 pixels (scaled to 32×32 VGA area)
4. Increment PC to 0x0202
5. Loop back to fetch (infinite loop)

---

## Common Issues & Troubleshooting

### Issue: "Black screen, nothing happens"

**Possible causes**:
1. VGA initialization failed
   - [ ] Check that INT 10h AH=0x00 is called correctly
   - [ ] Verify AL = 0x13 before interrupt
   - [ ] Use emu8086 memory viewer to check ES register (should be set to 0xA000)

2. ROM not loaded at 0x2200
   - [ ] Verify `load_rom_into_memory` loop copies 32 bytes
   - [ ] Check memory 0x2200-0x221F in debugger

3. Infinite loop in main loop, but decode_dispatch skips DXYN
   - [ ] Check opcode at 0x200 (after byte swap)
   - [ ] Expected: 0xD000 (draw at 0,0)

### Issue: "Garbled pixels, wrong pattern"

**Possible causes**:
1. Big-endian fetch not working
   - [ ] Verify `xchg ah, al` is executed after lodsw
   - [ ] Check last_opcode variable after first fetch
   - [ ] Expected: 0xD000, not 0x00D0

2. Scaling math incorrect
   - [ ] Verify `shl bx, 2` (multiply by 4) is correct
   - [ ] Check VGA offset calculation: `(Y * 320) + X`

3. Color wrong (black instead of white)
   - [ ] Verify AL = 0xFF in draw_4x4_block
   - [ ] Check that ES is set to 0xA000

### Issue: "Crash after launch, emu8086 stops"

**Possible causes**:
1. Stack collision
   - [ ] Verify SP = 0xFFFE at startup (40KB buffer)
   - [ ] Check that no nested subroutine calls exceed ~100 pushes

2. Segment violation
   - [ ] Verify all DS references stay below 0x4000
   - [ ] Verify all ES:DI writes to VGA stay below 0xFA00 (64KB limit)

3. Infinite loop in decode_dispatch
   - [ ] Ensure all CMP/JE pairs have matching labels
   - [ ] Verify .decode_done exists and is reachable

---

## Performance Baseline (Phase 1)

Expected metrics (in emu8086 at 10 MHz simulation):

| Metric | Value | Note |
|---|---|---|
| Frame time | ~16.7ms | (60 Hz target) |
| Draw time | ~5-8ms | sprite rasterization |
| Fetch-decode time | ~1ms | simple dispatch |
| Loop overhead | ~2ms | register updates |

**Acceptable range**: 10-30 FPS visible motion. If much slower, check for infinite loops or excessive PUSH/POP instructions.

---

## Passing Criteria

Phase 1 is considered **PASS** when ALL of the following are true:

1. ✓ Binary builds successfully (phase1_nano_vm.com exists)
2. ✓ emu8086 launches without crash
3. ✓ VGA Mode 13h initializes (black 320×200 screen)
4. ✓ White pixels appear in upper-left corner (IBM logo rendering)
5. ✓ Logo remains stable for 30+ seconds
6. ✓ Memory layout matches expected offsets
7. ✓ Last opcode shows correct fetch (0xD000 or similar DXYN)

---

## Passing Criteria: FAILURE SCENARIOS

Phase 1 is considered **FAIL** if any of these occur:

1. ✗ Binary does not compile (NASM error)
2. ✗ emu8086 crashes immediately (no VGA mode change)
3. ✗ Screen shows unrelated garbage (not black, not logo pattern)
4. ✗ Logo pattern exists but colors wrong (black on white, inverted, etc.)
5. ✗ Program crashes within 10 seconds
6. ✗ Memory corruption detected (beyond expected VRAM region)

---

## Sign-Off

After passing all checks above, fill in:

```
Date:              ________________
Tester:            ________________
emu8086 Version:   ________________
Build Command:     make -f phase1_makefile
Test Duration:     30+ seconds
Result:            [ ] PASS  [ ] FAIL

Notes:
_________________________________________________________________
_________________________________________________________________
```

---

## Next Steps (Phase 2)

If Phase 1 PASSES:

1. [ ] Archive phase1_nano_vm.com as baseline
2. [ ] Begin implementing full opcode set (all 16 families)
3. [ ] Add keyboard input handling
4. [ ] Implement 60 Hz timer synchronization
5. [ ] Test with PONG or other CHIP-8 ROMs

If Phase 1 FAILS:

1. [ ] Debug memory layout with emu8086 memory viewer
2. [ ] Check each subroutine step-by-step in debugger
3. [ ] Review segment setup (DS, ES, SS) in CPU window
4. [ ] Refer to PORTING_PLAN.md Pillar A, B, C for architecture review
