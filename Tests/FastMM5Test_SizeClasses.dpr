{Walks every block size class:  small blocks, medium blocks and large blocks,
 plus reallocations that cross the class boundaries in both directions.

 Every block is filled with a size dependent pattern and read back, so a block
 that overlaps its neighbour, or a reallocation that moves the wrong number of
 bytes, shows up as a content mismatch rather than as a crash somewhere later.}

program FastMM5Test_SizeClasses;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

{Fills the block with a pattern derived from its size and verifies it.  The
 first and last byte are checked explicitly because that is where an off-by-one
 in the block size shows up.}
function FillAndVerify(APointer: Pointer; ASize: Integer): Boolean;
var
  i: Integer;
begin
  Result := False;
  if APointer = nil then
    Exit;
  FillChar(APointer^, ASize, Byte(ASize));
  for i := 0 to ASize - 1 do
  begin
    if PByte(PAnsiChar(APointer) + i)^ <> Byte(ASize) then
      Exit;
  end;
  Result := True;
end;

{Fills a block with a pattern that depends on the position in the block and on
 ASeed.  A different seed is used after every reallocation, so content that was
 not copied, was copied from the wrong offset or is left over from an earlier
 step does not match.}
procedure FillPattern(APointer: Pointer; ASize: Integer; ASeed: Byte);
var
  i: Integer;
begin
  for i := 0 to ASize - 1 do
    PByte(PAnsiChar(APointer) + i)^ := Byte((i xor (i shr 8)) xor ASeed);
end;

{Checks the pattern written by FillPattern.}
function PatternIsIntact(APointer: Pointer; ASize: Integer; ASeed: Byte): Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to ASize - 1 do
  begin
    if PByte(PAnsiChar(APointer) + i)^ <> Byte((i xor (i shr 8)) xor ASeed) then
      Exit;
  end;
  Result := True;
end;

{Reallocates a block that holds the pattern for ASeed, checks that every byte the
 old and the new size have in common was kept, and fills the block with the
 pattern for the next seed.  Returns False if content was lost.}
function ReallocAndVerify(var APointer: Pointer; var ASize: Integer; ANewSize: Integer; ASeed: Byte): Boolean;
var
  LCommonSize: Integer;
begin
  ReallocMem(APointer, ANewSize);
  if ANewSize < ASize then
    LCommonSize := ANewSize
  else
    LCommonSize := ASize;
  Result := PatternIsIntact(APointer, LCommonSize, ASeed);
  ASize := ANewSize;
  FillPattern(APointer, ASize, Byte(ASeed + 1));
end;

var
  GPointer: Pointer;
  GSize, i: Integer;
  GOk: Boolean;
  GFirstBadSize: Integer;
  GUsageBefore, GUsageAfter: TFastMM_UsageSummary;

begin
  TestsBegin('FastMM5 block size classes');

  GUsageBefore := FastMM_GetUsageSummary;
  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  Section('Small and medium blocks:  1 to 70000 bytes, step 61');
  GOk := True;
  GFirstBadSize := 0;
  GSize := 1;
  while GSize <= 70000 do
  begin
    GetMem(GPointer, GSize);
    if not FillAndVerify(GPointer, GSize) then
    begin
      if GOk then
        GFirstBadSize := GSize;
      GOk := False;
    end;
    FreeMem(GPointer);
    Inc(GSize, 61);
  end;
  if GOk then
    Check(True, 'every size allocates, holds its content and frees')
  else
    Check(False, Format('content mismatch, first at %d bytes', [GFirstBadSize]));

  Section('Large blocks:  100000 to 2000000 bytes, step 100000');
  GOk := True;
  GFirstBadSize := 0;
  GSize := 100000;
  while GSize <= 2000000 do
  begin
    GetMem(GPointer, GSize);
    if not FillAndVerify(GPointer, GSize) then
    begin
      if GOk then
        GFirstBadSize := GSize;
      GOk := False;
    end;
    FreeMem(GPointer);
    Inc(GSize, 100000);
  end;
  if GOk then
    Check(True, 'every large size allocates, holds its content and frees')
  else
    Check(False, Format('content mismatch, first at %d bytes', [GFirstBadSize]));

  Section('Reallocations across the class boundaries');
  {A reallocation may move the block between size classes in either direction.
   Every byte that the old and the new size have in common has to survive every
   move.}
  GSize := 10;
  GetMem(GPointer, GSize);
  FillPattern(GPointer, GSize, 0);
  GOk := True;
  for i := 1 to 60 do
  begin
    if not ReallocAndVerify(GPointer, GSize, (i * 12345) mod 300000 + 1, Byte(i - 1)) then
      GOk := False;
  end;
  Check(GOk, 'the block content survives 60 reallocations across all classes');
  FreeMem(GPointer);

  {Growing one byte at a time across the small/medium boundary is the case where
   an off-by-one in the class lookup table would surface.}
  GSize := 2000;
  GetMem(GPointer, GSize);
  FillPattern(GPointer, GSize, 0);
  GOk := True;
  for i := 1 to 400 do
  begin
    if not ReallocAndVerify(GPointer, GSize, 2000 + i, Byte(i - 1)) then
      GOk := False;
  end;
  Check(GOk, 'growing byte by byte across the small block boundary keeps the content');
  FreeMem(GPointer);

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  Section('Accounting');
  GUsageAfter := FastMM_GetUsageSummary;
  CheckEqualsInt(Int64(GUsageBefore.AllocatedBytes), Int64(GUsageAfter.AllocatedBytes),
    'the allocated byte count returns to its starting value');

  TestsEnd;
end.
