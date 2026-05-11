; ============================================================================
; NANO-VM: Phase 1 - Main Program (.COM Executable for emu8086)
; phase1_main.asm
;
; Entry Point for CHIP-8 emulator targeting 16-bit Intel 8086 (emu8086)
; Executable Format: .COM (single segment, ORG 100h)
;
; Phase 1 Responsibilities:
; 1. Initialize CPU state and memory (PC, SP, registers)
; 2. Set up VGA Mode 13h graphics environment
; 3. Load IBM Logo ROM into RAM at 0x2200 (VM address 0x200)
; 4. Implement fetch-decode-execute main loop
; 5. Render display on each cycle
; 6. Handle basic keyboard input
;
; Memory Map (Relative to Segment 0x0000):
; 0x0000-0x00FF   : DOS PSP (Program Segment Prefix)
; 0x0100          : Code Start (ORG directive)
; 0x0100-0x1FFF   : Code & Data (~7.75KB)
; 0x2000-0x5FFF   : CHIP-8 VM State (16KB)
;   0x2000-0x204F : Font data
;   0x2050-0x207F : Stack space (32B)
;   0x2080+       : Registers & VM state
;   0x2200-0x27FF : Program RAM (4KB for ROM)
; 0x6000-0xFFFE   : Host Stack (~40KB buffer)
;
; Segment Discipline:
; - CS = DS = SS = 0x0000 (all code/data in one segment)
; - ES = 0xA000 (during graphics operations, points to VGA)
; - SP = 0xFFFE (maximum stack, never overwrites VM state)
; ============================================================================

bits 16
org 100h

; ============================================================================
; SECTION: Data Definitions
; ============================================================================

section .data

    ; --- CHIP-8 State Variables (Memory-resident) ---
    ; These offsets are relative to segment start (0x0000)
    
    ; Virtual Machine State
    vm_pc:              dw 0x0200       ; Program Counter (CHIP-8 VM address)
    vm_sp:              db 0x00         ; Stack Pointer (0-15 = stack depth)
    vm_i_register:      dw 0x0000       ; I register (address register)
    vm_delay_timer:     db 0x00         ; Delay timer (60Hz decrement)
    vm_sound_timer:     db 0x00         ; Sound timer (60Hz decrement)
    
    ; General-purpose registers V0-VF (16 bytes)
    vm_registers:       db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    
    ; VM Stack (16 * 2B = 32B for nested calls)
    vm_stack:           dw 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    
    ; Last fetched opcode (for debugging)
    last_opcode:        dw 0x0000
    
    ; Graphics buffer (temporary, used for pixel rendering)
    graphics_vram_offset: dw 0x0000
    
    ; Keyboard state (16 keys, 1 byte each)
    keyboard_state:     db 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    
    ; --- IBM LOGO ROM Data ---
    ; Classic 8-row by 4-byte sprite pattern (IBM logo display)
    ; Each byte = 8 pixels (bit 7 to bit 0, left to right)
    rom_data:
        db 0xF0, 0x90, 0x90, 0xF0      ; Row 0: "I"
        db 0x90, 0x90, 0x90, 0x90      ; Row 1
        db 0xF0, 0x10, 0xF0, 0x80      ; Row 2: "B"
        db 0xF0, 0x80, 0xF0, 0x10      ; Row 3
        db 0x10, 0xF0, 0x10, 0x10      ; Row 4: "M"
        db 0x10, 0x10, 0x10, 0x10      ; Row 5
        db 0xF0, 0x90, 0xF0, 0x90      ; Row 6
        db 0xF0, 0x90, 0x90, 0x90      ; Row 7
    
    rom_size:           equ $ - rom_data    ; ROM size = 32 bytes
    
    ; --- VGA Mode 13h Constants ---
    ; VGA 320x200 resolution, 8-bit color, direct memory at 0xA000
    vga_width:          dw 320
    vga_height:         dw 200
    vga_segment:        dw 0xA000
    
    ; Scaling factor (4x4 pixels per CHIP-8 pixel)
    pixel_scale:        db 4
    
    ; Color palette
    color_black:        db 0x00
    color_white:        db 0xFF
    color_border:       db 0x80         ; Gray border

; ============================================================================
; SECTION: Code
; ============================================================================

section .text

; ============================================================================
; ENTRY POINT: Startup
; ============================================================================

start:
    ; Standard entry for .COM executable
    ; No stack setup needed; DOS provides clean state
    
    call init_vga_mode13h               ; Set up VGA graphics mode
    call load_rom_into_memory           ; Copy ROM to 0x2200
    call init_vm_state                  ; Initialize CPU state
    
    ; Main execution loop
.main_loop:
    call fetch_opcode                   ; Fetch next 16-bit opcode
    call decode_dispatch                ; Decode and dispatch
    call render_frame                   ; Update display
    call update_timers                  ; Decrement delay/sound timers
    call handle_keyboard_input          ; Check for key presses
    
    ; Minimal delay for 60 Hz simulation (~16.7ms per frame)
    mov ah, 0x2C                        ; INT 21h function for system time
    int 0x21                            ; Returns time in CX (days), DX (ms since midnight)
    
    jmp .main_loop                      ; Loop forever

; ============================================================================
; SUBROUTINE: init_vga_mode13h
; Initialize VGA to Mode 13h (320x200, 8-bit color)
; ============================================================================

init_vga_mode13h:
    push ax
    
    ; Set VGA mode 13h (320x200, 256-color graphics)
    mov al, 0x13                        ; Mode 13h
    mov ah, 0x00                        ; INT 10h: Set video mode
    int 0x10
    
    ; Clear screen to black
    call clear_vga_screen
    
    pop ax
    ret

; ============================================================================
; SUBROUTINE: clear_vga_screen
; Fill entire VGA screen with black (0x00)
; ============================================================================

clear_vga_screen:
    push ax
    push cx
    push di
    push es
    
    ; Set ES to VGA segment
    mov ax, 0xA000
    mov es, ax
    
    ; Clear all 64000 pixels (320 * 200)
    xor di, di                          ; Start at offset 0
    xor al, al                          ; AL = 0x00 (black)
    mov cx, 32000                       ; 32000 words = 64000 bytes
    rep stosw                           ; Fill ES:DI with AX, increment DI
    
    pop es
    pop di
    pop cx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: load_rom_into_memory
; Copy ROM data from .data section to 0x2200 (CHIP-8 0x200 address)
; ============================================================================

load_rom_into_memory:
    push ax
    push cx
    push si
    push di
    
    ; Source: rom_data (absolute address in .data section)
    lea si, [rom_data]                  ; SI = address of ROM data
    
    ; Destination: 0x2200 (VM address 0x200 at memory base 0x2000)
    mov di, 0x2200
    
    ; Copy 32 bytes (rom_size)
    mov cx, rom_size
    
    ; DS is already 0x0000, so direct copy
.copy_loop:
    mov al, [si]
    mov [di], al
    inc si
    inc di
    loop .copy_loop
    
    pop di
    pop si
    pop cx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: init_vm_state
; Initialize CHIP-8 CPU state: PC, SP, registers, timers
; ============================================================================

init_vm_state:
    push ax
    push cx
    push di
    
    ; Set PC to 0x200 (standard CHIP-8 program start)
    mov word [vm_pc], 0x0200
    
    ; Clear stack pointer
    mov byte [vm_sp], 0x00
    
    ; Clear all 16 general-purpose registers
    xor al, al
    mov di, vm_registers
    mov cx, 16
.clear_regs:
    mov [di], al
    inc di
    loop .clear_regs
    
    ; Clear I register
    mov word [vm_i_register], 0x0000
    
    ; Clear timers
    mov byte [vm_delay_timer], 0x00
    mov byte [vm_sound_timer], 0x00
    
    ; Clear keyboard state
    mov di, keyboard_state
    mov cx, 16
.clear_kbd:
    mov [di], al
    inc di
    loop .clear_kbd
    
    pop di
    pop cx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: fetch_opcode
; Fetch 16-bit CHIP-8 opcode from RAM at [PC]
; Result: AX = opcode (big-endian corrected)
; Side effect: Increments PC by 2
; ============================================================================

fetch_opcode:
    push bx
    push si
    
    ; Load PC into SI and add VM base offset (0x2000)
    mov si, [vm_pc]
    add si, 0x2000
    
    ; Load word: AX = [SI]
    lodsw                               ; AX = [SI], SI += 2
    
    ; CRITICAL: Swap bytes (CHIP-8 is big-endian, 8086 is little-endian)
    xchg ah, al                         ; Swap: AX = big-endian aligned
    
    ; Cache opcode for debugging
    mov [last_opcode], ax
    
    ; Increment PC by 2 in VM space
    add word [vm_pc], 0x0002
    
    pop si
    pop bx
    ret

; ============================================================================
; SUBROUTINE: decode_dispatch
; Decode opcode in AX and dispatch to appropriate handler
; For Phase 1: Implement minimal jump table covering all 16 opcode families
; ============================================================================

decode_dispatch:
    push ax
    push bx
    push cx
    
    ; AX contains the opcode from fetch_opcode
    ; Extract the high nibble to determine opcode family
    mov cl, 12                          ; Shift amount
    mov bx, ax
    shr bx, cl                          ; BX = opcode family (0x0-0xF)
    
    ; Jump table dispatch
    cmp bx, 0x00
    je .op_0nnn_
    cmp bx, 0x01
    je .op_1nnn_
    cmp bx, 0x02
    je .op_2nnn_
    cmp bx, 0x03
    je .op_3nnn_
    cmp bx, 0x04
    je .op_4nnn_
    cmp bx, 0x05
    je .op_5nnn_
    cmp bx, 0x06
    je .op_6nnn_
    cmp bx, 0x07
    je .op_7nnn_
    cmp bx, 0x08
    je .op_8nnn_
    cmp bx, 0x09
    je .op_9nnn_
    cmp bx, 0x0A
    je .op_annn_
    cmp bx, 0x0B
    je .op_bnnn_
    cmp bx, 0x0C
    je .op_cnnn_
    cmp bx, 0x0D
    je .op_dnnn_
    cmp bx, 0x0E
    je .op_ennn_
    cmp bx, 0x0F
    je .op_fnnn_
    
    jmp .decode_done                    ; Unknown opcode, skip
    
.op_0nnn_:
    ; 0nnn: Execute machine language routine (usually CLEAR SCREEN)
    ; For IBM Logo test: implement DXYN (draw sprite)
    jmp .decode_done
    
.op_1nnn_:
    ; 1nnn: Jump to address NNN
    mov [vm_pc], ax
    and word [vm_pc], 0x0FFF            ; Mask to 12-bit address
    jmp .decode_done
    
.op_2nnn_:
    ; 2nnn: Call subroutine at NNN
    jmp .decode_done
    
.op_3nnn_:
    ; 3xkk: Skip next instruction if Vx == kk
    jmp .decode_done
    
.op_4nnn_:
    ; 4xkk: Skip next instruction if Vx != kk
    jmp .decode_done
    
.op_5nnn_:
    ; 5xy0: Skip next instruction if Vx == Vy
    jmp .decode_done
    
.op_6nnn_:
    ; 6xkk: Set Vx = kk
    jmp .decode_done
    
.op_7nnn_:
    ; 7xkk: Add kk to Vx
    jmp .decode_done
    
.op_8nnn_:
    ; 8xy?: Register operations (add, sub, etc.)
    jmp .decode_done
    
.op_9nnn_:
    ; 9xy0: Skip next instruction if Vx != Vy
    jmp .decode_done
    
.op_annn_:
    ; Annn: Set I = nnn
    mov word [vm_i_register], ax
    and word [vm_i_register], 0x0FFF
    jmp .decode_done
    
.op_bnnn_:
    ; Bnnn: Jump to nnn + V0
    jmp .decode_done
    
.op_cnnn_:
    ; Cxkk: Set Vx = random & kk
    jmp .decode_done
    
.op_dnnn_:
    ; Dxyn: Draw sprite at (Vx, Vy) with height n
    ; **THIS IS THE CRITICAL OPCODE FOR IBM LOGO RENDERING**
    call opcode_draw_sprite
    jmp .decode_done
    
.op_ennn_:
    ; Ex???: Keyboard operations
    jmp .decode_done
    
.op_fnnn_:
    ; Fx???: Miscellaneous (timers, etc.)
    jmp .decode_done
    
.decode_done:
    pop cx
    pop bx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: opcode_draw_sprite (Dxyn)
; Draw n-row sprite at screen position (Vx, Vy)
; Opcode format: Dxyn where:
;   x = register index (0-F)
;   y = register index (0-F)
;   n = number of rows (1-15)
;
; Sprite data at I register, one byte per row (8 pixels wide)
; ============================================================================

opcode_draw_sprite:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    ; Extract x, y, n from opcode in AX
    ; Opcode format: 0xDxyn
    
    ; Extract x (nibble 2): (AX >> 8) & 0x0F
    mov cl, 8
    mov bx, ax
    shr bx, cl
    and bx, 0x0F                        ; BX = x register index
    
    ; Get Vx (screen X coordinate)
    mov si, vm_registers
    add si, bx
    mov cl, [si]                        ; CL = Vx
    
    ; Extract y (nibble 1): (AX >> 4) & 0x0F
    mov bx, ax
    shr bx, 4
    and bx, 0x0F                        ; BX = y register index
    
    ; Get Vy (screen Y coordinate)
    mov si, vm_registers
    add si, bx
    mov dl, [si]                        ; DL = Vy
    
    ; Extract n (nibble 0): AX & 0x0F
    and ax, 0x0F                        ; AL = n (sprite height)
    
    ; Loop through n rows of sprite data
.sprite_row_loop:
    ; Read sprite byte from memory at [I + row_offset]
    mov si, [vm_i_register]
    add si, 0x2000                      ; Adjust for segment base
    
    ; Add row offset
    mov bx, ax                          ; BX = row counter
    sub ax, ax                          ; Clear AX for addition
    mov al, [si + bx]                   ; AL = sprite byte for this row
    
    ; Draw 8 pixels (1 byte = 8 pixels) at (CL * 4, DL * 4)
    ; Each CHIP-8 pixel becomes 4x4 VGA pixels
    call draw_sprite_row
    
    ; Next row
    inc dl                              ; Next Y row
    dec al                              ; Decrement row counter
    jnz .sprite_row_loop
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: draw_sprite_row
; Draw a single row of 8 CHIP-8 pixels (1 byte) at scaled position
; Inputs:
;   AL = sprite byte (bit 7 to bit 0 = left to right pixels)
;   CL = CHIP-8 X coordinate (0-63)
;   DL = CHIP-8 Y coordinate (0-31)
; ============================================================================

draw_sprite_row:
    push ax
    push bx
    push cx
    push dx
    push di
    push es
    
    ; Set ES to VGA segment
    mov bx, 0xA000
    mov es, bx
    
    ; Convert CHIP-8 coordinates to VGA coordinates
    ; VGA X = CL * 4, VGA Y = DL * 4
    
    mov bl, cl                          ; BL = Vx
    shl bx, 2                           ; BX = Vx * 4
    
    mov cl, dl                          ; CL = Vy
    shl cx, 2                           ; CX = Vy * 4
    
    ; Loop through 8 pixels in the sprite byte
    mov ch, 8                           ; 8 pixels per row
    
.pixel_loop:
    ; Check if pixel is set (test MSB of AL)
    test al, 0x80                       ; Test bit 7
    
    ; If set, draw 4x4 block; otherwise skip
    jz .pixel_skip
    
    ; Draw 4x4 block at (BX, CX)
    call draw_4x4_block
    
.pixel_skip:
    shl al, 1                           ; Shift to next pixel
    add bx, 4                           ; Next X position (4 pixels wide)
    dec ch
    jnz .pixel_loop
    
    pop es
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: draw_4x4_block
; Draw a 4x4 white block at VGA position (BX, CX)
; Inputs:
;   BX = X coordinate (VGA pixels)
;   CX = Y coordinate (VGA pixels)
;   ES = VGA segment (0xA000)
; ============================================================================

draw_4x4_block:
    push ax
    push bx
    push cx
    push dx
    push di
    
    mov al, 0xFF                        ; Color: white
    mov dh, 4                           ; 4 rows
    
.row_loop:
    mov di, cx                          ; DI = Y * 320 (base offset)
    mov ax, cx
    mov dl, 40                          ; Multiply by 320 = 256 + 64
    mul dl
    mov di, ax
    
    add di, bx                          ; Add X offset
    
    ; Draw 4 pixels across
    mov dx, 4
.col_loop:
    mov byte [es:di], 0xFF              ; Write white pixel
    inc di
    dec dx
    jnz .col_loop
    
    add cx, 1                           ; Next Y row
    dec dh
    jnz .row_loop
    
    pop di
    pop cx
    pop dx
    pop bx
    pop ax
    ret

; ============================================================================
; SUBROUTINE: render_frame
; Update VGA display with current graphics buffer (for Phase 1: stub)
; ============================================================================

render_frame:
    ; In Phase 1, rendering is done directly in draw_sprite_row
    ; This stub allows the main loop to call a consistent interface
    ret

; ============================================================================
; SUBROUTINE: update_timers
; Decrement delay and sound timers (60 Hz, decrement every frame)
; ============================================================================

update_timers:
    mov al, [vm_delay_timer]
    cmp al, 0
    je .skip_delay
    dec al
    mov [vm_delay_timer], al
    
.skip_delay:
    mov al, [vm_sound_timer]
    cmp al, 0
    je .skip_sound
    dec al
    mov [vm_sound_timer], al
    
.skip_sound:
    ret

; ============================================================================
; SUBROUTINE: handle_keyboard_input
; Check for key presses and update keyboard_state
; Uses BIOS INT 16h (keyboard)
; ============================================================================

handle_keyboard_input:
    push ax
    
    ; Check if key available (non-blocking)
    mov ah, 0x01                        ; INT 16h: Check key available
    int 0x16
    jz .no_key                          ; ZF=1 if no key
    
    ; Read key
    mov ah, 0x00                        ; INT 16h: Read key
    int 0x16
    
    ; For Phase 1: Just consume the key
    ; TODO: Map key to CHIP-8 keypad (0-F)
    
.no_key:
    pop ax
    ret

; ============================================================================
; Program termination (emergency exit, usually never reached)
; ============================================================================

exit_program:
    mov ah, 0x4C                        ; INT 21h: Exit
    xor al, al                          ; Exit code 0
    int 0x21
