program TestApp;

{$APPTYPE CONSOLE}

uses
  FastMMInitSharing,
  System.Classes;

{Note that TestLibrary.dll is statically linked, so it will be initialized before the main application.  This means the
main application will actually be sharing the memory manager of the DLL.  (If TestLibrary was loaded dynamically then
it would be sharing the memory manager of the main application.)}
procedure LeakMemory; external 'TestLibrary';

begin
  {Leak a TPersistent in the main application}
  TPersistent.Create;
  {Leak a TObject in the library}
  LeakMemory;
end.
