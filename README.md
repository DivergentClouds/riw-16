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
- 2^24 words of memory
  - Program is loaded in at address 0
    - Program Counter starts at 0
  - Only 2^16 words are addressable at a single time
- Paged memory
  - 256 pages
  - Each Page is 256 Words
- 2^32 words of addressable storage
  - The emulator will use a custom storage data format to allow for sparse data
- Text based I/O
- Words are big-endian

## I/O

### Devices
- System
  - ID: `0x0`
  - Operations:
    - Syscall `0x0`
      - Data: Writes to the internal `syscall-hold` register, then loads the
      `syscall-handler` register into `$pc`
    - Syscall-Hold-Get `0x1`
      - Data: Reads from the internal `syscall-hold` register
    - Syscall-Handler-Set `0x2`
      - Data: Writes to the internal `syscall-handler` register
    - Syscall-Handler-Get `0x3`
      - Data: Reads from the internal `syscall-handler` register
    - Fault `0x4`
      - Data: Writes to the internal `fault-hold` register, then loads the
      `fault-handler` register into `$pc`
    - Fault-Hold-Get `0x5`
      - Data: Reads from the internal `fault-hold` register
    - Fault-Handler-Set `0x6`
      - Data: Writes to the internal `fault-handler` register
    - Fault-Handler-Get `0x7`
      - Data: Reads from the internal `fault-handler` register
    - Halt `0x8`
      - Data: Ignored, Halts the system
- Console
  - ID: `0x1`
  - Operations:
    - Char-out `0x0`
      - Data: The lower octet is sent to stdout of the host.
    - Char-in `0x1`
      - Data: If there is a byte from stdin on the host available, then the
      upper octet is set to 0 and lower octet is set to the next byte of stdin,
      otherwise the whole word is set to `0xFFFF`.
- Storage
  - ID: `0x2`
  - Operations:
    - MSW-Address-Set `0x0`
      - Data: Writes to the most significant word of the storage device's
      internal address.
    - LSW-Address-Set `0x1`
      - Data: Writes to the least significant word of the storage device's
      internal address.
    - MSW-Address-Get `0x2`
      - Data: Reads the most significant word of the storage device's internal
      address.
    - LSW-Address-Get `0x3`
      - Data: Reads the least significant word of the storage device's internal
      address.
    - Storage-Out `0x4`
      - Data: Writes to the word at the storage device's current internal
      address.
    - Storage-In `0x5`
      - Data: Reads the word at the storage device's current internal address.
- MMU
  - ID: `0x3`
  - Operations:
    - MSW-Frame-Set `0x0`
      - Data: Writes the lower octet to the most significant word of the MMU's
      internal `frame` register.
    - LSW-Frame-Set `0x1`
      - Data: Writes to the least significant word of the MMU's internal `frame`
      register.
    - MSW-Frame-Get `0x2`
      - Data: Reads the lower octet of most significant word of the MMU's
      internal `frame` register. The upper octet is set to 0.
    - LSW-Frame-Get `0x3`
      - Data: Reads the least significant word of the MMU's internal `frame`
      register.
    - Map-Set `0x4`
      - Data: Sets the page specified by the data to be mapped to the frame
      specified by the internal `frame` register.
    - Map-Get `0x5`
      - Data: Sets the internal `frame` register to the frame mapped to the
      specified page.
    - Lock-IO `0x6`
      - Data: Redirect all I/O operations except `System/Syscall` on the
      specified page to `System/Fault` with the data as `$pc`.
    - Unlock-IO `0x7`
      - Data: Stop redirecting I/O operations on the specified page.
    - Lock-Read `0x8`
      - Data: Redirect all `load` operations on the specified page to act as
      `System/Fault` with the data as `$pc`
    - Unlock-Read `0x9`
      - Data: Stop redirecting `load` operations on the specified page.
    - Lock-Write `0xA`
      - Data: Redirect all `store` operations on the specified page to act as
      `System/Fault` with the data as `$pc`
    - Unlock-Write `0xB`
      - Data: Stop redirecting `store` operations on the specified page.
    - Lock-Execute `0xC`
      - Data: Redirect all operations from the specified page to act as
      `System/Fault` with the data as `$pc`.
    - Unlock-Execute `0xD`
      - Data: Stop redirecting all operations on the specified page.
    - Promote `0xE`
      - Data: Prevent all locks from affecting the specified page if `$pc` is
      in the specified page. Any attempts to preform any operations to the
      specified page or to set `$pc` to an address in the specified page from
      a non-promoted page (except through `System/Syscall`) results in that
      operation acting as `System/Fault` with the data as `$pc`.
    - Demote `0xF`
      - Data: Allow locks to affect the specified page and allow non-promoted
      pages to access it if a lock does not prevent it.

## Assembly Language

### Notes

- $ specifies a register
- The lack of a `$` prefix specifies a immediate
- Immediates may be prefixed with either `0b`, `0o`, `0d` or `0x` to specify
what base the number is in
  - `0b` is binary,`0o` is octal, `0d` is decimal and `0x` is hexadecimal
  - If a number is not prefixed then it is assumed to be decimal
- Underscores in immediates are ignored
- A series of octet immediates may be represented by a series of characters
surrounded by single or double quotes
- Identifiers are strings of the form `[a-zA-Z_][a-zA-Z0-9_]*`
- Identifiers may be used in place of an immediate
- An identifier may not be defined if it has been previously defined
- Forward references to identifiers are valid
- If an immediate is too large for an instruction, the assembler must emit an
error
  - If the bit width of an immediate is specified
- Some operators may optionally be suffixed with `w`, `o`, `n` or `b` to specify
the bit width of the result
  - `w` is 16-bit, `o` is 8-bit, `n` is 4-bit, `b` is 1-bit
  - If the operator is not suffixed, it is assumed to be 16-bit
  - The affected operators are `+`, `+|`, `-` and `-|`
- Operators are left associative
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
- `addi $A, $B, C`
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
  - Bitshifts `$B` by `$C` (negative for right, positive for left) and stores
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

### Labels and Constants

- `A:`
  - Create a global label equal to the current address
  - `A` is an identifier
- `.A:`
  - Create a local label equal to the current address
  - Forward references to `A` are only allowed starting from the previous global
  label
    - If no global label precedes `A`, forward references are allowed starting
    from the beginning of the file
  - The identifier `A` is only considered defined until the next global label
  - `A` is an identifier
- `A = B`
  - Create a global constant `A` equal to an immediate `B`
  - `A` is an identifier
- `.A = B`
  - Create a local constant `A` equal to an immediate `B`
  - Forward references to `A` are only allowed starting from the previous global
  label
    - If no global label precedes `A`, forward references are allowed starting
    from the beginning of the file
  - The identifier `A` is only considered defined until the next global label
  - `A` is an identifier

### Operators

- `@`
  - Treated as an immediate equal to the current address
- `A[B, C]`
  - Treated as an immediate equal to bits `B` through `C` from `A`
  - Precedence: 1
- `A + B`
  - Treated as an immediate equal to `A` plus `B`, wraps
  - Precedence: 0
- `A +| B`
  - Treated as an immediate equal to `A` plus `B`, staturates
  - Precedence: 0
- `A - B`
  - Treated as an immediate equal to `A` minus `B`, wraps
  - Precedence: 0
- `A -| B`
  - Treated as an immediate equal to `A` minus `B`, saturates
  - Precedence: 0

### Pseudo-Instructions

- `word $A, B`
  - Equivalent to `loct $A, B[0, 7]` followed by `uoct $A, B[8, 15]`
- `lit A, ...`
  - Takes one or more 16-bit immediates and stores them starting at the current
  address
- `lito A, ...`
  - Takes one or more 8-bit immediates and stores them starting at the current
  address
    - Up to two immediates are placed in each word, with the first immediate
    going in the upper octet
  
