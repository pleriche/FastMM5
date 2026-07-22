{Demo and self-test for FastMM_SnapshotDiff:  allocates known objects/strings/raw blocks between snapshots and
verifies that the diff reports the expected deltas.  Exit code 0 = all checks passed.}
program SnapshotDiffDemo;

{$APPTYPE CONSOLE}

uses
  FastMM5 in '..\..\..\FastMM5.pas',
  {$if CompilerVersion >= 23}System.SysUtils,{$else}SysUtils,{$ifend}
  FastMM_SnapshotDiff in '..\..\..\Profiling\FastMM_SnapshotDiff.pas';

type
  TDemoWidget = class(TObject)
  private
    FPayload: array[0..99] of Byte;
    FIdentifier: Integer;
  public
    constructor Create(AIdentifier: Integer);
  end;

  TDemoGadget = class(TObject)
  private
    FCaption: string;
  public
    constructor Create(const ACaption: string);
  end;

constructor TDemoWidget.Create(AIdentifier: Integer);
begin
  inherited Create;
  FIdentifier := AIdentifier;
  FillChar(FPayload, SizeOf(FPayload), AIdentifier and $FF);
end;

constructor TDemoGadget.Create(const ACaption: string);
begin
  inherited Create;
  FCaption := ACaption;
end;

const
  CWidgetCount = 1000;
  CGadgetCount = 250;
  CStringCount = 500;
  CRawBlockCount = 5;
  CRawBlockSize = 300 * 1024;
  CDebugWidgetCount = 100;

var
  GTestsPassed, GTestsFailed: Integer;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  if ACondition then
  begin
    Inc(GTestsPassed);
    WriteLn('  PASS  ', ADescription);
  end
  else
  begin
    Inc(GTestsFailed);
    WriteLn('  FAIL  ', ADescription);
  end;
end;

function FindDiffEntry(const ADiff: TFastMM_SnapshotDiff; const AName: string;
  out AEntry: TFastMM_SnapshotDiffEntry): Boolean;
var
  i: Integer;
begin
  {Zero the result so a failed lookup does not leave stale data from a previous call in the caller's variable.}
  AEntry.Name := AName;
  AEntry.CountA := 0;
  AEntry.CountB := 0;
  AEntry.DeltaCount := 0;
  AEntry.BytesA := 0;
  AEntry.BytesB := 0;
  AEntry.DeltaBytes := 0;

  for i := 0 to Length(ADiff.Entries) - 1 do
  begin
    if ADiff.Entries[i].Name = AName then
    begin
      AEntry := ADiff.Entries[i];
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

function NativeStringBucketName: string;
begin
  {The 'string' type maps to UnicodeString from Delphi 2009 and AnsiString before.}
  if SizeOf(Char) = 2 then
    Result := 'UnicodeString'
  else
    Result := 'AnsiString';
end;

var
  GSnapshotA, GSnapshotB, GSnapshotC, GSnapshotDebugA, GSnapshotDebugB: TFastMM_HeapSnapshot;
  GDiff, GDiffShrink, GDiffDebug: TFastMM_SnapshotDiff;
  GEntry: TFastMM_SnapshotDiffEntry;
  GWidgets: array of TDemoWidget;
  GGadgets: array of TDemoGadget;
  GStrings: array of string;
  GRawBlocks: array of Pointer;
  GDebugWidgets: array of TDemoWidget;
  i: Integer;
  GDiffFilename: string;

begin
  GTestsPassed := 0;
  GTestsFailed := 0;

  WriteLn('FastMM_SnapshotDiff self test');
  WriteLn;

  {--- Phase 1:  growth diff ---}
  WriteLn('Phase 1:  allocate known content between two snapshots');
  Check(FastMM_CaptureHeapSnapshot(GSnapshotA), 'snapshot A captured completely');

  SetLength(GWidgets, CWidgetCount);
  for i := 0 to CWidgetCount - 1 do
    GWidgets[i] := TDemoWidget.Create(i);

  SetLength(GGadgets, CGadgetCount);
  for i := 0 to CGadgetCount - 1 do
    GGadgets[i] := TDemoGadget.Create('Gadget caption #' + IntToStr(i));

  SetLength(GStrings, CStringCount);
  for i := 0 to CStringCount - 1 do
    GStrings[i] := StringOfChar('A', 64 + i);

  SetLength(GRawBlocks, CRawBlockCount);
  for i := 0 to CRawBlockCount - 1 do
  begin
    GetMem(GRawBlocks[i], CRawBlockSize);
    {Fill pattern $CC:  pointer aligned and > 65535, so it exercises the hash table path but resolves to unknown.}
    FillChar(GRawBlocks[i]^, CRawBlockSize, $CC);
  end;

  Check(FastMM_CaptureHeapSnapshot(GSnapshotB), 'snapshot B captured completely');
  FastMM_DiffHeapSnapshots(GSnapshotA, GSnapshotB, GDiff);

  Check(FindDiffEntry(GDiff, 'TDemoWidget', GEntry), 'TDemoWidget appears in diff A->B');
  Check(GEntry.DeltaCount = CWidgetCount, Format('TDemoWidget delta count = %d (got %d)',
    [CWidgetCount, GEntry.DeltaCount]));
  Check(GEntry.DeltaBytes >= CWidgetCount * TDemoWidget.InstanceSize,
    'TDemoWidget delta bytes >= count * instance size');

  Check(FindDiffEntry(GDiff, 'TDemoGadget', GEntry), 'TDemoGadget appears in diff A->B');
  Check(GEntry.DeltaCount = CGadgetCount, Format('TDemoGadget delta count = %d (got %d)',
    [CGadgetCount, GEntry.DeltaCount]));

  Check(FindDiffEntry(GDiff, NativeStringBucketName, GEntry),
    NativeStringBucketName + ' bucket appears in diff A->B');
  Check(GEntry.DeltaCount >= CStringCount, Format('%s delta count >= %d (got %d)',
    [NativeStringBucketName, CStringCount, GEntry.DeltaCount]));

  Check(FindDiffEntry(GDiff, '(unknown)', GEntry), '(unknown) bucket appears in diff A->B');
  Check(GEntry.DeltaBytes >= CRawBlockCount * CRawBlockSize, 'raw block bytes counted under (unknown)');

  Check(GDiff.TotalBlockCountB - GDiff.TotalBlockCountA > 0, 'total block count grew');
  Check(not GDiff.Incomplete, 'diff A->B not flagged incomplete');

  {--- Phase 2:  shrink diff ---}
  WriteLn;
  WriteLn('Phase 2:  free half of the widgets, diff again');
  for i := 0 to (CWidgetCount div 2) - 1 do
  begin
    GWidgets[i].Free;
    GWidgets[i] := nil;
  end;

  Check(FastMM_CaptureHeapSnapshot(GSnapshotC), 'snapshot C captured completely');
  FastMM_DiffHeapSnapshots(GSnapshotB, GSnapshotC, GDiffShrink);

  Check(FindDiffEntry(GDiffShrink, 'TDemoWidget', GEntry), 'TDemoWidget appears in diff B->C');
  Check(GEntry.DeltaCount = -(CWidgetCount div 2), Format('TDemoWidget delta count = %d (got %d)',
    [-(CWidgetCount div 2), GEntry.DeltaCount]));
  Check(GEntry.DeltaBytes < 0, 'TDemoWidget delta bytes negative');

  {--- Phase 3:  debug mode ---}
  WriteLn;
  WriteLn('Phase 3:  snapshots inside runtime debug mode');
  if FastMM_EnterDebugMode then
  begin
    try
      Check(FastMM_CaptureHeapSnapshot(GSnapshotDebugA), 'debug mode snapshot A captured completely');

      SetLength(GDebugWidgets, CDebugWidgetCount);
      for i := 0 to CDebugWidgetCount - 1 do
        GDebugWidgets[i] := TDemoWidget.Create(i);

      Check(FastMM_CaptureHeapSnapshot(GSnapshotDebugB), 'debug mode snapshot B captured completely');
      FastMM_DiffHeapSnapshots(GSnapshotDebugA, GSnapshotDebugB, GDiffDebug);

      Check(FindDiffEntry(GDiffDebug, 'TDemoWidget', GEntry), 'TDemoWidget appears in debug mode diff');
      Check(GEntry.DeltaCount = CDebugWidgetCount, Format('TDemoWidget delta count in debug mode = %d (got %d)',
        [CDebugWidgetCount, GEntry.DeltaCount]));

      for i := 0 to CDebugWidgetCount - 1 do
        GDebugWidgets[i].Free;
      GDebugWidgets := nil;
    finally
      FastMM_ExitDebugMode;
    end;
  end
  else
    Check(False, 'FastMM_EnterDebugMode succeeded');

  {--- Phase 4:  report output ---}
  WriteLn;
  WriteLn('Phase 4:  report rendering');
  GDiffFilename := ExtractFilePath(ParamStr(0)) + 'SnapshotDiffDemo_Diff.txt';
  Check(FastMM_SaveSnapshotDiffToFile(GDiff, GDiffFilename), 'diff report written to ' + GDiffFilename);

  WriteLn;
  WriteLn('--- Diff A->B (top 15 entries) ---');
  WriteLn(FastMM_SnapshotDiffToText(GDiff, 15));

  {--- Cleanup so the shutdown leak check stays green ---}
  for i := CWidgetCount div 2 to CWidgetCount - 1 do
    GWidgets[i].Free;
  GWidgets := nil;
  for i := 0 to CGadgetCount - 1 do
    GGadgets[i].Free;
  GGadgets := nil;
  GStrings := nil;
  for i := 0 to CRawBlockCount - 1 do
    FreeMem(GRawBlocks[i]);
  GRawBlocks := nil;

  WriteLn(Format('Result:  %d passed, %d failed', [GTestsPassed, GTestsFailed]));
  if GTestsFailed > 0 then
    ExitCode := 1;
end.
