{This sample library exports a single call that will leak a TObject.}

library TestLibrary;

uses
  FastMMInitSharing;

procedure LeakMemory;
begin
  TObject.Create;
end;

exports LeakMemory;

begin
  ReportMemoryLeaksOnShutdown := True;
end.
