{

Replacement BorlndMM.DLL using FastMM5

Description:
  A replacement borlndmm.dll using FastMM5 instead of the RTL memory manager.  This DLL may be used instead of the
  default DLL together with your own applications, exposing the benefits of using FastMM5 to them.

Usage:
  1) Compile this DLL
  2) Ship it with your applications that currently use the borlndmm.dll file that ships with Delphi.

}

{$IMAGEBASE $00D20000}

// JCL_DEBUG_EXPERT_INSERTJDBG ON
library BorlndMM;

uses
  FastMM5 in '..\FastMM5.pas',
  {System.SysUtils is needed for exception handling.}
  System.SysUtils;

{$R *.RES}

function GetAllocMemCount: Integer;
begin
  Result := 0;
end;

function GetAllocMemSize: Integer;
begin
  Result := 0;
end;

procedure DumpBlocks;
begin
  {Do nothing}
end;

function HeapRelease: Integer;
begin
  {Do nothing}
  Result := 2;
end;

function HeapAddRef: Integer;
begin
  {Do nothing}
  Result := 2;
end;

function FastMM_GetOutputDebugStringEvents: TFastMM_MemoryManagerEventTypeSet;
begin
  Result := FastMM_OutputDebugStringEvents;
end;

procedure FastMM_SetOutputDebugStringEvents(AEventTypes: TFastMM_MemoryManagerEventTypeSet);
begin
  FastMM_OutputDebugStringEvents := AEventTypes;
end;

function FastMM_GetLogToFileEvents: TFastMM_MemoryManagerEventTypeSet;
begin
  Result := FastMM_LogToFileEvents;
end;

procedure FastMM_SetLogToFileEvents(AEventTypes: TFastMM_MemoryManagerEventTypeSet);
begin
  FastMM_LogToFileEvents := AEventTypes;
end;

function FastMM_GetMessageBoxEvents: TFastMM_MemoryManagerEventTypeSet;
begin
  Result := FastMM_MessageBoxEvents;
end;

procedure FastMM_SetMessageBoxEvents(AEventTypes: TFastMM_MemoryManagerEventTypeSet);
begin
  FastMM_MessageBoxEvents := AEventTypes;
end;

{$ifdef DEBUG}
{The debug support library must be statically linked in order to prevent it from being unloaded before the leak check
can be performed.}
function LogStackTrace(AReturnAddresses: PNativeUInt; AMaxDepth: Cardinal; ABuffer: PAnsiChar): PAnsiChar;
  external {$if SizeOf(Pointer) = 4}'FastMM_FullDebugMode.dll'{$else}'FastMM_FullDebugMode64.dll'{$endif}
  name 'LogStackTrace';
{$endif}

exports
  GetAllocMemSize name 'GetAllocMemSize',
  GetAllocMemCount name 'GetAllocMemCount',
  FastMM_GetHeapStatus name 'GetHeapStatus',
  DumpBlocks name 'DumpBlocks',
  System.ReallocMemory name 'ReallocMemory',
  System.FreeMemory name 'FreeMemory',
  System.GetMemory name 'GetMemory',
{$ifdef DEBUG}
  FastMM_DebugReallocMem name '@Borlndmm@SysReallocMem$qqrpvi',
  FastMM_DebugFreeMem name '@Borlndmm@SysFreeMem$qqrpv',
  FastMM_DebugGetMem name '@Borlndmm@SysGetMem$qqri',
  FastMM_DebugAllocMem name '@Borlndmm@SysAllocMem$qqri',
{$else}
  FastMM_ReallocMem name '@Borlndmm@SysReallocMem$qqrpvi',
  FastMM_FreeMem name '@Borlndmm@SysFreeMem$qqrpv',
  FastMM_GetMem name '@Borlndmm@SysGetMem$qqri',
  FastMM_AllocMem name '@Borlndmm@SysAllocMem$qqri',
{$endif}
  FastMM_RegisterExpectedMemoryLeak(ALeakedPointer: Pointer) name '@Borlndmm@SysRegisterExpectedMemoryLeak$qqrpi',
  FastMM_UnregisterExpectedMemoryLeak(ALeakedPointer: Pointer) name '@Borlndmm@SysUnregisterExpectedMemoryLeak$qqrpi',
  HeapRelease name '@Borlndmm@HeapRelease$qqrv',
  HeapAddRef name '@Borlndmm@HeapAddRef$qqrv',
  {Export additional calls in order to make FastMM specific functionality available to the application and/or library.}
  FastMM_WalkBlocks,
  FastMM_ScanDebugBlocksForCorruption,
  FastMM_GetUsageSummary,
  FastMM_LogStateToFile,
  FastMM_EnterMinimumAddressAlignment,
  FastMM_ExitMinimumAddressAlignment,
  FastMM_GetCurrentMinimumAddressAlignment,
  FastMM_SetDefaultEventLogFilename,
  FastMM_SetEventLogFilename,
  FastMM_GetEventLogFilename,
  FastMM_DeleteEventLogFile,
  FastMM_GetOutputDebugStringEvents,
  FastMM_SetOutputDebugStringEvents,
  FastMM_GetLogToFileEvents,
  FastMM_SetLogToFileEvents,
  FastMM_GetMessageBoxEvents,
  FastMM_SetMessageBoxEvents;

begin
{$ifdef DEBUG}
  {Touch LogStackTrace in order to prevent the linker from eliminating the static link to the debug support library.}
  if @LogStackTrace <> nil then
  begin
    FastMM_EnterDebugMode;
    FastMM_MessageBoxEvents := FastMM_MessageBoxEvents + [mmetUnexpectedMemoryLeakDetail, mmetUnexpectedMemoryLeakSummary];
  end;
{$endif}
end.
