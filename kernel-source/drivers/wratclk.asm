;
; TIPC is no AT. No AT clock, no code ;)
;
        %include "../kernel/segs.inc"
segment HMA_TEXT
global WRITEATCLOCK
WRITEATCLOCK:
        ret     8
