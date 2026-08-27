;
; TIPC has no integrated RTC, add-on cards are handled by their own drivers
; so just return if called
;
        %include "../kernel/segs.inc"
segment HMA_TEXT
global WRITEPCCLOCK
WRITEPCCLOCK:
        pop     ax              ; return address
        add     sp,4            ; discard ULONG ticks argument
        push    ax
        ret
