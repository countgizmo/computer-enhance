## Compute Enhance (The Homework)

### 8086 Simulator

My silly simulator can:
- disassemble a subset of 8086 instructions from binary;
- simulate storing to and reading from (simulated) registers;
- run arithmetic operations (add, sub, cmp);
- IP register and conditional jumps;
- simulate 64K of memory.

```
❯ zig run simulator.zig -- asm/listing_46
; FILE: asm/listing_46
bits 16

mov bx, 61443
mov cx, 3841
sub bx, cx
mov sp, 998
mov bp, 999
cmp bp, sp
add bp, 1027
sub bp, 2026

=== REGISTERS ===
ax: 0 (0x0)
bx: -7934 (0x-1EFE)
cx: 3841 (0xF01)
dx: 0 (0x0)
sp: 998 (0x3E6)
bp: 0 (0x0)
si: 0 (0x0)
di: 0 (0x0)
=================

=== FLAGS ===
zf: 1
sf: 0
=================

```

My CPU can put pixel data into memory.

<img width="1212" alt="image" src="https://github.com/countgizmo/computer-enhance/assets/926908/acca1a21-38ed-4dc8-956f-130a32de5c77">

