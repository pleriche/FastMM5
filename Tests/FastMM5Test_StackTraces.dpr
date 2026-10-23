{Tests the stack traces of the debug support library (FastMM_FullDebugMode.dll
 and FastMM_FullDebugMode64.dll).

 A known call chain is run, and each routine in it records its own return
 address.  The raw and the frame based stack traces of the library must both
 report these return addresses, in order and with nothing in between.  FastMM5
 must also record the call chain in the allocation and free stack traces of a
 debug block.

 The 64-bit build of this program is based above 4GB.  The 64-bit raw stack
 trace used to ignore return addresses above 4GB, so for this program it came
 back empty.  It also never included the frames of system libraries, which
 64-bit Windows loads above 4GB.  The checks that are only done under 64-bit
 test this.

 The call chain is also run in two harder situations:  From a callback of a
 system library, and from a routine whose local buffer still holds the return
 addresses of earlier calls.  In the stack trace, the call chain must then be
 followed by exactly its callers.  The 32-bit raw stack trace used to report
 everything on the stack that looked like a return address.  Left over return
 addresses then showed up between the callers, and after the callback the stack
 trace could fill up before it got back to this program.  In FastMM5's own stack
 traces this applied to the whole stack, because EBP does not point to a stack
 frame when FastMM5 asks for a stack trace.

 Under 32-bit the call chain is also run through indirect calls (as for virtual
 methods) into routines without a stack frame, which save registers before they
 call on.  The raw stack trace cannot check where an indirect call went, so it
 has to confirm such a return address from the one above it.  See
 RunCallChainThroughIndirectCalls.

 Under 32-bit a stack trace is also taken with -4 in EBP.  FastMM5's routines
 without a stack frame use EBP for other values, and the raw stack trace used to
 read from the address in EBP if it was -4.  See
 CaptureStackTraceWithEbpMinus4.

 Under 64-bit the call chain is also run where the stack has to grow while the
 stack trace is taken.  RtlCaptureStackBackTrace returns no frames at all in
 that case.  See RunCallChainOnGrowingStack.

 Parameter:  The path of the debug support library.  Without it, the library is
 loaded by its default name, i.e. from the directory of this program or from the
 search path.  RunTests.ps1 builds the library into a directory of its own and
 passes its path, so that the other tests do not load it when they enter debug
 mode.}

program FastMM5Test_StackTraces;

{$APPTYPE CONSOLE}

{The routines of the call chain need stack frames:  The 32-bit frame based stack
 trace follows the chain of stack frames.}
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
  {The size of a medium block.  A freed small block could be handed out again by
   the next allocation of its size, before the test has read its free stack
   trace.}
  CBlockSize = 50000;

type
  TGetStackTrace = procedure(APReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
  TStackTrace = array[0..CMaxDepth - 1] of NativeUInt;
  {The return addresses of the call chain, innermost first:  Into Level3, into
   Level2, into Level1, and into the routine that called Level1.  Each routine
   in the chain records its own return address, so the expected values come
   from the compiler, not from walking the stack.}
  TCallChain = array[0..3] of NativeUInt;

var
  GLibraryPath: string;
  {What Level3 calls at the end of the call chain.}
  GAction: procedure;
  GChain: TCallChain;
  GGetStackTrace: TGetStackTrace;
  GTrace: TStackTrace;
  GBlock: Pointer;
  {The return address of the routine that started the call chain, as recorded by
   that routine.  IsCallChainFollowedByCallers checks where it is in the stack
   trace.}
  GOuterCaller: NativeUInt;
  {Keeps the local buffer of RunCallChainOverStaleReturnAddresses from being
   optimised away.}
  GBufferByte: Byte;
{$if SizeOf(Pointer) = 4}
  {The return addresses that RunCallChainThroughIndirectCalls runs the call
   chain through, innermost first, as recorded by the routines themselves.}
  GIndirectCallers: array[0..3] of NativeUInt;
{$ifend}

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

{$if SizeOf(Pointer) = 4}
{$StackFrames off}
{Calls Level1 for RunCallChainThroughIndirectCalls.  It has no stack frame and
 saves registers first, as such routines often do.  The raw stack trace takes a
 return address to be in a routine that is called if it lies less than 4KB after
 its start, or less than 256 bytes before it.  This routine is therefore placed
 well away from the routine that calls it, FramelessCallsIndirectly, so that it
 does not look like a part of it.}
procedure FramelessCallsLevel1;
asm
  push ebx
  push esi
  push edi
  call Level1
  pop edi
  pop esi
  pop ebx
end;
{$StackFrames on}
{$ifend}

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
  GOuterCaller := NativeUInt(ReturnAddress);
  EnumSystemLocales(@LocaleCallback, LCID_INSTALLED);
end;

{Makes calls that leave their return addresses on the stack, in the place where
 the local buffer of RunCallChainOverStaleReturnAddresses will be.}
function LeaveReturnAddressesOnStack(ADepth: Integer): Integer;
begin
  if ADepth > 0 then
    Result := LeaveReturnAddressesOnStack(ADepth - 1) + Length(IntToStr(ADepth))
  else
    Result := 0;
end;

{Runs the call chain from a routine whose local buffer is not initialised, so
 that it still holds the return addresses of earlier calls.}
procedure RunCallChainOverStaleReturnAddresses;
var
  LBuffer: array[0..2047] of Byte;
begin
  GOuterCaller := NativeUInt(ReturnAddress);
  Level1;
  {Use the buffer, so that the compiler keeps it.}
  GBufferByte := LBuffer[Length(LBuffer) div 2];
end;

procedure RunCallChainFromStaleLocals;
begin
  LeaveReturnAddressesOnStack(40);
  RunCallChainOverStaleReturnAddresses;
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

{Returns True if the return address is in a module other than this program.}
function IsCallChainFollowedByCallers_IsInLibrary(AReturnAddress: NativeUInt): Boolean;
var
  LModule: HMODULE;
begin
  LModule := ModuleOf(AReturnAddress);
  Result := (LModule <> 0) and (LModule <> HInstance);
end;

{Returns True if the stack trace contains the call chain, followed by exactly
 its callers up to GOuterCaller:
   - If AThroughLibrary:  First the frames of the system library that called
     back into this program, then the routine that called the library, and then
     GOuterCaller.
   - Otherwise:  GOuterCaller straight after the call chain.
 A return address that an earlier call left on the stack would get in between.}
function IsCallChainFollowedByCallers(const ATrace: array of NativeUInt; AThroughLibrary: Boolean): Boolean;
var
  LIndex: Integer;
begin
  Result := False;
  LIndex := FindCallChain(ATrace, GChain);
  if LIndex < 0 then
    Exit;
  Inc(LIndex, Length(GChain));
  if AThroughLibrary then
  begin
    {The frames of the library (which may span more than one module), at least
     one...}
    if (LIndex > High(ATrace)) or not IsCallChainFollowedByCallers_IsInLibrary(ATrace[LIndex]) then
      Exit;
    while (LIndex <= High(ATrace)) and IsCallChainFollowedByCallers_IsInLibrary(ATrace[LIndex]) do
      Inc(LIndex);
    {...then the routine that called the library.}
    if (LIndex > High(ATrace)) or (ModuleOf(ATrace[LIndex]) <> HInstance) then
      Exit;
    Inc(LIndex);
  end;
  Result := (LIndex <= High(ATrace)) and (ATrace[LIndex] = GOuterCaller);
end;

{Returns True if the stack trace contains the call chain, followed directly by
 the return addresses in ACallers, in order.}
function IsCallChainFollowedBy(const ATrace, ACallers: array of NativeUInt): Boolean;
var
  LIndex, i: Integer;
begin
  Result := False;
  LIndex := FindCallChain(ATrace, GChain);
  if LIndex < 0 then
    Exit;
  Inc(LIndex, Length(GChain));
  for i := 0 to High(ACallers) do
  begin
    if (LIndex + i > High(ATrace)) or (ATrace[LIndex + i] <> ACallers[i]) then
      Exit;
  end;
  Result := True;
end;

{Returns the allocation stack trace of a debug block.}
function AllocationStackTrace(ABlock: Pointer): TStackTrace;
var
  LEntryCount: Integer;
begin
  FillChar(Result, SizeOf(Result), 0);
  LEntryCount := Header(ABlock).StackTraceEntryCount;
  if LEntryCount > CMaxDepth then
    LEntryCount := CMaxDepth;
  Move(Header(ABlock).DebugFooter_AllocationStackTracePtr^, Result, LEntryCount * SizeOf(NativeUInt));
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

{-------------------------- Indirect calls --------------------------}

{$if SizeOf(Pointer) = 4}
{$StackFrames off}

{Calls FramelessCallsLevel1 indirectly.  Has no stack frame, and saves
 registers first.}
procedure FramelessCallsIndirectly;
asm
  push ebx
  push esi
  push edi
  mov eax, offset FramelessCallsLevel1
  call eax
@ReturnAddress:
  mov dword ptr [GIndirectCallers], offset @ReturnAddress
  pop edi
  pop esi
  pop ebx
end;

{Calls FramelessCallsIndirectly directly.  Has no stack frame, and saves
 registers first.}
procedure FramelessCallsDirectly;
asm
  push ebx
  push esi
  push edi
  call FramelessCallsIndirectly
@ReturnAddress:
  mov dword ptr [GIndirectCallers + 4], offset @ReturnAddress
  pop edi
  pop esi
  pop ebx
end;

{Calls FramelessCallsDirectly indirectly.  Has a stack frame.  The registers
 that the routines below save are cleared, so that they cannot look like return
 addresses.}
procedure FrameCallsIndirectly;
asm
  push ebp
  mov ebp, esp
  push ebx
  push esi
  push edi
  xor ebx, ebx
  xor esi, esi
  xor edi, edi
  mov eax, offset FramelessCallsDirectly
  call eax
@ReturnAddress:
  mov dword ptr [GIndirectCallers + 8], offset @ReturnAddress
  mov eax, [ebp + 4]
  mov dword ptr [GIndirectCallers + 12], eax
  pop edi
  pop esi
  pop ebx
  pop ebp
end;

{$StackFrames on}

{Runs the call chain through indirect calls into routines without a stack
 frame, which save registers before they call on:
   RunCallChainThroughIndirectCalls (has a stack frame, calls directly)
   FrameCallsIndirectly (has a stack frame, calls through EAX)
   FramelessCallsDirectly
   FramelessCallsIndirectly (calls through EAX)
   FramelessCallsLevel1
   Level1
 An indirect call does not tell where it goes.  The raw stack trace can only
 tell that the return address after one is part of the call chain from the
 return address above it:  The one after FramelessCallsIndirectly from the
 direct call into FramelessCallsIndirectly, and the one after
 FrameCallsIndirectly from the stack frame of FrameCallsIndirectly, whose return
 address follows a direct call into it.}
procedure RunCallChainThroughIndirectCalls;
begin
  FrameCallsIndirectly;
end;

{Allocates a block at the end of the call chain that
 RunCallChainThroughIndirectCalls runs, and checks that the call chain is
 followed by the routines it was called through in the allocation stack trace.}
procedure CheckAllocationStackTraceThroughIndirectCalls;
var
  LTrace: TStackTrace;
  LFailures: Integer;
begin
  GAction := AllocateBlock;
  RunCallChainThroughIndirectCalls;
  LTrace := AllocationStackTrace(GBlock);
  FreeMem(GBlock);
  LFailures := FailureCount;
  Check(IsCallChainFollowedBy(LTrace, GIndirectCallers), 'through indirect calls:  the allocation stack trace '
    + 'contains the call chain, followed by the routines that it was called through');
  if FailureCount <> LFailures then
    DumpStackTrace(LTrace, GChain);
end;

{$ifend}

{-------------------------- EBP holding -4 --------------------------}

{$if SizeOf(Pointer) = 4}
var
  {The return address of the call to the stack trace in
   CaptureStackTraceWithEbpMinus4.}
  GReturnAddressWithEbpMinus4: NativeUInt;

{$StackFrames off}
{Takes a stack trace with -4 in EBP.  The raw stack trace looks for the first
 stack frame at the address in EBP, which is not a frame pointer when FastMM5
 asks for a stack trace.}
procedure CaptureStackTraceWithEbpMinus4;
asm
  push ebp
  mov ebp, -4
  mov eax, offset GTrace
  mov edx, CMaxDepth
  xor ecx, ecx
  call GGetStackTrace
@ReturnAddress:
  pop ebp
  mov GReturnAddressWithEbpMinus4, offset @ReturnAddress
end;
{$StackFrames on}

{Returns True if the stack trace with -4 in EBP did not raise an exception, and
 starts with the return address of the call to it.}
function IsStackTraceTakenWithEbpMinus4: Boolean;
begin
  FillChar(GTrace, SizeOf(GTrace), 0);
  try
    CaptureStackTraceWithEbpMinus4;
    Result := GTrace[0] = GReturnAddressWithEbpMinus4;
  except
    Result := False;
  end;
end;
{$ifend}

{-------------------------- A growing stack --------------------------}

{$if SizeOf(Pointer) = 8}
var
  {The number of runs of RunCallChainOnGrowingStack in which the stack trace
   contained the call chain.}
  GGrowingStackChainCount: Integer;

{Runs the call chain below a large local buffer, so that it runs deeper than
 the stack of the thread has been before.}
procedure RunCallChainOnGrowingStack_BelowLargeBuffer;
var
  LBuffer: array[0..65535] of Byte;
begin
  Level1;
  {Use the buffer, so that the compiler keeps it.}
  GBufferByte := LBuffer[Length(LBuffer) div 2];
end;

{Uses a little more than 256 bytes of stack per level before it runs the call
 chain.}
procedure RunCallChainOnGrowingStack_Pad(ALevels: Integer);
var
  LBuffer: array[0..255] of Byte;
begin
  if ALevels > 0 then
    RunCallChainOnGrowingStack_Pad(ALevels - 1)
  else
    RunCallChainOnGrowingStack_BelowLargeBuffer;
  GBufferByte := LBuffer[ALevels];
end;

function RunCallChainOnGrowingStack_Thread(AParameter: Pointer): Integer;
begin
  FillChar(GTrace, SizeOf(GTrace), 0);
  RunCallChainOnGrowingStack_Pad(NativeInt(AParameter));
  if FindCallChain(GTrace, GChain) = 1 then
    Inc(GGrowingStackChainCount);
  Result := 0;
end;

{Runs the call chain where the stack has to grow while the stack trace is
 taken, and returns the number of runs in which the stack trace contained it.
 Whether the stack grows during the stack trace depends on where in a page of
 the stack the stack trace starts.  The call chain is therefore run in 16 new
 threads, each time a little deeper.}
function RunCallChainOnGrowingStack: Integer;
var
  LThread: THandle;
  LThreadId: Cardinal;
  i: Integer;
begin
  GGrowingStackChainCount := 0;
  for i := 0 to 15 do
  begin
    LThread := BeginThread(nil, 0, RunCallChainOnGrowingStack_Thread, Pointer(i), 0, LThreadId);
    WaitForSingleObject(LThread, INFINITE);
    CloseHandle(LThread);
  end;
  Result := GGrowingStackChainCount;
end;
{$ifend}

{-------------------------- The tests --------------------------}

procedure TestLibraryStackTrace(const AName: string; AGetStackTrace: TGetStackTrace);
var
  LFailures: Integer;
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
  Check(IsCallChainFollowedByCallers(GTrace, True),
    'from a system library callback:  the call chain is followed by the frames of the library, the routine that '
    + 'called the library and its caller, with nothing in between');
  if FailureCount <> LFailures then
    DumpStackTrace(GTrace, GChain);

  LFailures := FailureCount;
  RunCallChainFromStaleLocals;
  CheckEqualsInt(1, FindCallChain(GTrace, GChain),
    'over stale return addresses:  the call chain is reported in order, directly after the first entry');
  Check(IsCallChainFollowedByCallers(GTrace, False),
    'over stale return addresses:  the call chain is followed by the caller of the routine that ran it');
  if FailureCount <> LFailures then
    DumpStackTrace(GTrace, GChain);

{$if SizeOf(Pointer) = 4}
  Check(IsStackTraceTakenWithEbpMinus4,
    'with -4 in EBP:  the stack trace does not raise an exception, and starts with the return address');
{$ifend}

{$if SizeOf(Pointer) = 8}
  CheckEqualsInt(16, RunCallChainOnGrowingStack,
    'while the stack grows:  the stack trace contains the call chain, in all 16 runs');
{$ifend}
end;

{Allocates a block at the end of the call chain that AScenario runs, and checks
 that the callers follow the call chain in its allocation stack trace.}
procedure CheckAllocationStackTrace(const AWhat: string; AScenario: TProcedure; AThroughLibrary: Boolean);
var
  LTrace: TStackTrace;
  LFailures: Integer;
begin
  GAction := AllocateBlock;
  AScenario;
  LTrace := AllocationStackTrace(GBlock);
  FreeMem(GBlock);
  LFailures := FailureCount;
  if AThroughLibrary then
    Check(IsCallChainFollowedByCallers(LTrace, True), AWhat + ':  the allocation stack trace contains the call '
      + 'chain, followed by the frames of the library, the routine that called the library and its caller')
  else
    Check(IsCallChainFollowedByCallers(LTrace, False), AWhat + ':  the allocation stack trace contains the call '
      + 'chain, followed by the caller of the routine that ran it');
  if FailureCount <> LFailures then
    DumpStackTrace(LTrace, GChain);
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
  LAllocationTrace := AllocationStackTrace(GBlock);
  LEntryCount := Header(GBlock).StackTraceEntryCount;
  if LEntryCount > CMaxDepth then
    LEntryCount := CMaxDepth;

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

  CheckAllocationStackTrace('from a system library callback', RunCallChainFromSystemCallback, True);
  CheckAllocationStackTrace('over stale return addresses', RunCallChainFromStaleLocals, False);
{$if SizeOf(Pointer) = 4}
  CheckAllocationStackTraceThroughIndirectCalls;
{$ifend}

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
