; ============================================================================
; NANO-VM: Hardware Layer (hardware.asm)
; 
; Defines the virtual CPU state including:
; - 16 general-purpose registers (V0-VF)
; - 1 index register (I)
; - Program counter (PC)
; - Stack pointer (SP)
; - 16-level call stack
; - 4096-byte RAM
; - 256-byte display buffer
;
; All symbols are exported for use by other modules.
; ============================================================================

global ram
global display_buffer
global registers
global stack
global pc
global sp
global i_register
global delay_timer
global sound_timer
global keyboard_state
global font_data
global font_data_in_ram

section .bss
    ; --- REGISTER FILE ---
    ; 16 general-purpose registers (V0-VF)
    ; Each register is 1 byte (8 bits)
    ; Total: 16 bytes
    registers:      resb    16

    ; --- INDEX REGISTER ---
    ; Used for memory addressing in DXYN (Draw) instruction
    ; 2 bytes (can address up to 4096)
    i_register:     resw    1

    ; --- PROGRAM COUNTER ---
    ; Tracks the current instruction address in RAM
    ; Initially set to 0x200 (start of program memory)
    ; 2 bytes (can address up to 65536, but we use 4096)
    pc:             resw    1

    ; --- STACK POINTER ---
    ; Points to the top of the call stack
    ; Range: 0-15 (we support 16 nested subroutine calls)
    ; 1 byte
    sp:             resb    1

    ; --- CALL STACK ---
    ; 16 entries, each 2 bytes (return addresses)
    ; Stack grows upward (sp=0 is empty, sp=1 has 1 entry, etc.)
    stack:          resw    16

    ; --- RAM (4096 bytes) ---
    ; 0x000-0x1FF: Reserved for CHIP-8 interpreter (we don't use this)
    ; 0x200-0xFFF: Program memory and data
    ; Our programs start at 0x200
    ram:            resb    4096

    ; --- DISPLAY BUFFER (256 bytes) ---
    ; Packed bitmap: 64 pixels wide × 32 pixels tall
    ; Each pixel is 1 bit; 8 pixels per byte
    ; Total: (64 * 32) / 8 = 256 bytes
    ; 
    ; Layout:
    ;   Row 0:  bytes 0-7     (pixels 0-63)
    ;   Row 1:  bytes 8-15    (pixels 64-127)
    ;   ...
    ;   Row 31: bytes 248-255 (pixels 1984-2047)
    ;
    ; Bit indexing within a byte:
    ;   Bit 7 (MSB) = leftmost pixel
    ;   Bit 0 (LSB) = rightmost pixel
    display_buffer: resb    256

    ; --- DELAY TIMER (1 byte) ---
    ; Counts down at 60 Hz. When set to non-zero, decrements each cycle.
    ; Used for timing in games (e.g., delays, timeouts)
    delay_timer:    resb    1

    ; --- SOUND TIMER (1 byte) ---
    ; Counts down at 60 Hz. When non-zero, a beep should sound.
    ; We won't actually play sound, just track the timer.
    sound_timer:    resb    1

    ; --- KEYBOARD STATE (16 bytes) ---
    ; Maps 16 keys (0x0-0xF) to their current state (0=up, non-zero=down)
    ; Simulates a hex keypad input
    ; For now, we'll support keyboard input simulation.
    keyboard_state: resb    16

    ; --- PHASE 1: FONT DATA IN RAM (80 bytes) ---
    ; CHIP-8 font data is loaded into RAM at address 0x50 during initialization
    ; This area is reserved for the font sprites (characters 0-F)
    ; Each character is 5 bytes, so 16 chars * 5 bytes = 80 bytes
    ; The handler_ld_font (FX29) opcode uses: I = 0x50 + (V[X] * 5)
    ; This marker is here for reference; actual font loading happens in main.asm
    font_data_in_ram: equ 0x50     ; Font data starts at address 0x50 in RAM

    ; --- PHASE 2: TIMING STRUCTURES ---
    ; High-resolution timer data for 500Hz instruction execution and 60Hz timer sync
    
    ; Last wall-clock time when timers were decremented (nanoseconds)
    ; Used to implement delta-time based timer synchronization
    timer_last_decrement: dq 0      ; 8 bytes: nanosecond timestamp of last decrement
    
    ; Timespec structures for clock_gettime (Linux POSIX syscalls)
    ; struct timespec {
    ;    time_t tv_sec;    /* seconds (8 bytes on 64-bit) */
    ;    long tv_nsec;     /* nanoseconds (8 bytes) */
    ; };
    timespec_now: dq 0, 0           ; Current time: seconds, nanoseconds
    timespec_target: dq 0, 0        ; Target sleep time for nanosleep
    
    ; Nanosleep remainder (for EINTR handling on signal interruption)
    sleep_remainder: dq 0, 0        ; Remaining sleep time if interrupted
    
    ; Instruction execution counter (for statistics and debugging)
    instruction_count: dq 0         ; Total instructions executed since start
    
    ; CPU statistics tracking
    total_time_elapsed: dq 0        ; Total milliseconds elapsed since start
    start_time: dq 0, 0             ; Program start time (seconds, nanoseconds)

    ; --- PHASE 3: GRAPHICS OPTIMIZATION (Double-Buffering) ---
    ; Double-buffering prevents visual artifacts and optimizes rendering
    ; Back buffer: where DXYN and other drawing operations write
    ; Front buffer: what's currently displayed
    ; Only write to terminal if front != back (saves syscalls)
    
    display_buffer_front: resb 256   ; Currently displayed buffer (front)
    display_buffer_back: resb 256    ; Being drawn to buffer (back)
    buffer_dirty_flag: resb 1        ; 1 if back != front, 0 if identical
    
    ; Pre-formatted screen output buffer (monochrome, 60 FPS target)
    ; Size: 3 (home code) + 64 (pixels) + 1 (newline) * 32 (rows) = 2,083 bytes
    ; HARD CONSTRAINT: Do NOT add ANSI color codes here!
    ; Color support requires separate Phase 5+ with different render pipeline
    screen_output_buffer: resb 2083  ; Pre-formatted screen string for write()

section .data
    ; --- CHIP-8 FONT DATA ---
    ; 16 character sprites (0x0 through 0xF)
    ; Each character is 5 bytes tall (as per CHIP-8 standard)
    ; Total: 80 bytes
    ;
    ; These sprites are typically loaded into memory at 0x050 in standard CHIP-8
    ; For our implementation, we store them here in .data for reference.
    ; In a complete implementation, these would be copied into RAM during init.
    
    font_data:
        ; Character '0' (0x30 or 0x0)
        db  0xF0, 0x90, 0x90, 0x90, 0xF0    ; ####  #  #  #  ####
        
        ; Character '1' (0x31 or 0x1)
        db  0x20, 0x60, 0x20, 0x20, 0x70    ;   #   ##   #   #  ###
        
        ; Character '2' (0x32 or 0x2)
        db  0xF0, 0x10, 0xF0, 0x80, 0xF0    ; ####     #  ####  #    ####
        
        ; Character '3' (0x33 or 0x3)
        db  0xF0, 0x10, 0xF0, 0x10, 0xF0    ; ####     #  ####     #  ####
        
        ; Character '4' (0x34 or 0x4)
        db  0x90, 0x90, 0xF0, 0x10, 0x10    ; #  #  #  #  ####     #     #
        
        ; Character '5' (0x35 or 0x5)
        db  0xF0, 0x80, 0xF0, 0x10, 0xF0    ; ####  #    ####     #  ####
        
        ; Character '6' (0x36 or 0x6)
        db  0xF0, 0x80, 0xF0, 0x90, 0xF0    ; ####  #    ####  #  #  ####
        
        ; Character '7' (0x37 or 0x7)
        db  0xF0, 0x10, 0x20, 0x40, 0x40    ; ####     #     #   #    #
        
        ; Character '8' (0x38 or 0x8)
        db  0xF0, 0x90, 0xF0, 0x90, 0xF0    ; ####  #  #  ####  #  #  ####
        
        ; Character '9' (0x39 or 0x9)
        db  0xF0, 0x90, 0xF0, 0x10, 0xF0    ; ####  #  #  ####     #  ####
        
        ; Character 'A' (0x3A or 0xA)
        db  0xF0, 0x90, 0xF0, 0x90, 0x90    ; ####  #  #  ####  #  #  #  #
        
        ; Character 'B' (0x3B or 0xB)
        db  0xE0, 0x90, 0xE0, 0x90, 0xE0    ; ###   #  #  ###   #  #  ###
        
        ; Character 'C' (0x3C or 0xC)
        db  0xF0, 0x80, 0x80, 0x80, 0xF0    ; ####  #    #    #    ####
        
        ; Character 'D' (0x3D or 0xD)
        db  0xE0, 0x90, 0x90, 0x90, 0xE0    ; ###   #  #  #  #  #  #  ###
        
        ; Character 'E' (0x3E or 0xE)
        db  0xF0, 0x80, 0xF0, 0x80, 0xF0    ; ####  #    ####  #    ####
        
        ; Character 'F' (0x3F or 0xF)
        db  0xF0, 0x80, 0xF0, 0x80, 0x80    ; ####  #    ####  #    #

; ============================================================================
; INITIALIZATION NOTES
; ============================================================================
;
; These symbols are allocated in the .bss section and are initialized
; to zero by the linker. Before the main loop starts, main.asm must:
;
; 1. Set PC to 0x200 (program start)
; 2. Set SP to 0 (empty stack)
; 3. Load the ROM data into RAM starting at address 0x200
; 4. Initialize any other state as needed
;
; The fetch-decode-execute loop will then begin reading instructions
; from RAM[PC] and executing them.
;
; ============================================================================
; MEMORY MAP SUMMARY
; ============================================================================
;
; Virtual Address | Size      | Purpose
; ================|===========|============================================
; 0x0000-0x01FF   | 512 B     | Reserved (not used by nano-vm)
; 0x0200-0x0FFF   | 3840 B    | Program memory (where ROM is loaded)
; (RAM is all 4096 B total, starting at address 0)
;
; Register File:  | 16 B      | V0-VF (general purpose)
; Index Register: | 2 B       | I (memory addressing)
; PC:             | 2 B       | Program counter
; SP:             | 1 B       | Stack pointer (0-15)
; Stack:          | 32 B      | 16 × 2-byte return addresses
; Display Buffer: | 256 B     | 64×32 bitmap (packed bits)
;
; Total Virtual HW State: ~309 bytes (registers, pc, sp, stack, display)
; Total Memory Model: ~4352 bytes (RAM + virtual HW state)
;
; ============================================================================
; END OF HARDWARE MODULE
; ============================================================================
