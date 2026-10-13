{Erase mode test:  while FastMM_BeginEraseAllocatedBlockContent is in effect
 every block handed out must be filled with $90, and while
 FastMM_BeginEraseFreedBlockContent is in effect every block given back must be
 filled with $80.  That includes the blocks ReallocMem allocates and frees when
 it moves a block, which used to be left out:  the old copy of the data stayed
 in the pool, and the space added by a move kept whatever was there before.

 A freed block is inspected straight after the call that freed it, before
 anything else is allocated, and a neighbouring block keeps its span committed.
 Large blocks are returned to the operating system when they are freed, so the
 freed block checks only use small and medium blocks.  The start and the end of
 a freed block hold free list links and size information, so the fill is
 checked in the middle.

 Optional parameter:  the number of iterations of the ReallocMem data integrity
 check.  Default 20000.}

program FastMM5Test_EraseModes;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

const
  CAllocatedFill = $90;
  CFreedFill = $80;
  CSecretFill = Ord('S');
  CDataFill = Ord('D');
  CStaleFill = Ord('G');

{Returns the number of bytes in the range that hold AValue.}
function CountBytes(APointer: Pointer; AOffset, ACount: Integer; AValue: Byte): Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := AOffset to AOffset + ACount - 1 do
    if PByte(PAnsiChar(APointer) + i)^ = AValue then
      Inc(Result);
end;

{GetMem must fill the whole block, for every size class.}
procedure CheckAllocatedBlocksAreFilled;
const
  CSizes: array[0..2] of Integer = (1000, 20000, 300000);
var
  i, LCount: Integer;
  P: Pointer;
begin
  Section('GetMem while allocated block content is erased');
  FastMM_BeginEraseAllocatedBlockContent;
  for i := Low(CSizes) to High(CSizes) do
  begin
    GetMem(P, CSizes[i]);
    LCount := CountBytes(P, 0, CSizes[i], CAllocatedFill);
    FreeMem(P);
    CheckEqualsInt(CSizes[i], LCount, Format('a %d byte block is filled with $90', [CSizes[i]]));
  end;
  FastMM_EndEraseAllocatedBlockContent;
end;

{FreeMem must fill the block before it is returned to the pool.}
procedure CheckFreedBlocksAreFilled;
const
  CSizes: array[0..1] of Integer = (100, 20000);
var
  i, LCount: Integer;
  P, LKeeper: Pointer;
begin
  Section('FreeMem while freed block content is erased');
  FastMM_BeginEraseFreedBlockContent;
  for i := Low(CSizes) to High(CSizes) do
  begin
    GetMem(P, CSizes[i]);
    GetMem(LKeeper, CSizes[i]);
    FillChar(P^, CSizes[i], CSecretFill);
    FreeMem(P);
    LCount := CountBytes(P, 16, CSizes[i] - 32, CFreedFill);
    FreeMem(LKeeper);
    CheckEqualsInt(CSizes[i] - 32, LCount, Format('a freed %d byte block is filled with $80', [CSizes[i]]));
  end;
  FastMM_EndEraseFreedBlockContent;
end;

{Moves a block of AOldSize bytes to ANewSize bytes with ReallocMem, and checks
 that the old block was erased and the data was kept.}
procedure CheckReallocMemErasesOldBlock(AOldSize, ANewSize: Integer; const ADescription: string);
var
  P, LOld, LKeeper: Pointer;
  LErased, LKept, LKeptExpected: Integer;
  LMoved: Boolean;
begin
  GetMem(P, AOldSize);
  GetMem(LKeeper, AOldSize);
  FillChar(P^, AOldSize, CSecretFill);
  LOld := P;
  ReallocMem(P, ANewSize);
  LMoved := P <> LOld;
  LErased := CountBytes(LOld, 16, AOldSize - 32, CFreedFill);
  LKeptExpected := AOldSize;
  if LKeptExpected > ANewSize then
    LKeptExpected := ANewSize;
  LKept := CountBytes(P, 0, LKeptExpected, CSecretFill);
  FreeMem(P);
  FreeMem(LKeeper);
  Check(LMoved, ADescription + ':  the block is moved');
  CheckEqualsInt(AOldSize - 32, LErased, ADescription + ':  the old block is filled with $80');
  CheckEqualsInt(LKeptExpected, LKept, ADescription + ':  the data is kept');
end;

procedure CheckReallocMemErasesFreedBlocks;
begin
  Section('ReallocMem while freed block content is erased');
  FastMM_BeginEraseFreedBlockContent;
  CheckReallocMemErasesOldBlock(100, 2000, 'small block grown');
  CheckReallocMemErasesOldBlock(20000, 100, 'medium block shrunk to a small block');
  CheckReallocMemErasesOldBlock(20000, 300000, 'medium block grown to a large block');
  FastMM_EndEraseFreedBlockContent;
end;

{Grows a block of AOldSize bytes to ANewSize bytes with ReallocMem, and checks
 that the space that was added is filled and the data was kept.  A block of the
 new size is freed first, so that the added space is likely to contain stale
 data rather than fresh zeroed memory.}
procedure CheckReallocMemFillsAddedSpace(AOldSize, ANewSize: Integer; const ADescription: string);
var
  P, LStale: Pointer;
  LKept, LFilled, LAddedSize: Integer;
begin
  GetMem(LStale, ANewSize);
  FillChar(LStale^, ANewSize, CStaleFill);
  FreeMem(LStale);

  FastMM_BeginEraseAllocatedBlockContent;
  GetMem(P, AOldSize);
  FillChar(P^, AOldSize, CDataFill);
  ReallocMem(P, ANewSize);
  LAddedSize := ANewSize - AOldSize;
  LKept := CountBytes(P, 0, AOldSize, CDataFill);
  LFilled := CountBytes(P, AOldSize, LAddedSize, CAllocatedFill);
  FreeMem(P);
  FastMM_EndEraseAllocatedBlockContent;

  CheckEqualsInt(AOldSize, LKept, ADescription + ':  the data is kept');
  CheckEqualsInt(LAddedSize, LFilled, ADescription + ':  the added space is filled with $90');
end;

procedure CheckReallocMemFillsAllocatedBlocks;
begin
  Section('ReallocMem while allocated block content is erased');
  CheckReallocMemFillsAddedSpace(16, 6000, 'small block grown to a medium block');
  CheckReallocMemFillsAddedSpace(20000, 300000, 'medium block grown to a large block');
end;

{A resize that fits in the block must still be done in place.}
procedure CheckReallocMemInPlace;
var
  P, LOld: Pointer;
  LKept: Integer;
begin
  Section('ReallocMem in place while both erase modes are active');
  FastMM_BeginEraseAllocatedBlockContent;
  FastMM_BeginEraseFreedBlockContent;
  GetMem(P, 20000);
  FillChar(P^, 20000, CDataFill);
  LOld := P;
  ReallocMem(P, 15000);
  LKept := CountBytes(P, 0, 15000, CDataFill);
  Check(P = LOld, 'a medium block shrunk by a quarter stays in place');
  CheckEqualsInt(15000, LKept, 'the data is kept');
  FreeMem(P);
  FastMM_EndEraseFreedBlockContent;
  FastMM_EndEraseAllocatedBlockContent;
end;

{Random reallocations across all size classes, verifying after every call that
 the data up to the smaller of the old and new sizes survived.}
procedure CheckReallocMemDataIntegrity(AIterations: Integer);
const
  CSlots = 64;
var
  LBlocks: array[0..CSlots - 1] of Pointer;
  LSizes, LSeeds: array[0..CSlots - 1] of Integer;
  i, j, LSlot, LNewSize, LCheckSize, LMaximumSize, LMismatches: Integer;
begin
  Section(Format('ReallocMem data integrity, %d iterations, both erase modes active', [AIterations]));
  RandSeed := 12345;
  LMismatches := 0;
  for i := 0 to CSlots - 1 do
  begin
    LBlocks[i] := nil;
    LSizes[i] := 0;
    LSeeds[i] := 0;
  end;

  FastMM_BeginEraseAllocatedBlockContent;
  FastMM_BeginEraseFreedBlockContent;
  for i := 1 to AIterations do
  begin
    LSlot := Random(CSlots);
    case Random(3) of
      0: LMaximumSize := 2600;
      1: LMaximumSize := 260000;
    else
      LMaximumSize := 1000000;
    end;
    LNewSize := 1 + Random(LMaximumSize);

    if LSizes[LSlot] = 0 then
      GetMem(LBlocks[LSlot], LNewSize)
    else
    begin
      ReallocMem(LBlocks[LSlot], LNewSize);
      LCheckSize := LSizes[LSlot];
      if LCheckSize > LNewSize then
        LCheckSize := LNewSize;
      for j := 0 to LCheckSize - 1 do
      begin
        if PByte(PAnsiChar(LBlocks[LSlot]) + j)^ <> Byte(LSeeds[LSlot] + j) then
        begin
          Inc(LMismatches);
          Break;
        end;
      end;
    end;

    LSizes[LSlot] := LNewSize;
    LSeeds[LSlot] := Random(256);
    for j := 0 to LNewSize - 1 do
      PByte(PAnsiChar(LBlocks[LSlot]) + j)^ := Byte(LSeeds[LSlot] + j);
  end;

  for i := 0 to CSlots - 1 do
    FreeMem(LBlocks[i]);
  FastMM_EndEraseFreedBlockContent;
  FastMM_EndEraseAllocatedBlockContent;

  CheckEqualsInt(0, LMismatches, 'no data is lost by ReallocMem');
end;

begin
  TestsBegin('FastMM5 erase modes');

  CheckAllocatedBlocksAreFilled;
  CheckFreedBlocksAreFilled;
  CheckReallocMemErasesFreedBlocks;
  CheckReallocMemFillsAllocatedBlocks;
  CheckReallocMemInPlace;
  CheckReallocMemDataIntegrity(StrToIntDef(ParamStr(1), 20000));

  TestsEnd;
end.
