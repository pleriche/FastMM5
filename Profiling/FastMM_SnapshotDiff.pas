{

FastMM_SnapshotDiff - heap snapshot capture and comparison for FastMM5

Description:
  Captures point-in-time snapshots of all live FastMM5 allocations, aggregated by block content (class instances by
  class name, probable string data, unclassified blocks), and compares two snapshots taken at different times.  This
  answers the most common memory profiling question - "which classes grew between point A and point B?" - without
  requiring debug mode, allocation groups or a recompile.

  Note the difference to FastMM_LogStateToFile:  the latter can only diff allocation group ranges (which requires
  debug mode), whereas this unit diffs two arbitrary points in time in any mode.

Usage:
  var
    LBefore, LAfter: TFastMM_HeapSnapshot;
    LDiff: TFastMM_SnapshotDiff;
  begin
    FastMM_CaptureHeapSnapshot(LBefore);
    ...do work...
    FastMM_CaptureHeapSnapshot(LAfter);
    FastMM_DiffHeapSnapshots(LBefore, LAfter, LDiff);
    FastMM_SaveSnapshotDiffToFile(LDiff, 'HeapDiff.txt');
  end;

Notes:
  - Capturing walks the memory pool via FastMM_WalkBlocks.  While an arena is being walked it is locked, so other
    threads allocating from that arena will briefly block.  The walk itself does not allocate any memory.
  - If other threads allocate or free while the snapshot is being captured, the snapshot is a close approximation
    rather than an exact atomic picture.
  - Block content detection uses the same heuristics as the FastMM5 leak report (FastMM_DetectClassInstance /
    FastMM_DetectStringData), so the same caveats apply:  a block that merely looks like a class instance or string
    will be classified as one.
  - Compatible with Delphi 7 and later (no generics, no inline without guard, no Exit(Value)).

Version history:
  1.0 (17 July 2026): Initial implementation.

}

unit FastMM_SnapshotDiff;

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
  {$if CompilerVersion >= 23}Winapi.Windows, System.SysUtils,{$else}Windows, SysUtils,{$ifend}
  {FastMM5 is only used, not installed here:  the application itself must list FastMM5 as the very first unit of the
  project so that it installs itself as the memory manager.}
  FastMM5;

type
  {A single aggregated entry in a heap snapshot:  all live blocks with the same detected content.}
  TFastMM_SnapshotEntry = record
    {The class name for detected class instances, 'AnsiString' / 'UnicodeString' for probable string data, or
    '(unknown)' for blocks that could not be classified.}
    Name: string;
    InstanceCount: Int64;
    TotalBytes: Int64;
  end;
  TFastMM_SnapshotEntries = array of TFastMM_SnapshotEntry;

  TFastMM_HeapSnapshot = record
    Timestamp: TDateTime;
    {False if one or more arenas could not be locked within the timeout, i.e. the snapshot is incomplete.}
    AllArenasWalked: Boolean;
    {True if there were more distinct block content types than the (generous) table capacity.  The blocks that did not
    fit are aggregated under '(unknown)'.}
    ContentTypeTableOverflowed: Boolean;
    TotalBlockCount: Int64;
    {The sum of the usable sizes of all live blocks, i.e. excluding block headers and internal fragmentation.}
    TotalUserBytes: Int64;
    {Aggregated entries, sorted by Name.}
    Entries: TFastMM_SnapshotEntries;
  end;

  TFastMM_SnapshotDiffEntry = record
    Name: string;
    CountA, CountB, DeltaCount: Int64;
    BytesA, BytesB, DeltaBytes: Int64;
  end;
  TFastMM_SnapshotDiffEntries = array of TFastMM_SnapshotDiffEntry;

  TFastMM_SnapshotDiff = record
    TimestampA, TimestampB: TDateTime;
    TotalBlockCountA, TotalBlockCountB: Int64;
    TotalUserBytesA, TotalUserBytesB: Int64;
    {True if either snapshot was incomplete (arena lock timeout or content type table overflow).}
    Incomplete: Boolean;
    {Entries sorted by DeltaBytes descending, i.e. the biggest growth first and the biggest shrinkage last.}
    Entries: TFastMM_SnapshotDiffEntries;
  end;

{Captures a snapshot of all currently allocated blocks.  Returns True if the snapshot is complete, False if one or
more arenas were skipped due to a lock timeout or the content type table overflowed (both are also reflected in the
snapshot fields).}
function FastMM_CaptureHeapSnapshot(out ASnapshot: TFastMM_HeapSnapshot;
  ALockTimeoutMilliseconds: Cardinal = 1000): Boolean;

{Compares two snapshots.  Entries that are byte- and count-identical in both snapshots are omitted unless
AIncludeUnchanged is True.}
procedure FastMM_DiffHeapSnapshots(const ASnapshotA, ASnapshotB: TFastMM_HeapSnapshot; out ADiff: TFastMM_SnapshotDiff;
  AIncludeUnchanged: Boolean = False);

{Renders a snapshot as text, sorted by total bytes descending.  AMaxEntries = 0 means no limit.}
function FastMM_SnapshotToText(const ASnapshot: TFastMM_HeapSnapshot; AMaxEntries: Integer = 0): string;

{Renders a diff as text.  Entries are listed in DeltaBytes descending order, so with AMaxEntries > 0 the biggest
shrinkage entries (at the bottom) are cut off first.  AMaxEntries = 0 means no limit.}
function FastMM_SnapshotDiffToText(const ADiff: TFastMM_SnapshotDiff; AMaxEntries: Integer = 0): string;

{Writes the text rendering of a diff to a file (UTF-8, no BOM).  Returns False if the file could not be written.}
function FastMM_SaveSnapshotDiffToFile(const ADiff: TFastMM_SnapshotDiff; const AFilename: string;
  AMaxEntries: Integer = 0): Boolean;

implementation

const
  {Pseudo content types for non-class block content.  Real class content types are the class pointer itself, which is
  always > 65535 and pointer aligned, so these values can never collide with a class.}
  CContentTypeUnknown = 0;
  CContentTypeAnsiString = 1;
  CContentTypeUnicodeString = 2;

  {The initial and maximum number of distinct content types (i.e. classes) the capture hash table can hold.  On
  overflow the capture is retried with 4x the capacity until the maximum is reached.}
  CInitialEntryCapacity = 8 * 1024;
  CMaximumEntryCapacity = 512 * 1024;

  CEntryNameAnsiString = 'AnsiString';
  CEntryNameUnicodeString = 'UnicodeString';
  CEntryNameUnknown = '(unknown)';

type
  {One entry of the capture hash table.  The table is keyed on the first native word of the block content:  for class
  instances that word is the class pointer, so expensive content detection (which involves VirtualQuery) runs only
  once per distinct first word - the same optimization FastMM_LogStateToFile uses.}
  TRawContentEntry = record
    {The first native word of the block content.  0 = slot unused (0 never passes the plausibility check).}
    RawFirstWord: NativeUInt;
    {The resolved content type:  a class pointer, or one of the CContentType* pseudo types.}
    ContentType: NativeUInt;
    InstanceCount: Int64;
    TotalBytes: Int64;
  end;
  PRawContentEntry = ^TRawContentEntry;
  TRawContentEntries = array of TRawContentEntry;

  PCaptureState = ^TCaptureState;
  TCaptureState = record
    {Length(Slots) - 1.  Length(Slots) is a power of two.}
    SlotMask: NativeUInt;
    UsedEntryCount: Integer;
    {The maximum number of used entries (half the slot count, to keep open addressing probes short).}
    MaxUsedEntryCount: Integer;
    Overflowed: Boolean;
    {The result of FastMM_WalkBlocks:  False if one or more arenas were skipped due to a lock timeout.}
    WalkComplete: Boolean;
    TotalBlockCount: Int64;
    TotalUserBytes: Int64;
    {Blocks whose first word cannot be a class reference are classified directly into these accumulators, bypassing
    the hash table.}
    DirectCounts: array[CContentTypeUnknown..CContentTypeUnicodeString] of Int64;
    DirectBytes: array[CContentTypeUnknown..CContentTypeUnicodeString] of Int64;
    {The open addressing (linear probing) hash table.}
    Slots: TRawContentEntries;
  end;

{--------------------------------------------------------}
{---------------------Snapshot capture-------------------}
{--------------------------------------------------------}

function HashFirstWord(AValue: NativeUInt): NativeUInt; {$IF CompilerVersion >= 18}inline;{$IFEND}
begin
  {The low bits of a pointer are zero due to alignment, so shift them out before mixing.}
  Result := (AValue shr 3) * NativeUInt($9E3779B1);
end;

{Classifies block content that has already been checked to not be a class instance.}
function DetectNonClassContentType(APBlock: Pointer; AUsableSize: NativeInt): NativeUInt;
begin
  case FastMM_DetectStringData(APBlock, AUsableSize) of
    sdtAnsiString:
      Result := CContentTypeAnsiString;
    sdtUnicodeString:
      Result := CContentTypeUnicodeString;
  else
    Result := CContentTypeUnknown;
  end;
end;

{Fully classifies block content.  This is the expensive path (FastMM_DetectClassInstance calls VirtualQuery), so it
runs only once per distinct first word.}
function DetectContentType(APBlock: Pointer; AUsableSize: NativeInt): NativeUInt;
var
  LClass: TClass;
begin
  LClass := FastMM_DetectClassInstance(APBlock);
  if LClass <> nil then
    Result := NativeUInt(LClass)
  else
    Result := DetectNonClassContentType(APBlock, AUsableSize);
end;

{The FastMM_WalkBlocks callback.  IMPORTANT:  arenas are locked while this executes, so this routine (and everything
it calls) must not allocate or free memory through the memory manager.}
procedure CaptureSnapshotCallback(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
var
  LPState: PCaptureState;
  LFirstWord, LSlotIndex: NativeUInt;
  LContentType: NativeUInt;
  LPEntry: PRawContentEntry;
begin
  LPState := ABlockInfo.UserData;

  Inc(LPState.TotalBlockCount);
  Inc(LPState.TotalUserBytes, ABlockInfo.UsableSize);

  {Plausibility check for a class reference in the first word, as in FastMM_LogStateToFile:  class pointers are
  > 65535 and pointer aligned.  Anything else can at most be string data.}
  LFirstWord := PNativeUInt(ABlockInfo.BlockAddress)^;
  if (LFirstWord > 65535) and (LFirstWord and NativeUInt(SizeOf(Pointer) - 1) = 0) then
  begin
    LSlotIndex := HashFirstWord(LFirstWord) and LPState.SlotMask;
    while True do
    begin
      LPEntry := @LPState.Slots[LSlotIndex];

      if LPEntry.RawFirstWord = LFirstWord then
      begin
        {Known first word:  just accumulate.}
        Inc(LPEntry.InstanceCount);
        Inc(LPEntry.TotalBytes, ABlockInfo.UsableSize);
        Exit;
      end;

      if LPEntry.RawFirstWord = 0 then
      begin
        {Free slot reached:  this is a new first word.}
        if LPState.UsedEntryCount >= LPState.MaxUsedEntryCount then
        begin
          {Table full:  flag the overflow (the capture will be retried with a bigger table if possible) and fall back
          to the direct accumulators so the totals stay correct even if no retry is possible.}
          LPState.Overflowed := True;
          LContentType := DetectNonClassContentType(ABlockInfo.BlockAddress, ABlockInfo.UsableSize);
          Inc(LPState.DirectCounts[LContentType]);
          Inc(LPState.DirectBytes[LContentType], ABlockInfo.UsableSize);
          Exit;
        end;

        Inc(LPState.UsedEntryCount);
        LPEntry.RawFirstWord := LFirstWord;
        LPEntry.ContentType := DetectContentType(ABlockInfo.BlockAddress, ABlockInfo.UsableSize);
        LPEntry.InstanceCount := 1;
        LPEntry.TotalBytes := ABlockInfo.UsableSize;
        Exit;
      end;

      LSlotIndex := (LSlotIndex + 1) and LPState.SlotMask;
    end;
  end
  else
  begin
    {The first word cannot be a class reference:  classify directly.}
    LContentType := DetectNonClassContentType(ABlockInfo.BlockAddress, ABlockInfo.UsableSize);
    Inc(LPState.DirectCounts[LContentType]);
    Inc(LPState.DirectBytes[LContentType], ABlockInfo.UsableSize);
  end;
end;

procedure InitializeCaptureState(var AState: TCaptureState; AEntryCapacity: Integer);
begin
  {Release a previous table (retry pass) before wiping the record, otherwise the array reference would leak.}
  AState.Slots := nil;
  FillChar(AState, SizeOf(AState), 0);
  SetLength(AState.Slots, AEntryCapacity * 2);
  FillChar(AState.Slots[0], Length(AState.Slots) * SizeOf(TRawContentEntry), 0);
  AState.SlotMask := NativeUInt(Length(AState.Slots) - 1);
  AState.MaxUsedEntryCount := AEntryCapacity;
end;

procedure QuickSortEntriesByName(var AEntries: TFastMM_SnapshotEntries; ALeft, ARight: Integer);
var
  i, j: Integer;
  LPivot: string;
  LTemp: TFastMM_SnapshotEntry;
begin
  while ALeft < ARight do
  begin
    i := ALeft;
    j := ARight;
    LPivot := AEntries[(ALeft + ARight) shr 1].Name;
    repeat
      while CompareStr(AEntries[i].Name, LPivot) < 0 do
        Inc(i);
      while CompareStr(AEntries[j].Name, LPivot) > 0 do
        Dec(j);
      if i <= j then
      begin
        if i <> j then
        begin
          LTemp := AEntries[i];
          AEntries[i] := AEntries[j];
          AEntries[j] := LTemp;
        end;
        Inc(i);
        Dec(j);
      end;
    until i > j;
    if j > ALeft then
      QuickSortEntriesByName(AEntries, ALeft, j);
    ALeft := i;
  end;
end;

{Builds the final name-keyed snapshot entries from the capture state:  resolve class names, merge the string/unknown
pseudo types, sort by name and merge duplicate names (distinct classes may share a name across packages).}
procedure BuildSnapshotFromState(const AState: TCaptureState; var ASnapshot: TFastMM_HeapSnapshot);
var
  LRawIndex, LOutCount, i: Integer;
  LPRawEntry: PRawContentEntry;
  LPseudoCounts: array[CContentTypeUnknown..CContentTypeUnicodeString] of Int64;
  LPseudoBytes: array[CContentTypeUnknown..CContentTypeUnicodeString] of Int64;
  LContentType: NativeUInt;
begin
  ASnapshot.ContentTypeTableOverflowed := AState.Overflowed;
  ASnapshot.TotalBlockCount := AState.TotalBlockCount;
  ASnapshot.TotalUserBytes := AState.TotalUserBytes;

  for LContentType := CContentTypeUnknown to CContentTypeUnicodeString do
  begin
    LPseudoCounts[LContentType] := AState.DirectCounts[LContentType];
    LPseudoBytes[LContentType] := AState.DirectBytes[LContentType];
  end;

  {Worst case:  every used hash entry is a distinct class, plus the three pseudo entries.}
  SetLength(ASnapshot.Entries, AState.UsedEntryCount + 3);
  LOutCount := 0;

  for LRawIndex := 0 to Length(AState.Slots) - 1 do
  begin
    LPRawEntry := @AState.Slots[LRawIndex];
    if LPRawEntry.RawFirstWord = 0 then
      Continue;

    if LPRawEntry.ContentType > CContentTypeUnicodeString then
    begin
      {A class:  resolve the name now (string allocation is safe here, the walk is over).}
      ASnapshot.Entries[LOutCount].Name := string(TClass(LPRawEntry.ContentType).ClassName);
      ASnapshot.Entries[LOutCount].InstanceCount := LPRawEntry.InstanceCount;
      ASnapshot.Entries[LOutCount].TotalBytes := LPRawEntry.TotalBytes;
      Inc(LOutCount);
    end
    else
    begin
      {A first word that passed the plausibility check but turned out to be string/unknown content.}
      Inc(LPseudoCounts[LPRawEntry.ContentType], LPRawEntry.InstanceCount);
      Inc(LPseudoBytes[LPRawEntry.ContentType], LPRawEntry.TotalBytes);
    end;
  end;

  for LContentType := CContentTypeUnknown to CContentTypeUnicodeString do
  begin
    if LPseudoCounts[LContentType] <> 0 then
    begin
      case LContentType of
        CContentTypeAnsiString:
          ASnapshot.Entries[LOutCount].Name := CEntryNameAnsiString;
        CContentTypeUnicodeString:
          ASnapshot.Entries[LOutCount].Name := CEntryNameUnicodeString;
      else
        ASnapshot.Entries[LOutCount].Name := CEntryNameUnknown;
      end;
      ASnapshot.Entries[LOutCount].InstanceCount := LPseudoCounts[LContentType];
      ASnapshot.Entries[LOutCount].TotalBytes := LPseudoBytes[LContentType];
      Inc(LOutCount);
    end;
  end;

  SetLength(ASnapshot.Entries, LOutCount);
  if LOutCount > 1 then
    QuickSortEntriesByName(ASnapshot.Entries, 0, LOutCount - 1);

  {Merge adjacent entries with the same name (classes with equal names from different modules).}
  LOutCount := 0;
  for i := 0 to Length(ASnapshot.Entries) - 1 do
  begin
    if (LOutCount > 0) and (ASnapshot.Entries[LOutCount - 1].Name = ASnapshot.Entries[i].Name) then
    begin
      Inc(ASnapshot.Entries[LOutCount - 1].InstanceCount, ASnapshot.Entries[i].InstanceCount);
      Inc(ASnapshot.Entries[LOutCount - 1].TotalBytes, ASnapshot.Entries[i].TotalBytes);
    end
    else
    begin
      if LOutCount <> i then
        ASnapshot.Entries[LOutCount] := ASnapshot.Entries[i];
      Inc(LOutCount);
    end;
  end;
  SetLength(ASnapshot.Entries, LOutCount);
end;

function FastMM_CaptureHeapSnapshot(out ASnapshot: TFastMM_HeapSnapshot;
  ALockTimeoutMilliseconds: Cardinal): Boolean;
var
  LState: TCaptureState;
  LEntryCapacity: Integer;
begin
  ASnapshot.Entries := nil;
  FillChar(ASnapshot, SizeOf(ASnapshot), 0);

  LEntryCapacity := CInitialEntryCapacity;
  while True do
  begin
    InitializeCaptureState(LState, LEntryCapacity);

    {Process pending frees first so blocks freed by other threads are not counted as live.}
    FastMM_ProcessAllPendingFrees;

    ASnapshot.Timestamp := Now;
    LState.WalkComplete := FastMM_WalkBlocks(CaptureSnapshotCallback, [btSmallBlock, btMediumBlock, btLargeBlock],
      True, @LState, ALockTimeoutMilliseconds);

    if (not LState.Overflowed) or (LEntryCapacity >= CMaximumEntryCapacity) then
      Break;

    {The content type table overflowed:  discard this pass and retry with a bigger table.}
    LEntryCapacity := LEntryCapacity * 4;
  end;

  BuildSnapshotFromState(LState, ASnapshot);
  ASnapshot.AllArenasWalked := LState.WalkComplete;

  Result := LState.WalkComplete and (not LState.Overflowed);
end;

{--------------------------------------------------------}
{------------------------Diffing-------------------------}
{--------------------------------------------------------}

procedure QuickSortDiffEntriesByDeltaBytes(var AEntries: TFastMM_SnapshotDiffEntries; ALeft, ARight: Integer);
var
  i, j: Integer;
  LPivot: Int64;
  LTemp: TFastMM_SnapshotDiffEntry;
begin
  while ALeft < ARight do
  begin
    i := ALeft;
    j := ARight;
    LPivot := AEntries[(ALeft + ARight) shr 1].DeltaBytes;
    repeat
      {Descending order.}
      while AEntries[i].DeltaBytes > LPivot do
        Inc(i);
      while AEntries[j].DeltaBytes < LPivot do
        Dec(j);
      if i <= j then
      begin
        if i <> j then
        begin
          LTemp := AEntries[i];
          AEntries[i] := AEntries[j];
          AEntries[j] := LTemp;
        end;
        Inc(i);
        Dec(j);
      end;
    until i > j;
    if j > ALeft then
      QuickSortDiffEntriesByDeltaBytes(AEntries, ALeft, j);
    ALeft := i;
  end;
end;

procedure FastMM_DiffHeapSnapshots(const ASnapshotA, ASnapshotB: TFastMM_HeapSnapshot; out ADiff: TFastMM_SnapshotDiff;
  AIncludeUnchanged: Boolean);
var
  ia, ib, LOutCount, LCompareResult: Integer;
  LCountA, LCountB, LBytesA, LBytesB: Int64;
  LName: string;
begin
  ADiff.Entries := nil;
  FillChar(ADiff, SizeOf(ADiff), 0);

  ADiff.TimestampA := ASnapshotA.Timestamp;
  ADiff.TimestampB := ASnapshotB.Timestamp;
  ADiff.TotalBlockCountA := ASnapshotA.TotalBlockCount;
  ADiff.TotalBlockCountB := ASnapshotB.TotalBlockCount;
  ADiff.TotalUserBytesA := ASnapshotA.TotalUserBytes;
  ADiff.TotalUserBytesB := ASnapshotB.TotalUserBytes;
  ADiff.Incomplete := (not ASnapshotA.AllArenasWalked) or ASnapshotA.ContentTypeTableOverflowed
    or (not ASnapshotB.AllArenasWalked) or ASnapshotB.ContentTypeTableOverflowed;

  SetLength(ADiff.Entries, Length(ASnapshotA.Entries) + Length(ASnapshotB.Entries));
  LOutCount := 0;

  {Merge-join the two name-sorted entry lists.}
  ia := 0;
  ib := 0;
  while (ia < Length(ASnapshotA.Entries)) or (ib < Length(ASnapshotB.Entries)) do
  begin
    if ia >= Length(ASnapshotA.Entries) then
      LCompareResult := 1
    else if ib >= Length(ASnapshotB.Entries) then
      LCompareResult := -1
    else
      LCompareResult := CompareStr(ASnapshotA.Entries[ia].Name, ASnapshotB.Entries[ib].Name);

    if LCompareResult < 0 then
    begin
      {Only in A:  disappeared completely.}
      LName := ASnapshotA.Entries[ia].Name;
      LCountA := ASnapshotA.Entries[ia].InstanceCount;
      LBytesA := ASnapshotA.Entries[ia].TotalBytes;
      LCountB := 0;
      LBytesB := 0;
      Inc(ia);
    end
    else if LCompareResult > 0 then
    begin
      {Only in B:  newly appeared.}
      LName := ASnapshotB.Entries[ib].Name;
      LCountA := 0;
      LBytesA := 0;
      LCountB := ASnapshotB.Entries[ib].InstanceCount;
      LBytesB := ASnapshotB.Entries[ib].TotalBytes;
      Inc(ib);
    end
    else
    begin
      LName := ASnapshotA.Entries[ia].Name;
      LCountA := ASnapshotA.Entries[ia].InstanceCount;
      LBytesA := ASnapshotA.Entries[ia].TotalBytes;
      LCountB := ASnapshotB.Entries[ib].InstanceCount;
      LBytesB := ASnapshotB.Entries[ib].TotalBytes;
      Inc(ia);
      Inc(ib);
    end;

    if AIncludeUnchanged or (LCountA <> LCountB) or (LBytesA <> LBytesB) then
    begin
      ADiff.Entries[LOutCount].Name := LName;
      ADiff.Entries[LOutCount].CountA := LCountA;
      ADiff.Entries[LOutCount].CountB := LCountB;
      ADiff.Entries[LOutCount].DeltaCount := LCountB - LCountA;
      ADiff.Entries[LOutCount].BytesA := LBytesA;
      ADiff.Entries[LOutCount].BytesB := LBytesB;
      ADiff.Entries[LOutCount].DeltaBytes := LBytesB - LBytesA;
      Inc(LOutCount);
    end;
  end;

  SetLength(ADiff.Entries, LOutCount);
  if LOutCount > 1 then
    QuickSortDiffEntriesByDeltaBytes(ADiff.Entries, 0, LOutCount - 1);
end;

{--------------------------------------------------------}
{----------------------Text output-----------------------}
{--------------------------------------------------------}

function SignedIntToStr(AValue: Int64): string;
begin
  if AValue > 0 then
    Result := '+' + IntToStr(AValue)
  else
    Result := IntToStr(AValue);
end;

function TimestampToStr(ATimestamp: TDateTime): string;
begin
  Result := FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', ATimestamp);
end;

function FastMM_SnapshotToText(const ASnapshot: TFastMM_HeapSnapshot; AMaxEntries: Integer): string;
var
  LSorted: TFastMM_SnapshotDiffEntries;
  i, LShownCount: Integer;
begin
  {Reuse the diff sorting by treating the snapshot as a diff against an empty heap.}
  SetLength(LSorted, Length(ASnapshot.Entries));
  for i := 0 to Length(ASnapshot.Entries) - 1 do
  begin
    LSorted[i].Name := ASnapshot.Entries[i].Name;
    LSorted[i].DeltaCount := ASnapshot.Entries[i].InstanceCount;
    LSorted[i].DeltaBytes := ASnapshot.Entries[i].TotalBytes;
  end;
  if Length(LSorted) > 1 then
    QuickSortDiffEntriesByDeltaBytes(LSorted, 0, Length(LSorted) - 1);

  Result := 'FastMM heap snapshot  ' + TimestampToStr(ASnapshot.Timestamp) + #13#10
    + Format('Live blocks: %d,  user bytes: %d', [ASnapshot.TotalBlockCount, ASnapshot.TotalUserBytes]) + #13#10;
  if not ASnapshot.AllArenasWalked then
    Result := Result + '*** WARNING:  one or more arenas were skipped (lock timeout) - the snapshot is incomplete ***'
      + #13#10;
  if ASnapshot.ContentTypeTableOverflowed then
    Result := Result + '*** WARNING:  content type table overflowed - excess content is aggregated as '
      + CEntryNameUnknown + ' ***' + #13#10;
  Result := Result + #13#10
    + '       Count           Bytes  Content' + #13#10
    + '------------  --------------  -----------------------------------' + #13#10;

  LShownCount := Length(LSorted);
  if (AMaxEntries > 0) and (AMaxEntries < LShownCount) then
    LShownCount := AMaxEntries;

  for i := 0 to LShownCount - 1 do
  begin
    Result := Result + Format('%12d  %14d  %s',
      [LSorted[i].DeltaCount, LSorted[i].DeltaBytes, LSorted[i].Name]) + #13#10;
  end;

  if LShownCount < Length(LSorted) then
    Result := Result + Format('... (%d more entries)', [Length(LSorted) - LShownCount]) + #13#10;
end;

function FastMM_SnapshotDiffToText(const ADiff: TFastMM_SnapshotDiff; AMaxEntries: Integer): string;
var
  i, LShownCount: Integer;
begin
  Result := 'FastMM heap snapshot diff' + #13#10
    + Format('Snapshot A: %s  (%d blocks, %d user bytes)',
        [TimestampToStr(ADiff.TimestampA), ADiff.TotalBlockCountA, ADiff.TotalUserBytesA]) + #13#10
    + Format('Snapshot B: %s  (%d blocks, %d user bytes)',
        [TimestampToStr(ADiff.TimestampB), ADiff.TotalBlockCountB, ADiff.TotalUserBytesB]) + #13#10
    + Format('Delta:      %s blocks, %s user bytes',
        [SignedIntToStr(ADiff.TotalBlockCountB - ADiff.TotalBlockCountA),
         SignedIntToStr(ADiff.TotalUserBytesB - ADiff.TotalUserBytesA)]) + #13#10;
  if ADiff.Incomplete then
    Result := Result + '*** WARNING:  one or both snapshots are incomplete - deltas may be misleading ***' + #13#10;
  Result := Result + #13#10
    + '     Count A      Count B  Delta Count         Bytes A         Bytes B     Delta Bytes  Content' + #13#10
    + '------------ ------------ ------------ --------------- --------------- ---------------  ------------------'
    + #13#10;

  LShownCount := Length(ADiff.Entries);
  if (AMaxEntries > 0) and (AMaxEntries < LShownCount) then
    LShownCount := AMaxEntries;

  for i := 0 to LShownCount - 1 do
  begin
    Result := Result + Format('%12d %12d %12s %15d %15d %15s  %s',
      [ADiff.Entries[i].CountA, ADiff.Entries[i].CountB, SignedIntToStr(ADiff.Entries[i].DeltaCount),
       ADiff.Entries[i].BytesA, ADiff.Entries[i].BytesB, SignedIntToStr(ADiff.Entries[i].DeltaBytes),
       ADiff.Entries[i].Name]) + #13#10;
  end;

  if LShownCount < Length(ADiff.Entries) then
    Result := Result + Format('... (%d more entries)', [Length(ADiff.Entries) - LShownCount]) + #13#10;
end;

function FastMM_SaveSnapshotDiffToFile(const ADiff: TFastMM_SnapshotDiff; const AFilename: string;
  AMaxEntries: Integer): Boolean;
var
  LText: string;
  LUTF8: UTF8String;
  LFileHandle: THandle;
  LBytesWritten: Integer;
begin
  Result := False;

  LText := FastMM_SnapshotDiffToText(ADiff, AMaxEntries);
  LUTF8 := UTF8Encode(LText);
  if LUTF8 = '' then
    Exit;

  {FileCreate returns Integer on older Delphi versions and THandle on newer ones;  -1 and INVALID_HANDLE_VALUE have
  the same bit pattern, so the cast is safe in both directions.}
  LFileHandle := THandle(FileCreate(AFilename));
  if LFileHandle = INVALID_HANDLE_VALUE then
    Exit;
  try
    LBytesWritten := FileWrite(LFileHandle, LUTF8[1], Length(LUTF8));
    Result := LBytesWritten = Length(LUTF8);
  finally
    FileClose(LFileHandle);
  end;
end;

end.
