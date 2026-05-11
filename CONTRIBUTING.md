# Contributing to NANO-VM

Thank you for your interest in contributing to NANO-VM! This document provides guidelines for submitting code, reporting bugs, and proposing enhancements.

---

## Table of Contents

1. [Code of Conduct](#code-of-conduct)
2. [Getting Started](#getting-started)
3. [Development Setup](#development-setup)
4. [Coding Standards](#coding-standards)
5. [Commit Message Guidelines](#commit-message-guidelines)
6. [Pull Request Process](#pull-request-process)
7. [Reporting Bugs](#reporting-bugs)
8. [Proposing Enhancements](#proposing-enhancements)

---

## Code of Conduct

We are committed to providing a welcoming and inclusive environment. All contributors are expected to adhere to our [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

**In short:**
- Be respectful and inclusive
- Give credit where credit is due
- Focus on the issue, not the person
- Help others learn and grow

---

## Getting Started

### Prerequisites

- NASM assembler (v2.14+): [https://www.nasm.us/](https://www.nasm.us/)
- DOSBox or emu8086 for testing
- Git for version control
- A text editor (VS Code, Vim, Emacs, etc.)
- Basic knowledge of x86-16 assembly

### Fork & Clone

```bash
# Fork the repository on GitHub
# Clone your fork locally
git clone https://github.com/YOUR_USERNAME/nano-vm.git
cd nano-vm

# Add upstream remote
git remote add upstream https://github.com/ORIGINAL_OWNER/nano-vm.git
```

### Create a Feature Branch

```bash
# Update main branch
git fetch upstream
git checkout main
git merge upstream/main

# Create feature branch
git checkout -b feature/your-feature-name
```

---

## Development Setup

### Install Dependencies

**Linux/macOS:**
```bash
# Install NASM
sudo apt-get install nasm      # Ubuntu/Debian
brew install nasm               # macOS

# Install DOSBox (optional, for testing)
sudo apt-get install dosbox     # Ubuntu/Debian
brew install dosbox             # macOS
```

**Windows:**
```powershell
# Download NASM from https://www.nasm.us/
# Or use Chocolatey
choco install nasm

# Download DOSBox or use emu8086 IDE
```

### Build & Test

```bash
# Build the emulator
nasm -f bin phase3_main.asm -o nano-vm.com

# Check size (should be < 64KB)
ls -lh nano-vm.com

# Test with DOSBox
dosbox nano-vm.com
```

---

## Coding Standards

### Assembly Language Style

We follow these conventions to maintain code clarity and consistency:

#### 1. Instruction Format

```assembly
; GOOD: Clear, properly indented
mov ax, 0x1000           ; Load 0x1000 into AX
add bx, 4                ; Increment BX by 4
jnz loop_start            ; Jump if not zero

; BAD: Inconsistent spacing
MOV AX,0x1000
   ADD BX,   4
JNZ loop_start
```

#### 2. Register Naming

```assembly
; GOOD: Semantic names with clear purpose
mov si, pc_offset        ; PC (program counter) offset
mov di, vram_addr        ; Video RAM address
mov al, key_scancode     ; Keyboard input

; BAD: Cryptic single letters
mov a, b
mov c, d
```

#### 3. Comments

Every non-obvious instruction should have a comment:

```assembly
; GOOD: Descriptive comments
lodsw                    ; Fetch next opcode (SI += 2, AX = opcode)
xchg ah, al              ; Convert from big-endian to little-endian
shr ah, 4                ; Extract opcode family (0x8 from 0x8XY0)

; BAD: Useless comments
mov ax, bx               ; Move BX to AX
add cx, 1                ; Add 1 to CX
```

#### 4. Code Organization

```assembly
; --- SECTION: DESCRIPTIVE NAME ---
; Clear indication of major code blocks

; --- SUBSECTION: More specific ---
; Logical grouping of related operations

; --- END SECTION: DESCRIPTIVE NAME ---
```

#### 5. Magic Numbers

Always define named constants:

```assembly
; GOOD
VGA_MODE_13H    equ 0x13
VIDEO_SEGMENT   equ 0xA000
CHIP8_RAM_BASE  equ 0x1000

mov al, VGA_MODE_13H
mov es, VIDEO_SEGMENT

; BAD
mov al, 0x13
mov es, 0xA000
```

#### 6. Macro Usage

For repeated patterns, use macros:

```assembly
; Define macro
%macro SAVE_REGS 0
    push ax
    push bx
    push cx
    push dx
%endmacro

%macro RESTORE_REGS 0
    pop dx
    pop cx
    pop bx
    pop ax
%endmacro

; Use macro
SAVE_REGS
; ... operation ...
RESTORE_REGS
```

#### 7. Line Length

Keep lines under 100 characters for readability:

```assembly
; GOOD: Split long operations
mov ax, [CHIP8_V0_REGISTER]
add ax, [CHIP8_V1_REGISTER]
mov [RESULT], ax

; BAD: Long, hard-to-read line
mov ax, [CHIP8_V0_REGISTER]; add ax, [CHIP8_V1_REGISTER]; mov [RESULT], ax
```

---

## Commit Message Guidelines

Write clear, descriptive commit messages:

```
[AREA] Short description (50 characters max)

Detailed explanation of the change (wrap at 72 characters).
Explain what you changed and why, not how.

Fixes #123
Related to #456
```

### Format Example

```
[OPCODE] Implement 0x8XY4 (ADD with carry)

- Extract V[X] and V[Y] from memory
- Perform 8-bit addition
- Set V[F] = 1 if overflow, 0 otherwise
- Update I register for next opcode

Fixes #42
```

### Area Tags

- `[OPCODE]` - CPU opcode implementation
- `[GRAPHICS]` - VGA/display system
- `[SOUND]` - PC speaker audio
- `[INPUT]` - Keyboard handling
- `[MEMORY]` - Memory management
- `[IO]` - Disk I/O operations
- `[DOCS]` - Documentation
- `[BUILD]` - Build system/Makefile

---

## Pull Request Process

### Before Submitting

1. **Test Your Code**
   ```bash
   # Rebuild
   nasm -f bin phase3_main.asm -o nano-vm.com
   
   # Test with a ROM
   dosbox nano-vm.com
   ```

2. **Check for Regressions**
   - Run existing test cases from PHASE3_VALIDATION.md
   - Verify no opcodes were broken

3. **Update Documentation**
   - Update CHANGELOG.md with your changes
   - Update ARCHITECTURE.md if you modified memory layout
   - Add comments to complex code

4. **Run Validation**
   ```bash
   # Check binary size
   wc -c nano-vm.com  # Should be < 64000 bytes
   
   # Verify it still assembles
   nasm -f bin phase3_main.asm -o nano-vm-test.com && echo "Build OK"
   ```

### Submitting the PR

1. Push your branch to your fork
   ```bash
   git push origin feature/your-feature-name
   ```

2. Open a Pull Request on GitHub with:
   - Clear title: `[AREA] Brief description`
   - Detailed description of changes
   - Link to related issues
   - Any testing notes

3. PR Template
   ```markdown
   ## Description
   Brief summary of what this PR does.

   ## Related Issues
   Fixes #123
   Related to #456

   ## Changes Made
   - Change 1
   - Change 2
   - Change 3

   ## Testing
   - Tested opcode X with ROM Y
   - Verified no regressions
   - Binary size: 1234 bytes

   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Comments added for complex logic
   - [ ] CHANGELOG.md updated
   - [ ] Tested with at least one ROM
   - [ ] No new warnings on build
   ```

### Code Review

- We aim to review PRs within 1 week
- Feedback will be constructive and specific
- Multiple iterations may be needed
- Once approved, we'll merge to main

---

## Reporting Bugs

### Before Filing a Bug

1. Check [PHASE3_VALIDATION.md](PHASE3_VALIDATION.md) for known issues
2. Check existing GitHub issues
3. Try the latest version

### Bug Report Template

```markdown
## Description
Clear, concise description of the bug.

## Steps to Reproduce
1. Load ROM: [filename]
2. Run command: [command]
3. Observe issue: [what went wrong]

## Expected Behavior
What should have happened.

## Actual Behavior
What actually happened.

## Environment
- NASM version: `nasm -version`
- Emulator: emu8086 / DOSBox
- OS: Linux / macOS / Windows
- ROM: [filename and link if possible]

## Error Output
```
Paste any error messages or console output
```

## Additional Context
Screenshots, hex dumps, or other relevant information.
```

### Bug Report Example

```markdown
## Description
IBM Logo test renders incorrectly - pixels are offset.

## Steps to Reproduce
1. Build nano-vm.com with phase3_main.asm
2. Run without a ROM loaded
3. IBM logo appears in wrong position

## Expected Behavior
IBM logo should be centered on screen.

## Actual Behavior
Logo is shifted 8 pixels to the left.

## Environment
- NASM version: 2.15
- Emulator: DOSBox 0.74
- OS: Ubuntu 20.04

## Additional Context
Issue likely in graphics.asm line 245 (offset calculation).
Might be related to #78.
```

---

## Proposing Enhancements

### Feature Request Template

```markdown
## Description
Clear description of the desired feature.

## Motivation
Why is this feature needed? What problem does it solve?

## Proposed Solution
How should this feature work?

## Alternative Solutions
Other approaches you considered.

## Additional Context
Links to related issues, code examples, etc.
```

### Enhancement Example

```markdown
## Description
Add support for CHIP-8 Super (S-CHIP) variant.

## Motivation
S-CHIP extends CHIP-8 with higher resolution (128×64).
Several popular games (Pong 2, etc.) require this.

## Proposed Solution
1. Add new mode flag at startup
2. Allocate 128×64 VRAM if in S-CHIP mode
3. Implement S-CHIP-specific opcodes

## Estimated Effort
- Low: < 100 lines
- Medium: 100-500 lines
- High: > 500 lines

## Related Issues
Mentioned in #89, #95
```

---

## Development Tips

### Debugging Common Issues

**Binary won't assemble:**
```bash
nasm -f bin phase3_main.asm -o nano-vm.com 2>&1 | head -20
```

**Wrong opcode behavior:**
1. Check ARCHITECTURE.md for expected behavior
2. Add debug output to the opcode handler
3. Use DOSBox debugger: `debug nano-vm.com`

**Memory corruption:**
1. Check memory layout in ARCHITECTURE.md
2. Add boundary checks
3. Use hexdump to inspect memory regions

### Using the DOSBox Debugger

```
debug nano-vm.com
> r              ; Show registers
> t              ; Trace next instruction
> g 100          ; Go to address 100h
> d 2000 2010    ; Dump memory 2000-2010
> q              ; Quit debugger
```

### Performance Profiling

```bash
# Use emu8086 performance counters
# (emu8086 IDE has built-in cycle counter)

# Or use DOSBox timing
dosbox -cpu=max nano-vm.com
# Monitor CPU usage in DOSBox window
```

---

## Communication

- **Issues & Discussions**: GitHub Issues
- **Quick Questions**: GitHub Discussions (when available)
- **Security Issues**: Do NOT open public issue - email maintainer privately

---

## License

By contributing, you agree that your code will be licensed under the same [MIT License](LICENSE) as the project.

---

## Thank You!

Your contributions make NANO-VM better. We appreciate every bug report, feature request, and pull request!

---

**Last Updated:** 2025-05  
**Version:** 1.0.0
