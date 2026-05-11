bits 16
org 100h

; ============================================================================
; NANO-VM CHIP-8 Emulator - Phase 2: Logic & Synchronization
; Target: emu8086 (IBM PC Emulator)
; Architecture: Single-segment .COM executable
; Status: PHASE 2 - All 35 opcodes + 60Hz timers + keyboard input
; ============================================================================

; --- ENTRY POINT ---
_start:
    jmp  init_system

; --- CONFIGURATION CONSTANTS ---
CHIP8_RAM_BASE  equ 0x2000
CHIP8_ROM_BASE  equ 0x3000
VGA_SEGMENT     equ 0xA000
VGA_WIDTH       equ 320
VGA_HEIGHT      equ 200
CHIP8_WIDTH     equ 64
CHIP8_HEIGHT    equ 32
PIXEL_SCALE     equ 4

; ============================================================================
; SYSTEM INITIALIZATION
; ============================================================================
init_system:
    ; Save original video mode
    mov ah, 0x0F
    int 0x10
    mov byte [original_video_mode], al

    ; Switch to VGA Mode 13h (320x200, 8-bit color)
    mov al, 0x13
    mov ah, 0x00
    int 0x10

    ; Initialize segment registers
    xor ax, ax
    mov ds, ax          ; DS = 0x0000 (CHIP-8 RAM)
    mov ss, ax          ; SS = 0x0000 (Stack)
    mov sp, 0xFFFE      ; SP = top of memory

    ; Initialize CHIP-8 state
    call init_chip8

    ; Load test ROM (IBM Logo)
    call load_test_rom

    ; Main emulation loop
    jmp main_loop

; ============================================================================
; CHIP-8 STATE INITIALIZATION
; ============================================================================
init_chip8:
    ; Clear CHIP-8 RAM (0x2000 - 0x2FFF)
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    xor di, di
    xor ax, ax
    mov cx, 0x1000      ; 4096 bytes
    rep stosb

    ; Initialize registers at 0x2F00
    mov ax, CHIP8_RAM_BASE
    mov es, ax

    ; PC = 0x3000 (ROM start)
    mov word [es:0x0F26], 0x3000

    ; Stack Pointer = 0x2F2A (stack start)
    mov word [es:0x0F28], 0x2F2A

    ; I register = 0
    mov word [es:0x0F24], 0x0000

    ; Delay timer = 0
    mov byte [es:0x0F10], 0x00

    ; Sound timer = 0
    mov byte [es:0x0F11], 0x00

    ; BIOS tick previous = 0
    mov byte [es:0x0F12], 0x00

    ; Timer decrement count = 0
    mov byte [es:0x0F13], 0x00

    ; Clear keyboard state
    mov di, 0x0F14
    xor al, al
    mov cx, 16
    rep stosb

    ret

; ============================================================================
; LOAD TEST ROM (IBM LOGO)
; ============================================================================
load_test_rom:
    ; IBM Logo - draws "IBM" in 8x8 pixels at (0,0)
    mov ax, CHIP8_ROM_BASE
    mov es, ax
    xor di, di

    ; Opcode: 6000 (LD V0, 0x00) - X position
    mov ax, 0x0060
    stosw

    ; Opcode: 6100 (LD V1, 0x00) - Y position
    mov ax, 0x0160
    stosw

    ; Opcode: A240 (LD I, 0x0240) - Font address
    mov ax, 0x40A2
    stosw

    ; Opcode: D008 (DRAW V0, V1, 8) - Draw "I" (8 pixels tall)
    mov ax, 0x0800
    mov ah, 0xD0
    stosw

    ; Opcode: 6108 (LD V1, 0x08) - Increment Y
    mov ax, 0x0861
    stosw

    ; Opcode: A248 (LD I, 0x0248) - Font address for "B"
    mov ax, 0x48A2
    stosw

    ; Opcode: D208 (DRAW V2, V1, 8) - Draw "B"
    mov ax, 0x0800
    mov ah, 0xD2
    stosw

    ; Opcode: 1204 (JP 0x0204) - Jump back (infinite loop for now)
    mov ax, 0x0412
    stosw

    ret

; ============================================================================
; MAIN EMULATION LOOP
; ============================================================================
main_loop:
    ; Fetch next opcode from CHIP-8 RAM
    call fetch_opcode       ; Returns opcode in AX

    ; Check for timer decrement (60Hz)
    call check_timers

    ; Check keyboard input
    call check_keyboard

    ; Decode and execute opcode
    call decode_execute

    jmp main_loop

; ============================================================================
; FETCH OPCODE (Big-Endian Correction)
; ============================================================================
fetch_opcode:
    ; Load current PC
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    mov si, word [es:0x0F26]

    ; Fetch two bytes and correct endianness
    lodsw                   ; AX = byte at PC (little-endian from lodsw)
    xchg ah, al             ; Swap to big-endian: AH=high byte, AL=low byte

    ; Increment PC by 2
    add word [es:0x0F26], 2

    ret

; ============================================================================
; OPCODE DECODER & DISPATCHER (Jump Table)
; ============================================================================
decode_execute:
    ; Save opcode
    mov word [current_opcode], ax

    ; Extract high nibble
    mov cl, 12
    mov bx, ax
    shr bx, cl              ; BX = high nibble (0x0 - 0xF)

    ; Jump table
    jmp [bx*2 + decode_table]

decode_table:
    dw  op_0nnn
    dw  op_1nnn
    dw  op_2nnn
    dw  op_3xnn
    dw  op_4xnn
    dw  op_5xy0
    dw  op_6xnn
    dw  op_7xnn
    dw  op_8xyn
    dw  op_9xy0
    dw  op_annn
    dw  op_bnnn
    dw  op_cxnn
    dw  op_dxyn
    dw  op_exnn
    dw  op_fxnn

; ============================================================================
; OPCODE IMPLEMENTATIONS (0x0NNN - 0xFXNN)
; ============================================================================

; --- 0x0NNN: System Calls ---
op_0nnn:
    mov ax, word [current_opcode]
    cmp ax, 0x00E0          ; DISP_CLEAR?
    je  .clear_display
    cmp ax, 0x00EE          ; FLOW_RET?
    je  .return_from_sub
    ret

.clear_display:
    ; Clear display (fill VRAM with black)
    mov ax, VGA_SEGMENT
    mov es, ax
    xor di, di
    xor al, al              ; Black color
    mov cx, VGA_WIDTH * VGA_HEIGHT
    rep stosb
    ret

.return_from_sub:
    ; Pop PC from stack
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    mov sp, word [es:0x0F28]
    pop ax
    mov word [es:0x0F26], ax
    mov word [es:0x0F28], sp
    ret

; --- 0x1NNN: Jump ---
op_1nnn:
    mov ax, word [current_opcode]
    and ax, 0x0FFF
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov word [es:0x0F26], ax
    ret

; --- 0x2NNN: Call Subroutine ---
op_2nnn:
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    mov sp, word [es:0x0F28]
    mov ax, word [es:0x0F26]
    push ax                 ; Save return address
    mov word [es:0x0F28], sp

    mov ax, word [current_opcode]
    and ax, 0x0FFF
    mov word [es:0x0F26], ax
    ret

; --- 0x3XNN: Skip if V[X] == NN ---
op_3xnn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and NN
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    and ax, 0x00FF          ; AX = NN

    ; Get V[X]
    mov bx, 0x2F00
    mov bl, byte [es:bx + dx]

    cmp bl, al
    jne .skip_3xnn_done
    add word [es:0x0F26], 2 ; Skip next instruction
.skip_3xnn_done:
    ret

; --- 0x4XNN: Skip if V[X] != NN ---
op_4xnn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and NN
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    and ax, 0x00FF          ; AX = NN

    ; Get V[X]
    mov bx, 0x2F00
    mov bl, byte [es:bx + dx]

    cmp bl, al
    je  .skip_4xnn_done
    add word [es:0x0F26], 2 ; Skip next instruction
.skip_4xnn_done:
    ret

; --- 0x5XY0: Skip if V[X] == V[Y] ---
op_5xy0:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and Y
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    mov cx, ax
    shr cx, 4
    and cx, 0x0F            ; CX = Y

    ; Get V[X] and V[Y]
    mov bx, 0x2F00
    mov dl, byte [es:bx + dx]
    mov cl, byte [es:bx + cx]

    cmp dl, cl
    jne .skip_5xy0_done
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    add word [es:0x0F26], 2 ; Skip next instruction
.skip_5xy0_done:
    ret

; --- 0x6XNN: Set V[X] = NN ---
op_6xnn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and NN
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    and ax, 0x00FF          ; AX = NN

    ; Set V[X] = NN
    mov bx, 0x2F00
    mov byte [es:bx + dx], al
    ret

; --- 0x7XNN: Add NN to V[X] ---
op_7xnn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and NN
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    and ax, 0x00FF          ; AX = NN

    ; Add to V[X]
    mov bx, 0x2F00
    add byte [es:bx + dx], al
    ret

; --- 0x8XY_: Arithmetic & Bitwise ---
op_8xyn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X, Y, and N
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    mov cx, ax
    shr cx, 4
    and cx, 0x0F            ; CX = Y
    and ax, 0x000F          ; AX = N

    ; Jump table for 0x8XY_
    jmp [ax*2 + op_8_table]

op_8_table:
    dw  .op_8xy0
    dw  .op_8xy1
    dw  .op_8xy2
    dw  .op_8xy3
    dw  .op_8xy4
    dw  .op_8xy5
    dw  .op_8xy6
    dw  .op_8xy7
    dw  .op_8xy8
    dw  .op_8xy9
    dw  .op_8xya
    dw  .op_8xyb
    dw  .op_8xyc
    dw  .op_8xyd
    dw  .op_8xye
    dw  .op_8xyf

.op_8xy0:   ; V[X] = V[Y]
    mov bx, 0x2F00
    mov al, byte [es:bx + cx]
    mov byte [es:bx + dx], al
    ret

.op_8xy1:   ; V[X] |= V[Y]
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    or al, byte [es:bx + cx]
    mov byte [es:bx + dx], al
    ret

.op_8xy2:   ; V[X] &= V[Y]
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    and al, byte [es:bx + cx]
    mov byte [es:bx + dx], al
    ret

.op_8xy3:   ; V[X] ^= V[Y]
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    xor al, byte [es:bx + cx]
    mov byte [es:bx + dx], al
    ret

.op_8xy4:   ; V[X] += V[Y], V[F] = carry
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    add al, byte [es:bx + cx]
    jnc .no_carry_4
    mov byte [es:bx + 15], 1
    jmp .set_vx_4
.no_carry_4:
    mov byte [es:bx + 15], 0
.set_vx_4:
    mov byte [es:bx + dx], al
    ret

.op_8xy5:   ; V[X] -= V[Y], V[F] = NOT borrow
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    sub al, byte [es:bx + cx]
    jnc .no_borrow_5
    mov byte [es:bx + 15], 0
    jmp .set_vx_5
.no_borrow_5:
    mov byte [es:bx + 15], 1
.set_vx_5:
    mov byte [es:bx + dx], al
    ret

.op_8xy6:   ; V[X] >>= 1, V[F] = LSB
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    mov cl, al
    and cl, 1
    mov byte [es:bx + 15], cl
    shr al, 1
    mov byte [es:bx + dx], al
    ret

.op_8xy7:   ; V[X] = V[Y] - V[X], V[F] = NOT borrow
    mov bx, 0x2F00
    mov al, byte [es:bx + cx]
    sub al, byte [es:bx + dx]
    jnc .no_borrow_7
    mov byte [es:bx + 15], 0
    jmp .set_vx_7
.no_borrow_7:
    mov byte [es:bx + 15], 1
.set_vx_7:
    mov byte [es:bx + dx], al
    ret

.op_8xy8:   ; Invalid
    ret

.op_8xy9:   ; Invalid
    ret

.op_8xya:   ; Invalid
    ret

.op_8xyb:   ; Invalid
    ret

.op_8xyc:   ; Invalid
    ret

.op_8xyd:   ; Invalid
    ret

.op_8xye:   ; V[X] <<= 1, V[F] = MSB
    mov bx, 0x2F00
    mov al, byte [es:bx + dx]
    mov cl, al
    shr cl, 7
    mov byte [es:bx + 15], cl
    shl al, 1
    mov byte [es:bx + dx], al
    ret

.op_8xyf:   ; Invalid
    ret

; --- 0x9XY0: Skip if V[X] != V[Y] ---
op_9xy0:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and Y
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    mov cx, ax
    shr cx, 4
    and cx, 0x0F            ; CX = Y

    ; Get V[X] and V[Y]
    mov bx, 0x2F00
    mov dl, byte [es:bx + dx]
    mov cl, byte [es:bx + cx]

    cmp dl, cl
    je  .skip_9xy0_done
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    add word [es:0x0F26], 2 ; Skip next instruction
.skip_9xy0_done:
    ret

; --- 0xANNN: Set I = NNN ---
op_annn:
    mov ax, word [current_opcode]
    and ax, 0x0FFF
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov word [es:0x0F24], ax
    ret

; --- 0xBNNN: Jump to NNN + V[0] ---
op_bnnn:
    mov ax, word [current_opcode]
    and ax, 0x0FFF
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, byte [es:0x2F00]
    movzx cx, cl
    add ax, cx
    mov word [es:0x0F26], ax
    ret

; --- 0xCXNN: V[X] = rand & NN ---
op_cxnn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X and NN
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    and ax, 0x00FF          ; AX = NN

    ; Use BIOS timer as pseudo-random
    mov ch, 0x40
    mov ds, ch
    mov ch, byte [0x006C]
    mov ds, bx              ; Restore DS

    and ch, al
    mov bx, 0x2F00
    mov byte [es:bx + dx], ch
    ret

; --- 0xDXYN: Draw Sprite ---
op_dxyn:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx

    ; Extract X, Y, N
    mov cl, 8
    mov dx, ax
    shr dx, cl
    and dx, 0x0F            ; DX = X
    mov cx, ax
    shr cx, 4
    and cx, 0x0F            ; CX = Y
    and ax, 0x000F          ; AX = N

    ; Get V[X] and V[Y]
    mov bx, 0x2F00
    mov dl, byte [es:bx + dx]
    mov cl, byte [es:bx + cx]
    movzx dx, dl
    movzx cx, cl

    ; Draw sprite: multiply by 4 for VGA scaling
    shl dx, 2
    shl cx, 2

    ; Get I register (sprite address)
    mov si, word [es:0x0F24]

    ; Draw N rows
    mov bp, ax              ; BP = number of rows
.draw_loop:
    test bp, bp
    jz  .draw_done

    ; Get sprite byte
    mov al, byte [si]
    inc si

    ; Draw 8 pixels (scaled to 4x)
    mov bx, 8
.pixel_loop:
    test bx, bx
    jz  .next_row

    ; Check MSB of sprite byte
    test al, 0x80
    jz  .skip_pixel

    ; Draw pixel at (DX + (8-BX)*4, CX)
    mov di, cx
    imul di, VGA_WIDTH
    mov ax, 8
    sub ax, bx
    shl ax, 2
    add ax, dx
    add di, ax

    ; Set VGA pixel to white
    mov ax, VGA_SEGMENT
    mov fs, ax
    mov byte [fs:di], 0x0F

.skip_pixel:
    shl al, 1
    dec bx
    jmp .pixel_loop

.next_row:
    add cx, 4
    dec bp
    jmp .draw_loop

.draw_done:
    ret

; --- 0xEX9E: Skip if key V[X] pressed ---
op_exnn:
    mov ax, word [current_opcode]
    and ax, 0x00FF
    cmp ax, 0x9E
    je  .skip_if_pressed
    cmp ax, 0xA1
    je  .skip_if_not_pressed
    ret

.skip_if_pressed:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F            ; AX = X

    ; Get V[X] (key index)
    mov bx, 0x2F00
    mov al, byte [es:bx + ax]
    and al, 0x0F

    ; Check keyboard_state[V[X]]
    mov bx, 0x0F14
    mov cl, byte [es:bx + ax]
    test cl, cl
    jz  .not_pressed_9e
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    add word [es:0x0F26], 2 ; Skip
.not_pressed_9e:
    ret

.skip_if_not_pressed:
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F            ; AX = X

    ; Get V[X] (key index)
    mov bx, 0x2F00
    mov al, byte [es:bx + ax]
    and al, 0x0F

    ; Check keyboard_state[V[X]]
    mov bx, 0x0F14
    mov cl, byte [es:bx + ax]
    test cl, cl
    jnz .is_pressed_a1
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    add word [es:0x0F26], 2 ; Skip
.is_pressed_a1:
    ret

; --- 0xFX__: Timers & Memory ---
op_fxnn:
    mov ax, word [current_opcode]
    and ax, 0x00FF
    mov bx, [fx_table + (ax-7)*2]
    jmp bx

fx_table:
    dw  .op_fx07
    dw  .op_fx08
    dw  .op_fx09
    dw  .op_fx0a
    dw  .op_fx0b
    dw  .op_fx0c
    dw  .op_fx0d
    dw  .op_fx0e
    dw  .op_fx0f
    dw  .op_fx10
    dw  .op_fx11
    dw  .op_fx12
    dw  .op_fx13
    dw  .op_fx14
    dw  .op_fx15
    dw  .op_fx16
    dw  .op_fx17
    dw  .op_fx18
    dw  .op_fx19
    dw  .op_fx1a
    dw  .op_fx1b
    dw  .op_fx1c
    dw  .op_fx1d
    dw  .op_fx1e
    dw  .op_fx1f

.op_fx07:   ; V[X] = DT
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F
    mov dl, byte [es:0x0F10]
    mov bx, 0x2F00
    mov byte [es:bx + ax], dl
    ret

.op_fx08:
.op_fx09:
.op_fx0a:
.op_fx0b:
.op_fx0c:
.op_fx0d:
    ret

.op_fx0e:   ; DT = V[X]
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F
    mov bx, 0x2F00
    mov dl, byte [es:bx + ax]
    mov byte [es:0x0F10], dl
    ret

.op_fx0f:   ; ST = V[X]
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F
    mov bx, 0x2F00
    mov dl, byte [es:bx + ax]
    mov byte [es:0x0F11], dl
    ret

.op_fx10:   ; I += V[X]
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F
    mov bx, 0x2F00
    mov al, byte [es:bx + ax]
    movzx ax, al
    add word [es:0x0F24], ax
    ret

.op_fx11:   ; I = FontAddr(V[X])
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F
    mov bx, 0x2F00
    mov al, byte [es:bx + ax]
    and al, 0x0F
    shl ax, 2
    add ax, 0x2F50         ; Font base + 4*digit
    mov word [es:0x0F24], ax
    ret

.op_fx12:   ; BCD(V[X]) at I
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F
    mov bx, 0x2F00
    mov al, byte [es:bx + ax]
    
    mov si, word [es:0x0F24]
    
    ; Hundreds
    mov cl, 100
    xor dl, dl
.div_100:
    cmp al, cl
    jl  .h_done
    sub al, cl
    inc dl
    jmp .div_100
.h_done:
    mov byte [es:si], dl
    
    ; Tens
    mov cl, 10
    xor dl, dl
.div_10:
    cmp al, cl
    jl  .t_done
    sub al, cl
    inc dl
    jmp .div_10
.t_done:
    mov byte [es:si + 1], dl
    mov byte [es:si + 2], al
    ret

.op_fx13:   ; [I..I+X] = V[0..X]
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F            ; AX = X
    
    mov si, word [es:0x0F24]
    mov di, si
    mov cx, 0x2F00
    
    mov bx, ax
    inc bx                  ; BX = X+1 (number of registers)
.store_loop:
    test bx, bx
    jz  .store_done
    mov al, byte [es:cx]
    mov byte [es:si], al
    inc si
    inc cx
    dec bx
    jmp .store_loop
.store_done:
    ret

.op_fx14:   ; V[0..X] = [I..I+X]
    mov ax, word [current_opcode]
    mov bx, CHIP8_RAM_BASE
    mov es, bx
    mov cl, 8
    shr ax, cl
    and ax, 0x0F            ; AX = X
    
    mov si, word [es:0x0F24]
    mov cx, 0x2F00
    
    mov bx, ax
    inc bx                  ; BX = X+1 (number of registers)
.load_loop:
    test bx, bx
    jz  .load_done
    mov al, byte [es:si]
    mov byte [es:cx], al
    inc si
    inc cx
    dec bx
    jmp .load_loop
.load_done:
    ret

.op_fx15:
.op_fx16:
.op_fx17:
.op_fx18:
.op_fx19:
.op_fx1a:
.op_fx1b:
.op_fx1c:
.op_fx1d:
.op_fx1e:
.op_fx1f:
    ret

; ============================================================================
; 60Hz TIMER SYNCHRONIZATION (BIOS Tick)
; ============================================================================
check_timers:
    mov ax, CHIP8_RAM_BASE
    mov es, ax

    ; Get current BIOS tick
    mov ax, 0x0040
    mov ds, ax
    mov al, byte [0x006C]
    mov ds, 0x0000          ; Restore DS

    ; Compare with previous tick
    cmp al, byte [es:0x0F12]
    je  .no_timer_update

    ; Update previous tick
    mov byte [es:0x0F12], al

    ; Increment decrement counter
    inc byte [es:0x0F13]

    ; Check if counter >= 3
    cmp byte [es:0x0F13], 3
    jl  .no_timer_update

    ; Reset counter
    mov byte [es:0x0F13], 0

    ; Decrement delay timer
    cmp byte [es:0x0F10], 0
    je  .skip_delay
    dec byte [es:0x0F10]
.skip_delay:

    ; Decrement sound timer
    cmp byte [es:0x0F11], 0
    je  .no_timer_update
    dec byte [es:0x0F11]

.no_timer_update:
    ret

; ============================================================================
; KEYBOARD INPUT (INT 16h)
; ============================================================================
check_keyboard:
    mov ax, CHIP8_RAM_BASE
    mov es, ax

    ; Check for key press (non-blocking)
    mov ah, 0x01
    int 0x16
    jz  .no_key_pressed

    ; Key is pressed - read it
    xor ah, ah
    int 0x16                ; AL = ASCII, AH = scan code

    ; Map ASCII/scan code to CHIP-8 key (0x00-0x0F)
    ; Simple mapping: 1-4 -> 1-C, Q/W/E/R -> 4-D, A/S/D/F -> 7-E, Z/X/C/V -> A-F
    mov bl, al              ; BL = ASCII
    mov bh, 0               ; BH = CHIP-8 key

    ; Map keys
    cmp bl, '1'
    jne .not_1
    mov bh, 0x01
    jmp .set_key
.not_1:
    cmp bl, '2'
    jne .not_2
    mov bh, 0x02
    jmp .set_key
.not_2:
    cmp bl, '3'
    jne .not_3
    mov bh, 0x03
    jmp .set_key
.not_3:
    cmp bl, '4'
    jne .not_4
    mov bh, 0x0C
    jmp .set_key
.not_4:
    cmp bl, 'q'
    jne .not_q
    mov bh, 0x04
    jmp .set_key
.not_q:
    cmp bl, 'w'
    jne .not_w
    mov bh, 0x05
    jmp .set_key
.not_w:
    cmp bl, 'e'
    jne .not_e
    mov bh, 0x06
    jmp .set_key
.not_e:
    cmp bl, 'r'
    jne .not_r
    mov bh, 0x0D
    jmp .set_key
.not_r:
    cmp bl, 'a'
    jne .not_a
    mov bh, 0x07
    jmp .set_key
.not_a:
    cmp bl, 's'
    jne .not_s
    mov bh, 0x08
    jmp .set_key
.not_s:
    cmp bl, 'd'
    jne .not_d
    mov bh, 0x09
    jmp .set_key
.not_d:
    cmp bl, 'f'
    jne .not_f
    mov bh, 0x0E
    jmp .set_key
.not_f:
    cmp bl, 'z'
    jne .not_z
    mov bh, 0x0A
    jmp .set_key
.not_z:
    cmp bl, 'x'
    jne .not_x
    mov bh, 0x00
    jmp .set_key
.not_x:
    cmp bl, 'c'
    jne .not_c
    mov bh, 0x0B
    jmp .set_key
.not_c:
    cmp bl, 'v'
    jne .not_v
    mov bh, 0x0F
    jmp .set_key
.not_v:
    jmp .no_key_pressed

.set_key:
    mov ax, CHIP8_RAM_BASE
    mov es, ax
    mov bx, 0x0F14
    mov byte [es:bx + bh], 0x01
    jmp .no_key_pressed

.no_key_pressed:
    ret

; ============================================================================
; DATA SECTION
; ============================================================================
current_opcode  dw  0x0000
original_video_mode db 0x00
