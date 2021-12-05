octet   $1,    41h            ; load ascii 'a' into register 1
octet   $2,    1              ; load 1 into register 2
sub     $0,    $0,    $0      ; set register 0 to 0 
sub     $2,    $0,    $2      ; make register 2 point to the top of memory
store   $2,    $0,    $1      ; write the contents of register 1 to char-out
octet   $1,    0ah            ; load ascii newline into register 1
store   $2,    $0,    $1      ; write the contents of register 1 to char-out
halt                          ; stop the program
 
