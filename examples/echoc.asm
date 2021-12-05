; echo characters pressed

sub     $0,  $0,  $0     ; zero out reg 0
octet   $1,  1           ; set reg 1 to 1
sub     $2,  $0,  $1     ; set reg 2 to char-out (-1)
sub     $1,  $2,  $1     ; set reg 1 to char-in (-2)
octet   $5,  6           ; for branching to reset
octet   $6   7           ; for branching to check


; reset (location = 6)
store   $1,  $0,  $0     ; store 0 in char-in to compare against

; check (location = 7)
load    $3,  $1,  $0     ; load the value at char-in to reg 3
cmpa    $4,  $3   $3     ; check flags of reg 3 + reg 3, store in reg 4
branch  $6,  $4,  0001b  ; branch to check if char-in is 0 (zero flag is set)

store   $2,  $0,  $3     ; write value from reg 3 (char-in) to char-out
branch  $5,  $0,  0000b  ; unconditionally branch to reset (B & 0 == 0)

