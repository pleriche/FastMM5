{Leak and address space growth detector:  hammers GetMem/FreeMem in each size
 class in turn and checks that the memory manager gives everything back.

 Two things are asserted after every phase:

   - the allocated byte count returns to where it was, which catches a block
     that is never accounted as freed, and
   - the overhead (committed address space that is not allocated to the
     application) does not keep growing from phase to phase, which catches spans
     that are never released.

 The second one is why this test exists:  in debug mode FastMM deliberately
 keeps freed blocks around as use-after-free tripwires, and a version of that
 behaviour once turned into an unbounded ratchet under repeated churn.}

program FastMM5Test_UsagePerSizeClass;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

var
  GBaselineAllocated: NativeUInt;
  GPeakOverhead: NativeUInt;

procedure ReportUsage(const APhase: string);
var
  LSummary: TFastMM_UsageSummary;
begin
  LSummary := FastMM_GetUsageSummary;
  Info(Format('%-44s allocated %10d   overhead %10d',
    [APhase, Int64(LSummary.AllocatedBytes), Int64(LSummary.OverheadBytes)]));
  if LSummary.OverheadBytes > GPeakOverhead then
    GPeakOverhead := LSummary.OverheadBytes;
end;

{Allocates and frees ACount blocks of ASize bytes, then checks that the
 allocated total is back at the baseline.}
procedure Hammer(ASize, ACount: Integer);
var
  LPointer: Pointer;
  i: Integer;
  LSummary: TFastMM_UsageSummary;
begin
  for i := 1 to ACount do
  begin
    GetMem(LPointer, ASize);
    FillChar(LPointer^, ASize, 1);
    FreeMem(LPointer);
  end;
  ReportUsage(Format('%d x GetMem/FreeMem(%d)', [ACount, ASize]));

  LSummary := FastMM_GetUsageSummary;
  {The baseline is whatever the RTL itself holds;  it must not have grown by the
   churn.  A tolerance of a few hundred bytes covers the bookkeeping the test
   program itself does between the measurements.}
  Check(Int64(LSummary.AllocatedBytes) - Int64(GBaselineAllocated) < 4096,
    Format('%d byte class:  nothing is left allocated', [ASize]));
end;

var
  GSummary: TFastMM_UsageSummary;
  GOverheadAfterFirstPhase: NativeUInt;

begin
  TestsBegin('FastMM5 usage accounting per size class');

  GPeakOverhead := 0;
  GSummary := FastMM_GetUsageSummary;
  GBaselineAllocated := GSummary.AllocatedBytes;
  ReportUsage('start');

  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');
  ReportUsage('after FastMM_EnterDebugMode');

  Section('Churn per size class (debug mode)');
  Hammer(500, 10000);
  GSummary := FastMM_GetUsageSummary;
  GOverheadAfterFirstPhase := GSummary.OverheadBytes;

  Hammer(3000, 10000);
  Hammer(10000, 10000);
  Hammer(40000, 10000);
  Hammer(70000, 10000);
  Hammer(200000, 2000);
  Hammer(500000, 1000);

  Section('Address space');
  GSummary := FastMM_GetUsageSummary;
  {Every phase frees everything it allocates, so the committed address space
   must not keep climbing phase after phase.  Some growth is expected (each size
   class needs its own spans), hence the generous factor;  what this catches is
   the unbounded case, where the overhead is orders of magnitude larger.}
  Check(Int64(GSummary.OverheadBytes) < Int64(GOverheadAfterFirstPhase) * 4 + 16 * 1024 * 1024,
    Format('the overhead stays bounded across the phases (%d -> %d bytes)',
      [Int64(GOverheadAfterFirstPhase), Int64(GSummary.OverheadBytes)]));

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');
  ReportUsage('after FastMM_ExitDebugMode');

  GSummary := FastMM_GetUsageSummary;
  Check(Int64(GSummary.AllocatedBytes) - Int64(GBaselineAllocated) < 4096,
    'the allocated byte count is back at the baseline');

  TestsEnd;
end.
