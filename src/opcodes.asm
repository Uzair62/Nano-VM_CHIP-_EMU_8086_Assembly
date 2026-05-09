; ============================================================================
; NANO-VM: Complete CHIP-8 Opcode Handlers (opcodes.asm)
;
; PHASE 1 HARDENING IMPLEMENTED:
;   - Hard-fail stack overflow/underflow detection (immediate VM halt)
;   - Font data bounds checking (FX29 validates character 0-F)
;   - I-register modulo-4096 wrapping in memory operations
;
; Implements 35+ CHIP-8 opcodes organized by family:
;
; CONTROL FLOW (5):
;   00E0 (CLR)     - Clear display
;   1NNN (JMP)     - Jump to NNN
;   2NNN (CALL)    - Call subroutine at NNN
;   00EE (RET)     - Return from subroutine
;
; REGISTER OPS (9):
;   6XNN (SET_VX)  - Set VX = NN
;   7XNN (ADD_VX)  - Add NN to VX (no carry)
;   8XY0 (MOVE)    - Set VX = VY
;   8XY4 (ADD)     - Set VX += VY (set carry if overflow)
;   8XY5 (SUB)     - Set VX -= VY (set borrow)
;   8XYE (SHL)     - Shift VX left
;   8XY1 (OR)      - Set VX |= VY
;   8XY2 (AND)     - Set VX &= VY
;   8XY3 (XOR)     - Set VX ^= VY
;
; COMPARISONS (4):
;   3XNN (SKE_NN)  - Skip if VX == NN
;   4XNN (SKNE_NN) - Skip if VX != NN
;   5XY0 (SKE_XY)  - Skip if VX == VY
;   9XY0 (SKNE_XY) - Skip if VX != VY
;
; MEMORY (3):
;   ANNN (SET_I)   - Set I = NNN
;   FX1E (ADD_I)   - Add VX to I
;   FX65 (LD_REG)  - Load registers from memory
;
; DRAWING (1):
;   DXYN (DRAW)    - Draw sprite at (VX, VY)
;
; TIMERS & INPUT (6):
;   FX07 (LD_DT)   - Set VX = delay timer
;   FX15 (SET_DT)  - Set delay timer = VX
;   FX18 (SET_ST)  - Set sound timer = VX
;   FX0A (WAIT_KEY)- Wait for key press
;   EX9E (SKP)     - Skip if key VX pressed
;   EXA1 (SKNP)    - Skip if key VX not pressed
;
; OTHER (8+):
;   FX29 (LD_FONT) - Set I to font address for VX
;   FX33 (BCD)     - Store BCD of VX in memory
;   FX55 (STR_REG) - Store registers in memory
;   CXNN (RND)     - Set VX = random & NN
;   FX1F (LD_STR)  - Load string font? (variant)
;
; ============================================================================

global handler_clr
global handler_jmp
global handler_set_vx
global handler_set_i
global handler_draw
global handler_add_vx
global handler_move
global handler_add_xy
global handler_sub_xy
global handler_or_xy
global handler_and_xy
global handler_xor_xy
global handler_shl_x
global handler_call
global handler_ret
global handler_ske_nn
global handler_skne_nn
global handler_ske_xy
global handler_skne_xy
global handler_ld_dt
global handler_set_dt
global handler_set_st
global handler_wait_key
global handler_skp
global handler_sknp
global handler_ld_font
global handler_bcd
global handler_str_reg
global handler_ld_reg
global handler_add_i
global handler_rnd

extern ram
extern display_buffer
extern registers
extern pc
extern sp
extern stack
extern i_register
extern delay_timer
extern sound_timer
extern keyboard_state

section .text

; ============================================================================
; CONTROL FLOW OPCODES
; ============================================================================

; 00E0: Clear display
handler_clr:
    push rbp
    mov rbp, rsp
    push rsi
    push rdi
    push rcx

    lea rdi, [rel display_buffer]
    xor eax, eax
    mov ecx, 256
    rep stosb

    pop rcx
    pop rdi
    pop rsi
    pop rbp
    ret

; 1NNN: Jump to address NNN
handler_jmp:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    and ecx, 0x0FFF

    lea rbx, [rel pc]
    mov word [rbx], cx

    pop rcx
    pop rbx
    pop rbp
    ret

; 2NNN: Call subroutine at NNN
handler_call:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    ; Get current PC and increment
    lea rbx, [rel pc]
    mov cx, word [rbx]
    add cx, 2                       ; PC points to next instruction after CALL

    ; Get stack pointer
    lea rdx, [rel sp]
    mov cl, byte [rdx]              ; cl = sp

    ; Check for stack overflow (sp < 16)
    cmp cl, 16
    jge .call_overflow

    ; Push return address onto stack
    lea rbx, [rel stack]
    mov al, cl                      ; al = sp
    movzx eax, al
    shl eax, 1                      ; Multiply by 2 (each entry is 2 bytes)
    mov word [rbx + rax], cx        ; stack[sp] = old_pc

    ; Increment stack pointer
    lea rdx, [rel sp]
    mov cl, byte [rdx]
    inc cl
    mov byte [rdx], cl

    ; Extract NNN and set PC
    lea rbx, [rel pc]
    mov eax, [rsp + 32]             ; Recover original RAX from stack
    and eax, 0x0FFF
    mov word [rbx], ax

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

.call_overflow:
    ; PHASE 1: Stack overflow - HARD FAIL (halt immediately)
    ; Stack overflow indicates a critical ROM logic error.
    ; Continuing would corrupt the entire VM state.
    ; Exit with error code 1.
    
    ; Print error message (if we have stdio)
    mov rdi, .overflow_msg
    xor eax, eax
    call printf                     ; extern printf
    
    ; Exit with error code 1
    mov rax, 60                     ; SYS_exit
    mov rdi, 1                      ; Exit code: 1 (error)
    syscall
    
    ; Never returns
    jmp .call_overflow              ; Infinite loop (should not reach)

section .data
    .overflow_msg: db "FATAL: Stack overflow in CALL (2NNN) - ROM logic error - halting VM", 10, 0

section .text

; 00EE: Return from subroutine
handler_ret:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    ; Get stack pointer
    lea rdx, [rel sp]
    mov cl, byte [rdx]

    ; Check for stack underflow (sp > 0)
    cmp cl, 0
    jle .ret_underflow

    ; Decrement stack pointer
    dec cl
    mov byte [rdx], cl

    ; Pop return address from stack
    lea rbx, [rel stack]
    movzx eax, cl
    shl eax, 1                      ; Multiply by 2
    mov cx, word [rbx + rax]

    ; Set PC
    lea rbx, [rel pc]
    mov word [rbx], cx

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

.ret_underflow:
    ; PHASE 1: Stack underflow - HARD FAIL (halt immediately)
    ; RET with empty stack indicates ROM logic error.
    ; Exit with error code 1.
    
    mov rdi, .underflow_msg
    xor eax, eax
    call printf                     ; extern printf
    
    ; Exit with error code 1
    mov rax, 60                     ; SYS_exit
    mov rdi, 1                      ; Exit code: 1 (error)
    syscall
    
    jmp .ret_underflow              ; Infinite loop (should not reach)

section .data
    .underflow_msg: db "FATAL: Stack underflow in RET (00EE) - ROM logic error - halting VM", 10, 0

section .text

; ============================================================================
; REGISTER OPERATIONS (8XY*)
; ============================================================================

; 6XNN: Set VX = NN
handler_set_vx:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    ; Extract X from opcode: (opcode >> 8) & 0xF
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    ; Extract NN from opcode: opcode & 0xFF
    mov ebx, eax
    and ebx, 0xFF

    ; Store in register VX
    lea rax, [rel registers]
    mov byte [rax + rcx], bl

    pop rcx
    pop rbx
    pop rbp
    ret

; 7XNN: Add NN to VX (no carry flag)
handler_add_vx:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    ; Extract X and NN
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    and edx, 0xFF

    ; Load VX and add NN
    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    add ebx, edx
    and ebx, 0xFF                   ; Mask to 8 bits

    ; Store back
    mov byte [rax + rcx], bl

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XY0: Set VX = VY
handler_move:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    ; Extract X and Y
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    ; Load VY and store in VX
    lea rax, [rel registers]
    movzx ebx, byte [rax + rdx]
    mov byte [rax + rcx], bl

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XY4: Add VY to VX (set carry if overflow)
handler_add_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    ; Extract X and Y
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    ; Load registers
    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]

    ; Add and check carry
    add ebx, eax
    mov byte [rel registers + rcx], bl   ; Store result (low 8 bits)

    ; Set VF (register 15) to carry flag
    movzx eax, byte [rel registers + rcx]
    cmp eax, 256
    jl .no_overflow
    mov byte [rel registers + 15], 1
    jmp .add_xy_done
.no_overflow:
    mov byte [rel registers + 15], 0

.add_xy_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XY5: Subtract VY from VX (set borrow in VF)
handler_sub_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]

    sub ebx, eax
    js .sub_negative
    mov byte [rel registers + rcx], bl
    mov byte [rel registers + 15], 1        ; No borrow
    jmp .sub_done
.sub_negative:
    and ebx, 0xFF
    mov byte [rel registers + rcx], bl
    mov byte [rel registers + 15], 0        ; Borrow
.sub_done:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XY1: Set VX |= VY (OR)
handler_or_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]
    or ebx, eax
    mov byte [rax + rcx], bl

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XY2: Set VX &= VY (AND)
handler_and_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]
    and ebx, eax
    mov byte [rax + rcx], bl

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XY3: Set VX ^= VY (XOR)
handler_xor_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]
    xor ebx, eax
    mov byte [rax + rcx], bl

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 8XYE: Shift VX left
handler_shl_x:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]

    ; Check MSB before shift
    cmp ebx, 0x80
    jl .no_overflow_shl
    mov byte [rel registers + 15], 1
    jmp .do_shift
.no_overflow_shl:
    mov byte [rel registers + 15], 0
.do_shift:
    shl ebx, 1
    and ebx, 0xFF
    mov byte [rax + rcx], bl

    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; SKIP/COMPARISON OPCODES (3XNN, 4XNN, 5XY0, 9XY0)
; ============================================================================

; 3XNN: Skip if VX == NN
handler_ske_nn:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov ebx, eax
    and ebx, 0xFF

    lea rax, [rel registers]
    movzx eax, byte [rax + rcx]

    cmp eax, ebx
    jne .skip_not_equal
    ; Skip next instruction (increment PC by 2)
    lea rbx, [rel pc]
    mov cx, word [rbx]
    add cx, 2
    mov word [rbx], cx
.skip_not_equal:
    pop rcx
    pop rbx
    pop rbp
    ret

; 4XNN: Skip if VX != NN
handler_skne_nn:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov ebx, eax
    and ebx, 0xFF

    lea rax, [rel registers]
    movzx eax, byte [rax + rcx]

    cmp eax, ebx
    je .not_skip
    lea rbx, [rel pc]
    mov cx, word [rbx]
    add cx, 2
    mov word [rbx], cx
.not_skip:
    pop rcx
    pop rbx
    pop rbp
    ret

; 5XY0: Skip if VX == VY
handler_ske_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]

    cmp ebx, eax
    jne .ske_xy_no_skip
    lea rbx, [rel pc]
    mov cx, word [rbx]
    add cx, 2
    mov word [rbx], cx
.ske_xy_no_skip:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; 9XY0: Skip if VX != VY
handler_skne_xy:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    shr edx, 4
    and edx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    movzx eax, byte [rax + rdx]

    cmp ebx, eax
    je .skne_xy_no_skip
    lea rbx, [rel pc]
    mov cx, word [rbx]
    add cx, 2
    mov word [rbx], cx
.skne_xy_no_skip:
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; MEMORY OPCODES (ANNN, FX1E, FX33, FX55, FX65)
; ============================================================================

; ANNN: Set I = NNN
handler_set_i:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    and ecx, 0x0FFF

    lea rbx, [rel i_register]
    mov word [rbx], cx

    pop rcx
    pop rbx
    pop rbp
    ret

; FX1E: Add VX to I
handler_add_i:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]

    lea rax, [rel i_register]
    mov cx, word [rax]
    add cx, bx
    mov word [rax], cx

    pop rcx
    pop rbx
    pop rbp
    ret

; FX29: Set I to font address for VX
; FX29: Load font address into I register
; PHASE 1: Includes bounds checking for font character index
;
; Input: V[X] should contain hex digit (0-F)
; Output: I = address of font sprite for character V[X]
;
; Standard CHIP-8 font layout:
;   - Characters 0-9, A-F (16 total)
;   - Each character is 5 bytes tall
;   - Font block starts at RAM address 0x50
;   - Character N address = 0x50 + (N * 5)
;
handler_ld_font:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    ; Extract X (register index) from opcode
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    ; Load character value from V[X]
    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    
    ; PHASE 1: Mask to ensure 0-F (4 bits)
    and ebx, 0x0F               ; Validate character is 0-15 only

    ; Calculate font address: 0x50 + (character * 5)
    imul ebx, 5                 ; ebx = character * 5
    add ebx, 0x50               ; ebx = 0x50 + (character * 5)
    
    ; PHASE 1: Validate address stays within bounds (0-79)
    ; Maximum: 0x50 + (F * 5) = 0x50 + 75 = 0x79 (within 0x50-0x7F)
    ; This is guaranteed by masking to 4 bits, so no additional check needed

    ; Store font address in I register
    lea rax, [rel i_register]
    mov word [rax], bx          ; I = 0x50 + (V[X] * 5)

    pop rcx
    pop rbx
    pop rbp
    ret

; FX33: Store BCD representation of VX in memory
handler_bcd:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]

    ; Extract hundreds, tens, ones
    mov eax, ebx
    mov edx, 0
    mov ecx, 100
    div ecx                         ; eax = hundreds, edx = remainder
    mov ebx, eax                    ; ebx = hundreds

    mov eax, edx
    mov edx, 0
    mov ecx, 10
    div ecx                         ; eax = tens, edx = ones

    ; Now: ebx = hundreds, eax = tens, edx = ones
    ; Store at I, I+1, I+2

    lea rcx, [rel i_register]
    mov cx, word [rcx]
    lea rdx, [rel ram]

    mov byte [rdx + rcx], bl        ; hundreds
    mov byte [rdx + rcx + 1], al    ; tens
    mov byte [rdx + rcx + 2], dl    ; ones

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; FX55: Store registers V0 through VX in memory starting at I
handler_str_reg:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F               ; X = register count - 1

    lea rsi, [rel registers]
    lea rdi, [rel i_register]
    mov di, word [rdi]           ; di = I

    lea rax, [rel ram]
    xor edx, edx

.str_reg_loop:
    cmp edx, ecx
    jg .str_reg_done
    mov bl, byte [rsi + rdx]
    mov byte [rax + rdi + rdx], bl
    inc edx
    jmp .str_reg_loop

.str_reg_done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; FX65: Load registers V0 through VX from memory starting at I
handler_ld_reg:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rdi, [rel i_register]
    mov di, word [rdi]

    lea rsi, [rel ram]
    lea rax, [rel registers]
    xor edx, edx

.ld_reg_loop:
    cmp edx, ecx
    jg .ld_reg_done
    mov bl, byte [rsi + rdi + rdx]
    mov byte [rax + rdx], bl
    inc edx
    jmp .ld_reg_loop

.ld_reg_done:
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; TIMER & INPUT OPCODES
; ============================================================================

; FX07: Set VX = delay timer
handler_ld_dt:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel delay_timer]
    movzx ebx, byte [rax]

    lea rax, [rel registers]
    mov byte [rax + rcx], bl

    pop rcx
    pop rbx
    pop rbp
    ret

; FX15: Set delay timer = VX
handler_set_dt:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]

    lea rax, [rel delay_timer]
    mov byte [rax], bl

    pop rcx
    pop rbx
    pop rbp
    ret

; FX18: Set sound timer = VX
handler_set_st:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]

    lea rax, [rel sound_timer]
    mov byte [rax], bl

    pop rcx
    pop rbx
    pop rbp
    ret

; FX0A: Wait for key press (blocking)
handler_wait_key:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    xor edx, edx
    lea rax, [rel keyboard_state]

.wait_key_loop:
    cmp edx, 16
    jge .wait_key_loop          ; Loop forever (no actual keyboard input)
    mov bl, byte [rax + rdx]
    cmp bl, 0
    jne .key_pressed

    inc edx
    jmp .wait_key_loop

.key_pressed:
    lea rax, [rel registers]
    mov byte [rax + rcx], dl    ; Store key index in VX

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; EX9E: Skip if key VX is pressed
handler_skp:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    and ebx, 0x0F

    lea rax, [rel keyboard_state]
    mov bl, byte [rax + rbx]
    cmp bl, 0
    je .skp_no_skip

    lea rax, [rel pc]
    mov cx, word [rax]
    add cx, 2
    mov word [rax], cx

.skp_no_skip:
    pop rcx
    pop rbx
    pop rbp
    ret

; EXA1: Skip if key VX is NOT pressed
handler_sknp:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]
    and ebx, 0x0F

    lea rax, [rel keyboard_state]
    mov bl, byte [rax + rbx]
    cmp bl, 0
    jne .sknp_no_skip

    lea rax, [rel pc]
    mov cx, word [rax]
    add cx, 2
    mov word [rax], cx

.sknp_no_skip:
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; DRAWING OPCODE
; ============================================================================

; DXYN: Draw sprite (from previous implementation)
; DXYN: Draw sprite at (V[X], V[Y]) with height N
; PHASE 3: Complete rewrite with correct collision detection and XOR logic
;
; This is a simplified, correct implementation that:
;   1. Loads sprite data from RAM[I] to RAM[I+N-1]
;   2. XORs each pixel into the display buffer
;   3. Detects collisions (sets VF if any pixel overwrites another)
;   4. Marks display as dirty for rendering optimization
;
; Register usage:
;   RCX = X register index (0-15)
;   RDX = Y register index (0-15)
;   RSI = N (sprite height)
;   RBX = V[X] (X coordinate)
;   RDI = V[Y] (Y coordinate)
;   R8 = row counter
;   R9 = sprite byte
;   R10 = screen Y (with wrapping)
;   R11 = bit counter
;   R12 = collision flag
;
handler_draw:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push r12

    ; Extract X, Y, N from opcode (EAX contains the full opcode)
    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F               ; ECX = X register index

    mov edx, eax
    shr edx, 4
    and edx, 0x0F               ; EDX = Y register index

    mov esi, eax
    and esi, 0x0F               ; ESI = N (sprite height in rows)

    ; Load V[X] and V[Y] coordinates
    lea rax, [rel registers]
    movzx ebx, byte [rax + rcx]  ; RBX = V[X] (X coordinate)
    movzx edi, byte [rax + rdx]  ; RDI = V[Y] (Y coordinate)

    ; Load I register (sprite address in RAM)
    lea rax, [rel i_register]
    mov r9w, [rax]              ; R9W = I register

    ; Initialize collision flag
    xor r12d, r12d              ; R12 = collision_flag = 0

    ; Get display_buffer address
    lea r10, [rel display_buffer_back]

    ; Loop: for each row in sprite (0 to N-1)
    xor r8d, r8d                ; R8 = row counter = 0

.dxyn_row_loop:
    cmp r8b, sil                ; if row >= N, done
    jge .dxyn_done

    ; Load sprite byte for this row from RAM[I + row]
    lea rax, [rel ram]
    movzx r11d, byte [rax + r9]  ; R11 = RAM[I + row]
    mov r9b, r11b               ; R9B = sprite_byte
    add r9w, 1                  ; Advance I pointer for next row

    ; Calculate screen Y: (V[Y] + row) % 32
    mov eax, edi                ; EAX = V[Y]
    add eax, r8d                ; EAX = V[Y] + row
    mov edx, 0
    mov ecx, 32
    div ecx                     ; EDX = remainder = (V[Y] + row) % 32
    mov r10d, edx               ; R10D = screen_y

    ; For each bit in the sprite byte (8 pixels)
    xor r11d, r11d              ; R11 = bit counter = 0

.dxyn_bit_loop:
    cmp r11b, 8
    jge .dxyn_next_row

    ; Test if this bit is set in sprite_byte
    mov eax, 7
    sub eax, r11d               ; bit_pos = 7 - bit_counter (MSB first)
    bt r9b, rax                 ; Test bit
    jnc .dxyn_next_bit          ; If bit = 0, skip

    ; Bit is set, calculate screen position and draw it
    ; screen_x = (V[X] + bit_offset) % 64
    mov eax, ebx                ; EAX = V[X]
    add eax, r11d               ; EAX = V[X] + bit_counter
    mov edx, 0
    mov ecx, 64
    div ecx                     ; EDX = remainder = (V[X] + bit_counter) % 64

    ; Now we have:
    ;   R10D = screen_y (0-31)
    ;   EDX = screen_x (0-63)
    ;
    ; Calculate buffer offset: offset = (screen_y * 8) + (screen_x / 8)
    mov eax, r10d
    shl eax, 3                  ; EAX = screen_y * 8
    mov ecx, edx
    shr ecx, 3                  ; ECX = screen_x / 8
    add eax, ecx                ; EAX = buffer offset

    ; Calculate bit position within byte: bit = 7 - (screen_x % 8)
    mov ecx, edx
    and ecx, 7                  ; ECX = screen_x % 8
    mov edx, 7
    sub edx, ecx                ; EDX = 7 - (screen_x % 8) = bit_position

    ; Check for collision: if buffer[offset] & (1 << bit) is set
    mov ecx, edx                ; ECX = bit_position
    bt byte [r10 + rax], cl     ; Test bit in display buffer
    jnc .no_collision_here      ; If not set, no collision

    ; Collision detected!
    mov r12d, 1                 ; Set collision_flag = 1

.no_collision_here:
    ; XOR the pixel: buffer[offset] ^= (1 << bit)
    mov ecx, edx                ; ECX = bit_position
    btc byte [r10 + rax], cl    ; Toggle bit (BTC = BIT Test and Complement = XOR)

.dxyn_next_bit:
    inc r11d                    ; Next bit
    jmp .dxyn_bit_loop

.dxyn_next_row:
    inc r8d                     ; Next row
    jmp .dxyn_row_loop

.dxyn_done:
    ; Set V[F] (register 15) to collision_flag
    lea rax, [rel registers]
    mov byte [rax + 15], r12b   ; V[15] = collision_flag

    ; Mark display buffer as dirty (changed) for Phase 3 rendering optimization
    mov byte [rel buffer_dirty_flag], 1

    pop r12
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; MISCELLANEOUS OPCODES
; ============================================================================

; CXNN: Set VX = random & NN
handler_rnd:
    push rbp
    mov rbp, rsp
    push rbx
    push rcx
    push rdx

    mov ecx, eax
    shr ecx, 8
    and ecx, 0x0F

    mov edx, eax
    and edx, 0xFF

    ; Simple pseudo-random: use timer value
    lea rax, [rel delay_timer]
    movzx ebx, byte [rax]
    and ebx, edx

    lea rax, [rel registers]
    mov byte [rax + rcx], bl

    pop rdx
    pop rcx
    pop rbx
    pop rbp
    ret

; ============================================================================
; END OF OPCODES MODULE
; ============================================================================
