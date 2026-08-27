;
; FreeDOS rdpcclk had to be replaced with TIPC-specific code
; TIPC has a 100ms resolution clock in ROMDAT, so read and convert
;
        %include "../kernel/segs.inc"

segment HMA_TEXT

global READPCCLOCK
READPCCLOCK:
        push    bx
        push    si
        push    ds

        xor     ax,ax
        mov     ds,ax
        mov     bx,[0180h]            ; ROMDAT segment pointer
        mov     ds,bx

        ; total ticks ~= hours*64800 + minutes*1080 + seconds*18
        xor     ax,ax
        mov     al,[013dh]            ; hours
        mov     bx,64800
        mul     bx                    ; DX:AX = hours * 64800
        mov     si,ax
        mov     cx,dx

        xor     ax,ax
        mov     al,[013ch]            ; minutes
        mov     bx,1080
        mul     bx
        add     si,ax
        adc     cx,dx

        xor     ax,ax
        mov     al,[013bh]            ; seconds
        mov     bx,18
        mul     bx
        add     si,ax
        adc     cx,dx

        ; hundredths are advanced in 10-unit steps. Convert approximately
        ; to 18 Hz using hundredths / 6 (0..16 extra ticks per second).
        xor     ax,ax
        mov     al,[013ah]
        xor     dx,dx
        mov     bx,6
        div     bx
        add     si,ax
        adc     cx,byte 0

        mov     ax,si
        mov     dx,cx

        pop     ds
        pop     si
        pop     bx
        ret
