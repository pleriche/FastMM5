// JCL_DEBUG_EXPERT_INSERTJDBG ON
program ShareMemDemo;

{$APPTYPE CONSOLE}

uses
  System.ShareMem,
  System.Classes;

procedure LeakMemory; external 'TestLibrary';

begin
  {Leak memory in the library}
  LeakMemory;

  {Leak memory in the main application.}
  TPersistent.Create;

end.
