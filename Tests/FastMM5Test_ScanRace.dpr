{The counterpart to FastMM5Test_ScanCoverage:  that one checks that real
 corruption is still found, this one that none is invented.

 Worker threads hammer small debug block allocation and freeing, so spans are
 constantly sequentially fed, split off and recycled, while another thread runs
 FastMM_ScanDebugBlocksForCorruption in a loop.  Nothing is ever corrupted here,
 so every exception the scanner sees is a false positive, and any access
 violation is a crash inside the walk itself.

 The header of a small block is populated after the block has been split off
 from the sequential feed span, without the protection of a lock, so the walk
 has to decide what to make of a header that may not be valid yet.  That
 decision trades detection against false positives (see issue #102), which is
 why both directions need a test.

 Parameters:  Seconds Threads     Defaults:  10 4}

program FastMM5Test_ScanRace;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}Winapi.Windows, System.SysUtils, System.Classes
  {$else}Windows, SysUtils, Classes{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

var
  GStop: Integer = 0;
  GAllocations: Integer = 0;
  GScans: Integer = 0;
  GFalsePositives: Integer = 0;
  GWorkerErrors: Integer = 0;
  GScannerCrashes: Integer = 0;

type
  TWorker = class(TThread)
  private
    FSeed: Cardinal;
    function NextRandom(ALimit: Integer): Integer;
  protected
    procedure Execute; override;
  public
    constructor Create(ASeed: Cardinal);
  end;

  TScanner = class(TThread)
  protected
    procedure Execute; override;
  end;

constructor TWorker.Create(ASeed: Cardinal);
begin
  FSeed := ASeed;
  inherited Create(False);
end;

function TWorker.NextRandom(ALimit: Integer): Integer;
begin
  {A private generator:  the RTL one is global state and would itself become a
   source of contention.}
  FSeed := FSeed * 1103515245 + 12345;
  Result := Integer((FSeed shr 16) mod Cardinal(ALimit));
end;

procedure TWorker.Execute;
const
  CLiveBlocks = 64;
var
  LBlocks: array[0..CLiveBlocks - 1] of Pointer;
  LSizes: array[0..CLiveBlocks - 1] of Integer;
  i, LIndex, LSize: Integer;
begin
  for i := 0 to CLiveBlocks - 1 do
  begin
    LBlocks[i] := nil;
    LSizes[i] := 0;
  end;
  try
    while GStop = 0 do
    begin
      LIndex := NextRandom(CLiveBlocks);
      if LBlocks[LIndex] <> nil then
      begin
        {Verify the block still holds what was written into it:  corruption of
         user data would show up here rather than in the scanner.}
        if PByte(LBlocks[LIndex])^ <> Byte(LSizes[LIndex]) then
          InterlockedIncrement(GWorkerErrors);
        FreeMem(LBlocks[LIndex]);
        LBlocks[LIndex] := nil;
      end;
      {Small blocks only:  that is the path the header validity question is
       about.}
      LSize := 16 + NextRandom(2000);
      GetMem(LBlocks[LIndex], LSize);
      LSizes[LIndex] := LSize;
      FillChar(LBlocks[LIndex]^, LSize, Byte(LSize));
      InterlockedIncrement(GAllocations);
    end;
  except
    on E: Exception do
    begin
      InterlockedIncrement(GWorkerErrors);
      WriteLn('        worker exception: ', E.ClassName, ': ', E.Message);
    end;
  end;
  for i := 0 to CLiveBlocks - 1 do
    if LBlocks[i] <> nil then
      FreeMem(LBlocks[i]);
end;

procedure TScanner.Execute;
begin
  while GStop = 0 do
  begin
    try
      FastMM_ScanDebugBlocksForCorruption(1000);
      InterlockedIncrement(GScans);
    except
      on E: Exception do
      begin
        if E is EAccessViolation then
        begin
          InterlockedIncrement(GScannerCrashes);
          WriteLn('        scanner A/V: ', E.Message);
        end
        else
        begin
          InterlockedIncrement(GFalsePositives);
          WriteLn('        scanner false positive: ', E.ClassName, ': ', E.Message);
        end;
      end;
    end;
  end;
end;

var
  GWorkers: array of TWorker;
  GScanner: TScanner;
  i, GSeconds, GThreadCount: Integer;

begin
  TestsBegin('FastMM5 corruption scan under concurrent allocation');

  GSeconds := StrToIntDef(ParamStr(1), 10);
  GThreadCount := StrToIntDef(ParamStr(2), 4);
  Info(Format('%d worker thread(s) churning small debug blocks for %d s, one thread scanning',
    [GThreadCount, GSeconds]));

  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  SetLength(GWorkers, GThreadCount);
  for i := 0 to GThreadCount - 1 do
    GWorkers[i] := TWorker.Create(Cardinal(i) * 7919 + 12345);
  GScanner := TScanner.Create(False);

  Sleep(GSeconds * 1000);
  InterlockedExchange(GStop, 1);

  GScanner.WaitFor;
  GScanner.Free;
  for i := 0 to GThreadCount - 1 do
  begin
    GWorkers[i].WaitFor;
    GWorkers[i].Free;
  end;

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  Section('Results');
  Info(Format('%d allocations, %d completed scans', [GAllocations, GScans]));
  Check(GAllocations > 0, 'the workers ran');
  Check(GScans > 0, 'the scanner ran');
  CheckEqualsInt(0, GFalsePositives, 'the scan reported no corruption that was never there');
  CheckEqualsInt(0, GScannerCrashes, 'the scan did not crash');
  CheckEqualsInt(0, GWorkerErrors, 'the workers saw no corrupted block content');

  TestsEnd;
end.
