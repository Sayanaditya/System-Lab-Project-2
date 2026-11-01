; =============================================================================
; PROGRAM     : CAESAR.ASM
; TITLE       : 8086 MASM Simulation of the Caesar Cipher (+3 Shift)
; ARCHITECTURE: Intel 8086 (16-Bit Real Mode, MS-DOS / DOSBox / EMU8086)
; ASSEMBLER   : Microsoft Macro Assembler (MASM) / TASM / EMU8086
; =============================================================================
; DESCRIPTION :
;   This program implements the classical Caesar Cipher with a fixed shift key
;   of K = +3. It demonstrates:
;     a) Buffered user string input via DOS Interrupt 21h (Function 0Ah).
;     b) Character-by-character encryption: E(x) = (x + 3) mod 26
;        with full uppercase ('A'-'Z') and lowercase ('a'-'z') wrap-around
;        handling and preservation of non-alphabetic characters.
;     c) Step-by-step live console trace showing each character's original
;        ASCII code (in Hex), shifted ASCII code, and transformed symbol.
;     d) Two-page automatic screen clearing via BIOS INT 10h (Mode 03h)
;        so output is 100% visible on standard 25-line DOS terminals.
;     e) Character-by-character decryption: D(x) = (x - 3) mod 26
;        recovering the original plaintext string.
; =============================================================================

.MODEL SMALL
.STACK 100H

.DATA
    ; -------------------------------------------------------------------------
    ; CONSTANTS & CONFIGURATION
    ; -------------------------------------------------------------------------
    SHIFT_KEY       EQU 3               ; Fixed Caesar shift key (+3)
    MAX_LEN         EQU 64              ; Maximum input string length

    ; -------------------------------------------------------------------------
    ; BUFFERS (DOS Function 0Ah Buffered Keyboard Input Structure)
    ; Byte 0: Maximum characters buffer can hold (including CR)
    ; Byte 1: Actual number of characters read by DOS (excluding CR)
    ; Byte 2+: The actual characters entered by the user
    ; -------------------------------------------------------------------------
    INPUT_BUF       DB  MAX_LEN
    ACTUAL_LEN      DB  0
    PLAINTEXT       DB  MAX_LEN DUP('$')

    ENCRYPTED_STR   DB  MAX_LEN DUP('$') ; Buffer for encrypted ciphertext
    DECRYPTED_STR   DB  MAX_LEN DUP('$') ; Buffer for decrypted plaintext

    ; -------------------------------------------------------------------------
    ; UI BANNER & STEP-BY-STEP VISUALIZATION STRINGS
    ; -------------------------------------------------------------------------
    BANNER_TOP      DB 13, 10, '+==============================================================+$'
    BANNER_TITLE    DB 13, 10, '|      8086 MASM SYSTEM LAB: CAESAR CIPHER SIMULATOR (+3)      |$'
    BANNER_BOT      DB 13, 10, '+==============================================================+$'

    PROMPT_MSG      DB 13, 10, 13, 10, '[INPUT] Enter Plaintext String (e.g., HELLO): $'
    DEFAULT_NOTE    DB 13, 10, '        (Empty input detected -> Using default: "HELLO")$'
    DEFAULT_STR     DB 'HELLO'

    ; Step 1 Visualization Headers (Page 1)
    STEP1_HDR       DB 13, 10, 13, 10, '+--------------------------------------------------------------+'
                    DB 13, 10, '| STEP 1: ENCRYPTION TRACE  [Formula: C = (P - Base + 3) % 26] |'
                    DB 13, 10, '+-------+-----------+-------------+---------------+------------+'
                    DB 13, 10, '| Index | Plain Chr | Plain ASCII | Shifted ASCII | Cipher Chr |'
                    DB 13, 10, '+-------+-----------+-------------+---------------+------------+$'

    ; Interactive Pause Message
    PAUSE_MSG       DB 13, 10, 13, 10, '>>> [Press any key to view Step 2: Decryption Trace...] $'

    ; Step 2 Visualization Headers (Page 2)
    STEP2_HDR       DB 13, 10, '+--------------------------------------------------------------+'
                    DB 13, 10, '| STEP 2: DECRYPTION TRACE  [Formula: P = (C - Base - 3) % 26] |'
                    DB 13, 10, '+-------+-----------+-------------+---------------+------------+'
                    DB 13, 10, '| Index | Ciphr Chr | Ciphr ASCII | Restord ASCII | Plain Chr  |'
                    DB 13, 10, '+-------+-----------+-------------+---------------+------------+$'

    TABLE_SEP       DB 13, 10, '+-------+-----------+-------------+---------------+------------+$'

    ; Row Formatting Templates
    COL_BAR_1       DB 13, 10, '|   $'
    COL_BAR_2       DB '   |     $'
    COL_BAR_3       DB '     |     $'
    COL_BAR_4       DB 'h     |      $'
    COL_BAR_5       DB 'h      |     $'
    COL_BAR_END     DB '      |$'

    ; Final Summary Strings
    SUMMARY_HDR     DB 13, 10, 13, 10, '+==============================================================+'
                    DB 13, 10, '|                    FINAL CIPHER SUMMARY                      |'
                    DB 13, 10, '+==============================================================+$'
    LBL_PLAIN       DB 13, 10, '  a) Original Plaintext  : $'
    LBL_ENCRYPTED   DB 13, 10, '  b) Encrypted (+3 Shift): $'
    LBL_DECRYPTED   DB 13, 10, '  c) Decrypted Plaintext : $'
    FOOTER_LINE     DB 13, 10, '+==============================================================+', 13, 10, '$'

    HEX_DIGITS      DB '0123456789ABCDEF' ; Lookup table for Hex visualization

.CODE
MAIN PROC
    ; -------------------------------------------------------------------------
    ; 1. INITIALIZE DATA SEGMENT & CLEAR SCREEN (PAGE 1)
    ; -------------------------------------------------------------------------
    MOV AX, @DATA
    MOV DS, AX
    MOV ES, AX                          ; Initialize ES for string operations

    CALL CLEAR_SCREEN                   ; Reset video to 80x25 and clear startup text

    ; -------------------------------------------------------------------------
    ; 2. DISPLAY PROGRAM BANNER & ACCEPT USER INPUT (Requirement a)
    ; -------------------------------------------------------------------------
    LEA DX, BANNER_TOP
    CALL PRINT_STR
    LEA DX, BANNER_TITLE
    CALL PRINT_STR
    LEA DX, BANNER_BOT
    CALL PRINT_STR

    LEA DX, PROMPT_MSG
    CALL PRINT_STR

    ; Call DOS INT 21h, Function 0Ah (Buffered Keyboard Input)
    LEA DX, INPUT_BUF
    MOV AH, 0AH
    INT 21H

    ; Check if user pressed Enter without typing any characters
    MOV CL, ACTUAL_LEN
    CMP CL, 0
    JNE TERMINATE_INPUT

    ; Populate default "HELLO" if input is empty so simulation always works
    LEA DX, DEFAULT_NOTE
    CALL PRINT_STR
    MOV ACTUAL_LEN, 5
    LEA SI, DEFAULT_STR
    LEA DI, PLAINTEXT
    MOV CX, 5
    CLD
    REP MOVSB

TERMINATE_INPUT:
    ; Append '$' terminator to PLAINTEXT buffer for DOS Function 09h printing
    XOR BH, BH
    MOV BL, ACTUAL_LEN
    MOV PLAINTEXT[BX], '$'
    MOV ENCRYPTED_STR[BX], '$'
    MOV DECRYPTED_STR[BX], '$'

    ; -------------------------------------------------------------------------
    ; 3. ENCRYPT PLAINTEXT USING CAESAR SHIFT OF +3 (Requirement b)
    ; -------------------------------------------------------------------------
    LEA DX, STEP1_HDR
    CALL PRINT_STR

    XOR CX, CX
    MOV CL, ACTUAL_LEN                  ; CX = Loop counter (number of chars)
    XOR SI, SI                          ; SI = Current character index (0..N-1)

ENCRYPT_LOOP:
    MOV AL, PLAINTEXT[SI]               ; Load plaintext byte into AL
    MOV BL, AL                          ; Save original byte in BL for trace

    ; Check if character is Uppercase ('A' = 41h to 'Z' = 5Ah)
    CMP AL, 'A'
    JB  ENC_STORE                       ; Below 'A' -> Non-alphabetic, skip shift
    CMP AL, 'Z'
    JBE ENC_UPPER                       ; Between 'A' and 'Z' -> Uppercase shift

    ; Check if character is Lowercase ('a' = 61h to 'z' = 7Ah)
    CMP AL, 'a'
    JB  ENC_STORE                       ; Between 'Z' and 'a' -> Non-alphabetic
    CMP AL, 'z'
    JA  ENC_STORE                       ; Above 'z' -> Non-alphabetic

ENC_LOWER:
    ADD AL, SHIFT_KEY                   ; Apply +3 shift: AL = AL + 3
    CMP AL, 'z'                         ; Did it overflow past 'z' (7Ah)?
    JBE ENC_STORE
    SUB AL, 26                          ; Wrap around alphabet: AL = AL - 26
    JMP ENC_STORE

ENC_UPPER:
    ADD AL, SHIFT_KEY                   ; Apply +3 shift: AL = AL + 3
    CMP AL, 'Z'                         ; Did it overflow past 'Z' (5Ah)?
    JBE ENC_STORE
    SUB AL, 26                          ; Wrap around alphabet: AL = AL - 26

ENC_STORE:
    MOV ENCRYPTED_STR[SI], AL           ; Store encrypted byte into ciphertext buffer
    MOV BH, AL                          ; BH = Transformed character for trace

    ; Print live step-by-step visualization row for this character
    CALL PRINT_TRACE_ROW

    INC SI                              ; Advance to next character index
    LOOP ENCRYPT_LOOP

    LEA DX, TABLE_SEP
    CALL PRINT_STR

    ; Pause Page 1: Let user review complete Step 1 Encryption Table
    LEA DX, PAUSE_MSG
    CALL PRINT_STR
    CALL WAIT_KEY

    ; -------------------------------------------------------------------------
    ; 4. CLEAR SCREEN & DISPLAY DECRYPTION TRACE (PAGE 2 - Requirement c)
    ; -------------------------------------------------------------------------
    CALL CLEAR_SCREEN                   ; Fresh clean screen for Page 2

    LEA DX, STEP2_HDR
    CALL PRINT_STR

    XOR CX, CX
    MOV CL, ACTUAL_LEN                  ; Reload string length into CX
    XOR SI, SI                          ; Reset index SI to 0

DECRYPT_LOOP:
    MOV AL, ENCRYPTED_STR[SI]           ; Load encrypted character into AL
    MOV BL, AL                          ; Save input ciphertext char in BL

    ; Check if character is Uppercase ('A' to 'Z')
    CMP AL, 'A'
    JB  DEC_STORE
    CMP AL, 'Z'
    JBE DEC_UPPER

    ; Check if character is Lowercase ('a' to 'z')
    CMP AL, 'a'
    JB  DEC_STORE
    CMP AL, 'z'
    JA  DEC_STORE

DEC_LOWER:
    SUB AL, SHIFT_KEY                   ; Apply -3 reverse shift: AL = AL - 3
    CMP AL, 'a'                         ; Did it underflow below 'a' (61h)?
    JAE DEC_STORE
    ADD AL, 26                          ; Wrap around alphabet: AL = AL + 26
    JMP DEC_STORE

DEC_UPPER:
    SUB AL, SHIFT_KEY                   ; Apply -3 reverse shift: AL = AL - 3
    CMP AL, 'A'                         ; Did it underflow below 'A' (41h)?
    JAE DEC_STORE
    ADD AL, 26                          ; Wrap around alphabet: AL = AL + 26

DEC_STORE:
    MOV DECRYPTED_STR[SI], AL           ; Store recovered plaintext byte
    MOV BH, AL                          ; BH = Restored character for trace

    ; Print live step-by-step visualization row for this character
    CALL PRINT_TRACE_ROW

    INC SI                              ; Advance index
    LOOP DECRYPT_LOOP

    LEA DX, TABLE_SEP
    CALL PRINT_STR

    ; -------------------------------------------------------------------------
    ; 5. DISPLAY FINAL SUMMARY OF RESULTS
    ; -------------------------------------------------------------------------
    LEA DX, SUMMARY_HDR
    CALL PRINT_STR

    LEA DX, LBL_PLAIN
    CALL PRINT_STR
    LEA DX, PLAINTEXT
    CALL PRINT_STR

    LEA DX, LBL_ENCRYPTED
    CALL PRINT_STR
    LEA DX, ENCRYPTED_STR
    CALL PRINT_STR

    LEA DX, LBL_DECRYPTED
    CALL PRINT_STR
    LEA DX, DECRYPTED_STR
    CALL PRINT_STR

    LEA DX, FOOTER_LINE
    CALL PRINT_STR

    ; -------------------------------------------------------------------------
    ; 6. TERMINATE PROGRAM CLEANLY (DOS INT 21h, Function 4Ch)
    ; -------------------------------------------------------------------------
    MOV AH, 4CH
    XOR AL, AL                          ; Return code 0
    INT 21H
MAIN ENDP

; =============================================================================
; SUBROUTINE: CLEAR_SCREEN
; Purpose   : Sets 80x25 16-color text video mode via BIOS INT 10h, which
;             clears all screen characters and resets cursor to row 0, col 0.
; Preserves : All general-purpose registers
; =============================================================================
CLEAR_SCREEN PROC
    PUSH AX
    MOV AX, 0003H                       ; BIOS Video Mode 03h (80x25 color text)
    INT 10H
    POP AX
    RET
CLEAR_SCREEN ENDP

; =============================================================================
; SUBROUTINE: WAIT_KEY
; Purpose   : Pauses execution until the user presses any key (without echo)
; Preserves : AX
; =============================================================================
WAIT_KEY PROC
    PUSH AX
    MOV AH, 07H                         ; Direct console input without echo
    INT 21H
    POP AX
    RET
WAIT_KEY ENDP

; =============================================================================
; SUBROUTINE: PRINT_STR
; Purpose   : Prints a '$'-terminated string pointed to by DS:DX
; Inputs    : DX = Offset of string in Data Segment
; Preserves : AX, BX, CX, SI
; =============================================================================
PRINT_STR PROC
    PUSH AX
    MOV AH, 09H
    INT 21H
    POP AX
    RET
PRINT_STR ENDP

; =============================================================================
; SUBROUTINE: PRINT_CHAR
; Purpose   : Prints a single ASCII character in DL to standard output
; Inputs    : DL = Character to print
; Preserves : AX, BX, CX, DX, SI
; =============================================================================
PRINT_CHAR PROC
    PUSH AX
    MOV AH, 02H
    INT 21H
    POP AX
    RET
PRINT_CHAR ENDP

; =============================================================================
; SUBROUTINE: PRINT_HEX_BYTE
; Purpose   : Prints an 8-bit value in AL as a 2-digit hexadecimal number
; Inputs    : AL = Byte value to display in Hex
; Preserves : AX, BX, CX, DX, SI
; =============================================================================
PRINT_HEX_BYTE PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    MOV AH, AL                          ; Save full byte in AH

    ; Extract upper nibble (bits 7..4)
    SHR AL, 1
    SHR AL, 1
    SHR AL, 1
    SHR AL, 1
    AND AL, 0FH
    LEA BX, HEX_DIGITS
    XLAT                                ; AL = HEX_DIGITS[AL]
    MOV DL, AL
    CALL PRINT_CHAR

    ; Extract lower nibble (bits 3..0)
    MOV AL, AH
    AND AL, 0FH
    LEA BX, HEX_DIGITS
    XLAT                                ; AL = HEX_DIGITS[AL]
    MOV DL, AL
    CALL PRINT_CHAR

    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_HEX_BYTE ENDP

; =============================================================================
; SUBROUTINE: PRINT_TRACE_ROW
; Purpose   : Prints a formatted step-by-step table row showing:
;             | Index | Input Char | Input ASCII (Hex) | Output ASCII | Output Char |
; Inputs    : SI = Current 0-based index
;             BL = Input character (Plaintext in Step 1, Ciphertext in Step 2)
;             BH = Output character (Ciphertext in Step 1, Plaintext in Step 2)
; Preserves : All registers (AX, BX, CX, DX, SI)
; =============================================================================
PRINT_TRACE_ROW PROC
    PUSH AX
    PUSH BX
    PUSH CX
    PUSH DX

    ; Column 1: Index (single digit 0-9 or low digit of index)
    LEA DX, COL_BAR_1
    CALL PRINT_STR
    MOV AX, SI
    XOR DX, DX
    MOV CX, 10
    DIV CX                              ; DL = SI mod 10
    ADD DL, '0'
    CALL PRINT_CHAR

    ; Column 2: Input Character
    LEA DX, COL_BAR_2
    CALL PRINT_STR
    MOV DL, BL
    CALL PRINT_CHAR

    ; Column 3: Input ASCII Hex Value
    LEA DX, COL_BAR_3
    CALL PRINT_STR
    MOV AL, BL
    CALL PRINT_HEX_BYTE

    ; Column 4: Output ASCII Hex Value
    LEA DX, COL_BAR_4
    CALL PRINT_STR
    MOV AL, BH
    CALL PRINT_HEX_BYTE

    ; Column 5: Output Character
    LEA DX, COL_BAR_5
    CALL PRINT_STR
    MOV DL, BH
    CALL PRINT_CHAR

    LEA DX, COL_BAR_END
    CALL PRINT_STR

    POP DX
    POP CX
    POP BX
    POP AX
    RET
PRINT_TRACE_ROW ENDP

END MAIN
