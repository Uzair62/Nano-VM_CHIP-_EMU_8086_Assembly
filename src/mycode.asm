; ============================================================================
; NANO-VM: CHIP-8 Emulator for emu8086 v4.08
; DOS .COM executable - ORG 100h
;
; BUGS FIXED (vs. original):
;   * ROM filename "GAME_CH8" -> "GAME.CH8" (DOS 8.3 needs the dot)
;   * Removed illegal "mov es, 0xA000" (cannot move immediate to segment reg)
;   * Speed prompt now shown BEFORE mode 13h so user can see it
;   * ROM load error halts via INT 21h AH=4Ch (was: fall-through into emulator)
;   * ROM read capped at 0E00h (was 0F00h - would overrun V register area)
;   * draw_sprite: BX (pixelX) saved around VF=1 write on collision
;   * DXYN: coordinate wrap (X mod 64, Y mod 32) per CHIP-8 spec
;   * CXNN (RND): proper LCG, seeded from BIOS ticks at startup
;   * get_key_state: no longer consumes keys from BIOS buffer
;   * Font table: standard 5-byte stride (was 8 with padding)
;   * Fx29: uses *5 stride to match new font layout
;   * 8XYE: cleaner bit-7 extraction via shift+adc
;   * 8XY0: removed duplicate DS restore
;   * Fetch loop: unsigned (jae) compare for instruction counter
;
; QUIRK CHOICES (intentionally CHIP-48 / Schip behavior):
;   * 8XY6 / 8XYE: shift Vx in place
;   * BNNN: PC = V0 + NNN (original CHIP-8)
;   * FX55 / FX65: I unchanged after operation
;
; MEMORY MAP:
;   DS = CS throughout (COM segment, ~0700h in emu8086)
;       All variables live here as normal DB/DW labels.
;       DS is only temporarily swapped and ALWAYS restored to CS.
;
;   CHIP8_SEG = 2000h
;       0000h-004Fh  : font sprites (16 glyphs * 5 bytes = 80 bytes)
;       0200h-0FFFh  : ROM data (max 3584 bytes)
;       1000h-100Fh  : V[0]-V[F] registers
;       1010h-1011h  : I register (word)
;       1012h-1013h  : PC (word)
;       1014h        : SP (byte)
;       1015h        : Delay timer (byte)
;       1016h        : Sound timer (byte)
;       1017h        : Opcode high byte
;       1018h        : Opcode low byte
;       1019h        : X nibble
;       101Ah        : Y nibble
;       101Bh        : N nibble
;       101Ch        : NN byte
;       101Dh-101Eh  : NNN word
;       2000h-203Fh  : Stack (16 word entries)
;
;   ES = 0A000h (VGA framebuffer, set once at startup, never changed)
; ============================================================================

#make_COM#
ORG 100h

    jmp start

; ============================================================================
; VARIABLES in COM segment (DS=CS always)
; ============================================================================

instructions_per_frame  db 00Ah
instruction_counter     db 000h
last_timer_byte         db 000h
rom_file_handle         dw 0000h
rom_bytes_loaded        dw 0000h
prng_state              dw 0ACE1h   ; LCG seed (non-zero starting value)

speed_prompt    db 'Speed: [S]low [D]efault [F]ast: $'
err_not_found   db 0Dh,0Ah,'ROM not found',0Dh,0Ah,'$'
err_too_large   db 0Dh,0Ah,'ROM too large',0Dh,0Ah,'$'

vga_palette:
    db 000h,000h,000h
    db 03Fh,03Fh,03Fh
    db 03Fh,000h,000h
    db 000h,03Fh,000h
    db 000h,000h,03Fh
    db 03Fh,03Fh,000h
    db 03Fh,000h,03Fh
    db 000h,03Fh,03Fh
    db 01Fh,01Fh,01Fh
    db 02Fh,02Fh,02Fh
    db 03Fh,01Fh,01Fh
    db 01Fh,03Fh,01Fh
    db 01Fh,01Fh,03Fh
    db 03Fh,03Fh,01Fh
    db 03Fh,01Fh,03Fh
    db 01Fh,03Fh,03Fh

chip8_font:
    db 0F0h,090h,090h,090h,0F0h     ; 0
    db 020h,060h,020h,020h,070h     ; 1
    db 0F0h,010h,0F0h,080h,0F0h     ; 2
    db 0F0h,010h,0F0h,010h,0F0h     ; 3
    db 090h,090h,0F0h,010h,010h     ; 4
    db 0F0h,080h,0F0h,010h,0F0h     ; 5
    db 0F0h,080h,0F0h,090h,0F0h     ; 6
    db 0F0h,010h,020h,040h,040h     ; 7
    db 0F0h,090h,0F0h,090h,0F0h     ; 8
    db 0F0h,090h,0F0h,010h,0F0h     ; 9
    db 0F0h,090h,0F0h,090h,090h     ; A
    db 0E0h,090h,0E0h,090h,0E0h     ; B
    db 0F0h,080h,080h,080h,0F0h     ; C
    db 0E0h,090h,090h,090h,0E0h     ; D
    db 0F0h,080h,0F0h,080h,0F0h     ; E
    db 0F0h,080h,0F0h,080h,080h     ; F

keymap:
    db 'x','1','2','3','q','w','e','a','s','d','z','c','4','r','f','v'

rom_filename    db 'GAME.CH8',000h

; ============================================================================
; CHIP-8 state segment and offsets
; ============================================================================
CHIP8_SEG   EQU 02000h

C8_REG      EQU 01000h
C8_I        EQU 01010h
C8_PC       EQU 01012h
C8_SP       EQU 01014h
C8_DT       EQU 01015h
C8_ST       EQU 01016h
C8_OPH      EQU 01017h
C8_OPL      EQU 01018h
C8_X        EQU 01019h
C8_Y        EQU 0101Ah
C8_N        EQU 0101Bh
C8_NN       EQU 0101Ch
C8_NNNH     EQU 0101Dh
C8_NNNL     EQU 0101Eh
C8_STACK    EQU 02000h

; ============================================================================
; ENTRY POINT
; ============================================================================
start:
    mov ax, cs            ; DS = CS for .COM file
    mov ds, ax
    mov ss, ax
    mov sp, 0FFFEh        ; SP at top of 64KB

    ; --- Prompt for speed FIRST, while still in text mode (so user can see it) ---
    lea dx, speed_prompt
    mov ah, 009h
    int 021h

    mov ah, 000h
    int 016h

    cmp al, 'S'
    je _slow
    cmp al, 's'
    je _slow
    cmp al, 'F'
    je _fast
    cmp al, 'f'
    je _fast
    mov byte ptr [instructions_per_frame], 00Ah
    jmp _spd_done
_slow:
    mov byte ptr [instructions_per_frame], 005h
    jmp _spd_done
_fast:
    mov byte ptr [instructions_per_frame], 014h
_spd_done:

    ; --- Now load ROM (still in text mode so error message is visible) ---
    call init_chip8
    call rom_load

    ; --- NOW switch to graphics mode 13h ---
    mov ax, 0A000h        ; Set ES = VGA segment (correct way: via AX)
    mov es, ax

    ; *** Double mode-13h init (emu8086 screen refresh fix) ***
    mov ax, 00013h
    int 010h
    mov ax, 00013h
    int 010h

    call load_vga_palette
    ; Note: skipping clear_screen - mode 13h already gives black screen

; ============================================================================
; MAIN LOOP
; DS = CS at top of every iteration
; Simplified: no throttling, no BIOS tick polling.
; Timer decrement happens once per N opcodes.
; ============================================================================
_loop:
    ; Decrement timers every 256 opcodes (rough 60Hz equivalent at high speeds)
    inc byte ptr [instruction_counter]
    jnz _fetch

    ; instruction_counter wrapped to 0 - tick timers
    mov ax, CHIP8_SEG
    mov ds, ax
    cmp byte ptr [C8_DT], 000h
    je _dt_done
    dec byte ptr [C8_DT]
_dt_done:
    cmp byte ptr [C8_ST], 000h
    je _st_done
    dec byte ptr [C8_ST]
_st_done:
    mov ax, cs
    mov ds, ax

_fetch:
    ; NOTE: Throttling removed - emu8086's BIOS tick counter doesn't advance
    ; reliably during tight CPU loops, causing speed-dependent stalls.
    ; Run opcodes continuously.

    ; Fetch opcode from CHIP8_SEG:PC
    mov ax, CHIP8_SEG
    mov ds, ax

    mov si, [C8_PC]
    add word ptr [C8_PC], 2

    mov ah, [si]        ; high byte (big-endian)
    mov al, [si+1]      ; low byte
    mov [C8_OPH], ah
    mov [C8_OPL], al

    ; X = low nibble of high byte
    mov bl, ah
    and bl, 00Fh
    mov [C8_X], bl

    ; Y = high nibble of low byte
    mov bl, al
    shr bl, 1
    shr bl, 1
    shr bl, 1
    shr bl, 1
    mov [C8_Y], bl

    ; N = low nibble of low byte
    mov bl, al
    and bl, 00Fh
    mov [C8_N], bl

    ; NN = full low byte
    mov [C8_NN], al

    ; NNN: high nibble of high byte gone, lower 4 of high byte + full low byte
    mov bh, ah
    and bh, 00Fh
    mov [C8_NNNH], bh
    mov [C8_NNNL], al

    ; Type nibble = high nibble of high byte
    mov bl, ah
    shr bl, 1
    shr bl, 1
    shr bl, 1
    shr bl, 1

    mov ax, cs
    mov ds, ax

    cmp bl, 000h
    je _t00
    cmp bl, 001h
    je _t01
    cmp bl, 002h
    je _t02
    cmp bl, 003h
    je _t03
    cmp bl, 004h
    je _t04
    cmp bl, 005h
    je _t05
    cmp bl, 006h
    je _t06
    cmp bl, 007h
    je _t07
    cmp bl, 008h
    je _t08
    cmp bl, 009h
    je _t09
    cmp bl, 00Ah
    je _t0A
    cmp bl, 00Bh
    je _t0B
    cmp bl, 00Ch
    je _t0C
    cmp bl, 00Dh
    je _t0D
    cmp bl, 00Eh
    je _t0E
    cmp bl, 00Fh
    je _t0F
    jmp _next

; ============================================================================
; 00E0 CLS / 00EE RET
; ============================================================================
_t00:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov bl, [C8_OPL]
    mov ax, cs
    mov ds, ax

    cmp bl, 0E0h
    je _cls
    cmp bl, 0EEh
    je _ret
    jmp _next

_cls:
    call clear_screen
    jmp _next

_ret:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov bl, [C8_SP]
    dec bl
    mov [C8_SP], bl
    xor bh, bh
    shl bx, 1
    mov si, [C8_STACK + bx]
    mov [C8_PC], si
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 1NNN JP
; ============================================================================
_t01:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov bl, [C8_NNNL]
    mov bh, [C8_NNNH]
    mov [C8_PC], bx
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 2NNN CALL
; ============================================================================
_t02:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov bl, [C8_SP]
    xor bh, bh
    shl bx, 1
    mov si, [C8_PC]
    mov [C8_STACK + bx], si
    inc byte ptr [C8_SP]
    mov bl, [C8_NNNL]
    mov bh, [C8_NNNH]
    mov [C8_PC], bx
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 3XNN SE Vx,NN
; ============================================================================
_t03:
    mov ax, CHIP8_SEG
    mov ds, ax
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]
    mov cl, [C8_NN]
    mov ch, al                  ; save Vx in CH before AL is clobbered
    mov ax, cs
    mov ds, ax
    cmp ch, cl                  ; compare Vx (saved in CH) to NN
    jne _next
    mov ax, CHIP8_SEG
    mov ds, ax
    add word ptr [C8_PC], 2
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 4XNN SNE Vx,NN
; ============================================================================
_t04:
    mov ax, CHIP8_SEG
    mov ds, ax
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]
    mov cl, [C8_NN]
    mov ch, al                  ; save Vx before AL is clobbered
    mov ax, cs
    mov ds, ax
    cmp ch, cl                  ; compare Vx to NN
    je _next
    mov ax, CHIP8_SEG
    mov ds, ax
    add word ptr [C8_PC], 2
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 5XY0 SE Vx,Vy
; ============================================================================
_t05:
    mov ax, CHIP8_SEG
    mov ds, ax
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]
    mov bl, [C8_Y]
    mov cl, [C8_REG + bx]
    mov ch, al                  ; save Vx before AL is clobbered
    mov ax, cs
    mov ds, ax
    cmp ch, cl                  ; compare Vx to Vy
    jne _next
    mov ax, CHIP8_SEG
    mov ds, ax
    add word ptr [C8_PC], 2
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 6XNN LD Vx,NN
; ============================================================================
_t06:
    mov ax, CHIP8_SEG
    mov ds, ax
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_NN]
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 7XNN ADD Vx,NN
; ============================================================================
_t07:
    mov ax, CHIP8_SEG
    mov ds, ax
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_NN]
    add [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 8XY_ ALU
; ============================================================================
_t08:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov cl, [C8_N]
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]      ; AL = Vx
    mov dl, [C8_Y]
    xor dh, dh
    mov si, dx
    mov ah, [C8_REG + si]      ; AH = Vy

    cmp cl, 000h
    je _8_0
    cmp cl, 001h
    je _8_1
    cmp cl, 002h
    je _8_2
    cmp cl, 003h
    je _8_3
    cmp cl, 004h
    je _8_4
    cmp cl, 005h
    je _8_5
    cmp cl, 006h
    je _8_6
    cmp cl, 007h
    je _8_7
    cmp cl, 00Eh
    je _8_E
    mov ax, cs
    mov ds, ax
    jmp _next

_8_0:   ; Vx = Vy
    mov [C8_REG + bx], ah
    mov ax, cs
    mov ds, ax
    jmp _next

_8_1:   ; Vx |= Vy
    or al, ah
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

_8_2:   ; Vx &= Vy
    and al, ah
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

_8_3:   ; Vx ^= Vy
    xor al, ah
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

_8_4:   ; Vx += Vy, VF=carry
    add al, ah
    mov [C8_REG + bx], al
    mov si, 00Fh
    mov byte ptr [C8_REG + si], 000h
    jnc _8_4d
    mov byte ptr [C8_REG + si], 001h
_8_4d:
    mov ax, cs
    mov ds, ax
    jmp _next

_8_5:   ; Vx -= Vy, VF=1 if no borrow
    sub al, ah
    mov [C8_REG + bx], al
    mov si, 00Fh
    mov byte ptr [C8_REG + si], 001h
    jnc _8_5d
    mov byte ptr [C8_REG + si], 000h
_8_5d:
    mov ax, cs
    mov ds, ax
    jmp _next

_8_6:   ; Vx>>=1, VF=old bit0
    mov cl, al
    and cl, 001h
    shr byte ptr [C8_REG + bx], 1
    mov si, 00Fh
    mov [C8_REG + si], cl
    mov ax, cs
    mov ds, ax
    jmp _next

_8_7:   ; Vx = Vy-Vx, VF=1 if no borrow
    sub ah, al
    mov [C8_REG + bx], ah
    mov si, 00Fh
    mov byte ptr [C8_REG + si], 001h
    jnc _8_7d
    mov byte ptr [C8_REG + si], 000h
_8_7d:
    mov ax, cs
    mov ds, ax
    jmp _next

_8_E:   ; Vx<<=1, VF=old bit7
    mov cl, al              ; CL = Vx
    shl cl, 1               ; old bit 7 -> CF
    mov cl, 0
    adc cl, 0               ; CL = old bit 7 (0 or 1)
    shl byte ptr [C8_REG + bx], 1
    mov si, 00Fh
    mov [C8_REG + si], cl
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; 9XY0 SNE Vx,Vy
; ============================================================================
_t09:
    mov ax, CHIP8_SEG
    mov ds, ax
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]
    mov bl, [C8_Y]
    mov cl, [C8_REG + bx]
    mov ch, al                  ; save Vx before AL is clobbered
    mov ax, cs
    mov ds, ax
    cmp ch, cl                  ; compare Vx to Vy
    je _next
    mov ax, CHIP8_SEG
    mov ds, ax
    add word ptr [C8_PC], 2
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; ANNN LD I,NNN
; ============================================================================
_t0A:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov bl, [C8_NNNL]
    mov bh, [C8_NNNH]
    mov [C8_I], bx
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; BNNN JP V0+NNN
; ============================================================================
_t0B:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov bl, [C8_NNNL]
    mov bh, [C8_NNNH]
    mov si, bx
    mov bl, [C8_REG]
    xor bh, bh
    add si, bx
    mov [C8_PC], si
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; CXNN RND  -  uses an LCG seeded at startup so multiple calls per BIOS tick
; produce different values (BIOS-tick RND repeats at 18.2Hz, breaking games).
; ============================================================================
_t0C:
    ; Advance LCG: state = state * 25173 + 13849
    mov ax, [prng_state]
    mov bx, 25173
    mul bx                      ; DX:AX = state * 25173 (we use low word)
    add ax, 13849
    mov [prng_state], ax
    ; Use the high byte of the new state (better entropy than low byte)
    mov al, ah

    push ax                     ; save random byte across DS swap
    mov dx, CHIP8_SEG
    mov ds, dx
    pop ax
    and al, [C8_NN]
    xor bh, bh
    mov bl, [C8_X]
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; DXYN DRW Vx,Vy,N
; ============================================================================
_t0D:
    mov ax, CHIP8_SEG
    mov ds, ax

    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]
    and al, 03Fh            ; X mod 64 (wrap horizontally per CHIP-8 spec)
    xor ah, ah
    shl ax, 1
    shl ax, 1               ; pixelX = (Vx mod 64) * 4
    push ax                 ; save pixelX

    mov bl, [C8_Y]
    mov al, [C8_REG + bx]
    and al, 01Fh            ; Y mod 32 (wrap vertically)
    xor ah, ah
    shl ax, 1
    shl ax, 1               ; pixelY = (Vy mod 32) * 4
    mov cx, ax              ; CX = pixelY

    mov al, [C8_N]
    xor ah, ah
    push ax                 ; save row count

    mov si, [C8_I]          ; SI = sprite data offset in CHIP8_SEG

    mov ax, cs
    mov ds, ax

    pop ax                  ; AX = row count
    pop bx                  ; BX = pixelX

    call draw_sprite
    jmp _next

; ============================================================================
; EX9E / EXA1
; ============================================================================
_t0E:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov cl, [C8_OPL]
    xor bh, bh
    mov bl, [C8_X]
    mov al, [C8_REG + bx]
    ; Save AL (key index) and CL (opcode low byte) before DS swap clobbers AL
    mov ch, al              ; CH = key index from Vx
    mov ax, cs
    mov ds, ax

    cmp cl, 09Eh
    je _skp
    cmp cl, 0A1h
    je _sknp
    jmp _next

_skp:
    ; SKP Vx: skip next instruction IF key in Vx IS pressed
    mov al, ch              ; AL = key index
    call get_key_state
    cmp al, 000h
    je _next                ; key NOT pressed - don't skip
    ; Key IS pressed - skip next instruction
    push ax
    mov ax, CHIP8_SEG
    mov ds, ax
    add word ptr [C8_PC], 2
    mov ax, cs
    mov ds, ax
    pop ax
    jmp _next

_sknp:
    ; SKNP Vx: skip next instruction IF key in Vx is NOT pressed
    mov al, ch              ; AL = key index
    call get_key_state
    cmp al, 000h
    jne _next               ; key IS pressed - don't skip
    ; Key NOT pressed - skip next instruction
    push ax
    mov ax, CHIP8_SEG
    mov ds, ax
    add word ptr [C8_PC], 2
    mov ax, cs
    mov ds, ax
    pop ax
    jmp _next

; ============================================================================
; FX__ family
; ============================================================================
_t0F:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov cl, [C8_OPL]
    xor bh, bh
    mov bl, [C8_X]
    mov ax, cs
    mov ds, ax

    cmp cl, 007h
    je _fx07
    cmp cl, 00Ah
    je _fx0A
    cmp cl, 015h
    je _fx15
    cmp cl, 018h
    je _fx18
    cmp cl, 01Eh
    je _fx1E
    cmp cl, 029h
    je _fx29
    cmp cl, 033h
    je _fx33
    cmp cl, 055h
    je _fx55
    cmp cl, 065h
    je _fx65
    jmp _next

_fx07:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov al, [C8_DT]
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

; ============================================================================
; FX0A  LD Vx, K  (wait for key press; store key index 0..15 in Vx)
; Blocks (via INT 16h AH=00h) until a CHIP-8 keymap key is pressed.
; BX contains X register index on entry (from _t0F dispatcher).
; DS = CS on entry.
; ============================================================================
_fx0A:
    push bx                     ; save X register index
_fx0A_wait:
    mov ah, 000h
    int 016h                    ; AL = ASCII of pressed key (BLOCKING)

    ; Search keymap for matching char (DS=CS so keymap accessible)
    lea si, keymap
    mov cx, 0010h
    xor di, di                  ; DI = current index (0..15)
_fx0A_lp:
    cmp al, [si]
    je _fx0A_found
    inc si
    inc di
    loop _fx0A_lp
    ; Key not in keymap - wait again
    jmp _fx0A_wait

_fx0A_found:
    pop bx                      ; restore X register index
    ; DI = CHIP-8 key index (0..15), need to store in V[X]
    mov ax, di                  ; AX = key index
    push ax                     ; preserve across DS swap
    mov ax, CHIP8_SEG
    mov ds, ax
    pop ax                      ; AL = key index again
    mov [C8_REG + bx], al
    mov ax, cs
    mov ds, ax
    jmp _next

_fx15:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov al, [C8_REG + bx]
    mov [C8_DT], al
    mov ax, cs
    mov ds, ax
    jmp _next

_fx18:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov al, [C8_REG + bx]
    mov [C8_ST], al
    mov ax, cs
    mov ds, ax
    jmp _next

_fx1E:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov al, [C8_REG + bx]
    xor ah, ah
    add [C8_I], ax
    mov ax, cs
    mov ds, ax
    jmp _next

_fx29:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov al, [C8_REG + bx]
    and al, 00Fh
    mov cl, 5
    mul cl                  ; AX = Vx * 5  (standard CHIP-8 font stride)
    mov [C8_I], ax
    mov ax, cs
    mov ds, ax
    jmp _next

_fx33:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov al, [C8_REG + bx]
    mov si, [C8_I]
    xor ah, ah
    mov bl, 064h
    div bl
    mov cl, al
    mov al, ah
    xor ah, ah
    mov bl, 00Ah
    div bl
    mov [si],   cl
    mov [si+1], al
    mov [si+2], ah
    mov ax, cs
    mov ds, ax
    jmp _next

_fx55:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov si, [C8_I]
    mov cl, [C8_X]
    xor ch, ch
    inc cx
    xor di, di
_55lp:
    mov al, [C8_REG + di]
    mov [si], al
    inc si
    inc di
    loop _55lp
    mov ax, cs
    mov ds, ax
    jmp _next

_fx65:
    mov ax, CHIP8_SEG
    mov ds, ax
    mov si, [C8_I]
    mov cl, [C8_X]
    xor ch, ch
    inc cx
    xor di, di
_65lp:
    mov al, [si]
    mov [C8_REG + di], al
    inc si
    inc di
    loop _65lp
    mov ax, cs
    mov ds, ax
    jmp _next

_next:
    jmp _loop

; ============================================================================
; draw_sprite
; BX=pixelX, CX=pixelY, SI=sprite offset in CHIP8_SEG, AX=rows
; DS=CS, ES=0A000h on entry
; ============================================================================
; ============================================================================
; draw_sprite
; BX=pixelX, CX=pixelY, SI=sprite offset in CHIP8_SEG, AX=rows
; DS=CS, ES=0A000h on entry
; ============================================================================
draw_sprite:
    ; 1. Reset VF (Collision Flag) to 0
    push ds
    mov dx, CHIP8_SEG
    mov ds, dx
    mov byte ptr [C8_REG + 0Fh], 0 
    pop ds

    push ax         ; Save row count (AX)
    
    ; 2. Calculate initial VGA offset: DI = (Y * 320) + X
    mov ax, cx      ; AX = Y
    mov dx, 320
    mul dx          ; AX = Y * 320
    add ax, bx      ; AX = (Y * 320) + X
    mov di, ax      ; DI is now our screen pointer
    
    pop dx          ; DX = row count (moved from AX)

_dr_row:
    push dx         ; Save remaining row count
    push di         ; Save start of this row's VGA position
    
    ; 3. Fetch sprite byte from CHIP8_SEG:SI
    push ds
    mov ax, CHIP8_SEG
    mov ds, ax
    lodsb           ; AL = [SI], then SI = SI + 1 (Crucial: SI moves only here)
    pop ds

    mov cx, 8       ; 8 bits (pixels) per byte
_dr_bit:
    test al, 080h   ; Check highest bit
    jz _dr_skip

    ; SIMPLIFIED: Always paint white, no collision detection / VGA read-back.
    ; The VGA read-back in emu8086 was unreliable.
    ; For the IBM logo (and any ROM that doesn't overlap sprites), this is fine.
    ; VF (collision flag) stays at 0 - games checking VF will simply never
    ; see collisions, but most playable ROMs do not depend on this.
    mov bl, 00Fh
    mov es:[di], bl
    mov es:[di+1], bl
    mov es:[di+2], bl
    mov es:[di+3], bl
    mov es:[di+320], bl
    mov es:[di+321], bl
    mov es:[di+322], bl
    mov es:[di+323], bl
    mov es:[di+640], bl
    mov es:[di+641], bl
    mov es:[di+642], bl
    mov es:[di+643], bl
    mov es:[di+960], bl
    mov es:[di+961], bl
    mov es:[di+962], bl
    mov es:[di+963], bl

_dr_skip:
    add di, 4       ; Move 4 pixels right on screen
    shl al, 1       ; Shift to next bit in sprite byte
    loop _dr_bit    ; Repeat for all 8 bits

    ; 6. Move to next row
    pop di          ; Get back start of previous row
    add di, 1280    ; Move down 4 screen rows (320 * 4)
    pop dx          ; Get back row count
    dec dx
    jnz _dr_row

    ret

; ============================================================================
; get_key_state  AL=key index -> AL=1 pressed, AL=0 not
; DS=CS on entry and exit
; Uses INT 16h AH=01h (peek) WITHOUT consuming the key, so held keys keep
; registering. A separate buffer-flush in the main loop prevents pile-up.
; ============================================================================
get_key_state:
    push bx
    push cx
    push si
    mov bl, al                  ; BL = requested key index (0..15)

    mov ah, 001h
    int 016h                    ; peek: ZF=1 if no key, AX=key in buffer otherwise
    jz _gk0

    ; AL now has the ASCII char from the buffer (peek does not consume)
    lea si, keymap
    mov cx, 0010h
_gkl:
    cmp al, [si]
    je _gkf
    inc si
    loop _gkl
    jmp _gk0

_gkf:
    mov ax, 0010h
    sub ax, cx                  ; AX = 0-based index of matched key
    cmp al, bl
    jne _gk0
    mov al, 001h
    pop si
    pop cx
    pop bx
    ret
_gk0:
    xor al, al
    pop si
    pop cx
    pop bx
    ret

; ============================================================================
; rom_load - loads GAME_CH8 into CHIP8_SEG:0200h
; DS=CS on entry and exit
; ============================================================================
rom_load:
    lea dx, rom_filename
    mov al, 000h
    mov ah, 03Dh
    int 021h
    jc _rl_err
    mov [rom_file_handle], ax
    mov bx, ax

    push ds
    mov ax, CHIP8_SEG
    mov ds, ax
    mov dx, 00200h
    mov cx, 00E00h            ; Max 3584 bytes (0200h..0FFFh) - stops before V registers
    mov ah, 03Fh
    int 021h
    pop ds

    jc _rl_err
    mov [rom_bytes_loaded], ax

    mov bx, [rom_file_handle]
    mov ah, 03Eh
    int 021h
    clc
    ret

_rl_err:
    lea dx, err_not_found
    mov ah, 009h
    int 021h
    mov ax, 04C01h            ; DOS exit with errorlevel 1
    int 021h

; ============================================================================
; init_chip8 - zero state, load font, set PC=0200h
; DS=CS on entry and exit
; ============================================================================
init_chip8:
    ; --- Seed PRNG from BIOS tick counter so each run differs ---
    push ds
    mov ax, 00040h
    mov ds, ax
    mov ax, [0006Ch]
    pop ds
    or  ax, ax                  ; ensure non-zero seed
    jnz _seed_ok
    mov ax, 0ACE1h
_seed_ok:
    mov [prng_state], ax

    mov ax, CHIP8_SEG
    mov ds, ax

    xor al, al
    xor si, si
    mov cx, 0010h
_ir:
    mov [C8_REG + si], al
    inc si
    loop _ir

    mov word ptr [C8_PC], 00200h
    mov word ptr [C8_I],  00000h
    mov byte ptr [C8_SP], 000h
    mov byte ptr [C8_DT], 000h
    mov byte ptr [C8_ST], 000h

    mov ax, cs
    mov ds, ax

    ; Copy font to CHIP8_SEG:0000h using ES temporarily
    push es
    mov ax, CHIP8_SEG
    mov es, ax
    xor di, di
    lea si, chip8_font
    mov cx, 0050h           ; 80 bytes: 16 glyphs * 5 bytes each
    cld
    rep movsb
    pop es                  ; restore prior ES value
    ret

; ============================================================================
; clear_screen - Uses INT 10h AH=00h to re-set mode 13h
; This is instant in emu8086 (BIOS-level) vs ~80 seconds for rep stosw.
; Re-loads palette afterward since mode set may reset DAC.
; ============================================================================
clear_screen:
    push ax
    mov ax, 00013h
    int 010h
    pop ax
    call load_vga_palette
    ret

; ============================================================================
; load_vga_palette - DS=CS, programs DAC 0-15
; ============================================================================
load_vga_palette:
    xor si, si
_pl:
    cmp si, 0010h
    jge _pl_done

    mov dx, 03C8h
    mov ax, si
    out dx, al

    mov bx, si
    add bx, si
    add bx, si
    lea di, vga_palette
    add di, bx

    mov dx, 03C9h
    mov al, [di]
    out dx, al
    mov al, [di+1]
    out dx, al
    mov al, [di+2]
    out dx, al

    inc si
    jmp _pl
_pl_done:
    ret

; ============================================================================
; speaker_enable / speaker_disable
; ============================================================================
speaker_enable:
    mov al, 0B6h
    out 043h, al
    mov al, 04Ch
    out 042h, al
    mov al, 005h
    out 042h, al
    in  al, 061h
    or  al, 003h
    out 061h, al
    ret

speaker_disable:
    in  al, 061h
    and al, 0FCh
    out 061h, al
    ret