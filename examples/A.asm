byte  $1,    41h        ; Load ASCII 'A' into register 1
byte  $2,    1          ; Load 1 into register 2
sub   $0,    $0,    $0  ; Set register 0 to 0 
sub   $2,    $0,    $2  ; Make register 2 point to the top of memory
store $2,    $0,    $1  ; Write the contents of register 1 to char-out
byte  $1,    0Ah        ; Load ASCII newline into register 1
store $2,    $0,    $1  ; Write the contents of register 1 to char-out
halt                    ; Stop the program

