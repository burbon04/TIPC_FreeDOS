;
; File:
;                         floppy.asm
; Description:
;                   floppy disk driver primitives
;
;                       Copyright (c) 1995
;                       Pasquale J. Villani
;                       All Rights Reserved
;
; This file is part of DOS-C.
;
; DOS-C is free software; you can redistribute it and/or
; modify it under the terms of the GNU General Public License
; as published by the Free Software Foundation; either version
; 2, or (at your option) any later version.
;
; DOS-C is distributed in the hope that it will be useful, but
; WITHOUT ANY WARRANTY; without even the implied warranty of
; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See
; the GNU General Public License for more details.
;
; You should have received a copy of the GNU General Public
; License along with DOS-C; see the file COPYING.  If not,
; write to the Free Software Foundation, 675 Mass Ave,
; Cambridge, MA 02139, USA.
;
; $Id: floppy.asm 980 2004-06-19 19:41:47Z perditionc $
;

%include "../kernel/segs.inc"
segment HMA_TEXT

        extern  _DGROUP_:wrt HMA_TEXT

;
; BOOL ASMPASCAL fl_reset(WORD drive);
;
; Reset both the diskette and hard disk system.
; returns TRUE if successful.
;

		global	FL_RESET
FL_RESET:
                call    tipc_counter_install    ; TIPC "media-changed" timer
		pop	ax		; return address
		pop	dx		; drive (DL only)
		push	ax		; restore address
		mov	ah,0		; BIOS reset diskette & fixed disk
		int	4Dh

		sbb	ax,ax		; carry set indicates error, AX=-CF={-1,0}
		inc	ax		; ...return TRUE (1) on success,
		ret			; else FALSE (0) on failure

;
; COUNT ASMPASCAL fl_diskchanged(WORD drive);
;
; Read disk change line status.
; returns 1 if disk has changed, 0 if not, 0xFFFF if error.
;

		global	FL_DISKCHANGED
FL_DISKCHANGED:
		pop	ax		; return address
		pop	dx		; drive (DL only, 00h-7Fh)
		push	ax		; restore stack

		push	si		; preserve value
		mov	ah,16h	; read change status type
		xor	si,si		; RBIL: avoid crash on AT&T 6300
		int	4Dh
		pop	si		; restore

		sbb	al,al		; AL=-CF={-1,0} where 0==no change
		jnc   fl_dc		; carry set on error or disk change
		cmp	ah,6		; if AH==6 then disk change, else error
		jne	fl_dc		; if error, return -1
		mov	al, 1		; set change occurred
fl_dc:	cbw		          	; extend AL into AX, AX={1,0,-1}
		ret			; note: AH=0 on no change, AL set above

;
; Format tracks (sector should be 0).
; COUNT ASMPASCAL fl_format(WORD drive, WORD head, WORD track, WORD sector, WORD count, UBYTE FAR *buffer);
; Reads one or more sectors.
; COUNT ASMPASCAL fl_read  (WORD drive, WORD head, WORD track, WORD sector, WORD count, UBYTE FAR *buffer);
; Writes one or more sectors.
; COUNT ASMPASCAL fl_write (WORD drive, WORD head, WORD track, WORD sector, WORD count, UBYTE FAR *buffer);
; COUNT ASMPASCAL fl_verify(WORD drive, WORD head, WORD track, WORD sector, WORD count, UBYTE FAR *buffer);
;
; Returns 0 if successful, error code otherwise.
;

TIPC_COUNTER_INIT equ 1Eh    ; time span for the timer, 1Eh is 3 seconds

; status in return path:
;   0 = M_DONT_KNOW = timer expired, reload BPB
;   1 = M_NOT_CHANGED = treat disk as not changed
; as TIPC does not use PIN 34 (RDY) signal that IBM systems used for "media changed" events
;
; we install the counter in INT 5Ah, to decrement every 100ms.
; 

       global  TIPC_MEDIA_CHECK
TIPC_MEDIA_CHECK:
        pop     ax              ; stored return address
        pop     dx              ; stored drive
        push    ax
        push    bx
        push    ds
        call    tipc_counter_install ; install inline
        mov     ax,[cs:_DGROUP_]
        mov     ds,ax
        and     dl,7fh
        cmp     dl,4
        jae     .unchanged
        xor     dh,dh
        mov     bx,dx
        cmp     byte [tipc_kernel_counters+bx],0
        jne     .unchanged
        mov     byte [tipc_kernel_counters+bx],TIPC_COUNTER_INIT
        xor     ax,ax           ; it's a M_DONT_KNOW
        jmp     short .finish
.unchanged:
        mov     ax,1            ; it's a M_NOT_CHANGED
.finish:
        pop     ds
        pop     bx
        ret

tipc_counter_install:           ; the lazy way - check this every time
        cmp     byte [cs:tipc_counter_installed],0
        jne     .finish         ; if already installed, skip installation and return
        pushf                   ; otherwise, initial run - so hook existing INT 
        cli
        push    ax
        push    bx
        push    es
        xor     ax,ax
        mov     es,ax
        mov     bx,[es:0168h]
        mov     [cs:tipc_old_int5a],bx
        mov     bx,[es:016Ah]
        mov     [cs:tipc_old_int5a+2],bx
        mov     word [es:0168h],tipc_counter_timer
        mov     ax,cs
        mov     word [es:016Ah],ax
        mov     byte [cs:tipc_counter_installed],1
        pop     es
        pop     bx
        pop     ax
        popf
.finish:
        ret

tipc_counter_activity:
        push    ax
        push    bx
        push    dx
        push    ds
        call    tipc_counter_install
        mov     ax,[cs:_DGROUP_]
        mov     ds,ax
        mov     dl,[bp+10h]
        and     dl,7fh
        cmp     dl,4
        jae     .finish
        xor     dh,dh
        mov     bx,dx
        mov     byte [tipc_kernel_counters+bx],TIPC_COUNTER_INIT
.finish:
        pop     ds
        pop     dx
        pop     bx
        pop     ax
        ret

tipc_counter_timer:
        push    ax
        push    bx
        push    ds
        mov     ax,[cs:_DGROUP_]
        mov     ds,ax
        xor     bx,bx
.looper:
        cmp     byte [tipc_kernel_counters+bx],0
        je      .next
        dec     byte [tipc_kernel_counters+bx]
.next:
        inc     bx
        cmp     bx,4
        jb      .looper
        pop     ds
        pop     bx
        pop     ax
        jmp     far [cs:tipc_old_int5a]   ; call the previous owner

tipc_counter_installed: db 0         
tipc_old_int5a:         dw 0,0


        ; TIPC uses DITs to install the parameter block        
        ; ( WORD drive, WORD bytes_per_sector,
        ;   WORD sectors_per_track,
        ;   WORD tracks_per_cylinder,
        ;   WORD cylinders );
        global TIPC_INSTALL_DIT_FROM_BPB
TIPC_INSTALL_DIT_FROM_BPB:
        push    bp
        mov     bp,sp
        push    ax
        push    bx
        push    cx
        push    dx
        push    si
        push    di
        push    ds
        push    es

        mov     dx,[bp+0Ch]     ; drive
        and     dl,03h
        xor     dh,dh
        pushf
        push    bp
        mov     ah,0Ah
        int     4Dh
        pop     bp
        popf

        mov     si,bx           ; ES:SI = source ROM DIT
        mov     ax,[cs:_DGROUP_]
        mov     ds,ax
        mov     ax,dx
        and     ax,0003h
        mov     di,ax
        shl     di,1            ; 2*n
        mov     cx,di
        shl     di,1            ; 4*n
        shl     di,1            ; 8*n
        add     di,cx           ; 10*n
        add     di,ax           ; 11*n
        add     di,TIPC_KERNEL_DITS

        mov     cx,11
.copy_dit:
        mov     al,[es:si]
        mov     [di],al
        inc     si
        inc     di
        loop    .copy_dit
        sub     di,11

        mov     ax,[bp+0Ah]     ; bytes/sector
        mov     [di+4],ax
        mov     ax,[bp+08h]     ; sectors/track
        mov     [di+6],al
        mov     ax,[bp+06h]     ; tracks/cylinder (heads)
        mov     [di+7],al
        mov     ax,[bp+04h]     ; disk size in cylinders
        mov     [di+8],al

        push    ds
        pop     es
        mov     bx,di
        mov     dx,[bp+0Ch]
        and     dl,03h
        xor     dh,dh
        pushf                   ; careful with the flags
        push    bp
        mov     ah,09h
        int     4Dh
        pop     bp
        popf

        pushf
        cli
        push    ds
        push    ax
        xor     ax,ax
        mov     ds,ax
        mov     ax,[0180h]       ; get DIT pointer in ROMDAT 0000:0180
        mov     es,ax
        pop     ax
        pop     ds
        mov     [es:0093h],bx    ; D_REQ + DIT
        mov     ax,ds
        mov     [es:0095h],ax
        popf

        pop     es
        pop     ds
        pop     di
        pop     si
        pop     dx
        pop     cx
        pop     bx
        pop     ax
        pop     bp
        ret     10


		global	FL_FORMAT
FL_FORMAT:
                mov     ah,5            ; format track
                jmp     short fl_common

		global	FL_READ
FL_READ:
                mov     ah,2            ; read sector(s)
                jmp short fl_common
                
		global	FL_VERIFY
FL_VERIFY:
                mov     ah,4            ; verify sector(s)
                jmp short fl_common
                
		global	FL_WRITE
FL_WRITE:
                mov     ah,3            ; write sector(s)

fl_common:                
                push    bp              ; setup stack frame
                mov     bp,sp

                mov     cx,[bp+0Ch]     ; cylinder number

                mov     al,1            ; this should be an error code                     
                cmp     ch,3            ; this code can't write above 3FFh=1023
                ja      fl_error        ; as cylinder # is limited to 10 bits.

                xchg    ch,cl           ; ch=low 8 bits of cyl number
                ror     cl,1            ; bits 8-9 of cylinder number...
                ror     cl,1            ; ...to bits 6-7 in CL
                or      cl,[bp+0Ah]	; or in the sector number (bits 0-5)

                mov     al,1            ; TODO TIPC: single sector for now
                les     bx,[bp+04h]     ; Load 32 bit buffer ptr into ES:BX

                mov     dl,[bp+10h]     ; drive (if or'ed 80h its a hard drive)
                mov     dh,[bp+0Eh]     ; get the head number

                ; Hit the media timer button 
                call    tipc_counter_activity
                int     4Dh             ; process sectors

		sbb	al,al		; carry: al=ff, else al=0
		and	al,ah		; carry: error code, else 0
                or      al,al
                jnz     fl_error
                ; media timer button once again
                call    tipc_counter_activity
fl_error:
                mov     ah,0            ; extend AL into AX without sign extension
                pop     bp
                ret     14

;
; COUNT ASMPASCAL fl_lba_ReadWrite(BYTE drive, WORD mode, void FAR * dap_p);
;
; Returns 0 if successful, error code otherwise.
;

		global  FL_LBA_READWRITE
FL_LBA_READWRITE:
		push    bp              ; setup stack frame
		mov     bp,sp
		
		push    ds
		push    si              ; wasn't in kernel < KE2024Bo6!!

		mov     dl,[bp+10]      ; drive (if or'ed with 80h a hard drive)
		mov     ax,[bp+8]       ; get the command
		lds     si,[bp+4]       ; get far dap pointer
		int     4Dh             ; read from/write to drive
		
		pop     si
		pop     ds

		pop     bp

		mov     al,ah           ; place any error code into al
		mov     ah,0            ; zero out ah           
		ret     8

;
; void ASMPASCAL fl_readkey (void);
;

		global	FL_READKEY
FL_READKEY:     xor	ah, ah
		int	4Ah
		ret

;
; COUNT ASMPASCAL fl_setdisktype (WORD drive, WORD type);
;

		global	FL_SETDISKTYPE
FL_SETDISKTYPE:
		pop	bx		; return address
		pop	ax		; disk format type (al)
		pop	dx		; drive number (dl)
		push	bx		; restore stack
		mov	ah,17h	; floppy set disk type for format
		int	4Dh
ret_AH:
		mov     al,ah           ; place any error code into al
		mov     ah,0            ; zero out ah           
		ret
                        
;
; COUNT ASMPASCAL fl_setmediatype (WORD drive, WORD tracks, WORD sectors);
;
		global	FL_SETMEDIATYPE
FL_SETMEDIATYPE:
		pop	ax		; return address
		pop	bx		; sectors/track
		pop	cx		; number of tracks
		pop	dx		; drive number
		push	ax		; restore stack
		push	di

		dec	cx		; number of cylinders - 1 (last cyl number)
		xchg	ch,cl		; CH=low 8 bits of last cyl number
               
		ror	cl,1		; extract bits 8-9 of cylinder number...
		ror	cl,1		; ...into cl bit 6-7
                
		or	cl,bl		; sectors/track (bits 0-5) or'd with high cyl bits 7-6

		mov	ah,18h	; disk set media type for format
		int	4Dh
		jc	skipint1e

		push	es
                xor     dx,dx
                mov     es,dx
		cli
                pop     word [es:0x1e*4+2] ; set int 0x1e table to es:di
                mov     [es:0x1e*4  ], di
		sti
skipint1e:		
                pop     di
		jmp	short ret_AH

                
segment _FIXED_DATA                  ; global vars need FIXED_DATA, otherwise access
global TIPC_KERNEL_DITS              ; is unreliable and causes weird behaviour
TIPC_KERNEL_DITS:
        times 44 db 0
tipc_kernel_counters:   db 0,0,0,0


