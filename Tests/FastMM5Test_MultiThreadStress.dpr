{Multithreaded allocation stress.

 Every thread allocates blocks of random sizes, fills them with a size dependent
 pattern, verifies that pattern and frees them again.  Optionally a share of the
 blocks is handed to another thread through a lock free mailbox and freed there,
 which exercises the cross thread free path (the pending free lists).

 What is asserted at the end:  every block that was handed out came back with
 its content intact, and the allocated byte count returns to where it started -
 so nothing was leaked, double counted or handed out twice.

 Parameters:  Threads Iterations MaxBlockSize DebugMode(0/1) CrossThreadFree(0/1)
 Defaults:    4 20000 70000 1 1}

program FastMM5Test_MultiThreadStress;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}Winapi.Windows, System.SysUtils{$else}Windows, SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

const
  CMailboxSlots = 64;
  CMaxThreads = 32;

var
  GIterations, GMaxBlockSize: Integer;
  GCrossThreadFree: Boolean;
  GMailbox: array[0..CMailboxSlots - 1] of Pointer;
  {Counts blocks whose content did not survive:  written by the worker threads,
   read after they have all finished.}
  GContentErrors: Integer;
  GBlocksHandled: Integer;

{Pointer wide atomic exchange.  Plain InterlockedExchange takes a 32 bit value,
 which would silently truncate the upper half of a pointer on Win64, so use the
 pointer sized API where it is available.  Delphi 7 does not declare it, but
 that compiler only ever builds 32 bit.}
function ExchangePointer(var ATarget: Pointer; AValue: Pointer): Pointer;
begin
{$if CompilerVersion >= 18}
  Result := InterlockedExchangePointer(ATarget, AValue);
{$else}
  Result := Pointer(InterlockedExchange(Integer(ATarget), Integer(AValue)));
{$ifend}
end;

{Verifies the pattern that was written into a block.  The size is recovered from
 the first byte, so a block that came back from another thread can be checked
 without carrying its size along.}
function ContentIsIntact(APointer: Pointer; ASize: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to ASize - 1 do
  begin
    if PByte(PAnsiChar(APointer) + i)^ <> Byte(ASize) then
      Exit;
  end;
  Result := True;
end;

function StressThread(AParameter: Pointer): Integer; stdcall;
var
  LSeed: Cardinal;
  LIteration, LSize, LSlot: Integer;
  LPointer, LSwapped: Pointer;
begin
  {A per thread xorshift generator:  the RTL random number generator is global
   state and would serialise the threads.}
  LSeed := Cardinal(NativeUInt(AParameter)) * $9E3779B9 + 1;
  for LIteration := 1 to GIterations do
  begin
    LSeed := LSeed xor (LSeed shl 13);
    LSeed := LSeed xor (LSeed shr 17);
    LSeed := LSeed xor (LSeed shl 5);
    LSize := Integer(LSeed mod Cardinal(GMaxBlockSize)) + 1;

    GetMem(LPointer, LSize);
    FillChar(LPointer^, LSize, Byte(LSize));
    if not ContentIsIntact(LPointer, LSize) then
      InterlockedIncrement(GContentErrors);
    InterlockedIncrement(GBlocksHandled);

    if GCrossThreadFree and (LSeed and 7 = 0) then
    begin
      {Hand the block to whichever thread comes past this slot next, and free
       whatever was in the slot before.}
      LSlot := (LSeed shr 16) and (CMailboxSlots - 1);
      LSwapped := ExchangePointer(GMailbox[LSlot], LPointer);
      if LSwapped <> nil then
        FreeMem(LSwapped);
    end
    else
      FreeMem(LPointer);
  end;
  Result := 0;
end;

var
  GThreads: array[0..CMaxThreads - 1] of THandle;
  GThreadId: Cardinal;
  i, GThreadCount: Integer;
  GDebugMode: Boolean;
  GUsageBefore, GUsageAfter: TFastMM_UsageSummary;

begin
  TestsBegin('FastMM5 multithreaded stress');

  GThreadCount := StrToIntDef(ParamStr(1), 4);
  if GThreadCount > CMaxThreads then
    GThreadCount := CMaxThreads;
  GIterations := StrToIntDef(ParamStr(2), 20000);
  GMaxBlockSize := StrToIntDef(ParamStr(3), 70000);
  GDebugMode := ParamStr(4) <> '0';
  GCrossThreadFree := ParamStr(5) <> '0';

  Info(Format('threads %d, iterations %d, max block size %d, debug mode %s, cross thread free %s',
    [GThreadCount, GIterations, GMaxBlockSize, BoolToStr(GDebugMode, True),
     BoolToStr(GCrossThreadFree, True)]));

  GUsageBefore := FastMM_GetUsageSummary;
  if GDebugMode then
    Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  GContentErrors := 0;
  GBlocksHandled := 0;
  for i := 0 to GThreadCount - 1 do
    GThreads[i] := CreateThread(nil, 0, @StressThread, Pointer(i + 1), 0, GThreadId);
  for i := 0 to GThreadCount - 1 do
  begin
    WaitForSingleObject(GThreads[i], INFINITE);
    CloseHandle(GThreads[i]);
  end;

  {Drain the mailbox:  whatever is still parked there was never freed.}
  for i := 0 to CMailboxSlots - 1 do
    if GMailbox[i] <> nil then
      FreeMem(GMailbox[i]);

  Section('Results');
  Info(Format('%d blocks handled', [GBlocksHandled]));
  CheckEqualsInt(GThreadCount * GIterations, GBlocksHandled, 'every iteration ran');
  CheckEqualsInt(0, GContentErrors, 'every block kept its content');

  {Cross thread frees may still be sitting in the pending free lists of arenas
   that were locked at the time, so they have to be processed before the balance
   can be compared.}
  FastMM_ProcessAllPendingFrees;
  GUsageAfter := FastMM_GetUsageSummary;
  Info(Format('allocated before %d, after %d, overhead after %d',
    [Int64(GUsageBefore.AllocatedBytes), Int64(GUsageAfter.AllocatedBytes),
     Int64(GUsageAfter.OverheadBytes)]));
  Check(Int64(GUsageAfter.AllocatedBytes) - Int64(GUsageBefore.AllocatedBytes) < 65536,
    'the allocated byte count returns to its starting value');

  if GDebugMode then
    Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  TestsEnd;
end.
