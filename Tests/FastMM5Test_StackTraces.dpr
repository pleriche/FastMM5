{Stack traces from the debug support library (FastMM_FullDebugMode.dll,
 FastMM_FullDebugMode64.dll):  the raw and the frame based stack trace must both
 report a known call chain, in order and with nothing in between, and FastMM5
 must record that call chain in the allocation and free stack traces of a debug
 block.

 The 64-bit build of this program is based above 4GB.  The raw stack trace of the
 64-bit library used to only consider return addresses below 4GB, so it came back
 empty for code based above 4GB, and it never included the frames of the system
 libraries, which 64-bit Windows loads above 4GB.  The 64-bit only checks below
 guard that.

 Parameter:  the path of the debug support library.  Without it the library is
 loaded by its default name, i.e. from the directory of this program or the
 search path.  RunTests.ps1 builds the library into a directory of its own and
 passes its path, so that the other tests do not load it when they enter debug
 mode.}

program FastMM5Test_StackTraces;

{$APPTYPE CONSOLE}

{The 32-bit frame based stack trace follows the chain of stack frames.}
{$StackFrames on}

{$if SizeOf(Pointer) = 8}
{$IMAGEBASE $140000000}
{$ifend}

uses
  FastMM5,
  {$if CompilerVersion >= 23}Winapi.Windows{$else}Windows{$ifend},
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend},
  FastMM_TestUtils in 'FastMM_TestUtils.pas';

const
  CMaxDepth = 32;
  {A medium block:  a freed small block may be handed out again by the next
   allocation of its size before its free stack trace has been read.}
  CBlockSize = 50000;

type
  TGetStackTrace = procedure(APReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
  TStackTrace = array[0..CMaxDepth - 1] of NativeUInt;
  {The return addresses of the call chain, innermost first:  into Level3, into
   Level2, into Level1 and into the routine that called Level1.  Each routine in
   the chain records its own return address, so the expected values come from
   the compiler and not from a stack walk.}
  TCallChain = array[0..3] of NativeUInt;

var
  GLibraryPath: string;
  {What Level3 calls at the end of the call chain.}
  GAction: procedure;
  GChain: TCallChain;
  GGetStackTrace: TGetStackTrace;
  GTrace: TStackTrace;
  GBlock: Pointer;

{-------------------------- The call chain --------------------------}

procedure Level3;
begin
  GChain[1] := NativeUInt(ReturnAddress);
  GAction;
end;

procedure Level2;
begin
  GChain[2] := NativeUInt(ReturnAddress);
  Level3;
end;

procedure Level1;
begin
  GChain[3] := NativeUInt(ReturnAddress);
  Level2;
end;

{The actions at the end of the call chain.}

procedure CaptureStackTrace;
begin
  GChain[0] := NativeUInt(ReturnAddress);
  FillChar(GTrace, SizeOf(GTrace), 0);
  GGetStackTrace(@GTrace[0], CMaxDepth, 0);
end;

procedure AllocateBlock;
begin
  GChain[0] := NativeUInt(ReturnAddress);
  GetMem(GBlock, CBlockSize);
end;

procedure FreeBlock;
begin
  GChain[0] := NativeUInt(ReturnAddress);
  FreeMem(GBlock);
end;

{Runs the call chain from a callback of a system library, so that the stack
 trace has to pass through the frames of that library to get back here.}
function LocaleCallback(ALocaleString: PChar): BOOL; stdcall;
begin
  Level1;
  {Stop the enumeration after the first locale.}
  Result := False;
end;

procedure RunCallChainFromSystemCallback;
begin
  EnumSystemLocales(@LocaleCallback, LCID_INSTALLED);
end;

{-------------------------- Helpers --------------------------}

function Header(APointer: Pointer): PFastMM_DebugBlockHeader;
begin
  Result := PFastMM_DebugBlockHeader(PAnsiChar(APointer) - SizeOf(TFastMM_DebugBlockHeader));
end;

{Returns the module containing the call instruction before the return address,
 or 0 if there is none.  The image of a module is a single allocation, so the
 allocation base is the module handle.}
function ModuleOf(AReturnAddress: NativeUInt): HMODULE;
var
  LMemInfo: TMemoryBasicInformation;
begin
  if (AReturnAddress > 1)
    and (VirtualQuery(Pointer(AReturnAddress - 1), LMemInfo, SizeOf(LMemInfo)) <> 0)
    and (LMemInfo.State = MEM_COMMIT) then
  begin
    Result := HMODULE(LMemInfo.AllocationBase);
  end
  else
    Result := 0;
end;

{Returns the index at which the call chain starts in the stack trace, or -1 if
 the stack trace does not contain the whole call chain in order.}
function FindCallChain(const ATrace: array of NativeUInt; const AChain: TCallChain): Integer;
var
  i, j: Integer;
begin
  for i := 0 to Length(ATrace) - Length(AChain) do
  begin
    j := 0;
    while (j <= High(AChain)) and (ATrace[i + j] = AChain[j]) do
      Inc(j);
    if j > High(AChain) then
    begin
      Result := i;
      Exit;
    end;
  end;
  Result := -1;
end;

{Returns the index of the first entry at or after AStart that is in a module
 other than this program, or -1 if there is none.}
function FindEntryOutsideThisProgram(const ATrace: array of NativeUInt; AStart: Integer): Integer;
var
  i: Integer;
  LModule: HMODULE;
begin
  for i := AStart to High(ATrace) do
  begin
    LModule := ModuleOf(ATrace[i]);
    if (LModule <> 0) and (LModule <> HInstance) then
    begin
      Result := i;
      Exit;
    end;
  end;
  Result := -1;
end;

function FindEntryInThisProgram(const ATrace: array of NativeUInt; AStart: Integer): Integer;
var
  i: Integer;
begin
  for i := AStart to High(ATrace) do
  begin
    if ModuleOf(ATrace[i]) = HInstance then
    begin
      Result := i;
      Exit;
    end;
  end;
  Result := -1;
end;

function TraceContainsModule(const ATrace: array of NativeUInt; AModule: HMODULE): Boolean;
var
  i: Integer;
begin
  for i := 0 to High(ATrace) do
  begin
    if ModuleOf(ATrace[i]) = AModule then
    begin
      Result := True;
      Exit;
    end;
  end;
  Result := False;
end;

{Prints the stack trace with module and offset, so that a failure can be
 diagnosed from the log.}
procedure DumpStackTrace(const ATrace: array of NativeUInt; const AChain: TCallChain);
var
  i: Integer;
  LModule: HMODULE;
  LModuleName: array[0..MAX_PATH] of Char;
  LText: string;
begin
  Info(Format('Expected call chain:  %x %x %x %x', [AChain[0], AChain[1], AChain[2], AChain[3]]));
  for i := 0 to High(ATrace) do
  begin
    if ATrace[i] = 0 then
      Break;
    LModule := ModuleOf(ATrace[i]);
    if (LModule <> 0) and (GetModuleFileName(LModule, LModuleName, Length(LModuleName)) <> 0) then
      LText := Format('%s+%x', [ExtractFileName(LModuleName), ATrace[i] - LModule])
    else
      LText := '(not in a module)';
    Info(Format('%2d  %x  %s', [i, ATrace[i], LText]));
  end;
end;

{-------------------------- The tests --------------------------}

procedure TestLibraryStackTrace(const AName: string; AGetStackTrace: TGetStackTrace);
var
  LFailures: Integer;
{$if SizeOf(Pointer) = 8}
  LIndex: Integer;
{$ifend}
begin
  Section(AName);
  Check(Assigned(AGetStackTrace), 'the library exports ' + AName);
  if not Assigned(AGetStackTrace) then
    Exit;
  GGetStackTrace := AGetStackTrace;
  GAction := CaptureStackTrace;

  LFailures := FailureCount;
  Level1;
  CheckEqualsInt(1, FindCallChain(GTrace, GChain),
    'the call chain is reported in order, directly after the first entry');
  Check(ModuleOf(GTrace[0]) = HInstance, 'the first entry is in this program, not in the library');
{$if SizeOf(Pointer) = 8}
  Check(TraceContainsModule(GTrace, GetModuleHandle(kernel32)),
    'the stack trace continues up to kernel32, which is loaded above 4GB');
{$ifend}
  if FailureCount <> LFailures then
    DumpStackTrace(GTrace, GChain);

  LFailures := FailureCount;
  RunCallChainFromSystemCallback;
  CheckEqualsInt(1, FindCallChain(GTrace, GChain),
    'from a system library callback:  the call chain is reported in order, directly after the first entry');
{$if SizeOf(Pointer) = 8}
  {The call chain ends in LocaleCallback, so the next entries are in the library
   that called it, and after those comes RunCallChainFromSystemCallback.}
  LIndex := FindEntryOutsideThisProgram(GTrace, 1 + Length(GChain));
  Check(LIndex > 0, 'from a system library callback:  the stack trace includes the frames of the library');
  Check((LIndex > 0) and (FindEntryInThisProgram(GTrace, LIndex) > LIndex),
    'from a system library callback:  the stack trace continues into this program after them');
{$ifend}
  if FailureCount <> LFailures then
    DumpStackTrace(GTrace, GChain);
end;

procedure TestDebugBlockStackTraces(ALibrary: HMODULE);
var
  LAllocationChain, LFreeChain: TCallChain;
  LAllocationTrace, LFreeTrace: TStackTrace;
  LEntryCount, LFailures: Integer;
begin
  Section('FastMM5 debug block stack traces');
  FastMM_DebugSupportLibraryName := PWideChar(GLibraryPath);
  Check(FastMM_EnterDebugMode, 'FastMM_EnterDebugMode succeeds');
  Check(@FastMM_GetStackTrace = GetProcAddress(ALibrary, 'GetRawStackTrace'),
    'FastMM5 uses the raw stack trace of the library');

  GAction := AllocateBlock;
  Level1;
  LAllocationChain := GChain;
  FillChar(LAllocationTrace, SizeOf(LAllocationTrace), 0);
  LEntryCount := Header(GBlock).StackTraceEntryCount;
  if LEntryCount > CMaxDepth then
    LEntryCount := CMaxDepth;
  Move(Header(GBlock).DebugFooter_AllocationStackTracePtr^, LAllocationTrace, LEntryCount * SizeOf(NativeUInt));

  GAction := FreeBlock;
  Level1;
  LFreeChain := GChain;
  {Read the free stack trace straight away, before anything else allocates.}
  FillChar(LFreeTrace, SizeOf(LFreeTrace), 0);
  Move(Header(GBlock).DebugFooter_FreeStackTracePtr^, LFreeTrace, LEntryCount * SizeOf(NativeUInt));

  Check(LEntryCount > Length(LAllocationChain), 'debug blocks have stack traces');

  LFailures := FailureCount;
  Check(FindCallChain(LAllocationTrace, LAllocationChain) > 0,
    'the allocation stack trace contains the call chain, in order');
  if FailureCount <> LFailures then
    DumpStackTrace(LAllocationTrace, LAllocationChain);

  LFailures := FailureCount;
  Check(FindCallChain(LFreeTrace, LFreeChain) > 0,
    'the free stack trace contains the call chain, in order');
  if FailureCount <> LFailures then
    DumpStackTrace(LFreeTrace, LFreeChain);

  Check(FastMM_ExitDebugMode, 'FastMM_ExitDebugMode succeeds');
end;

var
  GLibrary: HMODULE;

begin
  TestsBegin('FastMM5 debug support library stack traces');

  if ParamCount >= 1 then
    GLibraryPath := ParamStr(1)
  else
    GLibraryPath := CFastMM_DefaultDebugSupportLibraryName;

{$if SizeOf(Pointer) = 8}
  Info(Format('This program is loaded at %x', [NativeUInt(HInstance)]));
  Check(NativeUInt(HInstance) > $FFFFFFFF, 'this program is loaded above 4GB');
{$ifend}

  GLibrary := LoadLibrary(PChar(GLibraryPath));
  Check(GLibrary <> 0, 'the debug support library loads:  ' + GLibraryPath);
  if GLibrary <> 0 then
  begin
    TestLibraryStackTrace('GetRawStackTrace', GetProcAddress(GLibrary, 'GetRawStackTrace'));
    TestLibraryStackTrace('GetFrameBasedStackTrace', GetProcAddress(GLibrary, 'GetFrameBasedStackTrace'));
    TestDebugBlockStackTraces(GLibrary);
  end;

  TestsEnd;
end.
