; ============================================================================
; Nano-VM Test Harness - Unit Testing for Individual Opcodes
; ============================================================================
; This module provides a testing framework to verify the correctness of 
; individual opcode handlers without needing to load a full ROM.
; ============================================================================

%include "nano-vm.h"

; ============================================================================
; External Symbols (from other modules)
; ============================================================================
extern hardware_init
extern fetch_decode_execute
extern draw_display

; ============================================================================
; Test Framework Data
; ============================================================================
section .data
    ; Test counter and state
    tests_run:      dq 0
    tests_passed:   dq 0
    tests_failed:   dq 0
    
    ; Test result strings
    test_header:    db "=== Nano-VM Unit Test Harness ===", 0x0A, 0
    test_pass_msg:  db "[PASS] ", 0
    test_fail_msg:  db "[FAIL] ", 0
    
    test_clr_name:     db "CLR (0x00E0): Clear Display", 0x0A, 0
    test_jmp_name:     db "JMP (0x1NNN): Jump to Address", 0x0A, 0
    test_setreg_name:  db "SET_VX (0x6XNN): Set Register", 0x0A, 0
    test_seti_name:    db "SET_I (0xANNN): Set Index", 0x0A, 0
    test_draw_name:    db "DRAW (0xDXYN): Draw Sprite", 0x0A, 0
    
    crlf:           db 0x0A, 0

section .bss
    ; Test buffer for display validation
    test_buffer:    resb DISPLAY_SIZE

; ============================================================================
; Helper Macros
; ============================================================================

; Print a string to stdout
%macro print_string 1
    mov rdi, %1
    call print_str
%endmacro

; Assert register value
%macro assert_register 2
    ; rax = register value, rsi = expected value
    cmp rax, %2
    jne %%fail
    mov r8, 1
    jmp %%done
%%fail:
    mov r8, 0
%%done:
%endmacro

; ============================================================================
; Main Entry Point
; ============================================================================
global main
main:
    push rbp
    mov rbp, rsp
    sub rsp, 16
    
    ; Print header
    lea rdi, [rel test_header]
    call print_str
    
    ; Initialize hardware
    call hardware_init
    
    ; Run test suite
    call test_opcode_clr
    call test_opcode_jmp
    call test_opcode_setreg
    call test_opcode_seti
    call test_opcode_draw
    
    ; Print summary
    call print_test_summary
    
    ; Exit with status
    xor eax, eax
    leave
    ret

; ============================================================================
; Test: CLR (0x00E0) - Clear Display
; ============================================================================
test_opcode_clr:
    push rbp
    mov rbp, rsp
    
    lea rdi, [rel test_clr_name]
    call print_str
    
    ; Initialize display with pattern
    mov rcx, DISPLAY_SIZE / 8
    lea rsi, [rel display_buffer]
%%fill_loop:
    mov qword [rsi], 0xFFFFFFFFFFFFFFFF
    add rsi, 8
    loop %%fill_loop
    
    ; Load CLR opcode (0x00E0)
    mov rax, 0x00E0
    call fetch_decode_execute
    
    ; Verify display is clear
    mov rcx, DISPLAY_SIZE / 8
    lea rsi, [rel display_buffer]
    xor r8, r8  ; Result flag
    mov r8, 1   ; Assume pass
%%verify_loop:
    cmp qword [rsi], 0
    jne %%fail
    add rsi, 8
    loop %%verify_loop
    jmp %%success
    
%%fail:
    xor r8, r8
%%success:
    call record_test_result
    pop rbp
    ret

; ============================================================================
; Test: JMP (0x1NNN) - Jump to Address
; ============================================================================
test_opcode_jmp:
    push rbp
    mov rbp, rsp
    
    lea rdi, [rel test_jmp_name]
    call print_str
    
    ; Save current PC
    lea rsi, [rel program_counter]
    mov r10, [rsi]
    
    ; Load JMP opcode (0x1234)
    mov rax, 0x1234
    call fetch_decode_execute
    
    ; Verify PC is set to 0x234
    lea rsi, [rel program_counter]
    mov rax, [rsi]
    cmp rax, 0x234
    mov r8, 0
    je %%success
    jmp %%done
%%success:
    mov r8, 1
%%done:
    call record_test_result
    pop rbp
    ret

; ============================================================================
; Test: SET_VX (0x6XNN) - Set Register Value
; ============================================================================
test_opcode_setreg:
    push rbp
    mov rbp, rsp
    
    lea rdi, [rel test_setreg_name]
    call print_str
    
    ; Load SET_VX opcode (0x6355) - Set V3 to 0x55
    mov rax, 0x6355
    call fetch_decode_execute
    
    ; Verify V3 contains 0x55
    lea rsi, [rel registers]
    movzx rax, byte [rsi + 3]
    cmp rax, 0x55
    mov r8, 0
    je %%success
    jmp %%done
%%success:
    mov r8, 1
%%done:
    call record_test_result
    pop rbp
    ret

; ============================================================================
; Test: SET_I (0xANNN) - Set Index Register
; ============================================================================
test_opcode_seti:
    push rbp
    mov rbp, rsp
    
    lea rdi, [rel test_seti_name]
    call print_str
    
    ; Load SET_I opcode (0xA567) - Set I to 0x567
    mov rax, 0xA567
    call fetch_decode_execute
    
    ; Verify I contains 0x567
    lea rsi, [rel index_register]
    mov rax, [rsi]
    cmp rax, 0x567
    mov r8, 0
    je %%success
    jmp %%done
%%success:
    mov r8, 1
%%done:
    call record_test_result
    pop rbp
    ret

; ============================================================================
; Test: DRAW (0xDXYN) - Draw Sprite with XOR
; ============================================================================
test_opcode_draw:
    push rbp
    mov rbp, rsp
    
    lea rdi, [rel test_draw_name]
    call print_str
    
    ; Setup: Place sprite data in memory
    lea rsi, [rel memory]
    add rsi, 0x200          ; Load at ROM start
    mov byte [rsi], 0xF0    ; 1111 0000
    mov byte [rsi + 1], 0x90; 1001 0000
    
    ; Set I to point to sprite (assume 0x200)
    lea rsi, [rel index_register]
    mov qword [rsi], 0x200
    
    ; Set V0=0, V1=0 (screen position)
    lea rsi, [rel registers]
    mov byte [rsi], 0
    mov byte [rsi + 1], 0
    
    ; Clear display first
    mov rcx, DISPLAY_SIZE / 8
    lea rsi, [rel display_buffer]
%%clear_loop:
    mov qword [rsi], 0
    add rsi, 8
    loop %%clear_loop
    
    ; Execute DRAW (0xD012) - Draw at V0,V1 with height 2
    mov rax, 0xD012
    call fetch_decode_execute
    
    ; Verify display was modified
    lea rsi, [rel display_buffer]
    mov rax, [rsi]
    cmp rax, 0
    mov r8, 0
    jne %%success
    jmp %%done
%%success:
    mov r8, 1
%%done:
    call record_test_result
    pop rbp
    ret

; ============================================================================
; Helper Functions
; ============================================================================

; Record test result
; r8 = 1 for pass, 0 for fail
record_test_result:
    push rax
    
    lea rsi, [rel tests_run]
    inc qword [rsi]
    
    cmp r8, 1
    jne %%fail
    
    lea rsi, [rel tests_passed]
    inc qword [rsi]
    
    lea rdi, [rel test_pass_msg]
    call print_str
    jmp %%done
    
%%fail:
    lea rsi, [rel tests_failed]
    inc qword [rsi]
    
    lea rdi, [rel test_fail_msg]
    call print_str
    
%%done:
    pop rax
    ret

; Print test summary
print_test_summary:
    push rax
    push rsi
    
    mov rax, [rel tests_run]
    mov rsi, [rel tests_passed]
    mov r10, [rel tests_failed]
    
    ; Print summary (simplified - would need full printf implementation)
    lea rdi, [rel crlf]
    call print_str
    
    pop rsi
    pop rax
    ret

; Simple string print (requires libc printf or write syscall)
print_str:
    ; rdi = pointer to null-terminated string
    ; This is a stub - in practice, use printf or write()
    ret

; ============================================================================
; External references from other modules
; ============================================================================
extern memory
extern registers
extern index_register
extern program_counter
extern display_buffer
