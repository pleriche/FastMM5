{What happens when the size fields of a debug block header are themselves the
 thing that got corrupted?  DebugFooterPtr is derived from UserSize and the
 stack traces from StackTraceEntryCount, so a corrupted size field decides where
 the scan reads.  This program corrupts those fields (and nothing else) and
 reports how the scan reacts:  a clean corruption report, an access violation,
 or silence.

 What makes this safe upstream (verified for issue #102) is the evaluation
 order:  the header checksum is compared before the footer checksum, and since
 FastMM5.pas compiles with complete boolean evaluation off, the footer read is
 short-circuited away as soon as the header does not match - and a corrupted
 size field always invalidates the header checksum.  So this test is really guarding that ordering:  if anyone ever
 reorders those comparisons, or reads the footer before validating the header,
 the cases below turn into access violations.

 Why there is no "small block, freed" case:  a freed debug block sits in the
 debug free queue and is a candidate for the next allocation of that size.  When
 the scan reports the corruption it raises an exception, and raising allocates
 the exception object - which hands out precisely that corrupted block, so the
 corruption is detected again while an exception is already being raised, and
 the process dies before any handler runs.  That is FastMM doing its job;  the
 test simply cannot observe it.  For medium and large blocks the exception
 object is far too small to be given the freed block, so those cases are stable.}

program FastMM5Test_ScanHeaderBounds;

{$APPTYPE CONSOLE}

uses
  FastMM5,
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

function Header(APointer: Pointer): PFastMM_DebugBlockHeader;
begin
  Result := PFastMM_DebugBlockHeader(PAnsiChar(APointer) - SizeOf(TFastMM_DebugBlockHeader));
end;

{Runs the scan and checks the outcome.  Anything other than a proper corruption
 report is a failure:  an access violation means the scan read where the
 corrupted size field pointed it, and silence means the corruption went
 unnoticed.}
procedure CheckScanReportsCorruption(const AWhat: string);
begin
  try
    FastMM_ScanDebugBlocksForCorruption(1000);
    Check(False, AWhat + ':  no error - the corruption was NOT reported');
  except
    on E: EAccessViolation do
      Check(False, AWhat + ':  ACCESS VIOLATION - ' + E.Message);
    on E: Exception do
      Check(True, AWhat + ':  reported (' + E.ClassName + ')');
  end;
end;

procedure TestUserSize(const AWhat: string; ASize: Integer; AFreeFirst: Boolean);
var
  LP: Pointer;
  LOriginal: NativeInt;
begin
  GetMem(LP, ASize);
  if AFreeFirst then
    FreeMem(LP);
  LOriginal := Header(LP).UserSize;
  {A plausible corruption:  something overran the previous block and wrote over
   the size field of this one.  Everything else in the header is untouched.}
  Header(LP).UserSize := $30000000;
  CheckScanReportsCorruption('UserSize, ' + AWhat);
  Header(LP).UserSize := LOriginal;
  if not AFreeFirst then
    FreeMem(LP);
end;

procedure TestStackTraceEntryCount(const AWhat: string; ASize: Integer; AFreeFirst: Boolean);
var
  LP: Pointer;
  LOriginal: Byte;
begin
  GetMem(LP, ASize);
  if AFreeFirst then
    FreeMem(LP);
  LOriginal := Header(LP).StackTraceEntryCount;
  Header(LP).StackTraceEntryCount := 255;
  CheckScanReportsCorruption('StackTraceEntryCount, ' + AWhat);
  Header(LP).StackTraceEntryCount := LOriginal;
  if not AFreeFirst then
    FreeMem(LP);
end;

begin
  TestsBegin('FastMM5 corrupted size fields in the debug block header');

  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');

  Section('UserSize overwritten with $30000000');
  TestUserSize('small block, allocated', 100, False);
  TestUserSize('medium block, allocated', 50000, False);
  TestUserSize('medium block, freed', 50000, True);
  TestUserSize('large block, allocated', 300000, False);
  TestUserSize('large block, freed', 300000, True);

  Section('StackTraceEntryCount overwritten with 255');
  TestStackTraceEntryCount('small block, allocated', 100, False);
  TestStackTraceEntryCount('medium block, allocated', 50000, False);
  TestStackTraceEntryCount('large block, freed', 300000, True);

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');

  TestsEnd;
end.
