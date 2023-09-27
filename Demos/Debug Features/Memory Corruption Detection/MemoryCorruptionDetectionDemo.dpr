program MemoryCorruptionDetectionDemo;

{$APPTYPE CONSOLE}

uses
  {FastMM5 has to be the first unit in the DPR, otherwise FastMM5 cannot install itself.}
  FastMM5,
  System.SysUtils;

procedure Test;
var
  LPointer: PByte;
begin
  {Allocate a 1 byte memory block.}
  GetMem(LPointer, 1);

  {Write beyond the end of the allocated memory block, thus corrupting the memory pool.}
  LPointer[1] := 0;

  {Now try to free the block.  FastMM will detect that the block has been corrupted and display an error report.  This
  error report will also be logged to a file in the same folder as the application.}
  FreeMem(LPointer);
end;

begin
  {Debug mode enables various consistency checks that will catch most memory corruption issues.  Enabling debug mode
  will attempt to load the FastMM_FullDebugMode.dll library - make sure it is in the same folder, or on the path.  If
  successful, and a map file for the application (or embedded jdbg info) is available, then crash reports will include
  unit and line information that will help with finding the cause of the error.}
  FastMM_EnterDebugMode;

  try
    Test;
  except
    on E: Exception do
      Writeln(E.ClassName, ': ', E.Message);
  end;
end.
