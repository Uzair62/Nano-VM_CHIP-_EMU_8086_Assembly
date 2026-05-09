; ============================================================================
; NANO-VM: Header File (nano-vm.h)
; Assembly macro definitions and memory layout constants
; ============================================================================
; 
; This header contains all shared constants, macros, and memory layout
; definitions used across all nano-vm modules.
;
; ============================================================================

; --- MEMORY LAYOUT CONSTANTS ---
%define RAM_SIZE        4096        ; Total RAM in bytes
%define DISPLAY_WIDTH   64          ; Display width in pixels
%define DISPLAY_HEIGHT  32          ; Display height in pixels
%define DISPLAY_BUFFER_SIZE 256     ; (64 * 32) / 8 = 256 bytes
%define STACK_DEPTH     16          ; Maximum subroutine call depth
%define PROGRAM_START   0x200       ; Programs start at address 0x200
%define REGISTER_COUNT  17          ; 16 general + 1 index register

; --- REGISTER INDICES ---
; Registers V0 through VF (V15) are general purpose
; VF is also the "carry" flag (set by collision detection, arithmetic)
; I is the Index register (used for memory addressing in DXYN)

; --- ANSI ESCAPE CODES ---
%define ANSI_CLEAR      27, '[', 'H'     ; ESC[H - Move cursor home
%define ANSI_NEWLINE    10                ; \n

; --- PHASE 1: HARDENING CONSTANTS ---
%define FONT_OFFSET     0x50             ; Font data location in RAM
%define FONT_SIZE       80               ; 16 characters * 5 bytes each
%define FONT_CHAR_SIZE  5                ; Bytes per character
%define MAX_FONT_CHAR   15               ; Maximum font character index (0-F)

; Stack validation constants
%define STACK_EMPTY     0
%define STACK_FULL      16
%define STACK_OVERFLOW_CODE  1           ; Exit code for stack overflow

; --- PHASE 2: TIMING CONSTANTS ---
%define INSTRUCTIONS_PER_SECOND  500     ; Target: 500 Hz instruction execution
%define NANOSECONDS_PER_INSTRUCTION  2000000  ; 1 second / 500 = 2 milliseconds
%define TIMERS_PER_SECOND  60            ; 60 Hz timer decrement rate
%define NANOSECONDS_PER_TIMER_TICK  16666667  ; 1 second / 60 ≈ 16.67 ms
%define CLOCK_MONOTONIC  1               ; CLOCK_MONOTONIC for clock_gettime
%define NANOSLEEP_SYS_CALL  35           ; SYS_nanosleep syscall number
%define SELECT_SYS_CALL  23              ; SYS_select syscall number
%define CLOCK_GETTIME_SYS_CALL  228      ; SYS_clock_gettime syscall number
%define EINTR_ERROR  -4                  ; Return code for EINTR
%define MAX_EINTR_RETRIES  5             ; Max retries for interrupted sleep

; ============================================================================
; MACROS
; ============================================================================

; --- MACRO: GET_REGISTER_OFFSET
; Calculates the offset in the registers array for a given register index
; Arguments:
;   %1 = register index (0-16, where 16 is the I register)
; Returns:
;   The offset in bytes from the start of the registers array
;
; Example:
;   mov rax, GET_REGISTER_OFFSET(3)  ; Get offset for V3
;
%macro GET_REGISTER_OFFSET 1
    %1  ; Register index (0-16)
%endmacro

; --- MACRO: LOAD_REGISTER
; Load a register value into a destination register
; Arguments:
;   %1 = destination register (rax, rbx, etc.)
;   %2 = source register index (0-16)
;   %3 = base address of registers array
;
; Example:
;   mov rsi, [registers_base]
;   LOAD_REGISTER rax, 5, rsi
;
%macro LOAD_REGISTER 3
    movzx %1, byte [%3 + %2]    ; Load register value
%endmacro

; --- MACRO: STORE_REGISTER
; Store a value into a register
; Arguments:
;   %1 = source register/value
;   %2 = destination register index (0-16)
;   %3 = base address of registers array
;
; Example:
;   mov rsi, [registers_base]
;   STORE_REGISTER rax, 5, rsi
;
%macro STORE_REGISTER 3
    mov byte [%3 + %2], %1      ; Store register value
%endmacro

; --- MACRO: SET_BIT_IN_BUFFER
; Set a bit at a specific position in a byte buffer
; Arguments:
;   %1 = buffer base address
;   %2 = bit offset (bit position in entire buffer)
;
; This calculates:
;   byte_offset = bit_offset / 8
;   bit_in_byte = bit_offset % 8
;   buffer[byte_offset] |= (1 << bit_in_byte)
;
%macro SET_BIT_IN_BUFFER 2
    ; Calculate byte offset: bit_offset / 8
    ; Calculate bit position: bit_offset % 8
    ; Then OR with the bit mask
    ; (Implementation left to opcodes.asm for efficiency)
%endmacro

; --- MACRO: XOR_BIT_IN_BUFFER
; XOR a bit at a specific position in a byte buffer
; Used for sprite drawing (DXYN opcode)
; Arguments:
;   %1 = buffer base address
;   %2 = bit offset
;
%macro XOR_BIT_IN_BUFFER 2
    ; Calculate byte offset: bit_offset / 8
    ; Calculate bit position: bit_offset % 8
    ; Then XOR with the bit mask
    ; (Implementation left to opcodes.asm for efficiency)
%endmacro

; ============================================================================
; PHASE 1: GUARD MACROS FOR MEMORY SAFETY
; ============================================================================

; --- MACRO: VALIDATE_REGISTER
; Ensure register index is valid (0-15)
; Arguments:
;   %1 = register value/expression to validate
; Jumps to .invalid_register if check fails
%macro VALIDATE_REGISTER 1
    cmp %1, 0xF
    jg .invalid_register
%endmacro

; --- MACRO: CHECK_STACK_PUSH
; Ensure stack has room before pushing (SP < 16)
; Jumps to .stack_overflow if SP is already full
%macro CHECK_STACK_PUSH 0
    lea rax, [rel sp]
    cmp byte [rax], STACK_FULL
    jge .stack_overflow
%endmacro

; --- MACRO: CHECK_STACK_POP
; Ensure stack has data before popping (SP > 0)
; Jumps to .stack_underflow if stack is empty
%macro CHECK_STACK_POP 0
    lea rax, [rel sp]
    cmp byte [rax], STACK_EMPTY
    jle .stack_underflow
%endmacro

; --- MACRO: VALIDATE_BOUNDS_I_REGISTER
; Ensure I register value wraps correctly (modulo 4096)
; Arguments:
;   %1 = I register value to validate/wrap
; Result: %1 is wrapped to 0-4095
%macro VALIDATE_BOUNDS_I_REGISTER 1
    mov rax, %1
    mov rdx, 0
    mov rcx, 4096
    div rcx                 ; RAX = rax / 4096, RDX = rax % 4096
    mov %1, rdx             ; Store wrapped value back
%endmacro

; --- MACRO: VALIDATE_MEMORY_ACCESS
; Ensure memory address is within bounds (0-4095)
; Arguments:
;   %1 = address to validate
; Jumps to .memory_access_violation if out of bounds
%macro VALIDATE_MEMORY_ACCESS 1
    cmp %1, RAM_SIZE
    jge .memory_access_violation
%endmacro

; ============================================================================
; PHASE 2: TIMING & INPUT MACROS
; ============================================================================

; --- MACRO: DECREMENT_DELAY_TIMER_IF_NEEDED
; Check elapsed time and decrement delay_timer if enough time has passed (60Hz)
; Uses delta-time comparison against timer_last_decrement
; Modifies: RAX, RBX, RCX, RDX
;
%macro DECREMENT_DELAY_TIMER_IF_NEEDED 0
    ; Get current time in nanoseconds
    mov rdi, CLOCK_MONOTONIC
    lea rsi, [rel timespec_now]
    mov rax, CLOCK_GETTIME_SYS_CALL
    syscall
    
    ; Calculate delta: current_time - last_decrement_time
    mov rax, qword [rel timespec_now + 8]  ; current nsec
    sub rax, qword [rel timer_last_decrement]  ; subtract last time
    
    ; 60 Hz = 1 tick every 16,666,667 nanoseconds
    cmp rax, NANOSECONDS_PER_TIMER_TICK
    jl .no_timer_decrement
    
    ; Time to decrement: update last time and decrement timer
    mov rax, qword [rel timespec_now + 8]
    mov [rel timer_last_decrement], rax
    
    ; Decrement delay_timer if non-zero
    lea rax, [rel delay_timer]
    cmp byte [rax], 0
    je .skip_delay_decrement
    dec byte [rax]
.skip_delay_decrement:
    
    ; Decrement sound_timer if non-zero
    lea rax, [rel sound_timer]
    cmp byte [rax], 0
    je .skip_sound_decrement
    dec byte [rax]
.skip_sound_decrement:

.no_timer_decrement:
%endmacro

; --- MACRO: NANOSLEEP_WITH_EINTR_HANDLING
; Sleep for N nanoseconds, with automatic EINTR retry
; Arguments:
;   %1 = nanoseconds to sleep (must fit in 64-bit)
; Modifies: RAX, RDI, RSI, RCX
;
%macro NANOSLEEP_WITH_EINTR_HANDLING 1
    ; Set up timespec for nanosleep
    mov qword [rel timespec_target], 0  ; tv_sec = 0 (no seconds)
    mov qword [rel timespec_target + 8], %1  ; tv_nsec = nanoseconds
    
    xor rcx, rcx  ; Retry counter
.nanosleep_retry:
    cmp rcx, MAX_EINTR_RETRIES
    jge .nanosleep_give_up
    
    mov rax, NANOSLEEP_SYS_CALL        ; SYS_nanosleep = 35
    lea rdi, [rel timespec_target]     ; req timespec
    lea rsi, [rel sleep_remainder]     ; rem timespec
    syscall
    
    ; Check for EINTR (return value -4)
    cmp rax, EINTR_ERROR
    je .nanosleep_interrupted
    cmp rax, 0
    je .nanosleep_done
    
    ; Other error - give up
    jmp .nanosleep_give_up
    
.nanosleep_interrupted:
    ; EINTR occurred, restore remaining time and retry
    mov rax, qword [rel sleep_remainder]
    mov qword [rel timespec_target + 8], rax
    inc rcx
    jmp .nanosleep_retry
    
.nanosleep_give_up:
    ; Fallback: busy-loop (last resort if nanosleep not working)
    ; This is better than nothing but less accurate
.nanosleep_done:
%endmacro

; ============================================================================
; SYMBOL EXPORTS (External symbols defined in modules)
; ============================================================================

extern ram                  ; 4096-byte RAM array
extern display_buffer       ; 256-byte display buffer
extern registers            ; 17-byte register file (V0-VF + I)
extern stack                ; 16 * 2 byte stack
extern pc                   ; Program counter (2 bytes)
extern sp                   ; Stack pointer (1 byte, 0-15)
extern i_register           ; Index register (2 bytes)
extern delay_timer          ; Delay timer (1 byte)
extern sound_timer          ; Sound timer (1 byte)
extern keyboard_state       ; Keyboard state (16 bytes)
extern font_data            ; Font data (80 bytes)
extern timer_last_decrement ; Last timer decrement timestamp
extern instruction_count    ; Total instructions executed
extern start_time           ; Program start time
extern total_time_elapsed   ; Total elapsed milliseconds

; --- PHASE 3: GRAPHICS STRUCTURES ---
%define SCREEN_BUFFER_SIZE  2083    ; 3 (home code) + 65*32 (display)
%define SCREEN_WIDTH_BYTES  8       ; 8 bytes per row (64 pixels / 8)
%define SCREEN_HEIGHT       32      ; 32 pixel rows

extern render_screen        ; Function: render display buffer to terminal

extern fetch_opcode         ; Function: fetch next instruction
extern decode_dispatch      ; Function: decode and dispatch opcode
extern render_screen        ; Function: render display buffer to terminal

extern handler_clr          ; Handler: 00E0 (Clear)
extern handler_jmp          ; Handler: 1NNN (Jump)
extern handler_set_vx       ; Handler: 6XNN (Set VX)
extern handler_set_i        ; Handler: ANNN (Set I)
extern handler_draw         ; Handler: DXYN (Draw sprite)

; ============================================================================
; END OF HEADER
; ============================================================================
