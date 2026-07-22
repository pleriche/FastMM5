{Demo and self-test for FastMM_SamplingProfiler:  runs a grow-then-shrink workload while a background sampler writes
CSV time series, then verifies the collected samples show the expected rise and fall.  Exit code 0 = all checks
passed.}
program SamplingProfilerDemo;

{$APPTYPE CONSOLE}

uses
  FastMM5 in '..\..\..\FastMM5.pas',
  Classes,
  {$if CompilerVersion >= 23}System.SysUtils, Winapi.Windows,{$else}SysUtils, Windows,{$ifend}
  FastMM_SamplingProfiler in '..\..\..\Profiling\FastMM_SamplingProfiler.pas';

type
  TBlob = class(TObject)
  private
    FData: array[0..4095] of Byte;
  end;

const
  CBlobCount = 4000;

var
  GTestsPassed, GTestsFailed: Integer;
  {Samples collected by the profiler callback.}
  GCollected: array of TFastMM_MemorySample;
  GCollectedCount: Integer;
  GCollectLock: TRTLCriticalSection;

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

{Runs on the sampling thread.}
procedure CollectCallback(const ASample: TFastMM_MemorySample; AUserData: Pointer);
begin
  EnterCriticalSection(GCollectLock);
  try
    if GCollectedCount >= Length(GCollected) then
      SetLength(GCollected, Length(GCollected) * 2 + 16);
    GCollected[GCollectedCount] := ASample;
    Inc(GCollectedCount);
  finally
    LeaveCriticalSection(GCollectLock);
  end;
end;

function CountFileLines(const AFileName: string): Integer;
var
  LLines: TStringList;
begin
  Result := 0;
  if not FileExists(AFileName) then
    Exit;
  LLines := TStringList.Create;
  try
    LLines.LoadFromFile(AFileName);
    Result := LLines.Count;
  finally
    LLines.Free;
  end;
end;

var
  GProfiler: TFastMM_SamplingProfiler;
  GBlobs: array of TBlob;
  GSummaryFile, GDetailFile: string;
  i: Integer;
  GPeakAllocated, GFinalAllocated, GFirstAllocated: Int64;
  GElapsedMonotonic: Boolean;
  GManualSample, GStandaloneSample: TFastMM_MemorySample;
  GSummaryLineCount: Integer;

begin
  GTestsPassed := 0;
  GTestsFailed := 0;
  InitializeCriticalSection(GCollectLock);

  WriteLn('FastMM_SamplingProfiler self test');
  WriteLn;

  GSummaryFile := ExtractFilePath(ParamStr(0)) + 'SamplingDemo_Summary.csv';
  GDetailFile := ExtractFilePath(ParamStr(0)) + 'SamplingDemo_Detail.csv';

  {--- Phase 1:  standalone one-shot sample ---}
  WriteLn('Phase 1:  standalone FastMM_TakeMemorySample');
  GStandaloneSample := FastMM_TakeMemorySample;
  Check(GStandaloneSample.ReservedBytes >= GStandaloneSample.AllocatedBytes,
    'reserved >= allocated in standalone sample');
  Check((GStandaloneSample.EfficiencyPercentage >= 0) and (GStandaloneSample.EfficiencyPercentage <= 100),
    'efficiency within 0..100 in standalone sample');
  Check(GStandaloneSample.AllocatedBytes > 0, 'allocated bytes > 0 in standalone sample');

  {--- Phase 2:  timed sampling across a grow-then-shrink workload ---}
  WriteLn;
  WriteLn('Phase 2:  background sampling of a grow-then-shrink workload');
  GProfiler := TFastMM_SamplingProfiler.Create;
  try
    GProfiler.SummaryFileName := GSummaryFile;
    GProfiler.DetailFileName := GDetailFile;
    GProfiler.IntervalMilliseconds := 25;
    GProfiler.Callback := CollectCallback;
    GProfiler.Start;
    Check(GProfiler.Running, 'profiler reports running after Start');

    {Grow:  allocate blobs in batches with small pauses so the sampler catches the ramp.}
    SetLength(GBlobs, CBlobCount);
    for i := 0 to CBlobCount - 1 do
    begin
      GBlobs[i] := TBlob.Create;
      if (i mod 500) = 0 then
        Sleep(15);
    end;
    Sleep(80);

    {Shrink:  free most of the blobs.}
    for i := 0 to CBlobCount - 1 do
    begin
      GBlobs[i].Free;
      GBlobs[i] := nil;
      if (i mod 500) = 0 then
        Sleep(15);
    end;
    Sleep(80);

    {Manual sample while running (must not touch the timer-owned file, but must still return valid data + fire the
    callback).}
    GManualSample := GProfiler.SampleNow;
    Check(GManualSample.ReservedBytes >= GManualSample.AllocatedBytes, 'manual sample reserved >= allocated');

    GProfiler.Stop;
    Check(not GProfiler.Running, 'profiler reports stopped after Stop');
  finally
    GProfiler.Free;
  end;

  {--- Phase 3:  verify the collected series ---}
  WriteLn;
  WriteLn('Phase 3:  verify collected series (', GCollectedCount, ' samples)');
  Check(GCollectedCount >= 4, 'at least 4 samples were collected');

  if GCollectedCount > 0 then
  begin
    GFirstAllocated := GCollected[0].AllocatedBytes;
    GPeakAllocated := 0;
    GElapsedMonotonic := True;
    for i := 0 to GCollectedCount - 1 do
    begin
      if GCollected[i].AllocatedBytes > GPeakAllocated then
        GPeakAllocated := GCollected[i].AllocatedBytes;
      if (i > 0) and (GCollected[i].ElapsedMilliseconds < GCollected[i - 1].ElapsedMilliseconds) then
        GElapsedMonotonic := False;
    end;
    {The final timed sample is the one before the manual SampleNow;  use the last collected entry.}
    GFinalAllocated := GCollected[GCollectedCount - 1].AllocatedBytes;

    Check(GPeakAllocated >= GFirstAllocated + Int64(CBlobCount) * 4096,
      'peak allocated grew by at least the blob payload');
    Check(GFinalAllocated < GPeakAllocated, 'final allocated fell below the peak (shrink observed)');
    Check(GElapsedMonotonic, 'elapsed_ms is non-decreasing across samples');
    Check(GCollected[0].SampleIndex = 0, 'first sample has index 0');
  end;

  {--- Phase 4:  verify the CSV files ---}
  WriteLn;
  WriteLn('Phase 4:  verify CSV output');
  GSummaryLineCount := CountFileLines(GSummaryFile);
  {The callback fires for every sample, but the one manual SampleNow taken while the timer was running deliberately
  does NOT write to the timer-owned file.  So the file has: 1 header + (collected - 1 manual) timer rows.}
  Check(GSummaryLineCount >= GCollectedCount,
    Format('summary CSV has header + >= %d timed rows (got %d lines, %d callbacks)',
      [GCollectedCount - 1, GSummaryLineCount, GCollectedCount]));
  Check(CountFileLines(GDetailFile) > 1, 'detail CSV has header + rows');
  WriteLn('  Summary CSV: ', GSummaryFile);
  WriteLn('  Detail  CSV: ', GDetailFile);

  DeleteCriticalSection(GCollectLock);

  WriteLn;
  WriteLn(Format('Result:  %d passed, %d failed', [GTestsPassed, GTestsFailed]));
  if GTestsFailed > 0 then
    ExitCode := 1;
end.
