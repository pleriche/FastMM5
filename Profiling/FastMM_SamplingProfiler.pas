{

FastMM_SamplingProfiler - periodic memory usage sampling for FastMM5

Description:
  Runs a low priority background thread that periodically samples the FastMM5 memory manager state and appends the
  result as a row to a CSV file.  Over the run of an application this produces time series for:
    - the total memory footprint (committed + reserved) of the process heap,
    - the allocated / reserved / overhead byte counts,
    - the memory manager efficiency (allocated as a percentage of reserved),
    - the small / medium / large block breakdown.
  These can be plotted directly (Excel, gnuplot, ...) to reveal memory growth and fragmentation trends that a single
  point-in-time snapshot cannot show.

  Optionally a second, detailed CSV can be written with one row per small block size class per sample, so per-bin
  fragmentation (reserved address space versus bytes actually in use) can be tracked over time.

  A callback may also be registered to receive every sample, e.g. to feed a live dashboard instead of (or in addition
  to) the CSV output.

Usage:
  var
    LProfiler: TFastMM_SamplingProfiler;
  begin
    LProfiler := TFastMM_SamplingProfiler.Create;
    LProfiler.SummaryFileName := 'MemUsage.csv';
    LProfiler.DetailFileName := 'MemUsageDetail.csv';  (optional)
    LProfiler.IntervalMilliseconds := 1000;
    LProfiler.Start;
    ...run the application...
    LProfiler.Stop;
    LProfiler.Free;
  end;

  // A one-off sample (e.g. at a specific application event) can be taken at any time, whether or not the timer is running:
    LProfiler.SampleNow;

Notes:
  - Each sample calls FastMM_GetMemoryManagerState, which walks the entire memory pool and briefly locks each arena.
    Keep the interval well above the walk duration;  for large heaps a walk can take a few milliseconds.  Intervals
    below ~100 ms are only advisable for short diagnostic runs.
  - The sampling thread itself allocates a little memory while formatting and writing CSV rows.  This shows up as a
    small, roughly constant overhead in the samples and does not affect the trends.
  - Allocated / reserved / overhead / efficiency are derived from the single state walk and use the same UsableSize
    based accounting as FastMM_GetUsageSummary, so their values match (a second walk is avoided).
  - Numbers are written with a '.' decimal separator regardless of the system locale, so the CSV is portable.
  - Compatible with Delphi 7 and later (no generics, no anonymous methods, no Exit(Value)).

Version history:
  1.0 (17 July 2026): Initial implementation.
}

unit FastMM_SamplingProfiler;

{$ifdef FPC}
  {Free Pascal does not predefine Delphi's CompilerVersion constant that the version switches below rely on, so it is
  supplied as a macro (FPC evaluates the IF CompilerVersion switches correctly against a macro).  Version 22 selects
  the behaviour FPC wants:  no unit scope names, and inline enabled.}
  {$mode delphi}
  {$macro on}
  {$define CompilerVersion:=22}
{$endif}

interface

{$RangeChecks Off}
{$BoolEval Off}
{$OverflowChecks Off}
{$Optimization On}

uses
  {$if CompilerVersion >= 23}Winapi.Windows, System.SysUtils, System.Classes, System.SyncObjs;
  {$else}Windows, SysUtils, Classes, SyncObjs;{$ifend}

type
  {A single sample of the memory manager state.  All byte counts use the same UsableSize based accounting as
  FastMM_GetUsageSummary.}
  TFastMM_MemorySample = record
    {A monotonically increasing index, starting at 0 for the first sample of a profiler run.}
    SampleIndex: Integer;
    {The wall clock time at which the sample was taken.}
    WallClock: TDateTime;
    {Milliseconds elapsed since the profiler was started (or since the first manual SampleNow if the timer was never
    started).}
    ElapsedMilliseconds: Cardinal;
    {The total address space (committed + reserved) currently used by FastMM, as reported by
    FastMM_GetCurrentMemoryUsage.}
    MemoryManagerUsageBytes: Int64;
    {The number of bytes currently allocated to the application.}
    AllocatedBytes: Int64;
    {The total address space reserved by the block spans (allocated and free).}
    ReservedBytes: Int64;
    {ReservedBytes - AllocatedBytes:  address space used by management structures, internal fragmentation and freed
    but not yet released blocks.}
    OverheadBytes: Int64;
    {100 * AllocatedBytes / ReservedBytes, or 100 if ReservedBytes is 0.}
    EfficiencyPercentage: Double;
    {Small block totals (summed over all size classes).}
    SmallBlockAllocatedBytes: Int64;
    SmallBlockReservedBytes: Int64;
    SmallBlockCount: Int64;
    {Medium block totals.}
    MediumBlockAllocatedBytes: Int64;
    MediumBlockReservedBytes: Int64;
    MediumBlockCount: Int64;
    {Large block totals.}
    LargeBlockAllocatedBytes: Int64;
    LargeBlockReservedBytes: Int64;
    LargeBlockCount: Int64;
    {Cumulative arena lock contention counts (since program start) at the moment of the sample.  Plotting these over
    time shows the contention rate (the slope) alongside the memory trends;  a rising slope means the allocator is
    increasingly starved of unlocked arenas.}
    SmallBlockContentionCount: Int64;
    MediumBlockContentionCount: Int64;
    LargeBlockContentionCount: Int64;
  end;

  {A callback invoked for every sample.  It runs on the sampling thread, so it must be thread safe and must not block
  for long.  AUserData is the value assigned to the profiler's CallbackUserData property.}
  TFastMM_SampleCallback = procedure(const ASample: TFastMM_MemorySample; AUserData: Pointer);

  TFastMM_SamplingProfiler = class(TObject)
  private
    FThread: TThread;
    FStopEvent: TEvent;
    FLock: TRTLCriticalSection;

    FIntervalMilliseconds: Cardinal;
    FSummaryFileName: string;
    FDetailFileName: string;
    FLockTimeoutMilliseconds: Cardinal;
    FCallback: TFastMM_SampleCallback;
    FCallbackUserData: Pointer;

    FRunning: Boolean;
    FStartTickCount: Cardinal;
    FSampleIndex: Integer;
    FStartTickValid: Boolean;

    FSummaryHandle: THandle;
    FDetailHandle: THandle;

    procedure SetIntervalMilliseconds(AValue: Cardinal);
    function GetRunning: Boolean;

    procedure OpenOutputFiles;
    procedure CloseOutputFiles;
    procedure WriteSummaryHeader;
    procedure WriteDetailHeader;
    {Takes a sample and writes it to the open files and/or the callback.  Runs on the sampling thread.}
    procedure DoSample;
  public
    constructor Create;
    destructor Destroy; override;

    {Starts periodic sampling.  Has no effect if already running.}
    procedure Start;
    {Stops periodic sampling and closes the output files.  Blocks until the sampling thread has stopped.  Has no
    effect if not running.}
    procedure Stop;

    {Takes a single sample immediately, independently of the timer.  Thread safe:  may be called whether or not the
    timer is running.  If the timer is not running and no output file is open, a temporary file handle is opened for
    the SummaryFileName (append) for the duration of the call.  Returns the sample that was taken.}
    function SampleNow: TFastMM_MemorySample;

    {True while the sampling thread is running.}
    property Running: Boolean read GetRunning;

    {The sampling interval in milliseconds.  May be changed while running;  the new interval takes effect after the
    current wait completes.  Default 1000.}
    property IntervalMilliseconds: Cardinal read FIntervalMilliseconds write SetIntervalMilliseconds;
    {The CSV file that receives one summary row per sample.  Must be set before Start.}
    property SummaryFileName: string read FSummaryFileName write FSummaryFileName;
    {Optional CSV file that receives one row per small block size class per sample.  Leave empty to disable.}
    property DetailFileName: string read FDetailFileName write FDetailFileName;
    {The maximum time in milliseconds to wait for an arena lock during a sample before skipping the arena.  Default
    50.}
    property LockTimeoutMilliseconds: Cardinal read FLockTimeoutMilliseconds write FLockTimeoutMilliseconds;
    {An optional callback invoked for every sample (on the sampling thread).}
    property Callback: TFastMM_SampleCallback read FCallback write FCallback;
    property CallbackUserData: Pointer read FCallbackUserData write FCallbackUserData;
  end;

{Takes a single memory manager sample without a profiler instance.  ElapsedMilliseconds is set to 0 and SampleIndex to
0.  Useful for ad-hoc measurements.}
function FastMM_TakeMemorySample(ALockTimeoutMilliseconds: Cardinal = 50): TFastMM_MemorySample;

implementation

uses
  FastMM5;

{--------------------------------------------------------}
{---------------------Sampling core----------------------}
{--------------------------------------------------------}

{Fills a sample from a memory manager state.  Does not set SampleIndex / WallClock / ElapsedMilliseconds /
MemoryManagerUsageBytes - those are filled by the caller.}
procedure PopulateSampleFromState(const AState: TFastMM_MemoryManagerState; var ASample: TFastMM_MemorySample);
var
  i: Integer;
begin
  ASample.SmallBlockAllocatedBytes := 0;
  ASample.SmallBlockReservedBytes := 0;
  ASample.SmallBlockCount := 0;

  for i := 0 to Integer(AState.SmallBlockTypeCount) - 1 do
  begin
    Inc(ASample.SmallBlockCount, Int64(AState.SmallBlockTypeStates[i].AllocatedBlockCount));
    Inc(ASample.SmallBlockAllocatedBytes,
      Int64(AState.SmallBlockTypeStates[i].AllocatedBlockCount) * AState.SmallBlockTypeStates[i].UseableBlockSize);
    Inc(ASample.SmallBlockReservedBytes, Int64(AState.SmallBlockTypeStates[i].ReservedAddressSpace));
  end;

  ASample.MediumBlockCount := Int64(AState.AllocatedMediumBlockCount);
  ASample.MediumBlockAllocatedBytes := Int64(AState.TotalAllocatedMediumBlockSize);
  ASample.MediumBlockReservedBytes := Int64(AState.ReservedMediumBlockAddressSpace);

  ASample.LargeBlockCount := Int64(AState.AllocatedLargeBlockCount);
  ASample.LargeBlockAllocatedBytes := Int64(AState.TotalAllocatedLargeBlockSize);
  ASample.LargeBlockReservedBytes := Int64(AState.ReservedLargeBlockAddressSpace);

  ASample.AllocatedBytes := ASample.SmallBlockAllocatedBytes + ASample.MediumBlockAllocatedBytes
    + ASample.LargeBlockAllocatedBytes;
  ASample.ReservedBytes := ASample.SmallBlockReservedBytes + ASample.MediumBlockReservedBytes
    + ASample.LargeBlockReservedBytes;

  {Reserved should always be >= allocated;  guard against a transient walk race producing the opposite.}
  if ASample.ReservedBytes >= ASample.AllocatedBytes then
    ASample.OverheadBytes := ASample.ReservedBytes - ASample.AllocatedBytes
  else
    ASample.OverheadBytes := 0;

  if ASample.ReservedBytes > 0 then
    ASample.EfficiencyPercentage := 100.0 * ASample.AllocatedBytes / ASample.ReservedBytes
  else
    ASample.EfficiencyPercentage := 100.0;

  {The arena lock contention counters are independent of the block state walk;  read them here so every sample the
  profiler produces carries them.}
  ASample.SmallBlockContentionCount := Int64(FastMM_SmallBlockThreadContentionCount);
  ASample.MediumBlockContentionCount := Int64(FastMM_MediumBlockThreadContentionCount);
  ASample.LargeBlockContentionCount := Int64(FastMM_LargeBlockThreadContentionCount);
end;

function FastMM_TakeMemorySample(ALockTimeoutMilliseconds: Cardinal): TFastMM_MemorySample;
var
  LState: TFastMM_MemoryManagerState;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.WallClock := Now;
  Result.MemoryManagerUsageBytes := Int64(FastMM_GetCurrentMemoryUsage);
  FastMM_GetMemoryManagerState(LState, ALockTimeoutMilliseconds);
  PopulateSampleFromState(LState, Result);
end;

{--------------------------------------------------------}
{------------------Number/CSV formatting-----------------}
{--------------------------------------------------------}

{Formats a non-negative Double with a fixed number of decimals and a '.' separator, independent of the locale.}
function FloatToCsv(AValue: Double; ADecimals: Integer): string;
var
  LScale: Int64;
  LScaled, LIntegerPart, LFractionPart: Int64;
  LFraction: string;
  i: Integer;
begin
  LScale := 1;
  for i := 1 to ADecimals do
    LScale := LScale * 10;

  {Round to the requested number of decimals.}
  LScaled := Round(AValue * LScale);
  if LScaled < 0 then
    LScaled := 0;

  LIntegerPart := LScaled div LScale;
  LFractionPart := LScaled mod LScale;

  LFraction := IntToStr(LFractionPart);
  {Left pad the fraction with zeroes.}
  while Length(LFraction) < ADecimals do
    LFraction := '0' + LFraction;

  Result := IntToStr(LIntegerPart) + '.' + LFraction;
end;

function TimestampToCsv(ATimestamp: TDateTime): string;
begin
  Result := FormatDateTime('yyyy"-"mm"-"dd" "hh":"nn":"ss"."zzz', ATimestamp);
end;

{Writes an AnsiString to an open file handle.  Returns False on a short write.}
function WriteStringToHandle(AHandle: THandle; const AText: AnsiString): Boolean;
begin
  if AText = '' then
  begin
    Result := True;
    Exit;
  end;
  Result := FileWrite(AHandle, AText[1], Length(AText)) = Length(AText);
end;

{Builds the CSV summary row (without a trailing newline) for a sample.  Built by successive concatenation to keep
each term a plain string, avoiding any ambiguity in a single large casted expression.}
function BuildSummaryRow(const ASample: TFastMM_MemorySample): AnsiString;
var
  LText: string;
begin
  LText := IntToStr(ASample.SampleIndex);
  LText := LText + ',' + TimestampToCsv(ASample.WallClock);
  LText := LText + ',' + IntToStr(Int64(ASample.ElapsedMilliseconds));
  LText := LText + ',' + IntToStr(ASample.MemoryManagerUsageBytes);
  LText := LText + ',' + IntToStr(ASample.AllocatedBytes);
  LText := LText + ',' + IntToStr(ASample.ReservedBytes);
  LText := LText + ',' + IntToStr(ASample.OverheadBytes);
  LText := LText + ',' + FloatToCsv(ASample.EfficiencyPercentage, 2);
  LText := LText + ',' + IntToStr(ASample.SmallBlockAllocatedBytes);
  LText := LText + ',' + IntToStr(ASample.SmallBlockReservedBytes);
  LText := LText + ',' + IntToStr(ASample.SmallBlockCount);
  LText := LText + ',' + IntToStr(ASample.MediumBlockAllocatedBytes);
  LText := LText + ',' + IntToStr(ASample.MediumBlockReservedBytes);
  LText := LText + ',' + IntToStr(ASample.MediumBlockCount);
  LText := LText + ',' + IntToStr(ASample.LargeBlockAllocatedBytes);
  LText := LText + ',' + IntToStr(ASample.LargeBlockReservedBytes);
  LText := LText + ',' + IntToStr(ASample.LargeBlockCount);
  LText := LText + ',' + IntToStr(ASample.SmallBlockContentionCount);
  LText := LText + ',' + IntToStr(ASample.MediumBlockContentionCount);
  LText := LText + ',' + IntToStr(ASample.LargeBlockContentionCount);
  LText := LText + #13#10;
  Result := AnsiString(LText);
end;

{Builds a CSV detail row (without a trailing newline) for one small block size class of a sample.}
function BuildDetailRow(ASampleIndex: Integer; AElapsedMilliseconds: Cardinal;
  const AState: TSmallBlockTypeState): AnsiString;
var
  LText: string;
  LUsedBytes, LReservedBytes: Int64;
  LEfficiency: Double;
begin
  LReservedBytes := Int64(AState.ReservedAddressSpace);
  LUsedBytes := Int64(AState.AllocatedBlockCount) * AState.UseableBlockSize;
  if LReservedBytes > 0 then
    LEfficiency := 100.0 * LUsedBytes / LReservedBytes
  else
    LEfficiency := 100.0;

  LText := IntToStr(ASampleIndex);
  LText := LText + ',' + IntToStr(Int64(AElapsedMilliseconds));
  LText := LText + ',' + IntToStr(Int64(AState.InternalBlockSize));
  LText := LText + ',' + IntToStr(Int64(AState.UseableBlockSize));
  LText := LText + ',' + IntToStr(Int64(AState.AllocatedBlockCount));
  LText := LText + ',' + IntToStr(LReservedBytes);
  LText := LText + ',' + IntToStr(LUsedBytes);
  LText := LText + ',' + FloatToCsv(LEfficiency, 2);
  LText := LText + #13#10;
  Result := AnsiString(LText);
end;

{--------------------------------------------------------}
{-----------------------Thread class---------------------}
{--------------------------------------------------------}

type
  {A minimal TThread that forwards execution to the owning profiler.  Kept private to the unit.}
  TSamplingThread = class(TThread)
  private
    FProfiler: TFastMM_SamplingProfiler;
  protected
    procedure Execute; override;
  public
    constructor Create(AProfiler: TFastMM_SamplingProfiler);
  end;

constructor TSamplingThread.Create(AProfiler: TFastMM_SamplingProfiler);
begin
  {Wire up the profiler reference before the thread body can run.  The profiler itself is fully constructed by the
  time Start creates this thread, and Execute only touches the profiler and this thread's own Terminated flag, so the
  thread may be created running (no suspend/resume dance, which differs across Delphi versions).}
  FProfiler := AProfiler;
  inherited Create(False);
end;

procedure TSamplingThread.Execute;
begin
  {Sampling is a background diagnostic;  keep it out of the way of the application threads.  Setting the priority from
  within the thread body avoids any cross-version Start/Resume differences.}
  Priority := tpLower;

  {Take an initial sample at t = 0 so the series starts at the moment Start was called.}
  FProfiler.DoSample;

  while not Terminated do
  begin
    {Wait for the interval, but wake immediately if a stop is requested.}
    if FProfiler.FStopEvent.WaitFor(FProfiler.FIntervalMilliseconds) = wrSignaled then
      Break;
    if Terminated then
      Break;
    FProfiler.DoSample;
  end;
end;

{--------------------------------------------------------}
{---------------------TFastMM_SamplingProfiler-----------}
{--------------------------------------------------------}

constructor TFastMM_SamplingProfiler.Create;
begin
  inherited Create;
  InitializeCriticalSection(FLock);
  FStopEvent := TEvent.Create(nil, True, False, '');
  FIntervalMilliseconds := 1000;
  FLockTimeoutMilliseconds := 50;
  FSummaryHandle := INVALID_HANDLE_VALUE;
  FDetailHandle := INVALID_HANDLE_VALUE;
end;

destructor TFastMM_SamplingProfiler.Destroy;
begin
  Stop;
  FStopEvent.Free;
  DeleteCriticalSection(FLock);
  inherited Destroy;
end;

procedure TFastMM_SamplingProfiler.SetIntervalMilliseconds(AValue: Cardinal);
begin
  if AValue < 1 then
    AValue := 1;
  FIntervalMilliseconds := AValue;
end;

function TFastMM_SamplingProfiler.GetRunning: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    Result := FRunning;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TFastMM_SamplingProfiler.OpenOutputFiles;
begin
  if FSummaryFileName <> '' then
  begin
    FSummaryHandle := THandle(FileCreate(FSummaryFileName));
    if FSummaryHandle <> INVALID_HANDLE_VALUE then
      WriteSummaryHeader;
  end;

  if FDetailFileName <> '' then
  begin
    FDetailHandle := THandle(FileCreate(FDetailFileName));
    if FDetailHandle <> INVALID_HANDLE_VALUE then
      WriteDetailHeader;
  end;
end;

procedure TFastMM_SamplingProfiler.CloseOutputFiles;
begin
  if FSummaryHandle <> INVALID_HANDLE_VALUE then
  begin
    FileClose(FSummaryHandle);
    FSummaryHandle := INVALID_HANDLE_VALUE;
  end;
  if FDetailHandle <> INVALID_HANDLE_VALUE then
  begin
    FileClose(FDetailHandle);
    FDetailHandle := INVALID_HANDLE_VALUE;
  end;
end;

procedure TFastMM_SamplingProfiler.WriteSummaryHeader;
begin
  WriteStringToHandle(FSummaryHandle,
    'sample_index,wall_clock,elapsed_ms,mm_usage_bytes,allocated_bytes,reserved_bytes,overhead_bytes,'
    + 'efficiency_pct,small_alloc_bytes,small_reserved_bytes,small_block_count,medium_alloc_bytes,'
    + 'medium_reserved_bytes,medium_block_count,large_alloc_bytes,large_reserved_bytes,large_block_count,'
    + 'small_contention,medium_contention,large_contention'#13#10);
end;

procedure TFastMM_SamplingProfiler.WriteDetailHeader;
begin
  WriteStringToHandle(FDetailHandle,
    'sample_index,elapsed_ms,block_size,useable_size,allocated_count,reserved_bytes,used_bytes,efficiency_pct'#13#10);
end;

procedure TFastMM_SamplingProfiler.DoSample;
var
  LState: TFastMM_MemoryManagerState;
  LSample: TFastMM_MemorySample;
  i: Integer;
begin
  {Snapshot the state (this is the expensive part - it walks the pool and locks arenas).}
  FillChar(LSample, SizeOf(LSample), 0);
  LSample.WallClock := Now;
  if FStartTickValid then
    LSample.ElapsedMilliseconds := GetTickCount - FStartTickCount
  else
    LSample.ElapsedMilliseconds := 0;
  LSample.MemoryManagerUsageBytes := Int64(FastMM_GetCurrentMemoryUsage);
  FastMM_GetMemoryManagerState(LState, FLockTimeoutMilliseconds);
  PopulateSampleFromState(LState, LSample);

  {Assign the sample index and advance it under the lock so SampleNow and the timer thread cannot collide.}
  EnterCriticalSection(FLock);
  try
    LSample.SampleIndex := FSampleIndex;
    Inc(FSampleIndex);
  finally
    LeaveCriticalSection(FLock);
  end;

  {Write the summary row.}
  if FSummaryHandle <> INVALID_HANDLE_VALUE then
  begin
    WriteStringToHandle(FSummaryHandle, BuildSummaryRow(LSample));
    {Flush so a later crash still leaves the samples collected so far.}
    FlushFileBuffers(FSummaryHandle);
  end;

  {Write the detail rows (one per small block size class that has any reserved space).}
  if FDetailHandle <> INVALID_HANDLE_VALUE then
  begin
    for i := 0 to Integer(LState.SmallBlockTypeCount) - 1 do
    begin
      if (LState.SmallBlockTypeStates[i].ReservedAddressSpace = 0)
        and (LState.SmallBlockTypeStates[i].AllocatedBlockCount = 0) then
        Continue;
      WriteStringToHandle(FDetailHandle,
        BuildDetailRow(LSample.SampleIndex, LSample.ElapsedMilliseconds, LState.SmallBlockTypeStates[i]));
    end;
    FlushFileBuffers(FDetailHandle);
  end;

  {Invoke the callback last, after the row is safely written.}
  if Assigned(FCallback) then
    FCallback(LSample, FCallbackUserData);
end;

procedure TFastMM_SamplingProfiler.Start;
begin
  EnterCriticalSection(FLock);
  try
    if FRunning then
      Exit;
    FRunning := True;
  finally
    LeaveCriticalSection(FLock);
  end;

  FSampleIndex := 0;
  FStartTickCount := GetTickCount;
  FStartTickValid := True;
  FStopEvent.ResetEvent;
  OpenOutputFiles;

  {The thread starts running immediately;  everything it needs is already in place.}
  FThread := TSamplingThread.Create(Self);
end;

procedure TFastMM_SamplingProfiler.Stop;
var
  LWasRunning: Boolean;
begin
  EnterCriticalSection(FLock);
  try
    LWasRunning := FRunning;
    FRunning := False;
  finally
    LeaveCriticalSection(FLock);
  end;

  if not LWasRunning then
    Exit;

  {Signal the thread to wake and terminate, then wait for it.}
  FThread.Terminate;
  FStopEvent.SetEvent;
  FThread.WaitFor;
  FThread.Free;
  FThread := nil;

  CloseOutputFiles;
  FStartTickValid := False;
end;

function TFastMM_SamplingProfiler.SampleNow: TFastMM_MemorySample;
var
  LState: TFastMM_MemoryManagerState;
  LTemporarilyOpened: Boolean;
begin
  {If the timer is running the sampling thread owns the file handles;  route through DoSample on THIS thread is not
  safe for the file handle, so for a manual call while running we only compute and return the sample plus invoke the
  callback, without touching the timer-owned files.  When not running we may open the summary file in append mode for
  the duration of the call.}
  LTemporarilyOpened := False;

  if not GetRunning then
  begin
    if (FSummaryFileName <> '') and (FSummaryHandle = INVALID_HANDLE_VALUE) then
    begin
      {Open for append (create if missing).}
      if FileExists(FSummaryFileName) then
        FSummaryHandle := THandle(FileOpen(FSummaryFileName, fmOpenReadWrite or fmShareDenyWrite))
      else
      begin
        FSummaryHandle := THandle(FileCreate(FSummaryFileName));
        if FSummaryHandle <> INVALID_HANDLE_VALUE then
          WriteSummaryHeader;
      end;

      if FSummaryHandle <> INVALID_HANDLE_VALUE then
      begin
        FileSeek(FSummaryHandle, 0, 2 {soFromEnd});
        LTemporarilyOpened := True;
      end;
    end;
  end;

  FillChar(Result, SizeOf(Result), 0);
  Result.WallClock := Now;
  if FStartTickValid then
    Result.ElapsedMilliseconds := GetTickCount - FStartTickCount
  else
    Result.ElapsedMilliseconds := 0;
  Result.MemoryManagerUsageBytes := Int64(FastMM_GetCurrentMemoryUsage);
  FastMM_GetMemoryManagerState(LState, FLockTimeoutMilliseconds);
  PopulateSampleFromState(LState, Result);

  EnterCriticalSection(FLock);
  try
    Result.SampleIndex := FSampleIndex;
    Inc(FSampleIndex);
  finally
    LeaveCriticalSection(FLock);
  end;

  if LTemporarilyOpened then
  begin
    WriteStringToHandle(FSummaryHandle, BuildSummaryRow(Result));
    FileClose(FSummaryHandle);
    FSummaryHandle := INVALID_HANDLE_VALUE;
  end;

  if Assigned(FCallback) then
    FCallback(Result, FCallbackUserData);
end;

end.
