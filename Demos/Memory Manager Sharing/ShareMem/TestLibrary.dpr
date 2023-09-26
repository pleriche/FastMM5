{This sample library exports a single call that will leak a TObject.}

// JCL_DEBUG_EXPERT_INSERTJDBG ON
library TestLibrary;

uses
  System.ShareMem;

procedure LeakMemory;
begin
  TObject.Create;
end;

exports LeakMemory;

begin
end.
