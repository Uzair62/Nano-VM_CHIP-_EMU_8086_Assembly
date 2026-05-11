# NANO-VM Phase 1 - Quick Reference

## Essential Files

```
phase1_main.asm              Main source code (.COM executable)
phase1_makefile              Build system
PORTING_PLAN.md              Master architecture spec
PHASE1_IMPLEMENTATION.md     Technical guide
PHASE1_VALIDATION.md         Test checklist
PHASE1_SUMMARY.md            Executive summary
QUICK_REFERENCE.md           This file
```

---

## Build & Run (30 seconds)

```bash
# Build
make -f phase1_makefile

# Run in emu8086
make -f phase1_makefile run

# Or manually
emu8086 phase1_nano_vm.com

# Expected: White IBM Logo on black VGA screen
```

---

## Memory Map Cheat Sheet

```
0x0100-0x1FFF   Code & ROM data
0x2000-0x20FF   Font data & stack space
0x2080-0x208F   Registers V0-VF
0x2200-0x27FF   Program RAM (ROM loaded at 0x2200 = 0x200 + 0x2000)
0xA000          VGA video memory (access via ES:DI)
0x6000-0xFFFE   Host stack (40KB gap buffer)
```

---

## Critical Code Patterns

### Fetch Opcode

```asm
fetch_opcode:
    mov si, [vm_pc]
    add si, 0x2000
    lodsw
    xchg ah, al                 ; **MUST SWAP**
    add word [vm_pc], 0x0002
    ret
```

### Draw Pixel at VGA (X, Y)

```asm
; Setup: ES = 0xA000
mov di, (Y * 320) + X
mov byte [es:di], 0xFF          ; White pixel
```

### Set VGA Mode 13h

```asm
mov al, 0x13
mov ah, 0x00
int 0x10
```

### Access CHIP-8 Register

```asm
; Get register Vx where x is in BX
mov si, vm_registers
add si, bx
mov al, [si]                    ; AL = Vx
```

---

## Debugging Tips

### Check Last Opcode
```
Memory at offset: last_opcode (somewhere in .data section)
Expected: 0xD000 or similar DXYN instruction
```

### Check PC
```
Memory: vm_pc (near start of .data)
Expected after startup: 0x0202 (incremented twice)
```

### Verify ROM Loaded
```
Memory region: 0x2200-0x221F
Expected: F0 90 90 F0 90 90 90 90 ... (rom_data bytes)
```

### Check VGA Memory
```
Segment: 0xA000 (video memory)
Expected: First 256 pixels contain white (0xFF) in pattern
```

---

## Opcode Dispatch Table

```asm
decode_dispatch extracts high nibble and routes:

0x0nnn  → .op_0nnn_   (Machine code / Clear screen)
0x1nnn  → .op_1nnn_   (Jump)
0x2nnn  → .op_2nnn_   (Call)
0x3xkk  → .op_3nnn_   (Skip if Vx == kk)
0x4xkk  → .op_4nnn_   (Skip if Vx != kk)
0x5xy0  → .op_5nnn_   (Skip if Vx == Vy)
0x6xkk  → .op_6nnn_   (Set Vx = kk)
0x7xkk  → .op_7nnn_   (Add kk to Vx)
0x8xy?  → .op_8nnn_   (Register operations)
0x9xy0  → .op_9nnn_   (Skip if Vx != Vy)
0xAnnn  → .op_annn_   (Set I = nnn)
0xBnnn  → .op_bnnn_   (Jump + V0)
0xCxkk  → .op_cnnn_   (Random & kk)
0xDxyn  → .op_dnnn_   (Draw sprite) **IMPLEMENTED**
0xEx??  → .op_ennn_   (Keyboard)
0xFx??  → .op_fnnn_   (Misc)
```

---

## Segment Registers

```asm
; Permanent (set once)
mov ax, 0x0000          ; DS = code/data segment
mov ds, ax

; Graphics operations only
mov ax, 0xA000          ; ES = video memory
mov es, ax
```

---

## Stack Safety

**SP initialized**: 0xFFFE (grows downward)
**VM state**: Ends at 0x27FF
**Gap**: 0x2800 to 0x5FFF = ~13 KB free
**Safe depth**: Up to ~6500 words (13 KB / 2)

Current code: ~10 nested calls max → ~20 bytes used → **SAFE**

---

## VGA Graphics Formula

```
Pixel address in VRAM = (Y * 320) + X

For 4:1 scaling:
  CHIP-8 pixel (cx, cy)
  → VGA block (cx*4, cy*4) to (cx*4+3, cy*4+3)
  → Draw 4x4 block of white pixels
```

---

## Common Register Assignments

```asm
AX      Opcode, temporary calculation
BX      Register index (often), loop counter
CX      Loop counter, shift amount
DX      Second operand, coordinate (DL for Y)
SI      Memory pointer (ROM, RAM)
DI      VRAM offset (video writes)
```

---

## INT Calls Used

```asm
INT 0x10 AH=00h     Set video mode (VGA Mode 13h)
INT 0x10 AH=0Dh     Write pixel (not used, direct VRAM faster)
INT 0x21 AH=02h     Print character (debugging only)
INT 0x21 AH=2Ch     Get system time (for delay)
INT 0x21 AH=4Ch     Exit program
INT 0x16 AH=00h     Read keyboard
INT 0x16 AH=01h     Check key available
```

---

## Phase 1 Features

✓ .COM executable (ORG 100h)
✓ VGA Mode 13h (320×200 graphics)
✓ Fetch-decode-execute loop
✓ DXYN sprite drawing
✓ 4:1 pixel scaling
✓ Big-endian byte swap
✓ Jump table dispatcher
✓ All 16 opcode families routable

---

## Phase 2 Work Items

Coming soon after Phase 1 validation:
- Full opcode implementation (all 16 families)
- Keyboard mapping (0x0-0xF keys)
- 60 Hz timer synchronization
- Testing with real CHIP-8 ROMs

---

## File Sizes

```
phase1_nano_vm.com          ~1-2 KB (executable)
phase1_main.asm             ~20 KB (source)
phase1_makefile             ~3 KB
Documentation (total)       ~1.5 MB (this bundle)
```

---

## Testing Checklist (30 seconds)

```
[ ] Build: make -f phase1_makefile
[ ] Run: emu8086 phase1_nano_vm.com
[ ] Wait: 5 seconds (allow boot)
[ ] Check: Black screen appears
[ ] Check: White pixels in top-left (logo)
[ ] Check: No crash in 30 seconds
[ ] Success!
```

---

## Key Insights

1. **Byte swap is mandatory** - `xchg ah, al` after every lodsw
2. **Segment discipline prevents crashes** - SP=0xFFFE keeps 40KB buffer
3. **Direct VRAM writes are fast** - No INT 10h per-pixel
4. **4:1 scaling keeps math simple** - All shifts, no multiplies
5. **Single dispatch loop is simple** - Linear comparisons, easy to debug

---

## Next Steps

1. Build and run Phase 1
2. Verify IBM Logo renders on VGA
3. Review PHASE1_VALIDATION.md if issues
4. Move to Phase 2 implementation

---

For detailed information:
- Architecture: PORTING_PLAN.md
- Implementation: PHASE1_IMPLEMENTATION.md
- Testing: PHASE1_VALIDATION.md
- Summary: PHASE1_SUMMARY.md

**Happy emulating!**
