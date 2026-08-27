/* HMA/XMS kind of disabled for TIPC, we only have conventional memory 
   TODO - remove more of this stuff */
#include "portab.h"
#include "init-mod.h"
#define HMAOFFSET 0x20

BYTE DosLoadedInHMA BSS_INIT(FALSE);
BYTE HMAclaimed BSS_INIT(0);
UWORD HMAFree BSS_INIT(0);
unsigned CurrentKernelSegment = 0;

int MoveKernelToHMA(void)
{
  return FALSE;
}

VOID FAR * HMAalloc(COUNT bytesToAllocate)
{
  (void)bytesToAllocate;
  return NULL;
}

void MoveKernel(unsigned NewKernelSegment)
{
  UBYTE FAR *HMADest;
  UBYTE FAR *HMASource;
  unsigned len;
  unsigned jmpseg = CurrentKernelSegment;

  if (CurrentKernelSegment == 0)
    CurrentKernelSegment = FP_SEG(_HMATextEnd);

  if (CurrentKernelSegment == 0xffff)
    return;

  HMASource = MK_FP(CurrentKernelSegment,
                    (FP_OFF(_HMATextStart) & 0xfff0));
  HMADest = MK_FP(NewKernelSegment, 0x0000);
  len = (FP_OFF(_HMATextEnd) | 0x000f) -
        (FP_OFF(_HMATextStart) & 0xfff0);

  if (NewKernelSegment == 0xffff)
  {
    HMASource += HMAOFFSET;
    HMADest += HMAOFFSET;
    len -= HMAOFFSET;
  }

  if (NewKernelSegment < CurrentKernelSegment ||
      NewKernelSegment == 0xffff)
    fmemcpy(HMADest, HMASource, len);

  HMAFree = (FP_OFF(HMADest) + len + 0xf) & 0xfff0;

  {
    struct RelocationTable FAR *rp, rtemp;

    for (rp = _HMARelocationTableStart;
         rp < _HMARelocationTableEnd; rp++)
    {
      if (rp->jmpFar != 0xea || rp->jmpSegment != jmpseg ||
          rp->callNear != 0xe8)
        for (;;) ;
    }

    for (rp = _HMARelocationTableStart;
         rp < _HMARelocationTableEnd; rp++)
    {
      if (NewKernelSegment == 0xffff)
      {
        struct RelocatedEntry FAR *rel =
          (struct RelocatedEntry FAR *)rp;
        fmemcpy(&rtemp, rp, sizeof(rtemp));
        rel->jmpFar = rtemp.jmpFar;
        rel->jmpSegment = NewKernelSegment;
        rel->jmpOffset = rtemp.jmpOffset;
        rel->callNear = rtemp.callNear;
        rel->callOffset = rtemp.callOffset + 5;
      }
      else
        rp->jmpSegment = NewKernelSegment;
    }

    if (NewKernelSegment == 0xffff)
    {
      pokeb(0xffff, 0x30 * 4 + 0x10, 0xea);
      pokel(0xffff, 0x30 * 4 + 0x11, (ULONG)cpm_entry);
    }
  }

  CurrentKernelSegment = NewKernelSegment;
}
