; ============================================================================
; NANO-VM: Graphics Renderer (graphics.asm)
;
; Implements terminal-based graphics rendering.
; Converts the 256-byte display buffer to ASCII output using:
; - '#' for set bits (pixels on)
; - ' ' (space) for unset bits (pixels off)
;
; Uses ANSI escape codes for cursor control and clearing.
; ============================================================================

global render_screen

extern display_buffer

; C library functions for I/O
extern printf
extern fflush
extern stdout

section .data
    ; ANSI escape sequence to move cursor to home (top-left)
    ansi_home: db 27, '[', 'H', 0

    ; Format strings for printf
    pixel_on:  db '#', 0
    pixel_off: db ' ', 0
    newline:   db 10, 0          ; ASCII newline

section .text

; ============================================================================
; FUNCTION: render_screen
;
; Renders the 256-byte display buffer to the terminal as ASCII art.
; 
; Display format:
;   - 32 rows (one for each pixel row)
;   - 64 columns (one for each pixel column)
;   - Each row is 8 bytes in the display buffer
;   - Each byte contains 8 pixels (MSB = leftmost pixel)
;
; Algorithm:
;   1. Move cursor home using ANSI escape code
;   2. For each row (0-31):
;      a. For each byte in the row (0-7):
;         i. For each bit in the byte (7 down to 0):
;            - Extract bit
;            - Print '#' if 1, ' ' if 0
;      b. Print newline
;   3. Flush stdout
;
; ============================================================================
render_screen:
    push rbp
    mov rbp, rsp
    sub rsp, 32                 ; Allocate space for local variables
    
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push r8
    push r9

    ; [Local variables - using stack offsets from rbp]
    ; -8: row_index (0-31)
    ; -16: col_index (0-7, for bytes within a row)
    ; -24: bit_index (0-7, for bits within a byte)
    ; -32: byte_value (the actual byte being processed)

    ; Send ANSI home command: ESC[H
    lea rdi, [rel ansi_home]
    mov rsi, rdi
    call print_string

    ; Get display buffer address
    lea r8, [rel display_buffer]

    ; Initialize row index
    xor r9d, r9d                ; r9 = row_index = 0

.row_loop:
    cmp r9d, 32                 ; Check if row_index >= 32
    jge .render_done

    ; Calculate buffer offset for this row: row * 8
    mov ecx, r9d
    shl ecx, 3                  ; ecx = row * 8
    mov r10d, ecx               ; r10 = byte offset for current row

    ; Process each byte in the row (8 bytes per row)
    xor ebx, ebx                ; rbx = byte_index = 0

.byte_loop:
    cmp ebx, 8                  ; Check if byte_index >= 8
    jge .next_row

    ; Load the byte from display buffer
    mov eax, r10d
    add eax, ebx                ; eax = buffer offset
    movzx edx, byte [r8 + rax]  ; edx = byte_value

    ; Process each bit in the byte (from MSB to LSB)
    xor ecx, ecx                ; rcx = bit_index = 0

.bit_loop:
    cmp ecx, 8                  ; Check if bit_index >= 8
    jge .next_byte

    ; Extract bit: (byte_value >> (7 - bit_index)) & 1
    mov eax, edx                ; eax = byte_value
    mov esi, 7
    sub esi, ecx                ; esi = 7 - bit_index
    shr eax, cl                 ; Shift right by bit_index
    and eax, 1                  ; Mask to get just the bit

    ; Print '#' if bit is 1, ' ' if bit is 0
    test eax, eax
    jnz .print_on

.print_off:
    ; Print space
    lea rsi, [rel pixel_off]
    jmp .print_pixel

.print_on:
    ; Print '#'
    lea rsi, [rel pixel_on]

.print_pixel:
    call print_string

    ; Next bit
    inc ecx
    jmp .bit_loop

.next_byte:
    ; Print newline after each byte row
    lea rsi, [rel newline]
    call print_string

    ; Next byte
    inc ebx
    jmp .byte_loop

.next_row:
    ; Next row
    inc r9d
    jmp .row_loop

.render_done:
    ; Flush output
    call flush_output

    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    add rsp, 32
    pop rbp
    ret

; ============================================================================
; HELPER: print_string
;
; Prints a null-terminated string using printf.
; 
; Inputs:
;   RSI = pointer to null-terminated string
;
; ============================================================================
print_string:
    push rdi
    push rsi

    ; printf expects RDI to be the format string
    mov rdi, rsi
    xor eax, eax                ; No variadic arguments
    call printf

    pop rsi
    pop rdi
    ret

; ============================================================================
; HELPER: flush_output
;
; Flushes stdout buffer.
;
; ============================================================================
flush_output:
    ; fflush(stdout)
    ; Get stdout file pointer
    lea rsi, [rel stdout]
    mov rdi, [rsi]              ; rdi = stdout
    call fflush
    ret

; ============================================================================
; END OF GRAPHICS MODULE
; ============================================================================
