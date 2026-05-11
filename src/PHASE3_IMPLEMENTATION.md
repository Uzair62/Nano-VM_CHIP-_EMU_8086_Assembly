# PHASE 3: HARDWARE INTEGRATION & POLISH
## Implementation Technical Guide

**Document Version**: 1.0  
**Phase Status**: IMPLEMENTATION ACTIVE  
**Objectives**: ROM Loading, PC Speaker Sound, Performance Throttling

---

## 1. ROM LOADING (Priority 1)

### Objective
Load external CHIP-8 ROM files (.ch8) from the emu8086 file system instead of hardcoding the IBM Logo.

### DOS Interrupt 21h File I/O

#### Open File (AH=3Dh)
```asm
mov dx, rom_filename        ; DS:DX = pointer to filename string (null-terminated)
mov al, 0x00               ; AL = access mode (00h = read-only)
mov ah, 0x3D
int 0x21

; Output: AX = file handle (if success), CF=0
;         AX = error code (if error), CF=1
```

**Error Codes**:
- 02h: File not found
- 03h: Path not found
- 04h: Too many open files
- 05h: Access denied

#### Read File (AH=3Fh)
```asm
mov bx, file_handle         ; File handle from open operation
mov cx, bytes_to_read       ; Number of bytes to read
mov dx, buffer_address      ; DS:DX = buffer to read into
mov ah, 0x3F
int 0x21

; Output: AX = bytes actually read (if success), CF=0
;         AX = error code (if error), CF=1
```

#### Close File (AH=3Eh)
```asm
mov bx, file_handle         ; File handle
mov ah, 0x3E
int 0x21

; Output: AX = 0 (success), CF=0
;         AX = error code (if error), CF=1
```

### ROM Loading Sequence in phase3_main.asm

1. **Call rom_load subroutine**
   ```asm
   call rom_load
   jc .load_fallback    ; If CF=1, ROM load failed
   ```

2. **rom_load subroutine does**:
   - Open GAME.CH8 with INT 21h AH=3Dh
   - Read file into 0x0200 with INT 21h AH=3Fh
   - Close file with INT 21h AH=3Eh
   - Validate ROM size (max 3840 bytes)
   - Return CF=0 on success, CF=1 on failure

3. **Fallback behavior**:
   - If ROM not found, display IBM Logo (Phase 1 behavior)
   - User can replace ROM by placing GAME.CH8 in emu8086 directory

### Memory Layout for ROM
```
DS:0x0200-0x0FFF: CHIP-8 Program RAM (4KB total)
                  Maximum ROM size: 3840 bytes (0xF00)
                  
DS:0x0200: First opcode (executed after init)
DS:0x0201: Second opcode byte
...
DS:0x0FFF: Last possible ROM byte
```

### Testing ROM Loading

#### Test Case 1: GAME.CH8 Present
1. Create binary file with CHIP-8 opcodes
2. Place in emu8086 working directory as GAME.CH8
3. Run emulator
4. **Expected**: ROM loads, emulator executes ROM code

#### Test Case 2: GAME.CH8 Missing
1. Remove GAME.CH8 from directory
2. Run emulator
3. **Expected**: Display "ROM Not Found" message, show IBM Logo fallback

#### Test Case 3: ROM Too Large
1. Create GAME.CH8 file > 3840 bytes
2. Run emulator
3. **Expected**: Display "ROM Too Large" message, exit gracefully

---

## 2. PC SPEAKER SOUND (Priority 2)

### Objective
Enable audible sound output via the PC speaker when sound_timer > 0.

### Hardware Overview

#### Programmable Interval Timer (PIT) 8253
- **Port 0x40**: Counter 0 (system timer, read-only)
- **Port 0x42**: Counter 2 (speaker frequency, programmable)
- **Port 0x43**: Control word register (timer mode selection)

#### System Control Port (0x61)
- **Bit 0**: Speaker data (1 = enable, 0 = disable)
- **Bit 1**: Speaker gate (1 = enable, 0 = disable)

#### Frequency Calculation
```
Divisor = 1193180 Hz (PIT base frequency) / Desired_Frequency_Hz

Examples:
  880 Hz (high note):   divisor = 1193180 / 880 = 1356 (0x054C)
  440 Hz (A note):      divisor = 1193180 / 440 = 2711 (0x0A97)
  200 Hz (low note):    divisor = 1193180 / 200 = 5966 (0x174E)
```

### Sound Output Algorithm

**Pseudocode**:
```
Each 60Hz tick:
  If sound_timer > 0:
    - Decrement sound_timer
    - If sound_timer was > 0 (not just became 0):
      - Load frequency into PIT (Port 0x42)
      - Enable speaker via Port 0x61
  Else (sound_timer == 0):
    - Disable speaker via Port 0x61
```

### Assembly Implementation

#### Enable Speaker at 880 Hz
```asm
speaker_enable_880hz:
    ; Set frequency divisor via PIT Counter 2
    mov al, 0x0C           ; 00001100b = Counter 2, LSB then MSB
    out 0x43, al           ; Write control word to Port 43h
    
    ; Load divisor 1356 (0x054C) into Counter 2
    mov al, 0x4C           ; LSB = 0x4C
    out 0x42, al
    
    mov al, 0x05           ; MSB = 0x05
    out 0x42, al
    
    ; Enable speaker via Port 61h
    in al, 0x61            ; Read current control bits
    or al, 0x03            ; Set bits 0-1 (speaker data and gate)
    out 0x61, al
    
    ret
```

#### Disable Speaker
```asm
speaker_disable:
    in al, 0x61
    and al, 0xFC           ; Clear bits 0-1
    out 0x61, al
    ret
```

### Integration with Main Loop

In the main emulation loop (every 60Hz tick):

```asm
; Check and decrement sound_timer
cmp byte [chip8_sound_timer], 0
je .check_delay_timer       ; If zero, skip speaker

dec byte [chip8_sound_timer] ; Decrement timer

; Enable/disable speaker based on new timer value
cmp byte [chip8_sound_timer], 0
je .disable_speaker
call speaker_enable_880hz    ; Enable speaker
jmp .check_delay_timer

.disable_speaker:
call speaker_disable
```

### Testing Sound Output

#### Test Case 1: FNNN Opcode (Set Sound Timer)
1. Create ROM with `0xF118` (sound_timer = V[1])
2. Set V[1] = 0xFF (255)
3. Run emulator
4. **Expected**: Speaker produces steady tone for ~4.25 seconds (255/60 Hz)

#### Test Case 2: Sound Duration Accuracy
1. Measure actual sound duration with timer
2. Compare with expected: N_cycles / 60 Hz
3. **Expected**: Within 1-2% accuracy margin

#### Test Case 3: Multiple Sound Events
1. Create ROM that sets sound_timer multiple times
2. Verify speaker stops/starts correctly
3. **Expected**: Clean audio transitions without pops

---

## 3. PERFORMANCE THROTTLING (Priority 3)

### Objective
Add configurable instruction-per-frame cap to prevent ROMs from running too fast.

### Algorithm Overview

**Challenge**: Different host CPUs execute instructions at different speeds. Without throttling:
- Fast CPU: ROM runs 2-3x faster, games unplayable
- Slow CPU: ROM runs slowly but still inconsistent

**Solution**: Limit instructions per 60Hz frame to a constant number.

```
Default: 10 instructions per frame = 600 instructions per second (600 IPS)
Fast:    20 instructions per frame = 1200 IPS
Slow:    5 instructions per frame = 300 IPS
```

### State Variables

```asm
instructions_per_frame  db 10   ; User-configurable (range: 5-20)
instruction_counter     db 0    ; Counter within current frame
last_timer_byte        db 0    ; Last BIOS timer sample
```

### Main Loop Throttling Logic

```asm
.main_loop:
    ; Sample BIOS timer
    mov ax, 0x0040
    mov ds, ax
    mov al, [0x006C]        ; Get timer low byte
    mov ds, 0x0000
    
    cmp al, [last_timer_byte]
    je .fetch_opcode        ; Same tick, continue execution
    
    ; New tick detected: reset counter
    mov [last_timer_byte], al
    mov byte [instruction_counter], 0
    
    ; Decrement timers (sound/delay)...

.fetch_opcode:
    ; Check if frame instruction limit reached
    mov al, [instruction_counter]
    cmp al, [instructions_per_frame]
    jge .main_loop          ; Limit reached, wait for next frame
    
    ; Fetch, decode, execute opcode...
    
.next_instruction:
    inc byte [instruction_counter]
    jmp .main_loop
```

### User Configuration

At startup, display speed selection menu:

```
Speed [S]low/[D]efault/[F]ast: _
```

- **S (Slow)**: `instructions_per_frame = 5`
- **D (Default)**: `instructions_per_frame = 10`
- **F (Fast)**: `instructions_per_frame = 20`

Implementation:
```asm
mov ah, 0x08            ; Read character (non-echoing)
int 0x21

cmp al, 'S'
je .speed_slow
cmp al, 'F'
je .speed_fast

; Default
mov byte [instructions_per_frame], 10
```

### Testing Throttling

#### Test Case 1: Speed Selection
1. Run emulator with 'S' (slow)
2. Run emulator with 'D' (default)
3. Run emulator with 'F' (fast)
4. **Expected**: Games run at 0.5x, 1x, and 2x speed respectively

#### Test Case 2: Frame Consistency
1. Measure time between instruction counters resetting
2. Should be ~16.67ms (60 Hz)
3. **Expected**: Variance < 2ms

#### Test Case 3: Game Playability
1. Run Pong or Tetris at default speed
2. Game should be playable
3. **Expected**: Smooth, consistent gameplay

---

## Building Phase 3

### Compile Command
```bash
nasm -f bin -o nano_vm.com phase3_main.asm
```

### Output
- `nano_vm.com`: 64KB single-segment executable

### Verify Build
```bash
ls -la nano_vm.com
hexdump -C nano_vm.com | head -20
```

---

## Known Limitations & Future Work

### Phase 3 Scope
✓ ROM loading from GAME.CH8  
✓ PC speaker sound output  
✓ Instruction throttling with user config  

### Future Enhancements (Phase 4+)
- ROM selection menu (multiple files)
- Sound frequency adjustment
- Save/load game state
- Debugger integration

---

## Troubleshooting

### ROM Not Loading
- Check GAME.CH8 filename (case-sensitive)
- Verify file exists in emu8086 working directory
- Check file size (max 3840 bytes)
- Review dos error messages: "ROM Not Found" or "ROM Too Large"

### No Sound Output
- Verify `sound_timer` is being set (FX18 opcode)
- Check speaker enable logic (Port 61h bits 0-1)
- Test with simple ROM: set V[0]=255, call 0xF018
- Verify 8086 emulator supports I/O port operations

### Game Runs Too Fast/Slow
- Adjust `instructions_per_frame` variable
- Default 10 may need tweaking for specific ROM
- Verify BIOS timer is functioning (18.2 Hz clock)

---

**End of Phase 3 Technical Implementation Guide**
