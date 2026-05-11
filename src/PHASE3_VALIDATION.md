# PHASE 3: VALIDATION & TESTING FRAMEWORK
## Comprehensive Test Specification & Sign-Off

**Document Version**: 1.0  
**Phase Status**: VALIDATION READY  
**Success Criteria**: All three priorities verified at 100%

---

## PART 1: ROM LOADING VALIDATION

### 1.1 Basic ROM Load Test

**Test ID**: LOAD-001  
**Category**: File I/O Operations  
**Objective**: Verify successful ROM loading from disk

**Setup**:
1. Create binary file `GAME.CH8` (minimum 10 bytes, maximum 3840 bytes)
2. Place in emu8086 working directory
3. Content: `00 E0 12 00 34 56 78 9A BC DE F0` (example opcodes)

**Procedure**:
1. Start emulator: `emu8086 nano_vm.com`
2. When prompted for speed, enter 'D' (default)
3. Observe program execution

**Expected Result**:
- No "ROM Not Found" error message
- Emulator proceeds to main loop
- PC register = 0x0200 (start of loaded ROM)
- Memory at 0x0200 contains first opcode byte (0x00)

**Verification**:
- [ ] ROM file opened successfully
- [ ] ROM file read into memory
- [ ] PC points to 0x0200
- [ ] No error message displayed
- [ ] Emulator continues to main loop

---

### 1.2 ROM Not Found Error

**Test ID**: LOAD-002  
**Category**: Error Handling  
**Objective**: Verify graceful error handling when ROM missing

**Setup**:
1. Delete GAME.CH8 from working directory
2. Ensure emulator cannot find file

**Procedure**:
1. Start emulator
2. When prompted for speed, enter 'D'
3. Observe error handling

**Expected Result**:
- Display message: "ROM Not Found"
- Emulator displays IBM Logo fallback
- Program continues without crashing
- User can see logo and know ROM load failed

**Verification**:
- [ ] Error message displayed
- [ ] Message is clear and readable
- [ ] Fallback to IBM Logo works
- [ ] No system crash
- [ ] Graceful degradation

---

### 1.3 ROM Size Validation

**Test ID**: LOAD-003  
**Category**: Input Validation  
**Objective**: Verify ROM size enforcement (max 3840 bytes)

**Setup**:
1. Create GAME.CH8 with exactly 3840 bytes (maximum valid)
2. Create GAME2.CH8 with 3841 bytes (one byte over)

**Procedure for Valid Size**:
1. Copy GAME.CH8 as GAME.CH8
2. Start emulator
3. Observe successful load

**Expected Result** (3840 bytes):
- Successful load
- No error message
- Emulator executes ROM

**Procedure for Invalid Size**:
1. Copy GAME2.CH8 as GAME.CH8
2. Start emulator
3. Observe error handling

**Expected Result** (3841 bytes):
- Display message: "ROM Too Large"
- Fallback to IBM Logo
- No memory corruption
- System stable

**Verification**:
- [ ] 3840-byte ROM loads successfully
- [ ] 3841-byte ROM rejected
- [ ] Boundary correctly enforced at 3840
- [ ] Error message specific ("ROM Too Large")
- [ ] No memory overflow

---

### 1.4 ROM Opcode Execution

**Test ID**: LOAD-004  
**Category**: ROM Functionality  
**Objective**: Verify that loaded ROM opcodes execute correctly

**Setup**:
1. Create test ROM with known opcode sequence:
   ```
   0x200: 0x6005   (Set V[0] = 0x05)
   0x202: 0x7001   (Add 0x01 to V[0])
   0x204: 0x00E0   (Clear screen)
   0x206: 0x1200   (Jump to 0x200)
   ```
2. Save as GAME.CH8

**Procedure**:
1. Load and run ROM
2. After 3-4 frames, inspect V[0] register
3. Verify screen cleared

**Expected Result**:
- V[0] = 0x06 (initialized to 0x05, incremented by 0x01)
- Screen cleared (DXYN not called, but 00E0 should work)
- PC cycling between 0x200 and 0x206
- No errors in execution

**Verification**:
- [ ] Arithmetic opcodes execute
- [ ] Screen clear opcode (00E0) works
- [ ] Jump opcode (1NNN) works
- [ ] Register values correct
- [ ] No crash on opcode execution

---

## PART 2: PC SPEAKER SOUND VALIDATION

### 2.1 Speaker Enable Test

**Test ID**: SOUND-001  
**Category**: Hardware I/O  
**Objective**: Verify speaker enable/disable functionality

**Setup**:
1. Create test ROM that sets sound_timer:
   ```
   0x200: 0x60FF   (Set V[0] = 0xFF)
   0x202: 0xF018   (Set sound_timer = V[0] = 0xFF)
   0x204: 0x1204   (Jump to 0x204, infinite loop)
   ```
2. Save as GAME.CH8
3. Use speaker-enabled emulator environment

**Procedure**:
1. Run emulator with ROM
2. Listen for audible tone
3. Observe duration (~4.25 seconds for 255 cycles at 60Hz)
4. After tone stops, observe silence

**Expected Result**:
- Hear continuous tone immediately after startup
- Tone duration: 255 / 60 Hz ≈ 4.25 seconds
- Tone stops cleanly without pops/glitches
- Frequency: 880 Hz (identifiable pitch)

**Verification**:
- [ ] Audible tone present
- [ ] Tone starts at correct time (sound_timer set)
- [ ] Tone duration approximately correct
- [ ] No audio glitches
- [ ] Tone frequency identifiable as 880 Hz

---

### 2.2 Sound Timer Decrement

**Test ID**: SOUND-002  
**Category**: Timer Management  
**Objective**: Verify sound_timer decrements at 60Hz rate

**Setup**:
1. Create ROM that sets sound_timer to known value:
   ```
   0x200: 0x60FF   (V[0] = 0xFF)
   0x202: 0xF018   (sound_timer = V[0])
   0x204: 0xF007   (V[0] = delay_timer, trick to read frame count)
   0x206: 0x1204   (Loop)
   ```

**Procedure**:
1. Start emulator
2. Count seconds until sound stops
3. Calculate: expected_seconds = (sound_timer_initial - 0) / 60 Hz

**Expected Result**:
- Sound duration: 255 / 60 = 4.25 seconds
- Actual duration within ±0.2 seconds (18.2 Hz BIOS tick approximation)
- Decrement rate: ~60 per second

**Verification**:
- [ ] Timer decrements at approximately 60Hz
- [ ] Duration matches 1 cycle = 16.67ms
- [ ] No skipped ticks
- [ ] Smooth, continuous decrement

---

### 2.3 Multiple Sound Events

**Test ID**: SOUND-003  
**Category**: Rapid Sound Changes  
**Objective**: Verify speaker handles rapid sound timer updates

**Setup**:
1. Create ROM with sound timer pulsing:
   ```
   0x200: 0x6050   (V[0] = 0x50)
   0x202: 0xF018   (sound_timer = 0x50)
   0x204: 0x1210   (Jump to next)
   0x210: 0x6020   (V[0] = 0x20, after ~1.3s)
   0x212: 0xF018   (sound_timer = 0x20)
   0x214: 0x1214   (Loop)
   ```

**Procedure**:
1. Run ROM
2. Listen for first tone (~0.83s)
3. Hear brief silence
4. Listen for second tone (~0.33s)
5. Observe smooth transitions

**Expected Result**:
- First tone: 0x50 / 60 ≈ 0.83 seconds
- Brief silence: < 0.1 seconds
- Second tone: 0x20 / 60 ≈ 0.33 seconds
- Clean transitions without pops

**Verification**:
- [ ] Multiple sound events handled correctly
- [ ] Timing accurate for each event
- [ ] No audio corruption between events
- [ ] Speaker state changes cleanly

---

### 2.4 Speaker Port Access Verification

**Test ID**: SOUND-004  
**Category**: Hardware Register Access  
**Objective**: Verify correct I/O port operations

**Ports Used**:
- 0x42: PIT Counter 2 (speaker frequency divisor)
- 0x43: PIT Control Word (timer mode selection)
- 0x61: System Control Port (speaker enable)

**Procedure**:
1. Instrument emulator with port access logging
2. Run ROM that triggers sound
3. Capture all port write operations
4. Verify sequence:
   ```
   1. OUT 0x43, 0x0C          (Select Counter 2, LSB+MSB)
   2. OUT 0x42, 0x4C          (LSB of divisor)
   3. OUT 0x42, 0x05          (MSB of divisor)
   4. IN  0x61, AL             (Read control port)
   5. OR  AL, 0x03             (Set speaker bits)
   6. OUT 0x61, AL             (Enable speaker)
   ```

**Expected Result**:
- All port operations executed
- Correct sequence maintained
- Divisor = 0x054C (880 Hz)
- Speaker enable bit set

**Verification**:
- [ ] Port sequence correct
- [ ] Divisor value correct (0x054C for 880 Hz)
- [ ] Speaker enable/disable bits correct
- [ ] No spurious port accesses

---

## PART 3: PERFORMANCE THROTTLING VALIDATION

### 3.1 Default Speed (10 IPS)

**Test ID**: THROTTLE-001  
**Category**: Performance Control  
**Objective**: Verify default instruction throttling at 10 IPS

**Setup**:
1. Create ROM with measurable instruction sequence
2. Default configuration: `instructions_per_frame = 10`

**Procedure**:
1. Start emulator, select 'D' (default)
2. Run ROM for 10 seconds
3. Count execution frames (each frame = ~16.67ms)
4. Measure: frames * instructions_per_frame = total instructions executed

**Expected Result**:
- 10 frames/second × 10 instructions/frame = 100 IPS average
- Total instructions in 10 seconds: ~100
- Actual: 95-105 (±5% tolerance for BIOS timer jitter)

**Verification**:
- [ ] Frame rate stable at ~60 Hz
- [ ] Instructions per frame: 10
- [ ] No instruction skips
- [ ] Consistent timing across frames

---

### 3.2 Slow Speed (5 IPS)

**Test ID**: THROTTLE-002  
**Category**: Speed Selection  
**Objective**: Verify slow speed mode (5 IPS)

**Setup**:
1. Create measurable ROM
2. Configuration: `instructions_per_frame = 5` (via 'S' selection)

**Procedure**:
1. Start emulator, select 'S' (slow)
2. Run ROM for 10 seconds
3. Count instructions executed
4. Compare with default speed (should be 50% slower)

**Expected Result**:
- 5 frames/second × 10 instructions/frame... wait, that's not right
- Actually: 60 frames/second, but only 5 instructions per frame = 300 IPS
- Wait, recalculate: 60 ticks/sec, 5 instructions/tick = 300 IPS
- Actually comparing: Default = 600 IPS, Slow should be ~300 IPS (50% of default)

**Corrected Expectation**:
- Total instructions: 50 per second (since each frame is 1/60 sec and we do 5 instructions)
- No wait: 60 frames/sec × 5 instructions = 300 instructions/sec
- In 10 seconds: 3000 instructions (vs 6000 for default)

**Verification**:
- [ ] Slow speed enabled via 'S' key
- [ ] `instructions_per_frame` = 5
- [ ] Execution is visibly slower
- [ ] Game (if loaded) runs at ~50% normal speed

---

### 3.3 Fast Speed (20 IPS)

**Test ID**: THROTTLE-003  
**Category**: Speed Selection  
**Objective**: Verify fast speed mode (20 IPS)

**Setup**:
1. Create measurable ROM
2. Configuration: `instructions_per_frame = 20` (via 'F' selection)

**Procedure**:
1. Start emulator, select 'F' (fast)
2. Run ROM for 10 seconds
3. Count instructions executed
4. Compare with default speed (should be 2x faster)

**Expected Result**:
- 60 frames/sec × 20 instructions/frame = 1200 IPS
- In 10 seconds: 12000 instructions (vs 6000 for default)
- Execution appears 2x faster

**Verification**:
- [ ] Fast speed enabled via 'F' key
- [ ] `instructions_per_frame` = 20
- [ ] Execution is visibly faster
- [ ] Game (if loaded) runs at ~200% normal speed

---

### 3.4 Instruction Counter Reset

**Test ID**: THROTTLE-004  
**Category**: Frame Synchronization  
**Objective**: Verify instruction counter resets each frame

**Setup**:
1. Instrument code to log `instruction_counter` value
2. Monitor BIOS timer transitions

**Procedure**:
1. Run emulator
2. Log instruction_counter value on each BIOS timer tick
3. Verify counter resets when new tick detected

**Expected Result**:
- Each frame starts with `instruction_counter = 0`
- Increments from 0 to `instructions_per_frame - 1`
- Resets to 0 when new BIOS tick detected
- No counter overflow
- Consistent pattern across all frames

**Verification**:
- [ ] Counter resets on each frame
- [ ] Counter increments correctly
- [ ] Frame boundaries align with BIOS ticks
- [ ] No lost or double-counted instructions

---

### 3.5 Game Playability Test (Pong)

**Test ID**: THROTTLE-005  
**Category**: End-to-End  
**Objective**: Verify game is playable with default throttling

**Setup**:
1. Obtain Pong ROM (pong.ch8)
2. Place in working directory as GAME.CH8
3. Default configuration: `instructions_per_frame = 10`

**Procedure**:
1. Start emulator, select 'D' (default)
2. Play Pong for 2-3 minutes
3. Evaluate gameplay:
   - Ball speed reasonable?
   - Paddle response smooth?
   - No game speed variations?

**Expected Result**:
- Pong is playable at normal speed
- Ball moves at consistent velocity
- Paddle responds immediately to input
- No noticeable frame drops or hitches
- Game is fun and engaging

**Verification**:
- [ ] Game runs at playable speed
- [ ] No visible stuttering
- [ ] Input response is immediate
- [ ] Ball physics reasonable
- [ ] Consistent gameplay experience

---

## PART 4: INTEGRATION TESTS

### 4.1 ROM + Sound Combination

**Test ID**: INTEG-001  
**Category**: Multi-Feature  
**Objective**: Verify ROM loading and sound work together

**Setup**:
1. Create test ROM with:
   - Initial graphics (draw IBM logo)
   - Set sound_timer to 0x80
   - Wait in loop
2. Save as GAME.CH8

**Procedure**:
1. Start emulator
2. Select default speed
3. Observe graphics + sound simultaneously

**Expected Result**:
- ROM loads successfully
- Graphics display (IBM logo drawn)
- Sound plays for ~2.1 seconds (128/60)
- Both systems work without interference

**Verification**:
- [ ] ROM loads correctly
- [ ] Graphics render properly
- [ ] Sound plays simultaneously
- [ ] No performance degradation
- [ ] No memory corruption

---

### 4.2 All Three Priorities Combined

**Test ID**: INTEG-002  
**Category**: Full System  
**Objective**: Verify ROM + Sound + Throttling work together

**Setup**:
1. Create comprehensive test ROM:
   - Load ROM from disk (verify via opcode execution)
   - Set sound_timer (0x80)
   - Draw graphics (DXY4 opcode)
   - Loop indefinitely
2. Test at slow, default, and fast speeds

**Procedure**:
1. Run at slow speed ('S')
   - Graphics slow
   - Sound pitch remains 880 Hz
   - Duration: 2.1 seconds
2. Run at default speed ('D')
   - Graphics normal
   - Sound normal
3. Run at fast speed ('F')
   - Graphics fast
   - Sound still correct duration

**Expected Result**:
- All three features work together seamlessly
- No conflicts between systems
- Speed adjustment affects game, not sound
- Consistent behavior across all speeds

**Verification**:
- [ ] ROM loads and executes
- [ ] Sound plays at all speeds
- [ ] Graphics render correctly
- [ ] No feature interference
- [ ] Performance acceptable

---

## PART 5: EDGE CASES & ERROR CONDITIONS

### 5.1 Disk I/O Error Handling

**Test ID**: EDGE-001  
**Category**: Robustness  
**Objective**: Handle disk I/O failures gracefully

**Scenarios**:
1. GAME.CH8 exists but is 0 bytes
2. GAME.CH8 corrupted (invalid binary)
3. Filename typo (GmE.CH8)
4. File locked by another process

**Expected Behavior**:
- 0-byte file: Load accepted (valid but empty ROM)
- Corrupted file: Load accepted (no validation in Phase 3)
- Typo: "ROM Not Found" error, fallback to IBM Logo
- Locked file: "Access Denied" or "ROM Not Found" error

**Verification**:
- [ ] No crashes on file errors
- [ ] Appropriate error message displayed
- [ ] Fallback to IBM Logo when appropriate
- [ ] System remains stable

---

### 5.2 Sound Timer Edge Cases

**Test ID**: EDGE-002  
**Category**: Timer Correctness  
**Objective**: Verify sound_timer behavior at boundaries

**Test Cases**:
1. Set sound_timer = 0 (no sound)
2. Set sound_timer = 1 (beep for 1 frame)
3. Set sound_timer = 255 (maximum)

**Expected Results**:
1. No audible sound
2. Brief beep for ~16.67ms
3. Extended tone for ~4.25 seconds

**Verification**:
- [ ] Zero timer produces no sound
- [ ] Single-frame timer works
- [ ] Maximum timer works
- [ ] No overflow/wraparound

---

### 5.3 Instruction Counter Overflow

**Test ID**: EDGE-003  
**Category**: Data Integrity  
**Objective**: Verify counter doesn't overflow

**Setup**:
1. Set `instructions_per_frame = 255` (maximum byte value)
2. Run emulator for extended period

**Expected Result**:
- Counter increments from 0 to 254
- Resets to 0 on frame boundary
- No overflow beyond 255
- Counter remains single byte

**Verification**:
- [ ] Counter is single byte (0-255)
- [ ] No overflow into next memory location
- [ ] Frame boundaries correct
- [ ] Memory integrity maintained

---

## PHASE 3 SUCCESS CRITERIA

### Final Sign-Off Checklist

**ROM Loading (Priority 1)**:
- [ ] GAME.CH8 loads successfully
- [ ] Error handling works (missing/too large)
- [ ] Loaded ROM executes correctly
- [ ] Memory layout correct (0x0200 start)

**PC Speaker Sound (Priority 2)**:
- [ ] Sound_timer decrements at 60Hz
- [ ] Speaker produces audible tone
- [ ] Frequency: 880 Hz
- [ ] Duration matches timer value
- [ ] Speaker enable/disable clean

**Performance Throttling (Priority 3)**:
- [ ] Slow speed: 5 IPS
- [ ] Default speed: 10 IPS
- [ ] Fast speed: 20 IPS
- [ ] User can select speed at startup
- [ ] Throttling stable and consistent

**Integration**:
- [ ] All three features work together
- [ ] No feature interference
- [ ] Games playable (Pong, Tetris, Space Invaders)
- [ ] System stable under all conditions
- [ ] Memory protected (no corruption)

**Quality**:
- [ ] No crashes or hangs
- [ ] Graceful error handling
- [ ] Clear error messages
- [ ] Consistent behavior
- [ ] Performance acceptable

---

## PHASE 3 SIGN-OFF

**Status**: READY FOR FINAL TESTING  
**Estimated Completion**: Upon all tests passing  
**Next Phase**: Documentation & Release  

**Signed**: Phase 3 Technical Lead  
**Date**: [To be filled upon completion]  
**Version**: 1.0 GOLD MASTER

---

**End of Phase 3 Validation Framework**
