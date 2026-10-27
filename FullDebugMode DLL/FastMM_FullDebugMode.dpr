{

Fast Memory Manager: FullDebugMode Support DLL 1.74

Description:
 Support DLL for FastMM. With this DLL available, FastMM will report debug info (unit name, line numbers, etc.) for
 stack traces.

Usage:
 1) To compile you will need the JCL library (http://sourceforge.net/projects/jcl/).  The Windows on ARM (Arm64EC) DLL
    does not use the JCL, since the JCL does not support Arm64EC yet.
 2) Place in the same location as the replacement borlndmm.dll or your application's executable module.

Change log:
 Version 1.00 (9 July 2005):
  - Initial release.
 Version 1.01 (13 July 2005):
  - Added the option to use madExcept instead of the JCL Debug library. (Thanks to Martin Aignesberger.)
 Version 1.02 (30 September 2005):
  - Changed options to display detail for addresses inside libraries as well.
 Version 1.03 (13 October 2005):
  - Added a raw stack trace procedure that implements raw stack traces.
 Version 1.10 (14 October 2005):
  - Improved the program logic behind the skipping of stack levels to cause less incorrect entries in raw stack traces.
    (Thanks to Craig Peterson.)
 Version 1.20 (17 October 2005):
  - Improved support for madExcept stack traces. (Thanks to Mathias Rauen.)
 Version 1.30 (26 October 2005):
  - Changed name to FastMM_FullDebugMode to reflect the fact that there is now a static dependency on this DLL for
    FullDebugMode.  The static dependency solves a DLL unload order issue.  (Thanks to Bart van der Werf.)
 Version 1.40 (31 October 2005):
  - Added support for EurekaLog. (Thanks to Fabio Dell'Aria.)
 Version 1.42 (23 June 2006):
  - Fixed a bug in the RawStackTraces code that may have caused an A/V in some rare circumstances. (Thanks to Primoz
    Gabrijelcic.)
 Version 1.44 (16 November 2006):
  - Changed the RawStackTraces code to prevent it from modifying the Windows "GetLastError" error code. (Thanks to
    Primoz Gabrijelcic.)
 Version 1.50 (14 August 2008):
  - Added support for Delphi 2009. (Thanks to Mark Edington.)
 Version 1.60 (5 May 2009):
  - Improved the code used to identify call instructions in the stack trace code.  (Thanks to the JCL team.)
 Version 1.61 (5 September 2010):
  - Recompiled using the latest JCL in order to fix a possible crash on shutdown when the executable contains no debug
    information. (Thanks to Hanspeter Widmer.)
 Version 1.62 (19 July 2012):
  - Added a workaround for QC 107209 (Thanks to David Heffernan.)
 Version 1.63 (14 September 2013):
  - Added support for OSX (Thanks to Sebastian Zierer)
 Version 1.64 (27 February 2021)
  - Implemented a return address information cache that greatly speeds up the conversion of many similar stack traces
    to text.
 Version 1.65 (10 July 2023)
  - Made LogStackTrace thread safe.
 Version 1.70 (19 July 2025)
  - Invalidate the memory map cache when a library is loaded or unloaded.
 Version 1.71 (29 April 2026)
  - Reduce the number of false positives in the 64-bit stack tracing code by skipping opcodes that are only valid in
    32-bit mode.
 Version 1.72 (14 October 2026)
  - Added support for Windows on ARM (Arm64EC).  The DLL is named FastMM_FullDebugModeArm64EC.dll, and raw stack traces
    are the same as frame based stack traces:  Both walk the stack with the unwind information.  The JCL does not
    support Arm64EC yet, so return addresses are described by module and offset only.
  - 64-bit frame based stack traces no longer start with a return address inside this DLL.
  - If no stack tracing library is selected, return addresses are described by module and offset.
 Version 1.73 (22 October 2026)
  - 64-bit (x64) raw stack traces are now the same as frame based stack traces, as under Arm64EC.  The raw stack tracing
    code relied on 32-bit stack frames and only handled addresses below 4GB.  Under 64-bit it therefore left out the
    frames of system libraries and of modules loaded above 4GB, and it reported return addresses that earlier calls
    had left on the stack.
  - ModuleAndOffsetOnly may be defined on the command line to build the DLL without a stack tracing library.
  - 32-bit raw stack traces now only report the return addresses of the current call chain.  They used to report
    everything on the stack that looked like a return address, including return addresses that earlier calls had left
    in local variables.  This affected every stack trace that FastMM asks for, since EBP does not point to a stack
    frame at that point.  After a callback from a system library, for example, the stack trace could fill up before
    it got back to the code that called the library.
  - Corrected the recognition of the call instruction before a 32-bit return address.  The last bytes of some longer
    instructions are no longer taken for complete 2 and 3 byte calls.  Calls through a table that is indexed by a
    register (CALL [EAX*4+$12345678]) are now recognized.  A call that ends where executable memory ends is no longer
    rejected.  Direct far calls, which 32-bit Windows code does not use, are no longer recognized.
 Version 1.74 (27 October 2026)
  - Added LogStackTraceW, which converts a stack trace to Unicode text and is given the end of the buffer.  With
    LogStackTrace, which produces ANSI text, characters that are not in the system code page are lost, e.g. in the names
    of source files.  FastMM5 uses LogStackTraceW if the DLL has it, and LogStackTrace otherwise.  The madExcept and
    EurekaLog builds only have LogStackTrace, since those libraries only produce ANSI text.

}

{$IFDEF MSWINDOWS}
{--------------------Start of options block-------------------------}

{Select the stack tracing library to use. The JCL, madExcept and EurekaLog are supported. Only one can be used at a
time.}
{$define JCLDebug}
{.$define madExcept}
{.$define EurekaLog_Legacy}
{.$define EurekaLog_V7}

{--------------------End of options block-------------------------}

{The JCL does not support Windows on ARM (Arm64EC) yet.}
{$ifdef ARM64EC}
{$undef JCLDebug}
{$endif}

{Defining ModuleAndOffsetOnly (e.g. on the command line) builds the DLL without a stack tracing library, whatever is
selected above.}
{$ifdef ModuleAndOffsetOnly}
{$undef JCLDebug}
{$undef madExcept}
{$undef EurekaLog_Legacy}
{$undef EurekaLog_V7}
{$endif}

{Without a stack tracing library return addresses are described by module and offset only.}
{$if not (defined(JCLDebug) or defined(madExcept) or defined(EurekaLog_Legacy) or defined(EurekaLog_V7))}
{$define ModuleAndOffsetOnly}
{$ifend}
{$ENDIF}

// JCL_DEBUG_EXPERT_INSERTJDBG OFF
library FastMM_FullDebugMode;

uses
  {$ifdef JCLDebug}JCLDebug,{$endif}
  {$ifdef madExcept}madStackTrace,{$endif}
  {$ifdef EurekaLog_Legacy}ExceptionLog,{$endif}
  {$ifdef EurekaLog_V7}EFastMM4Support,{$endif}
  System.SysUtils, {$IFDEF MACOS}Posix.Base, SBMapFiles {$ELSE} Winapi.Windows {$ENDIF};

{$R *.res}

{$StackFrames on}
{$Warn Symbol_Platform off}
{$Align 8}

{The stack tracing code computes addresses that wrap around, e.g. when it adds a negative call displacement to a return
address.  With overflow and range checks each of them would raise an exception.}
{$OverflowChecks off}
{$RangeChecks off}

{The name of the 64-bit DLL has a '64' at the end, and that of the Windows on ARM (Arm64EC) DLL 'Arm64EC'.}
{$if defined(ARM64EC)}
{$LIBSUFFIX 'Arm64EC'}
{$elseif SizeOf(Pointer) = 8}
{$LIBSUFFIX '64'}
{$ifend}

{Raw stack tracing is only done under 32-bit Windows.  It searches the stack for return addresses, so that it also finds
the callers of functions that were compiled without stack frames.  It relies on the layout of 32-bit stack frames, and
it only handles addresses below 4GB.

64-bit code (x64 and Arm64EC) does not need it.  Every 64-bit function that calls other functions has unwind
information, and the 64-bit frame based stack trace uses it, so it does not depend on stack frames.  The 64-bit Windows
DLLs therefore export the frame based stack tracing routine under both names.  Under macOS, raw stack traces come from
backtrace.}
{$if defined(MSWINDOWS) and (SizeOf(Pointer) = 4)}
{$define Win32RawStackTraces}
{$ifend}

{--------------------------Return Address Info Cache --------------------------}

const
  CReturnAddressCacheSize = 4096;
  {FastMM assumes a maximum of 256 characters per stack trace entry.  The address text and line break are in addition to
  the info text.}
  CMaxInfoTextLength = 224;

type
  {Return address info cache:  Maintains the source information for up to CReturnAddressCacheSize return addresses in
  a binary search tree.}

  PReturnAddressInfo = ^TReturnAddressInfo;
  TReturnAddressInfo = record
    ParentEntry: PReturnAddressInfo;
    ChildEntries: array[0..1] of PReturnAddressInfo;
    ReturnAddress: NativeUInt;
    InfoTextLength: Integer;
    {The info text is kept as Unicode text for LogStackTraceW, and converted to ANSI text for LogStackTrace.}
    InfoText: array[0..CMaxInfoTextLength - 1] of Char;
  end;

  TReturnAddressInfoCache = record
    {Entry 0 is the root of the tree.}
    Entries: array[0..CReturnAddressCacheSize] of TReturnAddressInfo;
    NextNewEntryIndex: Integer;
    function AddEntry(AReturnAddress: NativeUInt; const AReturnAddressInfoText: string): PReturnAddressInfo;
    procedure DeleteEntry(AEntry: PReturnAddressInfo);
    function FindEntry(AReturnAddress: NativeUInt): PReturnAddressInfo;
  end;

function TReturnAddressInfoCache.AddEntry(AReturnAddress: NativeUInt; const AReturnAddressInfoText: string): PReturnAddressInfo;
var
  LParentItem, LChildItem: PReturnAddressInfo;
  LAddressBits: NativeUInt;
  LChildIndex: Integer;
begin
  {Get the address of the entry to reuse. (Entry 0 is the tree root.)}
  if NextNewEntryIndex = High(Entries) then
    NextNewEntryIndex := 0;
  Inc(NextNewEntryIndex);

  Result := @Entries[NextNewEntryIndex];

  {Delete it if it is already in use}
  DeleteEntry(Result);

  {Step down the tree until an open slot is found in the required direction.}
  LParentItem := @Entries[0];
  LAddressBits := AReturnAddress;
  while True do
  begin
    {Get the current child in the appropriate direction.}
    LChildItem := LParentItem.ChildEntries[LAddressBits and 1];
    {No child -> This slot is available.}
    if LChildItem = nil then
      Break;
    {Traverse further down the tree.}
    LParentItem := LChildItem;
    LAddressBits := LAddressBits shr 1;
  end;
  LChildIndex := LAddressBits and 1;

  {Insert the node into the tree}
  LParentItem.ChildEntries[LChildIndex] := Result;
  Result.ParentEntry := LParentItem;

  {Set the info text for the item.}
  Result.ReturnAddress := AReturnAddress;
  Result.InfoTextLength := Length(AReturnAddressInfoText);
  if Result.InfoTextLength > CMaxInfoTextLength then
    Result.InfoTextLength := CMaxInfoTextLength;
  System.Move(Pointer(AReturnAddressInfoText)^, Result.InfoText, Result.InfoTextLength * SizeOf(Char));
end;

procedure TReturnAddressInfoCache.DeleteEntry(AEntry: PReturnAddressInfo);
var
  LRemovedItemChildIndex, LMovedItemChildIndex: Integer;
  LMovedItem, LChildItem: PReturnAddressInfo;
begin
  {Is this entry currently in the tree?}
  if AEntry.ParentEntry = nil then
    Exit;

  LRemovedItemChildIndex := Ord(AEntry.ParentEntry.ChildEntries[1] = AEntry);

  {Does this item have children of its own?}
  if (NativeInt(AEntry.ChildEntries[0]) or NativeInt(AEntry.ChildEntries[1])) <> 0 then
  begin
    {It has children:  We need to traverse child items until we find a leaf item and then move it into this item's
    position in the search tree.}
    LMovedItem := AEntry;

    while True do
    begin
      LChildItem := LMovedItem.ChildEntries[0]; //try left then right
      if LChildItem = nil then
      begin
        LChildItem := LMovedItem.ChildEntries[1];
        if LChildItem = nil then
          Break;
      end;
      LMovedItem := LChildItem;
    end;

    {Disconnect the moved item from its current parent item.}
    LMovedItemChildIndex := Ord(LMovedItem.ParentEntry.ChildEntries[1] = LMovedItem);
    LMovedItem.ParentEntry.ChildEntries[LMovedItemChildIndex] := nil;

    {Set the new parent for the moved item}
    AEntry.ParentEntry.ChildEntries[LRemovedItemChildIndex] := LMovedItem;
    LMovedItem.ParentEntry := AEntry.ParentEntry;

    {Set the new left child for the moved item}
    LChildItem := AEntry.ChildEntries[0];
    if LChildItem <> nil then
    begin
      LMovedItem.ChildEntries[0] := LChildItem;
      LChildItem.ParentEntry := LMovedItem;
      AEntry.ChildEntries[0] := nil;
    end;

    {Set the new right child for the moved item}
    LChildItem := AEntry.ChildEntries[1];
    if LChildItem <> nil then
    begin
      LMovedItem.ChildEntries[1] := LChildItem;
      LChildItem.ParentEntry := LMovedItem;
      AEntry.ChildEntries[1] := nil;
    end;

  end
  else
  begin
    {The deleted item is a leaf item:  Remove it from the tree directly.}
    AEntry.ParentEntry.ChildEntries[LRemovedItemChildIndex] := nil;
  end;
  {Reset the parent for the removed item.}
  AEntry.ParentEntry := nil;
end;

function TReturnAddressInfoCache.FindEntry(AReturnAddress: NativeUInt): PReturnAddressInfo;
var
  LAddressBits: NativeUInt;
  LParentItem: PReturnAddressInfo;
begin
  LAddressBits := AReturnAddress;
  LParentItem := @Entries[0];
  {Step down the tree until the item is found or there is no child item in the required direction.}
  while True do
  begin
    {Get the child item in the required direction.}
    Result := LParentItem.ChildEntries[LAddressBits and 1];
    {If there is no child, or the child's key value matches the search key value then we're done.}
    if (Result = nil)
      or (Result.ReturnAddress = AReturnAddress) then
    begin
      Exit;
    end;
    {The child key value is not a match -> Move down the tree.}
    LParentItem := Result;
    LAddressBits := LAddressBits shr 1;
  end;
end;

{--------------------------Stack Tracing Subroutines--------------------------}

{Used by the 32-bit frame based and raw stack tracing routines.}
{$if SizeOf(Pointer) = 4}
procedure GetStackRange(var AStackBaseAddress, ACurrentStackPointer: NativeUInt);
asm
  mov ecx, fs:[4]
  mov [eax], ecx
  mov [edx], ebp
end;
{$ifend}

{--------------------------Frame Based Stack Tracing--------------------------}

{$if SizeOf(Pointer) = 8}

function CaptureStackBackTrace(FramesToSkip, FramesToCapture: DWORD; BackTrace: Pointer; BackTraceHash: PDWORD): Word;
  external kernel32 name 'RtlCaptureStackBackTrace';

{We use the Windows API to do frame based stack tracing under 64-bit.}
procedure GetFrameBasedStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
type
{$PointerMath On}
  PNativeUIntArray = ^NativeUInt;
{$PointerMath Off}
var
  LCapturedFrameCount: Cardinal;
begin
  {RtlCaptureStackBackTrace includes the frame of this routine, so one more frame is skipped.}
  LCapturedFrameCount := CaptureStackBackTrace(ASkipFrames + 1, AMaxDepth, AReturnAddresses, nil);
  {It returns no frames at all if the stack has to grow while it runs, i.e. if it is called close to the deepest point
  that the stack has reached so far.  The stack has grown by then, so the second attempt succeeds.}
  if LCapturedFrameCount = 0 then
    LCapturedFrameCount := CaptureStackBackTrace(ASkipFrames + 1, AMaxDepth, AReturnAddresses, nil);

  {Clear trailing entries}
  while LCapturedFrameCount < AMaxDepth do
  begin
    PNativeUIntArray(AReturnAddresses)[LCapturedFrameCount] := 0;
    Inc(LCapturedFrameCount);
  end;
end;

{$else}

{Dumps the call stack trace to the given address. Fills the list with the addresses where the called addresses can be
found.  This is the fast stack frame based tracing routine.}
procedure GetFrameBasedStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
var
  LStackTop, LStackBottom, LCurrentFrame: NativeUInt;
begin
  {Get the call stack top and current bottom}
  GetStackRange(LStackTop, LStackBottom);
  {A stack frame is the saved frame pointer followed by the return address, so it must start at least two pointers
  below the top of the stack.}
  Dec(LStackTop, 2 * SizeOf(Pointer) - 1);
  {Get the current frame start}
  LCurrentFrame := LStackBottom;
  {Fill the call stack}
  while (AMaxDepth > 0)
    and (LCurrentFrame >= LStackBottom)
    and (LCurrentFrame < LStackTop) do
  begin
    {Ignore the requested number of levels}
    if ASkipFrames = 0 then
    begin
      AReturnAddresses^ := PNativeUInt(LCurrentFrame + SizeOf(Pointer))^;
      Inc(AReturnAddresses);
      Dec(AMaxDepth);
    end
    else
      Dec(ASkipFrames);
    {Get the next frame}
    LCurrentFrame := PNativeUInt(LCurrentFrame)^;
  end;
  {Clear the remaining entries}
  while AMaxDepth > 0 do
  begin
    AReturnAddresses^ := 0;
    Inc(AReturnAddresses);
    Dec(AMaxDepth);
  end;
end;
{$ifend}

{-----------------------------Raw Stack Tracing-----------------------------}

{$ifdef Win32RawStackTraces}

const
  {The largest size assumed for a function without a stack frame.  A return address on the stack is only accepted as
  the caller of the previous entry if its call goes to a function that starts less than this many bytes before that
  entry.  A larger value would let more return addresses through that earlier calls left on the stack.}
  CMaxFramelessFunctionSize = 4096;
  {Some functions end by jumping to code that lies just before them, e.g. System.@UStrCat3 jumps into System.@UStrCat.
  The previous entry may then lie up to this many bytes before the start of the function that was called.}
  CMaxTailJumpDistance = 256;
  {The target of an indirect call (e.g. CALL EAX) cannot be read from the code, so it cannot be checked.  The return
  address of such a call is only accepted if it is at most this many stack slots above the previous entry.}
  CMaxIndirectCallDistance = 2;
  {A function without a stack frame uses little stack:  The registers it saves, and the parameters it passes on the
  stack.  The return addresses of a chain of such functions therefore lie close together, and the search for the next
  one stops this many bytes above the last entry or the last candidate.  Above that lie the local variables of the
  function that the next stack frame belongs to, which can be large.}
  CMaxFramelessStackUsage = 256;

type
  {The state of a memory page. Used by the raw stack tracing mechanism to determine whether an address is a valid call
  site or not.  mpaModuleData is readable data in the image of a module, e.g. import table entries and global
  variables.  Other readable pages, such as the heap, are mpaNotExecutable.}
  TMemoryPageAccess = (mpaUnknown, mpaNotExecutable, mpaModuleData, mpaExecutable);

var
  {There are a total of 1M x 4K pages in the (low) 4GB address space}
  MemoryPageAccessMap: array[0..1024 * 1024 - 1] of TMemoryPageAccess;
  {Incremented by InvalidateMemoryPageAccessMap before it resets the pages of a DLL that is loaded or unloaded.
  UpdateMemoryPageAccessMap uses it to detect that this happened while it was querying a region, in which case the
  access it found may already be out of date.}
  MemoryPageAccessMapGeneration: Integer;

procedure InvalidateMemoryPageAccessMap(ABaseAddress: Pointer; ASize: NativeUInt);
const
  CPageSize = 4096;
var
  LStartPage, LEndPage: NativeUInt;
  LPageCount: NativeInt;
begin
  if ASize = 0 then
    Exit;

  LStartPage := NativeUInt(ABaseAddress) div CPageSize;
  LEndPage := LStartPage + (ASize - 1) div CPageSize;
  if LEndPage > High(MemoryPageAccessMap) then
    LEndPage := High(MemoryPageAccessMap);

  LPageCount := LEndPage - LStartPage + 1;
  if LPageCount > 0 then
  begin
    {Increment the counter before resetting the pages, so that an UpdateMemoryPageAccessMap call that queried the
    region before the DLL was loaded cannot leave what it found in the map after the reset.}
    AtomicIncrement(MemoryPageAccessMapGeneration);
    FillChar(MemoryPageAccessMap[LStartPage], LPageCount, Ord(mpaUnknown));
  end;
end;

{Queries the region of memory that contains the address, and records in the memory page access map whether its pages
are executable, or readable data in the image of a module.  If a DLL is loaded or unloaded while the region is being
queried, the pages are left as mpaUnknown instead, so that they are queried again when next needed.  Returns the
address of the last byte of the region.  Only supports the low 4GB of address space.}
function UpdateMemoryPageAccessMap(AAddress: NativeUInt): NativeUInt;
var
  LMemInfo: TMemoryBasicInformation;
  LAccess: TMemoryPageAccess;
  LStartPage, LPageCount: NativeUInt;
  LGeneration: Integer;
begin
  LGeneration := MemoryPageAccessMapGeneration;

  {Query the page}
  if VirtualQuery(Pointer(AAddress), LMemInfo, SizeOf(LMemInfo)) <> 0 then
  begin
    {Get access type}
    LAccess := mpaNotExecutable;
    if (LMemInfo.State = MEM_COMMIT)
      and (LMemInfo.Protect and PAGE_GUARD = 0) then
    begin
      if LMemInfo.Protect and (PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY or PAGE_EXECUTE) <> 0 then
        LAccess := mpaExecutable
      else if (LMemInfo.Type_9 = MEM_IMAGE)
        and (LMemInfo.Protect and (PAGE_READONLY or PAGE_READWRITE or PAGE_WRITECOPY) <> 0) then
      begin
        LAccess := mpaModuleData;
      end;
    end;
    {Update the map}
    LStartPage := NativeUInt(LMemInfo.BaseAddress) div 4096;
    LPageCount := LMemInfo.RegionSize div 4096;
    if LStartPage < NativeUInt(Length(MemoryPageAccessMap)) then
    begin
      if (LStartPage + LPageCount) >= NativeUInt(Length(MemoryPageAccessMap)) then
        LPageCount := NativeUInt(Length(MemoryPageAccessMap)) - LStartPage;
      FillChar(MemoryPageAccessMap[LStartPage], LPageCount, Ord(LAccess));

      {If a DLL was loaded or unloaded since the region was queried, what was just recorded may be out of date, e.g.
      the pages of a DLL that was loaded into a free region would be marked as not executable, and since such pages are
      never queried again, the DLL's return addresses would be missing from all later stack traces.  Reset the pages
      instead.  The locked compare also ensures that the counter is not read before the writes above are visible to
      other threads.}
      if AtomicCmpExchange(MemoryPageAccessMapGeneration, LGeneration, LGeneration) <> LGeneration then
        FillChar(MemoryPageAccessMap[LStartPage], LPageCount, Ord(mpaUnknown));
    end;
    Result := NativeUInt(LMemInfo.BaseAddress) + (LMemInfo.RegionSize - 1);
  end
  else
  begin
    {Invalid address}
    MemoryPageAccessMap[AAddress div 4096] := mpaNotExecutable;
    Result := AAddress or 4095;
  end;
end;

{Updates the memory page access map for the memory from AFirstByte to ALastByte, which may lie on two pages.  This is
needed when reading it failed, since the map was then out of date.}
procedure UpdateMemoryPageAccessMapForRange(AFirstByte, ALastByte: NativeUInt);
begin
  {The region that contains the first byte may also contain the last byte.  Only query the last byte if it does not.}
  if UpdateMemoryPageAccessMap(AFirstByte) < ALastByte then
    UpdateMemoryPageAccessMap(ALastByte);
end;

{Thread-safe version that avoids the global variable Default8087CW.}
procedure Set8087CW(ANewCW: Word);
var
  L8087CW: Word;
asm
  mov L8087CW, ANewCW
  fnclex
  fldcw L8087CW
end;

{$if CompilerVersion > 22}
{Thread-safe version that avoids the global variable DefaultMXCSR.}
procedure SetMXCSR(ANewMXCSR: Cardinal);
var
  LMXCSR: Cardinal;
asm
  cmp System.TestSSE, 0
  je @exit
  {Remove the flag bits}
  and ANewMXCSR, $ffc0
  mov LMXCSR, ANewMXCSR
  ldmxcsr LMXCSR
@exit:
end;
{$ifend}

{Returns True if the memory page access map says that the address is executable.  If the map does not know the page
yet, it is queried first.}
function IsExecutable(AAddress: NativeUInt): Boolean; inline;
begin
  if MemoryPageAccessMap[AAddress div 4096] = mpaUnknown then
    UpdateMemoryPageAccessMap(AAddress);
  Result := MemoryPageAccessMap[AAddress div 4096] = mpaExecutable;
end;

{Returns True if the memory from the address to the end of a pointer there is in the image of a module, i.e. code or
readable module data.  That is where calls and jumps through memory read the address that they go to (import table
entries and global variables).}
function IsModulePointer(AAddress: NativeUInt): Boolean;
var
  LLastByte: NativeUInt;
begin
  LLastByte := AAddress + SizeOf(Pointer) - 1;
  if MemoryPageAccessMap[AAddress div 4096] = mpaUnknown then
    UpdateMemoryPageAccessMap(AAddress);
  {If the pointer lies on one page, or the region that was just queried contains both pages, the last byte's page is
  known now.}
  if MemoryPageAccessMap[LLastByte div 4096] = mpaUnknown then
    UpdateMemoryPageAccessMap(LLastByte);
  Result := (MemoryPageAccessMap[AAddress div 4096] in [mpaModuleData, mpaExecutable])
    and (MemoryPageAccessMap[LLastByte div 4096] in [mpaModuleData, mpaExecutable]);
end;

{Returns True if the return address can lie in the function that starts at AFunction.  It can if it is less than
AMaxOffset bytes after the start of the function, or less than ATailJumpDistance bytes before it.  (The latter is for
a function that ends by jumping to code that lies just before it.)}
function IsInFunction(AReturnAddress, AFunction, AMaxOffset, ATailJumpDistance: NativeUInt): Boolean; inline;
begin
  if AReturnAddress > AFunction then
    Result := AReturnAddress - AFunction < AMaxOffset
  else
    Result := AFunction - AReturnAddress < ATailJumpDistance;
end;

type
  {The state of a stack trace by TraceLiveReturnAddresses, with the routines it uses.  An "entry" is a return address
  in the stack trace, and a "slot" is the stack address that a value was read from.}
  TTraceLiveReturnAddressesState = record
    {Where the next entry goes, the number of entries that are still to be filled in, and the number of entries that
    are still to be skipped.}
    ReturnAddresses: PNativeUInt;
    MaxDepth, SkipFrames: Cardinal;
    {Stack addresses below this one can be read.}
    StackTop: NativeUInt;
    {The last entry, and its slot.}
    Entry, EntrySlot: NativeUInt;
    {The floating point control words on entry.  Reading code can cause an access violation, and the RTL then resets
    the control words to the defaults of this DLL, which may differ from those of the application (QC 107198).  The
    exception handlers restore these values.}
    Saved8087CW: Word;
    SavedMXCSR: Cardinal;
    {Values on the stack below the last entry that point further up the stack.  Some of them are saved frame pointers.
    The stack below CollectedTo has already been searched for them.}
    CollectedTo: NativeUInt;
    FramePointerCount: Integer;
    FramePointers: array[0..255] of NativeUInt;
    {The candidates for the next entry, lowest first, with their slots:  Return addresses after indirect calls (e.g.
    CALL EAX) that lie more than CMaxIndirectCallDistance slots above the last entry.  An indirect call does not tell
    where it goes, so it cannot be checked whether it went into the function of the last entry.  It can be checked
    from further up the stack instead:  If the call before the next return address up the call chain goes into the
    function of a candidate, that candidate is the next entry.  AddEntry clears the list.}
    CandidateCount: Integer;
    CandidateReturnAddresses, CandidateSlots: array[0..15] of NativeUInt;
    {Adds an entry, or skips it if entries are still to be skipped.  Either way it becomes the last entry.}
    procedure AddEntry(AReturnAddress, ASlot: NativeUInt);
    {Returns True if the bytes just before the return address form a call instruction.  Only safe to call while
    exceptions are being handled.}
    function IsValidCallSite(AReturnAddress: NativeUInt): Boolean;
    {Gets the address that the call instruction before the return address calls, following up to two jump thunks.
    ATarget is 0 if the code does not tell, e.g. for CALL EAX.  Returns False if the call cannot have been made:  A
    call through memory (CALL [$12345678]) reads the address it goes to from an import table entry or a global
    variable, which are in the image of a module, and if that memory is not there or not readable the call would
    have crashed.  The return address must be a valid call site.  Only safe to call while exceptions are being
    handled.}
    function GetCallTarget(AReturnAddress: NativeUInt; out ATarget: NativeUInt): Boolean;
    {Returns True if there is a stack frame at the address, and the address is above the last entry.  A stack frame is
    a saved EBP that is 0 or points further up the stack, followed by a valid return address.}
    function IsFrame(AAddress: NativeUInt): Boolean;
    {Returns the lowest stack frame above the last entry that a value below the last entry points to, or 0 if there is
    none.}
    function FindNearestFrame: NativeUInt;
    {If a candidate lies in the function that starts at AFunction, adds the lowest one as the next entry and returns
    True.}
    function AddCandidateInFunction(AFunction: NativeUInt): Boolean;
    {Adds the return address in the slot as the next entry if the call before it goes into the function of the last
    entry.  If the call goes into the function of a candidate instead, that candidate is added first.  The return
    address of an indirect call is added if it is at most CMaxIndirectCallDistance slots above the last entry, and
    otherwise becomes a candidate.  Returns True if an entry was added.}
    function AddCallerOfLastEntry(ASlot: NativeUInt): Boolean;
  end;

procedure TTraceLiveReturnAddressesState.AddEntry(AReturnAddress, ASlot: NativeUInt);
begin
  if SkipFrames = 0 then
  begin
    ReturnAddresses^ := AReturnAddress;
    Inc(ReturnAddresses);
    Dec(MaxDepth);
  end
  else
    Dec(SkipFrames);
  Entry := AReturnAddress;
  EntrySlot := ASlot;
  {The candidates were for the entry after the previous one.}
  CandidateCount := 0;
end;

function TTraceLiveReturnAddressesState.IsValidCallSite(AReturnAddress: NativeUInt): Boolean;
var
  LCallAddress: NativeUInt;
  LCode8Back, LCode4Back, LTemp: Cardinal;
begin
  {The first 64K of address space is never allocated.}
  if AReturnAddress <= $ffff then
    Exit(False);

  {A call instruction is at most 8 bytes long, and it ends just before the return address.  Both the first byte it can
  start at and its last byte must be executable.}
  LCallAddress := AReturnAddress - 8;
  if not (IsExecutable(LCallAddress) and IsExecutable(AReturnAddress - 1)) then
    Exit(False);

  {Try to determine what kind of call it is (if any), more or less in order of frequency of occurrence. (Code below
  taken from the Jedi Code Library (jcl.sourceforge.net).)}
  try
    {5 bytes, CALL NEAR REL32}
    if PByteArray(LCallAddress)[3] = $E8 then
    begin
      Result := True;
      Exit;
    end;
    {Get the 4 bytes before the return address}
    LCode4Back := PCardinal(LCallAddress + 4)^;
    {2 byte call?}
    LTemp := LCode4Back and $F8FF0000;
    {2 bytes, CALL NEAR EAX}
    if LTemp = $D0FF0000 then
    begin
      Result := True;
      Exit;
    end;
    {2 bytes, CALL NEAR [EAX].  The encodings for [ESP] and [EBP] do not count:  They mean that a SIB byte or a 32-bit
    address follows, so the instruction would be longer.}
    if LTemp = $10FF0000 then
    begin
      LTemp := LCode4Back and $07000000;
      if (LTemp <> $04000000) and (LTemp <> $05000000) then
      begin
        Result := True;
        Exit;
      end;
    end;
    {3 bytes, CALL NEAR [EAX+EAX*i].  A SIB byte with EBP as the base does not count:  It means that a 32-bit
    displacement follows, so the instruction would be longer.}
    if ((LCode4Back and $00FFFF00) = $0014FF00)
      and ((LCode4Back and $07000000) <> $05000000) then
    begin
      Result := True;
      Exit;
    end;
    {3 bytes, CALL NEAR [EAX+$12]}
    if ((LCode4Back and $00F8FF00) = $0050FF00)
      and ((LCode4Back and $00070000) <> $00040000) then
    begin
      Result := True;
      Exit;
    end;
    {4 bytes, CALL NEAR [EAX+EAX+$12]}
    if Word(LCode4Back) = $54FF then
    begin
      Result := True;
      Exit;
    end;
    {6 bytes, CALL NEAR [$12345678]}
    LCode8Back := PCardinal(LCallAddress)^;
    if (LCode8Back and $FFFF0000) = $15FF0000 then
    begin
      Result := True;
      Exit;
    end;
    {6 bytes, CALL NEAR [EAX+$12345678]}
    if ((LCode8Back and $F8FF0000) = $90FF0000)
      and ((LCode8Back and $07000000) <> $04000000) then
    begin
      Result := True;
      Exit;
    end;
    {7 bytes, CALL NEAR [EAX+EAX+$1234567]}
    if (LCode8Back and $00FFFF00) = $0094FF00 then
    begin
      Result := True;
      Exit;
    end;
    {7 bytes, CALL NEAR [EAX*i+$12345678]:  A SIB byte without a base register (which is encoded as EBP), followed by
    a 32-bit displacement.}
    if (LCode8Back and $07FFFF00) = $0514FF00 then
    begin
      Result := True;
      Exit;
    end;
    {Direct far calls (CALL FAR $1234:12345678) are not accepted.  32-bit Windows code does not use them.  A check for
    them would pass for about one in 256 code addresses, as often as the check for CALL NEAR REL32 does, so it would
    let many code pointers on the stack through that are not return addresses.}
    {Not a valid call site}
    Result := False;
  except
    {Reading the code failed, so the memory page access map was out of date for it.}
    UpdateMemoryPageAccessMapForRange(LCallAddress, AReturnAddress - 1);
    {The RTL sets the FPU control words to the default values if an external exception occurs.  Reset them to the
    values on entry to the stack trace.}
    Set8087CW(Saved8087CW);
    SetMXCSR(SavedMXCSR);
    {Not executable}
    Result := False;
  end;
end;

function TTraceLiveReturnAddressesState.GetCallTarget(AReturnAddress: NativeUInt; out ATarget: NativeUInt): Boolean;
var
  LJumpCount: Integer;
  LPointerAddress: NativeUInt;
  {The memory that is being read:  The call instruction before the return address, the address that a call or jump
  through memory reads, or a jump thunk.  If reading it fails, the exception handler updates the memory page access
  map for it.}
  LReadFirstByte, LReadLastByte: NativeUInt;
begin
  ATarget := 0;
  Result := False;
  LReadFirstByte := AReturnAddress - 8;
  LReadLastByte := AReturnAddress - 1;
  try
    if PByte(AReturnAddress - 5)^ = $E8 then
    begin
      {5 bytes, CALL NEAR REL32}
      ATarget := AReturnAddress + NativeUInt(PInteger(AReturnAddress - 4)^);
    end
    else if PWord(AReturnAddress - 6)^ = $15FF then
    begin
      {6 bytes, CALL NEAR [$12345678]:  A call through an import table entry or a global variable.  If the address is
      not in the image of a module, this is not a call that was made.}
      LPointerAddress := PNativeUInt(AReturnAddress - 4)^;
      if not IsModulePointer(LPointerAddress) then
        Exit;
      LReadFirstByte := LPointerAddress;
      LReadLastByte := LPointerAddress + SizeOf(Pointer) - 1;
      ATarget := PNativeUInt(LPointerAddress)^;
    end;
    {The call can have been made.  For any other kind of call, e.g. CALL EAX, the code does not tell where it goes, so
    ATarget stays 0.}
    Result := True;
    {Follow JMP REL32 and JMP [$12345678] thunks, e.g. those that the linker generates for imported functions.}
    for LJumpCount := 1 to 2 do
    begin
      if (ATarget = 0)
        or not (IsExecutable(ATarget) and IsExecutable(ATarget + 5)) then
      begin
        Break;
      end;
      LReadFirstByte := ATarget;
      LReadLastByte := ATarget + 5;
      if PByte(ATarget)^ = $E9 then
        ATarget := ATarget + 5 + NativeUInt(PInteger(ATarget + 1)^)
      else if PWord(ATarget)^ = $25FF then
      begin
        {A jump through memory, which is only followed if the address that it reads is in the image of a module.}
        LPointerAddress := PNativeUInt(ATarget + 2)^;
        if not IsModulePointer(LPointerAddress) then
          Break;
        LReadFirstByte := LPointerAddress;
        LReadLastByte := LPointerAddress + SizeOf(Pointer) - 1;
        ATarget := PNativeUInt(LPointerAddress)^;
      end
      else
        Break;
    end;
  except
    {Reading failed, so the memory page access map was out of date for that memory.}
    UpdateMemoryPageAccessMapForRange(LReadFirstByte, LReadLastByte);
    {The RTL sets the FPU control words to the default values if an external exception occurs, so reset them to the
    values on entry to the stack trace.}
    Set8087CW(Saved8087CW);
    SetMXCSR(SavedMXCSR);
    ATarget := 0;
    Result := False;
  end;
end;

function TTraceLiveReturnAddressesState.IsFrame(AAddress: NativeUInt): Boolean;
var
  LSavedFrame: NativeUInt;
begin
  {The address is any value that was found on the stack, so the check against the top of the stack must not add to
  it:  For $FFFFFFFC the sum would wrap around to 0.}
  if (AAddress <= EntrySlot)
    or (AAddress >= StackTop - SizeOf(Pointer))
    or (AAddress and (SizeOf(Pointer) - 1) <> 0) then
  begin
    Exit(False);
  end;

  LSavedFrame := PNativeUInt(AAddress)^;
  if (LSavedFrame <> 0)
    and ((LSavedFrame <= AAddress) or (LSavedFrame >= StackTop)) then
  begin
    Exit(False);
  end;

  Result := IsValidCallSite(PNativeUInt(AAddress + SizeOf(Pointer))^);
end;

function TTraceLiveReturnAddressesState.FindNearestFrame: NativeUInt;
var
  LPointer: NativeUInt;
  LIndex, LKeptCount: Integer;
begin
  {Collect the values below the last entry that point further up the stack.  Over the whole stack trace, each stack
  address is only read once.}
  while CollectedTo < EntrySlot do
  begin
    LPointer := PNativeUInt(CollectedTo)^;
    if (LPointer > CollectedTo)
      and (LPointer < StackTop)
      and (FramePointerCount < Length(FramePointers)) then
    begin
      FramePointers[FramePointerCount] := LPointer;
      Inc(FramePointerCount);
    end;
    Inc(CollectedTo, SizeOf(Pointer));
  end;

  {Find the lowest frame among them.  Pointers to below the last entry will not be needed again, since the last entry
  only moves up the stack, so they are dropped.}
  Result := 0;
  LKeptCount := 0;
  for LIndex := 0 to FramePointerCount - 1 do
  begin
    LPointer := FramePointers[LIndex];
    if LPointer > EntrySlot then
    begin
      FramePointers[LKeptCount] := LPointer;
      Inc(LKeptCount);
      if ((Result = 0) or (LPointer < Result))
        and IsFrame(LPointer) then
      begin
        Result := LPointer;
      end;
    end;
  end;
  FramePointerCount := LKeptCount;
end;

function TTraceLiveReturnAddressesState.AddCandidateInFunction(AFunction: NativeUInt): Boolean;
var
  LIndex: Integer;
begin
  for LIndex := 0 to CandidateCount - 1 do
  begin
    if IsInFunction(CandidateReturnAddresses[LIndex], AFunction, CMaxFramelessFunctionSize, CMaxTailJumpDistance) then
    begin
      AddEntry(CandidateReturnAddresses[LIndex], CandidateSlots[LIndex]);
      Exit(True);
    end;
  end;
  Result := False;
end;

function TTraceLiveReturnAddressesState.AddCallerOfLastEntry(ASlot: NativeUInt): Boolean;
var
  LReturnAddress, LCallTarget: NativeUInt;
begin
  LReturnAddress := PNativeUInt(ASlot)^;
  if not (IsValidCallSite(LReturnAddress)
    and GetCallTarget(LReturnAddress, LCallTarget)) then
  begin
    Exit(False);
  end;

  if LCallTarget = 0 then
  begin
    {An indirect call:  Further up than CMaxIndirectCallDistance slots it becomes a candidate.}
    if ASlot - EntrySlot > CMaxIndirectCallDistance * SizeOf(Pointer) then
    begin
      if CandidateCount < Length(CandidateReturnAddresses) then
      begin
        CandidateReturnAddresses[CandidateCount] := LReturnAddress;
        CandidateSlots[CandidateCount] := ASlot;
        Inc(CandidateCount);
      end;
      Exit(False);
    end;
  end
  else if not IsInFunction(Entry, LCallTarget, CMaxFramelessFunctionSize, CMaxTailJumpDistance) then
  begin
    {The call does not go into the function of the last entry.  If it goes into the function of a candidate, the
    candidate is the next entry, and this return address the one after it.}
    if not AddCandidateInFunction(LCallTarget) then
      Exit(False);
    if MaxDepth = 0 then
      Exit(True);
  end;

  AddEntry(LReturnAddress, ASlot);
  Result := True;
end;

{Fills the list with the return addresses of the current call chain, starting with the return address of the stack
frame at AFrame.  The entries that are not needed are set to 0.

It is not good enough to scan the stack for values that look like return addresses:  Local variables often still hold
the return addresses of earlier calls.  Instead, every entry is shown to be part of the current call chain before it is
added.  The first entry is the return address of the frame at AFrame.  After that, the next entries are found from the
last entry in three steps:
  1. Find the next stack frame up the stack.  It belongs to the function that the last entry returns into, or, if that
     function has no stack frame, to its nearest caller that has one.
     - If the function that was called from the last entry has a stack frame, the slot just below the last entry holds
       its saved EBP, which points to the next frame.
     - Otherwise, take the lowest frame above the last entry that some value below the last entry points to.  Every
       value below the last entry belongs to the current call chain, and a function without a stack frame that uses
       EBP for something else saves EBP on the stack first.  (FastMM's own code does this, which is why EBP does not
       point to a stack frame when FastMM asks for a stack trace.)
  2. Between the last entry and the next frame lie the return addresses of calls into functions without a stack frame.
     A return address there is accepted if the call before it goes to the function of the last entry.  For an indirect
     call the target is not known.  Its return address is accepted if it is at most CMaxIndirectCallDistance slots
     above the last entry.  Otherwise it becomes a candidate, which is accepted, before the return address above it,
     if the call before that return address goes into the candidate's function.  The search stops
     CMaxFramelessStackUsage bytes above the last entry or the last candidate.  If the next frame belongs to the
     function of the last entry itself, there is nothing to look for:  That is the case if the frame's return address
     follows a call into that function.
  3. The next frame's return address is the next entry.  It follows a call into the function that the next frame
     belongs to, so a candidate in that function is accepted first.
If there is no next frame, the next entry is the first return address above the last entry that passes the test in
step 2.  The stack trace ends when there is none.}
procedure TraceLiveReturnAddresses(AFrame, AStackTop: NativeUInt; AReturnAddresses: PNativeUInt;
  AMaxDepth, ASkipFrames: Cardinal);
var
  LState: TTraceLiveReturnAddressesState;
  LNextFrame, LNextFrameFunction, LLimit, LSlot, LValue, LLastFound: NativeUInt;
  LFound: Boolean;
begin
  {The first entry is added unconditionally below, so with no room for any entry it would be written past the end of
  the list, and MaxDepth would wrap around.}
  if AMaxDepth = 0 then
    Exit;

  LState.ReturnAddresses := AReturnAddresses;
  LState.MaxDepth := AMaxDepth;
  LState.SkipFrames := ASkipFrames;
  LState.StackTop := AStackTop;
  LState.Saved8087CW := Get8087CW;
  LState.SavedMXCSR := GetMXCSR;
  LState.CollectedTo := AFrame;
  LState.FramePointerCount := 0;
  LState.AddEntry(PNativeUInt(AFrame + SizeOf(Pointer))^, AFrame + SizeOf(Pointer));

  while LState.MaxDepth > 0 do
  begin
    {Step 1:  Find the next frame.}
    LNextFrame := PNativeUInt(LState.EntrySlot - SizeOf(Pointer))^;
    if not LState.IsFrame(LNextFrame) then
      LNextFrame := LState.FindNearestFrame;

    {Step 2:  Look for the callers of functions without a stack frame below the next frame.  Without a next frame, look
    for the next entry anywhere above the last entry.}
    LNextFrameFunction := 0;
    if LNextFrame <> 0 then
    begin
      LLimit := LNextFrame;
      {The function that the next frame belongs to, if the call before its return address tells.}
      if not LState.GetCallTarget(PNativeUInt(LNextFrame + SizeOf(Pointer))^, LNextFrameFunction) then
        LNextFrameFunction := 0;
      if (LNextFrameFunction <> 0)
        and IsInFunction(LState.Entry, LNextFrameFunction, CMaxFramelessFunctionSize, 0) then
      begin
        LLimit := LState.EntrySlot;
      end;
    end
    else
      LLimit := AStackTop;
    LFound := False;
    LSlot := LState.EntrySlot + SizeOf(Pointer);
    while (LState.MaxDepth > 0)
      and (LSlot < LLimit) do
    begin
      {Most values on the stack are not return addresses.  The memory page access map rules most of them out much faster
      than the check for a call site.}
      LValue := PNativeUInt(LSlot)^;
      if (LValue > $ffff)
        and (MemoryPageAccessMap[(LValue - 1) div 4096] <> mpaNotExecutable)
        and LState.AddCallerOfLastEntry(LSlot) then
      begin
        LFound := True;
        {Without a next frame, start again from the last entry:  A next frame may be found from it.}
        if LNextFrame = 0 then
          Break;
      end
      else if LNextFrame <> 0 then
      begin
        LLastFound := LState.EntrySlot;
        if LState.CandidateCount > 0 then
          LLastFound := LState.CandidateSlots[LState.CandidateCount - 1];
        if LSlot - LLastFound >= CMaxFramelessStackUsage then
          Break;
      end;
      Inc(LSlot, SizeOf(Pointer));
    end;

    {Step 3:  The next frame's return address is the next entry.  A candidate in the function that the next frame
    belongs to is the return address of the call that function made, so it comes first.}
    if LNextFrame <> 0 then
    begin
      if (LState.MaxDepth > 0)
        and (LNextFrameFunction <> 0) then
      begin
        LState.AddCandidateInFunction(LNextFrameFunction);
      end;
      if LState.MaxDepth > 0 then
        LState.AddEntry(PNativeUInt(LNextFrame + SizeOf(Pointer))^, LNextFrame + SizeOf(Pointer));
    end
    else if not LFound then
      Break;
  end;

  {Clear the remaining entries}
  while LState.MaxDepth > 0 do
  begin
    LState.ReturnAddresses^ := 0;
    Inc(LState.ReturnAddresses);
    Dec(LState.MaxDepth);
  end;
end;

{Dumps the call stack trace to the given address.  Fills the list with the addresses where the called addresses can be
found.  This is the "raw" stack tracing routine.  Unlike the frame based one, it also finds the callers of functions
without a stack frame, and it works even if EBP does not point to a stack frame when it is called.}
procedure GetRawStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
var
  LStackTop, LStackBottom: NativeUInt;
  LLastOSError: Cardinal;
begin
  {Are exceptions being handled?  Can only do a raw stack trace if the possible access violations are going to be
  handled.}
  if Assigned(ExceptObjProc) then
  begin
    {Save the last Windows error code}
    LLastOSError := GetLastError;
    {Get the top of the stack and the stack frame of this routine.  The stack trace starts with the return address of
    this routine.}
    GetStackRange(LStackTop, LStackBottom);
    TraceLiveReturnAddresses(LStackBottom, LStackTop - (SizeOf(Pointer) - 1), AReturnAddresses, AMaxDepth, ASkipFrames);
    {Restore the last Windows error code, since a VirtualQuery call may have modified it.}
    SetLastError(LLastOSError);
  end
  else
  begin
    {Exception handling is not available - do a frame based stack trace}
    GetFrameBasedStackTrace(AReturnAddresses, AMaxDepth, ASkipFrames);
  end;
end;

{$else}

{$IFDEF MSWINDOWS}
{Without raw stack tracing there is no memory page access map, so there is nothing to do.  The routine is still
exported, so that all the DLLs have the same exports.}
procedure InvalidateMemoryPageAccessMap(ABaseAddress: Pointer; ASize: NativeUInt);
begin
end;
{$ENDIF}

{$endif}

{Under macOS the raw stack trace comes from backtrace, for both 32-bit and 64-bit code.}
{$IFDEF MACOS}
function backtrace(Result: PNativeUInt; size: Integer): Integer; cdecl; external libc name '_backtrace';
function _NSGetExecutablePath(buf: PAnsiChar; BufSize: PCardinal): Integer; cdecl; external libc name '__NSGetExecutablePath';

{Dumps the call stack trace to the given address.  Fills the list with the addresses where the called addresses can be
found.  This is the "raw" stack tracing routine.}
procedure GetRawStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
var
  StackLog: PNativeUInt; //array[0..10] of Pointer;
  Cnt: Integer;
  I: Integer;
begin
  {$POINTERMATH ON}
  Cnt := AMaxDepth + ASkipFrames;

  GetMem(StackLog, SizeOf(Pointer) * Cnt);
  try
    Cnt := backtrace(StackLog, Cnt);

    for I := ASkipFrames to Cnt - 1 do
    begin
//      writeln('Stack: ', inttohex(NativeUInt(stacklog[I]), 8));
      AReturnAddresses[I - ASkipFrames] := StackLog[I];
    end;

  finally
    FreeMem(StackLog);
  end;
  {$POINTERMATH OFF}
end;
{$ENDIF}

{--------------------------DLL load and unload notifications--------------------------}

{The memory page access map used by raw stack tracing is invalidated whenever a DLL is loaded or unloaded.}
{$ifdef Win32RawStackTraces}

type

  UNICODE_STRING = record
    Length: Word;
    MaximumLength: Word;
    Buffer: PWideChar;
  end;
  PUNICODE_STRING = ^UNICODE_STRING;

  TCLDR_DLL_NOTIFICATION_DATA = record
    Flags: Cardinal;                //Reserved.
    FullDllName: PUNICODE_STRING;   //The full path name of the DLL module.
    BaseDllName: PUNICODE_STRING;   //The base file name of the DLL module.
    DllBase: Pointer;               //A pointer to the base address for the DLL in memory.
    SizeOfImage: Cardinal;          //The size of the DLL image, in bytes.
  end;
  PCLDR_DLL_NOTIFICATION_DATA = ^TCLDR_DLL_NOTIFICATION_DATA;

  TLdrDllNotification = procedure(NotificationReason: Cardinal; NotificationData: PCLDR_DLL_NOTIFICATION_DATA;
    Context: Pointer); stdcall;

  TLdrRegisterDllNotification = function(Flags: Cardinal; NotificationFunction: TLdrDllNotification;
    Context: Pointer; var Cookie: Pointer): LongInt; stdcall;

  TLdrUnregisterDllNotification = function(Cookie: Pointer): LongInt; stdcall;

procedure LdrDllNotification(NotificationReason: Cardinal; NotificationData: PCLDR_DLL_NOTIFICATION_DATA;
  Context: Pointer); stdcall;
begin
  InvalidateMemoryPageAccessMap(NotificationData.DllBase, NotificationData.SizeOfImage);
end;

var
  DllNotificationCookie: Pointer = nil;

procedure RegisterDLLLoadAndUnloadNotifications;
var
  LdrRegisterDllNotification: TLdrRegisterDllNotification;
begin
  if DllNotificationCookie <> nil then
    Exit;

  {Attempt to register notifications when a DLL is loaded or unloaded.}
  LdrRegisterDllNotification := GetProcAddress(GetModuleHandle('NTDLL.DLL'), 'LdrRegisterDllNotification');
  if Assigned(LdrRegisterDllNotification) then
  begin
    if LdrRegisterDllNotification(0, LdrDllNotification, nil, DllNotificationCookie) <> ERROR_SUCCESS then
      DllNotificationCookie := nil;
  end;

  if DllNotificationCookie = nil then
    OutputDebugString('FastMM_FullDebugMode: Failed to register DLL load and unload notifications.');
end;

procedure UnregisterDLLLoadAndUnloadNotifications;
var
  LdrUnregisterDllNotification: TLdrUnregisterDllNotification;
begin
  if DllNotificationCookie = nil then
    Exit;

  LdrUnregisterDllNotification := GetProcAddress(GetModuleHandle('NTDLL.DLL'), 'LdrUnregisterDllNotification');
  if Assigned(LdrUnregisterDllNotification)
    and (LdrUnregisterDllNotification(DllNotificationCookie) = ERROR_SUCCESS) then
  begin
    DllNotificationCookie := nil;
  end;

  if DllNotificationCookie <> nil then
    OutputDebugString('FastMM_FullDebugMode: Failed to deregister DLL load and unload notifications.');
end;

procedure DllMain(AReason: Integer);
begin
  if AReason = DLL_PROCESS_DETACH then
    UnregisterDLLLoadAndUnloadNotifications;
end;

{$endif}

{-----------------------------Stack Trace Logging----------------------------}

{Gets the textual representation of the stack trace into ABuffer and returns a pointer to the position just after the
last character.}
{$if defined(JCLDebug) or defined(ModuleAndOffsetOnly)}
{Converts an unsigned integer to a hexadecimal string at the buffer location, returning the new buffer position.}
function NativeUIntToHexBuf(ANum: NativeUInt; APBuffer: PAnsiChar): PAnsiChar;
const
  CHexTable: array[0..15] of AnsiChar = '0123456789ABCDEF';
  CMaxDigits = 16;
var
  LDigitBuffer: array[0..CMaxDigits - 1] of AnsiChar;
  LCount: Cardinal;
  LDigit: NativeUInt;
begin
  {Generate the digits in the local buffer}
  LCount := 0;
  repeat
    LDigit := ANum;
    ANum := ANum div 16;
    LDigit := LDigit - ANum * 16;
    Inc(LCount);
    LDigitBuffer[CMaxDigits - LCount] := CHexTable[LDigit];
  until ANum = 0;
  {Add leading zeros}
  while LCount < SizeOf(NativeUInt) * 2 do
  begin
    Inc(LCount);
    LDigitBuffer[CMaxDigits - LCount] := '0';
  end;
  {Copy the digits to the output buffer and advance it}
  System.Move(LDigitBuffer[CMaxDigits - LCount], APBuffer^, LCount);
  Result := APBuffer + LCount;
end;

{Appends the info text for a return address to the output of LogStackTrace, converted to ANSI text.  It is cut off at
CMaxInfoTextLength bytes, since FastMM's buffer only has room for 256 characters per stack trace entry.}
function AppendInfoTextA(APInfoText: PChar; AInfoTextLength: Integer; APBuffer: PAnsiChar): PAnsiChar;
var
  LInfoText: string;
  LAnsiInfoText: AnsiString;
  LLength: Integer;
begin
  SetString(LInfoText, APInfoText, AInfoTextLength);
  LAnsiInfoText := AnsiString(LInfoText);
  LLength := Length(LAnsiInfoText);
  if LLength > CMaxInfoTextLength then
    LLength := CMaxInfoTextLength;
  System.Move(Pointer(LAnsiInfoText)^, APBuffer^, LLength);
  Result := APBuffer + LLength;
end;

{Appends as much of the text as fits into the output buffer of LogStackTraceW, returning the new buffer position.}
function AppendToBufferW(APText: PWideChar; ALength: Integer; APBuffer, APBufferEnd: PWideChar): PWideChar;
begin
  if ALength > APBufferEnd - APBuffer then
    ALength := Integer(APBufferEnd - APBuffer);
  if ALength > 0 then
  begin
    System.Move(APText^, APBuffer^, ALength * SizeOf(WideChar));
    Inc(APBuffer, ALength);
  end;
  Result := APBuffer;
end;

{Appends the line break and the return address in hexadecimal that start every stack trace entry to the output buffer
of LogStackTraceW, returning the new buffer position.}
function AppendAddressW(AAddress: NativeUInt; APBuffer, APBufferEnd: PWideChar): PWideChar;
var
  LAnsiText: array[0..SizeOf(NativeUInt) * 2 + 1] of AnsiChar;
  LText: array[0..SizeOf(NativeUInt) * 2 + 1] of WideChar;
  LLength, i: Integer;
begin
  LAnsiText[0] := #13;
  LAnsiText[1] := #10;
  LLength := Integer(NativeUIntToHexBuf(AAddress, @LAnsiText[2]) - PAnsiChar(@LAnsiText));
  for i := 0 to LLength - 1 do
    LText[i] := WideChar(LAnsiText[i]);
  Result := AppendToBufferW(@LText, LLength, APBuffer, APBufferEnd);
end;
{$ifend}

{$ifdef JCLDebug}
{Subroutine used by LogStackTrace}
procedure AppendInfoToString(var AString: string; const AInfo: string);
begin
  if AInfo <> '' then
    AString := Format('%s[%s]', [AString, AInfo]);
end;

var
  LReturnAddressInfoCache: TReturnAddressInfoCache;
  LLogStackTrace_Locked: Integer; //0 = unlocked, 1 = locked

{LogStackTrace and LogStackTraceW are protected by a lock - only one thread can be inside them at any given time.}
procedure BeginLogStackTrace;
begin
  while AtomicCmpExchange(LLogStackTrace_Locked, 1, 0) <> 0 do
    Winapi.Windows.SwitchToThread;
end;

{Releases the JCL's location info cache if GetReturnAddressInfo used it, and the lock.}
procedure EndLogStackTrace(ALocationCacheInitialized: Boolean);
begin
  if ALocationCacheInitialized then
  begin
    {$if declared(BeginGetLocationInfoCache)} // available depending on the JCL's version
    EndGetLocationInfoCache;
    {$endif}
  end;

  LLogStackTrace_Locked := 0;
end;

{Returns the cache entry with the info text for the return address, adding it to the cache if it is not there yet.
The caller must hold the lock (BeginLogStackTrace).}
function GetReturnAddressInfo(AAddress: NativeUInt; var ALocationCacheInitialized: Boolean): PReturnAddressInfo;
var
  LInfo: TJCLLocationInfo;
  LTempStr: string;
  P: PChar;
begin
  Result := LReturnAddressInfoCache.FindEntry(AAddress);
  if Result <> nil then
    Exit;

  if not ALocationCacheInitialized then
  begin
    {$if declared(BeginGetLocationInfoCache)} // available depending on the JCL's version
    BeginGetLocationInfoCache;
    {$endif}
    ALocationCacheInitialized := True;
  end;
  {Get location info for the caller (at least one byte before the return address).}
  GetLocationInfo(Pointer(AAddress - 1), LInfo);
  {Build the result string}
  LTempStr := ' ';
  AppendInfoToString(LTempStr, LInfo.SourceName);
  AppendInfoToString(LTempStr, LInfo.UnitName);

  {Remove UnitName from ProcedureName, no need to output it twice}
  P := PChar(LInfo.ProcedureName);
  if (StrLComp(P, PChar(LInfo.UnitName), Length(LInfo.UnitName)) = 0) and (P[Length(LInfo.UnitName)] = '.') then
    AppendInfoToString(LTempStr, Copy(LInfo.ProcedureName, Length(LInfo.UnitName) + 2))
  else
    AppendInfoToString(LTempStr, LInfo.ProcedureName);

  if LInfo.LineNumber <> 0 then
    AppendInfoToString(LTempStr, IntToStr(LInfo.LineNumber));

  Result := LReturnAddressInfoCache.AddEntry(AAddress, LTempStr);
end;

function LogStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal; ABuffer: PAnsiChar): PAnsiChar;
var
  LInd: Cardinal;
  LAddress: NativeUInt;
  LLocationCacheInitialized: Boolean;
  LPInfo: PReturnAddressInfo;
begin
  LLocationCacheInitialized := False;

  Result := ABuffer;

  BeginLogStackTrace;
  try
    {Counted from 1:  With "0 to AMaxDepth - 1" the bound would wrap around for AMaxDepth = 0.}
    for LInd := 1 to AMaxDepth do
    begin
      LAddress := AReturnAddresses^;
      if LAddress = 0 then
        Exit;
      Result^ := #13;
      Inc(Result);
      Result^ := #10;
      Inc(Result);
      Result := NativeUIntToHexBuf(LAddress, Result);

      LPInfo := GetReturnAddressInfo(LAddress, LLocationCacheInitialized);
      Result := AppendInfoTextA(@LPInfo.InfoText, LPInfo.InfoTextLength, Result);

      Inc(AReturnAddresses);
    end;
  finally
    EndLogStackTrace(LLocationCacheInitialized);
  end;
end;

{The same as LogStackTrace, but the text is Unicode text, and it is cut off at APBufferEnd.}
function LogStackTraceW(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
  APBuffer, APBufferEnd: PWideChar): PWideChar;
var
  LInd: Cardinal;
  LAddress: NativeUInt;
  LLocationCacheInitialized: Boolean;
  LPInfo: PReturnAddressInfo;
begin
  LLocationCacheInitialized := False;

  Result := APBuffer;

  BeginLogStackTrace;
  try
    for LInd := 1 to AMaxDepth do
    begin
      LAddress := AReturnAddresses^;
      if (LAddress = 0) or (Result >= APBufferEnd) then
        Exit;
      Result := AppendAddressW(LAddress, Result, APBufferEnd);

      LPInfo := GetReturnAddressInfo(LAddress, LLocationCacheInitialized);
      Result := AppendToBufferW(@LPInfo.InfoText, LPInfo.InfoTextLength, Result, APBufferEnd);

      Inc(AReturnAddresses);
    end;
  finally
    EndLogStackTrace(LLocationCacheInitialized);
  end;
end;
{$endif}

{$ifdef ModuleAndOffsetOnly}
{Describes the return address by the name of the module containing it and its offset in that module, e.g.
" [MyApp.exe+1A2B3C]", or returns '' if it is not in a loaded module.  The offset can be looked up in the map file of
the module, after subtracting the address of the code section (usually $1000).}
function GetModuleAndOffsetInfoText(AAddress: NativeUInt): string;
var
  LMemInfo: TMemoryBasicInformation;
  LModuleFileName: array[0..MAX_PATH] of Char;
begin
  {Find the module containing the call instruction, which is at least one byte before the return address.  The image
  of a module is a single allocation, so the allocation base is the module handle.  The memory must be part of a
  loaded image:  For the address of a DLL that has since been unloaded, VirtualQuery returns MEM_FREE with an
  AllocationBase of nil, and GetModuleFileName(0) would return the name of the executable.}
  if (VirtualQuery(Pointer(AAddress - 1), LMemInfo, SizeOf(LMemInfo)) <> 0)
    and (LMemInfo.State = MEM_COMMIT)
    and (LMemInfo.Type_9 = MEM_IMAGE)
    and (GetModuleFileName(HMODULE(LMemInfo.AllocationBase), LModuleFileName, Length(LModuleFileName)) <> 0) then
  begin
    Result := Format(' [%s+%x]', [ExtractFileName(LModuleFileName), AAddress - NativeUInt(LMemInfo.AllocationBase)]);
  end
  else
    Result := '';
end;

{Describes each return address by module and offset (see GetModuleAndOffsetInfoText).}
function LogStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal; ABuffer: PAnsiChar): PAnsiChar;
var
  LInd: Cardinal;
  LAddress: NativeUInt;
  LInfoText: string;
begin
  Result := ABuffer;

  for LInd := 1 to AMaxDepth do
  begin
    LAddress := AReturnAddresses^;
    if LAddress = 0 then
      Exit;
    Result^ := #13;
    Inc(Result);
    Result^ := #10;
    Inc(Result);
    Result := NativeUIntToHexBuf(LAddress, Result);

    LInfoText := GetModuleAndOffsetInfoText(LAddress);
    Result := AppendInfoTextA(PChar(LInfoText), Length(LInfoText), Result);

    Inc(AReturnAddresses);
  end;
end;

{The same as LogStackTrace, but the text is Unicode text, and it is cut off at APBufferEnd.}
function LogStackTraceW(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
  APBuffer, APBufferEnd: PWideChar): PWideChar;
var
  LInd: Cardinal;
  LAddress: NativeUInt;
  LInfoText: string;
begin
  Result := APBuffer;

  for LInd := 1 to AMaxDepth do
  begin
    LAddress := AReturnAddresses^;
    if (LAddress = 0) or (Result >= APBufferEnd) then
      Exit;
    Result := AppendAddressW(LAddress, Result, APBufferEnd);

    LInfoText := GetModuleAndOffsetInfoText(LAddress);
    Result := AppendToBufferW(PChar(LInfoText), Length(LInfoText), Result, APBufferEnd);

    Inc(AReturnAddresses);
  end;
end;
{$endif}

{$ifdef madExcept}
function LogStackTrace(AReturnAddresses: PNativeUInt;
  AMaxDepth: Cardinal; ABuffer: PAnsiChar): PAnsiChar;
begin
  {Needs madExcept 2.7i or madExcept 3.0a or a newer build}
  Result := madStackTrace.FastMM_LogStackTrace(
    AReturnAddresses,
    AMaxDepth,
    ABuffer,
    {madExcept stack trace fine tuning}
    False, //hide items which have no line number information?
    True,  //show relative address offset to procedure entrypoint?
    True,  //show relative line number offset to procedure entry point?
    False  //skip special noise reduction processing?
    );
end;
{$endif}

{$ifdef EurekaLog_Legacy}
function LogStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
  ABuffer: PAnsiChar): PAnsiChar;
begin
  {Needs EurekaLog 5 or 6}
  Result := ExceptionLog.FastMM_LogStackTrace(
    AReturnAddresses, AMaxDepth, ABuffer,
    {EurekaLog stack trace fine tuning}
    False, // Show the DLLs functions call.  <--|
           //                                   |-- See the note below!
    False, // Show the BPLs functions call.  <--|
    True  // Show relative line no. offset to procedure start point.
    );
// NOTE:
// -----
// With these values set both to "False", EurekaLog try to returns the best
// call-stack available.
//
// To do this EurekaLog execute the following points:
// --------------------------------------------------
// 1)...try to fill all call-stack items using only debug data with line no.
// 2)...if remains some empty call-stack items from the previous process (1),
//      EurekaLog try to fill these with the BPLs functions calls;
// 3)...if remains some empty call-stack items from the previous process (2),
//      EurekaLog try to fill these with the DLLs functions calls;
end;
{$endif}

{$ifdef EurekaLog_V7}
function LogStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal; ABuffer: PAnsiChar): PAnsiChar;
begin
  {Needs EurekaLog 7 or later.  FastMM's buffer has room for 256 characters per stack trace entry, so the size is
  based on the number of entries:  A fixed size would cut off the text of deeper stack traces.}
  Result := EFastMM4Support.FastMM_LogStackTrace(PPointer(AReturnAddresses), AMaxDepth, ABuffer, AMaxDepth * 256,
    [ddUnit, ddProcedure, ddSourceCode], True, False, False, True, False, True);
end;
{$endif}

{$IFDEF MACOS}

{Appends the source text to the destination and returns the new destination position}
function AppendStringToBuffer(const ASource, ADestination: PAnsiChar; ACount: Cardinal): PAnsiChar;
begin
  System.Move(ASource^, ADestination^, ACount);
  Result := Pointer(PByte(ADestination) + ACount);
end;

var
  MapFile: TSBMapFile;

function LogStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal; ABuffer: PAnsiChar): PAnsiChar;
var
  s1: AnsiString;
  I: Integer;
  FileName: array[0..255] of AnsiChar;
  Len: Cardinal;
begin
  {$POINTERMATH ON}
//  writelN('LogStackTrace');
//  for I := 0 to AMaxDepth - 1 do
//    Writeln(IntToHex(AReturnAddresses[I], 8));

//  s1 := IntToHex(Integer(AReturnAddresses[0]), 8);
//  result := ABuffer;
//  Move(pointer(s1)^, result^, Length(s1));
//  inc(result, Length(s1));

  if MapFile = nil then
  begin
    MapFile := TSBMapFile.Create;
    Len := Length(FileName);
    _NSGetExecutablePath(@FileName[0], @Len);
    if FileExists(ChangeFileExt(FileName, '.map')) then
      MapFile.LoadFromFile(ChangeFileExt(FileName, '.map'));
  end;

  Result := ABuffer;

  s1 := #13#10;
  Result := AppendStringToBuffer(PAnsiChar(s1), Result, Length(s1));

  for I := 0 to AMaxDepth - 1 do
  begin
    s1 := IntToHex(AReturnAddresses[I], 8);
    s1 := s1 + ' ' + MapFile.GetFunctionName(AReturnAddresses[I]) + #13#10;
    Result := AppendStringToBuffer(PAnsiChar(s1), Result, Length(s1));
  end;

  {$POINTERMATH OFF}
end;
{$ENDIF}

{-----------------------------Exported Functions----------------------------}

exports
  GetFrameBasedStackTrace,
{$if defined(Win32RawStackTraces) or defined(MACOS)}
  GetRawStackTrace,
{$else}
  GetFrameBasedStackTrace name 'GetRawStackTrace',
{$ifend}
{$IFDEF MSWINDOWS}
  InvalidateMemoryPageAccessMap,
{$ENDIF}
{The other stack tracing libraries only produce ANSI text, so for them FastMM converts the text of LogStackTrace.}
{$if defined(JCLDebug) or defined(ModuleAndOffsetOnly)}
  LogStackTraceW,
{$ifend}
  LogStackTrace;

begin
{$ifdef JCLDebug}
  JclStackTrackingOptions := JclStackTrackingOptions + [stAllModules];
{$endif}

{$ifdef Win32RawStackTraces}

  {When this DLL is unloaded we need to unregister DLL load and unload notifications.}
  DLLProc := DllMain;

  {The memory map used by the stack tracing code must be updated whenever a DLL is loaded or unloaded.}
  RegisterDLLLoadAndUnloadNotifications;

{$endif}

end.
