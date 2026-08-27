; Native TIPC printer backend for FreeDOS character devices PRN/LPT1.
; TIPC ROM printer DSR: INT 4Bh, DL=0
;   AH=00h write AL
;   AH=02h status
; reconstructed from TIPC MS-DOS 2.13 IO.SYS

; TODO - needs turther testing!!!

%include "io.inc"

segment _IO_FIXED_DATA

global LptTable
LptTable        db      18h
                dw      _IOExit
                dw      _IOExit
                dw      _IOExit
                dw      _IOCommandError
                dw      _IOSuccess
                dw      _IODone
                dw      _IOExit
                dw      _IOExit
                dw      PrtWrite
                dw      PrtWrite
                dw      PrtOutStat
                dw      _IOExit
                dw      _IOExit
                dw      _IOExit
                dw      _IOExit
                dw      _IOExit
                dw      PrtOutBsy
                dw      _IOExit
                dw      _IOExit
                dw      PrtGenIoctl
                dw      _IOExit
                dw      _IOExit
                dw      _IOExit
                dw      _IOCommandError
                dw      _IOCommandError

segment _IO_TEXT

global uPrtNo
uPrtNo          db      0
uPrtQuantum     dw      50h,50h,50h,50h

; Return ZF=1 and AX=0 when ready. Otherwise AX contains DOS error.
tipc_prt_ready:
                push    dx
                mov     dl,0
                mov     ah,2
                int     4Bh
                pop     dx
                xor     ah,50h
                test    ah,0F0h
                jnz     .not_ready
                xor     ax,ax
                ret
.not_ready:
                mov     ax,0200h          ; AL=E_NOTRDY, NZ
                or      ax,ax
                ret

; AL=character. Return ZF=1 on success, AX DOS error otherwise.
tipc_prt_write:
                push    dx
                push    cx
                mov     dl,0
                mov     cx,0FFFFh
.wait:
                push    ax
                mov     ah,2
                int     4Bh
                xor     ah,50h
                test    ah,0F0h
                pop     ax
                loopnz  .wait
                jnz     .error
                mov     ah,0
                int     4Bh
                xor     ah,40h
                test    ah,0E0h
                jnz     .error
                pop     cx
                pop     dx
                xor     ax,ax
                ret
.error:
                pop     cx
                pop     dx
                mov     ax,0A00h          ; AL=E_WRITE, NZ
                or      ax,ax
                ret

PrtWrite:
                jcxz    .done
.loop:
                mov     al,[es:di]
                call    tipc_prt_write
                jnz     .fail
                inc     di
                loop    .loop
.done:
                jmp     _IOExit
.fail:
                jmp     _IOErrCnt

PrtOutStat:
                call    tipc_prt_ready
                jnz     .busy
                jmp     _IOExit
.busy:
                jmp     _IODone

PrtOutBsy:
                ; Background write uses the same safe polling backend.
                jmp     PrtWrite

PrtGenIoctl:
                les     di,[cs:_ReqPktPtr]
                cmp     byte [es:di+0Dh],5
                jne     _IOCommandError
                mov     al,[es:di+0Eh]
                les     di,[es:di+13h]
                xor     bx,bx
                mov     bl,[cs:uPrtNo]
                shl     bx,1
                mov     cx,[cs:uPrtQuantum+bx]
                cmp     al,65h
                je      .store
                cmp     al,45h
                jne     _IOCommandError
                mov     cx,[es:di]
.store:
                mov     [cs:uPrtQuantum+bx],cx
                mov     [es:di],cx
                jmp     _IOExit
