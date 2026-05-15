
# NANO-VM — CHIP-8 Emulator in 8086 Assembly

A low-level **CHIP-8 virtual machine** built entirely in **8086 Assembly**, targeting **DOS `.COM` execution via emu8086**.
This project demonstrates **VM architecture, memory isolation, and instruction-level control** under real-mode constraints.

---

## Highlights

* Full **fetch–decode–execute pipeline**
* Dedicated **guest memory segment (`0x2000`)**
* Clean separation between **host (DS=CS)** and **VM state**
* VGA **Mode 13h renderer** (scaled 64×32 → 256×128)
* BIOS-based **input handling (non-destructive key polling)**
* Deterministic **LCG-based RNG** (avoids BIOS timing issues)
* Safe **ROM loading with bounds enforcement**
* Spec-aware implementation with documented quirks (CHIP-48 behavior)

---

## Architecture

### Virtual Machine Layout

```text
CHIP8_SEG (0x2000)
├── 0000–004F  Font data (5-byte glyphs)
├── 0200–0FFF  ROM
├── 1000–100F  V registers (V0–VF)
├── 1010–1011  I register
├── 1012–1013  Program Counter
├── 1014       Stack Pointer
├── 1015       Delay Timer
├── 1016       Sound Timer
├── 2000–203F  Call Stack
```

### Execution Model

* Instructions fetched as **big-endian 16-bit opcodes**
* Decoded via **high-nibble dispatch**
* Frequent **DS switching** ensures strict memory control
* No reliance on runtime abstractions or libraries

---

## Technical Decisions

* **Memory Isolation**
  VM state is fully separated from host code to prevent corruption and simplify reasoning.

* **Custom PRNG (LCG)**
  Replaces BIOS-tick randomness to ensure consistent entropy across rapid calls.

* **Non-destructive Input Polling**
  Uses BIOS interrupt (`INT 16h AH=01h`) to detect key state without consuming buffer.

* **Instruction-based Timing**
  Timers decrement periodically based on instruction count (simplified model).

---

## Limitations / Tradeoffs

* No real-time (60Hz) timer synchronization
* No execution throttling (speed depends on host/emulator)
* Sprite rendering is overwrite-based (no XOR collision flag)
* Sound timer not wired to speaker output
* Blocking key-wait (`FX0A`) halts execution loop

These are deliberate simplifications to prioritize architectural clarity.

---

## Controls

```text
1 2 3 4
Q W E R
A S D F
Z X C V
```

---

## Running

1. Place ROM:

   ```
   GAME.CH8
   ```

2. Run in **emu8086**

3. Select execution speed:

   * `S` — Slow
   * `D` — Default
   * `F` — Fast

---

## What This Demonstrates

* Low-level **virtual machine design**
* Instruction decoding and execution pipelines
* Real-mode **memory management (segmentation)**
* Hardware interaction via **BIOS interrupts**
* Debuggable, deterministic system construction in Assembly

---

## Context

This project is part of a broader focus on:

* Systems programming (C++ / low-level)
* Engine/tooling development
* Runtime and execution model design

---

## Future Improvements

* Real-time 60Hz timer implementation
* Cycle-based CPU throttling
* XOR sprite rendering with collision detection (VF)
* Non-blocking input for `FX0A`
* Sound timer integration with PC speaker

---

## License

MIT
