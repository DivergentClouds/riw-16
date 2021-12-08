# Galactic

## Overview
Galactic is a fantasy computer that is interacted with via a simulated teletype.

### Notes
- Custom CPU called RIW-16
	- RIW-16 stands for Reduced Instruction Word-16
- Programmed in custom ASM
- 16-bit registers
- 16-bit instructions
- 16-bit words instead of bytes
- Fixed instruction width
- Mixed Program/Data
- 16 Registers
- 2^16 words of memory
  - Top 6 Words are used for memory-mapped I/O
    - Address -1 is char-out
    - Address -2 is char-in
    - Address -3 is storage-io
      - Read from address for input, write for output
    - Address -4 is the MSW of storage-address
    - Address -5 is the LSW of storage-address
    - Address -6 halts the machine when accessed
  - Program is loaded in at address 0
    - Program Counter starts at 0
- 2^20 words of addressable storage (not implimented)
- Text based I/O
- Non-moveable cursor

## Assembly Language

### Notes
- $ specifies a register
- The lack of a prefix specifies a immediate
- Immediates may be prefixed with either `b` `o` `d` or `h` to specifiy what
  base the number is in
  - `b` is binary,`o` is octal, `d` is decimal, `h` is hexadecimal
  - If a number is not prefixed then it is assumed to be decimal
- Line comments are started with `;
- The emulator currently does not support `loct` and `uoct`


### Instructions

- `loct $A, B`
  - `0000 AAAA BBBB BBBB`
  - Loads the value `B` into the lower octet of`$A`, other bits in `$A` are
  not afected
- `load $A, $B, $C`
  - `0001 AAAA BBBB CCCC`
  - Loads the contents of the address that `($B + $C)` points to into `$A`
- `store $A, $B, $C`
  - `0010 AAAA BBBB CCCC`
  - Stores `$C` into the address that `($A + $B)` points to
- `add $A, $B, $C`
  - `0011 AAAA BBBB CCCC`
  - Adds `$B` to `$C` and stores the result in `$A`
- `sub $A, $B, $C`
  - `0100 AAAA BBBB CCCC`
  - Subtracts `$C` from `$B` and stores the result in `$A`
- `cmpa $A, $B, $C`
  - `0101 AAAA BBBB CCCC`
  - Compare `$B` and `$C` with an add, store/clear the flags of the
  comparison in `$A`, other bits in `$A` are not affected
- `cmps $A, $B, $C`
  - `0110 AAAA BBBB CCCC`
  - Compare `$B` and `$C` with a subtraction, store/clear flags of the
  comparison in `$A`, other bits in `$A` are not affected
- `branch $A, $B, C`
  - `0111 AAAA BBBB CCCC`
  - If the results of a bitwise AND with `#C` and `$B` match `#C`, copy `$A`
  into `$pc`
- `shift $A, $B, $C`
  - `1000 AAAA BBBB CCCC`
  - Bitshifts `$B` by `$C` (negative for left, positive for right) and stores
  the result in `$A`
- `and $A, $B, $C`
  - `1001 AAAA BBBB CCCC`
  - Performs a bitwise AND on `$B` and `$C`, and stores the result into `$A`
- `or $A, $B, $C`
  - `1010 AAAA BBBB CCCC`
  - Performs a bitwise OR on `$B` and `$C`, and stores the result into `$A`
- `xor $A, $B, $C`
  - `1011 AAAA BBBB CCCC`
  - Performs a bitwise XOR on `$B` and `$C`, and stores the result into `$A`
- `nor $A, $B, $C`
  - `1100 AAAA BBBB CCCC`
  - Performs a bitwise NOR on `$B` and `$C`, and stores the result into `$A`
- `mso $A, $B, $C`
  - `1101 AAAA BBBB CCCC`
  - Loads the contents of the most significant octet of the address that
  `($B + $C)` points to into `$A`
- `lso $A, $B, $C`
  - `1110 AAAA BBBB CCCC`
  - Loads the contents of the least significant octet of the address that
  `($B + $C)` points to into `$A`
- `uoct $A, B`
  - `1111 AAAA BBBB BBBB`
  - Loads the value `B` into the upper octet of`$A`, other bits in `$A` are
  not afected

### Registers

- `$0`-`$14`
  - General Purpose Registers
  - Alias: None
  - Purpose: Anything
- `$15`
  - Program Counter
  - Alias: `$pc`
  - Purpose: Contains pointer to the current instruction, jumps if written to

### Flags

Flags are stored in the least significant nibble of the register that
`cmpa`/`cmps` is given. The flags are as follows:
- Carry
  - x???
  - Set if the comparison had a carry out of bit 15; cleared otherwise
- Overflow
  - ?x??
  - Set if both operands were of the comparison were the same sign and the
  result is of the opposite sign
- Negative
  - ??x?
  - Set if result of the comparison was less than 0; cleared otherwise
- Zero
  - ???x
  - Set if the result of the comparison was 0; cleared otherwise
