; Native TIPC serial backend for AUX/COM1..COM4.
; Reconstructed from TI MS-DOS IO.SYS 2.13 serial driver.
; Polling implementation, no IBM INT 14h emulation.
;
; Channel assignment follows the TIPC hardware channel number directly:
;   COM1/AUX -> FC/FE/FF
;   COM2     -> F4/F6/F7
;   COM3     -> EC/EE/EF
;   COM4     -> E4/E6/E7
; Presence is read from SYSCON via native INT 4Fh (SC1MSK..SC4MSK).
; TODO - needs further testing!!

%include "io.inc"

TIPC_SC1MSK      equ 0100h
TIPC_SC2MSK      equ 0200h
TIPC_SC3MSK      equ 0400h
TIPC_SC4MSK      equ 0800h

segment _IO_FIXED_DATA

global ComTable
ComTable        db      0Ah
                dw      _IOExit
                dw      _IOExit
                dw      _IOExit
                dw      _IOCommandError
                dw      ComRead
                dw      ComNdRead
                dw      ComInStat
                dw      ComInpFlush
                dw      ComWrite
                dw      ComWrite
                dw      ComOutStat

; Per-unit one-byte nondestructive-read cache.
ComStatArray    db      0,0,0,0

; Active controller state, corresponding to IO.SYS 210Eh..2130h.
tipc_cmd_port   dw      0
 tipc_data_port  dw      0
 tipc_modem_port dw      0
 tipc_active_unit db     0FFh
 tipc_flags      db      0
 tipc_syscon     dw      0

; Controller initialization stream copied from the original TIPC IO.SYS.
tipc_init_stream:
                db 00h,09h,0C0h,0Fh,00h,01h,00h,03h
                db 0C1h,04h,44h,05h,0EAh,0Bh,56h,0Ch
                db 06h,0Dh,00h,0Eh,03h,02h,55h,02h
 tipc_aux_stream: db 0Fh,00h,01h,00h

segment _IO_TEXT

extern CommonNdRdExit:wrt LGROUP

; DL unit number: 0=COM1/AUX, 1=COM2, 2=COM3, 3=COM4.
; ZF=1 when the channel is installed and initialized.
tipc_select:
                push    ax
                push    bx
                push    cx
                cmp     dl,3
                ja      .failed

                ; Native system configuration service: AX = SYSCON.
                ; Preserve all registers which the ROM service may use.
                push    dx
                push    si
                push    di
                push    bp
                push    ds
                push    es
                int     4Fh
                mov     [cs:tipc_syscon],ax
                pop     es
                pop     ds
                pop     bp
                pop     di
                pop     si
                pop     dx

                xor     bx,bx
                mov     bl,dl
                shl     bx,1
                mov     ax,[cs:tipc_presence_masks+bx]
                test    word [cs:tipc_syscon],ax
                jz      .failed

                cmp     dl,[cs:tipc_active_unit]
                je      .ready
                mov     [cs:tipc_active_unit],dl
                call    tipc_derive_ports
                call    tipc_init
                jnz     .failed
.ready:
                pop     cx
                pop     bx
                pop     ax
                cmp     dl,dl             ; ZF=1
                ret
.failed:
                pop     cx
                pop     bx
                pop     ax
                or      dl,1              ; ZF=0
                ret

tipc_presence_masks:
                dw TIPC_SC1MSK,TIPC_SC2MSK,TIPC_SC3MSK,TIPC_SC4MSK

; Derive the three native I/O ports directly from the COM channel number.
; cmd = FEh - 8*unit, data = cmd+1, modem/status = cmd-2.
tipc_derive_ports:
                push    ax
                push    bx
                xor     ax,ax
                mov     al,dl
                mov     bl,8
                mul     bl                 ; AX = unit * 8
                mov     bx,00FEh
                sub     bx,ax
                mov     [cs:tipc_cmd_port],bx
                inc     bx
                mov     [cs:tipc_data_port],bx
                sub     bx,3
                mov     [cs:tipc_modem_port],bx

                ; Preserve the two already reconstructed handshake defaults.
                ; COM3/COM4 initially use the conservative COM1 setting.
                xor     bx,bx
                mov     bl,dl
                mov     al,[cs:tipc_default_flags+bx]
                mov     [cs:tipc_flags],al
                pop     bx
                pop     ax
                ret

tipc_default_flags db 02h,10h,02h,02h

; Initialize the TIPC serial controller. ZF=1 success.
tipc_init:
                push    ax
                push    cx
                push    dx
                push    si
                mov     si,tipc_init_stream
                mov     dx,[cs:tipc_cmd_port]
                mov     cx,24
.send_init:
                mov     al,[cs:si]
                inc     si
                out     dx,al
                loop    .send_init
                mov     cx,4
.verify:
                in      al,dx
                xor     al,0AAh
                xor     al,0FFh
                jnz     .error
                loop    .verify
                mov     dx,[cs:tipc_modem_port]
                mov     si,tipc_aux_stream
                mov     cx,4
.send_aux:
                mov     al,[cs:si]
                inc     si
                out     dx,al
                loop    .send_aux
                and     byte [cs:tipc_flags],0FBh
                or      byte [cs:tipc_flags],08h
                xor     ax,ax
                jmp     short .done
.error:
                and     byte [cs:tipc_flags],0F7h
                mov     ax,1
                or      ax,ax
.done:
                pop     si
                pop     dx
                pop     cx
                pop     ax
                ret

; Return original TIPC status in AH. Bit 10h means not ready,
; bit 40h is the base ready state used by IO.SYS.
tipc_status:
                push    dx
                push    bx
                mov     ah,40h
                test    byte [cs:tipc_flags],08h
                jnz     .configured
                or      ah,70h
                jmp     .done
.configured:
                mov     dx,[cs:tipc_cmd_port]
                mov     al,2
                out     dx,al
                in      al,dx
                xor     al,0AAh
                xor     al,0FFh
                jz      .controller_ok
                call    tipc_init
.controller_ok:
                mov     dx,[cs:tipc_modem_port]
                in      al,dx
                test    byte [cs:tipc_flags],01h
                jz      .cts_done
                test    al,10h
                jnz     .cts_done
                or      ah,10h
.cts_done:
                test    al,08h
                jnz     .dsr_done
                test    byte [cs:tipc_flags],02h
                jnz     .keep_ready
                and     ah,0BFh
.keep_ready:
                or      ah,10h
.dsr_done:
                mov     dx,[cs:tipc_cmd_port]
                in      al,dx
                test    byte [cs:tipc_flags],10h
                jz      .tx_test
                test    al,01h
                jz      .flow_done
                inc     dx
                in      al,dx
                and     al,7Fh
                dec     dx
                cmp     al,13h
                jne     .not_xoff
                or      byte [cs:tipc_flags],04h
                jmp     short .flow_done
.not_xoff:
                cmp     al,11h
                jne     .flow_done
                and     byte [cs:tipc_flags],0FBh
.flow_done:
                test    byte [cs:tipc_flags],04h
                jz      .tx_test
                or      ah,10h
.tx_test:
                in      al,dx
                test    al,04h
                jnz     .done
                or      ah,10h
.done:
                pop     bx
                pop     dx
                ret

; AL character, ZF=1 success.
tipc_write_char:
                push    cx
                push    dx
                mov     cx,0168h
.wait:
                call    tipc_status
                xor     ah,40h
                jz      .send
                test    ah,0E0h
                loopz  .wait
                mov     ax,8202h
                or      ax,ax
                jmp     short .done
.send:
                mov     dx,[cs:tipc_data_port]
                out     dx,al
                xor     ax,ax
.done:
                pop     dx
                pop     cx
                ret

; ZF=1 when input available, CF=1 when a byte is waiting.
tipc_input_probe:
                push    dx
                mov     dx,[cs:tipc_cmd_port]
                mov     al,1
                out     dx,al
                in      al,dx
                test    al,70h
                jz      .probe
                mov     ah,0Bh
                or      ah,ah
                clc
                pop     dx
                ret
.probe:
                mov     al,0
                out     dx,al
                in      al,dx
                and     al,1
                jz      .none
                stc
                xor     ah,ah
                pop     dx
                ret
.none:
                clc
                xor     ah,ah
                pop     dx
                ret

; Blocking read. AL=byte, AH=0 success; AH!=0 error.
tipc_read_char:
.wait:
                call    tipc_input_probe
                jnz     .error
                jnc     .wait
                mov     dx,[cs:tipc_data_port]
                in      al,dx
                and     al,7Fh
                xor     ah,ah
                ret
.error:
                mov     ah,2
                ret

GetComStat:
                call    GetUnitNum
                mov     bx,dx
                add     bx,ComStatArray
                ret

ComRead:
                jcxz    .done
                call    GetComStat
                xor     ax,ax
                xchg    [bx],al
                or      al,al
                jnz     .store
.loop:
                call    GetUnitNum
                call    tipc_select
                jnz     .fail
                call    tipc_read_char
                or      ah,ah
                jnz     .fail
.store:
                stosb
                loop    .loop
.done:
                jmp     _IOExit
.fail:
                mov     al,E_READ
                jmp     _IOErrCnt

ComNdRead:
                call    GetComStat
                mov     al,[bx]
                or      al,al
                jnz     .return
                call    GetUnitNum
                call    tipc_select
                jnz     .busy
                call    tipc_input_probe
                jnz     .busy
                jnc     .busy
                call    tipc_read_char
                or      ah,ah
                jnz     .busy
                call    GetComStat
                mov     [bx],al
.return:
                jmp     CommonNdRdExit
.busy:
                jmp     _IODone

ComInStat:
                call    GetComStat
                cmp     byte [bx],0
                jne     .ready
                call    GetUnitNum
                call    tipc_select
                jnz     .busy
                call    tipc_input_probe
                jnz     .busy
                jnc     .busy
.ready:
                jmp     _IOExit
.busy:
                jmp     _IODone

ComInpFlush:
                call    GetComStat
                mov     byte [bx],0
                jmp     _IOExit

ComWrite:
                jcxz    .done
                call    GetUnitNum
                call    tipc_select
                jnz     .fail
.loop:
                mov     al,[es:di]
                inc     di
                call    tipc_write_char
                jnz     .fail
                loop    .loop
.done:
                jmp     _IOExit
.fail:
                mov     al,E_WRITE
                jmp     _IOErrCnt

ComOutStat:
                call    GetUnitNum
                call    tipc_select
                jnz     .busy
                call    tipc_status
                xor     ah,40h
                jnz     .busy
                jmp     _IOExit
.busy:
                jmp     _IODone
