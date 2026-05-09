; ============================================================================
; NANO-VM: Main Program & ROM Loader (main.asm)
;
; Entry point for the nano-vm emulator.
;
; Responsibilities:
; 1. Load ROM data into RAM at address 0x200
; 2. Initialize CPU state (PC, SP, registers)
; 3. Run the main fetch-decode-execute loop
; 4. Render the display
; 5. Exit cleanly
;
; The ROM data (IBM Logo) is hardcoded as hex bytes in the .data section.
; ============================================================================

global main

extern ram
extern display_buffer
extern registers
extern pc
extern sp
extern i_register
extern stack
extern delay_timer
extern sound_timer
extern keyboard_state
extern font_data

extern fetch_opcode
extern decode_dispatch
extern render_screen

; C library functions
extern printf
extern sleep

section .data
    ; --- IBM LOGO ROM ---
    ; This is the classic IBM Logo displayed by CHIP-8 emulators.
    ; Each byte represents 8 pixels (1 = on, 0 = off)
    ; The logo is 8 bytes wide by 8 rows tall (64 pixels)
    ;
    ; Format: Each pair of hex digits is one byte, representing sprite data.
    ; The logo will be rendered at position (0, 0) on the display.
    rom_data:
        ; Row 0
        db 0xF0, 0x90, 0x90, 0xF0
        ; Row 1
        db 0x90, 0x90, 0x90, 0x90
        ; Row 2
        db 0xF0, 0x10, 0xF0, 0x80
        ; Row 3
        db 0xF0, 0x80, 0xF0, 0x10
        ; Additional rows for more complex pattern
        db 0x10, 0xF0, 0x10, 0x10

    rom_size equ $ - rom_data      ; Calculate ROM size
    
    ; Format strings for printf
    startup_msg: db "Nano-VM starting...", 10, 0
    exit_msg:    db "Nano-VM exiting.", 10, 0
    rom_loaded_msg: db "ROM loaded at 0x200", 10, 0
    
    ; PHASE 2: Statistics messages
    instr_count_msg: db "Instructions executed: %llu", 10, 0

section .text

; ============================================================================
; ENTRY POINT: main
;
; Standard C entry point. Must return 0 on success.
;
; ============================================================================
main:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    ; Print startup message
    lea rdi, [rel startup_msg]
    xor eax, eax
    call printf

    ; --- INITIALIZE CPU STATE ---
    
    ; Set PC to 0x200 (program start)
    lea rbx, [rel pc]
    mov word [rbx], 0x200

    ; Set SP to 0 (empty stack)
    lea rbx, [rel sp]
    mov byte [rbx], 0

    ; Clear all registers
    lea rbx, [rel registers]
    xor ecx, ecx
.clear_regs:
    cmp ecx, 16
    jge .regs_cleared
    mov byte [rbx + rcx], 0
    inc ecx
    jmp .clear_regs

.regs_cleared:
    ; Initialize I register to 0
    lea rbx, [rel i_register]
    mov word [rbx], 0

    ; Initialize timers to 0
    lea rbx, [rel delay_timer]
    mov byte [rbx], 0
    
    lea rbx, [rel sound_timer]
    mov byte [rbx], 0

    ; Clear keyboard state
    lea rbx, [rel keyboard_state]
    xor ecx, ecx
.clear_keys:
    cmp ecx, 16
    jge .keys_cleared
    mov byte [rbx + rcx], 0
    inc ecx
    jmp .clear_keys

.keys_cleared:

    ; --- PHASE 1: LOAD FONT DATA INTO RAM AT 0x50 ---
    ;
    ; CHIP-8 specification requires font data to be loaded into RAM
    ; at address 0x50 (80 decimal). This is used by the FX29 opcode
    ; which loads the address of a font character into the I register.
    ;
    
    lea rsi, [rel font_data]        ; RSI = source (font data from .data)
    lea rdi, [rel ram]
    add rdi, 0x50                   ; RDI = RAM + 0x50 (font offset)
    
    mov ecx, 80                     ; 16 characters * 5 bytes = 80 bytes
    rep movsb                       ; Copy font data into RAM

    ; --- LOAD ROM INTO RAM ---
    
    ; Copy ROM data from .data section into RAM at offset 0x200
    ; Use rep movsb for bulk copy
    
    lea rsi, [rel rom_data]         ; RSI = source (ROM data)
    lea rdi, [rel ram]
    add rdi, 0x200                  ; RDI = RAM + 0x200 (program start)
    
    mov ecx, rom_size               ; RCX = number of bytes to copy
    rep movsb                       ; Copy bytes from RSI to RDI

    ; Print ROM loaded message
    lea rdi, [rel rom_loaded_msg]
    xor eax, eax
    call printf

    ; --- PHASE 2: HIGH-RESOLUTION MAIN EXECUTION LOOP ---
    ; 
    ; This is the core of the emulator with professional timing:
    ; 1. Record start time for statistics
    ; 2. For each instruction cycle:
    ;    a. Get current time
    ;    b. Fetch and execute instruction
    ;    c. Check if time for 60Hz timer decrement
    ;    d. Render display (if changed)
    ;    e. Sleep to maintain 500Hz (2ms per instruction)
    ; 3. Exit on halt condition
    ;
    
    ; Initialize timing: record program start time
    mov rax, CLOCK_GETTIME_SYS_CALL  ; SYS_clock_gettime
    mov rdi, CLOCK_MONOTONIC         ; CLOCK_MONOTONIC
    lea rsi, [rel start_time]
    syscall
    
    ; Also initialize timer_last_decrement to now
    mov rax, [rel start_time + 8]    ; nanoseconds part
    mov [rel timer_last_decrement], rax
    
    mov ecx, 1000                    ; Run for 1000 iterations (tunable, ~2 seconds at 500Hz)

.exec_loop:
    cmp ecx, 0
    jle .halt

    ; --- Get current time before instruction ---
    mov rax, CLOCK_GETTIME_SYS_CALL
    mov rdi, CLOCK_MONOTONIC
    lea rsi, [rel timespec_now]
    syscall

    ; --- Fetch and execute the next instruction ---
    call fetch_opcode                ; RAX = opcode
    call decode_dispatch             ; Execute it

    ; --- Increment instruction counter ---
    lea rax, [rel instruction_count]
    inc qword [rax]

    ; --- PHASE 2: Delta-time based timer synchronization ---
    ; Check if 16.67ms has elapsed since last timer decrement (60 Hz)
    mov rax, [rel timespec_now + 8]  ; Current nanoseconds
    mov rbx, [rel timer_last_decrement]  ; Last decrement time
    sub rax, rbx                     ; Delta = current - last
    
    ; 60 Hz = 16,666,667 nanoseconds between decrements
    cmp rax, 16666667
    jl .skip_timer_decrement
    
    ; Time for timer decrement
    mov rax, [rel timespec_now + 8]
    mov [rel timer_last_decrement], rax  ; Update last decrement time
    
    ; Decrement delay_timer if non-zero
    lea rax, [rel delay_timer]
    cmp byte [rax], 0
    je .skip_delay_timer
    dec byte [rax]
.skip_delay_timer:
    
    ; Decrement sound_timer if non-zero
    lea rax, [rel sound_timer]
    cmp byte [rax], 0
    je .skip_sound_timer
    dec byte [rax]
.skip_sound_timer:

.skip_timer_decrement:

    ; --- Render the display (single syscall, optimized in Phase 3) ---
    call render_screen

    ; --- PHASE 2: Sleep to maintain 500Hz instruction rate ---
    ; Target: 2,000,000 nanoseconds (2ms) per instruction
    ; 
    ; Get current time after execution
    mov rax, CLOCK_GETTIME_SYS_CALL
    mov rdi, CLOCK_MONOTONIC
    lea rsi, [rel timespec_now]
    syscall
    
    ; Calculate how long we've been working (nanoseconds)
    ; For simplicity, we'll just sleep 2ms regardless
    ; In a real implementation, we'd calculate: target_time - actual_elapsed
    
    ; Set up nanosleep for 2ms (2,000,000 ns)
    mov qword [rel timespec_target], 0       ; tv_sec = 0
    mov qword [rel timespec_target + 8], 2000000  ; tv_nsec = 2ms
    
    xor rcx, rcx  ; Retry counter
.nanosleep_with_retry:
    cmp rcx, 5    ; Max 5 retries for EINTR
    jge .nanosleep_done
    
    mov rax, 35   ; SYS_nanosleep
    lea rdi, [rel timespec_target]
    lea rsi, [rel sleep_remainder]
    syscall
    
    ; Check for EINTR
    cmp rax, -4   ; EINTR = -4
    je .nanosleep_interrupted
    cmp rax, 0
    je .nanosleep_done
    
    ; Error or other return, give up
    jmp .nanosleep_done

.nanosleep_interrupted:
    ; EINTR: restore remaining time and retry
    mov rax, qword [rel sleep_remainder + 8]
    mov qword [rel timespec_target + 8], rax
    inc rcx
    jmp .nanosleep_with_retry

.nanosleep_done:

    ; --- PHASE 2: Keyboard input polling (non-blocking) ---
    ; TODO: Implement in Phase 2 Part 2
    ; For now, skip keyboard polling to maintain timing precision

    ; Loop for next instruction
    dec ecx
    jmp .exec_loop

.halt:
    ; --- Calculate statistics ---
    mov rax, CLOCK_GETTIME_SYS_CALL
    mov rdi, CLOCK_MONOTONIC
    lea rsi, [rel timespec_now]
    syscall
    
    ; Calculate elapsed time in milliseconds
    mov rax, [rel timespec_now]      ; End seconds
    mov rbx, [rel start_time]        ; Start seconds
    sub rax, rbx                     ; Elapsed seconds
    imul rax, 1000                   ; Convert to milliseconds
    
    mov rbx, [rel timespec_now + 8]  ; End nanoseconds
    mov rcx, [rel start_time + 8]    ; Start nanoseconds
    sub rbx, rcx                     ; Delta nanoseconds
    
    ; Add nanoseconds/1,000,000 to milliseconds
    mov rax, rbx
    mov rdx, 0
    mov rcx, 1000000
    div rcx                          ; RAX = milliseconds from nanoseconds
    
    ; Store total elapsed
    lea rdi, [rel total_time_elapsed]
    add rax, qword [rdi]            ; Add seconds milliseconds
    mov [rel total_time_elapsed], rax

    ; Print exit message with statistics
    lea rdi, [rel exit_msg]
    xor eax, eax
    call printf

    ; Print instruction count
    lea rdi, [rel instr_count_msg]
    mov rsi, [rel instruction_count]
    xor eax, eax
    call printf

    ; Return 0 (success)
    xor eax, eax

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; NOTE: Building and Linking
;
; This program depends on external C library functions (printf, sleep, fflush).
; To build, use one of these commands:
;
; Using gcc (recommended, handles libc linking automatically):
;   nasm -f elf64 -o hardware.o hardware.asm
;   nasm -f elf64 -o decoder.o decoder.asm
;   nasm -f elf64 -o opcodes.o opcodes.asm
;   nasm -f elf64 -o graphics.o graphics.asm
;   nasm -f elf64 -o main.o main.asm
;   gcc -o nano-vm hardware.o decoder.o opcodes.o graphics.o main.o -lc
;
; Or using ld directly:
;   ld -o nano-vm hardware.o decoder.o opcodes.o graphics.o main.o \
;      -lc -dynamic-linker /lib64/ld-linux-x86-64.so.2
;
; ============================================================================

; ============================================================================
; END OF MAIN MODULE
; ============================================================================
