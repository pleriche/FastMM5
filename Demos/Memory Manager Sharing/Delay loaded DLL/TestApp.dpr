// JCL_DEBUG_EXPERT_INSERTJDBG ON
program TestApp;

{$APPTYPE CONSOLE}

uses
  FastMMInitSharing,
  System.Classes;

{Note that TestLibrary.dll is delay loaded, so it will be initialized after the main application.  Consequently the
library will be sharing the memory manager of the main application.}
procedure LeakMemory; external 'TestLibrary' delayed;

begin
  ReportMemoryLeaksOnShutdown := True;

  {Leak a TPersistent in the main application}
  TPersistent.Create;
  {Leak a TObject in the library}
  LeakMemory;
end.
