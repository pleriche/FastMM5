{Contract regression test for the debug and erase mode switches (issue #85).

 The documented contract:  the internal nesting counter is adjusted on every
 Begin/Enter and End/Exit call, regardless of the return value.  Callers must
 therefore balance a Begin/Enter with an End/Exit even when it returned False.
 The corresponding *Active function is True exactly when the counter is above
 zero AND the last call succeeded.

 This test pins that contract down, in particular against the tempting but wrong
 "roll the counter back when the call fails" idea:  with correctly balanced
 usage that drives the counter negative, so a later genuine Begin no longer
 activates the mode.  Scenario A below is what catches it.

 The failing Begin/Enter is produced by installing a memory manager whose
 function pointers differ from FastMM's, which makes FastMM see that the memory
 manager was changed externally.}

program FastMM5Test_ModeTransition;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

type
  {Delphi 7 does not export TMemoryManagerEx;  there the three field
   TMemoryManager is enough.  The size parameter became NativeInt in XE2
   (CompilerVersion 23);  older compilers use Integer.}
  {$if CompilerVersion >= 18}
  TMemoryManagerRecord = TMemoryManagerEx;
  {$else}
  TMemoryManagerRecord = TMemoryManager;
  {$ifend}
  {$if CompilerVersion >= 23}
  TMemoryManagerSize = NativeInt;
  {$else}
  TMemoryManagerSize = Integer;
  {$ifend}

var
  GOriginalMM: TMemoryManagerRecord;
  GExternalMM: TMemoryManagerRecord;

{The "external" memory manager just forwards to FastMM;  all that matters is
 that its function pointers are not FastMM's own.}
function ForwardGetMem(ASize: TMemoryManagerSize): Pointer;
begin
  Result := GOriginalMM.GetMem(ASize);
end;

function ForwardFreeMem(APointer: Pointer): Integer;
begin
  Result := GOriginalMM.FreeMem(APointer);
end;

function ForwardReallocMem(APointer: Pointer; ASize: TMemoryManagerSize): Pointer;
begin
  Result := GOriginalMM.ReallocMem(APointer, ASize);
end;

{Scenario A, the core case:  a failed Begin is balanced with an End as the
 contract requires, and a genuine Begin/End pair afterwards must still switch
 the mode correctly.}
procedure TestBalancedThroughFailure_FreedContent;
var
  LActiveAfterRealBegin: Boolean;
begin
  Section('Erase freed block content:  balanced through a failure');
  SetMemoryManager(GExternalMM);
  try
    Check(not FastMM_BeginEraseFreedBlockContent, 'Begin fails while an external manager is installed');
    {Per the contract the counter went up, but Active stays False because the
     last call did not succeed.}
    Check(not FastMM_EraseFreedBlockContentActive, 'the mode is not active after the failed Begin');
  finally
    SetMemoryManager(GOriginalMM);
  end;
  Check(FastMM_EndEraseFreedBlockContent, 'the balancing End succeeds');

  Check(FastMM_BeginEraseFreedBlockContent, 'a genuine Begin succeeds');
  LActiveAfterRealBegin := FastMM_EraseFreedBlockContentActive;
  Check(FastMM_EndEraseFreedBlockContent, 'the matching End succeeds');
  Check(LActiveAfterRealBegin, 'the genuine Begin actually activated the mode (counter intact)');
  Check(not FastMM_EraseFreedBlockContentActive, 'the mode is inactive again after the balanced pair');
end;

procedure TestBalancedThroughFailure_AllocatedContent;
var
  LActiveAfterRealBegin: Boolean;
begin
  Section('Erase allocated block content:  balanced through a failure');
  SetMemoryManager(GExternalMM);
  try
    Check(not FastMM_BeginEraseAllocatedBlockContent, 'Begin fails while an external manager is installed');
    Check(not FastMM_EraseAllocatedBlockContentActive, 'the mode is not active after the failed Begin');
  finally
    SetMemoryManager(GOriginalMM);
  end;
  Check(FastMM_EndEraseAllocatedBlockContent, 'the balancing End succeeds');

  Check(FastMM_BeginEraseAllocatedBlockContent, 'a genuine Begin succeeds');
  LActiveAfterRealBegin := FastMM_EraseAllocatedBlockContentActive;
  Check(FastMM_EndEraseAllocatedBlockContent, 'the matching End succeeds');
  Check(LActiveAfterRealBegin, 'the genuine Begin actually activated the mode (counter intact)');
  Check(not FastMM_EraseAllocatedBlockContentActive, 'the mode is inactive again after the balanced pair');
end;

procedure TestBalancedThroughFailure_DebugMode;
var
  LActiveAfterRealEnter: Boolean;
begin
  Section('Debug mode:  balanced through a failure');
  SetMemoryManager(GExternalMM);
  try
    Check(not FastMM_EnterDebugMode, 'Enter fails while an external manager is installed');
    Check(not FastMM_DebugModeActive, 'debug mode is not active after the failed Enter');
  finally
    SetMemoryManager(GOriginalMM);
  end;
  Check(FastMM_ExitDebugMode, 'the balancing Exit succeeds');

  Check(FastMM_EnterDebugMode, 'a genuine Enter succeeds');
  LActiveAfterRealEnter := FastMM_DebugModeActive;
  Check(FastMM_ExitDebugMode, 'the matching Exit succeeds');
  Check(LActiveAfterRealEnter, 'the genuine Enter actually activated debug mode (counter intact)');
  Check(not FastMM_DebugModeActive, 'debug mode is inactive again after the balanced pair');
end;

{Scenario B:  ordinary nested usage, no external manager involved.}
procedure TestNormalNesting;
begin
  Section('Ordinary nesting');
  Check(FastMM_BeginEraseFreedBlockContent, 'Begin succeeds');
  Check(FastMM_EraseFreedBlockContentActive, 'the mode is active after Begin');
  Check(FastMM_BeginEraseFreedBlockContent, 'the nested Begin succeeds');
  Check(FastMM_EndEraseFreedBlockContent, 'the first End succeeds');
  Check(FastMM_EraseFreedBlockContentActive, 'the mode is still active after the first End (nesting)');
  Check(FastMM_EndEraseFreedBlockContent, 'the second End succeeds');
  Check(not FastMM_EraseFreedBlockContentActive, 'the mode is inactive after the balanced End');
end;

begin
  TestsBegin('FastMM5 mode transition contract (issue #85)');

  GetMemoryManager(GOriginalMM);
  GExternalMM := GOriginalMM;
  GExternalMM.GetMem := ForwardGetMem;
  GExternalMM.FreeMem := ForwardFreeMem;
  GExternalMM.ReallocMem := ForwardReallocMem;

  TestBalancedThroughFailure_FreedContent;
  TestBalancedThroughFailure_AllocatedContent;
  TestBalancedThroughFailure_DebugMode;
  TestNormalNesting;

  TestsEnd;
end.
