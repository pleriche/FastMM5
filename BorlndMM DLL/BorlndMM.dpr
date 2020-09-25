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

library BorlndMM;

uses
  FastMM5;

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
  HeapAddRef name '@Borlndmm@HeapAddRef$qqrv';

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
