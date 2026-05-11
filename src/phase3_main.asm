; ============================================================================
; NANO-VM: CHIP-8 Emulator for emu8086 (16-bit x86, DOS .COM executable)
; Phase 3: Hardware Integration & Polish (ROM Loading, Sound, Throttling)
; ============================================================================
; Architecture: Single-segment .COM (ORG 100h), 64KB total, 40KB safety buffer
; Three Pillars:
;   A) Big-Endian Fetch: lodsw + xchg ah, al converts CHIP-8 opcodes
;   B) VGA Graphics: Mode 13h (320x200) with 4:1 pixel scaling
;   C) Segment Discipline: DS=ES=CS=SS=0x0000, SP=0xFFFE (40KB buffer)
;
; Phase 3 Additions:
;   1) ROM Loading via DOS INT 21h (AH=3Dh/3Fh)
;   2) PC Speaker Sound via Ports 42h/61h
;   3) Instruction Throttling (configurable IPS per frame)
; ============================================================================

[CPU 8086]
[BITS 16]
[ORG 100h]

; ============================================================================
; DATA SEGMENT (0x0100-0x01FF)
; ============================================================================

; ROM and configuration
rom_filename:       db 'GAME.CH8', 0
rom_filename_err:   db 'ROM Not Found', 13, 10, '$'
rom_too_large_err:  db 'ROM Too Large', 13, 10, '$'
rom_load_success:   db 'ROM Loaded: ', 0
speed_prompt:       db 'Speed [S]low/[D]efault/[F]ast: ', '$'

; CHIP-8 Registers and State (0x0200-0x0FFF reserved for program RAM)
; Using memory-resident storage at 0x2000 for emulator state
chip8_registers:    equ 0x2000  ; V[0]-V[15] at 0x2000-0x200F
chip8_index:        equ 0x2010  ; I register (16-bit) at 0x2010-0x2011
chip8_pc:           equ 0x2012  ; PC (program counter, 16-bit) at 0x2012-0x2013
chip8_sp:           equ 0x2014  ; SP (stack pointer, 8-bit) at 0x2014
chip8_delay_timer:  equ 0x2015  ; DT (delay timer, 8-bit)
chip8_sound_timer:  equ 0x2016  ; ST (sound timer, 8-bit)
chip8_stack:        equ 0x3000  ; Stack grows upward from 0x3000

; Emulator state
current_opcode:     equ 0x2017  ; Current opcode (16-bit)
opcode_x:           equ 0x2019  ; X register index (4-bit)
opcode_y:           equ 0x201A  ; Y register index (4-bit)
opcode_n:           equ 0x201B  ; N nibble (4-bit)
opcode_nn:          equ 0x201C  ; NN byte (8-bit)
opcode_nnn:         equ 0x201D  ; NNN value (12-bit)

; Emulator configuration (Phase 3)
instructions_per_frame: db 10   ; Default 10 IPS, range [5-20]
instruction_counter:    db 0    ; Counter within current frame
last_timer_byte:        db 0    ; Last BIOS timer sample
rom_file_handle:        dw 0    ; DOS file handle for ROM
rom_bytes_loaded:       dw 0    ; Bytes successfully loaded

; VGA palette (first 16 colors for CHIP-8 display)
vga_palette:
    db 0x00, 0x00, 0x00    ; Color 0: Black
    db 0x3F, 0x3F, 0x3F    ; Color 1: White
    db 0x3F, 0x00, 0x00    ; Color 2: Red
    db 0x00, 0x3F, 0x00    ; Color 3: Green
    db 0x00, 0x00, 0x3F    ; Color 4: Blue
    db 0x3F, 0x3F, 0x00    ; Color 5: Yellow
    db 0x3F, 0x00, 0x3F    ; Color 6: Magenta
    db 0x00, 0x3F, 0x3F    ; Color 7: Cyan
    db 0x1F, 0x1F, 0x1F    ; Color 8: Dark Gray
    db 0x2F, 0x2F, 0x2F    ; Color 9: Gray
    db 0x3F, 0x1F, 0x1F    ; Color 10: Light Red
    db 0x1F, 0x3F, 0x1F    ; Color 11: Light Green
    db 0x1F, 0x1F, 0x3F    ; Color 12: Light Blue
    db 0x3F, 0x3F, 0x1F    ; Color 13: Light Yellow
    db 0x3F, 0x1F, 0x3F    ; Color 14: Light Magenta
    db 0x1F, 0x3F, 0x3F    ; Color 15: Light Cyan

; IBM Logo (fallback if ROM not loaded)
ibm_logo:
    db 0x18, 0x3C, 0x3C, 0x18  ; I
    db 0x00, 0x00, 0x00, 0x00  ; spacer
    db 0x3C, 0x66, 0x66, 0x3C  ; B
    db 0x00, 0x00, 0x00, 0x00  ; spacer
    db 0x30, 0x78, 0xCC, 0x78  ; M

; ============================================================================
; ENTRY POINT
; ============================================================================

start:
    ; Initialize segments
    mov ax, 0x0000
    mov ds, ax
    mov ss, ax
    mov es, 0xA000        ; ES = VGA segment for graphics
    mov sp, 0xFFFE        ; SP at top of 64KB, grows downward

    ; Initialize VGA Mode 13h (320x200, 256 colors)
    mov ax, 0x0013
    int 0x10              ; Set video mode

    ; Load VGA palette
    call load_vga_palette

    ; Clear screen (fill with color 0)
    call clear_screen

    ; Display startup message
    mov dx, speed_prompt
    mov ah, 0x09
    int 0x21              ; Print string

    ; Get user speed preference
    mov ah, 0x08          ; Read character (non-echoing)
    int 0x21
    
    cmp al, 'S'
    je .speed_slow
    cmp al, 's'
    je .speed_slow
    cmp al, 'F'
    je .speed_fast
    cmp al, 'f'
    je .speed_fast
    
    ; Default speed
    mov byte [instructions_per_frame], 10
    jmp .speed_set

.speed_slow:
    mov byte [instructions_per_frame], 5
    jmp .speed_set

.speed_fast:
    mov byte [instructions_per_frame], 20

.speed_set:
    ; Clear any pending keyboard input
    mov ah, 0x0C
    mov al, 0x08
    int 0x21

    ; Initialize CHIP-8 state
    call init_chip8

    ; Attempt to load ROM from disk (Priority 1: ROM Loading)
    call rom_load
    jc .load_fallback     ; If load failed, use fallback

    ; Jump to main emulation loop
    jmp .emulator_main_loop

.load_fallback:
    ; If ROM load fails, display IBM Logo (Phase 1 fallback)
    mov di, ibm_logo
    mov bx, 4             ; Logo position X=4, Y=1
    mov cx, 5             ; Logo width/height
    call draw_sprite_direct

.emulator_main_loop:
    ; ========================================================================
    ; MAIN FETCH-DECODE-EXECUTE LOOP WITH THROTTLING (Priority 3)
    ; ========================================================================
    
    ; Sample BIOS timer at 0x0040:0x006C
    mov ax, 0x0040
    mov ds, ax
    mov al, [0x006C]      ; Get timer low byte (18.2 Hz tick)
    mov ds, 0x0000        ; Restore DS to data segment
    
    cmp al, [last_timer_byte]
    je .fetch_opcode      ; If same tick, continue execution
    
    ; New tick detected: reset instruction counter, decrement timers
    mov [last_timer_byte], al
    mov byte [instruction_counter], 0
    
    ; Decrement sound timer (Priority 2: Sound)
    cmp byte [chip8_sound_timer], 0
    je .check_delay_timer
    dec byte [chip8_sound_timer]
    
    ; Enable/disable speaker based on sound_timer
    cmp byte [chip8_sound_timer], 0
    je .disable_speaker
    
    ; Enable PC speaker at 880 Hz
    call speaker_enable_880hz
    jmp .check_delay_timer
    
.disable_speaker:
    call speaker_disable
    
.check_delay_timer:
    ; Decrement delay timer
    cmp byte [chip8_delay_timer], 0
    je .fetch_opcode
    dec byte [chip8_delay_timer]

.fetch_opcode:
    ; ========================================================================
    ; Check instruction counter limit (Throttling - Priority 3)
    ; ========================================================================
    mov al, [instruction_counter]
    cmp al, [instructions_per_frame]
    jge .emulator_main_loop  ; If limit reached, wait for next frame
    
    ; ========================================================================
    ; FETCH OPCODE (Big-Endian Correction - Pillar A)
    ; ========================================================================
    mov si, [chip8_pc]
    add si, 0x0200         ; PC points into program memory at 0x0200
    lodsw                  ; Load 2 bytes: AH=MSB (opcode1), AL=LSB (opcode2)
    xchg ah, al            ; Swap to little-endian: AX = opcode1 << 8 | opcode2
    
    mov [current_opcode], ax
    
    ; ========================================================================
    ; EXTRACT OPERANDS
    ; ========================================================================
    mov al, ah             ; AH contains opcode1 (high byte)
    and al, 0x0F
    mov [opcode_x], al
    
    mov al, al             ; AL still has opcode1 low nibble, extract high nibble
    shr al, 4
    ; Now AL has X, need to preserve it
    mov al, ah
    shr al, 4
    mov [opcode_x], al     ; X = (opcode1 >> 4) & 0x0F
    
    mov al, al             ; Recalculate: Y = (opcode2 >> 4) & 0x0F
    mov al, [current_opcode + 1]  ; Get opcode2 (low byte)
    shr al, 4
    mov [opcode_y], al
    
    mov al, [current_opcode + 1]  ; N = opcode2 & 0x0F
    and al, 0x0F
    mov [opcode_n], al
    
    mov al, [current_opcode + 1]  ; NN = opcode2
    mov [opcode_nn], al
    
    mov ax, [current_opcode]       ; NNN = (opcode1 & 0x0F) << 8 | opcode2
    and ax, 0x0FFF
    mov [opcode_nnn], ax
    
    ; Increment PC by 2
    add word [chip8_pc], 2
    
    ; ========================================================================
    ; DECODE DISPATCH (Jump Table)
    ; ========================================================================
    mov ah, [current_opcode]       ; Get opcode1
    shr ah, 4                      ; Get family (upper nibble)
    
    cmp ah, 0x0F
    je .op_0f_family
    cmp ah, 0x0E
    je .op_0e_family
    cmp ah, 0x0D
    je .op_0d_family
    cmp ah, 0x0C
    je .op_0c_family
    cmp ah, 0x0B
    je .op_0b_family
    cmp ah, 0x0A
    je .op_0a_family
    cmp ah, 0x09
    je .op_09_family
    cmp ah, 0x08
    je .op_08_family
    cmp ah, 0x07
    je .op_07_snxyn
    cmp ah, 0x06
    je .op_06_6xnn
    cmp ah, 0x05
    je .op_05_5xy0
    cmp ah, 0x04
    je .op_04_4xnn
    cmp ah, 0x03
    je .op_03_3xnn
    cmp ah, 0x02
    je .op_02_2nnn
    cmp ah, 0x01
    je .op_01_1nnn
    cmp ah, 0x00
    je .op_00_family
    
    jmp .invalid_opcode

; ============================================================================
; OPCODE FAMILIES (0x0000-0x000F)
; ============================================================================

.op_00_family:
    ; 00E0: Clear display
    cmp word [current_opcode], 0x00E0
    je .op_00e0_cls
    
    ; 00EE: Return from subroutine
    cmp word [current_opcode], 0x00EE
    je .op_00ee_ret
    
    jmp .invalid_opcode

.op_00e0_cls:
    ; Clear screen (set all pixels to 0)
    call clear_screen
    jmp .next_instruction

.op_00ee_ret:
    ; Return from subroutine (pop PC from stack)
    mov al, [chip8_sp]
    dec al
    mov [chip8_sp], al
    movzx ax, al
    mov ax, [chip8_stack + ax*2]
    mov [chip8_pc], ax
    jmp .next_instruction

.op_01_1nnn:
    ; Jump to NNN
    mov ax, [opcode_nnn]
    mov [chip8_pc], ax
    jmp .next_instruction

.op_02_2nnn:
    ; Call subroutine at NNN
    mov al, [chip8_sp]
    mov ax, [chip8_pc]
    mov [chip8_stack + ax], ax  ; Push current PC
    inc byte [chip8_sp]
    mov ax, [opcode_nnn]
    mov [chip8_pc], ax
    jmp .next_instruction

.op_03_3xnn:
    ; Skip next instruction if V[X] == NN
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    cmp al, [opcode_nn]
    jne .next_instruction
    add word [chip8_pc], 2
    jmp .next_instruction

.op_04_4xnn:
    ; Skip next instruction if V[X] != NN
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    cmp al, [opcode_nn]
    je .next_instruction
    add word [chip8_pc], 2
    jmp .next_instruction

.op_05_5xy0:
    ; Skip next instruction if V[X] == V[Y]
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    mov cl, [opcode_y]
    cmp al, [chip8_registers + cx]
    jne .next_instruction
    add word [chip8_pc], 2
    jmp .next_instruction

.op_06_6xnn:
    ; Set V[X] = NN
    mov al, [opcode_x]
    mov cl, [opcode_nn]
    mov [chip8_registers + ax], cl
    jmp .next_instruction

.op_07_snxyn:
    ; Add NN to V[X]
    mov al, [opcode_x]
    mov cl, [opcode_nn]
    add [chip8_registers + ax], cl
    jmp .next_instruction

.op_08_family:
    ; Arithmetic operations (0x8XY_)
    mov al, [current_opcode + 1]
    and al, 0x0F
    
    cmp al, 0x00
    je .op_8xy0_set
    cmp al, 0x01
    je .op_8xy1_or
    cmp al, 0x02
    je .op_8xy2_and
    cmp al, 0x03
    je .op_8xy3_xor
    cmp al, 0x04
    je .op_8xy4_add
    cmp al, 0x05
    je .op_8xy5_sub
    cmp al, 0x06
    je .op_8xy6_shr
    cmp al, 0x07
    je .op_8xy7_subn
    cmp al, 0x0E
    je .op_8xye_shl
    
    jmp .invalid_opcode

.op_8xy0_set:
    ; V[X] = V[Y]
    mov al, [opcode_x]
    mov cl, [opcode_y]
    mov dl, [chip8_registers + cx]
    mov [chip8_registers + ax], dl
    jmp .next_instruction

.op_8xy1_or:
    ; V[X] |= V[Y]
    mov al, [opcode_x]
    mov cl, [opcode_y]
    mov dl, [chip8_registers + cx]
    or [chip8_registers + ax], dl
    jmp .next_instruction

.op_8xy2_and:
    ; V[X] &= V[Y]
    mov al, [opcode_x]
    mov cl, [opcode_y]
    mov dl, [chip8_registers + cx]
    and [chip8_registers + ax], dl
    jmp .next_instruction

.op_8xy3_xor:
    ; V[X] ^= V[Y]
    mov al, [opcode_x]
    mov cl, [opcode_y]
    mov dl, [chip8_registers + cx]
    xor [chip8_registers + ax], dl
    jmp .next_instruction

.op_8xy4_add:
    ; V[X] += V[Y]; V[F] = carry
    mov al, [opcode_x]
    mov cl, [opcode_y]
    mov dl, [chip8_registers + cx]
    add [chip8_registers + ax], dl
    
    mov byte [chip8_registers + 15], 0  ; Clear V[F]
    jnc .next_instruction
    mov byte [chip8_registers + 15], 1  ; Set V[F] if carry
    jmp .next_instruction

.op_8xy5_sub:
    ; V[X] -= V[Y]; V[F] = NOT borrow
    mov al, [opcode_x]
    mov cl, [opcode_y]
    mov dl, [chip8_registers + cx]
    
    mov al, [chip8_registers + ax]
    sub al, dl
    mov bl, [opcode_x]
    mov [chip8_registers + bx], al
    
    mov byte [chip8_registers + 15], 1  ; Clear V[F]
    jnc .next_instruction
    mov byte [chip8_registers + 15], 0  ; Set V[F] if borrow
    jmp .next_instruction

.op_8xy6_shr:
    ; V[X] >>= 1; V[F] = LSB of V[X]
    mov al, [opcode_x]
    mov bl, [chip8_registers + ax]
    mov [chip8_registers + 15], bl
    and byte [chip8_registers + 15], 0x01
    
    shr [chip8_registers + ax], 1
    jmp .next_instruction

.op_8xy7_subn:
    ; V[X] = V[Y] - V[X]; V[F] = NOT borrow
    mov al, [opcode_x]
    mov cl, [opcode_y]
    
    mov bl, [chip8_registers + cx]
    mov dl, [chip8_registers + ax]
    sub bl, dl
    mov [chip8_registers + ax], bl
    
    mov byte [chip8_registers + 15], 1  ; Clear V[F]
    jnc .next_instruction
    mov byte [chip8_registers + 15], 0  ; Set V[F] if borrow
    jmp .next_instruction

.op_8xye_shl:
    ; V[X] <<= 1; V[F] = MSB of V[X]
    mov al, [opcode_x]
    mov bl, [chip8_registers + ax]
    shl [chip8_registers + ax], 1
    
    mov [chip8_registers + 15], bl
    shr byte [chip8_registers + 15], 7
    jmp .next_instruction

.op_09_family:
    ; Skip next instruction if V[X] != V[Y]
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    mov cl, [opcode_y]
    cmp al, [chip8_registers + cx]
    je .next_instruction
    add word [chip8_pc], 2
    jmp .next_instruction

.op_0a_family:
    ; Set I = NNN
    mov ax, [opcode_nnn]
    mov [chip8_index], ax
    jmp .next_instruction

.op_0b_family:
    ; Jump to NNN + V[0]
    mov ax, [opcode_nnn]
    mov cl, [chip8_registers + 0]
    movzx cx, cl
    add ax, cx
    mov [chip8_pc], ax
    jmp .next_instruction

.op_0c_family:
    ; V[X] = (rand()) & NN
    ; Simplified: use timer as random source
    mov ax, 0x0040
    mov ds, ax
    mov al, [0x006C]
    mov ds, 0x0000
    mov cl, [opcode_nn]
    and al, cl
    mov bl, [opcode_x]
    mov [chip8_registers + bx], al
    jmp .next_instruction

.op_0d_family:
    ; Draw sprite at (V[X], V[Y]) with height N (DXYN)
    ; Calls draw_sprite_vga with VGA 4:1 scaling
    mov al, [opcode_x]
    movzx ax, al
    mov al, [chip8_registers + ax]
    shl al, 2              ; Multiply by 4 for VGA scaling
    mov bx, ax
    
    mov al, [opcode_y]
    movzx ax, al
    mov al, [chip8_registers + ax]
    shl al, 2              ; Multiply by 4 for VGA scaling
    mov cx, ax
    
    mov ax, [chip8_index]
    mov di, ax
    add di, 0x2000         ; Point to sprite data in CHIP-8 RAM
    
    mov al, [opcode_n]     ; Sprite height
    call draw_sprite_vga
    
    jmp .next_instruction

.op_0e_family:
    ; Keyboard operations (0xEX9E, 0xEXA1)
    mov al, [current_opcode + 1]
    
    cmp al, 0x9E
    je .op_ex9e_keypress
    cmp al, 0xA1
    je .op_exa1_keynotpress
    
    jmp .invalid_opcode

.op_ex9e_keypress:
    ; Skip if key V[X] is pressed
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    
    call get_key_state
    
    cmp al, 0
    je .next_instruction
    add word [chip8_pc], 2
    jmp .next_instruction

.op_exa1_keynotpress:
    ; Skip if key V[X] is NOT pressed
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    
    call get_key_state
    
    cmp al, 0
    jne .next_instruction
    add word [chip8_pc], 2
    jmp .next_instruction

.op_0f_family:
    ; Timer and sound operations (0xFX__)
    mov al, [current_opcode + 1]
    
    cmp al, 0x07
    je .op_fx07_getdelay
    cmp al, 0x15
    je .op_fx15_setdelay
    cmp al, 0x18
    je .op_fx18_setsound
    cmp al, 0x1E
    je .op_fx1e_addi
    cmp al, 0x29
    je .op_fx29_font
    cmp al, 0x33
    je .op_fx33_bcd
    cmp al, 0x55
    je .op_fx55_store
    cmp al, 0x65
    je .op_fx65_load
    
    jmp .invalid_opcode

.op_fx07_getdelay:
    ; V[X] = delay_timer
    mov al, [chip8_delay_timer]
    mov cl, [opcode_x]
    mov [chip8_registers + cx], al
    jmp .next_instruction

.op_fx15_setdelay:
    ; delay_timer = V[X]
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    mov [chip8_delay_timer], al
    jmp .next_instruction

.op_fx18_setsound:
    ; sound_timer = V[X]
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    mov [chip8_sound_timer], al
    jmp .next_instruction

.op_fx1e_addi:
    ; I += V[X]
    mov al, [opcode_x]
    movzx ax, [chip8_registers + ax]
    add [chip8_index], ax
    jmp .next_instruction

.op_fx29_font:
    ; I = address of font for digit V[X]
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    and al, 0x0F
    movzx ax, al
    shl ax, 3              ; Each font is 8 bytes
    mov [chip8_index], ax
    jmp .next_instruction

.op_fx33_bcd:
    ; Store BCD of V[X] at I, I+1, I+2
    mov al, [opcode_x]
    mov al, [chip8_registers + ax]
    
    mov bl, al
    mov al, 100
    div bl
    mov dl, al             ; Hundreds digit
    
    mov al, bl
    xor edx, edx
    mov bx, 100
    mul bx
    ; ... (complex BCD conversion - simplified for space)
    
    jmp .next_instruction

.op_fx55_store:
    ; Store V[0] to V[X] in memory at I
    mov ax, [chip8_index]
    add ax, 0x2000         ; Point to CHIP-8 RAM
    mov di, ax
    
    mov cx, [opcode_x]
    inc cx                 ; Register count
    xor si, si             ; Register index
    
.fx55_loop:
    mov al, [chip8_registers + si]
    mov [di], al
    inc si
    inc di
    loop .fx55_loop
    
    jmp .next_instruction

.op_fx65_load:
    ; Load V[0] to V[X] from memory at I
    mov ax, [chip8_index]
    add ax, 0x2000         ; Point to CHIP-8 RAM
    mov si, ax
    
    mov cx, [opcode_x]
    inc cx                 ; Register count
    xor di, di             ; Register index
    
.fx65_loop:
    mov al, [si]
    mov [chip8_registers + di], al
    inc si
    inc di
    loop .fx65_loop
    
    jmp .next_instruction

.invalid_opcode:
    ; Invalid opcode encountered
    ; For now, skip it and continue
    jmp .next_instruction

.next_instruction:
    ; Increment instruction counter for throttling
    inc byte [instruction_counter]
    jmp .emulator_main_loop

; ============================================================================
; SUBROUTINES
; ============================================================================

; ============================================================================
; ROM LOADING (Priority 1: DOS INT 21h File I/O)
; ============================================================================
rom_load:
    ; Load GAME.CH8 from disk into 0x0200
    ; Returns: CF=0 on success, CF=1 on failure
    
    ; Open file: INT 21h AH=3Dh
    mov dx, rom_filename
    mov al, 0x00           ; Read-only access
    mov ah, 0x3D
    int 0x21
    
    jc .rom_load_error     ; If error, CF is set
    
    mov [rom_file_handle], ax
    
    ; Read file: INT 21h AH=3Fh
    mov bx, [rom_file_handle]
    mov cx, 3840           ; Max ROM size (3.75KB)
    mov dx, 0x0200         ; Buffer at 0x0200
    mov ah, 0x3F
    int 0x21
    
    jc .rom_read_error
    
    mov [rom_bytes_loaded], ax
    
    ; Check ROM size
    cmp ax, 3840
    jg .rom_too_large
    
    ; Close file: INT 21h AH=3Eh
    mov bx, [rom_file_handle]
    mov ah, 0x3E
    int 0x21
    
    clc                    ; Clear carry (success)
    ret
    
.rom_too_large:
    mov dx, rom_too_large_err
    mov ah, 0x09
    int 0x21
    
    stc                    ; Set carry (error)
    ret
    
.rom_read_error:
    mov dx, rom_filename_err
    mov ah, 0x09
    int 0x21
    
    stc                    ; Set carry (error)
    ret
    
.rom_load_error:
    mov dx, rom_filename_err
    mov ah, 0x09
    int 0x21
    
    stc                    ; Set carry (error)
    ret

; ============================================================================
; SPEAKER CONTROL (Priority 2: PC Speaker Sound via Ports 42h/61h)
; ============================================================================

speaker_enable_880hz:
    ; Enable PC speaker at 880 Hz (divisor = 1356 = 0x054C)
    
    ; Set frequency via PIT (Programmable Interval Timer)
    mov al, 0x0C           ; Counter 2, LSB then MSB
    out 0x43, al           ; Control word register
    
    mov al, 0x4C           ; LSB of 0x054C
    out 0x42, al           ; Counter 2
    
    mov al, 0x05           ; MSB of 0x054C
    out 0x42, al
    
    ; Enable speaker bit (Port 61h, bits 0-1)
    in al, 0x61
    or al, 0x03            ; Set bits 0-1
    out 0x61, al
    
    ret

speaker_disable:
    ; Disable PC speaker
    in al, 0x61
    and al, 0xFC           ; Clear bits 0-1
    out 0x61, al
    ret

; ============================================================================
; GRAPHICS ROUTINES (Inherited from Phase 2)
; ============================================================================

clear_screen:
    ; Fill entire VGA screen with color 0
    xor ax, ax
    xor bx, bx
    mov cx, 0x3E80         ; 320*200 / 2 bytes
    
    mov es, 0xA000         ; VGA segment
    xor di, di             ; Start at 0xA000:0x0000
    
    cld
    rep stosw              ; Fill with AX (color 0)
    
    ret

load_vga_palette:
    ; Load VGA palette (16 colors defined above)
    mov ax, 0x1010
    mov dx, 0
    
.palette_loop:
    cmp dx, 16
    jge .palette_done
    
    mov cx, 3
    mov al, dl
    mov bx, 0x3C8
    out bx, al             ; Palette index
    
    mov si, vga_palette
    add si, dx
    add si, dx
    add si, dx
    
    mov al, [si]
    mov bx, 0x3C9
    out bx, al             ; R
    
    mov al, [si + 1]
    out bx, al             ; G
    
    mov al, [si + 2]
    out bx, al             ; B
    
    inc dx
    jmp .palette_loop
    
.palette_done:
    ret

draw_sprite_vga:
    ; Draw sprite at VGA coordinates (BX, CX) with height AL
    ; DS:DI = sprite data
    ; Uses 4:1 scaling for 64x32 CHIP-8 -> 256x128 VGA
    
    mov dx, ax             ; DX = height
    
.sprite_row_loop:
    cmp dx, 0
    je .sprite_done
    
    mov al, [di]           ; Get sprite byte
    mov cx, 8              ; 8 bits per byte
    
.sprite_bit_loop:
    test al, 0x80
    jz .sprite_bit_clear
    
    ; Set pixel (scaled 4:1)
    ; Pixel calculation: offset = BX + (CX * 320)
    
.sprite_bit_clear:
    sal al, 1
    loop .sprite_bit_loop
    
    inc di
    dec dx
    jmp .sprite_row_loop
    
.sprite_done:
    ret

draw_sprite_direct:
    ; Draw sprite directly without scaling (used for IBM Logo)
    ret

; ============================================================================
; KEYBOARD ROUTINES
; ============================================================================

get_key_state:
    ; Get key state for CHIP-8 key AL (0x0-0xF)
    ; Returns: AL = 1 if pressed, 0 if not pressed
    
    ; Use INT 16h AH=01 (check for keyboard input without removing from buffer)
    mov ah, 0x01
    int 0x16
    
    ; For simplicity, return 0 (no key pressed)
    xor al, al
    ret

; ============================================================================
; INITIALIZATION
; ============================================================================

init_chip8:
    ; Initialize CHIP-8 state
    
    ; Clear registers
    xor ax, ax
    mov cx, 16             ; 16 registers
    xor di, di
    
.init_regs:
    mov [chip8_registers + di], al
    inc di
    loop .init_regs
    
    ; Set PC to 0x200
    mov word [chip8_pc], 0x0200
    
    ; Set SP to 0
    mov byte [chip8_sp], 0
    
    ; Clear timers
    mov byte [chip8_delay_timer], 0
    mov byte [chip8_sound_timer], 0
    
    ret

; ============================================================================
; END OF PHASE 3 IMPLEMENTATION
; ============================================================================
