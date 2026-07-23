{Does FastMM_ScanDebugBlocksForCorruption still detect a corrupted debug block?

 For each block size class the program allocates a debug block, corrupts one
 field, runs the scan and checks that the scan reported it.  The corruption is
 repaired again afterwards and a clean scan confirms that the heap is back to
 normal, so one run covers every case.

 Regression test for issue #102:  between cad1f04 and a9526b2 the walk only
 reported debug info for a small block whose header AND footer checksums were
 already valid, so the scan could not see the very state it looks for.  The
 three small block cases below failed silently in that window while medium and
 large kept working - which is why a corruption test that happens to use a large
 block proves nothing about the small block path.}

program FastMM5Test_ScanCoverage;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

function Header(APointer: Pointer): PFastMM_DebugBlockHeader;
begin
  Result := PFastMM_DebugBlockHeader(PAnsiChar(APointer) - SizeOf(TFastMM_DebugBlockHeader));
end;

{Runs the scan.  True means it reported a corruption.}
function ScanDetects: Boolean;
begin
  try
    FastMM_ScanDebugBlocksForCorruption(1000);
    Result := False;
  except
    Result := True;
  end;
end;

{Corrupts the header checksum of an allocated debug block, scans, and repairs.}
procedure TestHeaderCorruption(const AWhat: string; ASize: Integer);
var
  LPointer: Pointer;
  LOriginal: Cardinal;
  LDetected: Boolean;
begin
  GetMem(LPointer, ASize);
  try
    LOriginal := Header(LPointer).HeaderCheckSum;
    Header(LPointer).HeaderCheckSum := LOriginal xor $DEADBEEF;
    LDetected := ScanDetects;
    Header(LPointer).HeaderCheckSum := LOriginal;
    Check(LDetected, 'corrupted header checksum is detected:  ' + AWhat);
    Check(not ScanDetects, 'the heap is clean again after repairing the header:  ' + AWhat);
  finally
    FreeMem(LPointer);
  end;
end;

{Overwrites the first byte after the user data, which lands in the debug footer,
 i.e. what a one byte buffer overrun does.}
procedure TestFooterCorruption(const AWhat: string; ASize: Integer);
var
  LPointer: Pointer;
  LOriginal: Cardinal;
  LDetected: Boolean;
begin
  GetMem(LPointer, ASize);
  try
    LOriginal := Header(LPointer).DebugFooterPtr^;
    PByte(PAnsiChar(LPointer) + ASize)^ := PByte(PAnsiChar(LPointer) + ASize)^ xor $FF;
    LDetected := ScanDetects;
    Header(LPointer).DebugFooterPtr^ := LOriginal;
    Check(LDetected, 'overrun into the debug footer is detected:  ' + AWhat);
  finally
    FreeMem(LPointer);
  end;
end;

{Writes into a block after it was freed:  the fill pattern of the freed block is
 destroyed while its header and footer stay intact.}
procedure TestUseAfterFree(const AWhat: string; ASize: Integer);
var
  LPointer: Pointer;
  LOriginal: Byte;
  LDetected: Boolean;
begin
  GetMem(LPointer, ASize);
  FreeMem(LPointer);
  {The block is now in the debug free queue and still committed.}
  LOriginal := PByte(PAnsiChar(LPointer) + ASize - 1)^;
  PByte(PAnsiChar(LPointer) + ASize - 1)^ := LOriginal xor $FF;
  LDetected := ScanDetects;
  PByte(PAnsiChar(LPointer) + ASize - 1)^ := LOriginal;
  Check(LDetected, 'write into a freed block is detected:  ' + AWhat);
end;

begin
  TestsBegin('FastMM5 corruption scan coverage (issue #102)');

  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  Section('Header checksum corrupted (allocated block)');
  TestHeaderCorruption('small block, 100 bytes', 100);
  TestHeaderCorruption('small block, 2000 bytes', 2000);
  TestHeaderCorruption('medium block, 50000 bytes', 50000);
  TestHeaderCorruption('large block, 300000 bytes', 300000);

  Section('Buffer overrun into the debug footer (allocated block)');
  TestFooterCorruption('small block, 100 bytes', 100);
  TestFooterCorruption('medium block, 50000 bytes', 50000);
  TestFooterCorruption('large block, 300000 bytes', 300000);

  Section('Write after free (fill pattern destroyed, header intact)');
  TestUseAfterFree('small block, 100 bytes', 100);
  TestUseAfterFree('medium block, 50000 bytes', 50000);
  TestUseAfterFree('large block, 300000 bytes', 300000);

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  TestsEnd;
end.
