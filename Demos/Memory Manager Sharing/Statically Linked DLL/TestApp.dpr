program TestApp;

{$APPTYPE CONSOLE}

uses
  FastMMInitSharing,
  System.Classes;

{Note that TestLibrary.dll is statically linked, so it will be initialized before the main application.  This means the
main application will actually be sharing the memory manager of the DLL.  (If TestLibrary was loaded dynamically then
it would be sharing the memory manager of the main application.)

Sharing the memory manager with a statically linked library also has implications for debug mode:  Since the unload
order of dynamicaly loaded DLLs is not always predictable, the FastMM_FullDebugMode.dll library may end up being
unloaded before TestLibrary.dll if the debug library is loaded dynamically, causing an A/V when TestLibrary.dll runs its
leak reporting code.  When sharing the memory manager with statically linked libraries it is therefore recommended to
statically link to FastMM_FullDebugMode.dll as well (if debug mode is required) via the
FastMM_DebugLibraryStaticDependency define.}
procedure LeakMemory; external 'TestLibrary';

begin
  {Leak a TPersistent in the main application}
  TPersistent.Create;
  {Leak a TObject in the library}
  LeakMemory;
end.
