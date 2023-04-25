# RIW-16

## Overview
RIW-16 is a fantasy computer that is programmed in an assembly language with
16 instructions.

### Notes
- RIW-16 stands for Reduced Instruction Word-16
- Programmed in custom ASM
- 16-bit registers
- 16-bit instructions
- 16-bit words instead of bytes
- Fixed instruction width
- Mixed Program/Data
- 16 Registers
- 2^16 words of memory
  - Program is loaded in at address 0
    - Program Counter starts at 0
- 2^32 words of addressable storage
  - Custom storage data format to allow for sparse data
- Text based I/O
- Non-moveable cursor

## I/O

### Devices
- System
  - ID: `0x0`
  - Operations:
    - Halt `0x0`
- Console
  - ID: `0x1`
  - Operations:
    - Char-out `0x0`
      - Data: The lower octet is sent to stdout of the host.
    - Char-in `0x1`
      - Data: If there is a byte from stdin on the host available then the
      upper octet is set to 0 and lower octet is set to the next byte of stdin
      otherwise the whole word is set to `0xffff`.
- Storage
  - ID: `0x2`
  - Operations:
    - MSW-Out `0x0`
      - Data: Writes the most significant word of the storage device's internal
      address.
    - LSW-Out `0x1`
      - Data: Writes the least significant word of the storage device's internal
      address.
    - MSW-In `0x2`
      - Data: Reads the most significant word of the storage device's internal
      address.
    - LSW-In `0x3`
      - Data: Reads the least significant word of the storage device's internal
      address.
    - Storage-Out `0x4`
      - Data: Writes to the word at the storage device's current internal
      address.
    - Storage-In `0x5`
      - Data: Reads the word at the storage device's current internal
      address.


## Assembly Language

### Notes
- $ specifies a register
- The lack of a prefix specifies a immediate
- Immediates may be prefixed with either `0b` `0o` or `0x` to specifiy what
  base the number is in
  - `0b` is binary,`0o` is octal, `0x` is hexadecimal
  - If a number is not prefixed then it is assumed to be decimal
- Line comments are started with `;`


### Instructions

- `loct $A, B`
  - `0000 AAAA BBBB BBBB`
  - Loads the immediate value `B` into the lower octet of`$A`, other bits in
  `$A` are not affected
- `uoct $A, B`
  - `0001 AAAA BBBB BBBB`
  - Loads the immediate value `B` into the upper octet of`$A`, other bits in
  `$A` are not affected
- `adn $A, $B, C`
  - `0010 AAAA BBBB CCCC`
  - Adds `C` to `$B` and store the result in `$A`. `C` is treated as a 4-bit
  signed integer
- `load $A, $B, $C`
  - `0011 AAAA BBBB CCCC`
  - Loads the contents of the address that `($B + $C)` points to into `$A`.
  `$C` is treated as signed
- `store $A, $B, $C`
  - `0100 AAAA BBBB CCCC`
  - Stores `$C` into the address that `($A + $B)` points to. `$B` is treated
  as signed
- `add $A, $B, $C`
  - `0101 AAAA BBBB CCCC`
  - Adds `$B` to `$C` and stores the result in `$A`
- `sub $A, $B, $C`
  - `0110 AAAA BBBB CCCC`
  - Subtracts `$C` from `$B` and stores the result in `$A`
- `cmp $A, $B, $C`
  - `0111 AAAA BBBB CCCC`
  - Compare `$B` and `$C` with a subtraction of the form `$B - $C`,
  store/clear flags of the comparison in `$A`, other bits in `$A` are not
  affected
- `branch $A, $B, C`
  - `1000 AAAA BBBB CCCC`
  - If the results of a bitwise AND with the immediate value `C` and `$B` match
  `C`, copy `$A` into `$pc`
- `shift $A, $B, $C`
  - `1001 AAAA BBBB CCCC`
  - Bitshifts `$B` by `$C` (negative for left, positive for right) and stores
  the result in `$A`. Newly shifted in bits are 0
- `and $A, $B, $C`
  - `1010 AAAA BBBB CCCC`
  - Performs a bitwise AND on `$B` and `$C`, and stores the result into `$A`
- `or $A, $B, $C`
  - `1011 AAAA BBBB CCCC`
  - Performs a bitwise OR on `$B` and `$C`, and stores the result into `$A`
- `xor $A, $B, $C`
  - `1100 AAAA BBBB CCCC`
  - Performs a bitwise XOR on `$B` and `$C`, and stores the result into `$A`
- `nor $A, $B, $C`
  - `1101 AAAA BBBB CCCC`
  - Performs a bitwise NOR on `$B` and `$C`, and stores the result into `$A`
- `swap $A, $B, $C`
  - `1110 AAAA BBBB CCCC`
  - Sets the most significant octet of `$A` to the least significant octet of
  `$B` and the least significant octet of `$A` to the most significant octet
  of `$C` 
- `io $A, $B, $C`
  - `1111 AAAA BBBB CCCC`
  - Performs a device-specific I/O operation `$B` using device `$A` and
  and `$C` as the data.

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
`cmp` is given. Other bits in the register are unaffected.
The flags are as follows:
- Half
  - x???
  - Set if the result of the comparison was less than 256; cleared otherwise
- Overflow
  - ?x??
  - Set if both operands were of the comparison were the same sign and the
  result is of the opposite sign; cleared otherwise
- Negative
  - ??x?
  - Set if result of the comparison had the most significant bit set;
  cleared otherwise
- Zero
  - ???x
  - Set if the result of the comparison was 0; cleared otherwise
