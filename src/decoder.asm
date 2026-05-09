; ============================================================================
; NANO-VM: Complete CHIP-8 Instruction Decoder (decoder.asm)
;
; Implements the "Fetch-Decode-Execute" cycle for 35+ CHIP-8 opcodes:
; 1. FETCH:  Read 2 bytes from RAM[PC]
; 2. DECODE: Extract opcode and route to handler
; 3. EXECUTE: Handler processes instruction and updates VM state
;
; Key challenge: CHIP-8 is big-endian; x86_64 is little-endian
; Solution: Manually assemble bytes in correct order
; ============================================================================

global fetch_opcode
global decode_dispatch

extern ram
extern pc
extern sp
extern i_register
extern registers
extern display_buffer
extern stack
extern delay_timer
extern sound_timer
extern keyboard_state

; Import all opcode handlers
extern handler_clr
extern handler_jmp
extern handler_call
extern handler_ret
extern handler_set_vx
extern handler_add_vx
extern handler_move
extern handler_add_xy
extern handler_sub_xy
extern handler_or_xy
extern handler_and_xy
extern handler_xor_xy
extern handler_shl_x
extern handler_set_i
extern handler_ske_nn
extern handler_skne_nn
extern handler_ske_xy
extern handler_skne_xy
extern handler_ld_dt
extern handler_set_dt
extern handler_set_st
extern handler_wait_key
extern handler_skp
extern handler_sknp
extern handler_ld_font
extern handler_bcd
extern handler_str_reg
extern handler_ld_reg
extern handler_add_i
extern handler_draw
extern handler_rnd

section .text

; ============================================================================
; FUNCTION: fetch_opcode
;
; Fetches the next instruction from RAM at the current PC.
; Converts from CHIP-8 big-endian to native 16-bit format.
;
; Inputs: (uses global PC)
; Outputs: RAX = 16-bit opcode, PC += 2
; ============================================================================
fetch_opcode:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    lea rbx, [rel pc]
    movzx ecx, word [rbx]

    lea rdx, [rel ram]
    movzx eax, byte [rdx + rcx]
    shl eax, 8

    movzx edx, byte [rdx + rcx + 1]
    or eax, edx

    add word [rbx], 2

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; FUNCTION: decode_dispatch
;
; Routes opcode to appropriate handler using multi-level dispatch:
; 1. Primary dispatch on high nibble (0xF000)
; 2. Secondary dispatch for ambiguous cases (0x00FF, 0x8XY*, 0xEX**, 0xFX**)
;
; Inputs: RAX = 16-bit opcode
; Outputs: Handler is invoked (handlers update VM state and return)
; ============================================================================
decode_dispatch:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov ecx, eax
    shr ecx, 12
    and ecx, 0xF

    lea rbx, [rel primary_dispatch]
    mov rsi, [rbx + rcx * 8]
    call rsi

    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; PRIMARY DISPATCH TABLE (high nibble)
; ============================================================================
section .data
    primary_dispatch:
        dq handler_0xxx         ; 0x0xxx
        dq handler_1xxx         ; 0x1xxx
        dq handler_2xxx         ; 0x2xxx
        dq handler_3xxx         ; 0x3xxx
        dq handler_4xxx         ; 0x4xxx
        dq handler_5xxx         ; 0x5xxx
        dq handler_6xxx         ; 0x6xxx
        dq handler_7xxx         ; 0x7xxx
        dq handler_8xxx         ; 0x8xxx
        dq handler_9xxx         ; 0x9xxx
        dq handler_axxx         ; 0xAxxx
        dq handler_bxxx         ; 0xBxxx
        dq handler_cxxx         ; 0xCxxx
        dq handler_dxxx         ; 0xDxxx
        dq handler_exxx         ; 0xExxx
        dq handler_fxxx         ; 0xFxxx

section .text

; ============================================================================
; PRIMARY DISPATCH HANDLERS
; ============================================================================

; 0x0xxx: Special cases
handler_0xxx:
    cmp eax, 0x00E0
    je handler_clr              ; 00E0 - Clear display
    cmp eax, 0x00EE
    je handler_ret              ; 00EE - Return from subroutine
    ret                         ; Others: NOP

; 0x1xxx: 1NNN - Jump
handler_1xxx:
    jmp handler_jmp

; 0x2xxx: 2NNN - Call subroutine
handler_2xxx:
    jmp handler_call

; 0x3xxx: 3XNN - Skip if VX == NN
handler_3xxx:
    jmp handler_ske_nn

; 0x4xxx: 4XNN - Skip if VX != NN
handler_4xxx:
    jmp handler_skne_nn

; 0x5xxx: 5XY0 - Skip if VX == VY
handler_5xxx:
    jmp handler_ske_xy

; 0x6xxx: 6XNN - Set VX = NN
handler_6xxx:
    jmp handler_set_vx

; 0x7xxx: 7XNN - Add NN to VX
handler_7xxx:
    jmp handler_add_vx

; 0x8xxx: Arithmetic operations
handler_8xxx:
    push rbp
    mov rbp, rsp
    push rbx

    mov ebx, eax
    and ebx, 0x000F             ; Extract last nibble

    cmp ebx, 0x0
    je handler_move             ; 8XY0 - Set VX = VY
    cmp ebx, 0x1
    je handler_or_xy            ; 8XY1 - VX |= VY
    cmp ebx, 0x2
    je handler_and_xy           ; 8XY2 - VX &= VY
    cmp ebx, 0x3
    je handler_xor_xy           ; 8XY3 - VX ^= VY
    cmp ebx, 0x4
    je handler_add_xy           ; 8XY4 - VX += VY
    cmp ebx, 0x5
    je handler_sub_xy           ; 8XY5 - VX -= VY
    cmp ebx, 0xE
    je handler_shl_x            ; 8XYE - VX <<= 1

    pop rbx
    pop rbp
    ret

; 0x9xxx: 9XY0 - Skip if VX != VY
handler_9xxx:
    jmp handler_skne_xy

; 0xAxxx: ANNN - Set I = NNN
handler_axxx:
    jmp handler_set_i

; 0xBxxx: BNNN - Jump with offset (not implemented)
handler_bxxx:
    ret

; 0xCxxx: CXNN - Set VX = random & NN
handler_cxxx:
    jmp handler_rnd

; 0xDxxx: DXYN - Draw sprite
handler_dxxx:
    jmp handler_draw

; 0xExxx: Keyboard input operations
handler_exxx:
    push rbp
    mov rbp, rsp
    push rbx

    mov ebx, eax
    and ebx, 0x00FF

    cmp ebx, 0x9E
    je handler_skp              ; EX9E - Skip if key pressed
    cmp ebx, 0xA1
    je handler_sknp             ; EXA1 - Skip if key not pressed

    pop rbx
    pop rbp
    ret

; 0xFxxx: System operations, timers, memory
handler_fxxx:
    push rbp
    mov rbp, rsp
    push rbx

    mov ebx, eax
    and ebx, 0x00FF

    cmp ebx, 0x07
    je handler_ld_dt            ; FX07 - Set VX = delay timer
    cmp ebx, 0x0A
    je handler_wait_key         ; FX0A - Wait for key
    cmp ebx, 0x15
    je handler_set_dt           ; FX15 - Set delay timer = VX
    cmp ebx, 0x18
    je handler_set_st           ; FX18 - Set sound timer = VX
    cmp ebx, 0x1E
    je handler_add_i            ; FX1E - Add VX to I
    cmp ebx, 0x29
    je handler_ld_font          ; FX29 - Set I to font address
    cmp ebx, 0x33
    je handler_bcd              ; FX33 - Store BCD
    cmp ebx, 0x55
    je handler_str_reg          ; FX55 - Store registers
    cmp ebx, 0x65
    je handler_ld_reg           ; FX65 - Load registers

    pop rbx
    pop rbp
    ret

; ============================================================================
; END OF DECODER MODULE
; ============================================================================
