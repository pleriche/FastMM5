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

exports
  GetAllocMemSize name 'GetAllocMemSize',
  GetAllocMemCount name 'GetAllocMemCount',
  FastMM_GetHeapStatus name 'GetHeapStatus',
  DumpBlocks name 'DumpBlocks',
  System.ReallocMemory name 'ReallocMemory',
  System.FreeMemory name 'FreeMemory',
  System.GetMemory name 'GetMemory',
  FastMM_ReallocMem name '@Borlndmm@SysReallocMem$qqrpvi',
  FastMM_FreeMem name '@Borlndmm@SysFreeMem$qqrpv',
  FastMM_GetMem name '@Borlndmm@SysGetMem$qqri',
  FastMM_AllocMem name '@Borlndmm@SysAllocMem$qqri',
  FastMM_RegisterExpectedMemoryLeak(ALeakedPointer: Pointer) name '@Borlndmm@SysRegisterExpectedMemoryLeak$qqrpi',
  FastMM_UnregisterExpectedMemoryLeak(ALeakedPointer: Pointer) name '@Borlndmm@SysUnregisterExpectedMemoryLeak$qqrpi',
  HeapRelease name '@Borlndmm@HeapRelease$qqrv',
  HeapAddRef name '@Borlndmm@HeapAddRef$qqrv';

end.
