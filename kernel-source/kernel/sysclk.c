/****************************************************************/
/*                                                              */
/*                           sysclk.c                           */
/*                                                              */
/*                     System Clock Driver                      */
/*                                                              */
/*                      Copyright (c) 1995                      */
/*                      Pasquale J. Villani                     */
/*                      All Rights Reserved                     */
/*                                                              */
/* This file is part of DOS-C.                                  */
/*                                                              */
/* DOS-C is free software; you can redistribute it and/or       */
/* modify it under the terms of the GNU General Public License  */
/* as published by the Free Software Foundation; either version */
/* 2, or (at your option) any later version.                    */
/*                                                              */
/* DOS-C is distributed in the hope that it will be useful, but */
/* WITHOUT ANY WARRANTY; without even the implied warranty of   */
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See    */
/* the GNU General Public License for more details.             */
/*                                                              */
/* You should have received a copy of the GNU General Public    */
/* License along with DOS-C; see the file COPYING.  If not,     */
/* write to the Free Software Foundation, 675 Mass Ave,         */
/* Cambridge, MA 02139, USA.                                    */
/****************************************************************/

/* compared to TIPC, the clock on IBM is much more difficult    */
/* On TIPC the system ROM manages to clock values, and increases*/
/* the values with a 100ms tick interval                        */
/* So for the DOS clock, just read the memory values ;)         */

#include "portab.h"
#include "globals.h"

#ifdef VERSION_STRINGS
static char *RcsId =
    "$Id: sysclk.c 681 2003-09-09 17:32:20Z bartoldeman $";
#endif

/*                                                                      */
/* WARNING - THIS DRIVER IS NON-PORTABLE!!!!                            */
/* HENCE MODIFIED FOR TIPC, WHERE CLOCK IS MANAGED BY ROM               */
/*                                                                      */
UWORD ASM DaysSinceEpoch = 0;

/* TIPC ROMDAT derived from Tech Ref 1984. to the                       */
#define TIPC_ROMDAT_PTR  0x0180
#define TIPC_HUNS            0x013a
#define TIPC_SECS            0x013b
#define TIPC_MINS            0x013c
#define TIPC_HOURS           0x013d
#define TIPC_DATE            0x013e

/* System ROM takes care of clock - so just read from ROMDAT */
STATIC void tipc_read_clock(struct ClockRecord *clk)
{
  volatile UWORD FAR *fixed;
  volatile UBYTE FAR *romdat;
  UWORD seg;

  fixed = (volatile UWORD FAR *)MK_FP(0, TIPC_ROMDAT_PTR);
  seg = *fixed;
  romdat = (volatile UBYTE FAR *)MK_FP(seg, 0);

  disable();
  clk->clkHundredths = romdat[TIPC_HUNS];
  clk->clkSeconds = romdat[TIPC_SECS];
  clk->clkMinutes = romdat[TIPC_MINS];
  clk->clkHours = romdat[TIPC_HOURS];
  clk->clkDays = *(volatile UWORD FAR *)(romdat + TIPC_DATE);
  enable();

  DaysSinceEpoch = clk->clkDays;
}

/* source of truth is in ROMDAT - so modify if requested */
STATIC int tipc_write_clock(const struct ClockRecord *clk)
{
  volatile UWORD FAR *fixed;
  volatile UBYTE FAR *romdat;
  UWORD seg;

  if (clk->clkHours > 23 || clk->clkMinutes > 59 ||
      clk->clkSeconds > 59 || clk->clkHundredths > 99)
    return FALSE;

  fixed = (volatile UWORD FAR *)MK_FP(0, TIPC_ROMDAT_PTR);
  seg = *fixed;
  romdat = (volatile UBYTE FAR *)MK_FP(seg, 0);

  disable();
  romdat[TIPC_HUNS] = clk->clkHundredths;
  romdat[TIPC_SECS] = clk->clkSeconds;
  romdat[TIPC_MINS] = clk->clkMinutes;
  romdat[TIPC_HOURS] = clk->clkHours;
  *(volatile UWORD FAR *)(romdat + TIPC_DATE) = clk->clkDays;
  enable();

  DaysSinceEpoch = clk->clkDays;
  return TRUE;
}

WORD ASMCFUNC FAR clk_driver(rqptr rp)
{
  switch (rp->r_command)
  {
    case C_INIT:
      {
        /* TIPC has no integrated RTC. We init 1980-01-01 00:00:00 just like TIPC MS-DOS 2.x */
	/* note - add-on RTC cards on TIPC always initialized in OS (CONFIG.SYS or AUTOEXEC.BAT)  */
        struct ClockRecord initial = { 0, 0, 0, 0, 0 };
        tipc_write_clock(&initial);
        rp->r_nunits = 0;
      }
      return S_DONE;

    case C_INPUT:
      {
        struct ClockRecord clk;

        if (sizeof(struct ClockRecord) != rp->r_count)
          return failure(E_LENGTH);

        tipc_read_clock(&clk);
        fmemcpy(rp->r_trans, &clk, sizeof(struct ClockRecord));
      }
      return S_DONE;

    case C_OUTPUT:
      {
        struct ClockRecord clk;

        if (sizeof(struct ClockRecord) != rp->r_count)
          return failure(E_LENGTH);

        fmemcpy(&clk, rp->r_trans, sizeof(struct ClockRecord));
        if (!tipc_write_clock(&clk))
          return failure(E_FAILURE);
      }
      return S_DONE;

    case C_OFLUSH:
    case C_IFLUSH:
      return S_DONE;

    case C_OUB:
    case C_NDREAD:
    case C_OSTAT:
    case C_ISTAT:
    default:
      return failure(E_FAILURE);
  }
}
