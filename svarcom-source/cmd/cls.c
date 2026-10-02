/* This file is part of the SvarCOM project and is published under the terms
 * of the MIT license.
 *
 * Copyright (C) 2021-2022 Mateusz Viste
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

/*
 * cls
 *
 * TIPC extensions:
 *   CLS     clear text + graphics, reset text attribute
 *   CLS /T  clear text only, reset text attribute
 *   CLS /G  clear graphics planes only
 *   CLS /A  clear graphics plane A only
 *   CLS /B  clear graphics plane B only
 *   CLS /C  clear graphics plane C only
 *   CLS /P  reset prompt only
 */

static void tipc_cls_clear_plane(unsigned short planeseg) {
  _asm {
    push ax
    push cx
    push di
    push es

    mov ax, planeseg
    mov es, ax
    xor ax, ax
    xor di, di
    mov cx, 0x4000
    cld
    rep stosw

    pop es
    pop di
    pop cx
    pop ax
  }
}


static enum cmd_result cmd_cls(struct cmd_funcparam *p) {
  const char *ansiesc = "\x1B[2J$";
  unsigned char mode = 0;       /* 0=normal CLS, otherwise T/G/A/B/C */

  if (cmd_ishlp(p)) {
    nls_outputnl(10,0); /* "Clears the screen" */
    outputnl("");
    // outputnl("CLS");
    outputnl("CLS [/T|/G|/A|/B|/C|/P]");
    outputnl("  /T  Clear text only and reset cursor");
    outputnl("  /G  Clear graphics planes");
    outputnl("  /A  Clear graphics plane A only");
    outputnl("  /B  Clear graphics plane B only");
    outputnl("  /C  Clear graphics plane C only");
    outputnl("  /P  Reset prompt only");
    return(CMD_OK);
  }

  if (p->argc > 1) {
    outputnl("Usage: CLS [/T|/G|/A|/B|/C]");
    return(CMD_FAIL);
  }

  if (p->argc == 1) {
    if      (imatch(p->argv[0], "/T")) mode = 'T';
    else if (imatch(p->argv[0], "/G")) mode = 'G';
    else if (imatch(p->argv[0], "/A")) mode = 'A';
    else if (imatch(p->argv[0], "/B")) mode = 'B';
    else if (imatch(p->argv[0], "/C")) mode = 'C';
    else if (imatch(p->argv[0], "/P")) mode = 'P';
    else {
      outputnl("Usage: CLS [/T|/G|/A|/B|/C|/P]");
      return(CMD_FAIL);
    }
  }

  /* single graphics plane - don't use DSR, write to VRAM instead */
  if (mode == 'A') {
    tipc_cls_clear_plane(0xC000);
    return(CMD_OK);   
  }
  if (mode == 'B') {
    tipc_cls_clear_plane(0xC800);
    return(CMD_OK);
  }
  if (mode == 'C') {
    tipc_cls_clear_plane(0xD000);
    return(CMD_OK);
  }

  /* clear all graphics - use DSR interrupt function */
  if (mode == 'G') {
    _asm {
      mov ah, 0x14
      int 0x49
    }
    return(CMD_OK);   
  }

  /* clear text only  - use DSR interrupt function */
  if (mode == 'T') {
    _asm {
      mov ah, 0x13
      int 0x49
    }
    return(CMD_OK);   
  }

  /* reset prompt */
  if (mode == 'P') {
   _asm {
    mov bl, 0x0F
    mov ah, 0x16
    int 0x49
   }
   return(CMD_OK);   
  }


 _asm {
    /* output an ANSI ESC code for "clear screen" in case the console is
     * some kind of terminal */
    mov ah, 0x09     /* write $-terminated string to stdout */
    mov dx, ansiesc
    int 0x21

    /* check what stdout is set to */
    mov ax, 0x4400   /* IOCTL query device/flags flags */
    mov bx, 1        /* file handle (1 = stdout) */
    int 0x21         /* CF set on error, otherwise DX set with flags */
    jc DONE          /* abort on error */
    /* DX = 10000010
            |   |||
            |   ||+--- indicates standard output
            |   |+---- set if NUL device
            |   +----- set if CLOCK device
            +--------- set if handle is a device (ie. not a file)
            in other words, DL & 10001110 (8Eh) should result in 10000010 (82h)
            */
    and dl, 0x8e
    cmp dl, 0x82
    jne DONE         /* abort on error */

    /* TIPC native CRT DSR, just like TIPC MSDOS 2.13 */ 
    mov ah, 0x13
    int 0x49
    mov ah, 0x14
    int 0x49

    /* and reset attribute latch, like TIPC MSDOS 2.13 */
    mov bl, 0x0F
    mov ah, 0x16
    int 0x49

    DONE:
  }
  return(CMD_OK);
}
