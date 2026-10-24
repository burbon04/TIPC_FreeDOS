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
		pop	ax		
		pop	dx	
		push	ax		

                ; TIPC ROM disk reset - instead of IBM BIOS reset
                ; invalidates the ROM's position cache as well
		mov	ah,0
		int	4Dh
                jc      .fail

                ; check if floppy drive no., in case we ware called wrong
                and     dl,7fh
                cmp     dl,4
                jae     .ok

                ; state per drive:
                ;   0 = not checked yet
                ;   1 = known present
                ;   2 = checked, but TRACK0 was never reached -> absent/faulty
                ;
                ; TIPC ROM POST needs to reach cyl 0 on the drive, but only
                ; loops over 86 steps. That's not enough for >100 track virtual
                ; Flashfloppy disks, so the drive might be skipped.
                ; So try to re-init once from within the FreeDOS kernel
                ;
                ; Unlike POST DRVTST (86 attempts), allow 223 outward steps
                ; so an extended-geometry access can always return to TRACK 0.
                push    bx
                push    ds
                mov     ax,[cs:_DGROUP_]
                mov     ds,ax
                xor     dh,dh
                mov     bx,dx
                mov     al,[tipc_drive_probe_state+bx]
                pop     ds
                pop     bx
                cmp     al,1
                je      .ok
                cmp     al,2
                je      .fail

                ; TRACK 0 is checked before the first step and after every step.
                pushf
                cli
                push    bx
                push    cx
                push    si
                push    di
                push    bp
                push    es

                mov     bp,dx           ; requested unit
                ; INT 48h/AH=09h -> ES:BX = ROMDAT:SYSCON (offset 0003h).
                mov     ah,09h
                int     48h
                cli                     ; BEEPIO enables interrupts internally
                mov     di,bx           ; keep SYSCON offset

                ; If POST already marked this drive installed in SYSCON,
                ; remember it as present and skip the extended recovery.
                mov     bx,bp
                and     bx,3
                mov     al,[cs:tipc_drive_bit_table+bx]
                test    byte [es:di],al
                jz      .need_extended_probe

                push    ax
                push    bx
                push    ds
                mov     ax,[cs:_DGROUP_]
                mov     ds,ax
                mov     bx,bp
                and     bx,3
                mov     byte [tipc_drive_probe_state+bx],1
                pop     ds
                pop     bx
                pop     ax
                mov     si,1
                jmp     .leave_no_hw_change

.need_extended_probe:
                ; the probes are derived (mostly copied ;) from SYS ROM
                mov     ch,[es:di-3]
                mov     cl,[es:di-1]
                mov     al,ch
                and     al,3fh
                or      al,80h
                mov     [es:di-3],al
                out     00h,al

                mov     bx,bp
                and     bx,3
                mov     al,cl
                and     al,0f0h
                or      al,[cs:tipc_drvsel_table+bx]
                mov     [es:di-1],al
                out     04h,al

                ; SYS ROM moves to cyl 4, then tries to get back to 0
                ; just do the same here
                xor     al,al
                out     21h,al          
                mov     al,4
                out     23h,al          
                mov     al,10h          
                out     20h,al

.seek4_wait:
                mov     bx,10
.seek4_delay:
                dec     bx
                jnz     .seek4_delay
                in      al,20h
                test    al,01h          
                jnz     .seek4_wait
                mov     al,0d0h
                out     20h,al
                mov     bx,10
.pre_status_delay:
                dec     bx
                jnz     .pre_status_delay
                in      al,20h
                test    al,04h
                jnz     .home_ok
                ; more than 200 cyl is already unstable on TIPC, as the
                ; time needed to go back to 0 is aleady considered timed out
                ; anyway, it's cheap here
                mov     si,223   
.home_step:
                mov     al,061h
                out     20h,al
.wait_step:
                mov     bx,10
.step_delay:
                dec     bx
                jnz     .step_delay
                in      al,20h
                test    al,01h
                jnz     .wait_step
                mov     al,0d0h
                out     20h,al
                mov     bx,10
.track0_delay:
                dec     bx
                jnz     .track0_delay
                in      al,20h
                test    al,04h
                jnz     .home_ok
                dec     si
                jnz     .home_step

                ; cyl 0 not reached, give up and remember
                push    ax
                push    bx
                push    ds
                mov     ax,[cs:_DGROUP_]
                mov     ds,ax
                mov     bx,bp
                and     bx,3
                mov     byte [tipc_drive_probe_state+bx],2
                pop     ds
                pop     bx
                pop     ax

                xor     si,si
                jmp     short .restore_latches

.home_ok:
                ; looks good, enable drive
                ; again, same as SYS ROM code does
                push    ax
                push    bx
                push    ds
                mov     ax,[cs:_DGROUP_]
                mov     ds,ax
                mov     bx,bp
                and     bx,3
                mov     byte [tipc_drive_probe_state+bx],1
                mov     al,[cs:tipc_drive_bit_table+bx]
                or      byte [es:di],al
                pop     ds
                pop     bx
                pop     ax

                mov     si,1

.leave_no_hw_change:
                mov     ax,si
                pop     es
                pop     bp
                pop     di
                pop     si
                pop     cx
                pop     bx
                popf
                ret

.restore_latches:
                ; restore latches
                mov     al,cl
                mov     [es:di-1],al
                out     04h,al
                mov     al,ch
                mov     [es:di-3],al
                out     00h,al

                mov     ax,si
                pop     es
                pop     bp
                pop     di
                pop     si
                pop     cx
                pop     bx
                popf
                ret

.ok:
                mov     ax,1
                ret

.fail:
                xor     ax,ax
                ret

tipc_drvsel_table:
                db      03eh,03dh,04bh,087h
tipc_drive_bit_table:
                db      01h,02h,04h,08h



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

                mov     al,[bp+08h]     ; sector count from FreeDOS 
                les     bx,[bp+04h]     ; Load 32 bit buffer ptr into ES:BX

                mov     dl,[bp+10h]     ; drive (if or'ed 80h its a hard drive)
                mov     dh,[bp+0Eh]     ; get the head number

                int     4Dh             ; process sectors

		sbb	al,al		; carry: al=ff, else al=0
		and	al,ah		; carry: error code, else 0
                or      al,al
                jnz     fl_error
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
tipc_kernel_counters:     db 0,0,0,0
tipc_drive_probe_state:   db 0,0,0,0  


