{Regression test for the double free self cycle (issue #73).

 Freeing the same block twice must raise an invalid pointer error, and - the
 part that actually broke - it must not corrupt the pending free list while
 doing so.  The original implementation of the head guard wrote
 PPointer(ABlock)^ := LHead before comparing the two, so when the block being
 freed a second time already was the list head, the block ended up pointing at
 itself:  an endless loop the next time the pending frees were processed, even
 though the error had been reported correctly.

 Getting into the pending free path deterministically is the trick here:  a
 second thread walks the blocks and sleeps inside the walk callback, but only
 when it reaches this test's block, which guarantees that the manager owning
 that block is locked when both FreeMem calls arrive.  Sleeping on any block
 would not do - as soon as anything else is allocated (SysUtils alone is
 enough), the walker would fall asleep on the wrong manager and both frees would
 quietly take the normal path, which looks exactly like a passing test.

 Optional parameter:  the block size, to steer the test at a size class.
 Default 2000 (small);  50000 selects a medium block, 500000 a large one.}

program FastMM5Test_DoubleFree;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}Winapi.Windows, System.SysUtils{$else}Windows, SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

var
  GTarget: Pointer;
  GWalkerIsOnTarget: Integer;

procedure WalkCallback(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
begin
  {Only sleep on the block under test:  that pins the lock to the manager that
   owns it.}
  if ABlockInfo.BlockAddress = GTarget then
  begin
    InterlockedExchange(GWalkerIsOnTarget, 1);
    Sleep(2000);
  end;
end;

function LockerThread(AParameter: Pointer): DWORD; stdcall;
begin
  FastMM_WalkBlocks(WalkCallback, [btSmallBlock, btMediumBlock, btLargeBlock], False, nil, 5000);
  Result := 0;
end;

var
  GPointer: Pointer;
  GThread: THandle;
  GThreadId: DWORD;
  GSecondFreeRaised: Boolean;
  GLinkAfterFirstFree, GLinkAfterSecondFree: NativeUInt;
  GBlockSize: Integer;

begin
  TestsBegin('FastMM5 double free handling (issue #73)');

  GBlockSize := StrToIntDef(ParamStr(1), 2000);
  Info(Format('block size: %d bytes', [GBlockSize]));

  GetMem(GTarget, GBlockSize);
  GPointer := GTarget;

  GThread := CreateThread(nil, 0, @LockerThread, nil, 0, GThreadId);
  Check(GThread <> 0, 'the walker thread starts');
  while GWalkerIsOnTarget = 0 do
    Sleep(1);
  Info('the walker is holding the lock on the block under test');

  FreeMem(GPointer);
  GLinkAfterFirstFree := PNativeUInt(GPointer)^;

  GSecondFreeRaised := False;
  try
    FreeMem(GPointer);
  except
    GSecondFreeRaised := True;
  end;
  GLinkAfterSecondFree := PNativeUInt(GPointer)^;

  WaitForSingleObject(GThread, INFINITE);
  CloseHandle(GThread);

  Check(GSecondFreeRaised, 'the second FreeMem raises an error');
  {The regression:  the pending free link must be exactly what it was before the
   rejected second free, and in particular must not point at the block itself.}
  Check(GLinkAfterSecondFree <> NativeUInt(GPointer),
    'the block does not end up pointing at itself (no self cycle)');
  CheckEqualsInt(Int64(GLinkAfterFirstFree), Int64(GLinkAfterSecondFree),
    'the rejected free leaves the pending free link untouched');

  TestsEnd;
end.
