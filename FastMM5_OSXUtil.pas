unit FastMM5_OSXUtil;

interface

type
  LPCSTR = PAnsiChar;
  LPSTR = PAnsiChar;
  DWORD = Cardinal;
  BOOL = Boolean;

  PSystemTime = ^TSystemTime;
  _SYSTEMTIME = record
    wYear: Word;
    wMonth: Word;
    wDayOfWeek: Word;
    wDay: Word;
    wHour: Word;
    wMinute: Word;
    wSecond: Word;
    wMilliseconds: Word;
  end;
  TSystemTime = _SYSTEMTIME;
  SYSTEMTIME = _SYSTEMTIME;
  SIZE_T = NativeUInt;
  PUINT_PTR = ^UIntPtr;

const
  PAGE_NOACCESS = 1;
  PAGE_READONLY = 2;
  PAGE_READWRITE = 4;
  PAGE_WRITECOPY = 8;
  PAGE_EXECUTE = $10;
  PAGE_EXECUTE_READ = $20;
  PAGE_EXECUTE_READWRITE = $40;
  PAGE_GUARD = $100;
  PAGE_NOCACHE = $200;
  MEM_COMMIT = $1000;
  MEM_RESERVE = $2000;
  MEM_DECOMMIT = $4000;
  MEM_RELEASE = $8000;
  MEM_FREE = $10000;
  MEM_PRIVATE = $20000;
  MEM_MAPPED = $40000;
  MEM_RESET = $80000;
  MEM_TOP_DOWN = $100000;

  EXCEPTION_ACCESS_VIOLATION         = DWORD($C0000005);


//function GetModuleHandleA(lpModuleName: LPCSTR): HMODULE; stdcall;
function GetEnvironmentVariableW(lpName: PWideChar; lpBuffer: PWideChar; nSize: DWORD): DWORD; stdcall; overload;
function DeleteFileA(lpFileName: LPCSTR): BOOL; stdcall;
function VirtualAlloc(lpvAddress: Pointer; dwSize: SIZE_T; flAllocationType, flProtect: DWORD): Pointer; stdcall;
function VirtualFree(lpAddress: Pointer; dwSize, dwFreeType: Cardinal): LongBool; stdcall;

//procedure RaiseException(dwExceptionCode, dwExceptionFlags, nNumberOfArguments: DWORD;
//  lpArguments: PUINT_PTR); stdcall;

type
  PSecurityAttributes = ^TSecurityAttributes;
  _SECURITY_ATTRIBUTES = record
    nLength: DWORD;
    lpSecurityDescriptor: Pointer;
    bInheritHandle: BOOL;
  end;
  TSecurityAttributes = _SECURITY_ATTRIBUTES;
  SECURITY_ATTRIBUTES = _SECURITY_ATTRIBUTES;

const
  GENERIC_READ             = DWORD($80000000);
  GENERIC_WRITE            = $40000000;
  OPEN_ALWAYS = 4;
  FILE_ATTRIBUTE_NORMAL               = $00000080;
  FILE_BEGIN = 0;
  FILE_CURRENT = 1;
  FILE_END = 2;
  INVALID_SET_FILE_POINTER = DWORD(-1);
  FILE_SHARE_READ = $00000001;


procedure GetLocalTime(var lpSystemTime: TSystemTime); stdcall;
function GetTimeMilliSeconds: Int64;
function MilliSecondsToSystemTime(MSecs: Int64): TSystemTime;

function CreateFileUTF8(lpFileName: PAnsiChar; dwDesiredAccess, dwShareMode: DWORD;
  lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD;
  hTemplateFile: THandle): THandle; stdcall;

function SetFilePointer(hFile: THandle; lDistanceToMove: Longint;
  lpDistanceToMoveHigh: PLongInt; dwMoveMethod: DWORD): DWORD; stdcall;

function CloseHandle(hObject: THandle): BOOL; stdcall;
function WriteFile(hFile: THandle; const Buffer; nNumberOfBytesToWrite: Cardinal;
  var lpNumberOfBytesWritten: Cardinal; lpOverlapped: Pointer): Boolean; stdcall;

function StrLCopy(Dest: PWideChar; const Source: PWideChar; MaxLen: Cardinal): PWideChar; overload;


const
  libc        = '/usr/lib/libc.dylib';
  libdl       = '/usr/lib/libdl.dylib';
  libpthread  = '/usr/lib/libpthread.dylib';
  CarbonCoreLib = '/System/Library/Frameworks/CoreServices.framework/CoreServices';
  INVALID_HANDLE_VALUE = Cardinal(-1);

  _PU = '';
{$IF Defined(OSX) and (Defined(CPUX86) or Defined(CPUX64))}
  _INODE_SUFFIX = '$INODE64';
{$ELSE}
  _INODE_SUFFIX = '';
{$ENDIF}

const
  PROT_READ = 1;
  {$EXTERNALSYM PROT_READ}
  PROT_WRITE = 2;
  {$EXTERNALSYM PROT_WRITE}
  PROT_EXEC = 4;
  {$EXTERNALSYM PROT_EXEC}
  PROT_NONE = 0;
  {$EXTERNALSYM PROT_NONE}

  MAP_FIXED = $10;
  {$EXTERNALSYM MAP_FIXED}
  MAP_PRIVATE = 2;
  {$EXTERNALSYM MAP_PRIVATE}
  MAP_SHARED = 1;
  {$EXTERNALSYM MAP_SHARED}

  MAP_FILE  = $0 platform;
  {$EXTERNALSYM MAP_FILE}
  MAP_ANON  = $1000 platform;
  {$EXTERNALSYM MAP_ANON}

  MAP_FAILED  = Pointer(-1);
  {$EXTERNALSYM MAP_FAILED}

  RTLD_LAZY   = 1;             { Lazy function call binding.  }

type
  off_t = Int64;
  pthread_t = Pointer;
  UnsignedWide = UInt64;
  AbsoluteTime = UnsignedWide;
  Nanoseconds = UnsignedWide;

  dev_t = Int32;
  mode_t = UInt16;
  nlink_t = UInt16;
  uid_t = UInt32;
  gid_t = UInt32;
  time_t = LongInt;
  blkcnt_t = Int64;
  blksize_t = Int32;

  _stat = record
    st_dev: dev_t;         // device
    st_mode: mode_t;       // protection
    st_nlink: nlink_t;     // number of hard links
    st_ino: UInt64;        // inode ino64_t
    st_uid: uid_t;         // user ID of owner
    st_gid: gid_t;         // group ID of owner
    st_rdev: dev_t;        // device type (if inode device)
    st_atime: time_t;      // time of last access
    st_atimensec: LongInt;
    st_mtime: time_t;      // time of last modification
    st_mtimensec: LongInt;
    st_ctime: time_t;      // time of last change
    st_ctimensec: LongInt;
    st_birthtime: time_t;  // file creation time
    st_birthtimensec: LongInt;

    st_size: off_t;        // total size, in bytes
    st_blocks: blkcnt_t;   // number of blocks allocated
    st_blksize: blksize_t; // blocksize for filesystem I/O

    st_flags: UInt32;      // user defined flags for file
    st_gen: UInt32;        // file generation number

    __unused1: Int32;
    __unused2: Int64;
    __unused3: Int64;
  end;
  {$EXTERNALSYM _stat}
  P_stat = ^_stat;


(*function malloc(size: size_t): Pointer; cdecl;
  external libc name _PU + 'malloc';
{$EXTERNALSYM malloc} *)

function aligned_alloc(alignment, size: size_t): Pointer; cdecl;
  external libc name _PU + 'aligned_alloc';
{$EXTERNALSYM aligned_alloc}

(*function __malloc(size: size_t): Pointer; cdecl;
  external libc name _PU + 'malloc';
{$EXTERNALSYM __malloc}

function calloc(nelem: size_t; eltsize: size_t): Pointer; cdecl;
  external libc name _PU + 'calloc';

function realloc(P: Pointer; NewSize: size_t): Pointer; cdecl;
  external libc name _PU + 'realloc';       *)

procedure free(p: Pointer); cdecl;
  external libc name _PU + 'free';

function mprotect(Addr: Pointer; Len: size_t; Prot: Integer): Integer; cdecl;
  external libc name _PU + 'mprotect';

function mmap(Addr: Pointer; Len: size_t; Prot: Integer; Flags: Integer;
              FileDes: Integer; Off: off_t): Pointer; cdecl;
  external libc name _PU + 'mmap';

function sched_yield: Integer; cdecl; external libc name _PU + 'sched_yield';

function pthread_self: pthread_t; cdecl; external libpthread name _PU + 'pthread_self';

function UpTime: AbsoluteTime; cdecl; external CarbonCoreLib name _PU + 'UpTime';

function AbsoluteToNanoseconds(absoluteTime: AbsoluteTime): Nanoseconds; cdecl; external CarbonCoreLib name _PU + 'AbsoluteToNanoseconds';

function getenv(Name: MarshaledAString): MarshaledAString; cdecl;
  external libc name _PU + 'getenv';

function remove(Path: MarshaledAString): Integer; cdecl;
  external libc name _PU + 'remove';

function lstat(FileName: MarshaledAString; var StatBuffer: _stat): Integer; cdecl;
  external libc name _PU + 'lstat' + _INODE_SUFFIX;

function dlsym(Handle: NativeUInt; Symbol: MarshaledAString): Pointer; cdecl;
  external libdl name _PU + 'dlsym';

function dlerror: MarshaledAString; cdecl;
  external libdl name _PU + 'dlerror';

function LoadLibrary(ModuleName: PChar): HMODULE;
function FreeLibrary(Module: HMODULE): LongBool;
function GetProcAddress(Module: HMODULE; Proc: PAnsiChar): Pointer;

implementation

uses
  Posix.Stdlib, Posix.Unistd, Posix.SysMman, Posix.Fcntl, Posix.SysStat, Posix.SysTime, Posix.Time, Posix.Errno, Posix.Signal,
  Macapi.Mach;

function CreateFileUTF8(lpFileName: PAnsiChar; dwDesiredAccess, dwShareMode: DWORD;
  lpSecurityAttributes: PSecurityAttributes; dwCreationDisposition, dwFlagsAndAttributes: DWORD;
  hTemplateFile: THandle): THandle; stdcall;
var
  Flags: Integer;
  FileAccessRights: Integer;
begin
//           O_RDONLY        open for reading only
//           O_WRONLY        open for writing only
//           O_RDWR          open for reading and writing
//           O_NONBLOCK      do not block on open or for data to become available
//           O_APPEND        append on each write
//           O_CREAT         create file if it does not exist
//           O_TRUNC         truncate size to 0
//           O_EXCL          error if O_CREAT and the file exists
//           O_SHLOCK        atomically obtain a shared lock
//           O_EXLOCK        atomically obtain an exclusive lock
//           O_NOFOLLOW      do not follow symlinks
//           O_SYMLINK       allow open of symlinks
//           O_EVTONLY       descriptor requested for event notifications only
//          O_CLOEXEC       mark as close-on-exec

  Flags := 0;
  FileAccessRights := S_IRUSR or S_IWUSR or S_IRGRP or S_IWGRP or S_IROTH or S_IWOTH;

  case dwDesiredAccess and (GENERIC_READ or GENERIC_WRITE) of //= (GENERIC_READ or GENERIC_WRITE) then
    GENERIC_READ or GENERIC_WRITE: Flags := Flags or O_RDWR;
    GENERIC_READ: Flags := Flags or O_RDONLY;
    GENERIC_WRITE: Flags := Flags or O_WRONLY;
    else
      Exit(THandle(-1));
  end;

  case dwCreationDisposition of
//    CREATE_NEW:
//    CREATE_ALWAYS:
//    OPEN_EXISTING:
    OPEN_ALWAYS: Flags := Flags or O_CREAT;
//    TRUNCATE_EXISTING:
  end;

  Result := THandle(__open(lpFileName, Flags, FileAccessRights));

  // ShareMode

//    smode := Mode and $F0 shr 4;
//    if ShareMode[smode] <> 0 then
//    begin
//      LockVar.l_whence := SEEK_SET;
//      LockVar.l_start := 0;
//      LockVar.l_len := 0;
//      LockVar.l_type := ShareMode[smode];
//      Tvar :=  fcntl(FileHandle, F_SETLK, LockVar);
//      Code := errno;
//      if (Tvar = -1) and (Code <> EINVAL) and (Code <> ENOTSUP) then
//       EINVAL/ENOTSUP - file doesn't support locking
//      begin
//        __close(FileHandle);
//        Exit;
//      end;
end;

type
  _LARGE_INTEGER = record
    case Integer of
    0: (
      LowPart: DWORD;
      HighPart: Longint);
    1: (
      QuadPart: Int64);
  end;

function WriteFile(hFile: THandle; const Buffer; nNumberOfBytesToWrite: Cardinal;
  var lpNumberOfBytesWritten: Cardinal; lpOverlapped: Pointer): Boolean; stdcall;
begin
  lpNumberOfBytesWritten := __write(hFile, @Buffer, nNumberOfBytesToWrite);
  if lpNumberOfBytesWritten = Cardinal(-1) then
  begin
    lpNumberOfBytesWritten := 0;
    Result := False;
  end
  else
    Result := True;
end;

function SetFilePointer(hFile: THandle; lDistanceToMove: Longint;
  lpDistanceToMoveHigh: PLongInt; dwMoveMethod: DWORD): DWORD; stdcall;
var
  dist: _LARGE_INTEGER;
begin
  dist.LowPart := lDistanceToMove;
  if Assigned(lpDistanceToMoveHigh) then
    dist.HighPart := lpDistanceToMoveHigh^
  else
    dist.HighPart := 0;

  dist.QuadPart := lseek(hFile, dist.QuadPart, dwMoveMethod); // dwMoveMethod = same as in windows
  if dist.QuadPart = -1 then
    Result := DWORD(-1)
  else
  begin
    Result := dist.LowPart;
    if Assigned(lpDistanceToMoveHigh) then
      lpDistanceToMoveHigh^ := dist.HighPart;
  end;
end;

procedure GetLocalTime(var lpSystemTime: TSystemTime); stdcall;
var
  T: time_t;
  TV: timeval;
  UT: tm;
begin
  gettimeofday(TV, nil);
  T := TV.tv_sec;
  localtime_r(T, UT);

  lpSystemTime.wYear := UT.tm_year + 1900;
  lpSystemTime.wMonth := UT.tm_mon + 1;
  lpSystemTime.wDayOfWeek := UT.tm_wday;
  lpSystemTime.wDay := UT.tm_mday;
  lpSystemTime.wHour := UT.tm_hour;
  lpSystemTime.wMinute := UT.tm_min;
  lpSystemTime.wSecond := UT.tm_sec;
  lpSystemTime.wMilliseconds := TV.tv_usec div 1000;
end;

function GetTimeMilliSeconds: Int64;
var
  TV: timeval;
begin
  gettimeofday(TV, nil);
  Result := Int64(tv.tv_sec) * 1000000 + int64(tv.tv_usec);
end;

function MilliSecondsToSystemTime(MSecs: Int64): TSystemTime;
var
  T: time_t;
  TV: timeval;
  UT: tm;
begin
  TV.tv_usec := MSecs mod 1000000;
  TV.tv_sec := MSecs div 1000000;
  T := TV.tv_sec;
  localtime_r(T, UT);

  Result.wYear := UT.tm_year + 1900;
  Result.wMonth := UT.tm_mon + 1;
  Result.wDayOfWeek := UT.tm_wday;
  Result.wDay := UT.tm_mday;
  Result.wHour := UT.tm_hour;
  Result.wMinute := UT.tm_min;
  Result.wSecond := UT.tm_sec;
  Result.wMilliseconds := TV.tv_usec div 1000;
end;

{function GetLocalTimeNanoSeconds: Int64;
var
  t: mach_timespec_t;
const
  CLOCK_REALTIME = 0;
begin
  clock_get_time(CLOCK_REALTIME, t);
  Result := Int64(t.tv_sec) * 1000000000 + int64(t.tv_nsec);
end;  }

function CloseHandle(hObject: THandle): BOOL; stdcall;
begin
  Result := __close(hObject) = 0;
end;

function StrLen(const Str: PWideChar): Cardinal; overload;
begin
  Result := Length(Str);
end;

function StrLen(const Str: PAnsiChar): Cardinal; overload;
begin
  Result := Length(Str);
end;

function StrLCopy(Dest: PWideChar; const Source: PWideChar; MaxLen: Cardinal): PWideChar; overload;
var
  Len: Cardinal;
begin
  Result := Dest;
  Len := StrLen(Source);
  if Len > MaxLen then
    Len := MaxLen;
  Move(Source^, Dest^, Len * SizeOf(WideChar));
  Dest[Len] := #0;
end;

function StrLCopy(Dest: MarshaledAString; const Source: MarshaledAString; MaxLen: Cardinal): MarshaledAString; overload;
var
  Len: Cardinal;
begin
  Result := Dest;
  Len := StrLen(Source);
  if Len > MaxLen then
    Len := MaxLen;
  Move(Source^, Dest^, Len * SizeOf(Byte));
  Dest[Len] := #0;
end;


function StrPLCopy(Dest: PWideChar; const Source: UnicodeString; MaxLen: Cardinal): PWideChar;
begin
  Result := StrLCopy(Dest, PWideChar(Source), MaxLen);
end;

function GetModuleHandle(lpModuleName: PWideChar): HMODULE;
begin
  Result := 0;
  if lpModuleName = 'kernel32' then
    Result := 1;
end;

function GetModuleHandleA(lpModuleName: LPCSTR): HMODULE; stdcall;
begin
  Result := GetModuleHandle(PChar(string(lpModuleName)));
end;

function GetEnvironmentVariableW(lpName: PWideChar; lpBuffer: PWideChar; nSize: DWORD): DWORD; stdcall; overload;
var
  Len: Integer;
  Env: string;
begin
  env := string(getenv(PAnsiChar(UTF8Encode(lpName))));

  Len := Length(env) + 1;
  Result := Len;
  if nSize < Result then
    Result := nSize;

  StrPLCopy(lpBuffer, env, Result);
  if Len > nSize then
    SetLastError(122) //ERROR_INSUFFICIENT_BUFFER)
  else
  begin
    SetLastError(0);
    Dec(Result); // should not include terminating #0
  end;
end;

function DeleteFileA(lpFileName: LPCSTR): BOOL; stdcall;
begin
  Result := unlink(lpFileName) <> -1;
end;

//    ReservedBlock := VirtualAlloc(Pointer(DebugReservedAddress), 65536, MEM_RESERVE, PAGE_NOACCESS);

var
  PageSize: LongInt = 0;

function VirtualAlloc(lpvAddress: Pointer; dwSize: SIZE_T; flAllocationType, flProtect: DWORD): Pointer; stdcall;
var
//  PageSize: LongInt;
  AllocSize: LongInt;
  Flags: Integer;
  Prot: Integer;
begin
  if flAllocationType and (MEM_RESERVE or MEM_COMMIT) = 0 then
    Exit(0);

  Flags := MAP_PRIVATE or MAP_ANON;
  Prot := PROT_NONE;

  if flProtect and PAGE_READONLY <> 0 then
    Prot := Prot or PROT_READ;
  if flProtect and PAGE_READWRITE <> 0 then
    Prot := Prot or PROT_READ or PROT_WRITE;
  if flProtect and PAGE_EXECUTE <> 0 then
    Prot := Prot or PROT_EXEC;
  if flProtect and PAGE_EXECUTE_READ <> 0 then
    Prot := Prot or PROT_EXEC or PROT_READ;
  if flProtect and PAGE_EXECUTE_READWRITE <> 0 then
    Prot := Prot or PROT_EXEC or PROT_READ or PROT_WRITE;

  if PageSize = 0 then
    PageSize := sysconf(_SC_PAGESIZE);

  if lpvAddress <> nil then
    Flags := Flags or MAP_FIXED;

  AllocSize := dwSize - (dwSize mod PageSize) + PageSize;

  Result := mmap(lpvAddress, AllocSize, Prot, Flags, -1, 0);

  FillChar(Result^, dwSize, 0);
end;

function VirtualFree(lpAddress: Pointer; dwSize, dwFreeType: Cardinal): LongBool; stdcall;
var
  Err: Integer;
begin
  {if dwFreetype = MEM_RELEASE then
  begin
    if lpAddress = Pointer($80800000) then
      munmap(lpAddress, dwSize)
    else
      free(lpAddress);
  end;  }
  if dwFreeType = MEM_RELEASE then
  begin
    Err := munmap(lpAddress, dwSize);
    Result := Err = 0;

    if Err <> 0 then // for debugging
      System.Error(reInvalidOp);
  end
  else // if dwFreeType = MEM_DECOMMIT then
  begin
    Result := False;
    System.Error(reInvalidOp); // not supported
  end;
end;

//procedure RaiseException(dwExceptionCode, dwExceptionFlags, nNumberOfArguments: DWORD;
//  lpArguments: PUINT_PTR); stdcall;
//begin
//  WriteLN('ACCESS VIOLATION (set breakpoint in FastMM_OSXUtil: RaiseException for easier debugging)');
//  kill(getppid, SIGSEGV);
////  asm int 3; end;
//end;

function dlopen(Filename: MarshaledAString; Flag: Integer): NativeUInt; cdecl;
  external libdl name _PU + 'dlopen';

function dlclose(Handle: NativeUInt): Integer; cdecl;
  external libdl name _PU + 'dlclose';


function LoadLibrary(ModuleName: PChar): HMODULE;
begin
  Result := HMODULE(dlopen(PAnsiChar(UTF8Encode(ModuleName)), RTLD_LAZY));
end;

function FreeLibrary(Module: HMODULE): LongBool;
begin
  Result := False;
  if Module <> 0 then
    Result := LongBool(dlclose(Module));
end;

function GetProcAddress(Module: HMODULE; Proc: PAnsiChar): Pointer;
var
  Error: MarshaledAString;
begin
  // dlsym doesn't clear the error state when the function succeeds
  dlerror;
  Result := dlsym(Module, Proc);
  Error := dlerror;
  if Error <> nil then
    Result := nil
end;

// *************************** query memory access ************************
// doesn't work; always returns  KERN_INVALID_ARGUMENT
(*const
  libSystem = '/usr/lib/libSystem.dylib';

type
  mach_port_t = Pointer; // Delphi equivalent for mach_port_t
  boolean_t = Integer;

  vm_prot_t = UInt32;
  vm_inherit_t = UInt32;
  natural_t = UInt32;

  vm_map_t = mach_port_t;
  vm_map_read_t = mach_port_t;
  vm_map_inspect_t = mach_port_t;

  vm_offset_t = Pointer;
  vm_address_t = Pointer;
  Pvm_address_t = ^vm_address_t;
  vm_region_flavor_t = Integer;
  vm_size_t = UIntPtr;
  Pvm_size_t = ^vm_size_t;
  mach_msg_type_number_t = natural_t;
  Pmach_msg_type_number_t = ^mach_msg_type_number_t;
  Pmach_port_t = ^mach_port_t;
  kern_return_t = integer; // AI

type
  {$ALIGN 4}
  vm_region_basic_info_data_64_t = record
    protection: vm_prot_t;
    max_protection: vm_prot_t;
    inheritance: vm_inherit_t;
    shared: boolean_t;
    reserved: boolean_t;
    offset: UInt32;
    behavior: UInt32;
    user_wired_count: natural_t;
  end;
  vm_region_info_t = ^vm_region_basic_info_data_64_t;


function vm_region_64(
	target_task: vm_map_read_t;
	address: Pvm_address_t;
	size: Pvm_size_t;
	flavor: vm_region_flavor_t;
	info: vm_region_info_t;
	infoCnt: Pmach_msg_type_number_t;
	object_name: Pmach_port_t
): kern_return_t; cdecl; external libSystem;


//type
//  vm_info_region_64_t = record
//    vir_start: natural_t;            // start of region */
//    vir_end: natural_t;              // end of region */
//    vir_object: natural_t;           // the mapped object */
//    vir_offset: memory_object_offset_t;      // offset into object */
//    vir_needs_copy: boolean_t;       // does object need to be copied? */
//    vir_protection: vm_prot_t;       // protection code */
//    vir_max_protection: vm_prot_t;   // maximum protection */
//    vir_inheritance: vm_inherit_t;   // inheritance */
//    vir_wired_count: natural_t;      // number of times wired */
//    vir_user_wired_count: natural_t; // number of times user has wired */
//  end;
//  Pvm_info_region_64_t = ^vm_info_region_64_t;

//
//function mach_vm_region_info_64(
//	task: vm_map_read_t;
//	address: vm_address_t;
//	region: Pvm_info_region_64_t;
//	objects: Pvm_info_object_array_t;
//	objectsCnt: Pmach_msg_type_number_t
//): kern_return_t; cdecl; external libSystem;

function mach_task_self: mach_port_t; cdecl
  external libc name _PU + 'mach_task_self';

const
  VM_REGION_BASIC_INFO_64 = 9;
  VM_REGION_BASIC_INFO_COUNT_64 = SizeOf(vm_region_basic_info_data_64_t) div SizeOf(integer);
  VM_REGION_BASIC_INFO           = 10;
  KERN_SUCCESS = 0;
  VM_PROT_NONE = 0;

procedure test; // from AI
begin
    var size: vm_size_t := 4096;
    var address: vm_address_t := Pointer($10000000); // Replace with your desired virtual address

    var info: vm_region_basic_info_data_64_t;
    FillChar(info, SizeOf(info), 0);
    var info_count: mach_msg_type_number_t := VM_REGION_BASIC_INFO_COUNT_64;
    var object_name: mach_port_t := nil;

    var result: kern_return_t := vm_region_64(
        mach_task_self, @address, @size, VM_REGION_BASIC_INFO_64,
        @info, @info_count, @object_name);

    if (result = KERN_SUCCESS) then
    begin
        if (info.protection = VM_PROT_NONE) then
            writeln('The virtual memory region is free.')
         else
            writeln('The virtual memory region is not free.');
    end
    else if Result = KERN_INVALID_ARGUMENT then
      WriteLn('Invalid argument.')
    else
        writeln('Error querying virtual memory region.');
end;



begin
test;
*)


end.
