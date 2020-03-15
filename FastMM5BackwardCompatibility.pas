{FastMM5 backward compatibility options.  Sets FastMM5 options based on FastMM4 conditional defines.}

unit FastMM5BackwardCompatibility;

interface

uses
  FastMM5;

implementation

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

  {$ifdef FullDebugMode}
  FastMM_EnterDebugMode;
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
