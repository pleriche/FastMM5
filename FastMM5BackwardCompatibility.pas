{FastMM5 backward compatibility options.  Sets FastMM5 options based on FastMM4 conditional defines.}

unit FastMM5BackwardCompatibility;

interface

uses
  FastMM5;

var
  FastMM_DebugSupportLibraryNotAvailableError: PWideChar = 'The debug support library could not be loaded.';

implementation

uses
  System.SysUtils;

initialization
  {$ifdef Align16Bytes}
  FastMM_EnterMinimumAddressAlignment(maa16Bytes);
  {$endif}

  {$ifdef EnableMemoryLeakReporting}
  {$ifdef RequireDebuggerPresenceForLeakReporting}
  if DebugHook <> 0 then
  {$endif}
  begin
    FastMM_LogToFileEvents := FastMM_LogToFileEvents + [mmetUnexpectedMemoryLeakDetail, mmetUnexpectedMemoryLeakSummary];
    FastMM_MessageBoxEvents := FastMM_MessageBoxEvents + [mmetUnexpectedMemoryLeakSummary];
  end;
  {$endif}

  {$ifdef NoMessageBoxes}
  FastMM_MessageBoxEvents := [];
  {$endif}

  {$ifdef FullDebugModeWhenDLLAvailable}
  {$define FullDebugMode}
  {$endif}

  {$ifdef FullDebugMode}
  if FastMM_LoadDebugSupportLibrary then
  begin
    FastMM_EnterDebugMode;
  end
  else
  begin
    {$ifndef FullDebugModeWhenDLLAvailable}
    raise Exception.Create(FastMM_DebugSupportLibraryNotAvailableError);
    {$endif}
  end;
  {$endif}

  {$ifdef ShareMM}
  {$ifndef ShareMMIfLibrary}
  if not IsLibrary then
  {$endif}
    FastMM_ShareMemoryManager;
  {$endif}

  {$ifdef AttemptToUseSharedMM}
  FastMM_AttemptToUseSharedMemoryManager;
  {$endif}

end.
