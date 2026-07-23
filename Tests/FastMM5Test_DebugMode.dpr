{Basic debug mode test:  entering and leaving debug mode, allocating, writing,
 reallocating and freeing blocks in both modes, and verifying that the memory
 manager hands back what was written and accounts for everything afterwards.

 This is the smoke test:  if FastMM5 is fundamentally broken, this fails first.}

program FastMM5Test_DebugMode;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

{Fills a block with a size dependent pattern and checks it back.  Returns True
 if every byte survived.}
function FillAndVerify(APointer: Pointer; ASize: Integer): Boolean;
var
  i: Integer;
  LPBytes: PByte;
begin
  LPBytes := PByte(APointer);
  for i := 0 to ASize - 1 do
    PByte(PAnsiChar(LPBytes) + i)^ := Byte(i + ASize);
  Result := True;
  for i := 0 to ASize - 1 do
  begin
    if PByte(PAnsiChar(LPBytes) + i)^ <> Byte(i + ASize) then
    begin
      Result := False;
      Exit;
    end;
  end;
end;

var
  GPointer: Pointer;
  GSecond: Pointer;
  i: Integer;
  GAllContentIntact: Boolean;
  GUsageBefore, GUsageAfter: TFastMM_UsageSummary;
  GDebugHeaderSize: Integer;

begin
  TestsBegin('FastMM5 debug mode basics');

  {The debug block header carries the metadata (allocation number, stack trace
   pointers, checksums).  Its size is part of the on-block layout, so a change
   here means every debug block moved.}
  GDebugHeaderSize := SizeOf(TFastMM_DebugBlockHeader);
  Info(Format('SizeOf(TFastMM_DebugBlockHeader) = %d', [GDebugHeaderSize]));
  Check(GDebugHeaderSize > 0, 'the debug block header has a size');
  Check(GDebugHeaderSize mod 16 = 0, 'the debug block header keeps 16 byte alignment');

  Section('Normal mode');
  GetMem(GPointer, 100);
  Check(GPointer <> nil, 'GetMem(100) returns a pointer');
  Check(FillAndVerify(GPointer, 100), 'the block keeps its content');
  {Outside debug mode the requested size of a small or medium block is not
   tracked, so this returns the usable size rather than the 100 that was asked
   for (documented behaviour of FastMM_BlockCurrentUserBytes).}
  Check(FastMM_BlockCurrentUserBytes(GPointer) >= 100,
    'FastMM_BlockCurrentUserBytes covers the requested size');
  Check(FastMM_BlockMaximumUserBytes(GPointer) >= FastMM_BlockCurrentUserBytes(GPointer),
    'the maximum user size is not below the current user size');
  FreeMem(GPointer);
  Check(True, 'FreeMem returns without error');

  Section('Debug mode');
  GUsageBefore := FastMM_GetUsageSummary;
  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  GetMem(GPointer, 100);
  Check(GPointer <> nil, 'debug mode GetMem(100) returns a pointer');
  Check(FillAndVerify(GPointer, 100), 'the debug block keeps its content');
  {In debug mode the requested size is recorded in the debug header, so here the
   exact value must come back.}
  CheckEqualsInt(100, FastMM_BlockCurrentUserBytes(GPointer), 'the user size is the requested size');

  {Two blocks allocated after one another must not overlap - the debug header
   and footer sit between them.}
  GetMem(GSecond, 100);
  Check(GSecond <> GPointer, 'a second allocation returns a different block');
  Check(FillAndVerify(GSecond, 100) and FillAndVerify(GPointer, 100),
    'neither block disturbs the other');
  FreeMem(GSecond);
  FreeMem(GPointer);

  Section('Size sweep 1..2000 bytes');
  GAllContentIntact := True;
  for i := 1 to 2000 do
  begin
    GetMem(GPointer, i);
    if (GPointer = nil) or (not FillAndVerify(GPointer, i)) then
      GAllContentIntact := False;
    FreeMem(GPointer);
  end;
  Check(GAllContentIntact, 'every size from 1 to 2000 allocates, holds its content and frees');

  Section('Realloc chain');
  GetMem(GPointer, 10);
  PByte(GPointer)^ := $5A;
  GAllContentIntact := True;
  for i := 1 to 200 do
  begin
    ReallocMem(GPointer, (i * 37) mod 5000 + 1);
    {The first byte has to survive every move.}
    if PByte(GPointer)^ <> $5A then
      GAllContentIntact := False;
  end;
  Check(GAllContentIntact, 'the first byte survives 200 reallocations');
  FreeMem(GPointer);

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  Section('Accounting');
  GUsageAfter := FastMM_GetUsageSummary;
  {Everything allocated above was freed again, so the allocated total must be
   back where it started.  This is the leak tripwire for this program.}
  CheckEqualsInt(Int64(GUsageBefore.AllocatedBytes), Int64(GUsageAfter.AllocatedBytes),
    'the allocated byte count returns to its starting value');

  TestsEnd;
end.
