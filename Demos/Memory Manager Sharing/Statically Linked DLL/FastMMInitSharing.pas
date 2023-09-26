{Important note:  This has to be the first unit in the DPR, because memory managers cannot be switched once memory has
been allocated, and the initialization sections of other units are likely to allocate memory.}

unit FastMMInitSharing;


interface


uses
  FastMM5;


implementation

initialization
  {First try to share this memory manager.  This will fail if another module is already sharing its memory manager.  In
  case of the latter, try to use the memory manager shared by the other module.}
  if not FastMM_ShareMemoryManager then
    FastMM_AttemptToUseSharedMemoryManager;
end.
