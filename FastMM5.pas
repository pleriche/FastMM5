{

FastMM 5 Beta 1

Description:
  A fast replacement memory manager for Embarcadero Delphi applications that scales well under multi-threaded usage, is
  not prone to memory fragmentation, and supports shared memory without the use of external .DLL files.

Copyright:
  Pierre le Riche

Sponsored by:
  gs-soft AG

Homepage:
  https://github.com/pleriche/FastMM5

Licence:
  FastMM 5 is dual-licensed.  You may choose to use it under the restrictions of the GPL v3 licence at no cost, or you
  may purchase a commercial licence.  The commercial licence pricing is as follows:
    1 User = $99
    2 Users = $189
    3 Users = $269
    4 Users = $339
    5 Users = $399
    >5 Users = $399 + $50 per user from the 6th onwards
  Once payment has been made at https://www.paypal.me/fastmm (paypal@leriche.org), please send an e-mail to
  fastmm@leriche.org for confirmation.  Support is available for users with a commercial licence via the same e-mail
  address.

Usage Instructions:
  Add FastMM5.pas as the first unit in your project's DPR file.  It will install itself automatically during startup,
  replacing the default memory manager.

  In order to share the memory manager between the main application and libraries call
  FastMM_AttemptToUseSharedMemoryManager (in order to use the memory manager of another module in the process) or
  FastMM_ShareMemoryManager (to share the memory manager instance of the current module with other modules).  It is
  important to share the memory manager between modules where memory allocated in the one module may be freed by the
  other.

  If the application requires memory alignment greater than the default, call FastMM_EnterMinimumAddressAlignment and
  once the greater alignment is no longer required call FastMM_ExitMinimumAddressAlignment.  Calls may be nested.  The
  coarsest memory alignment requested takes precedence.

  At the cost of performance and increased memory usage FastMM can log additional metadata together with every block.
  In order to enable this mode call FastMM_EnterDebugMode and to exit debug mode call FastMM_ExitDebugMode.  Calls may
  be nested in which case debug mode will be active as long as the number of FastMM_EnterDebugMode calls exceed the
  number of FastMM_ExitDebugMode calls.  In debug mode freed memory blocks will be filled with the byte pattern
  $808080... so that usage of a freed memory block or object, as well as corruption of the block header and/or footer
  will likely be detected.  If the debug support library, FastMM_FullDebugMode.dll, is available and the application has
  not specified its own handlers for FastMM_GetStackTrace and FastMM_ConvertStackTraceToText then the support library
  will be loaded during the first call to FastMM_EnterDebugMode.

  Events (memory leaks, errors, etc.) may be logged to file, displayed on-screen, passed to the debugger or any
  combination of the three.  Specify how each event should be handled via the FastMM_LogToFileEvents,
  FastMM_MessageBoxEvents and FastMM_OutputDebugStringEvents variables.  The default event log filename will be built
  from the application filepath, but may be overridden via the FastMM_EventLogFilename variable.  Messages are built
  from templates that may be changed/translated by the application.

  The optimization strategy of the memory manager may be tuned via FastMM_SetOptimizationStrategy.  It can be set to
  favour performance, low memory usage, or a blend of both.  The default strategy is to blend the performance and low
  memory usage goals.

}

unit FastMM5;

interface

uses
  Winapi.Windows;

{$RangeChecks Off}
{$BoolEval Off}
{$OverflowChecks Off}
{$Optimization On}
{$StackFrames Off}
{$TypedAddress Off}
{$LongStrings On}

{Calling the deprecated GetHeapStatus is unavoidable, so suppress the warning.}
{$warn Symbol_Deprecated Off}
{$warn Symbol_Platform Off}

{$if SizeOf(Pointer) = 8}
  {$define 64Bit}
  {$align 8}
{$else}
  {$define 32Bit}
  {$align 4}
{$endif}

{$ifdef CPUX86}
  {$ifndef PurePascal}
    {$define X86ASM}
  {$endif}
{$else}
  {$ifdef CPUX64}
    {$ifndef PurePascal}
      {$define X64ASM}
    {$endif}
  {$else}
    {x86/x64 CPUs do not reorder writes, but ARM CPUs do.}
    {$define WeakMemoryOrdering}
  {$endif}
{$endif}

const
  {The number of entries per stack trace differs between 32-bit and 64-bit in order to ensure that the debug header is
  always a multiple of 64 bytes.}
{$ifdef 32Bit}
  CFastMM_StackTraceEntryCount = 11;
{$else}
  CFastMM_StackTraceEntryCount = 12;
{$endif}

type

  {The optimization strategy for the memory manager.}
  TFastMM_MemoryManagerOptimizationStrategy = (mmosOptimizeForSpeed, mmosBalanced, mmosOptimizeForLowMemoryUsage);

  TFastMM_MemoryManagerEventType = (
    {Another third party memory manager has already been installed.}
    mmetAnotherThirdPartyMemoryManagerAlreadyInstalled,
    {FastMM cannot be installed, because memory has already been allocated through the default memory manager.}
    mmetCannotInstallAfterDefaultMemoryManagerHasBeenUsed,
    {When an attempt is made to install or use a shared memory manager, but the memory manager has already been used to
    allocate memory.}
    mmetCannotSwitchToSharedMemoryManagerWithLivePointers,
    {Details about an individual memory leak.}
    mmetUnexpectedMemoryLeakDetail,
    {Summary of memory leaks}
    mmetUnexpectedMemoryLeakSummary,
    {When an attempt to free or reallocate a debug block that has already been freed is detected.}
    mmetDebugBlockDoubleFree,
    mmetDebugBlockReallocOfFreedBlock,
    {When a corruption of the memory pool is detected.}
    mmetDebugBlockHeaderCorruption,
    mmetDebugBlockFooterCorruption,
    mmetDebugBlockModifiedAfterFree);
  TFastMM_MemoryManagerEventTypeSet = set of TFastMM_MemoryManagerEventType;

  TFastMM_MemoryManagerInstallationState = (
    {The default memory manager is currently in use.}
    mmisDefaultMemoryManagerInUse,
    {Another third party memory manager has been installed.}
    mmisOtherThirdPartyMemoryManagerInstalled,
    {A shared memory manager is being used.}
    mmisUsingSharedMemoryManager,
    {This memory manager has been installed.}
    mmisInstalled);

  TFastMM_StackTrace = array[0..CFastMM_StackTraceEntryCount - 1] of NativeUInt;

  {The debug block header.  Must be a multiple of 64 in order to guarantee that minimum block alignment restrictions
  are honoured.}
  PFastMM_DebugBlockHeader = ^TFastMM_DebugBlockHeader;
  TFastMM_DebugBlockHeader = packed record
    {The first two pointer sized slots cannot be used by the debug block header.  The medium block manager uses the
    first two pointers in a free block for the free block linked list, and the small block manager uses the first
    pointer for the free block linked list.  This space is thus reserved.}
    Reserved1: Pointer;
    Reserved2: Pointer;
    {The user requested size for the block.}
    UserSize: NativeInt;
    {The object class this block was used for the previous time it was allocated.  When a block is freed, the pointer
    that would normally be in the space of the class pointer is copied here, so if it is detected that the block was
    used after being freed we have an idea what class it is.}
    PreviouslyUsedByClass: Pointer;
    {The call stack when the block was allocated}
    AllocationStackTrace: TFastMM_StackTrace;
    {The call stack when the block was freed}
    FreeStackTrace: TFastMM_StackTrace;
    {The value of the FastMM_CurrentAllocationGroup when the block was allocated.  Can be used in the debugging process
    to group related memory leaks together.}
    AllocationGroup: Cardinal;
    {The allocation number:  All debug mode allocations are numbered sequentially.  This number may be useful in memory
    leak analysis.  If it reaches 4G it wraps back to 0.}
    AllocationNumber: Cardinal;
    {The ID of the thread that allocated the block}
    AllocatedByThread: Cardinal;
    {The ID of the thread that freed the block}
    FreedByThread: Cardinal;
    {The sum of the dwords(32-bit)/qwords(64-bit) in this structure starting after the initial two reserved fields up
    to just before this field.}
    HeaderCheckSum: NativeUInt;
{$ifdef 64Bit}
    Padding1: Cardinal;
{$endif}
    Padding2: SmallInt;
    {The debug block signature.  This will always be CIsDebugBlockFlag.}
    DebugBlockFlags: SmallInt;
  end;

  TFastMM_WalkAllocatedBlocksBlockType = (
    btLargeBlock,
    btMediumBlockSpan,
    btMediumBlock,
    btSmallBlockSpan,
    btSmallBlock);
  TFastMM_WalkBlocksBlockTypes = set of TFastMM_WalkAllocatedBlocksBlockType;

  TFastMM_WalkAllocatedBlocks_BlockInfo = record
    BlockAddress: Pointer;
    {If there is additional debug information for the block, this will be a pointer to it.  (Will be nil if there is no
    additional debug information for the block.}
    DebugInformation: PFastMM_DebugBlockHeader;
    {The size of the block or span.  This includes the size of the block header, padding and internal fragmentation.}
    BlockSize: NativeInt;
    {The usable size of the block.  This is BlockSize less any headers, footers, other management structures and
    internal fragmentation.}
    UsableSize: NativeInt;
    {An arbitrary pointer value passed in to the WalkAllocatedBlocks routine, which is passed through to the callback.}
    UserData: Pointer;
    {The arena number for the block}
    ArenaIndex: Byte;
    {The type of block}
    BlockType: TFastMM_WalkAllocatedBlocksBlockType;
    {True if the block is free, False if it is in use}
    BlockIsFree: Boolean;
    {--------Medium block spans only-------}
    {If True this is the current sequential feed medium block span for ArenaIndex}
    IsSequentialFeedMediumBlockSpan: Boolean;
    {If this is the sequential feed span for the medium block arena then this will contain the number of bytes
    currently unused.}
    MediumBlockSequentialFeedSpanUnusedBytes: Integer;
    {----Small block spans only-----}
    {If True this is the current sequential feed small block span for ArenaIndex and the block size}
    IsSequentialFeedSmallBlockSpan: Boolean;
    {If IsSmallBlockSpan = True then this will contain the size of the small block.}
    SmallBlockSpanBlockSize: Word;
    {If this is a sequential feed small block span then this will contain the number of bytes currently unused.}
    SmallBlockSequentialFeedSpanUnusedBytes: Integer;
  end;

  TFastMM_WalkBlocksCallback = procedure(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);

  TFastMM_MinimumAddressAlignment = (maa8Bytes, maa16Bytes, maa32Bytes, maa64Bytes);
  TFastMM_MinimumAddressAlignmentSet = set of TFastMM_MinimumAddressAlignment;

  {The formats in which the event log file may be written.  Controlled via the FastMM_EventLogTextEncoding variable.}
  TFastMM_EventLogTextEncoding = (
    {UTF-8 with no byte-order mark}
    teUTF8,
    {UTF-8 with a byte-order mark}
    teUTF8_BOM,
    {UTF-16 little endian, with no byte-order mark}
    teUTF16LE,
    {UTF-16 little endian, with a byte-order mark}
    teUTF16LE_BOM);

  {A routine used to obtain the current stack trace up to AMaxDepth levels deep.  The first ASkipFrames frames in the
  stack trace are skipped.  Unused entries will be set to 0.}
  TFastMM_GetStackTrace = procedure(APReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);

  {A routine used to convert a stack trace to a textual representation (typically unit and line information).
  APReturnAddresses points to a buffer with up to AMaxDepth return addresses (zero return addresses are ignored).  The
  textual representation is stored to APBufferPosition.  The routine will update both APBufferPosition and
  ARemainingBufferSpaceInWideChars.}
  TFastMM_ConvertStackTraceToText = function(APReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
    APBuffer, APBufferEnd: PWideChar): PWideChar;

  {List of registered leaks}
  TFastMM_RegisteredMemoryLeak = record
    LeakAddress: Pointer;
    LeakedClass: TClass;
    LeakSize: NativeInt;
    LeakCount: Integer;
  end;
  TFastMM_RegisteredMemoryLeaks = array of TFastMM_RegisteredMemoryLeak;

{------------------------Core memory manager interface------------------------}
function FastMM_GetMem(ASize: NativeInt): Pointer;
function FastMM_FreeMem(APointer: Pointer): Integer;
function FastMM_ReallocMem(APointer: Pointer; ANewSize: NativeInt): Pointer;
function FastMM_AllocMem(ASize: NativeInt): Pointer;

{------------------------Expected memory leak management------------------------}

{Registers expected memory leaks.  Returns True on success.  The list of leaked blocks is limited, so failure is
possible if the list is full.}
function FastMM_RegisterExpectedMemoryLeak(ALeakedPointer: Pointer): Boolean; overload;
function FastMM_RegisterExpectedMemoryLeak(ALeakedObjectClass: TClass; ACount: Integer = 1): Boolean; overload;
function FastMM_RegisterExpectedMemoryLeak(ALeakedBlockSize: NativeInt; ACount: Integer = 1): Boolean; overload;
{Removes expected memory leaks.  Returns True on success.}
function FastMM_UnregisterExpectedMemoryLeak(ALeakedPointer: Pointer): Boolean; overload;
function FastMM_UnregisterExpectedMemoryLeak(ALeakedObjectClass: TClass; ACount: Integer = 1): Boolean; overload;
function FastMM_UnregisterExpectedMemoryLeak(ALeakedBlockSize: NativeInt; ACount: Integer = 1): Boolean; overload;
{Returns a list of all expected memory leaks}
function FastMM_GetRegisteredMemoryLeaks: TFastMM_RegisteredMemoryLeaks;

{------------------------Diagnostics------------------------}

{Returns the user size of the block, normally the number of bytes requested in the original GetMem or ReallocMem call.
Exception:  Outside of debug mode the requested size for small and medium blocks is not tracked, and in these instances
the value returned will be the same as the value returned by the FastMM_BlockMaximumUserBytes call.}
function FastMM_BlockCurrentUserBytes(APointer: Pointer): NativeInt;
{Returns the maximum number of bytes that may safely be used by the application for the block starting at APointer.
This will be greater or equal to the size requested in the original GetMem or ReallocMem call.  Note that using more
than the value returned by FastMM_BlockCurrentUserBytes is not recommended, since a reallocation request will only move
up to FastMM_BlockCurrentUserBytes bytes.}
function FastMM_BlockMaximumUserBytes(APointer: Pointer): NativeInt;

{Attempts to release all pending free blocks.  Returns True if there were no pending frees, or all pending frees could
be released.  Returns False if there were locked (currently in use) managers with pending frees.}
function FastMM_ProcessAllPendingFrees: Boolean;

{Walks the block types indicated by the AWalkBlockTypes set, calling ACallBack for each allocated block.  If
AWalkBlockTypes = [] then all block types is assumed.  Note that pending free blocks are treated as used blocks for the
purpose of the AWalkUsedBlocksOnly parameter.  Call FastMM_ProcessAllPendingFrees first in order to process all pending
frees if this is a concern.}
procedure FastMM_WalkBlocks(ACallBack: TFastMM_WalkBlocksCallback; AWalkBlockTypes: TFastMM_WalkBlocksBlockTypes = [];
  AWalkUsedBlocksOnly: Boolean = True; AUserData: Pointer = nil);

{Walks all debug mode blocks (blocks that were allocated between a FastMM_EnterDebugMode and FastMM_ExitDebugMode call),
checking for corruption of the debug header, footer, and in the case of freed blocks whether the block content was
modified after the block was freed.  If a corruption is encountered an error message will be logged and/or displayed
(as per the error logging configuration) and an invalid pointer exception will be raised.}
procedure FastMM_ScanDebugBlocksForCorruption;

{Returns a THeapStatus structure with information about the current memory usage.}
function FastMM_GetHeapStatus: THeapStatus;

{------------------------Memory Manager Sharing------------------------}

{Searches the current process for a shared memory manager.  If no memory has been allocated using this memory manager
it will switch to using the shared memory manager instead.  Returns True if another memory manager was found and it
could be shared.  If this memory manager instance *is* the shared memory manager, it will do nothing and return True.}
function FastMM_AttemptToUseSharedMemoryManager: Boolean;

{Starts sharing this memory manager with other modules in the current process.  Only one memory manager may be shared
per process, so this function may fail.}
function FastMM_ShareMemoryManager: Boolean;

{------------------------Configuration------------------------}

{Returns the current installation state of the memory manager.}
function FastMM_GetInstallationState: TFastMM_MemoryManagerInstallationState;

{Gets/sets the optimization strategy for the memory manager.  FastMM can be optimized for maximum performance, low
memory usage or a blend of the two.}
procedure FastMM_SetOptimizationStrategy(AStrategy: TFastMM_MemoryManagerOptimizationStrategy);
function FastMM_GetCurrentOptimizationStrategy: TFastMM_MemoryManagerOptimizationStrategy;

{Call FastMM_EnterMinimumAddressAlignment to request that all subsequent allocated blocks are aligned to the specified
minimum.  Call FastMM_ExitMinimumAddressAlignment to rescind a prior request.  Requests for coarser alignments have
precedence over requests for lesser alignments.  These calls are thread safe.  In the current implementation the
following minimum alignments are always in effect, regardless of any alignment requests:
  32-Bit applications: >= maa8Bytes
  64-bit applications: >= maa16Bytes
  Allocations greater than 150 bytes: >= maa16Bytes
  Allocations greater than 302 bytes: >= maa32Bytes
  Allocations greater than 606 bytes: maa64Bytes}
procedure FastMM_EnterMinimumAddressAlignment(AMinimumAddressAlignment: TFastMM_MinimumAddressAlignment);
procedure FastMM_ExitMinimumAddressAlignment(AMinimumAddressAlignment: TFastMM_MinimumAddressAlignment);

{Returns the current minimum address alignment in effect.}
function FastMM_GetCurrentMinimumAddressAlignment: TFastMM_MinimumAddressAlignment;

{Attempts to load the debug support library specified by FastMM_DebugSupportLibraryName.  On success it will set the
FastMM_GetStackTrace and FastMM_ConvertStackTraceToText handlers to point to the routines in the debug library, provided
alternate handlers have not yet been assigned by the application.  Returns True if the library was loaded successfully,
or was already loaded successfully prior to this call.  FastMM_EnterDebugMode will call FastMM_LoadDebugSupportLibrary
the first time it is called, unless the debug support library has already been loaded or handlers for both
FastMM_GetStackTrace and FastMM_ConvertStackTraceToText have been set by the application.}
function FastMM_LoadDebugSupportLibrary: Boolean;
{Frees the debug support library, pointing the stack trace handlers currently using the debug support library back to
the default no-op handlers.}
function FastMM_FreeDebugSupportLibrary: Boolean;

{Enters/exits debug mode.  Calls may be nested, in which case debug mode is only exited when the number of
FastMM_ExitDebugMode calls equal the number of FastMM_EnterDebugMode calls.  In debug mode extra metadata is logged
before and after the user data in the block, and extra checks are performed in order to catch common programming
errors.  Returns True on success, False if this memory manager instance is not currently installed or the installed
memory manager has changed.  Note that debug mode comes with a severe performance penalty, and due to the extra
metadata all blocks that are allocated while debug mode is active will use significantly more address space.}
function FastMM_EnterDebugMode: Boolean;
function FastMM_ExitDebugMode: Boolean;

{No-op call stack routines.}
procedure FastMM_NoOpGetStackTrace(APReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
function FastMM_NoOpConvertStackTraceToText(APReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
  APBufferPosition, APBufferEnd: PWideChar): PWideChar;

{Sets FastMM_EventLogFileName to the default event log filename for the application.  If APathOverride <> nil then
the default path will be substituted with the null terminated string pointed to by APathOverride.}
procedure FastMM_SetDefaultEventLogFileName(APathOverride: PWideChar = nil);

var

  {-----------Stack trace support routines----------}
  {The active routines used to get a call stack and to convert it to a textual representation.  These will be set to
  the no-op routines during startup.  If either of these have not been assigned a different value when
  FastMM_EnterDebugMode is called for the first time then an attempt will be made to load the debug support DLL and
  any of these still set to the no-op routines will be rerouted to the handlers in the debug support DLL.}
  FastMM_GetStackTrace: TFastMM_GetStackTrace;
  FastMM_ConvertStackTraceToText: TFastMM_ConvertStackTraceToText;

  {---------Debug options---------}

  {The name of the library that contains the functionality used to obtain the current call stack, and also to convert a
  call stack to unit and line number information.  The first time EnterDebugMode is called an attempt will be made to
  load this library, unless handlers for both FastMM_GetStackTrace and FastMM_ConvertStackTraceToText have already been
  set.}
  FastMM_DebugSupportLibraryName: PWideChar = {$ifndef 64Bit}'FastMM_FullDebugMode.dll'{$else}'FastMM_FullDebugMode64.dll'{$endif};

  {The events that are passed to OutputDebugString.}
  FastMM_OutputDebugStringEvents: TFastMM_MemoryManagerEventTypeSet = [mmetDebugBlockDoubleFree,
    mmetDebugBlockReallocOfFreedBlock, mmetDebugBlockHeaderCorruption, mmetDebugBlockFooterCorruption,
    mmetDebugBlockModifiedAfterFree, mmetAnotherThirdPartyMemoryManagerAlreadyInstalled,
    mmetCannotInstallAfterDefaultMemoryManagerHasBeenUsed, mmetCannotSwitchToSharedMemoryManagerWithLivePointers];
  {The events that are logged to file.}
  FastMM_LogToFileEvents: TFastMM_MemoryManagerEventTypeSet = [mmetDebugBlockDoubleFree,
    mmetDebugBlockReallocOfFreedBlock, mmetDebugBlockHeaderCorruption, mmetDebugBlockFooterCorruption,
    mmetDebugBlockModifiedAfterFree, mmetAnotherThirdPartyMemoryManagerAlreadyInstalled,
    mmetCannotInstallAfterDefaultMemoryManagerHasBeenUsed, mmetCannotSwitchToSharedMemoryManagerWithLivePointers];
  {The events that are displayed in a message box.}
  FastMM_MessageBoxEvents: TFastMM_MemoryManagerEventTypeSet = [mmetDebugBlockDoubleFree,
    mmetDebugBlockReallocOfFreedBlock, mmetDebugBlockHeaderCorruption, mmetDebugBlockFooterCorruption,
    mmetDebugBlockModifiedAfterFree, mmetAnotherThirdPartyMemoryManagerAlreadyInstalled,
    mmetCannotInstallAfterDefaultMemoryManagerHasBeenUsed, mmetCannotSwitchToSharedMemoryManagerWithLivePointers];
  {All debug blocks are tagged with the current value of this variable when the block is allocated.  This may be used
  by the application to track memory issues.}
  FastMM_CurrentAllocationGroup: Cardinal;
  {This variable is incremented during every debug getmem call (wrapping to 0 once it hits 4G) and stored in the debug
  header.  It may be useful for debugging purposes.}
  FastMM_LastAllocationNumber: Cardinal;

  {---------Message and log file text configuration--------}


  FastMM_EventLogTextEncoding: TFastMM_EventLogTextEncoding;

  {Pointer to the name of the file to which the event log is written.}
  FastMM_EventLogFilename: PWideChar;

  {Messages contain numeric tokens that will be substituted.  The available tokens are:
    0: A blank string (invalid token IDs will also translate to this)
    1: The current date in yyyy-mm-dd format.
    2: The current time in HH:nn:ss format.
    3: Block size in bytes
    4: The ID of the allocating thread (in hexadecimal).
    5: The ID of the freeing thread (in hexadecimal).
    6: The stack trace when the block was allocated.
    7: The stack trace when the block was freed.
    8: The object class for the block.  For freed blocks this will be the prior object class, otherwise it will be the
       current object class.
    9: The allocation number for the block (in decimal).
    10: Hex and ASCII dump size in bytes
    11: Block address (in hexadecimal).
    12: Hex dump of block (each line is followed by #13#10)
    13: ASCII dump of block (each line is followed by #13#10)
    14: Leak summary entries
    15: The size and offsets for modifications to a block after it was freed.
    16: The full path and filename of the event log.
  }

  {This entry precedes every entry in the event log.}
  FastMM_LogFileEntryHeader: PWideChar = '--------------------------------{1} {2}--------------------------------'#13#10;
  {Memory manager installation errors}
  FastMM_CannotInstallAfterDefaultMemoryManagerHasBeenUsedMessage: PWideChar = 'FastMM cannot be installed, because the '
    + 'default memory manager has already been used to allocate memory.';
  FastMM_CannotSwitchToSharedMemoryManagerWithLivePointersMessage: PWideChar = 'Cannot switch to the shared memory '
    + 'manager, because the local memory manager instance has already been used to allocate memory.';
  FastMM_AnotherMemoryManagerAlreadyInstalledMessage: PWideChar = 'FastMM cannot be installed, because another third '
    + 'party memory manager has already been installed.';
  FastMM_CannotSwitchMemoryManagerMessageBoxCaption: PWideChar = 'Cannot Switch Memory Managers';
  {Memory leak messages.}
  FastMM_MemoryLeakDetailMessage_NormalBlock: PWideChar = 'A memory block has been leaked. The size is: {3}'#13#10#13#10
    + 'The block is currently used for an object of class: {8}'#13#10#13#10
    + 'Current memory dump of {10} bytes starting at pointer address {11}:'#13#10
    + '{12}'#13#10'{13}'#13#10;
  FastMM_MemoryLeakDetailMessage_DebugBlock: PWideChar = 'A memory block has been leaked. The size is: {3}'#13#10#13#10
    + 'This block was allocated by thread 0x{4}, and the stack trace (return addresses) at the time was:'
    + '{6}'#13#10#13#10'The block is currently used for an object of class: {8}'#13#10#13#10
    + 'The allocation number is: {9}'#13#10#13#10
    + 'Current memory dump of {10} bytes starting at pointer address {11}:'#13#10
    + '{12}'#13#10'{13}'#13#10;
  FastMM_MemoryLeakSummaryMessage_LeakDetailNotLogged: PWideChar = 'This application has leaked memory. '
    + 'The leaks ordered by size are:'#13#10'{14}'#13#10;
  FastMM_MemoryLeakSummaryMessage_LeakDetailLoggedToEventLog: PWideChar = 'This application has leaked memory. '
    + 'The leaks ordered by size are:'#13#10'{14}'#13#10#13#10
    + 'Memory leak detail was logged to {16}'#13#10;
  FastMM_MemoryLeakMessageBoxCaption: PWideChar = 'Unexpected Memory Leak';
  {Attempts to free or reallocate a debug block that has alredy been freed.}
  FastMM_DebugBlockDoubleFree: PWideChar = 'An attempt was made to free a block that has already been freed.'#13#10#13#10
    + 'The block size is {3}.'#13#10#13#10
    + 'The block was allocated by thread 0x{4}, and the stack trace (return addresses) at the time was:'
    + '{6}'#13#10#13#10'This block was freed by thread 0x{5}, and the stack trace (return addresses) at the time was:'
    + '{7}'#13#10#13#10
    + 'The allocation number is: {9}'#13#10;
  FastMM_DebugBlockReallocOfFreedBlock: PWideChar = 'An attempt was made to resize a block that has already been freed.'#13#10#13#10
    + 'The block size is {3}.'#13#10#13#10
    + 'The block was allocated by thread 0x{4}, and the stack trace (return addresses) at the time was:'
    + '{6}'#13#10#13#10'This block was freed by thread 0x{5}, and the stack trace (return addresses) at the time was:'
    + '{7}'#13#10#13#10
    + 'The allocation number is: {9}'#13#10;
  {Memory pool corruption messages.}
  FastMM_BlockModifiedAfterFreeMessage: PWideChar = 'A memory block was modified after it was freed.'#13#10#13#10
    + 'The block size is {3}.'#13#10#13#10
    + 'Modifications were detected at offsets (with lengths in brackets): {15}.'#13#10#13#10
    + 'The block was allocated by thread 0x{4}, and the stack trace (return addresses) at the time was:'
    + '{6}'#13#10#13#10'This block was freed by thread 0x{5}, and the stack trace (return addresses) at the time was:'
    + '{7}'#13#10#13#10
    + 'The allocation number is: {9}'#13#10#13#10
    + 'Current memory dump of {10} bytes starting at pointer address {11}:'#13#10
    + '{12}'#13#10'{13}'#13#10;
  FastMM_BlockHeaderCorruptedMessage: PWideChar = 'A memory block header has been corrupted.'#13#10#13#10
    + 'Current memory dump of {10} bytes starting at pointer address {11}:'#13#10
    + '{12}'#13#10'{13}'#13#10;
  FastMM_BlockFooterCorruptedMessage_AllocatedBlock: PWideChar = 'A memory block footer has been corrupted.'#13#10#13#10
    + 'The block size is {3}.'#13#10#13#10
    + 'The block was allocated by thread 0x{4}, and the stack trace (return addresses) at the time was:'
    + '{6}'#13#10#13#10
    + 'The allocation number is: {9}'#13#10#13#10
    + 'Current memory dump of {10} bytes starting at pointer address {11}:'#13#10
    + '{12}'#13#10'{13}'#13#10;
  FastMM_BlockFooterCorruptedMessage_FreedBlock: PWideChar = 'A memory block footer has been corrupted.'#13#10#13#10
    + 'The block size is {3}.'#13#10#13#10
    + 'The block was allocated by thread 0x{4}, and the stack trace (return addresses) at the time was:'
    + '{6}'#13#10#13#10'This block was freed by thread 0x{5}, and the stack trace (return addresses) at the time was:'
    + '{7}'#13#10#13#10
    + 'The allocation number is: {9}'#13#10#13#10
    + 'Current memory dump of {10} bytes starting at pointer address {11}:'#13#10
    + '{12}'#13#10'{13}'#13#10;
  FastMM_MemoryCorruptionMessageBoxCaption: PWideChar = 'Memory Corruption Detected';

implementation

{All blocks are preceded by a block header.  The block header varies in size according to the block type.  The block
type and state may be determined from the bits of the word preceding the block address, as follows:

  All block types:
  ----------------

  Bit 0: Block is free flag
    0 = Block is in use
    1 = Block is free

  Bit 1: Debug info flag
    0 = the block contains no additional debug information
    1 = the block contains a debug mode sub-block

  Bit 2: Block type 1
    0 = Is not a small block
    1 = Is a small block


  Small blocks only (bit 2 = 1):
  ------------------------------

  Bits 3..15: Offset to small block span header
    The offset of the block from the start of the small block span header, divided by 64.


  Medium, Large and Debug Blocks (bit 2 = 0):
  -------------------------------------------

  Bit 3: Block type 2
    0 = Is not a medium block
    1 = Is a medium block

  Bit 4: Block type 3
    0 = Is not a large block
    1 = Is a large block

  Bit 5: Block type 4
    0 = Is not a debug sub-block
    1 = Is a debug sub-block

  Bits 6..15: Reserved (always 0)

}

const

  {Block status flags}
  CBlockStatusWordSize = 2;

  CBlockIsFreeFlag = 1;
  CHasDebugInfoFlag = 2;
  CIsSmallBlockFlag = 4;
  CIsMediumBlockFlag = 8;
  CIsLargeBlockFlag = 16;
  CIsDebugBlockFlag = 32;

  {-----Small block constants-----}
  CSmallBlockTypeCount = 61;
  CSmallBlockGranularity = 8;
  CMaximumSmallBlockSize = 2624; //Must be a multiple of 64 for the 64-byte alignment option to work
  CSmallBlockArenaCount = 4;
  CSmallBlockFlagCount = 3;
  CDropSmallBlockFlagsMask = - (1 shl CSmallBlockFlagCount);
  CSmallBlockSpanOffsetBitShift = 6 - CSmallBlockFlagCount;

  {-----Medium block constants-----}
  CMediumBlockArenaCount = 4;
  {Medium blocks are always aligned to at least 64 bytes (which is the typical cache line size).}
  CMediumBlockAlignment = 64;
  CMaximumMediumBlockSpanSize = 4 * 1024 * 1024; //64K * CMediumBlockAlignment = 4MB

  {Medium blocks are binned in linked lists - one linked list for each size.}
  CMediumBlockBinsPerGroup = 32;
  CMediumBlockBinGroupCount = 32;
  CMediumBlockBinCount = CMediumBlockBinGroupCount * CMediumBlockBinsPerGroup;

  {The smallest medium block should be <= 10% greater than the largest small block.  It is an odd multiple
  of the typical cache line size in order to facilitate better cache line utilization.}
  CMinimumMediumBlockSize = CMaximumSmallBlockSize + 256; // = 2880

  {The spacing between medium block bins is not constant.  There are three groups: initial, middle and final.}
  CInitialBinCount = 384;
  CInitialBinSpacing = 256; //must be a power of 2

  CMediumBlockMiddleBinsStart = CMinimumMediumBlockSize + CInitialBinSpacing * CInitialBinCount;
  CMiddleBinCount = 384;
  CMiddleBinSpacing = 512; //must be a power of 2

  CMediumBlockFinalBinsStart = CMediumBlockMiddleBinsStart + CMiddleBinSpacing * CMiddleBinCount;
  CFinalBinCount = CMediumBlockBinCount - CMiddleBinCount - CInitialBinCount;
  CFinalBinSpacing = 1024; //must be a power of 2

  {The maximum size allocatable through medium blocks.  Blocks larger than this are allocated via the OS from the
  virtual memory pool ( = large blocks).}
  CMaximumMediumBlockSize = CMediumBlockFinalBinsStart + (CFinalBinCount - 1) * CFinalBinSpacing;

  {-----Large block constants-----}
  CLargeBlockGranularity = 64 * 1024; //Address space obtained from VirtualAlloc is always aligned to a 64K boundary
  CLargeBlockArenaCount = 8;

  {-----Small block span constants-----}
  {Allocating and deallocating small block spans are expensive, so it is not something that should be done frequently.}
  CMinimumSmallBlocksPerSpan = 16;
  COptimalSmallBlocksPerSpan = 64;
  COptimalSmallBlockSpanSizeLowerLimit = CMinimumMediumBlockSize + 16 * 1024;
  COptimalSmallBlockSpanSizeUpperLimit = CMinimumMediumBlockSize + 96 * 1024;
  {The maximum amount by which a small block span may exceed the optimal size before the block will be split instead of
  using it as-is.}
  CSmallBlockSpanMaximumAmountWithWhichOptimalSizeMayBeExceeded = 4 * 1024;

  {-------------Block resizing constants---------------}
  CSmallBlockDownsizeCheckAdder = 64;
  CSmallBlockUpsizeAdder = 32;
  {When a medium block is reallocated to a size smaller than this, then it must be reallocated to a small block and the
  data moved. If not, then it is shrunk in place down to MinimumMediumBlockSize.  Currently the limit is set at a
  quarter of the minimum medium block size.}
  CMediumInPlaceDownsizeLimit = CMinimumMediumBlockSize div 4;

  {------Debug constants-------}
{$ifdef 32Bit}
  {The number of bytes of address space that is reserved and only released once the first OS allocation request fails.
  This allows some subsequent memory allocation requests to succeed in order to allow the application to allocate some
  memory for error handling, etc. in response to the first EOutOfMemory exception.  This only applies to 32-bit
  applications.}
  CEmergencyReserveAddressSpace = CMaximumMediumBlockSpanSize;
{$endif}

  {Event log tokens}
  CEventLogTokenBlankString = 0;
  CEventLogTokenCurrentDate = 1;
  CEventLogTokenCurrentTime = 2;
  CEventLogTokenBlockSize = 3;
  CEventLogTokenAllocatedByThread = 4;
  CEventLogTokenFreedByThread = 5;
  CEventLogTokenAllocationStackTrace = 6;
  CEventLogTokenFreeStackTrace = 7;
  CEventLogTokenObjectClass = 8;
  CEventLogTokenAllocationNumber = 9;
  CEventLogTokenMemoryDumpSize = 10;
  CEventLogTokenBlockAddress = 11;
  CEventLogTokenHexDump = 12;
  CEventLogTokenASCIIDump = 13;
  CEventLogTokenLeakSummaryEntries = 14;
  CEventLogTokenModifyAfterFreeDetail = 15;
  CEventLogTokenEventLogFilename = 16;

  {The highest ID of an event log token.}
  CEventLogMaxTokenID = 99;

  {The maximum size of an event message, in wide characters.}
  CMaximumEventMessageSize = 32768;

  CFilenameMaxLength = 1024;

  {The size of the memory block reserved for maintaining the list of registered memory leaks.}
  CExpectedMemoryLeaksListSize = 64 * 1024;

  CHexDigits: array[0..15] of Char = '0123456789ABCDEF';

  {The maximum size of hexadecimal and ASCII dumps.}
  CMemoryDumpMaxBytes = 256;
  CMemoryDumpMaxBytesPerLine = 32;

  {The debug block fill pattern, in several sizes.}
  CDebugFillPattern8B = $8080808080808080;
  CDebugFillPattern4B = $80808080;
  CDebugFillPattern2B = $8080;
  CDebugFillPattern1B = $80;

type

  {Event log token values are pointers #0 terminated text strings.  The payload for the tokens is in TokenData.}
  TEventLogTokenValues = array[0..CEventLogMaxTokenID] of PWideChar;

  TMoveProc = procedure(const ASource; var ADest; ACount: NativeInt);

  TIntegerWithABACounter = record
    case Integer of
      0: (IntegerAndABACounter: Int64);
      1: (IntegerValue, ABACounter: Integer);
  end;

{$PointerMath On}
  PSmallIntArray = ^SmallInt;
  PIntegerArray = ^Integer;
  PInt64Array = ^Int64;
{$PointerMath Off}

  {------------------------Small block structures------------------------}

  {Small blocks have a 16-bit header.}
  TSmallBlockHeader = record
    {
    Bit 0: Block is free flag
      0 = Block is in use
      1 = Block is free

    Bit 1: Debug flag
      0 = the block contains no additional debug information
      1 = the block contains a debug mode sub-block

    Bits 3..15 (0..8191):
      The offset of the block from the start of the small block span header, divided by 64.
    }
    BlockStatusFlagsAndSpanOffset: Word;
  end;
  PSmallBlockHeader = ^TSmallBlockHeader;

  {Small block layout:
    Offset: -2 = This block's header
    Offset: 0 = User data / Pointer to next free block (if this block is free)}

  PSmallBlockSpanHeader = ^TSmallBlockSpanHeader;

  {Always 64 bytes in size, under both 32-bit and 64-bit}
  TSmallBlockManager = packed record
    {The first/last partially free span in the arena.  This field must be at the same offsets as
    TSmallBlockSpanHeader.NextPartiallyFreeSpan and TSmallBlockSpanHeader.PreviousPartiallyFreeSpan.}
    FirstPartiallyFreeSpan: PSmallBlockSpanHeader; //Do not change position
    LastPartiallyFreeSpan: PSmallBlockSpanHeader; //Do not change position

    {The offset from the start of CurrentSequentialFeedSpan of the last block that was fed sequentially, as well as an
    ABA counter to solve concurrency issues.}
    LastSequentialFeedBlockOffset: TIntegerWithABACounter;

    {The span that is current being used to serve blocks in sequential order, from the last block down to the first.}
    CurrentSequentialFeedSpan: PSmallBlockSpanHeader;

    {Singly linked list of blocks in this arena that should be freed.  If a block must be freed but the arena is
    currently locked by another thread then the block is added to the head of this list.  It is the responsibility of
    the next thread that locks this arena to clean up this list.}
    PendingFreeList: Pointer;

    {The fixed size move procedure used to move data for this block size when it is upsized.  When a block is downsized
    (which typically occurs less often) the variable size move routine is used.}
    UpsizeMoveProcedure: TMoveProc;

    {0 = unlocked, 1 = locked, must be Integer due to RSP-25672}
    SmallBlockManagerLocked: Integer;

    {The minimum and optimal size of a small block span for this block type}
    MinimumSpanSize: Integer;
    OptimalSpanSize: Integer;

    {The block size for this small block manager}
    BlockSize: Word;

{$ifdef 64Bit}
    Padding: array[0..1] of Byte;
{$else}
    Padding: array[0..21] of Byte;
{$endif}
  end;
  PSmallBlockManager = ^TSmallBlockManager;

  TSmallBlockArena = array[0..CSmallBlockTypeCount - 1] of TSmallBlockManager;
  PSmallBlockArena = ^TSmallBlockArena;

  TSmallBlockArenas = array[0..CSmallBlockArenaCount - 1] of TSmallBlockArena;

  {This is always 64 bytes in size in order to ensure proper alignment of small blocks under all circumstances.}
  TSmallBlockSpanHeader = packed record
    {The next and previous spans in this arena that have free blocks of this size.  These fields must be at the same
    offsets as TSmallBlockManager.FirstPartiallyFreeSpan and TSmallBlockManager.LastPartiallyFreeSpan.}
    NextPartiallyFreeSpan: PSmallBlockSpanHeader; //Do not change position
    PreviousPartiallyFreeSpan: PSmallBlockSpanHeader; //Do not change position
    {Pointer to the first free block inside this span.}
    FirstFreeBlock: Pointer;
    {Pointer to the small block manager to which this span belongs.}
    SmallBlockManager: PSmallBlockManager;
    {The total number of blocks in this small block span.}
    TotalBlocksInSpan: Integer;
    {The number of blocks currently in use in this small block span.}
    BlocksInUse: Integer;
{$ifdef 64Bit}
    Padding: array[0..21] of Byte;
{$else}
    Padding: array[0..37] of Byte;
{$endif}
    {The header for the first block}
    FirstBlockHeader: TSmallBlockHeader;
  end;

  {------------------------Medium block structures------------------------}

  TMediumBlockHeader = packed record

    {Multiply with CMediumBlockAlignment in order to get the size of the block.}
    MediumBlockSizeMultiple: Word;

    {The offset from the start of medium block span header to the start of the block.  Multiply this with
    CMediumBlockAlignment and subtract the result from the pointer in order to obtain the address of the medium block
    span.}
    MediumBlockSpanOffsetMultiple: Word;

    {True if the previous medium block in the medium block span is free.  If this is True then the size of the previous
    block will be stored in the Integer immediately preceding this header.}
    PreviousBlockIsFree: Boolean;
    {True if this medium block is used as a small block span.}
    IsSmallBlockSpan: Boolean;
    {The block status and type}
    BlockStatusFlags: Word;
  end;
  PMediumBlockHeader = ^TMediumBlockHeader;

  {Medium block layout:
   Offset: - SizeOf(TMediumBlockHeader) - 4 = Integer containing the previous block size (only if PreviousBlockIsFree = True)
   Offset: - SizeOf(TMediumBlockHeader) = This block's header
   Offset: 0 = User data / Pointer to previous free block (if this block is free)
   Offset: SizeOf(Pointer) = Next Free Block (if this block is free)
   Offset: BlockSize - SizeOf(TMediumBlockHeader) - 4 = Size of this block (if this block is free)
   Offset: BlockSize - SizeOf(TMediumBlockHeader) = Header for the next block}

  PMediumBlockManager = ^TMediumBlockManager;

  {The medium block span from which medium blocks are drawn.  This is always 64 bytes in size.}
  PMediumBlockSpanHeader = ^TMediumBlockSpanHeader;
  TMediumBlockSpanHeader = packed record
    {Points to the previous and next medium block spans.  This circular linked list is used to track memory leaks on
    program shutdown.  Must be at the same offsets as TMediumBlockManager.FirstMediumBlockSpan and
    TMediumBlockManager.LastMediumBlockSpan.}
    NextMediumBlockSpanHeader: PMediumBlockSpanHeader; //Do not change position
    PreviousMediumBlockSpanHeader: PMediumBlockSpanHeader; //Do not change position
    {The arena to which this medium block span belongs.}
    MediumBlockArena: PMediumBlockManager;
    {The size of this medium block span, in bytes.}
    SpanSize: Integer;
{$ifdef 64Bit}
    Padding: array[0..27] of Byte;
{$else}
    Padding: array[0..39] of Byte;
{$endif}
    {The header for the first block}
    FirstBlockHeader: TMediumBlockHeader;
  end;

  {A medium block that is unused}
  PMediumFreeBlock = ^TMediumFreeBlock;
  TMediumFreeBlock = record
    {This will point to the bin if this is the last free medium block in the bin.}
    NextFreeMediumBlock: PMediumFreeBlock;
    {This will point to the bin if this is the first free medium block in the bin.}
    PreviousFreeMediumBlock: PMediumFreeBlock;
  end;

  TMediumBlockManager = record
    {Maintains a circular list of all medium block spans to enable memory leak detection on program shutdown.}
    FirstMediumBlockSpanHeader: PMediumBlockSpanHeader; //Do not change position
    LastMediumBlockSpanHeader: PMediumBlockSpanHeader; //Do not change position

    {The sequential feed medium block span.}
    LastSequentialFeedBlockOffset: TIntegerWithABACounter;
    SequentialFeedMediumBlockSpan: PMediumBlockSpanHeader;

    {Singly linked list of blocks in this arena that should be freed.  If a block must be freed but the arena is
    currently locked by another thread then the block is added to the head of this list.  It is the responsibility of
    the next thread that locks this arena to clean up this list.}
    PendingFreeList: Pointer;
    {0 = unlocked, 1 = locked, must be Integer due to RSP-25672}
    MediumBlockManagerLocked: Integer;

    {The medium block bins are divided into groups of 32 bins.  If a bit is set in this group bitmap, then at least one
    bin in the group has free blocks.}
    MediumBlockBinGroupBitmap: Cardinal;
    {The medium block bins:  total of 32 * 32 = 1024 bins of a certain minimum size.  The minimum size of blocks in the
    first bin will be CMinimumMediumBlockSize.}
    MediumBlockBinBitmaps: array[0..CMediumBlockBinGroupCount - 1] of Cardinal;
    {The medium block bins.  There are 1024 LIFO circular linked lists each holding blocks of a specified minimum size.
    The bin sizes vary from CMinimumMediumBlockSize to CMaximumMediumBlockSize.  The value for each bin is a pointer to
    the first free medium block in the bin.  Will point to itself if the bin is empty.  The last block in the bin will
    point back to the bin.}
    FirstFreeBlockInBin: array[0..CMediumBlockBinCount - 1] of Pointer;
  end;

  TMediumBlockArenas = array[0..CMediumBlockArenaCount - 1] of TMediumBlockManager;

  {-------------------------Large block structures------------------------}

  PLargeBlockManager = ^TLargeBlockManager;

  {Large block header.  Always 64 bytes in size.}
  PLargeBlockHeader = ^TLargeBlockHeader;
  TLargeBlockHeader = packed record
    {Points to the previous and next large blocks.  This circular linked list is used to track memory leaks on program
    shutdown.}
    NextLargeBlockHeader: PLargeBlockHeader; //Do not change position
    PreviousLargeBlockHeader: PLargeBlockHeader; //Do not change position
    {The large block arena to which this block belongs.}
    LargeBlockArena: PLargeBlockManager;
    {The actual block size as obtained from the operating system.}
    ActualBlockSize: NativeInt;
    {The user allocated size of the large block}
    UserAllocatedSize: NativeInt;
    {If True then the large block is built up from more than one chunk allocated through VirtualAlloc}
    BlockIsSegmented: Boolean;
    {Alignment padding}
{$ifdef 64Bit}
    Padding: array[0..20] of Byte;
{$else}
    Padding: array[0..40] of Byte;
{$endif}
    {The block status and type}
    BlockStatusFlags: Word;
  end;

  TLargeBlockManager = record
    {Maintains a circular list of all large blocks to enable memory leak detection on program shutdown.}
    FirstLargeBlockHeader: PLargeBlockHeader; //Do not change position
    LastLargeBlockHeader: PLargeBlockHeader; //Do not change position
    {Singly linked list of blocks in this arena that should be freed.  If a block must be freed but the arena is
    currently locked by another thread then the block is added to the head of this list.  It is the responsibility of
    the next thread that locks this arena to clean up this list.}
    PendingFreeList: Pointer;
    {0 = unlocked, 1 = locked, must be Integer due to RSP-25672}
    LargeBlockManagerLocked: Integer; //0 = unlocked, 1 = locked
  end;
  TLargeBlockArenas = array[0..CLargeBlockArenaCount - 1] of TLargeBlockManager;

  {---------Management variables----------}

  TSmallBlockTypeInfo = record
    BlockSize: Word;
    UpsizeMoveProcedure: TMoveProc;
  end;
  PSmallBlockTypeInfo = ^TSmallBlockTypeInfo;

  {-------------------------Expected Memory Leak Structures--------------------}

  {The layout of an expected leak.  All fields may not be specified, in which case it may be harder to determine which
  leaks are expected and which are not.}
  PExpectedMemoryLeak = ^TExpectedMemoryLeak;
  PPExpectedMemoryLeak = ^PExpectedMemoryLeak;
  TExpectedMemoryLeak = record
    {Leaks are maintained in doubly linked list.}
    PreviousLeak, NextLeak: PExpectedMemoryLeak;
    LeakAddress: Pointer;
    LeakedClass: TClass;
    LeakSize: NativeInt;
    LeakCount: Integer;
  end;

  TExpectedMemoryLeaks = record
    {The number of entries used in the expected leaks buffer}
    EntriesUsed: Integer;
    {Freed entries that are available for reuse}
    FirstFreeSlot: PExpectedMemoryLeak;
    {Entries with the address specified}
    FirstEntryByAddress: PExpectedMemoryLeak;
    {Entries with no address specified, but with the class specified}
    FirstEntryByClass: PExpectedMemoryLeak;
    {Entries with only size specified}
    FirstEntryBySizeOnly: PExpectedMemoryLeak;
    {The expected leaks buffer (Need to leave space for this header)}
    ExpectedLeaks: array[0..(CExpectedMemoryLeaksListSize - 64) div SizeOf(TExpectedMemoryLeak) - 1] of TExpectedMemoryLeak;
  end;
  PExpectedMemoryLeaks = ^TExpectedMemoryLeaks;

  {-------Memory leak reporting structures--------}

  TMemoryLeakType = (mltUnexpectedLeak, mltExpectedLeakRegisteredByPointer, mltExpectedLeakRegisteredByClass,
    mltExpectedLeakRegisteredBySize);

  TMemoryAccessRight = (marExecute, marRead, marWrite);
  TMemoryAccessRights = set of TMemoryAccessRight;
  TMemoryRegionInfo = record
    RegionStartAddress: Pointer;
    RegionSize: NativeUInt;
    RegionIsFree: Boolean;
    AccessRights: TMemoryAccessRights;
  end;

  {Used by the DetectStringData routine to detect whether a leaked block contains string data.}
  TStringDataType = (stNotAString, stAnsiString, stUnicodeString);

  {An entry in the binary search tree of memory leaks.  Leaks are grouped by block size and class.}
  TMemoryLeakSummaryEntry = record
    {The user size of the block}
    BlockUsableSize: NativeInt;
    {The content of the leaked block.}
    BlockContentType: NativeUInt; //0 = unknown, 1 = AnsiString, 2 = UnicodeString, other values = class pointer
    {The number of leaks of this block size and content type.}
    NumLeaks: NativeInt;
    {The indexes of the left (False) and right (True) leaks in the binary search tree.}
    ChildIndexes: array[Boolean] of Integer;
  end;
  PMemoryLeakSummaryEntry = ^TMemoryLeakSummaryEntry;

  TMemoryLeakSummary = record
    MemoryLeakEntries: array[0..4095] of TMemoryLeakSummaryEntry;
    LeakCount: Integer;
  end;
  PMemoryLeakSummary = ^TMemoryLeakSummary;

  {-------Legacy debug support DLL interface--------}
  {The interface for the legacy (version 4) stack trace conversion routine in the FastMM_FullDebugMode library.}
  TFastMM_LegacyConvertStackTraceToText = function(APReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
    APBuffer: PAnsiChar): PAnsiChar;

{Fixed size move procedures.  The 64-bit versions assume 16-byte alignment.}
procedure Move6(const ASource; var ADest; ACount: NativeInt); forward;
procedure Move14(const ASource; var ADest; ACount: NativeInt); forward;
procedure Move22(const ASource; var ADest; ACount: NativeInt); forward;
procedure Move30(const ASource; var ADest; ACount: NativeInt); forward;
procedure Move38(const ASource; var ADest; ACount: NativeInt); forward;
procedure Move46(const ASource; var ADest; ACount: NativeInt); forward;
{Variable size move routines.}
procedure MoveMultipleOf16Plus6(const ASource; var ADest; ACount: NativeInt); forward;
procedure MoveMultipleOf16Plus14(const ASource; var ADest; ACount: NativeInt); forward;
procedure MoveMultipleOf32Plus30(const ASource; var ADest; ACount: NativeInt); forward;

const
  {Structure size constants}
  CSmallBlockHeaderSize = SizeOf(TSmallBlockHeader);
  CMediumBlockHeaderSize = SizeOf(TMediumBlockHeader);
  CLargeBlockHeaderSize = SizeOf(TLargeBlockHeader);
  CDebugBlockHeaderSize = SizeOf(TFastMM_DebugBlockHeader);
  CDebugBlockFooterSize = SizeOf(NativeUInt);

  CSmallBlockSpanHeaderSize = SizeOf(TSmallBlockSpanHeader);
  CMediumBlockSpanHeaderSize = SizeOf(TMediumBlockSpanHeader);

  CSmallBlockManagerSize = SizeOf(TSmallBlockManager);

  {Small block sizes (including the header)}
  CSmallBlockTypeInfo: array[0..CSmallBlockTypeCount - 1] of TSmallBlockTypeInfo = (
    {8 byte jumps}
    (BlockSize: 8; UpsizeMoveProcedure: Move6),
    (BlockSize: 16; UpsizeMoveProcedure: Move14),
    (BlockSize: 24; UpsizeMoveProcedure: Move22),
    (BlockSize: 32; UpsizeMoveProcedure: Move30),
    (BlockSize: 40; UpsizeMoveProcedure: Move38),
    (BlockSize: 48; UpsizeMoveProcedure: Move46),
    (BlockSize: 56; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 64; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 72; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 80; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 88; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 96; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 104; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 112; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 120; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 128; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 136; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 144; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 152; UpsizeMoveProcedure: MoveMultipleOf16Plus6),
    (BlockSize: 160; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    {16 byte jumps}
    (BlockSize: 176; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 192; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 208; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 224; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 240; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 256; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 272; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 288; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 304; UpsizeMoveProcedure: MoveMultipleOf16Plus14),
    (BlockSize: 320; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    {32 byte jumps}
    (BlockSize: 352; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 384; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 416; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 448; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 480; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 512; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 544; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 576; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 608; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    (BlockSize: 640; UpsizeMoveProcedure: MoveMultipleOf32Plus30),
    {64 byte jumps}
    (BlockSize: 704),
    (BlockSize: 768),
    (BlockSize: 832),
    (BlockSize: 896),
    (BlockSize: 960),
    (BlockSize: 1024),
    (BlockSize: 1088),
    (BlockSize: 1152),
    (BlockSize: 1216),
    (BlockSize: 1280),
    (BlockSize: 1344),
    {128 byte jumps}
    (BlockSize: 1472),
    (BlockSize: 1600),
    (BlockSize: 1728),
    (BlockSize: 1856),
    (BlockSize: 1984),
    (BlockSize: 2112),
    (BlockSize: 2240),
    (BlockSize: 2368),
    (BlockSize: 2496),
    (BlockSize: CMaximumSmallBlockSize)
  );

var
  AlignmentRequestCounters: array[TFastMM_MinimumAddressAlignment] of Integer;

  SmallBlockTypeLookup: array[0.. CMaximumSmallBlockSize div CSmallBlockGranularity - 1] of Byte;

  SmallBlockArenas: TSmallBlockArenas;
  MediumBlockArenas: TMediumBlockArenas;
  LargeBlockArenas: TLargeBlockArenas;

  {The default size of new medium block spans.  Must be a multiple of 64K and may not exceed CMaximumMediumBlockSpanSize.}
  DefaultMediumBlockSpanSize: Integer;

  {The current optimization stategy in effect.}
  OptimizationStrategy: TFastMM_MemoryManagerOptimizationStrategy;

{$ifdef 32Bit}
  {Pointer to the emergency reserve address space.  This allows some subsequent memory allocation requests to succeed
  in order to allow the application to allocate some memory for error handling, etc. in response to the first
  EOutOfMemory exception.  This only applies to 32-bit applications.}
  EmergencyReserveAddressSpace: Pointer;
{$endif}

  CurrentInstallationState: TFastMM_MemoryManagerInstallationState;

  {The difference between the number of times EnterDebugMode has been called vs ExitDebugMode.}
  DebugModeCounter: Integer;
  SettingMemoryManager: Integer; //0 = False, 1 = True;

  {The memory manager that was in place before this memory manager was installed.}
  PreviousMemoryManager: TMemoryManagerEx;
  {The memory manager that is currently set.  This is used to detect the installation of another 3rd party memory
  manager which would prevent the switching between debug and normal mode.}
  InstalledMemoryManager: TMemoryManagerEx;
  {The handle to the debug mode support DLL.}
  DebugSupportLibraryHandle: NativeUInt;
  DebugSupportConfigured: Boolean;
  {The stack trace routines from the FastMM_FullDebugMode support DLL.  These will only be set if the support DLL is
  loaded.}
  DebugLibrary_GetRawStackTrace: TFastMM_GetStackTrace;
  DebugLibrary_GetFrameBasedStackTrace: TFastMM_GetStackTrace;
  DebugLibrary_LogStackTrace_Legacy: TFastMM_LegacyConvertStackTraceToText;

  {The default event log filename is stored in this buffer.}
  DefaultEventLogFilename: array[0..CFilenameMaxLength] of WideChar;

  {The expected memory leaks list}
  ExpectedMemoryLeaks: PExpectedMemoryLeaks;
  ExpectedMemoryLeaksListLocked: Integer; //1 = Locked

{$ifdef MSWindows}
  {A string uniquely identifying the current process (for sharing the memory manager between DLLs and the main
  application).}
  SharingFileMappingObjectName: array[0..25] of AnsiChar = ('L', 'o', 'c', 'a', 'l', '\', 'F', 'a', 's', 't', 'M', 'M',
    '_', 'P', 'I', 'D', '_', '?', '?', '?', '?', '?', '?', '?', '?', #0);
  {The handle of the memory mapped file.}
  SharingFileMappingObjectHandle: NativeUInt;
{$endif}


{------------------------------------------}
{--------------Move routines---------------}
{------------------------------------------}

procedure Move6(const ASource; var ADest; ACount: NativeInt);
begin
  PIntegerArray(@ADest)[0] := PIntegerArray(@ASource)[0];
  PSmallIntArray(@ADest)[2] := PSmallIntArray(@ASource)[2];
end;

procedure Move14(const ASource; var ADest; ACount: NativeInt);
begin
  PInt64Array(@ADest)[0] := PInt64Array(@ASource)[0];
  PIntegerArray(@ADest)[2] := PIntegerArray(@ASource)[2];
  PSmallIntArray(@ADest)[6] := PSmallIntArray(@ASource)[6];
end;

procedure Move22(const ASource; var ADest; ACount: NativeInt);
begin
  PInt64Array(@ADest)[0] := PInt64Array(@ASource)[0];
  PInt64Array(@ADest)[1] := PInt64Array(@ASource)[1];
  PIntegerArray(@ADest)[4] := PIntegerArray(@ASource)[4];
  PSmallIntArray(@ADest)[10] := PSmallIntArray(@ASource)[10];
end;

procedure Move30(const ASource; var ADest; ACount: NativeInt);
begin
  PInt64Array(@ADest)[0] := PInt64Array(@ASource)[0];
  PInt64Array(@ADest)[1] := PInt64Array(@ASource)[1];
  PInt64Array(@ADest)[2] := PInt64Array(@ASource)[2];
  PIntegerArray(@ADest)[6] := PIntegerArray(@ASource)[6];
  PSmallIntArray(@ADest)[14] := PSmallIntArray(@ASource)[14];
end;

procedure Move38(const ASource; var ADest; ACount: NativeInt);
begin
  PInt64Array(@ADest)[0] := PInt64Array(@ASource)[0];
  PInt64Array(@ADest)[1] := PInt64Array(@ASource)[1];
  PInt64Array(@ADest)[2] := PInt64Array(@ASource)[2];
  PInt64Array(@ADest)[3] := PInt64Array(@ASource)[3];
  PIntegerArray(@ADest)[8] := PIntegerArray(@ASource)[8];
  PSmallIntArray(@ADest)[18] := PSmallIntArray(@ASource)[18];
end;

procedure Move46(const ASource; var ADest; ACount: NativeInt);
begin
  PInt64Array(@ADest)[0] := PInt64Array(@ASource)[0];
  PInt64Array(@ADest)[1] := PInt64Array(@ASource)[1];
  PInt64Array(@ADest)[2] := PInt64Array(@ASource)[2];
  PInt64Array(@ADest)[3] := PInt64Array(@ASource)[3];
  PInt64Array(@ADest)[4] := PInt64Array(@ASource)[4];
  PIntegerArray(@ADest)[10] := PIntegerArray(@ASource)[10];
  PSmallIntArray(@ADest)[22] := PSmallIntArray(@ASource)[22];
end;

procedure MoveMultipleOf16Plus6(const ASource; var ADest; ACount: NativeInt);
var
  LPSource, LPDest: PByte;
begin
  LPSource := @PByte(@ASource)[ACount - 6];
  LPDest := @PByte(@ADest)[ACount - 6];
  ACount := 6 - ACount;

  while True do
  begin
    PInt64Array(@LPDest[ACount])[0] := PInt64Array(@LPSource[ACount])[0];
    PInt64Array(@LPDest[ACount])[1] := PInt64Array(@LPSource[ACount])[1];

    Inc(ACount, 16);
    if ACount >= 0 then
      Break;
  end;

  PIntegerArray(LPDest)[0] := PIntegerArray(LPSource)[0];
  PSmallIntArray(LPDest)[2] := PSmallIntArray(LPSource)[2];
end;

procedure MoveMultipleOf16Plus14(const ASource; var ADest; ACount: NativeInt);
var
  LPSource, LPDest: PByte;
begin
  LPSource := @PByte(@ASource)[ACount - 14];
  LPDest := @PByte(@ADest)[ACount - 14];
  ACount := 14 - ACount;

  while True do
  begin
    PInt64Array(@LPDest[ACount])[0] := PInt64Array(@LPSource[ACount])[0];
    PInt64Array(@LPDest[ACount])[1] := PInt64Array(@LPSource[ACount])[1];

    Inc(ACount, 16);
    if ACount >= 0 then
      Break;
  end;

  PInt64Array(LPDest)[0] := PInt64Array(LPSource)[0];
  PIntegerArray(LPDest)[2] := PIntegerArray(LPSource)[2];
  PSmallIntArray(LPDest)[6] := PSmallIntArray(LPSource)[6];
end;

procedure MoveMultipleOf32Plus30(const ASource; var ADest; ACount: NativeInt);
var
  LPSource, LPDest: PByte;
begin
  LPSource := @PByte(@ASource)[ACount - 30];
  LPDest := @PByte(@ADest)[ACount - 30];
  ACount := 30 - ACount;

  while True do
  begin
    PInt64Array(@LPDest[ACount])[0] := PInt64Array(@LPSource[ACount])[0];
    PInt64Array(@LPDest[ACount])[1] := PInt64Array(@LPSource[ACount])[1];
    PInt64Array(@LPDest[ACount])[2] := PInt64Array(@LPSource[ACount])[2];
    PInt64Array(@LPDest[ACount])[3] := PInt64Array(@LPSource[ACount])[3];

    Inc(ACount, 32);
    if ACount >= 0 then
      Break;
  end;

  PInt64Array(LPDest)[0] := PInt64Array(LPSource)[0];
  PInt64Array(LPDest)[1] := PInt64Array(LPSource)[1];
  PInt64Array(LPDest)[2] := PInt64Array(LPSource)[2];
  PIntegerArray(LPDest)[6] := PIntegerArray(LPSource)[6];
  PSmallIntArray(LPDest)[14] := PSmallIntArray(LPSource)[14];
end;


{------------------------------------------}
{---------Operating system calls-----------}
{------------------------------------------}

procedure ReleaseEmergencyReserveAddressSpace; forward;
function CharCount(APFirstFreeChar, APBufferStart: PWideChar): Integer; forward;

{Allocates a block of memory from the operating system.  The block is assumed to be aligned to at least a 64 byte
boundary, and is assumed to be zero initialized.  Returns nil on error.}
function OS_AllocateVirtualMemory(ABlockSize: NativeInt; AAllocateTopDown: Boolean;
  AReserveOnlyNoReadWriteAccess: Boolean): Pointer;
begin
  if AReserveOnlyNoReadWriteAccess then
  begin
    Result := Winapi.Windows.VirtualAlloc(nil, ABlockSize, MEM_RESERVE, PAGE_NOACCESS);
  end
  else
  begin
    Result := Winapi.Windows.VirtualAlloc(nil, ABlockSize, MEM_COMMIT, PAGE_READWRITE);
    {The emergency address space reserve is released when address space runs out for the first time.  This allows some
    subsequent memory allocation requests to succeed in order to allow the application to allocate some memory for error
    handling, etc. in response to the EOutOfMemory exception.  This only applies to 32-bit applications.}
    if Result = nil then
      ReleaseEmergencyReserveAddressSpace;
  end;
end;

function OS_AllocateVirtualMemoryAtAddress(APAddress: Pointer; ABlockSize: NativeInt;
  AReserveOnlyNoReadWriteAccess: Boolean): Boolean;
begin
  if AReserveOnlyNoReadWriteAccess then
  begin
    Result := Winapi.Windows.VirtualAlloc(APAddress, ABlockSize, MEM_RESERVE, PAGE_NOACCESS) <> nil;
  end
  else
  begin
    Result := (Winapi.Windows.VirtualAlloc(APAddress, ABlockSize, MEM_RESERVE, PAGE_READWRITE) <> nil)
      and (Winapi.Windows.VirtualAlloc(APAddress, ABlockSize, MEM_COMMIT, PAGE_READWRITE) <> nil);
  end;
end;

{Releases a block of memory back to the operating system.  Returns 0 on success, -1 on failure.}
function OS_FreeVirtualMemory(APointer: Pointer): Integer;
begin
  if Winapi.Windows.VirtualFree(APointer, 0, MEM_RELEASE) then
    Result := 0
  else
    Result := -1;
end;

{Determines the size and state of the virtual memory region starting at APRegionStart.  APRegionStart is assumed to be
rounded to a page (4K) boundary.}
procedure OS_GetVirtualMemoryRegionInfo(APRegionStart: Pointer; var AMemoryRegionInfo: TMemoryRegionInfo);
var
  LMemInfo: TMemoryBasicInformation;
begin
  Winapi.Windows.VirtualQuery(APRegionStart, LMemInfo, SizeOf(LMemInfo));

  AMemoryRegionInfo.RegionStartAddress := LMemInfo.BaseAddress;
  AMemoryRegionInfo.RegionSize := LMemInfo.RegionSize;
  AMemoryRegionInfo.RegionIsFree := LMemInfo.State = MEM_FREE;
  AMemoryRegionInfo.AccessRights := [];
  if (LMemInfo.State = MEM_COMMIT) and (LMemInfo.Protect and PAGE_GUARD = 0) then
  begin
    if (LMemInfo.Protect and (PAGE_READONLY or PAGE_READWRITE or PAGE_EXECUTE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY) <> 0) then
      Include(AMemoryRegionInfo.AccessRights, marRead);
    if (LMemInfo.Protect and (PAGE_READWRITE or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY) <> 0) then
      Include(AMemoryRegionInfo.AccessRights, marWrite);
    if (LMemInfo.Protect and (PAGE_EXECUTE or PAGE_EXECUTE_READ or PAGE_EXECUTE_READWRITE or PAGE_EXECUTE_WRITECOPY) <> 0) then
      Include(AMemoryRegionInfo.AccessRights, marExecute);
  end;
end;

{If another thread is ready to run on the current CPU, give it a chance to execute.  This is typically called if the
current thread is unable to make any progress, because it is waiting for locked resources.}
procedure OS_AllowOtherThreadToRun;
begin
  Winapi.Windows.SwitchToThread;
end;

{Returns the thread ID for the calling thread.}
function OS_GetCurrentThreadID: Cardinal;
begin
  Result := Winapi.Windows.GetCurrentThreadID;
end;

{Returns the current system date and time.  The time is in 24 hour format.}
procedure OS_GetCurrentDateTime(var AYear, AMonth, ADay, AHour, AMinute, ASecond: Word);
var
  LSystemTime: TSystemTime;
begin
  Winapi.Windows.GetLocalTime(LSystemTime);
  AYear := LSystemTime.wYear;
  AMonth := LSystemTime.wMonth;
  ADay := LSystemTime.wDay;
  AHour := LSystemTime.wHour;
  AMinute := LSystemTime.wMinute;
  ASecond := LSystemTime.wSecond;
end;

{Fills a buffer with the full path and filename of the application.  If AReturnLibraryFilename = True and this is a
library then the full path and filename of the library is returned instead.}
function OS_GetApplicationFilename(AReturnLibraryFilename: Boolean; APFilenameBuffer, APBufferEnd: PWideChar): PWideChar;
var
  LModuleHandle: HMODULE;
  LNumChars: Cardinal;
begin
  Result := APFilenameBuffer;

  LModuleHandle := 0;
  if AReturnLibraryFilename and IsLibrary then
    LModuleHandle := HInstance;

  LNumChars := Winapi.Windows.GetModuleFileNameW(LModuleHandle, Result, CharCount(APBufferEnd, APFilenameBuffer));
  Inc(Result, LNumChars);
end;

function OS_GetEnvironmentVariableValue(APEnvironmentVariableName, APValueBuffer, APBufferEnd: PWideChar): PWideChar;
var
  LNumChars, LBufferSize: Cardinal;
begin
  Result := APValueBuffer;

  if Result >= APBufferEnd then
    Exit;

  LBufferSize := (NativeInt(APBufferEnd) - NativeInt(Result)) div SizeOf(WideChar);
  LNumChars := Winapi.Windows.GetEnvironmentVariableW(APEnvironmentVariableName, Result, LBufferSize);
  if LNumChars < LBufferSize then
    Inc(Result, LNumChars);
end;

{Returns True if the given file exists.  APFileName must be a #0 terminated.}
function OS_FileExists(APFileName: PWideChar): Boolean;
begin
  {This will return True for folders and False for files that are locked by another process, but is "good enough" for
  the purpose for which it will be used.}
  Result := Winapi.Windows.GetFileAttributesW(APFileName) <> INVALID_FILE_ATTRIBUTES;
end;

{Attempts to delete the file.  Returns True if it was successfully deleted.}
function OS_DeleteFile(APFileName: PWideChar): Boolean;
begin
  Result := Winapi.Windows.DeleteFileW(APFileName);
end;

{Creates the given file if it does not exist yet, and then appends the given data to it.}
function OS_CreateOrAppendFile(APFileName: PWideChar; APData: Pointer; ADataSizeInBytes: Integer): Boolean;
var
  LFileHandle: THandle;
  LBytesWritten: Cardinal;
begin
  if ADataSizeInBytes <= 0 then
    Exit(True);

  {Try to open/create the log file in read/write mode.}
  LFileHandle := Winapi.Windows.CreateFileW(APFileName, GENERIC_READ or GENERIC_WRITE, 0, nil, OPEN_ALWAYS,
    FILE_ATTRIBUTE_NORMAL, 0);
  if LFileHandle = INVALID_HANDLE_VALUE then
    Exit(False);

  {Add the data to the end of the file}
  SetFilePointer(LFileHandle, 0, nil, FILE_END);
  Winapi.Windows.WriteFile(LFileHandle, APData^, Cardinal(ADataSizeInBytes), LBytesWritten, nil);
  Result := LBytesWritten = Cardinal(ADataSizeInBytes);

  CloseHandle(LFileHandle);
end;

procedure OS_OutputDebugString(APDebugMessage: PWideChar);
begin
  Winapi.Windows.OutputDebugString(APDebugMessage);
end;

{Shows a message box if the program is not showing one already.}
procedure OS_ShowMessageBox(APText, APCaption: PWideChar);
begin
  Winapi.Windows.MessageBoxW(0, APText, APCaption, MB_OK or MB_ICONERROR or MB_TASKMODAL or MB_DEFAULT_DESKTOP_ONLY);
end;


{------------------------------------------}
{--------Logging support subroutines-------}
{------------------------------------------}

function CharCount(APFirstFreeChar, APBufferStart: PWideChar): Integer; inline;
begin
  Result := (NativeInt(APFirstFreeChar) - NativeInt(APBufferStart)) div SizeOf(WideChar);
end;

{Converts the UTF-16 text pointed to by APWideText to UTF-8 in the buffer provided.  Returns a pointer to the byte
after the last output character.}
function ConvertUTF16toUTF8(APWideText: PWideChar; ANumWideChars: Integer; APOutputBuffer: PByte): PByte;
var
  LPIn, LPEnd: PWord;
  LCode: Cardinal;
begin
  Result := Pointer(APOutputBuffer);

  LPIn := Pointer(APWideText);
  LPEnd := LPIn;
  Inc(LPEnd, ANumWideChars);

  while NativeUInt(LPIn) < NativeUInt(LPEnd) do
  begin
    LCode := PCardinal(LPIn)^;
    if Word(LCode) <= $7f then
    begin
      if LCode <= $7fffff then
      begin
        {Both characters are single byte}
        PWord(Result)^ := Word(LCode or (LCode shr 8));
        Inc(Result, 2);
        Inc(LPIn, 2);
      end
      else
      begin
        {The second character is not single byte}
        Result[0] := Byte(LCode);
        Inc(Result);
        Inc(LPIn);
      end;
    end
    else
    begin
      if Word(LCode) <= $7ff then
      begin
        {Two byte encoding}
        Result[0] := Byte(LCode shr 6) or $c0;
        Result[1] := Byte(LCode and $3f) or $80;
        Inc(Result, 2);
        Inc(LPIn);
      end
      else
      begin
        if (LCode and $fc00fc00) <> $dc00d800 then
        begin
          {Three byte encoding}
          Result[0] := Byte((LCode shr 12) and $0f) or $e0;
          Result[1] := Byte((LCode shr 6) and $3f) or $80;
          Result[2] := Byte(LCode and $3f) or $80;
          Inc(Result, 3);
          Inc(LPIn);
        end
        else
        begin
          {It is a surrogate pair (4 byte) encoding:  Surrogate pairs are encoded in four bytes, with the high word
          first}
          LCode := ((LCode and $3ff) shl 10) + ((LCode shr 16) and $3ff) + $10000;
          Result[0] := Byte((LCode shr 18) and $07) or $e0;
          Result[1] := Byte((LCode shr 12) and $3f) or $80;
          Result[2] := Byte((LCode shr 6) and $3f) or $80;
          Result[3] := Byte(LCode and $3f) or $80;
          Inc(Result, 4);
          Inc(LPIn, 2);
        end;
      end;
    end;
  end;
  {Did we convert past the end?}
  if NativeUInt(LPIn) > NativeUInt(LPEnd) then
    Dec(Result);
end;

{Returns the class for a memory block.  Returns nil if it is not a valid class.  Used by the leak detection code.}
function DetectClassInstance(APointer: Pointer): TClass;
var
  LMemoryRegionInfo: TMemoryRegionInfo;

  {Checks whether the given address is a valid address for a VMT entry.}
  function IsValidVMTAddress(APAddress: Pointer): Boolean;
  begin
    {Do some basic pointer checks:  Must be pointer aligned and beyond 64K}
    if (NativeUInt(APAddress) > 65535)
      and (NativeUInt(APAddress) and (SizeOf(Pointer) - 1) = 0) then
    begin
      {Do we need to recheck the virtual memory?}
      if (NativeUInt(LMemoryRegionInfo.RegionStartAddress) > NativeUInt(APAddress))
        or ((NativeUInt(LMemoryRegionInfo.RegionStartAddress) + LMemoryRegionInfo.RegionSize) < (NativeUInt(APAddress) + SizeOf(Pointer))) then
      begin
        OS_GetVirtualMemoryRegionInfo(APAddress, LMemoryRegionInfo);
      end;
      Result := (not LMemoryRegionInfo.RegionIsFree)
        and (marRead in LMemoryRegionInfo.AccessRights);
    end
    else
      Result := False;
  end;

  {Returns True if AClassPointer points to a class VMT}
  function InternalIsValidClass(AClassPointer: Pointer; ADepth: Integer = 0): Boolean;
  var
    LParentClassSelfPointer: PPointer;
  begin
    {Check that the self pointer as well as parent class self pointer addresses are valid}
    if (ADepth < 1000)
      and IsValidVMTAddress(Pointer(PByte(AClassPointer) + vmtSelfPtr))
      and IsValidVMTAddress(Pointer(PByte(AClassPointer) + vmtParent)) then
    begin
      {Get a pointer to the parent class' self pointer}
      LParentClassSelfPointer := PPointer(PByte(AClassPointer) + vmtParent)^;
      {Check that the self pointer as well as the parent class is valid}
      Result := (PPointer(PByte(AClassPointer) + vmtSelfPtr)^ = AClassPointer)
        and ((LParentClassSelfPointer = nil)
          or (IsValidVMTAddress(LParentClassSelfPointer)
            and InternalIsValidClass(LParentClassSelfPointer^, ADepth + 1)));
    end
    else
      Result := False;
  end;

begin
  {Get the class pointer from the (suspected) object}
  Result := TClass(PPointer(APointer)^);
  {No VM info yet}
  LMemoryRegionInfo.RegionSize := 0;
  {Check the block}
  if (not InternalIsValidClass(Pointer(Result), 0)) then
    Result := nil;
end;

{Detects the probable string data type for a memory block.  Used by the leak classification code when a block cannot be
identified as a known class instance.}
function DetectStringData(APMemoryBlock: Pointer; AAvailableSpaceInBlock: NativeInt): TStringDataType;
type
  {The layout of a string header.}
  PStrRec = ^StrRec;
  StrRec = packed record
{$ifdef 64Bit}
    _Padding: Integer;
{$endif}
    codePage: Word;
    elemSize: Word;
    refCnt: Integer;
    length: Integer;
  end;
const
  {If the string reference count field contains a value greater than this, then it is assumed that the block is not a
  string.}
  CMaxRefCount = 255;
  {The lowest ASCII character code considered valid string data.  If there are any characters below this code point
  then the data is assumed not to be a string.}
  CMinCharCode = #9; //#9 = Tab.
var
  LStringLength, LElementSize, LCharInd: Integer;
  LPAnsiString: PAnsiChar;
  LPUnicodeString: PWideChar;
begin
  {Check that the reference count is within a reasonable range}
  if PStrRec(APMemoryBlock).refCnt > CMaxRefCount then
    Exit(stNotAString);

  {Element size must be either 1 (Ansi) or 2 (Unicode)}
  LElementSize := PStrRec(APMemoryBlock).elemSize;
  if (LElementSize <> 1) and (LElementSize <> 2) then
    Exit(stNotAString);

  {Get the string length and check whether it fits inside the block}
  LStringLength := PStrRec(APMemoryBlock).length;
  if (LStringLength <= 0)
    or (LStringLength >= (AAvailableSpaceInBlock - SizeOf(StrRec)) div LElementSize) then
  begin
    Exit(stNotAString);
  end;

  {Check for no characters outside the expected range.  If there are, then it is probably not a string.}
  if LElementSize = 1 then
  begin
    LPAnsiString := PAnsiChar(PByte(APMemoryBlock) + SizeOf(StrRec));

    {There must be a trailing #0}
    if LPAnsiString[LStringLength] <> #0 then
      Exit(stNotAString);

    {Check that all characters are in the range considered valid.}
    for LCharInd := 0 to LStringLength - 1 do
    begin
      if LPAnsiString[LCharInd] < CMinCharCode then
        Exit(stNotAString);
    end;

    Result := stAnsiString;
  end
  else
  begin
    LPUnicodeString := PWideChar(PByte(APMemoryBlock) + SizeOf(StrRec));

    {There must be a trailing #0}
    if LPUnicodeString[LStringLength] <> #0 then
      Exit(stNotAString);

    {Check that all characters are in the range considered valid.}
    for LCharInd := 0 to LStringLength - 1 do
    begin
      if LPUnicodeString[LCharInd] < CMinCharCode then
        Exit(stNotAString);
    end;

    Result := stUnicodeString;
  end;
end;

{Attempts to detect the class or string type of the given block.  Possible return values are:
  0 = Unknown class
  1 = AnsiString text
  1 = UnicodeString text
  > 1 = TClass Pointer}
function DetectBlockContentType(APMemoryBlock: Pointer; AAvailableSpaceInBlock: NativeInt): NativeUInt;
var
  LLeakedClass: TClass;
  LStringType: TStringDataType;
begin
  {Attempt to determine the class type for the block.}
  LLeakedClass := DetectClassInstance(APMemoryBlock);
  if LLeakedClass <> nil then
    Exit(NativeUInt(LLeakedClass));

  LStringType := DetectStringData(APMemoryBlock, AAvailableSpaceInBlock);
  Result := Ord(LStringType);
end;

{Counts the number of characters up to the trailing #0}
function GetStringLength(APWideText: PWideChar): Integer;
begin
  Result := 0;

  if APWideText = nil then
    Exit;

  while APWideText^ <> #0 do
  begin
    Inc(Result);
    Inc(APWideText);
  end;
end;

{Adds text to a buffer, returning the new buffer position.}
function AppendTextToBuffer(APSource: PWideChar; ACharCount: Integer;
  APTarget, APTargetBufferEnd: PWideChar): PWideChar; overload;
begin
  Result := APTarget;

  if @Result[ACharCount] > APTargetBufferEnd then
    ACharCount := CharCount(APTargetBufferEnd, Result);

  if ACharCount > 0 then
  begin
    System.Move(APSource^, Result^, ACharCount * SizeOf(WideChar));
    Inc(Result, ACharCount);
  end;
end;

{As above, but if APSource is non-nil then it is assumed to be #0 terminated.  The trailing #0 is not copied.}
function AppendTextToBuffer(APSource, APTarget, APTargetBufferEnd: PWideChar): PWideChar; overload;
var
  LChar: WideChar;
begin
  Result := APTarget;

  if APSource = nil then
    Exit;

  while Result < APTargetBufferEnd do
  begin
    LChar := APSource^;
    if LChar = #0 then
      Break;

    Result^ := LChar;
    Inc(APSource);
    Inc(Result);
  end;
end;

{Converts a NativeUInt to hexadecimal text in the given target buffer.}
function NativeUIntToHexadecimalBuffer(AValue: NativeUInt; APTarget, APTargetBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..15] of WideChar;
  LDigit: NativeInt;
  LDigitCount: Integer;
  LPPos: PWideChar;
begin
  Result := APTarget;

  LPPos := @LTempBuffer[High(LTempBuffer)];
  LDigitCount := 0;
  while True do
  begin
    LDigit := AValue mod 16;
    LPPos^ := CHexDigits[LDigit];
    Inc(LDigitCount);

    AValue := AValue div 16;
    if AValue = 0 then
      Break;

    Dec(LPPos);
  end;

  Result := AppendTextToBuffer(LPPos, LDigitCount, Result, APTargetBufferEnd);
end;

{Converts a NativeUInt to text in the given target buffer.}
function NativeUIntToTextBuffer(AValue: NativeUInt; APTarget, APTargetBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..20] of WideChar;
  LDigit: NativeInt;
  LDigitCount: Integer;
  LPPos: PWideChar;
begin
  Result := APTarget;

  LPPos := @LTempBuffer[High(LTempBuffer)];
  LDigitCount := 0;
  while True do
  begin
    LDigit := AValue mod 10;
    LPPos^ := WideChar(Ord('0') + LDigit);
    Inc(LDigitCount);

    AValue := AValue div 10;
    if AValue = 0 then
      Break;

    Dec(LPPos);
  end;

  Result := AppendTextToBuffer(LPPos, LDigitCount, Result, APTargetBufferEnd);
end;

{Converts a NativeInt to text in the given target buffer.}
function NativeIntToTextBuffer(AValue: NativeInt; APTarget, APTargetBufferEnd: PWideChar): PWideChar;
const
  CMinusSign: PWideChar = '-';
begin
  Result := APTarget;

  if AValue < 0 then
    Result := AppendTextToBuffer(@CMinusSign, 1, Result, APTargetBufferEnd);

  Result := NativeUIntToTextBuffer(Abs(AValue), Result, APTargetBufferEnd);
end;

function BlockContentTypeToTextBuffer(ABlockContentType: NativeUInt; APTarget, APTargetBufferEnd: PWideChar): PWideChar;
type
  PClassData = ^TClassData;
  TClassData = record
    ClassType: TClass;
    ParentInfo: Pointer;
    PropCount: SmallInt;
    UnitName: ShortString;
  end;
const
  CUnknown = 'Unknown';
  CAnsiString = 'AnsiString';
  CUnicodeString = 'UnicodeString';
var
  LClass: TClass;
  LBuffer: array[0..511] of WideChar;
  LPTarget: PWideChar;
  LPSource: PAnsiChar;
  LCharInd, LNumChars: Integer;
  LClassInfo: Pointer;
  LPShortString: PShortString;
begin
  Result := APTarget;

  case ABlockContentType of
    0: Result := AppendTextToBuffer(CUnknown, Length(CUnknown), Result, APTargetBufferEnd);
    1: Result := AppendTextToBuffer(CAnsiString, Length(CAnsiString), Result, APTargetBufferEnd);
    2: Result := AppendTextToBuffer(CUnicodeString, Length(CUnicodeString), Result, APTargetBufferEnd);

    else
    begin
      {All other content types are classes.}
      LClass := TClass(ABlockContentType);

      LPTarget := @LBuffer;

      {Get the name of the unit.}
      LClassInfo := LClass.ClassInfo;
      if LClassInfo <> nil then
      begin
        LPShortString := @PClassData(PByte(LClassInfo) + 2 + PByte(PByte(LClassInfo) + 1)^).UnitName;
        LPSource := @LPShortString^[1];
        LNumChars := Length(LPShortString^);

        while LNumChars > 0 do
        begin
          if LPSource^ = ':' then
            Break;

          if LPSource^ <> '@' then
          begin
            LPTarget^ := WideChar(LPSource^);
            Inc(LPTarget);
          end;

          Inc(LPSource);
          Dec(LNumChars);
        end;
        LPTarget^ := '.';
        Inc(LPTarget);
      end;

      {Append the class name}
      LPShortString := PShortString(PPointer(PByte(LClass) + vmtClassName)^);
      LPSource := @LPShortString^[1];
      LNumChars := Length(LPShortString^);
      for LCharInd := 1 to LNumChars do
      begin
        LPTarget^ := WideChar(LPSource^);
        Inc(LPTarget);
        Inc(LPSource);
      end;

      Result := AppendTextToBuffer(@LBuffer, CharCount(LPTarget, @LBuffer), Result, APTargetBufferEnd);
    end;

  end;
end;

{Copies a token value to the buffer and sets the pointer to the token in the values array.  Copies up to the size of
the target buffer.}
function AddTokenValue(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; APTokenValue: PWideChar;
  ACharCount: Integer; APBuffer, APBufferEnd: PWideChar): PWideChar;
begin
  Result := APBuffer;

  if Cardinal(ATokenID) > High(ATokenValues) then
    Exit;

  if (ACharCount <= 0)
    or (@Result[ACharCount] >= APBufferEnd) then
  begin
    ATokenValues[ATokenID] := nil;
    Exit;
  end;

  ATokenValues[ATokenID] := Result;
  Result := AppendTextToBuffer(APTokenValue, ACharCount, Result, APBufferEnd);

  {Store the trailing #0}
  Result^ := #0;
  Inc(Result);
end;

function AddTokenValue_NativeInt(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; ATokenValue: NativeInt;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..21] of WideChar;
  LPPos: PWideChar;
begin
  Result := APTokenValueBufferPos;

  LPPos := NativeIntToTextBuffer(ATokenValue, @LTempBuffer, @LTempBuffer[High(LTempBuffer)]);

  Result := AddTokenValue(ATokenValues, ATokenID, @LTempBuffer, CharCount(LPPos, @LTempBuffer), Result, APBufferEnd);
end;

function AddTokenValue_NativeUInt(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; ATokenValue: NativeUInt;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..20] of WideChar;
  LPPos: PWideChar;
begin
  Result := APTokenValueBufferPos;

  LPPos := NativeUIntToTextBuffer(ATokenValue, @LTempBuffer, @LTempBuffer[High(LTempBuffer)]);

  Result := AddTokenValue(ATokenValues, ATokenID, @LTempBuffer, CharCount(LPPos, @LTempBuffer), Result, APBufferEnd);
end;

function AddTokenValue_Hexadecimal(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; ATokenValue: NativeUInt;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..15] of WideChar;
  LPPos: PWideChar;
begin
  Result := APTokenValueBufferPos;

  LPPos := NativeUIntToHexadecimalBuffer(ATokenValue, @LTempBuffer, @LTempBuffer[High(LTempBuffer)]);

  Result := AddTokenValue(ATokenValues, ATokenID, @LTempBuffer, CharCount(LPPos, @LTempBuffer), Result, APBufferEnd);
end;

function AddTokenValue_HexDump(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; APBlock: PByte;
  ANumBytes: Integer; APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..CMemoryDumpMaxBytes * 5] of WideChar; //worst case scenario: allow for CRLF after every byte
  LPTarget: PWideChar;
  LBytesLeftInLine: Integer;
  LByteVal: Byte;
begin
  Result := APTokenValueBufferPos;

  if ANumBytes > CMemoryDumpMaxBytes then
    ANumBytes := CMemoryDumpMaxBytes;
  if ANumBytes <= 0 then
    Exit;

  LPTarget := @LTempBuffer;
  LBytesLeftInLine := CMemoryDumpMaxBytesPerLine;
  while True do
  begin
    LByteVal := APBlock^;
    LPTarget^ := CHexDigits[LByteVal div 16];
    Inc(LPTarget);
    LPTarget^ := CHexDigits[LByteVal and 15];
    Inc(LPTarget);
    Inc(APBlock);

    Dec(ANumBytes);
    if ANumBytes = 0 then
      Break;

    {Add the separator:  Either a space or a line break.}
    Dec(LBytesLeftInLine);
    if LBytesLeftInLine <= 0 then
    begin
      {Add a CRLF at the end of the line}
      LPTarget^ := #13;
      Inc(LPTarget);
      LPTarget^ := #10;
      Inc(LPTarget);

      LBytesLeftInLine := CMemoryDumpMaxBytesPerLine;
    end
    else
    begin
      LPTarget^ := ' ';
      Inc(LPTarget);
    end;

  end;

  Result := AddTokenValue(ATokenValues, ATokenID, @LTempBuffer, CharCount(LPTarget, @LTempBuffer), Result, APBufferEnd);
end;

function AddTokenValue_ASCIIDump(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; APBlock: PByte;
  ANumBytes: Integer; APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LTempBuffer: array[0..CMemoryDumpMaxBytes * 5] of WideChar; //worst case scenario: allow for CRLF after every byte
  LPTarget: PWideChar;
  LBytesLeftInLine: Integer;
  LByteVal: Byte;
begin
  Result := APTokenValueBufferPos;

  if ANumBytes > CMemoryDumpMaxBytes then
    ANumBytes := CMemoryDumpMaxBytes;
  if ANumBytes <= 0 then
    Exit;

  LPTarget := @LTempBuffer;
  LBytesLeftInLine := CMemoryDumpMaxBytesPerLine;
  while True do
  begin
    LByteVal := APBlock^;
    if (LByteVal > Ord(' ')) and (LByteVal < 128) then
      LPTarget^ := Char(LByteVal)
    else
      LPTarget^ := '.';
    Inc(LPTarget);
    Inc(APBlock);

    Dec(ANumBytes);
    if ANumBytes = 0 then
      Break;

    {Add the separator:  Either a space or a line break.}
    Dec(LBytesLeftInLine);
    if LBytesLeftInLine <= 0 then
    begin
      {Add a CRLF at the end of the line}
      LPTarget^ := #13;
      Inc(LPTarget);
      LPTarget^ := #10;
      Inc(LPTarget);

      LBytesLeftInLine := CMemoryDumpMaxBytesPerLine;
    end
    else
    begin
      LPTarget^ := ' ';
      Inc(LPTarget);
      LPTarget^ := ' ';
      Inc(LPTarget);
    end;

  end;

  Result := AddTokenValue(ATokenValues, ATokenID, @LTempBuffer, CharCount(LPTarget, @LTempBuffer), Result, APBufferEnd);
end;

function AddTokenValue_StackTrace(var ATokenValues: TEventLogTokenValues; ATokenID: Integer;
  const AStackTrace: TFastMM_StackTrace; APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LStackTraceBuffer: array[0..CFastMM_StackTraceEntryCount * 160] of WideChar;
  LPBuffer: PWideChar;
begin
  Result := APTokenValueBufferPos;

  LPBuffer := FastMM_ConvertStackTraceToText(@AStackTrace, CFastMM_StackTraceEntryCount, @LStackTraceBuffer,
    @LStackTraceBuffer[High(LStackTraceBuffer)]);

  Result := AddTokenValue(ATokenValues, ATokenID, LStackTraceBuffer, CharCount(LPBuffer, @LStackTraceBuffer), Result,
    APBufferEnd);
end;

{Adds a date token in ISO 8601 date format, e.g. 2020-01-01}
function AddTokenValue_Date(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; AYear, AMonth, ADay: Word;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LDateBuffer: array[0..9] of WideChar;
begin
  Result := APTokenValueBufferPos;

  LDateBuffer[3] := WideChar(Ord('0') + AYear mod 10);
  AYear := AYear div 10;
  LDateBuffer[2] := WideChar(Ord('0') + AYear mod 10);
  AYear := AYear div 10;
  LDateBuffer[1] := WideChar(Ord('0') + AYear mod 10);
  AYear := AYear div 10;
  LDateBuffer[0] := WideChar(Ord('0') + AYear mod 10);

  LDateBuffer[4] := '-';
  LDateBuffer[6] := WideChar(Ord('0') + AMonth mod 10);
  AMonth := AMonth div 10;
  LDateBuffer[5] := WideChar(Ord('0') + AMonth mod 10);

  LDateBuffer[7] := '-';
  LDateBuffer[9] := WideChar(Ord('0') + ADay mod 10);
  ADay := ADay div 10;
  LDateBuffer[8] := WideChar(Ord('0') + ADay mod 10);

  Result := AddTokenValue(ATokenValues, ATokenID, @LDateBuffer, Length(LDateBuffer), Result, APBufferEnd);
end;

{Adds a date token in ISO 8601 date format, e.g. 2020-01-01}
function AddTokenValue_Time(var ATokenValues: TEventLogTokenValues; ATokenID: Integer; AHour, AMinute, ASecond: Word;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LTimeBuffer: array[0..7] of WideChar;
begin
  Result := APTokenValueBufferPos;

  LTimeBuffer[1] := WideChar(Ord('0') + AHour mod 10);
  AHour := AHour div 10;
  LTimeBuffer[0] := WideChar(Ord('0') + AHour mod 10);

  LTimeBuffer[2] := ':';
  LTimeBuffer[4] := WideChar(Ord('0') + AMinute mod 10);
  AMinute := AMinute div 10;
  LTimeBuffer[3] := WideChar(Ord('0') + AMinute mod 10);

  LTimeBuffer[5] := ':';
  LTimeBuffer[7] := WideChar(Ord('0') + ASecond mod 10);
  ASecond := ASecond div 10;
  LTimeBuffer[6] := WideChar(Ord('0') + ASecond mod 10);

  Result := AddTokenValue(ATokenValues, ATokenID, @LTimeBuffer, Length(LTimeBuffer), Result, APBufferEnd);
end;

{Adds the tokens for the current date and time.}
function AddTokenValues_CurrentDateAndTime(var ATokenValues: TEventLogTokenValues;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
var
  LYear, LMonth, LDay, LHour, LMinute, LSecond: Word;
begin
  Result := APTokenValueBufferPos;

  OS_GetCurrentDateTime(LYear, LMonth, LDay, LHour, LMinute, LSecond);

  Result := AddTokenValue_Date(ATokenValues, CEventLogTokenCurrentDate, LYear, LMonth, LDay, Result, APBufferEnd);
  Result := AddTokenValue_Time(ATokenValues, CEventLogTokenCurrentTime, LHour, LMinute, LSecond, Result, APBufferEnd);
end;

function AddTokenValue_BlockContentType(var ATokenValues: TEventLogTokenValues; ATokenID: Integer;
  ABlockContentType: NativeUInt; APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
const
  CContentBufferSize = 512;
var
  LBuffer: array[0..CContentBufferSize] of WideChar;
  LPPos: PWideChar;
begin
  Result := APTokenValueBufferPos;

  LPPos := BlockContentTypeToTextBuffer(ABlockContentType, @LBuffer, @LBuffer[High(LBuffer)]);

  Result := AddTokenValue(ATokenValues, ATokenID, @LBuffer, CharCount(LPPos, @LBuffer), Result, APBufferEnd);
end;

function AddTokenValues_GeneralTokens(var ATokenValues: TEventLogTokenValues;
  APTokenValueBufferPos, APBufferEnd: PWideChar): PWideChar;
begin
  Result := AddTokenValues_CurrentDateAndTime(ATokenValues, APTokenValueBufferPos, APBufferEnd);
  Result := AddTokenValue(ATokenValues, CEventLogTokenEventLogFilename, FastMM_EventLogFilename,
    GetStringLength(FastMM_EventLogFilename), Result, APBufferEnd);
end;

function AddTokenValues_BlockTokens(var ATokenValues: TEventLogTokenValues; APBlock: Pointer;
  APBuffer, APBufferEnd: PWideChar): PWideChar;
var
  LBlockUserSize: NativeInt;
  LBlockContentType: NativeUInt;
  LMemoryDumpSize, LBlockHeader: Integer;
  LPDebugBlockHeader: PFastMM_DebugBlockHeader;
begin
  Result := APBuffer;

  {Add the token for the block size.}
  LBlockUserSize := FastMM_BlockMaximumUserBytes(APBlock);
  Result := AddTokenValue_NativeInt(ATokenValues, CEventLogTokenBlockSize, LBlockUserSize, Result, APBufferEnd);

  {Add the token for the block content type.}
  LBlockContentType := DetectBlockContentType(APBlock, LBlockUserSize);
  Result := AddTokenValue_BlockContentType(ATokenValues, CEventLogTokenObjectClass, LBlockContentType, Result,
    APBufferEnd);

  {Add the token for the block adddress in hex.}
  Result := AddTokenValue_Hexadecimal(ATokenValues, CEventLogTokenBlockAddress, NativeUInt(APBlock), Result, 
    APBufferEnd);

  {Add the block dump tokens.  The maximum dump size is less than the size of a medium block, so it's safe to read
  beyond the end of the block (due to the medium block header that will always follow a small block span).}
  if LBlockUserSize < CMemoryDumpMaxBytes - CMediumBlockHeaderSize then
    LMemoryDumpSize := LBlockUserSize + CMediumBlockHeaderSize
  else
    LMemoryDumpSize := CMemoryDumpMaxBytes;

  Result := AddTokenValue_NativeInt(ATokenValues, CEventLogTokenMemoryDumpSize, LMemoryDumpSize, Result, APBufferEnd);

  Result := AddTokenValue_HexDump(ATokenValues, CEventLogTokenHexDump, APBlock, LMemoryDumpSize, Result, APBufferEnd);

  Result := AddTokenValue_ASCIIDump(ATokenValues, CEventLogTokenASCIIDump, APBlock, LMemoryDumpSize, Result, APBufferEnd);

  {If this is a debug sub-block, log the additional debug information.}
  LBlockHeader := PWord(PByte(APBlock) - CBlockStatusWordSize)^;
  if LBlockHeader and (CIsSmallBlockFlag or CIsMediumBlockFlag or CIsLargeBlockFlag or CIsDebugBlockFlag) = CIsDebugBlockFlag then
  begin
    LPDebugBlockHeader := PFastMM_DebugBlockHeader(PByte(APBlock) - CDebugBlockHeaderSize);

    Result := AddTokenValue_Hexadecimal(ATokenValues, CEventLogTokenAllocatedByThread, LPDebugBlockHeader.AllocatedByThread,
      Result, APBufferEnd);

    Result := AddTokenValue_NativeUInt(ATokenValues, CEventLogTokenAllocationNumber, LPDebugBlockHeader.AllocationNumber,
      Result, APBufferEnd);

    Result := AddTokenValue_StackTrace(ATokenValues, CEventLogTokenAllocationStackTrace, LPDebugBlockHeader.AllocationStackTrace,
      Result, APBufferEnd);

    if LBlockHeader and CBlockIsFreeFlag = CBlockIsFreeFlag then
    begin
      Result := AddTokenValue_Hexadecimal(ATokenValues, CEventLogTokenFreedByThread, LPDebugBlockHeader.FreedByThread,
        Result, APBufferEnd);

      Result := AddTokenValue_StackTrace(ATokenValues, CEventLogTokenFreeStackTrace, LPDebugBlockHeader.FreeStackTrace,
        Result, APBufferEnd);
    end;
  end;

end;

{The template as well as token values must be #0 terminated.}
function SubstituteTokenValues(APTemplate: PWideChar; const ATokenValues: TEventLogTokenValues;
  APBuffer, APBufferEnd: PWideChar): PWideChar;
const
  CTokenStartChar = '{';
  CTokenEndChar = '}';
var
  LInputChar: WideChar;
  LInsideToken: Boolean;
  LTokenNumber: Cardinal;
  LPTokenValue: PWideChar;
begin
  LInsideToken := False;
  LTokenNumber := 0;
  Result := APBuffer;

  while Result < APBufferEnd do
  begin
    LInputChar := APTemplate^;
    if LInputChar = #0 then
      Break;
    Inc(APTemplate);

    if not LInsideToken then
    begin
      if LInputChar <> CTokenStartChar then
      begin
        Result^ := LInputChar;
        Inc(Result);
      end
      else
      begin
        LInsideToken := True;
        LTokenNumber := 0;
      end;
    end
    else
    begin
      if LInputChar <> CTokenEndChar then
      begin
        LTokenNumber := LTokenNumber * 10 + Ord(LInputChar) - Ord('0');
      end
      else
      begin
        if LTokenNumber <= CEventLogMaxTokenID then
        begin
          LPTokenValue := ATokenValues[LTokenNumber];
          if LPTokenValue <> nil then
          begin
            while Result < APBufferEnd do
            begin
              LInputChar := LPTokenValue^;
              if LInputChar = #0 then
                Break;
              Inc(LPTokenValue);

              Result^ := LInputChar;
              Inc(Result);

            end;
          end;

        end;
        LInsideToken := False;
      end;
    end;

  end;
end;

procedure LogEvent_WriteEventLogFile(APEventMessage: PWideChar; AWideCharCount: Integer);
const
  {We need to add either a BOM or a couple of line breaks before the text, so a larger buffer is needed than the
  maximum event message size.}
  CBufferSize = (CMaximumEventMessageSize + 4) * SizeOf(WideChar);
var
  LBuffer: array[0..CBufferSize] of Byte;
  LPBuffer: PByte;
begin
  LPBuffer := @LBuffer;

  if OS_FileExists(FastMM_EventLogFilename) then
  begin
    {The log file exists:  Add a line break after the previous event.}
    if FastMM_EventLogTextEncoding in [teUTF8, teUTF8_BOM] then
    begin
      PWord(LPBuffer)^ := $0A0D;
      Inc(LPBuffer, 2);
    end
    else
    begin
      PCardinal(LPBuffer)^ := $000A000D;
      Inc(LPBuffer, 4);
    end;
  end
  else
  begin
    {The file does not exist, so add the BOM if required.}
    if FastMM_EventLogTextEncoding = teUTF8_BOM then
    begin
      PCardinal(LPBuffer)^ := $BFBBEF;
      Inc(LPBuffer, 3);
    end else if FastMM_EventLogTextEncoding = teUTF16LE_BOM then
    begin
      PWord(LPBuffer)^ := $FEFF;
      Inc(LPBuffer, 2);
    end;
  end;

  {Copy the text across to the buffer, converting it as appropriate.}
  if FastMM_EventLogTextEncoding in [teUTF8, teUTF8_BOM] then
  begin
    LPBuffer := ConvertUTF16toUTF8(APEventMessage, AWideCharCount, LPBuffer);
  end
  else
  begin
    System.Move(APEventMessage^, LPBuffer^, AWideCharCount * 2);
    Inc(LPBuffer, AWideCharCount * 2);
  end;

  OS_CreateOrAppendFile(FastMM_EventLogFilename, @LBuffer, NativeInt(LPBuffer) - NativeInt(@LBuffer));
end;

{Logs an event to OutputDebugString, file or the display (or any combination thereof) depending on configuration.}
procedure LogEvent(AEventType: TFastMM_MemoryManagerEventType; const ATokenValues: TEventLogTokenValues);
var
  LPTextTemplate, LPMessageBoxCaption: PWideChar;
  LTextBuffer: array[0..CMaximumEventMessageSize] of WideChar;
  LPLogHeaderStart, LPBodyStart: PWideChar;
  LPBuffer, LPBufferEnd: PWideChar;
begin
  LPLogHeaderStart := @LTextBuffer;
  LPBufferEnd := @LTextBuffer[CMaximumEventMessageSize - 1];
  LPBuffer := LPLogHeaderStart;

  {Add the log file header.}
  if AEventType in FastMM_LogToFileEvents then
    LPBuffer := SubstituteTokenValues(FastMM_LogFileEntryHeader, ATokenValues, LPBuffer, LPBufferEnd);
  LPBodyStart := LPBuffer;

  {Add the message itself.}
  case AEventType of

    mmetAnotherThirdPartyMemoryManagerAlreadyInstalled:
    begin
      LPTextTemplate := FastMM_AnotherMemoryManagerAlreadyInstalledMessage;
      LPMessageBoxCaption := FastMM_CannotSwitchMemoryManagerMessageBoxCaption;
    end;

    mmetCannotInstallAfterDefaultMemoryManagerHasBeenUsed:
    begin
      LPTextTemplate := FastMM_CannotInstallAfterDefaultMemoryManagerHasBeenUsedMessage;
      LPMessageBoxCaption := FastMM_CannotSwitchMemoryManagerMessageBoxCaption;
    end;

    mmetCannotSwitchToSharedMemoryManagerWithLivePointers:
    begin
      LPTextTemplate := FastMM_CannotSwitchToSharedMemoryManagerWithLivePointersMessage;
      LPMessageBoxCaption := FastMM_CannotSwitchMemoryManagerMessageBoxCaption;
    end;

    mmetUnexpectedMemoryLeakDetail:
    begin
      {Determine which template to use from the block type:  Only debug blocks have thread information.}
      if ATokenValues[CEventLogTokenAllocatedByThread] <> nil then
        LPTextTemplate := FastMM_MemoryLeakDetailMessage_DebugBlock
      else
        LPTextTemplate := FastMM_MemoryLeakDetailMessage_NormalBlock;
      LPMessageBoxCaption := FastMM_MemoryLeakMessageBoxCaption;
    end;

    mmetUnexpectedMemoryLeakSummary:
    begin
      if mmetUnexpectedMemoryLeakDetail in FastMM_LogToFileEvents then
        LPTextTemplate := FastMM_MemoryLeakSummaryMessage_LeakDetailLoggedToEventLog
      else
        LPTextTemplate := FastMM_MemoryLeakSummaryMessage_LeakDetailNotLogged;
      LPMessageBoxCaption := FastMM_MemoryLeakMessageBoxCaption;
    end;

    mmetDebugBlockDoubleFree:
    begin
      LPTextTemplate := FastMM_DebugBlockDoubleFree;
      LPMessageBoxCaption := FastMM_MemoryCorruptionMessageBoxCaption;
    end;

    mmetDebugBlockReallocOfFreedBlock:
    begin
      LPTextTemplate := FastMM_DebugBlockReallocOfFreedBlock;
      LPMessageBoxCaption := FastMM_MemoryCorruptionMessageBoxCaption;
    end;

    mmetDebugBlockHeaderCorruption:
    begin
      LPTextTemplate := FastMM_BlockHeaderCorruptedMessage;
      LPMessageBoxCaption := FastMM_MemoryCorruptionMessageBoxCaption;
    end;

    mmetDebugBlockFooterCorruption:
    begin
      if ATokenValues[CEventLogTokenFreedByThread] <> nil then
        LPTextTemplate := FastMM_BlockFooterCorruptedMessage_FreedBlock
      else
        LPTextTemplate := FastMM_BlockFooterCorruptedMessage_AllocatedBlock;
      LPMessageBoxCaption := FastMM_MemoryCorruptionMessageBoxCaption;
    end;

    mmetDebugBlockModifiedAfterFree:
    begin
      LPTextTemplate := FastMM_BlockModifiedAfterFreeMessage;
      LPMessageBoxCaption := FastMM_MemoryCorruptionMessageBoxCaption;
    end;

  else
    begin
      {All event types should be handled above.}
      LPTextTemplate := nil;
      LPMessageBoxCaption := nil;
    end;
  end;
  LPBuffer := SubstituteTokenValues(LPTextTemplate, ATokenValues, LPBuffer, LPBufferEnd);

  {Store the trailing #0.}
  LPBuffer^ := #0;

  {Log the message to file, if needed.}
  if AEventType in FastMM_LogToFileEvents then
  begin
    LogEvent_WriteEventLogFile(LPLogHeaderStart, CharCount(LPBuffer, @LTextBuffer));
  end;

  if AEventType in FastMM_OutputDebugStringEvents then
  begin
    OS_OutputDebugString(LPLogHeaderStart);
  end;

  if AEventType in FastMM_MessageBoxEvents then
  begin
    OS_ShowMessageBox(LPBodyStart, LPMessageBoxCaption);
  end;

end;


{------------------------------------------}
{--------General utility subroutines-------}
{------------------------------------------}

{Returns the lowest set bit index in the 32-bit number}
function FindFirstSetBit(AInteger: Integer): Integer;
asm
{$ifdef 64Bit}
  .noframe
  mov rax, rcx
{$endif}
  bsf eax, eax
end;

{Returns True if the block is not in use.}
function BlockIsFree(APSmallMediumOrLargeBlock: Pointer): Boolean; inline;
begin
  Result := PWord(PByte(APSmallMediumOrLargeBlock) - CBlockStatusWordSize)^ and CBlockIsFreeFlag <> 0;
end;

{Tags a block as free, without affecting any other flags.}
procedure SetBlockIsFreeFlag(APSmallMediumOrLargeBlock: Pointer; ABlockIsFree: Boolean); inline;
var
  LPBlockStatus: PWord;
begin
  LPBlockStatus := PWord(PByte(APSmallMediumOrLargeBlock) - CBlockStatusWordSize);
  if ABlockIsFree then
    LPBlockStatus^ := LPBlockStatus^ or CBlockIsFreeFlag
  else
    LPBlockStatus^ := LPBlockStatus^ and (not CBlockIsFreeFlag);
end;

{Returns True if the block contains a debug sub-block.}
function BlockHasDebugInfo(APSmallMediumOrLargeBlock: Pointer): Boolean; inline;
begin
  Result := PWord(PByte(APSmallMediumOrLargeBlock) - CBlockStatusWordSize)^ and CHasDebugInfoFlag <> 0;
end;

{Tags a block as having debug info, without affecting any other flags.}
procedure SetBlockHasDebugInfo(APSmallMediumOrLargeBlock: Pointer; ABlockHasDebugInfo: Boolean); inline;
var
  LPBlockStatus: PWord;
begin
  LPBlockStatus := PWord(PByte(APSmallMediumOrLargeBlock) - CBlockStatusWordSize);
  if ABlockHasDebugInfo then
    LPBlockStatus^ := LPBlockStatus^ or CHasDebugInfoFlag
  else
    LPBlockStatus^ := LPBlockStatus^ and (not CHasDebugInfoFlag);
end;

function CalculateDebugBlockHeaderChecksum(APDebugBlockHeader: PFastMM_DebugBlockHeader): NativeUInt;
var
  LPCurPos: PNativeUInt;
begin
  Result := 0;
  LPCurPos := @APDebugBlockHeader.UserSize;
  while True do
  begin
    Result := Result xor LPCurPos^;
    Inc(LPCurPos);

    if LPCurPos = @APDebugBlockHeader.HeaderCheckSum then
      Break;
  end;

end;

procedure SetDebugBlockHeaderAndFooterChecksums(APDebugBlockHeader: PFastMM_DebugBlockHeader);
var
  LHeaderChecksum: NativeUInt;
  LPFooter: PNativeUInt;
begin
  LHeaderChecksum := CalculateDebugBlockHeaderChecksum(APDebugBlockHeader);
  APDebugBlockHeader.HeaderCheckSum := LHeaderChecksum;
  LPFooter := PNativeUInt(PByte(APDebugBlockHeader) + APDebugBlockHeader.UserSize + SizeOf(TFastMM_DebugBlockHeader));
  LPFooter^ := not LHeaderChecksum;
end;

procedure LogDebugBlockHeaderInvalid(APDebugBlockHeader: PFastMM_DebugBlockHeader);
const
  CTokenBufferSize = 65536;
var
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize] of WideChar;
  LPBufferPos, LPBufferEnd: PWideChar;
begin
  LTokenValues := Default(TEventLogTokenValues);

  LPBufferEnd := @LTokenValueBuffer[High(LTokenValueBuffer)];
  LPBufferPos := AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, LPBufferEnd);
  AddTokenValues_BlockTokens(LTokenValues, APDebugBlockHeader, LPBufferPos, LPBufferEnd);

  LogEvent(mmetDebugBlockHeaderCorruption, LTokenValues);
end;

{The debug header is assumed to be valid.}
procedure LogDebugBlockFooterInvalid(APDebugBlockHeader: PFastMM_DebugBlockHeader);
const
  CTokenBufferSize = 65536;
var
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize - 1] of WideChar;
  LPBufferPos, LPBufferEnd: PWideChar;
begin
  LTokenValues := Default(TEventLogTokenValues);

  LPBufferEnd := @LTokenValueBuffer[High(LTokenValueBuffer)];
  LPBufferPos := AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, LPBufferEnd);
  AddTokenValues_BlockTokens(LTokenValues, PByte(APDebugBlockHeader) + CDebugBlockHeaderSize, LPBufferPos, LPBufferEnd);

  LogEvent(mmetDebugBlockFooterCorruption, LTokenValues);
end;

{Checks the consistency of a block with embedded debug info.  Returns True if the block is intact, otherwise
(optionally) logs and/or displays the error and returns False.}
function CheckDebugBlockHeaderAndFooterCheckSumsValid(APDebugBlockHeader: PFastMM_DebugBlockHeader): Boolean;
var
  LHeaderChecksum: NativeUInt;
  LPFooter: PNativeUInt;
begin
  LHeaderChecksum := CalculateDebugBlockHeaderChecksum(APDebugBlockHeader);
  if APDebugBlockHeader.HeaderCheckSum <> LHeaderChecksum then
  begin
    LogDebugBlockHeaderInvalid(APDebugBlockHeader);
    Exit(False);
  end;
  LPFooter := PNativeUInt(PByte(APDebugBlockHeader) + APDebugBlockHeader.UserSize + SizeOf(TFastMM_DebugBlockHeader));
  if LPFooter^ <> (not LHeaderChecksum) then
  begin
    LogDebugBlockFooterInvalid(APDebugBlockHeader);
    Exit(False);
  end;

  Result := True;
end;

procedure FillDebugBlockWithDebugPattern(APDebugBlockHeader: PFastMM_DebugBlockHeader);
var
  LByteOffset: NativeInt;
  LPUserArea: PByte;
begin
  LByteOffset := APDebugBlockHeader.UserSize;
  LPUserArea := PByte(APDebugBlockHeader) + SizeOf(TFastMM_DebugBlockHeader);

  if LByteOffset and 1 <> 0 then
  begin
    Dec(LByteOffset);
    LPUserArea[LByteOffset] := CDebugFillPattern1B;
  end;

  if LByteOffset and 2 <> 0 then
  begin
    Dec(LByteOffset, 2);
    PWord(@LPUserArea[LByteOffset])^ := CDebugFillPattern2B;
  end;

  if LByteOffset and 4 <> 0 then
  begin
    Dec(LByteOffset, 4);
    PCardinal(@LPUserArea[LByteOffset])^ := CDebugFillPattern4B;
  end;

  {Loop over the remaining 8 byte chunks using a negative offset.}
  Inc(LPUserArea, LByteOffset);
  LByteOffset := - LByteOffset;
  while LByteOffset < 0 do
  begin
    PUInt64(@LPUserArea[LByteOffset])^ := CDebugFillPattern8B;
    Inc(LByteOffset, 8);
  end;

end;

{The debug header and footer are assumed to be valid.}
procedure LogDebugBlockFillPatternCorrupted(APDebugBlockHeader: PFastMM_DebugBlockHeader);
const
  CTokenBufferSize = 65536;
  CMaxLoggedChanges = 32;
var
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize - 1] of WideChar;
  LPBufferPos, LPBufferEnd: PWideChar;
  LPUserArea: PByte;
  LOffset, LChangeStart: NativeInt;
  LLogCount: Integer;
begin

  LTokenValues := Default(TEventLogTokenValues);
  LPBufferPos := @LTokenValueBuffer;
  LPBufferEnd := @LTokenValueBuffer[High(LTokenValueBuffer)];

  {Add the modification detail tokens.}
  LPUserArea := PByte(APDebugBlockHeader) + SizeOf(TFastMM_DebugBlockHeader);
  LLogCount := 0;
  LOffset := 0;
  LTokenValues[CEventLogTokenModifyAfterFreeDetail] := LPBufferPos;
  while LOffset < APDebugBlockHeader.UserSize do
  begin
    if LPUserArea[LOffset] <> CDebugFillPattern1B then
    begin

      {Found the start of a changed block, now find the length}
      LChangeStart := LOffset;
      while True do
      begin
        Inc(LOffset);
        if (LOffset >= APDebugBlockHeader.UserSize)
          or (LPUserArea[LOffset] = CDebugFillPattern1B) then
        begin
          Break;
        end;
      end;

      if LLogCount > 0 then
      begin
        LPBufferPos^ := ',';
        Inc(LPBufferPos);
        LPBufferPos^ := ' ';
        Inc(LPBufferPos);
      end;

      LPBufferPos := NativeIntToTextBuffer(LChangeStart, LPBufferPos, LPBufferEnd);
      LPBufferPos^ := '(';
      Inc(LPBufferPos);
      LPBufferPos := NativeIntToTextBuffer(LOffset - LChangeStart, LPBufferPos, LPBufferEnd);
      LPBufferPos^ := ')';
      Inc(LPBufferPos);

      Inc(LLogCount);
      if LLogCount >= CMaxLoggedChanges then
        Break;

    end;
    Inc(LOffset);
  end;

  LPBufferPos^ := #0;
  Inc(LPBufferPos);

  LPBufferPos := AddTokenValues_GeneralTokens(LTokenValues, LPBufferPos, LPBufferEnd);
  AddTokenValues_BlockTokens(LTokenValues, PByte(APDebugBlockHeader) + CDebugBlockHeaderSize, LPBufferPos, LPBufferEnd);

  LogEvent(mmetDebugBlockModifiedAfterFree, LTokenValues);
end;

{Checks that the debug fill pattern in the debug block is intact.  Returns True if the block is intact, otherwise
(optionally) logs and/or displays the error and returns False.}
function CheckDebugBlockFillPatternIntact(APDebugBlockHeader: PFastMM_DebugBlockHeader): Boolean;
var
  LByteOffset: NativeInt;
  LPUserArea: PByte;
  LFillPatternIntact: Boolean;
begin
  LFillPatternIntact := True;
  LByteOffset := APDebugBlockHeader.UserSize;
  LPUserArea := PByte(APDebugBlockHeader) + SizeOf(TFastMM_DebugBlockHeader);

  if LByteOffset and 1 <> 0 then
  begin
    Dec(LByteOffset);
    if LPUserArea[LByteOffset] <> CDebugFillPattern1B then
      LFillPatternIntact := False;
  end;

  if LByteOffset and 2 <> 0 then
  begin
    Dec(LByteOffset, 2);
    if PWord(@LPUserArea[LByteOffset])^ <> CDebugFillPattern2B then
      LFillPatternIntact := False;
  end;

  if LByteOffset and 4 <> 0 then
  begin
    Dec(LByteOffset, 4);
    if PCardinal(@LPUserArea[LByteOffset])^ <> CDebugFillPattern4B then
      LFillPatternIntact := False;
  end;

  {Loop over the remaining 8 byte chunks using a negative offset.}
  Inc(LPUserArea, LByteOffset);
  LByteOffset := - LByteOffset;
  while LByteOffset < 0 do
  begin
    if PUInt64(@LPUserArea[LByteOffset])^ <> CDebugFillPattern8B then
    begin
      LFillPatternIntact := False;
      Break;
    end;

    Inc(LByteOffset, 8);
  end;

  if not LFillPatternIntact then
  begin
    {Log the block error.}
    LogDebugBlockFillPatternCorrupted(APDebugBlockHeader);
    Result := False;
  end
  else
    Result := True;
end;

procedure EnsureEmergencyReserveAddressSpaceAllocated;
begin
{$ifdef 32Bit}
  if EmergencyReserveAddressSpace = nil then
    EmergencyReserveAddressSpace := OS_AllocateVirtualMemory(CEmergencyReserveAddressSpace, False, True);
{$endif}
end;

procedure ReleaseEmergencyReserveAddressSpace;
begin
{$ifdef 32Bit}
  if EmergencyReserveAddressSpace <> nil then
  begin
    OS_FreeVirtualMemory(EmergencyReserveAddressSpace);
    EmergencyReserveAddressSpace := nil;
  end;
{$endif}
end;


{-----------------------------------------}
{--------Large block management-----------}
{-----------------------------------------}

function FastMM_FreeMem_FreeLargeBlock_ReleaseVM(APLargeBlockHeader: PLargeBlockHeader): Integer;
var
  LRemainingSize: NativeUInt;
  LPCurrentSegment: Pointer;
  LMemoryRegionInfo: TMemoryRegionInfo;
begin
  if not APLargeBlockHeader.BlockIsSegmented then
  begin
    Result := OS_FreeVirtualMemory(APLargeBlockHeader);
  end
  else
  begin
    {The large block is segmented - free all segments}
    LPCurrentSegment := APLargeBlockHeader;
    LRemainingSize := NativeUInt(APLargeBlockHeader.ActualBlockSize);
    while True do
    begin
      OS_GetVirtualMemoryRegionInfo(LPCurrentSegment, LMemoryRegionInfo);

      Result := OS_FreeVirtualMemory(LPCurrentSegment);
      if Result <> 0 then
        Break;

      {Done?}
      if LMemoryRegionInfo.RegionSize >= LRemainingSize then
        Break;

      {Decrement the remaining size}
      Dec(LRemainingSize, LMemoryRegionInfo.RegionSize);
      Inc(PByte(LPCurrentSegment), LMemoryRegionInfo.RegionSize);
    end;

  end;
end;

{Unlink this block from the circular list of large blocks.  The manager must be locked.}
procedure UnlinkLargeBlock(APLargeBlockHeader: PLargeBlockHeader);
var
  LPreviousLargeBlockHeader: PLargeBlockHeader;
  LNextLargeBlockHeader: PLargeBlockHeader;
begin
  LPreviousLargeBlockHeader := APLargeBlockHeader.PreviousLargeBlockHeader;
  LNextLargeBlockHeader := APLargeBlockHeader.NextLargeBlockHeader;
  LNextLargeBlockHeader.PreviousLargeBlockHeader := LPreviousLargeBlockHeader;
  LPreviousLargeBlockHeader.NextLargeBlockHeader := LNextLargeBlockHeader;
end;

{Processes all the pending frees in the large block arena, and unlocks the arena when done.  Returns 0 on success.}
function ProcessLargeBlockPendingFrees_ArenaAlreadyLocked(APLargeBlockManager: PLargeBlockManager): Integer;
var
  LOldPendingFreeList, LPCurrentLargeBlock, LPNextLargeBlock: Pointer;
  LPLargeBlockHeader: PLargeBlockHeader;
begin
  Result := 0;

  {Get the pending free list}
  while True do
  begin
    LOldPendingFreeList := APLargeBlockManager.PendingFreeList;
    if AtomicCmpExchange(APLargeBlockManager.PendingFreeList, nil, LOldPendingFreeList) = LOldPendingFreeList then
      Break;
  end;

  {Unlink all the large blocks from the manager}
  LPCurrentLargeBlock := LOldPendingFreeList;
  while LPCurrentLargeBlock <> nil do
  begin
    LPNextLargeBlock := PPointer(LPCurrentLargeBlock)^;

    LPLargeBlockHeader := Pointer(PByte(LPCurrentLargeBlock) - CLargeBlockHeaderSize);

    UnlinkLargeBlock(LPLargeBlockHeader);

    LPCurrentLargeBlock := LPNextLargeBlock;
  end;

  {The large block manager no longer needs to be locked}
  APLargeBlockManager.LargeBlockManagerLocked := 0;

  {Free all the memory for the large blocks}
  LPCurrentLargeBlock := LOldPendingFreeList;
  while LPCurrentLargeBlock <> nil do
  begin
    LPNextLargeBlock := PPointer(LPCurrentLargeBlock)^;

    LPLargeBlockHeader := Pointer(PByte(LPCurrentLargeBlock) - CLargeBlockHeaderSize);

    if FastMM_FreeMem_FreeLargeBlock_ReleaseVM(LPLargeBlockHeader) <> 0 then
      Result := -1;

    LPCurrentLargeBlock := LPNextLargeBlock;
  end;

end;

{Process the pending frees list for all unlocked arenas, returning 0 on success or -1 if any error occurs}
function ProcessLargeBlockPendingFrees: Integer;
var
  LPLargeBlockManager: PLargeBlockManager;
  LArenaIndex: Integer;
begin
  Result := 0;

  LPLargeBlockManager := @LargeBlockArenas[0];
  for LArenaIndex := 0 to CLargeBlockArenaCount - 1 do
  begin

    if (LPLargeBlockManager.PendingFreeList <> nil)
      and (LPLargeBlockManager.LargeBlockManagerLocked = 0)
      and (AtomicCmpExchange(LPLargeBlockManager.LargeBlockManagerLocked, 1, 0) = 0) then
    begin

      Result := ProcessLargeBlockPendingFrees_ArenaAlreadyLocked(LPLargeBlockManager);

      if Result <> 0 then
        Break;

    end;

    {Do the next arena.}
    Inc(LPLargeBlockManager);
  end;

end;

{Allocates a Large block of at least ASize (actual size may be larger to allow for alignment etc.).  ASize must be the
actual user requested size.  This procedure will pad it to the appropriate page boundary and also add the space
required by the header.}
function FastMM_GetMem_GetLargeBlock(ASize: NativeInt): Pointer;
var
  LLargeBlockActualSize: NativeInt;
  LPLargeBlockManager: PLargeBlockManager;
  LArenaIndex: Integer;
  LOldFirstLargeBlock: PLargeBlockHeader;
begin
  {Process the pending free lists of all arenas.}
  if ProcessLargeBlockPendingFrees <> 0 then
    Exit(nil);

  {Pad the block size to include the header and granularity, checking for overflow.}
  LLargeBlockActualSize := (ASize + CLargeBlockHeaderSize + CLargeBlockGranularity - 1) and -CLargeBlockGranularity;
  if LLargeBlockActualSize <= 0 then
    Exit(nil);
  {Get the large block.  For segmented large blocks to work in practice without excessive move operations we need to
  allocate top down.}
  Result := OS_AllocateVirtualMemory(LLargeBlockActualSize, True, False);

  {Set the Large block fields}
  if Result <> nil then
  begin
    {Set the large block size and flags}
    PLargeBlockHeader(Result).UserAllocatedSize := ASize;
    PLargeBlockHeader(Result).ActualBlockSize := LLargeBlockActualSize;
    PLargeBlockHeader(Result).BlockIsSegmented := False;
    PLargeBlockHeader(Result).BlockStatusFlags := CIsLargeBlockFlag;

    {Insert the block in the first available arena.}
    while True do
    begin

      LPLargeBlockManager := @LargeBlockArenas[0];
      for LArenaIndex := 0 to CLargeBlockArenaCount - 1 do
      begin

        if (LPLargeBlockManager.LargeBlockManagerLocked = 0)
          and (AtomicCmpExchange(LPLargeBlockManager.LargeBlockManagerLocked, 1, 0) = 0) then
        begin
          PLargeBlockHeader(Result).LargeBlockArena := LPLargeBlockManager;

          {Insert the large block into the linked list of large blocks}
          LOldFirstLargeBlock := LPLargeBlockManager.FirstLargeBlockHeader;
          PLargeBlockHeader(Result).PreviousLargeBlockHeader := Pointer(LPLargeBlockManager);
          LPLargeBlockManager.FirstLargeBlockHeader := Result;
          PLargeBlockHeader(Result).NextLargeBlockHeader := LOldFirstLargeBlock;
          LOldFirstLargeBlock.PreviousLargeBlockHeader := Result;

          LPLargeBlockManager.LargeBlockManagerLocked := 0;

          {Add the size of the header}
          Inc(PByte(Result), CLargeBlockHeaderSize);

          Exit;
        end;

        {Try the next arena.}
        Inc(LPLargeBlockManager);
      end;

    end;

    {All large block managers are locked:  Back off and try again.}
    OS_AllowOtherThreadToRun;

  end;
end;

function FastMM_FreeMem_FreeLargeBlock(APLargeBlock: Pointer): Integer;
var
  LPLargeBlockHeader: PLargeBlockHeader;
  LPLargeBlockManager: PLargeBlockManager;
  LOldPendingFreeList: Pointer;
begin
  LPLargeBlockHeader := Pointer(PByte(APLargeBlock) - CLargeBlockHeaderSize);
  LPLargeBlockManager := LPLargeBlockHeader.LargeBlockArena;

  {Try to lock the large block manager so that the block may be freed.}
  if AtomicCmpExchange(LPLargeBlockManager.LargeBlockManagerLocked, 1, 0) = 0 then
  begin
    {Unlink the large block from the circular queue for the manager.}
    UnlinkLargeBlock(LPLargeBlockHeader);

    {The large block manager no longer has to be locked, since the large block has been unlinked.}
    LPLargeBlockManager.LargeBlockManagerLocked := 0;

    {Release the memory used by the large block.}
    Result := FastMM_FreeMem_FreeLargeBlock_ReleaseVM(LPLargeBlockHeader);

  end
  else
  begin
    {The large block manager is currently locked, so we need to add this block to its pending free list.}
    while True do
    begin
      LOldPendingFreeList := LPLargeBlockManager.PendingFreeList;
      PPointer(APLargeBlock)^ := LOldPendingFreeList;
      if AtomicCmpExchange(LPLargeBlockManager.PendingFreeList, APLargeBlock, LOldPendingFreeList) = LOldPendingFreeList then
        Break;
    end;

    Result := 0;
  end;

  if Result = 0 then
    Result := ProcessLargeBlockPendingFrees;
end;

function FastMM_ReallocMem_ReallocLargeBlock(APointer: Pointer; ANewSize: NativeInt): Pointer;
var
  LPLargeBlockHeader: PLargeBlockHeader;
  LOldAvailableSize, LMinimumUpsize, LNewAllocSize, LNewSegmentSize, LOldUserSize: NativeInt;
  LMemoryRegionInfo: TMemoryRegionInfo;
  LPNextSegment: Pointer;
begin
  {Get the block header}
  LPLargeBlockHeader := PLargeBlockHeader(PByte(APointer) - CLargeBlockHeaderSize);
  {Large block - size is (16 + 4) less than the allocated size}
  LOldAvailableSize := LPLargeBlockHeader.ActualBlockSize - CLargeBlockHeaderSize;
  {Is it an upsize or a downsize?}
  if ANewSize > LOldAvailableSize then
  begin
    {This pointer is being reallocated to a larger block and therefore it is logical to assume that it may be enlarged
    again.  Since reallocations are expensive, there is a minimum upsize percentage to avoid unnecessary future move
    operations.}
    {Add 25% for large block upsizes}
    LMinimumUpsize := LOldAvailableSize + (LOldAvailableSize shr 2);
    if ANewSize < LMinimumUpsize then
      LNewAllocSize := LMinimumUpsize
    else
      LNewAllocSize := ANewSize;

    {Can another large block segment be allocated directly after this segment, thus negating the need to move the data?}
    LPNextSegment := Pointer(PByte(LPLargeBlockHeader) + LPLargeBlockHeader.ActualBlockSize);
    OS_GetVirtualMemoryRegionInfo(LPNextSegment, LMemoryRegionInfo);
    if LMemoryRegionInfo.RegionIsFree then
    begin
      {Round the region size to the previous 64K}
      LMemoryRegionInfo.RegionSize := LMemoryRegionInfo.RegionSize and -CLargeBlockGranularity;
      {Enough space to grow in place?}
      if LMemoryRegionInfo.RegionSize >= NativeUInt(ANewSize - LOldAvailableSize) then
      begin
        {There is enough space after the block to extend it - determine by how much}
        LNewSegmentSize := (LNewAllocSize - LOldAvailableSize + CLargeBlockGranularity - 1) and -CLargeBlockGranularity;
        if NativeUInt(LNewSegmentSize) > LMemoryRegionInfo.RegionSize then
          LNewSegmentSize := LMemoryRegionInfo.RegionSize;
        {Attempt to reserve the address range (which will fail if another thread has just reserved it) and commit it
        immediately afterwards.}
        if OS_AllocateVirtualMemoryAtAddress(LPNextSegment, LNewSegmentSize, False) then
        begin
          {Update the requested size}
          LPLargeBlockHeader.UserAllocatedSize := ANewSize;
          Inc(LPLargeBlockHeader.ActualBlockSize, LNewSegmentSize);
          LPLargeBlockHeader.BlockIsSegmented := True;
          Exit(APointer);
        end;
      end;
    end;

    {Could not resize in place:  Allocate the new block}
    Result := FastMM_GetMem(LNewAllocSize);
    if Result <> nil then
    begin
      {If it's a large block - store the actual user requested size (it may not be if the block that is being
      reallocated from was previously downsized)}
      if LNewAllocSize > (CMaximumMediumBlockSize - CMediumBlockHeaderSize) then
        PLargeBlockHeader(PByte(Result) - CLargeBlockHeaderSize).UserAllocatedSize := ANewSize;
      {The user allocated size is stored for large blocks}
      LOldUserSize := LPLargeBlockHeader.UserAllocatedSize;
      {The number of bytes to move is the old user size.}
      System.Move(APointer^, Result^, LOldUserSize);
      {Free the old block.}
      FastMM_FreeMem(APointer);
    end;
  end
  else
  begin
    {It's a downsize:  Do we need to reallocate?  Only if the new size is less than half the old size.}
    if ANewSize >= (LOldAvailableSize shr 1) then
    begin
      {No need to reallocate}
      Result := APointer;
      {Update the requested size}
      LPLargeBlockHeader.UserAllocatedSize := ANewSize;
    end
    else
    begin
      {The block is less than half the old size, and the current size is greater than the minimum block size allowing a
      downsize:  Reallocate}
      Result := FastMM_GetMem(ANewSize);
      if Result <> nil then
      begin
        {Move the data across}
        System.Move(APointer^, Result^, ANewSize);
        {Free the old block.}
        FastMM_FreeMem(APointer);
      end;
    end;
  end;

end;


{------------------------------------------}
{--------Medium block management-----------}
{------------------------------------------}

{Takes a user request size and convents it to a size that fits the size of a medium block bin exactly.}
function RoundUserSizeUpToNextMediumBlockBin(AUserSize: Integer): Integer; inline;
begin
  if AUserSize <= (CMediumBlockMiddleBinsStart - CMediumBlockHeaderSize) then
  begin
    Result := (AUserSize + (CMediumBlockHeaderSize - CMinimumMediumBlockSize + CInitialBinSpacing - 1)) and -CInitialBinSpacing
      + CMinimumMediumBlockSize;
  end
  else
  begin
    if AUserSize <= (CMediumBlockFinalBinsStart - CMediumBlockHeaderSize) then
    begin
      Result := (AUserSize + (CMediumBlockHeaderSize - CMediumBlockMiddleBinsStart + CMiddleBinSpacing - 1)) and -CMiddleBinSpacing
        + CMediumBlockMiddleBinsStart;
    end
    else
    begin
      Result := (AUserSize + (CMediumBlockHeaderSize - CMediumBlockFinalBinsStart + CFinalBinSpacing - 1)) and -CFinalBinSpacing
        + CMediumBlockFinalBinsStart;
    end;
  end;
end;

{Determines the appropriate bin number for blocks of AMediumBlockSize.  If AMediumBlockSize is not exactly aligned to a
bin size then the bin just smaller than AMediumBlockSize will be returned.  It is assumed that AMediumBlockSize <=
CMaximumMediumBlockSize.}
function GetBinNumberForMediumBlockSize(AMediumBlockSize: Integer): Integer; inline;
begin
  if AMediumBlockSize <= CMediumBlockMiddleBinsStart then
  begin
    Result := (AMediumBlockSize - CMinimumMediumBlockSize) div CInitialBinSpacing;
  end
  else
  begin
    if AMediumBlockSize <= CMediumBlockFinalBinsStart then
      Result := (AMediumBlockSize + (CInitialBinCount * CMiddleBinSpacing - CMediumBlockMiddleBinsStart)) div CMiddleBinSpacing
    else
      Result := (AMediumBlockSize + ((CInitialBinCount + CMiddleBinCount) * CFinalBinSpacing - CMediumBlockFinalBinsStart)) div CFinalBinSpacing;
  end;
end;

function GetMediumBlockSpan(APMediumBlock: Pointer): PMediumBlockSpanHeader; inline;
begin
  Result := PMediumBlockSpanHeader(PByte(APMediumBlock)
    - (PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).MediumBlockSpanOffsetMultiple * CMediumBlockAlignment));
end;

function GetMediumBlockSize(APMediumBlock: Pointer): Integer; inline;
begin
  Result := PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).MediumBlockSizeMultiple * CMediumBlockAlignment;
end;

procedure SetMediumBlockHeader_SetIsSmallBlockSpan(APMediumBlock: Pointer; AIsSmallBlockSpan: Boolean); inline;
begin
  PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).IsSmallBlockSpan := AIsSmallBlockSpan;
end;

procedure SetMediumBlockHeader_SetMediumBlockSpan(APMediumBlock: Pointer; APMediumBlockSpan: PMediumBlockSpanHeader); inline;
begin
  {Store the offset to the medium block span.}
  PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).MediumBlockSpanOffsetMultiple :=
    (NativeInt(APMediumBlock) - NativeInt(APMediumBlockSpan)) div CMediumBlockAlignment;
end;

procedure SetMediumBlockHeader_SetSizeAndFlags(APMediumBlock: Pointer; ABlockSize: Integer; ABlockIsFree: Boolean;
  ABlockHasDebugInfo: Boolean); inline;
begin
  if ABlockIsFree then
  begin

    if ABlockHasDebugInfo then
    begin
      PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).BlockStatusFlags :=
        CHasDebugInfoFlag + CBlockIsFreeFlag + CIsMediumBlockFlag;
    end
    else
    begin
      PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).BlockStatusFlags :=
        CBlockIsFreeFlag + CIsMediumBlockFlag;
    end;

    {If the block is free then the size must also be stored just before the header of the next block.}
    PInteger(PByte(APMediumBlock) + ABlockSize - CMediumBlockHeaderSize - SizeOf(Integer))^ := ABlockSize;

    {Update the flag in the next block header to indicate that this block is free.}
    PMediumBlockHeader(PByte(APMediumBlock) + ABlockSize - CMediumBlockHeaderSize).PreviousBlockIsFree := True;

  end
  else
  begin

    if ABlockHasDebugInfo then
    begin
      PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).BlockStatusFlags :=
        CHasDebugInfoFlag + CIsMediumBlockFlag;
    end
    else
    begin
      PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).BlockStatusFlags := CIsMediumBlockFlag;
    end;

    {Update the flag in the next block to indicate that this block is in use.  The block size is not stored before
    the header of the next block if it is not free.}
    PMediumBlockHeader(PByte(APMediumBlock) + ABlockSize - CMediumBlockHeaderSize).PreviousBlockIsFree := False;

  end;

  {Store the block size.}
  PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).MediumBlockSizeMultiple := ABlockSize div CMediumBlockAlignment;
end;

{Inserts a medium block into the appropriate medium block bin.  The header for APMediumFreeBlock must already be set
correctly.}
procedure InsertMediumBlockIntoBin(APMediumBlockManager: PMediumBlockManager; APMediumFreeBlock: PMediumFreeBlock;
  AMediumBlockSize: Integer);
var
  LBinNumber, LBinGroupNumber: Cardinal;
  LPBin, LPInsertAfterBlock, LPInsertBeforeBlock: PMediumFreeBlock;
begin
  {Get the bin for blocks of this size.  If the block is not aligned to a bin size, then put it in the closest bin
  smaller than the block size.}
  if AMediumBlockSize < CMaximumMediumBlockSize then
    LBinNumber := GetBinNumberForMediumBlockSize(AMediumBlockSize)
  else
    LBinNumber := CMediumBlockBinCount - 1;
  LPBin := @APMediumBlockManager.FirstFreeBlockInBin[LBinNumber];

  {Bins are LIFO, so we insert this block as the first free block in the bin}
  LPInsertAfterBlock := LPBin;
  LPInsertBeforeBlock := LPBin.NextFreeMediumBlock;

  APMediumFreeBlock.NextFreeMediumBlock := LPInsertBeforeBlock;
  APMediumFreeBlock.PreviousFreeMediumBlock := LPInsertAfterBlock;
  LPInsertAfterBlock.NextFreeMediumBlock := APMediumFreeBlock;

  {Was this bin previously empty?}
  if LPInsertBeforeBlock <> LPInsertAfterBlock then
  begin
    {It's not a fully circular linked list:  Bins have no "previous" pointer.}
    if LPInsertBeforeBlock <> LPBin then
      LPInsertBeforeBlock.PreviousFreeMediumBlock := APMediumFreeBlock;
  end
  else
  begin
    {Get the group number}
    LBinGroupNumber := LBinNumber div 32;
    {Flag this bin as used}
    APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber] := APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber]
      or (1 shl (LBinNumber and 31));
    {Flag the group as used}
    APMediumBlockManager.MediumBlockBinGroupBitmap := APMediumBlockManager.MediumBlockBinGroupBitmap
      or (1 shl LBinGroupNumber);
  end;
end;

{Removes a medium block from the circular linked list of free blocks.  Does not change any header flags.  The medium
block manager should be locked before calling this procedure.}
procedure RemoveMediumFreeBlockFromBin(APMediumBlockManager: PMediumBlockManager; APMediumFreeBlock: PMediumFreeBlock);
var
  LPPreviousFreeBlock, LPNextFreeBlock: PMediumFreeBlock;
  LBinNumber, LBinGroupNumber: Cardinal;
begin
  {Get the current previous and next blocks}
  LPNextFreeBlock := APMediumFreeBlock.NextFreeMediumBlock;
  LPPreviousFreeBlock := APMediumFreeBlock.PreviousFreeMediumBlock;
  {Remove this block from the linked list}
  LPPreviousFreeBlock.NextFreeMediumBlock := LPNextFreeBlock;
  {Is this bin now empty?  If the previous and next free block pointers are equal, they must point to the bin.}
  if LPNextFreeBlock <> LPPreviousFreeBlock then
  begin
    {It's not a fully circular linked list:  Bins have no "previous" pointer.  Therefore we need to check whether
    LPNextFreeBlock points to the bin or not before setting the previous block pointer.}
    if (NativeUInt(LPNextFreeBlock) > NativeUInt(@MediumBlockArenas) + SizeOf(MediumBlockArenas))
      or (NativeUInt(LPNextFreeBlock) < NativeUInt(@MediumBlockArenas)) then
    begin
      LPNextFreeBlock.PreviousFreeMediumBlock := LPPreviousFreeBlock;
    end;
  end
  else
  begin
    {Get the bin number for this block size}
    LBinNumber := (NativeInt(LPNextFreeBlock) - NativeInt(@APMediumBlockManager.FirstFreeBlockInBin)) div SizeOf(Pointer);
    LBinGroupNumber := LBinNumber div 32;
    {Flag this bin as empty}
    APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber] := APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber]
      and (not (1 shl (LBinNumber and 31)));
    {Is the group now entirely empty?}
    if APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber] = 0 then
    begin
      {Flag this group as empty}
      APMediumBlockManager.MediumBlockBinGroupBitmap := APMediumBlockManager.MediumBlockBinGroupBitmap
        and (not (1 shl LBinGroupNumber));
    end;
  end;
end;

{Bins what remains in the current sequential feed medium block span.  The medium block manager must be locked.}
procedure BinMediumSequentialFeedRemainder(APMediumBlockManager: PMediumBlockManager);
var
  LPreviousLastSequentialFeedBlockOffset, LNextBlockSize: Integer;
  LSequentialFeedFreeSize: Integer;
  LPRemainderBlock, LPNextMediumBlock: Pointer;
begin
  while True do
  begin

    LPreviousLastSequentialFeedBlockOffset := APMediumBlockManager.LastSequentialFeedBlockOffset.IntegerValue;

    {Is there anything to bin?}
    if LPreviousLastSequentialFeedBlockOffset <= CMediumBlockSpanHeaderSize then
      Break;

    {There's no need to update the ABA counter, since the medium block manager is locked and no other thread can thus
    change the sequential feed span.}
    if AtomicCmpExchange(APMediumBlockManager.LastSequentialFeedBlockOffset.IntegerValue, 0, LPreviousLastSequentialFeedBlockOffset) = LPreviousLastSequentialFeedBlockOffset then
    begin
      LSequentialFeedFreeSize := LPreviousLastSequentialFeedBlockOffset - CMediumBlockSpanHeaderSize;

      {Get the block for the remaining space}
      LPNextMediumBlock := PByte(APMediumBlockManager.SequentialFeedMediumBlockSpan) + LPreviousLastSequentialFeedBlockOffset;

      {Point to the remainder}
      LPRemainderBlock := Pointer(PByte(APMediumBlockManager.SequentialFeedMediumBlockSpan) + CMediumBlockSpanHeaderSize);

      {Can the next block be combined with the remainder?}
      if BlockIsFree(LPNextMediumBlock) then
      begin
        LNextBlockSize := GetMediumBlockSize(LPNextMediumBlock);
        {Increase the size of this block}
        Inc(LSequentialFeedFreeSize, LNextBlockSize);
        {Remove the next block from the bins, if it is currently binned.}
        if LNextBlockSize >= CMinimumMediumBlockSize then
          RemoveMediumFreeBlockFromBin(APMediumBlockManager, LPNextMediumBlock);
      end;

      {Store the size of the block as well as the flags.  Also updates the header of the next block to indicate that
      this block is free.}
      SetMediumBlockHeader_SetSizeAndFlags(LPRemainderBlock, LSequentialFeedFreeSize, True, False);
      SetMediumBlockHeader_SetMediumBlockSpan(LPRemainderBlock, APMediumBlockManager.SequentialFeedMediumBlockSpan);

      {Bin this medium block}
      if LSequentialFeedFreeSize >= CMinimumMediumBlockSize then
        InsertMediumBlockIntoBin(APMediumBlockManager, LPRemainderBlock, LSequentialFeedFreeSize);

      Break;
    end;

  end;

end;

{Allocates a new sequential feed medium block span and immediately splits off a block of the requested size.  The block
size must be a multiple of 64 and medium blocks must be locked.  Returns a pointer to the first block.  The block
manager must be locked.}
function FastMM_GetMem_GetMediumBlock_AllocateNewSequentialFeedSpan(APMediumBlockManager: PMediumBlockManager;
  AFirstBlockSize: Integer): Pointer;
var
  LNewSpanSize: Integer;
  LOldFirstMediumBlockSpan, LPNewSpan: PMediumBlockSpanHeader;
begin
  {Bin the current sequential feed remainder}
  BinMediumSequentialFeedRemainder(APMediumBlockManager);
  {Allocate a new sequential feed block pool.  The block is assumed to be zero initialized.}
  LNewSpanSize := DefaultMediumBlockSpanSize;
  LPNewSpan := OS_AllocateVirtualMemory(LNewSpanSize, False, False);
  if LPNewSpan <> nil then
  begin
    LPNewSpan.SpanSize := LNewSpanSize;
    LPNewSpan.MediumBlockArena := APMediumBlockManager;

    {Insert this span into the circular linked list of medium block spans}
    LOldFirstMediumBlockSpan := APMediumBlockManager.FirstMediumBlockSpanHeader;
    LPNewSpan.PreviousMediumBlockSpanHeader := PMediumBlockSpanHeader(APMediumBlockManager);
    APMediumBlockManager.FirstMediumBlockSpanHeader := LPNewSpan;
    LPNewSpan.NextMediumBlockSpanHeader := LOldFirstMediumBlockSpan;
    LOldFirstMediumBlockSpan.PreviousMediumBlockSpanHeader := LPNewSpan;

    {Store the sequential feed span trailer.  Technically, this should not be necessary since the span is
    zero-initialized and the only flag that really matters is the "is free block" flag.}
    PMediumBlockHeader(PByte(LPNewSpan) + (LNewSpanSize - CMediumBlockHeaderSize)).BlockStatusFlags := CIsMediumBlockFlag;

    {Get the result and set its header.}
    Result := Pointer(PByte(LPNewSpan) + LNewSpanSize - AFirstBlockSize);
    SetMediumBlockHeader_SetSizeAndFlags(Result, AFirstBlockSize, False, False);
    SetMediumBlockHeader_SetMediumBlockSpan(Result, LPNewSpan);

    {Install this is the new sequential feed span.  The new offset must be set after the new span and ABA counter,
    since other threads may immediately split off blocks the moment the new offset is set.}
    Inc(APMediumBlockManager.LastSequentialFeedBlockOffset.ABACounter);
    APMediumBlockManager.SequentialFeedMediumBlockSpan := LPNewSpan;

    {May need a memory fence here for ARM.}

    APMediumBlockManager.LastSequentialFeedBlockOffset.IntegerValue := NativeInt(Result) - NativeInt(LPNewSpan);
  end
  else
  begin
    {Out of memory}
    Result := nil;
  end;
end;

{Attempts to split off a medium block from the sequential feed span for the arena.  Returns the block on success, nil if
there is not enough sequential feed space available.  The arena does not have to be locked.}
function FastMM_GetMem_GetMediumBlock_TryGetBlockFromSequentialFeedSpan(APMediumBlockManager: PMediumBlockManager;
  AMinimumSize, AOptimalSize: Integer): Pointer;
var
  LPSequentialFeedSpan: PMediumBlockSpanHeader;
  LPreviousLastSequentialFeedBlockOffset, LNewLastSequentialFeedBlockOffset: TIntegerWithABACounter;
  LBlockSize: Integer;
begin
  {The arena is not necessarily locked, so we may have to try several times to split off a block.}
  while True do
  begin
    LPreviousLastSequentialFeedBlockOffset := APMediumBlockManager.LastSequentialFeedBlockOffset;

    {Is there space available for at least the minimum size block?}
    if (LPreviousLastSequentialFeedBlockOffset.IntegerValue - CMediumBlockSpanHeaderSize) >= AMinimumSize then
    begin
      LBlockSize := LPreviousLastSequentialFeedBlockOffset.IntegerValue - CMediumBlockSpanHeaderSize;
      if LBlockSize > AOptimalSize then
        LBlockSize := AOptimalSize;

      {Calculate the new sequential feed parameters.}
      LNewLastSequentialFeedBlockOffset.IntegerAndABACounter := LPreviousLastSequentialFeedBlockOffset.IntegerAndABACounter
        - LBlockSize + Int64(1) shl 32;

      LPSequentialFeedSpan := APMediumBlockManager.SequentialFeedMediumBlockSpan;

      Result := Pointer(PByte(LPSequentialFeedSpan) + LNewLastSequentialFeedBlockOffset.IntegerValue);

      if AtomicCmpExchange(APMediumBlockManager.LastSequentialFeedBlockOffset.IntegerAndABACounter,
        LNewLastSequentialFeedBlockOffset.IntegerAndABACounter,
        LPreviousLastSequentialFeedBlockOffset.IntegerAndABACounter) = LPreviousLastSequentialFeedBlockOffset.IntegerAndABACounter then
      begin
        {Set the header for the block.}
        SetMediumBlockHeader_SetSizeAndFlags(Result, LBlockSize, False, False);
        SetMediumBlockHeader_SetMediumBlockSpan(Result, LPSequentialFeedSpan);

        Exit;
      end;

    end
    else
    begin
      {There is either no sequential feed span, or it has insufficient space.}
      Exit(nil);
    end;
  end;
end;

{Subroutine for FastMM_FreeMem_FreeMediumBlock.  The medium block manager must already be locked.  Optionally unlocks the
medium block manager before exit.  Returns 0 on success, -1 on failure.}
function FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(APMediumBlockManager: PMediumBlockManager;
  APMediumBlockSpan: PMediumBlockSpanHeader; APMediumBlock: Pointer; AUnlockMediumBlockManager: Boolean): Integer;
var
  LPPreviousMediumBlockSpan, LPNextMediumBlockSpan: PMediumBlockSpanHeader;
  LBlockSize, LNextBlockSize, LPreviousBlockSize: Integer;
  LPNextMediumBlock: Pointer;
begin
  LBlockSize := GetMediumBlockSize(APMediumBlock);

  if DebugModeCounter <= 0 then
  begin
    {Combine with the next block, if it is free.}
    LPNextMediumBlock := Pointer(PByte(APMediumBlock) + LBlockSize);
    if BlockIsFree(LPNextMediumBlock) then
    begin
      LNextBlockSize := GetMediumBlockSize(LPNextMediumBlock);
      Inc(LBlockSize, LNextBlockSize);
      if LNextBlockSize >= CMinimumMediumBlockSize then
        RemoveMediumFreeBlockFromBin(APMediumBlockManager, LPNextMediumBlock);
    end;

    {Combine with the previous block, if it is free.}
    if PMediumBlockHeader(PByte(APMediumBlock) - CMediumBlockHeaderSize).PreviousBlockIsFree then
    begin
      LPreviousBlockSize := PInteger(PByte(APMediumBlock) - CMediumBlockHeaderSize - SizeOf(Integer))^;
      {This is the new current block}
      APMediumBlock := Pointer(PByte(APMediumBlock) - LPreviousBlockSize);

      Inc(LBlockSize, LPreviousBlockSize);
      if LPreviousBlockSize >= CMinimumMediumBlockSize then
        RemoveMediumFreeBlockFromBin(APMediumBlockManager, APMediumBlock);
    end;

    {Outside of debug mode medium blocks are combined, so debug info will be lost.}
    SetMediumBlockHeader_SetSizeAndFlags(APMediumBlock, LBlockSize, True, False);

  end
  else
  begin
    {Medium blocks are not coalesced in debug mode, so just flag the block as free and leave the debug info flag as-is.}
    SetBlockIsFreeFlag(APMediumBlock, True);
  end;

  {Is the entire medium block span free?  Normally the span will be freed, but if there is not a lot of space left in
  the sequential feed span and the largest free block bin is empty then the block is binned instead (if allowed by the
  optimization strategy).}
  if (LBlockSize <> (APMediumBlockSpan.SpanSize - CMediumBlockSpanHeaderSize))
    or ((OptimizationStrategy <> mmosOptimizeForLowMemoryUsage)
      and (APMediumBlockManager.LastSequentialFeedBlockOffset.IntegerValue < CMaximumMediumBlockSize)
      and (APMediumBlockManager.MediumBlockBinBitmaps[CMediumBlockBinGroupCount - 1] and (1 shl 31) = 0)) then
  begin
    if LBlockSize >= CMinimumMediumBlockSize then
      InsertMediumBlockIntoBin(APMediumBlockManager, APMediumBlock, LBlockSize);

    if AUnlockMediumBlockManager then
      APMediumBlockManager.MediumBlockManagerLocked := 0;

    Result := 0;
  end
  else
  begin
    {Remove this medium block span from the linked list}
    LPPreviousMediumBlockSpan := APMediumBlockSpan.PreviousMediumBlockSpanHeader;
    LPNextMediumBlockSpan := APMediumBlockSpan.NextMediumBlockSpanHeader;
    LPPreviousMediumBlockSpan.NextMediumBlockSpanHeader := LPNextMediumBlockSpan;
    LPNextMediumBlockSpan.PreviousMediumBlockSpanHeader := LPPreviousMediumBlockSpan;

    if AUnlockMediumBlockManager then
      APMediumBlockManager.MediumBlockManagerLocked := 0;

    {Free the entire span.}
    Result := OS_FreeVirtualMemory(APMediumBlockSpan);
  end;
end;

{Frees a chain of blocks belonging to the medium block manager.  The block manager is assumed to be locked.  Optionally
unlocks the block manager when done.  The first pointer inside each free block should be a pointer to the next free
block.}
function FastMM_FreeMem_FreeMediumBlockChain(APMediumBlockManager: PMediumBlockManager; APPendingFreeMediumBlock: Pointer;
  AUnlockMediumBlockManagerWhenDone: Boolean): Integer;
var
  LPNextBlock: Pointer;
  LPMediumBlockSpan: PMediumBlockSpanHeader;
begin
  Result := 0;

  while True do
  begin
    LPNextBlock := PPointer(APPendingFreeMediumBlock)^;

    LPMediumBlockSpan := GetMediumBlockSpan(APPendingFreeMediumBlock);
    Result := Result or FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(APMediumBlockManager, LPMediumBlockSpan,
      APPendingFreeMediumBlock, AUnlockMediumBlockManagerWhenDone and (LPNextBlock = nil));

    if LPNextBlock = nil then
      Break;

    APPendingFreeMediumBlock := LPNextBlock;
  end;
end;

function FastMM_FreeMem_FreeMediumBlock(APMediumBlock: Pointer): Integer;
var
  LPMediumBlockSpan: PMediumBlockSpanHeader;
  LPMediumBlockManager: PMediumBlockManager;
  LFirstPendingFreeBlock: Pointer;
begin
  LPMediumBlockSpan := GetMediumBlockSpan(APMediumBlock);
  LPMediumBlockManager := LPMediumBlockSpan.MediumBlockArena;

  {Try to lock the medium block manager so that the block may be freed.}
  if AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0 then
  begin

    {Memory fence required for ARM here}

    if LPMediumBlockManager.PendingFreeList = nil then
    begin
      Result := FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(LPMediumBlockManager, LPMediumBlockSpan,
        APMediumBlock, True);
    end
    else
    begin
      Result := FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(LPMediumBlockManager, LPMediumBlockSpan,
        APMediumBlock, False);

      {Process the pending frees list.}
      while True do
      begin
        LFirstPendingFreeBlock := LPMediumBlockManager.PendingFreeList;
        if (AtomicCmpExchange(LPMediumBlockManager.PendingFreeList, nil, LFirstPendingFreeBlock) = LFirstPendingFreeBlock) then
        begin
          Result := Result or FastMM_FreeMem_FreeMediumBlockChain(LPMediumBlockManager, LFirstPendingFreeBlock, True);

          Exit;
        end;
      end;

    end;

  end
  else
  begin
    {The medium block manager is currently locked, so we need to add this block to its pending free list.}
    while True do
    begin
      LFirstPendingFreeBlock := LPMediumBlockManager.PendingFreeList;
      PPointer(APMediumBlock)^ := LFirstPendingFreeBlock;
      if AtomicCmpExchange(LPMediumBlockManager.PendingFreeList, APMediumBlock, LFirstPendingFreeBlock) = LFirstPendingFreeBlock then
        Break;
    end;

    Result := 0;
  end;

end;

{Clears the list of pending frees while attempting to reuse one of a suitable size.  The arena must be locked.}
function FastMM_GetMem_GetMediumBlock_TryReusePendingFreeBlock(APMediumBlockManager: PMediumBlockManager;
  AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize: Integer): Pointer;
var
  LBlockSize, LBestMatchBlockSize, LSecondSplitSize: Integer;
  LPSecondSplit: PMediumFreeBlock;
  LPPendingFreeBlock, LPNextPendingFreeBlock: Pointer;
  LPMediumBlockSpan: PMediumBlockSpanHeader;
begin

  {Retrieve the pending free list pointer.}
  while True do
  begin
    LPPendingFreeBlock := APMediumBlockManager.PendingFreeList;
    if AtomicCmpExchange(APMediumBlockManager.PendingFreeList, nil, LPPendingFreeBlock) = LPPendingFreeBlock then
      Break;
  end;

  if LPPendingFreeBlock <> nil then
  begin

    {Process all the pending frees, but keep the smallest block that is at least AMinimumBlockSize in size (if
    there is one).}
    LBestMatchBlockSize := MaxInt;
    Result := nil;

    while True do
    begin
      LPNextPendingFreeBlock := PPointer(LPPendingFreeBlock)^;
      LBlockSize := GetMediumBlockSize(LPPendingFreeBlock);

      if (LBlockSize >= AMinimumBlockSize) and (LBlockSize < LBestMatchBlockSize) then
      begin
        {Free the previous best match block.}
        if Result <> nil then
        begin
          LPMediumBlockSpan := GetMediumBlockSpan(Result);
          if FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(
            APMediumBlockManager, LPMediumBlockSpan, Result, False) <> 0 then
          begin
            System.Error(reInvalidPtr);
          end;
        end;
        Result := LPPendingFreeBlock;
        LBestMatchBlockSize := LBlockSize;
      end
      else
      begin
        LPMediumBlockSpan := GetMediumBlockSpan(LPPendingFreeBlock);
        if FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(
          APMediumBlockManager, LPMediumBlockSpan, LPPendingFreeBlock, False) <> 0 then
        begin
          System.Error(reInvalidPtr);
        end;
      end;

      if LPNextPendingFreeBlock = nil then
        Break;

      LPPendingFreeBlock := LPNextPendingFreeBlock;
    end;

    {Was there a suitable block in the pending free list?}
    if Result <> nil then
    begin

      {If the block currently has debug info, check it for consistency.}
      if BlockHasDebugInfo(Result) then
      begin
        if (not CheckDebugBlockHeaderAndFooterCheckSumsValid(Result))
         or (not CheckDebugBlockFillPatternIntact(Result)) then
        begin
          {The arena must be unlocked before the error is raised, otherwise the leak check at shutdown will hang.}
          APMediumBlockManager.MediumBlockManagerLocked := 0;
          System.Error(reInvalidPtr);
        end;
      end;

      {Should the block be split?}
      if LBestMatchBlockSize > AMaximumBlockSize then
      begin
        {Get the size of the second split}
        LSecondSplitSize := LBestMatchBlockSize - AOptimalBlockSize;
        {Adjust the block size}
        LBestMatchBlockSize := AOptimalBlockSize;
        {Split the block in two}
        LPSecondSplit := PMediumFreeBlock(PByte(Result) + LBestMatchBlockSize);
        LPMediumBlockSpan := GetMediumBlockSpan(Result);
        SetMediumBlockHeader_SetSizeAndFlags(LPSecondSplit, LSecondSplitSize, True, False);
        SetMediumBlockHeader_SetMediumBlockSpan(LPSecondSplit, LPMediumBlockSpan);

        {The second split is an entirely new block so all the header fields must be set.}
        SetMediumBlockHeader_SetIsSmallBlockSpan(LPSecondSplit, False);

        {Bin the second split.}
        if LSecondSplitSize >= CMinimumMediumBlockSize then
          InsertMediumBlockIntoBin(APMediumBlockManager, LPSecondSplit, LSecondSplitSize);

      end;

      {Set the header and trailer for this block, clearing the debug info flag.}
      SetMediumBlockHeader_SetSizeAndFlags(Result, LBestMatchBlockSize, False, False);

    end;
  end
  else
    Result := nil;
end;

{Tries to find a block of suitable size from the list of available blocks in the arena.  The arena must be locked.
Block sizes must be aligned to a bin size.}
function FastMM_GetMem_GetMediumBlock_TryAllocateFreeBlock(APMediumBlockManager: PMediumBlockManager;
  AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize: Integer): Pointer;
var
  LBinGroupNumber, LBinNumber, LBinGroupMasked, LBinGroupsMasked, LBlockSize, LSecondSplitSize: Integer;
  LPMediumBin, LPSecondSplit: PMediumFreeBlock;
  LPMediumBlockSpan: PMediumBlockSpanHeader;
begin
  {Round the request up to the next bin size.}
  LBinNumber := GetBinNumberForMediumBlockSize(AMinimumBlockSize);
  LBinGroupNumber := LBinNumber div 32;

  LBinGroupMasked := APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber] and -(1 shl (LBinNumber and 31));
  if LBinGroupMasked <> 0 then
  begin
    {Get the actual bin number}
    LBinNumber := FindFirstSetBit(LBinGroupMasked) + LBinGroupNumber * 32;
  end
  else
  begin
    {Try all groups greater than this group}
    LBinGroupsMasked := APMediumBlockManager.MediumBlockBinGroupBitmap and -(2 shl LBinGroupNumber);
    if LBinGroupsMasked <> 0 then
    begin
      {There is a suitable group with space:  Get the bin number}
      LBinGroupNumber := FindFirstSetBit(LBinGroupsMasked);
      {Get the bin in the group with free blocks}
      LBinNumber := FindFirstSetBit(APMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber]) + LBinGroupNumber * 32;
    end
    else
    begin
      {There is no free block of sufficient size available.}
      Exit(nil);
    end;
  end;

  {If we get here there is a block that is AMinimumBlockSize or greater.}
  LPMediumBin := @APMediumBlockManager.FirstFreeBlockInBin[LBinNumber];
  Result := LPMediumBin.NextFreeMediumBlock;

  RemoveMediumFreeBlockFromBin(APMediumBlockManager, Result);

  {If the block currently has debug info, check it for consistency before resetting the flag.}
  if BlockHasDebugInfo(Result) then
  begin
    if (not CheckDebugBlockHeaderAndFooterCheckSumsValid(Result))
      or (not CheckDebugBlockFillPatternIntact(Result)) then
    begin
      APMediumBlockManager.MediumBlockManagerLocked := 0;
      System.Error(reInvalidPtr);
    end;
  end;

  {Get the size of the available medium block}
  LBlockSize := GetMediumBlockSize(Result);
  LPMediumBlockSpan := GetMediumBlockSpan(Result);

  {Should the block be split?}
  if LBlockSize > AMaximumBlockSize then
  begin
    {Get the size of the second split}
    LSecondSplitSize := LBlockSize - AOptimalBlockSize;
    {Adjust the block size}
    LBlockSize := AOptimalBlockSize;
    {Split the block in two}
    LPSecondSplit := PMediumFreeBlock(PByte(Result) + LBlockSize);
    SetMediumBlockHeader_SetSizeAndFlags(LPSecondSplit, LSecondSplitSize, True, False);
    SetMediumBlockHeader_SetMediumBlockSpan(LPSecondSplit, LPMediumBlockSpan);

    {The second split is an entirely new block so all the header fields must be set.}
    SetMediumBlockHeader_SetIsSmallBlockSpan(LPSecondSplit, False);

    {Bin the second split.}
    if LSecondSplitSize >= CMinimumMediumBlockSize then
      InsertMediumBlockIntoBin(APMediumBlockManager, LPSecondSplit, LSecondSplitSize);
  end;

  {Set the header for this block, clearing the debug infor flag.}
  SetMediumBlockHeader_SetSizeAndFlags(Result, LBlockSize, False, False);
end;

{Allocates a medium block within the given size constraints.  Sizes must be properly aligned to a bin size.}
function FastMM_GetMem_GetMediumBlock(AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize: Integer): Pointer;
var
  LPMediumBlockManager: PMediumBlockManager;
  LArenaIndex, LBinGroupNumber, LBinNumber: Integer;
begin

  while True do
  begin

    {---------Step 1: Process pending free lists------------}
    {Scan the pending free lists for all medium block managers first, and reuse a block that is of sufficient size if
    possible.}

    LPMediumBlockManager := @MediumBlockArenas[0];
    for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
    begin

      if (LPMediumBlockManager.PendingFreeList <> nil)
        and (LPMediumBlockManager.MediumBlockManagerLocked = 0)
        and (AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0) then
      begin
        Result := FastMM_GetMem_GetMediumBlock_TryReusePendingFreeBlock(LPMediumBlockManager,
          AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize);

        {Memory fence needed here for ARM}

        LPMediumBlockManager.MediumBlockManagerLocked := 0;

        if Result <> nil then
          Exit;

      end;

      {Try the next arena.}
      Inc(LPMediumBlockManager);
    end;

    {--------Step 2: Try to find a suitable free block in the free lists for all arenas--------}

    {Determine the bin for blocks of this size.}
    LBinNumber := GetBinNumberForMediumBlockSize(AMinimumBlockSize);
    LBinGroupNumber := LBinNumber div 32;

    LPMediumBlockManager := @MediumBlockArenas[0];
    for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
    begin

      {The arena must currently be unlocked and there must be available blocks of the minimum size or larger.  If that
      is the case then try to lock the arena.}
      if (LPMediumBlockManager.MediumBlockManagerLocked = 0)
        and ((LPMediumBlockManager.MediumBlockBinBitmaps[LBinGroupNumber] and -(1 shl (LBinNumber and 31)) <> 0)
          or (LPMediumBlockManager.MediumBlockBinGroupBitmap and -(2 shl LBinGroupNumber) <> 0))
        and (AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0) then
      begin

        Result := FastMM_GetMem_GetMediumBlock_TryAllocateFreeBlock(LPMediumBlockManager,
          AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize);

        {Memory fence needed here for ARM}

        LPMediumBlockManager.MediumBlockManagerLocked := 0;

        if Result <> nil then
          Exit;

      end;

      {Try the next arena.}
      Inc(LPMediumBlockManager);
    end;

    {--------Step 3: Try to feed a medium block sequentially from an existing sequential feed span--------}

    LPMediumBlockManager := @MediumBlockArenas[0];
    for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
    begin

      Result := FastMM_GetMem_GetMediumBlock_TryGetBlockFromSequentialFeedSpan(LPMediumBlockManager, AMinimumBlockSize, AOptimalBlockSize);
      if Result <> nil then
        Exit;

      Inc(LPMediumBlockManager);
    end;

    {--------Step 4: Lock the first available arena and try again, allocating a new sequential feed span if needed--------}

    {At this point (a) all arenas are either locked, or (b) there are no pending free blocks, no available blocks, and
    all the sequential feed spans are exhausted.}

    LPMediumBlockManager := @MediumBlockArenas[0];
    for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
    begin

      if AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0 then
      begin
        {Try to allocate a free block.  Another thread may have freed a block before this arena could be locked.}
        Result := FastMM_GetMem_GetMediumBlock_TryAllocateFreeBlock(LPMediumBlockManager,
          AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize);

        if Result = nil then
        begin
          {Another thread may have allocated a sequential feed span before the arena could be locked, so a second
          attempt at feeding a block sequentially should be made before allocating a new span.}
          Result := FastMM_GetMem_GetMediumBlock_TryGetBlockFromSequentialFeedSpan(LPMediumBlockManager, AMinimumBlockSize, AOptimalBlockSize);
          if Result = nil then
          begin
            {Another thread may have added blocks to the pending free list in the meantime - try to reuse a pending
            free block again.  Allocating a span is very expensive, so has to be avoided if at all possible.}
            if LPMediumBlockManager.PendingFreeList <> nil then
            begin
              Result := FastMM_GetMem_GetMediumBlock_TryReusePendingFreeBlock(LPMediumBlockManager,
                AMinimumBlockSize, AOptimalBlockSize, AMaximumBlockSize);
            end;

            {If we get here then there are no suitable free blocks, pending free blocks, and the current sequential
            feed span has no space.}
            if Result = nil then
              Result := FastMM_GetMem_GetMediumBlock_AllocateNewSequentialFeedSpan(LPMediumBlockManager, AOptimalBlockSize);
          end;

        end;

        LPMediumBlockManager.MediumBlockManagerLocked := 0;
        Exit;
      end;

      {The arena could not be locked - try the next one.}
      Inc(LPMediumBlockManager);
    end;

    {--------Step 5: Back off and try again--------}

    OS_AllowOtherThreadToRun;

  end;

end;

function FastMM_ReallocMem_ReallocMediumBlock(APointer: Pointer; ANewUserSize: NativeInt): Pointer;
var
  LPNextBlock: Pointer;
  LBlockSize, LOldUserSize, LNextBlockSize, LCombinedUserSize, LMinimumUpsize, LNewAllocSize, LNewBlockSize, LSecondSplitSize: NativeInt;
  LPMediumBlockSpan: PMediumBlockSpanHeader;
  LPMediumBlockManager: PMediumBlockManager;
begin
  {TODO : Process the pending free lists?}

  {What is the available size in the block being reallocated?}
  LBlockSize := GetMediumBlockSize(APointer);
  {Get a pointer to the next block}
  LPNextBlock := Pointer(PByte(APointer) + LBlockSize);
  {Subtract the block header size from the old available size}
  LOldUserSize := LBlockSize - CMediumBlockHeaderSize;

  {Is it an upsize or a downsize?}
  if ANewUserSize > LOldUserSize then
  begin

    {If the next block is free then we need to check if this block can be upsized in-place.}
    if BlockIsFree(LPNextBlock) then
    begin
      LNextBlockSize := GetMediumBlockSize(LPNextBlock);
      LCombinedUserSize := LOldUserSize + LNextBlockSize;
      if ANewUserSize <= LCombinedUserSize then
      begin

        {The next block is currently free and there is enough space to grow this block in place.  Try to lock the
        medium block manager.  If it can be locked and the next block is still free and large enough then stretch the
        medium block in place.}
        LPMediumBlockSpan := GetMediumBlockSpan(APointer);
        LPMediumBlockManager := LPMediumBlockSpan.MediumBlockArena;
        if (LPMediumBlockManager.MediumBlockManagerLocked = 0)
          and (AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0) then
        begin

          {We need to recheck this, since another thread could have grabbed the block before the manager could be
          locked.}
          LNextBlockSize := GetMediumBlockSize(LPNextBlock);
          LCombinedUserSize := LOldUserSize + LNextBlockSize;

          if (ANewUserSize <= LCombinedUserSize)
            and BlockIsFree(LPNextBlock) then
          begin
            if LNextBlockSize >= CMinimumMediumBlockSize then
              RemoveMediumFreeBlockFromBin(LPMediumBlockManager, LPNextBlock);

            {Add 25% for medium block in-place upsizes}
            LMinimumUpsize := LOldUserSize + (LOldUserSize shr 2);
            if ANewUserSize < LMinimumUpsize then
              LNewAllocSize := LMinimumUpsize
            else
              LNewAllocSize := ANewUserSize;
            {Round up to the nearest block size granularity}
            LNewBlockSize := ((LNewAllocSize + (CMediumBlockHeaderSize + CMediumBlockAlignment - 1))
              and -CMediumBlockAlignment);
            {Calculate the size of the second split}
            LSecondSplitSize := LCombinedUserSize + CMediumBlockHeaderSize - LNewBlockSize;
            {Does it fit?}
            if LSecondSplitSize <= 0 then
            begin
              {The block size is the full available size plus header}
              LNewBlockSize := LCombinedUserSize + CMediumBlockHeaderSize;
            end
            else
            begin
              {Split the block in two}
              LPNextBlock := PMediumFreeBlock(PByte(APointer) + LNewBlockSize);

              SetMediumBlockHeader_SetSizeAndFlags(LPNextBlock, LSecondSplitSize, True, False);
              SetMediumBlockHeader_SetMediumBlockSpan(LPNextBlock, LPMediumBlockSpan);
              {The second split is an entirely new block so all the header fields must be set.}
              SetMediumBlockHeader_SetIsSmallBlockSpan(LPNextBlock, False);

              {Put the remainder in a bin if it is big enough}
              if LSecondSplitSize >= CMinimumMediumBlockSize then
                InsertMediumBlockIntoBin(LPMediumBlockManager, LPNextBlock, LSecondSplitSize);
            end;

            {Set the size and flags for this block}
            SetMediumBlockHeader_SetSizeAndFlags(APointer, LNewBlockSize, False, False);

            {Unlock the medium blocks}
            LPMediumBlockManager.MediumBlockManagerLocked := 0;

            Exit(APointer);
          end;

          {Couldn't use the next block, because another thread grabbed it:  Unlock the medium blocks}
          LPMediumBlockManager.MediumBlockManagerLocked := 0;
        end;
      end;
    end;

    {Couldn't upsize in place.  Allocate a new block and move the data across:  If we have to reallocate and move
    medium blocks, we grow by at least 25%}
    LMinimumUpsize := LOldUserSize + (LOldUserSize shr 2);
    if ANewUserSize < LMinimumUpsize then
      LNewAllocSize := LMinimumUpsize
    else
      LNewAllocSize := ANewUserSize;
    {Allocate the new block}
    Result := FastMM_GetMem(LNewAllocSize);
    if Result <> nil then
    begin
      {If it's a large block - store the actual user requested size}
      if LNewAllocSize > (CMaximumMediumBlockSize - CMediumBlockHeaderSize) then
        PLargeBlockHeader(PByte(Result) - CLargeBlockHeaderSize).UserAllocatedSize := ANewUserSize;
      {Move the data across}
      System.Move(APointer^, Result^, LOldUserSize);
      {Free the old block}
      FastMM_FreeMem(APointer);
    end;

  end
  else
  begin
    {Must be less than half the current size or we don't bother resizing.}
    if (ANewUserSize * 2) >= LOldUserSize then
    begin
      Result := APointer;
    end
    else
    begin

      {In-place downsize?  Balance the cost of moving the data vs. the cost of fragmenting the address space.}
      if ANewUserSize >= CMediumInPlaceDownsizeLimit then
      begin

        {Medium blocks in use may never be smaller than CMinimumMediumBlockSize.}
        if ANewUserSize < (CMinimumMediumBlockSize - CMediumBlockHeaderSize) then
          ANewUserSize := CMinimumMediumBlockSize - CMediumBlockHeaderSize;

        {Round up to the next medium block size}
        LNewBlockSize := ((ANewUserSize + (CMediumBlockHeaderSize + CMediumBlockAlignment - 1))
          and -CMediumBlockAlignment);

        LSecondSplitSize := (LOldUserSize + CMediumBlockHeaderSize) - LNewBlockSize;
        if LSecondSplitSize > 0 then
        begin

          LPMediumBlockSpan := GetMediumBlockSpan(APointer);

          {Set a proper header for the second split.}
          LPNextBlock := PMediumBlockHeader(PByte(APointer) + LNewBlockSize);
          SetMediumBlockHeader_SetSizeAndFlags(LPNextBlock, LSecondSplitSize, False, False);
          SetMediumBlockHeader_SetMediumBlockSpan(LPNextBlock, LPMediumBlockSpan);
          {The second split is an entirely new block so all the header fields must be set.}
          SetMediumBlockHeader_SetIsSmallBlockSpan(LPNextBlock, False);

          {Adjust the size of this block.}
          SetMediumBlockHeader_SetSizeAndFlags(APointer, LNewBlockSize, False, False);

          {Free the second split.}
          FastMM_FreeMem(LPNextBlock);
        end;

        Result := APointer;
      end
      else
      begin

        {Allocate the new block, move the data across and then free the old block.}
        Result := FastMM_GetMem(ANewUserSize);
        if Result <> nil then
        begin
          System.Move(APointer^, Result^, ANewUserSize);
          FastMM_FreeMem(APointer);
        end;

      end;
    end;
  end;

end;


{-----------------------------------------}
{--------Small block management-----------}
{-----------------------------------------}

procedure SetSmallBlockHeader(APSmallBlock: Pointer; APSmallBlockSpan: PSmallBlockSpanHeader; ABlockIsFree: Boolean;
  ABlockHasDebugInfo: Boolean); inline;
begin
  if ABlockIsFree then
  begin

    if ABlockHasDebugInfo then
    begin
      PSmallBlockHeader(PByte(APSmallBlock) - CSmallBlockHeaderSize).BlockStatusFlagsAndSpanOffset :=
        (((NativeInt(APSmallBlock) - NativeInt(APSmallBlockSpan)) and -CMediumBlockAlignment) shr CSmallBlockSpanOffsetBitShift)
        + (CHasDebugInfoFlag + CBlockIsFreeFlag + CIsSmallBlockFlag);
    end
    else
    begin
      PSmallBlockHeader(PByte(APSmallBlock) - CSmallBlockHeaderSize).BlockStatusFlagsAndSpanOffset :=
        (((NativeInt(APSmallBlock) - NativeInt(APSmallBlockSpan)) and -CMediumBlockAlignment) shr CSmallBlockSpanOffsetBitShift)
        + (CBlockIsFreeFlag + CIsSmallBlockFlag);
    end;

  end
  else
  begin

    if ABlockHasDebugInfo then
    begin
      PSmallBlockHeader(PByte(APSmallBlock) - CSmallBlockHeaderSize).BlockStatusFlagsAndSpanOffset :=
        (((NativeInt(APSmallBlock) - NativeInt(APSmallBlockSpan)) and -CMediumBlockAlignment) shr CSmallBlockSpanOffsetBitShift)
        + (CHasDebugInfoFlag + CIsSmallBlockFlag);
    end
    else
    begin
      PSmallBlockHeader(PByte(APSmallBlock) - CSmallBlockHeaderSize).BlockStatusFlagsAndSpanOffset :=
        ((NativeInt(APSmallBlock) - NativeInt(APSmallBlockSpan)) and -CMediumBlockAlignment) shr CSmallBlockSpanOffsetBitShift
        + CIsSmallBlockFlag;
    end;

  end;

end;

function GetSpanForSmallBlock(APSmallBlock: Pointer): PSmallBlockSpanHeader; inline;
var
  LBlockOffset: NativeInt;
begin
  LBlockOffset := (PWord(PByte(APSmallBlock) - CBlockStatusWordSize)^ and CDropSmallBlockFlagsMask) shl CSmallBlockSpanOffsetBitShift;
  Result := Pointer((NativeInt(APSmallBlock) - LBlockOffset) and -CMediumBlockAlignment);
end;

{Subroutine for FastMM_FreeMem_FreeSmallBlock.  The small block manager must already be locked.  Optionally unlocks the
small block manager before exit.}
procedure FastMM_FreeMem_InternalFreeSmallBlock_ManagerAlreadyLocked(APSmallBlockManager: PSmallBlockManager;
  APSmallBlockSpan: PSmallBlockSpanHeader; APSmallBlock: Pointer; AUnlockSmallBlockManager: Boolean);
var
  LPPreviousSpan, LPNextSpan, LPInsertAfterSpan, LPInsertBeforeSpan: PSmallBlockSpanHeader;
  LOldFirstFreeBlock: Pointer;
begin
  LOldFirstFreeBlock := APSmallBlockSpan.FirstFreeBlock;

  {Was the span previously full?}
  if LOldFirstFreeBlock = nil then
  begin
    {Insert this as the first partially free pool for the block size}
    LPInsertAfterSpan := PSmallBlockSpanHeader(APSmallBlockManager);
    LPInsertBeforeSpan := APSmallBlockManager.FirstPartiallyFreeSpan;

    APSmallBlockSpan.NextPartiallyFreeSpan := LPInsertBeforeSpan;
    APSmallBlockSpan.PreviousPartiallyFreeSpan := LPInsertAfterSpan;
    LPInsertBeforeSpan.PreviousPartiallyFreeSpan := APSmallBlockSpan;
    LPInsertAfterSpan.NextPartiallyFreeSpan := APSmallBlockSpan;
  end;

  {Mark the block as free, keeping the other flags (e.g. debug info) intact.}
  SetBlockIsFreeFlag(APSmallBlock, True);
  {Store the old first free block}
  PPointer(APSmallBlock)^ := LOldFirstFreeBlock;
  {Store this as the new first free block}
  APSmallBlockSpan.FirstFreeBlock := APSmallBlock;
  {Decrement the number of allocated blocks}
  Dec(APSmallBlockSpan.BlocksInUse);
  {Is the entire span now free? -> Free it, unless debug mode is active.  BlocksInUse is set to the maximum that will
  fit in the span when the span is added as the sequential feed span, so this can only hit zero once all the blocks have
  been fed sequentially and subsequently freed.}
  if (APSmallBlockSpan.BlocksInUse = 0) and (DebugModeCounter <= 0) then
  begin
    {Remove this span from the circular linked list of partially free spans for the block type.}
    LPPreviousSpan := APSmallBlockSpan.PreviousPartiallyFreeSpan;
    LPNextSpan := APSmallBlockSpan.NextPartiallyFreeSpan;
    LPPreviousSpan.NextPartiallyFreeSpan := LPNextSpan;
    LPNextSpan.PreviousPartiallyFreeSpan := LPPreviousSpan;

    {Clear the small block span flag in the header of the medium block.  This is important in case the block is ever
    reused and allocated blocks subsequently enumerated.}
    SetMediumBlockHeader_SetIsSmallBlockSpan(APSmallBlockSpan, False);

    {It's not necessary to check nor update the sequential feed details, since BlocksInUse can only hit 0 after the
    sequential feed range has been exhausted and all the blocks subsequently freed.}

    {Unlock this block type}
    if AUnlockSmallBlockManager then
      APSmallBlockManager.SmallBlockManagerLocked := 0;
    {Free the block pool}
    FastMM_FreeMem_FreeMediumBlock(APSmallBlockSpan);
  end
  else
  begin
    {Unlock this block type}
    if AUnlockSmallBlockManager then
      APSmallBlockManager.SmallBlockManagerLocked := 0;
  end;
end;

{Frees a chain of blocks belonging to the small block manager.  The block manager is assumed to be locked.  Optionally
unlocks the block manager when done.  The first pointer inside each free block should be a pointer to the next free
block.}
procedure FastMM_FreeMem_FreeSmallBlockChain(APSmallBlockManager: PSmallBlockManager; APPendingFreeSmallBlock: Pointer;
  AUnlockSmallBlockManagerWhenDone: Boolean);
var
  LPNextBlock: Pointer;
  LPSmallBlockSpan: PSmallBlockSpanHeader;
begin
  while True do
  begin
    LPNextBlock := PPointer(APPendingFreeSmallBlock)^;

    LPSmallBlockSpan := GetSpanForSmallBlock(APPendingFreeSmallBlock);
    FastMM_FreeMem_InternalFreeSmallBlock_ManagerAlreadyLocked(APSmallBlockManager, LPSmallBlockSpan,
      APPendingFreeSmallBlock, AUnlockSmallBlockManagerWhenDone and (LPNextBlock = nil));

    if LPNextBlock = nil then
      Break;

    APPendingFreeSmallBlock := LPNextBlock;
  end;
end;

{Returns a small block to the memory pool.}
procedure FastMM_FreeMem_FreeSmallBlock(APSmallBlock: Pointer);
var
  LPSmallBlockSpan: PSmallBlockSpanHeader;
  LPSmallBlockManager: PSmallBlockManager;
  LOldFirstFreeBlock, LFirstPendingFreeBlock: Pointer;
begin
  LPSmallBlockSpan := GetSpanForSmallBlock(APSmallBlock);
  LPSmallBlockManager := LPSmallBlockSpan.SmallBlockManager;

  if AtomicCmpExchange(LPSmallBlockManager.SmallBlockManagerLocked, 1, 0) = 0 then
  begin

    {ARM requires a memory fence here.}

    if LPSmallBlockManager.PendingFreeList = nil then
    begin
      FastMM_FreeMem_InternalFreeSmallBlock_ManagerAlreadyLocked(LPSmallBlockManager, LPSmallBlockSpan, APSmallBlock,
        True);
    end
    else
    begin
      FastMM_FreeMem_InternalFreeSmallBlock_ManagerAlreadyLocked(LPSmallBlockManager, LPSmallBlockSpan, APSmallBlock,
        False);

      {Process the pending frees list.}
      while True do
      begin
        LFirstPendingFreeBlock := LPSmallBlockManager.PendingFreeList;
        if (AtomicCmpExchange(LPSmallBlockManager.PendingFreeList, nil, LFirstPendingFreeBlock) = LFirstPendingFreeBlock) then
        begin
          FastMM_FreeMem_FreeSmallBlockChain(LPSmallBlockManager, LFirstPendingFreeBlock, True);

          {There is no need to set the block header since it was never actually freed and will still be marked as "in
          use".}
          Exit;
        end;
      end;

    end;

  end
  else
  begin
    {The small block manager is currently locked, so we need to add this block to its pending free list.}
    while True do
    begin
      LOldFirstFreeBlock := LPSmallBlockManager.PendingFreeList;
      PPointer(APSmallBlock)^ := LOldFirstFreeBlock;
      if AtomicCmpExchange(LPSmallBlockManager.PendingFreeList, APSmallBlock, LOldFirstFreeBlock) = LOldFirstFreeBlock then
        Break;
    end;
  end;
end;

{Allocates a new sequential feed small block span and splits off the first block, returning it.  The small block
manager is assumed to be locked, and will be unlocked before exit.}
function FastMM_GetMem_GetSmallBlock_AllocateNewSequentialFeedSpanAndUnlockArena(APSmallBlockManager: PSmallBlockManager): Pointer;
var
  LPSmallBlockSpan: PSmallBlockSpanHeader;
  LSpanSize, LLastBlockOffset, LTotalBlocksInSpan: Integer;
begin
  {A new sequential feed span may only be allocated once the previous span has been exhausted.}
  Assert(APSmallBlockManager.LastSequentialFeedBlockOffset.IntegerValue <= CSmallBlockSpanHeaderSize);

  LPSmallBlockSpan := FastMM_GetMem_GetMediumBlock(APSmallBlockManager.MinimumSpanSize,
    APSmallBlockManager.OptimalSpanSize, APSmallBlockManager.OptimalSpanSize + CSmallBlockSpanMaximumAmountWithWhichOptimalSizeMayBeExceeded);

  {Handle "out of memory".}
  if LPSmallBlockSpan = nil then
    Exit(nil);

  {Update the medium block header to indicate that this medium block serves as a small block span.}
  SetMediumBlockHeader_SetIsSmallBlockSpan(LPSmallBlockSpan, True);

  LSpanSize := GetMediumBlockSize(LPSmallBlockSpan);

  {Set up the block span}
  LPSmallBlockSpan.SmallBlockManager := APSmallBlockManager;
  LPSmallBlockSpan.FirstFreeBlock := nil;
  APSmallBlockManager.CurrentSequentialFeedSpan := LPSmallBlockSpan;
  {Calculate the number of small blocks that will fit inside the span.  We need to account for the span header,
  as well as the difference in the medium and small block header sizes for the last block.  All the sequential
  feed blocks are initially marked as used.  This implies that the sequential feed span can never be freed until
  all blocks have been fed sequentially.}
  LTotalBlocksInSpan := (LSpanSize - (CSmallBlockSpanHeaderSize + CMediumBlockHeaderSize - CSmallBlockHeaderSize))
    div APSmallBlockManager.BlockSize;
  LPSmallBlockSpan.TotalBlocksInSpan := LTotalBlocksInSpan;
  LPSmallBlockSpan.BlocksInUse := LTotalBlocksInSpan;

  {Set it up for sequential block serving}
  LLastBlockOffset := CSmallBlockSpanHeaderSize + APSmallBlockManager.BlockSize * (LTotalBlocksInSpan - 1);
  APSmallBlockManager.LastSequentialFeedBlockOffset.IntegerValue := LLastBlockOffset;

  {Memory fence required for ARM here.}

  APSmallBlockManager.SmallBlockManagerLocked := 0;

  Result := PByte(LPSmallBlockSpan) + LLastBlockOffset;

  {Set the header for the returned block.}
  SetSmallBlockHeader(Result, LPSmallBlockSpan, False, False);

end;

{Attempts to split off a small block from the sequential feed span for the arena.  Returns the block on success, nil if
there is no available sequential feed block.  The arena does not have to be locked.}
function FastMM_GetMem_GetSmallBlock_GetSequentialFeedBlock(APSmallBlockManager: PSmallBlockManager): Pointer;
var
  LPreviousLastSequentialFeedBlockOffset, LNewLastSequentialFeedBlockOffset: TIntegerWithABACounter;
  LPSequentialFeedSpan: PSmallBlockSpanHeader;
begin
  {The arena is not necessarily locked, so we may have to try several times to split off a block.}
  while True do
  begin
    LPreviousLastSequentialFeedBlockOffset := APSmallBlockManager.LastSequentialFeedBlockOffset;

    if LPreviousLastSequentialFeedBlockOffset.IntegerValue > CSmallBlockSpanHeaderSize then
    begin
      LPSequentialFeedSpan := APSmallBlockManager.CurrentSequentialFeedSpan;

      {Add the block size and increment the ABA counter to the new sequential feed offset.}
      LNewLastSequentialFeedBlockOffset.IntegerAndABACounter := LPreviousLastSequentialFeedBlockOffset.IntegerAndABACounter
        - APSmallBlockManager.BlockSize + Int64(1) shl 32;

      Result := @PByte(LPSequentialFeedSpan)[LNewLastSequentialFeedBlockOffset.IntegerValue];

      if AtomicCmpExchange(APSmallBlockManager.LastSequentialFeedBlockOffset.IntegerAndABACounter,
        LNewLastSequentialFeedBlockOffset.IntegerAndABACounter,
        LPreviousLastSequentialFeedBlockOffset.IntegerAndABACounter) = LPreviousLastSequentialFeedBlockOffset.IntegerAndABACounter then
      begin
        {Set the header for the block.}
        SetSmallBlockHeader(Result, LPSequentialFeedSpan, False, False);
        Exit;
      end;

    end
    else
    begin
      {There is either no sequential feed span, or its space has been exhausted.}
      Exit(nil);
    end;
  end;

end;

{Attempts to reuse a pending free block, freeing all pending free blocks other than the first.  The arena must be
locked.  This function unlocks the small block arena on success.}
function FastMM_GetMem_GetSmallBlock_TryReusePendingFreeBlockAndUnlockArenaOnSuccess(
  APSmallBlockManager: PSmallBlockManager): Pointer;
var
  LPNextFreeBlock: Pointer;
begin
  {Check if there is a pending free list.  If so the first pending free block is returned and the rest are freed.}
  while True do
  begin
    Result := APSmallBlockManager.PendingFreeList;
    if Result = nil then
      Break;

    {Swap out the single linked pending free list and release all the blocks other than the first.}
    if (AtomicCmpExchange(APSmallBlockManager.PendingFreeList, nil, Result) = Result) then
    begin
      LPNextFreeBlock := PPointer(Result)^;
      if LPNextFreeBlock <> nil then
        FastMM_FreeMem_FreeSmallBlockChain(APSmallBlockManager, PPointer(Result)^, True)
      else
        APSmallBlockManager.SmallBlockManagerLocked := 0;

      {Does this block currently contain debug info?  If so, check the header and footer checksums as well as the debug
      fill pattern.}
      if BlockHasDebugInfo(Result) then
      begin
        if (not CheckDebugBlockHeaderAndFooterCheckSumsValid(Result))
          or (not CheckDebugBlockFillPatternIntact(Result)) then
        begin
          System.Error(reInvalidPtr);
        end;

        {Reset the debug info flag in the block.}
        SetBlockHasDebugInfo(Result, False);
      end;

      {There is no need to set the block header since it will still be marked as "in use".}
      Exit;
    end;
  end;
end;

{Attempts to allocate a freed block.  The arena must be locked.}
function FastMM_GetMem_GetSmallBlock_TryAllocateFreeBlockAndUnlockArenaOnSuccess(
  APSmallBlockManager: PSmallBlockManager): Pointer;
var
  LPFirstPartiallyFreeSpan, LPNewFirstPartiallyFreeSpan: PSmallBlockSpanHeader;
begin
  LPFirstPartiallyFreeSpan := APSmallBlockManager.FirstPartiallyFreeSpan;
  if NativeInt(LPFirstPartiallyFreeSpan) <> NativeInt(APSmallBlockManager) then
  begin
    {Return the first free block in the span.}
    Result := LPFirstPartiallyFreeSpan.FirstFreeBlock;

    {Does this block currently contain debug info?  If so, check the header and footer checksums as well as the debug
    fill pattern.}
    if BlockHasDebugInfo(Result) then
    begin
      if (not CheckDebugBlockHeaderAndFooterCheckSumsValid(Result))
        or (not CheckDebugBlockFillPatternIntact(Result)) then
      begin
        APSmallBlockManager.SmallBlockManagerLocked := 0;
        System.Error(reInvalidPtr);
      end;

      {Reset the debug info flag in the block.}
      SetBlockHasDebugInfo(Result, False);
    end;

    {Mark the block as in use.}
    SetBlockIsFreeFlag(Result, False);

    {The current content of the first free block will be a pointer to the next free block in the span.}
    LPFirstPartiallyFreeSpan.FirstFreeBlock := PPointer(Result)^;

    {Increment the number of used blocks}
    Inc(LPFirstPartiallyFreeSpan.BlocksInUse);

    {If there are no more free blocks in the small block span then it must be removed from the circular linked list of
    small block spans with available blocks.}
    if LPFirstPartiallyFreeSpan.FirstFreeBlock = nil then
    begin
      LPNewFirstPartiallyFreeSpan := LPFirstPartiallyFreeSpan.NextPartiallyFreeSpan;
      APSmallBlockManager.FirstPartiallyFreeSpan := LPNewFirstPartiallyFreeSpan;
      LPNewFirstPartiallyFreeSpan.PreviousPartiallyFreeSpan := PSmallBlockSpanHeader(APSmallBlockManager);
    end;

    {ARM requires a data memory barrier here to ensure that all prior writes have completed before the arena is
    unlocked.}

    APSmallBlockManager.SmallBlockManagerLocked := 0;
  end
  else
    Result := nil;
end;

function FastMM_GetMem_GetSmallBlock(ASize: NativeInt): Pointer;
var
  LPSmallBlockManager: PSmallBlockManager;
  LSmallBlockTypeIndex: Integer;
begin
  LSmallBlockTypeIndex := SmallBlockTypeLookup[(NativeUInt(ASize) + (CSmallBlockHeaderSize - 1)) div CSmallBlockGranularity];

  {Get a pointer to the small block manager for the first arena.}
  LPSmallBlockManager := @SmallBlockArenas[0][LSmallBlockTypeIndex];

  while True do
  begin

    {--------------Attempt 1--------------
    Try to get a block from the first arena with an available block.  During the first attempt only memory that has
    already been reserved for use by the block type will be used - no new spans will be allocated.

    Try to obtain a block in this sequence:
      1) The pending free list
      2) From a partially free span
      3) From the sequential feed span}

    {Walk the arenas for this small block type until we find an unlocked arena that can be used to obtain a block.}
    while True do
    begin

      {In order to obtain a block from the pending free list or from a partially free span the arena must be locked.}
      if LPSmallBlockManager.SmallBlockManagerLocked = 0 then
      begin

        if LPSmallBlockManager.PendingFreeList = nil then
        begin

          {The pending free list is empty, so check whether there are any partially free spans.}
          if (NativeInt(LPSmallBlockManager.FirstPartiallyFreeSpan) <> NativeInt(LPSmallBlockManager))
            and (AtomicCmpExchange(LPSmallBlockManager.SmallBlockManagerLocked, 1, 0) = 0) then
          begin

            {Try to get a block from the first partially free span.}
            Result := FastMM_GetMem_GetSmallBlock_TryAllocateFreeBlockAndUnlockArenaOnSuccess(LPSmallBlockManager);
            if Result <> nil then
              Exit;

            {Another thread must allocated the last free block before the arena could be locked.}
            LPSmallBlockManager.SmallBlockManagerLocked := 0;

          end;

        end
        else
        begin

          if AtomicCmpExchange(LPSmallBlockManager.SmallBlockManagerLocked, 1, 0) = 0 then
          begin

            Result := FastMM_GetMem_GetSmallBlock_TryReusePendingFreeBlockAndUnlockArenaOnSuccess(LPSmallBlockManager);
            if Result <> nil then
              Exit;

            {The small block manager is already blocked, so try to allocate a block from the first partially free span.}
            Result := FastMM_GetMem_GetSmallBlock_TryAllocateFreeBlockAndUnlockArenaOnSuccess(LPSmallBlockManager);
            if Result <> nil then
              Exit;

            {Another thread must have processed the free list, and there are also no spans with free blocks.}
            LPSmallBlockManager.SmallBlockManagerLocked := 0;
          end;

        end;

      end;

      {Try to split off a block from the sequential feed span (if there is one).  Splitting off a sequential feed block
      does not require the arena to be locked.}
      Result := FastMM_GetMem_GetSmallBlock_GetSequentialFeedBlock(LPSmallBlockManager);
      if Result <> nil then
        Exit;

      {There are no available blocks in this arena:  Move on to the next arena.}
      if NativeUInt(LPSmallBlockManager) < NativeUInt(@SmallBlockArenas[CSmallBlockArenaCount - 1]) then
        Inc(LPSmallBlockManager, CSmallBlockTypeCount)
      else
        Break;

    end;
    Dec(LPSmallBlockManager, CSmallBlockTypeCount * (CSmallBlockArenaCount - 1));

    {--------------Attempt 2--------------
    Lock the first unlocked arena and try again.  During the second attempt a new sequential feed span will be allocated
    if there are no available blocks in the arena.

    Try to obtain a block in this sequence:
      1) The pending free list
      2) From a partially free span
      3) From the sequential feed span
      4) By allocating a new sequential feed span and splitting off a block from it}

    while True do
    begin

      if AtomicCmpExchange(LPSmallBlockManager.SmallBlockManagerLocked, 1, 0) = 0 then
      begin

        {Check if there is a pending free list.  If so the first pending free block is returned and the rest are
        freed.}
        Result := FastMM_GetMem_GetSmallBlock_TryReusePendingFreeBlockAndUnlockArenaOnSuccess(LPSmallBlockManager);
        if Result <> nil then
          Exit;

        {Try to get a block from the first partially free span.}
        Result := FastMM_GetMem_GetSmallBlock_TryAllocateFreeBlockAndUnlockArenaOnSuccess(LPSmallBlockManager);
        if Result <> nil then
          Exit;

        {It's possible another thread could have allocated a new sequential feed span in the meantime, so we need to
        check again before allocating a new one.}
        Result := FastMM_GetMem_GetSmallBlock_GetSequentialFeedBlock(LPSmallBlockManager);
        if Result <> nil then
        begin
          LPSmallBlockManager.SmallBlockManagerLocked := 0;
          Exit;
        end;

        {Allocate a new sequential feed span and split off a block from it}
        Result := FastMM_GetMem_GetSmallBlock_AllocateNewSequentialFeedSpanAndUnlockArena(LPSmallBlockManager);
        Exit;

      end;

      {Try the next small block arena}
      if NativeUInt(LPSmallBlockManager) < NativeUInt(@SmallBlockArenas[CSmallBlockArenaCount - 1]) then
        Inc(LPSmallBlockManager, CSmallBlockTypeCount)
      else
        Break;
    end;
    Dec(LPSmallBlockManager, CSmallBlockTypeCount * (CSmallBlockArenaCount - 1));

    {--------------Backoff--------------
    All arenas are currently locked:  Back off and start again at the first arena}

    OS_AllowOtherThreadToRun;

  end;

end;

function FastMM_ReallocMem_ReallocSmallBlock(APointer: Pointer; ANewUserSize: NativeInt): Pointer;
var
  LPSmallBlockSpan: PSmallBlockSpanHeader;
  LPSmallBlockManager: PSmallBlockManager;
  LOldUserSize, LNewUserSize: NativeInt;
begin
  LPSmallBlockSpan := GetSpanForSmallBlock(APointer);

  LPSmallBlockManager := LPSmallBlockSpan.SmallBlockManager;

  {Get the available size inside blocks of this type.}
  LOldUserSize := LPSmallBlockManager.BlockSize - CSmallBlockHeaderSize;
  {Is it an upsize or a downsize?}
  if LOldUserSize >= ANewUserSize then
  begin
    {It's a downsize.  Do we need to allocate a smaller block?  Only if the new block size is less than a quarter of
    the available size less SmallBlockDownsizeCheckAdder bytes}
    if (ANewUserSize * 4 + CSmallBlockDownsizeCheckAdder) >= LOldUserSize then
    begin
      {In-place downsize - return the pointer}
      Result := APointer;
      Exit;
    end
    else
    begin
      {Allocate a smaller block}
      Result := FastMM_GetMem(ANewUserSize);
      {Allocated OK?}
      if Result <> nil then
      begin
        {Move the data across}
        System.Move(APointer^, Result^, ANewUserSize);
        {Free the old pointer}
        FastMM_FreeMem(APointer);
      end;
    end;
  end
  else
  begin
    {This pointer is being reallocated to a larger block and therefore it is logical to assume that it may be enlarged
    again.  Since reallocations are expensive, there is a minimum upsize percentage to avoid unnecessary future move
    operations.}
    {Must grow with at least 100% + x bytes}
    LNewUserSize := LOldUserSize * 2 + CSmallBlockUpsizeAdder;

    {Still not large enough?}
    if LNewUserSize < ANewUserSize then
      LNewUserSize := ANewUserSize;

    {Allocate the new block, move the old data across and then free the old block.}
    Result := FastMM_GetMem(LNewUserSize);
    if Result <> nil then
    begin
      LPSmallBlockManager.UpsizeMoveProcedure(APointer^, Result^, LOldUserSize);
      FastMM_FreeMem(APointer);
    end;

  end;
end;


{-----------------------------------------}
{--------Debug block management-----------}
{-----------------------------------------}

function FastMM_FreeMem_FreeDebugBlock(APointer: Pointer): Integer;
var
  LPActualBlock: PFastMM_DebugBlockHeader;
begin
  LPActualBlock := PFastMM_DebugBlockHeader(PByte(APointer) - CDebugBlockHeaderSize);

  {Check that the debug header and footer are intact}
  if not CheckDebugBlockHeaderAndFooterCheckSumsValid(LPActualBlock) then
    System.Error(reInvalidPtr);

  {Update the information in the block header.}
  LPActualBlock.FreedByThread := OS_GetCurrentThreadID;
  FastMM_GetStackTrace(@LPActualBlock.FreeStackTrace, CFastMM_StackTraceEntryCount, 0);
  LPActualBlock.PreviouslyUsedByClass := PPointer(APointer)^;

  {Fill the user area of the block with the debug pattern.}
  FillDebugBlockWithDebugPattern(LPActualBlock);

  {The block is now free.}
  LPActualBlock.DebugBlockFlags := CIsDebugBlockFlag or CBlockIsFreeFlag;

  {Update the header and footer checksums}
  SetDebugBlockHeaderAndFooterChecksums(LPActualBlock);

  {Return the actual block to the memory pool.}
  Result := FastMM_FreeMem(LPActualBlock);
end;

{Reallocates a block containing debug information.  Any debug information remains intact.}
function FastMM_ReallocMem_ReallocDebugBlock(APointer: Pointer; ANewSize: NativeInt): Pointer;
var
  LPActualBlock: PFastMM_DebugBlockHeader;
  LAvailableSpace: NativeInt;
begin
  LPActualBlock := PFastMM_DebugBlockHeader(PByte(APointer) - CDebugBlockHeaderSize);

  {Check that the debug header and footer are intact}
  if not CheckDebugBlockHeaderAndFooterCheckSumsValid(LPActualBlock) then
    System.Error(reInvalidPtr);

  {Can the block be resized in-place?}
  LAvailableSpace := FastMM_BlockMaximumUserBytes(LPActualBlock);
  if LAvailableSpace >= ANewSize + (CDebugBlockHeaderSize + CDebugBlockFooterSize) then
  begin
    {Update the user block size and set the new header and footer checksums.}
    LPActualBlock.UserSize := ANewSize;
    SetDebugBlockHeaderAndFooterChecksums(LPActualBlock);

    Result := APointer;
  end
  else
  begin
    {The new size cannot fit in the existing block:  We need to allocate a new block.}
    Result := FastMM_GetMem(ANewSize + (CDebugBlockHeaderSize + CDebugBlockFooterSize));

    if Result <> nil then
    begin
      {Move the old data across and free the old block.}
      System.Move(LPActualBlock^, Result^, LPActualBlock.UserSize + CDebugBlockHeaderSize);
      FastMM_FreeMem_FreeDebugBlock(APointer);

      {Update the user block size and set the new header and footer checksums.}
      PFastMM_DebugBlockHeader(Result).UserSize := ANewSize;
      SetDebugBlockHeaderAndFooterChecksums(PFastMM_DebugBlockHeader(Result));

      {Set the flag in the actual block header to indicate that the block contains debug information.}
      SetBlockHasDebugInfo(Result, True);

      {Return a pointer to the user data}
      Inc(PByte(Result), CDebugBlockHeaderSize);

    end;

  end;
end;

{----------------------------------------------------}
{------------Invalid Free/realloc handling-----------}
{----------------------------------------------------}

procedure HandleInvalidFreeMemOrReallocMem(APointer: Pointer; AIsReallocMemCall: Boolean);
const
  CTokenBufferSize = 65536;
var
  LPDebugBlockHeader: PFastMM_DebugBlockHeader;
  LHeaderChecksum: NativeUInt;
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize - 1] of WideChar;
  LPBufferPos, LPBufferEnd: PWideChar;
begin
  {Is this a debug block that has already been freed?  If not, it could be a bad pointer value, in which case there's
  not much that can be done to provide additional error information.}
  if PWord(PByte(APointer) - CBlockStatusWordSize)^ <> (CBlockIsFreeFlag or CIsDebugBlockFlag) then
    Exit;

  {Check that the debug block header is intact.  If it is, then a meaningful error may be returned.}
  LPDebugBlockHeader := PFastMM_DebugBlockHeader(PByte(APointer) - CDebugBlockHeaderSize);
  LHeaderChecksum := CalculateDebugBlockHeaderChecksum(LPDebugBlockHeader);
  if LPDebugBlockHeader.HeaderCheckSum <> LHeaderChecksum then
    Exit;

  LTokenValues := Default(TEventLogTokenValues);

  LPBufferEnd := @LTokenValueBuffer[High(LTokenValueBuffer)];
  LPBufferPos := AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, LPBufferEnd);
  AddTokenValues_BlockTokens(LTokenValues, APointer, LPBufferPos, LPBufferEnd);

  if AIsReallocMemCall then
    LogEvent(mmetDebugBlockReallocOfFreedBlock, LTokenValues)
  else
    LogEvent(mmetDebugBlockDoubleFree, LTokenValues);
end;

{--------------------------------------------------------}
{-------Core memory manager interface: Normal mode-------}
{--------------------------------------------------------}

function FastMM_GetMem(ASize: NativeInt): Pointer;
begin
  {Is it a small block allocation request?}
  if NativeUInt(ASize) <= (CMaximumSmallBlockSize - CSmallBlockHeaderSize) then
  begin
    Result := FastMM_GetMem_GetSmallBlock(ASize);
  end
  else
  begin
    {Medium or large block.}
    if NativeUInt(ASize) <= (CMaximumMediumBlockSize - CMediumBlockHeaderSize) then
    begin
      {Add the size of the block header and round up to an exact bin size}
      ASize := RoundUserSizeUpToNextMediumBlockBin(ASize);
      Result := FastMM_GetMem_GetMediumBlock(ASize, ASize, ASize);
    end
    else
    begin
      Result := FastMM_GetMem_GetLargeBlock(ASize);
    end;
  end;
end;

function FastMM_FreeMem(APointer: Pointer): Integer;
var
  LBlockHeader: Integer;
begin
  {Read the flags from the block header.}
  LBlockHeader := PWord(PByte(APointer) - CBlockStatusWordSize)^;

  {Is it a small block that is in use?}
  if LBlockHeader and (CBlockIsFreeFlag or CIsSmallBlockFlag) = CIsSmallBlockFlag then
  begin
    FastMM_FreeMem_FreeSmallBlock(APointer);
    {No error}
    Result := 0;
  end
  else
  begin
    if LBlockHeader and (not CHasDebugInfoFlag) = CIsMediumBlockFlag then
    begin
      Result := FastMM_FreeMem_FreeMediumBlock(APointer);
    end
    else
    begin
      if LBlockHeader and (not CHasDebugInfoFlag) = CIsLargeBlockFlag then
      begin
        Result := FastMM_FreeMem_FreeLargeBlock(APointer);
      end
      else
      begin
        if LBlockHeader = CIsDebugBlockFlag then
        begin
          Result := FastMM_FreeMem_FreeDebugBlock(APointer);
        end
        else
        begin
          HandleInvalidFreeMemOrReallocMem(APointer, False);
          Result := -1;
        end;
      end;
    end;
  end;
end;

function FastMM_ReallocMem(APointer: Pointer; ANewSize: NativeInt): Pointer;
var
  LBlockHeader: Integer;
begin
  {Read the flags from the block header.}
  LBlockHeader := PWord(PByte(APointer) - CBlockStatusWordSize)^;

  {Is it a small block that is in use?}
  if LBlockHeader and (CBlockIsFreeFlag or CIsSmallBlockFlag) = CIsSmallBlockFlag then
  begin
    Result := FastMM_ReallocMem_ReallocSmallBlock(APointer, ANewSize);
  end
  else
  begin
    {Is this a medium block in use?}
    if LBlockHeader and (not CHasDebugInfoFlag) = CIsMediumBlockFlag then
    begin
      Result := FastMM_ReallocMem_ReallocMediumBlock(APointer, ANewSize);
    end
    else
    begin
      if LBlockHeader and (not CHasDebugInfoFlag) = CIsLargeBlockFlag then
      begin
        Result := FastMM_ReallocMem_ReallocLargeBlock(APointer, ANewSize);
      end
      else
      begin
        if LBlockHeader = CIsDebugBlockFlag then
        begin
          Result := FastMM_ReallocMem_ReallocDebugBlock(APointer, ANewSize)
        end
        else
        begin
          HandleInvalidFreeMemOrReallocMem(APointer, True);
          Result := nil;
        end;
      end;

    end;
  end;
end;

function FastMM_AllocMem(ASize: NativeInt): Pointer;
begin
  Result := FastMM_GetMem(ASize);
  {Large blocks are already zero filled}
  if (Result <> nil) and (ASize <= (CMaximumMediumBlockSize - CMediumBlockHeaderSize)) then
    FillChar(Result^, ASize, 0);
end;


{--------------------------------------------------------}
{-------Core memory manager interface: Debug mode--------}
{--------------------------------------------------------}

function FastMM_DebugGetMem_GetDebugBlock(ASize: NativeInt; AFillBlockWithDebugPattern: Boolean): Pointer;
begin
  Result := FastMM_GetMem(ASize + (CDebugBlockHeaderSize + CDebugBlockFooterSize));
  if Result = nil then
    Exit;

  {Populate the debug header and set the header and footer checksums.}
  PFastMM_DebugBlockHeader(Result).UserSize := ASize;
  PFastMM_DebugBlockHeader(Result).PreviouslyUsedByClass := nil;
  FastMM_GetStackTrace(@PFastMM_DebugBlockHeader(Result).AllocationStackTrace, CFastMM_StackTraceEntryCount, 0);
  PFastMM_DebugBlockHeader(Result).FreeStackTrace := Default(TFastMM_StackTrace);
  PFastMM_DebugBlockHeader(Result).AllocationGroup := FastMM_CurrentAllocationGroup;
  PFastMM_DebugBlockHeader(Result).AllocationNumber := AtomicIncrement(FastMM_LastAllocationNumber);
  PFastMM_DebugBlockHeader(Result).AllocatedByThread := OS_GetCurrentThreadID;
  PFastMM_DebugBlockHeader(Result).FreedByThread := 0;
  PFastMM_DebugBlockHeader(Result).DebugBlockFlags := CIsDebugBlockFlag;
  SetDebugBlockHeaderAndFooterChecksums(Result);

  {Fill the block with the debug pattern}
  if AFillBlockWithDebugPattern then
    FillDebugBlockWithDebugPattern(Result);

  {Set the flag in the actual block header to indicate that the block contains debug information.}
  SetBlockHasDebugInfo(Result, True);

  {Return a pointer to the user data}
  Inc(PByte(Result), CDebugBlockHeaderSize);
end;

function FastMM_DebugGetMem(ASize: NativeInt): Pointer;
begin
  Result := FastMM_DebugGetMem_GetDebugBlock(ASize, True);
end;

function FastMM_DebugFreeMem(APointer: Pointer): Integer;
begin
  Result := FastMM_FreeMem(APointer);
end;

function FastMM_DebugReallocMem(APointer: Pointer; ANewSize: NativeInt): Pointer;
var
  LBlockHeader: Integer;
  LMoveCount: NativeInt;
begin
  {Read the flags from the block header.}
  LBlockHeader := PWord(PByte(APointer) - CBlockStatusWordSize)^;

  if LBlockHeader = CIsDebugBlockFlag then
  begin
    Result := FastMM_ReallocMem_ReallocDebugBlock(APointer, ANewSize);
  end
  else
  begin
    {Catch an attempt to reallocate a freed block.}
    if LBlockHeader and CBlockIsFreeFlag <> 0 then
    begin
      HandleInvalidFreeMemOrReallocMem(APointer, True);
      Exit(nil);
    end;

    {The old block is not a debug block, so we need to allocate a new debug block and copy the data across.}
    Result := FastMM_DebugGetMem_GetDebugBlock(ANewSize, False);

    if Result <> nil then
    begin
      {Determine the used user size of the old block and move the lesser of the old and new sizes, and then free the
      old block.}
      LMoveCount := FastMM_BlockCurrentUserBytes(APointer);
      if LMoveCount > ANewSize then
        LMoveCount := ANewSize;
      System.Move(APointer^, Result^, LMoveCount);

      FastMM_FreeMem(APointer);
    end;
  end;

end;

function FastMM_DebugAllocMem(ASize: NativeInt): Pointer;
begin
  Result := FastMM_DebugGetMem_GetDebugBlock(ASize, False);
  {Large blocks are already zero filled}
  if (Result <> nil) and (ASize <= (CMaximumMediumBlockSize - CMediumBlockHeaderSize - CDebugBlockHeaderSize - CDebugBlockFooterSize)) then
    FillChar(Result^, ASize, 0);
end;

procedure FastMM_NoOpGetStackTrace(APReturnAddresses: PNativeUInt; AMaxDepth, ASkipFrames: Cardinal);
var
  i: Integer;
begin
  for i := 1 to AMaxDepth do
  begin
    APReturnAddresses^ := 0;
    Inc(APReturnAddresses);
  end;
end;

function FastMM_NoOpConvertStackTraceToText(APReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
  APBufferPosition, APBufferEnd: PWideChar): PWideChar;
begin
  {Nothing to do.}
  Result := APBufferPosition;
end;

function FastMM_DebugLibrary_LegacyLogStackTrace_Wrapper(APReturnAddresses: PNativeUInt; AMaxDepth: Cardinal;
  APBufferPosition, APBufferEnd: PWideChar): PWideChar;
var
  LAnsiBuffer: array[0..CFastMM_StackTraceEntryCount * 256] of AnsiChar;
  LPEnd, LPCurPos: PAnsiChar;
begin
  Result := APBufferPosition;

  LPEnd := DebugLibrary_LogStackTrace_Legacy(APReturnAddresses, AMaxDepth, @LAnsiBuffer);
  LPCurPos := @LAnsiBuffer;
  while (LPCurPos < LPEnd)
    and (Result < APBufferEnd) do
  begin
    Result^ := WideChar(LPCurPos^); //Assume it is Latin-1 text
    Inc(Result);
    Inc(LPCurPos);
  end;
end;

{--------------------------------------------------------}
{----------------------Diagnostics-----------------------}
{--------------------------------------------------------}

{Returns the user size of the block, i.e. the number of bytes in use by the application.}
function FastMM_BlockCurrentUserBytes(APointer: Pointer): NativeInt;
var
  LBlockHeader: Integer;
  LPSmallBlockSpan: PSmallBlockSpanHeader;
begin
  {Read the flags from the block header.}
  LBlockHeader := PWord(PByte(APointer) - CBlockStatusWordSize)^;
  {Is it a small block that is in use?}
  if LBlockHeader and CIsSmallBlockFlag = CIsSmallBlockFlag then
  begin
    LPSmallBlockSpan := GetSpanForSmallBlock(APointer);
    Result := LPSmallBlockSpan.SmallBlockManager.BlockSize - CSmallBlockHeaderSize;
  end
  else
  begin
    if LBlockHeader and CIsMediumBlockFlag = CIsMediumBlockFlag then
    begin
      Result := GetMediumBlockSize(APointer) - CMediumBlockHeaderSize;
    end
    else
    begin
      if LBlockHeader and CIsLargeBlockFlag = CIsLargeBlockFlag then
      begin
        Result := PLargeBlockHeader(PByte(APointer) - CLargeBlockHeaderSize).UserAllocatedSize;
      end
      else
      begin
        if LBlockHeader and CIsDebugBlockFlag = CIsDebugBlockFlag then
        begin
          Result := PFastMM_DebugBlockHeader(PByte(APointer) - CDebugBlockHeaderSize).UserSize;
        end
        else
        begin
          System.Error(reInvalidPtr);
          Result := 0;
        end;
      end;
    end;
  end;

end;

{Returns the available user size of the block, i.e. the block size less any headers and footers.}
function FastMM_BlockMaximumUserBytes(APointer: Pointer): NativeInt;
var
  LBlockHeader: Integer;
  LPSmallBlockSpan: PSmallBlockSpanHeader;
begin
  {Read the flags from the block header.}
  LBlockHeader := PWord(PByte(APointer) - CBlockStatusWordSize)^;
  {Is it a small block?}
  if LBlockHeader and CIsSmallBlockFlag = CIsSmallBlockFlag then
  begin
    LPSmallBlockSpan := GetSpanForSmallBlock(APointer);

    Result := LPSmallBlockSpan.SmallBlockManager.BlockSize - CSmallBlockHeaderSize;
  end
  else
  begin
    if LBlockHeader and CIsMediumBlockFlag = CIsMediumBlockFlag then
    begin
      Result := GetMediumBlockSize(APointer) - CMediumBlockHeaderSize;
    end
    else
    begin
      if LBlockHeader and CIsLargeBlockFlag = CIsLargeBlockFlag then
      begin
        Result := PLargeBlockHeader(PByte(APointer) - CLargeBlockHeaderSize).ActualBlockSize - CLargeBlockHeaderSize;
      end
      else
      begin
        if LBlockHeader and CIsDebugBlockFlag = CIsDebugBlockFlag then
        begin
          Result := PFastMM_DebugBlockHeader(PByte(APointer) - CDebugBlockHeaderSize).UserSize;
        end
        else
        begin
          System.Error(reInvalidPtr);
          Result := 0;
        end;
      end;
    end;
  end;

end;

function FastMM_ProcessAllPendingFrees: Boolean;
var
  LArenaIndex, LBlockTypeIndex: Integer;
  LPSmallBlockManager: PSmallBlockManager;
  LPPendingFreeBlock, LPNextPendingFreeBlock: Pointer;
  LPMediumBlockManager: PMediumBlockManager;
  LPMediumBlockSpan: PMediumBlockSpanHeader;
  LPLargeBlockManager: PLargeBlockManager;
begin
  {Assume success, until proven otherwise.}
  Result := True;

  {-------Small blocks-------}
  for LArenaIndex := 0 to CSmallBlockArenaCount - 1 do
  begin
    LPSmallBlockManager := @SmallBlockArenas[LArenaIndex][0];

    for LBlockTypeIndex := 0 to CSmallBlockTypeCount - 1 do
    begin

      if LPSmallBlockManager.PendingFreeList <> nil then
      begin
        if AtomicCmpExchange(LPSmallBlockManager.SmallBlockManagerLocked, 1, 0) = 0 then
        begin

          {Process the pending frees list.}
          while True do
          begin

            LPPendingFreeBlock := LPSmallBlockManager.PendingFreeList;
            if LPPendingFreeBlock = nil then
            begin
              LPSmallBlockManager.SmallBlockManagerLocked := 0;
              Break;
            end;

            if (AtomicCmpExchange(LPSmallBlockManager.PendingFreeList, nil, LPPendingFreeBlock) = LPPendingFreeBlock) then
            begin
              FastMM_FreeMem_FreeSmallBlockChain(LPSmallBlockManager, LPPendingFreeBlock, True);
              Break;
            end;

          end;

        end
        else
        begin
          {The small block manager has pending frees, but could not be locked.}
          Result := False;
        end;

      end;

      Inc(LPSmallBlockManager);
    end;
  end;

  {-------Medium blocks-------}
  LPMediumBlockManager := @MediumBlockArenas[0];
  for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
  begin

    if LPMediumBlockManager.PendingFreeList <> nil then
    begin

      if AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0 then
      begin

        {Retrieve the pending free list pointer.}
        while True do
        begin
          LPPendingFreeBlock := LPMediumBlockManager.PendingFreeList;
          if AtomicCmpExchange(LPMediumBlockManager.PendingFreeList, nil, LPPendingFreeBlock) = LPPendingFreeBlock then
            Break;
        end;

        while LPPendingFreeBlock <> nil do
        begin
          LPNextPendingFreeBlock := PPointer(LPPendingFreeBlock)^;

          LPMediumBlockSpan := GetMediumBlockSpan(LPPendingFreeBlock);
          if FastMM_FreeMem_InternalFreeMediumBlock_ManagerAlreadyLocked(LPMediumBlockManager, LPMediumBlockSpan,
            LPPendingFreeBlock, False) <> 0 then
          begin
            System.Error(reInvalidPtr);
          end;

          LPPendingFreeBlock := LPNextPendingFreeBlock;
        end;

        {Memory fence needed here for ARM}

        LPMediumBlockManager.MediumBlockManagerLocked := 0;
      end
      else
      begin
        {The medium block manager has pending frees, but could not be locked.}
        Result := False;
      end;
    end;

    Inc(LPMediumBlockManager);
  end;

  {-------Large blocks-------}
  LPLargeBlockManager := @LargeBlockArenas[0];
  for LArenaIndex := 0 to CLargeBlockArenaCount - 1 do
  begin

    if LPLargeBlockManager.PendingFreeList <> nil then
    begin
      if AtomicCmpExchange(LPLargeBlockManager.LargeBlockManagerLocked, 1, 0) = 0 then
      begin

        if ProcessLargeBlockPendingFrees_ArenaAlreadyLocked(LPLargeBlockManager) <> 0 then
        begin
          System.Error(reInvalidPtr);
        end;

      end;
    end
    else
    begin
      {The large block manager has pending frees, but could not be locked.}
      Result := False;
    end;

    Inc(LPLargeBlockManager);
  end;

end;

{Adjusts the block information for blocks that contain a debug mode sub-block.}
procedure FastMM_WalkBlocks_AdjustForDebugSubBlock(var ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo); inline;
begin
  if BlockHasDebugInfo(ABlockInfo.BlockAddress) then
  begin
    ABlockInfo.DebugInformation := ABlockInfo.BlockAddress;
    ABlockInfo.UsableSize := ABlockInfo.DebugInformation.UserSize;
    Inc(PByte(ABlockInfo.BlockAddress), CDebugBlockHeaderSize);
  end
  else
    ABlockInfo.DebugInformation := nil;
end;

{Walks the block types indicated by the AWalkBlockTypes set, calling ACallBack for each allocated block.}
procedure FastMM_WalkBlocks(ACallBack: TFastMM_WalkBlocksCallback; AWalkBlockTypes: TFastMM_WalkBlocksBlockTypes;
  AWalkUsedBlocksOnly: Boolean; AUserData: Pointer);
var
  LArenaIndex: Integer;
  LBlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo;
  LPLargeBlockManager: PLargeBlockManager;
  LPLargeBlock: PLargeBlockHeader;
  LPMediumBlockManager: PMediumBlockManager;
  LPMediumBlockSpan: PMediumBlockSpanHeader;
  LPMediumBlock: Pointer;
  LBlockOffsetFromMediumSpanStart, LMediumBlockSize, LSmallBlockOffset, LLastBlockOffset: Integer;
  LPMediumBlockHeader: PMediumBlockHeader;
  LPSmallBlockManager: PSmallBlockManager;
begin
  LBlockInfo.UserData := AUserData;

  if AWalkBlockTypes = [] then
    AWalkBlockTypes := [Low(TFastMM_WalkAllocatedBlocksBlockType)..High(TFastMM_WalkAllocatedBlocksBlockType)];

  {Walk the large block managers}
  if btLargeBlock in AWalkBlockTypes then
  begin
    LBlockInfo.BlockType := btLargeBlock;
    LBlockInfo.BlockIsFree := False;

    {Clear the fields that are not applicable to large blocks.}
    LBlockInfo.IsSequentialFeedMediumBlockSpan := False;
    LBlockInfo.MediumBlockSequentialFeedSpanUnusedBytes := 0;
    LBlockInfo.SmallBlockSpanBlockSize := 0;
    LBlockInfo.IsSequentialFeedSmallBlockSpan := False;

    for LArenaIndex := 0 to CLargeBlockArenaCount - 1 do
    begin
      LPLargeBlockManager := @LargeBlockArenas[LArenaIndex];

      LBlockInfo.ArenaIndex := LArenaIndex;

      while True do
      begin
        if AtomicCmpExchange(LPLargeBlockManager.LargeBlockManagerLocked, 1, 0) = 0 then
          Break;
        OS_AllowOtherThreadToRun;
      end;

      LPLargeBlock := LPLargeBlockManager.FirstLargeBlockHeader;
      while NativeUInt(LPLargeBlock) <> NativeUInt(LPLargeBlockManager) do
      begin
        LBlockInfo.BlockAddress := LPLargeBlock;
        LBlockInfo.BlockSize := LPLargeBlock.ActualBlockSize;
        LBlockInfo.UsableSize := LPLargeBlock.UserAllocatedSize;

        FastMM_WalkBlocks_AdjustForDebugSubBlock(LBlockInfo);
        ACallBack(LBlockInfo);

        LPLargeBlock := LPLargeBlock.NextLargeBlockHeader;
      end;

      LPLargeBlockManager.LargeBlockManagerLocked := 0;
    end;

  end;

  {Walk the medium block managers}
  if AWalkBlockTypes * [btMediumBlockSpan, btMediumBlock, btSmallBlockSpan, btSmallBlock] <> [] then
  begin

    for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
    begin
      LPMediumBlockManager := @MediumBlockArenas[LArenaIndex];

      LBlockInfo.ArenaIndex := LArenaIndex;

      while True do
      begin
        if AtomicCmpExchange(LPMediumBlockManager.MediumBlockManagerLocked, 1, 0) = 0 then
          Break;
        OS_AllowOtherThreadToRun;
      end;

      LPMediumBlockSpan := LPMediumBlockManager.FirstMediumBlockSpanHeader;
      while NativeUInt(LPMediumBlockSpan) <> NativeUInt(LPMediumBlockManager) do
      begin

        if LPMediumBlockManager.SequentialFeedMediumBlockSpan = LPMediumBlockSpan then
        begin
          LBlockOffsetFromMediumSpanStart := LPMediumBlockManager.LastSequentialFeedBlockOffset.IntegerValue;
          if LBlockOffsetFromMediumSpanStart <= CMediumBlockSpanHeaderSize then
            LBlockOffsetFromMediumSpanStart := CMediumBlockSpanHeaderSize;
        end
        else
          LBlockOffsetFromMediumSpanStart := CMediumBlockSpanHeaderSize;

        if btMediumBlockSpan in AWalkBlockTypes then
        begin
          LBlockInfo.BlockAddress := LPMediumBlockSpan;
          LBlockInfo.BlockSize := LPMediumBlockSpan.SpanSize;
          LBlockInfo.UsableSize := LPMediumBlockSpan.SpanSize - CMediumBlockSpanHeaderSize;
          LBlockInfo.BlockType := btMediumBlockSpan;
          LBlockInfo.BlockIsFree := False;
          LBlockInfo.ArenaIndex := LArenaIndex;
          if LBlockOffsetFromMediumSpanStart > CMediumBlockSpanHeaderSize then
          begin
            LBlockInfo.IsSequentialFeedMediumBlockSpan := True;
            LBlockInfo.MediumBlockSequentialFeedSpanUnusedBytes := LBlockOffsetFromMediumSpanStart - CMediumBlockSpanHeaderSize;
          end
          else
          begin
            LBlockInfo.IsSequentialFeedMediumBlockSpan := False;
            LBlockInfo.MediumBlockSequentialFeedSpanUnusedBytes := 0;
          end;
          LBlockInfo.SmallBlockSpanBlockSize := 0;
          LBlockInfo.IsSequentialFeedSmallBlockSpan := False;
          LBlockInfo.DebugInformation := nil;

          ACallBack(LBlockInfo);
        end;

        {Walk all the medium blocks in the medium block span.}
        if AWalkBlockTypes * [btMediumBlock, btSmallBlockSpan, btSmallBlock] <> [] then
        begin
          while LBlockOffsetFromMediumSpanStart < LPMediumBlockSpan.SpanSize do
          begin
            LPMediumBlock := PByte(LPMediumBlockSpan) + LBlockOffsetFromMediumSpanStart;
            LMediumBlockSize := GetMediumBlockSize(LPMediumBlock);

            LBlockInfo.BlockIsFree := BlockIsFree(LPMediumBlock);
            if (not AWalkUsedBlocksOnly) or (not LBlockInfo.BlockIsFree) then
            begin
              LPMediumBlockHeader := Pointer(PByte(LPMediumBlock) - CMediumBlockHeaderSize);

              {Read the pointer to the small block manager in case this is a small block span.}
              if (AWalkBlockTypes * [btSmallBlockSpan, btSmallBlock] <> [])
                and LPMediumBlockHeader.IsSmallBlockSpan then
              begin
                LPSmallBlockManager := PSmallBlockSpanHeader(LPMediumBlock).SmallBlockManager;

                while True do
                begin
                  if AtomicCmpExchange(LPSmallBlockManager.SmallBlockManagerLocked, 1, 0) = 0 then
                    Break;
                  OS_AllowOtherThreadToRun;
                end;

                {Memory fence required for ARM}

                {The last block may have been released before the manager was locked, so we need to check whether it is
                still a small block span.}
                if LPMediumBlockHeader.IsSmallBlockSpan then
                begin
                  if LPSmallBlockManager.CurrentSequentialFeedSpan = LPMediumBlock then
                  begin
                    LSmallBlockOffset := LPSmallBlockManager.LastSequentialFeedBlockOffset.IntegerValue;
                    if LSmallBlockOffset < LSmallBlockOffset then
                      LSmallBlockOffset := CSmallBlockSpanHeaderSize;
                  end
                  else
                    LSmallBlockOffset := CSmallBlockSpanHeaderSize;
                end
                else
                begin
                  LSmallBlockOffset := 0;
                  LPSmallBlockManager.SmallBlockManagerLocked := 0;
                  LPSmallBlockManager := nil;
                end;
              end
              else
              begin
                LPSmallBlockManager := nil;
                LSmallBlockOffset := 0;
              end;

              if AWalkBlockTypes * [btMediumBlock, btSmallBlockSpan] <> [] then
              begin
                LBlockInfo.BlockAddress := LPMediumBlock;
                LBlockInfo.BlockSize := LMediumBlockSize;
                LBlockInfo.ArenaIndex := LArenaIndex;
                LBlockInfo.MediumBlockSequentialFeedSpanUnusedBytes := 0;

                if LPSmallBlockManager <> nil then
                begin
                  if btSmallBlockSpan in AWalkBlockTypes then
                  begin
                    LBlockInfo.BlockType := btSmallBlockSpan;

  { TODO : Also subtract the partial last block from the usable size.}
                    LBlockInfo.UsableSize := LMediumBlockSize - CMediumBlockHeaderSize - CSmallBlockSpanHeaderSize;

                    LBlockInfo.SmallBlockSpanBlockSize := LPSmallBlockManager.BlockSize;
                    LBlockInfo.IsSequentialFeedSmallBlockSpan := LSmallBlockOffset > CSmallBlockSpanHeaderSize;
                    if LBlockInfo.IsSequentialFeedSmallBlockSpan then
                      LBlockInfo.SmallBlockSequentialFeedSpanUnusedBytes := LSmallBlockOffset - CSmallBlockSpanHeaderSize
                    else
                      LBlockInfo.SmallBlockSequentialFeedSpanUnusedBytes := 0;
                    LBlockInfo.DebugInformation := nil;
                    ACallBack(LBlockInfo);
                  end;
                end
                else
                begin
                  if btMediumBlock in AWalkBlockTypes then
                  begin
                    LBlockInfo.BlockType := btMediumBlock;
                    LBlockInfo.UsableSize := LMediumBlockSize - CMediumBlockHeaderSize;
                    LBlockInfo.SmallBlockSpanBlockSize := 0;
                    LBlockInfo.IsSequentialFeedSmallBlockSpan := False;
                    LBlockInfo.SmallBlockSequentialFeedSpanUnusedBytes := 0;
                    FastMM_WalkBlocks_AdjustForDebugSubBlock(LBlockInfo);
                    ACallBack(LBlockInfo);
                  end;
                end;

              end;

              {If small blocks need to be walked then LPSmallBlockManager will be <> nil.}
              if LPSmallBlockManager <> nil then
              begin

                if btSmallBlock in AWalkBlockTypes then
                begin
                  LLastBlockOffset := CSmallBlockSpanHeaderSize
                    + LPSmallBlockManager.BlockSize * (PSmallBlockSpanHeader(LPMediumBlock).TotalBlocksInSpan - 1);
                  while LSmallBlockOffset <= LLastBlockOffset do
                  begin
                    LBlockInfo.BlockAddress := PByte(LPMediumBlock) + LSmallBlockOffset;

                    LBlockInfo.BlockIsFree := BlockIsFree(LBlockInfo.BlockAddress);
                    if (not AWalkUsedBlocksOnly) or (not LBlockInfo.BlockIsFree) then
                    begin
                      LBlockInfo.BlockSize := LPSmallBlockManager.BlockSize;
                      LBlockInfo.UsableSize := LPSmallBlockManager.BlockSize - CSmallBlockHeaderSize;
                      LBlockInfo.ArenaIndex := (NativeInt(LPSmallBlockManager) - NativeInt(@SmallBlockArenas)) div SizeOf(TSmallBlockArena);
                      LBlockInfo.BlockType := btSmallBlock;
                      LBlockInfo.IsSequentialFeedMediumBlockSpan := False;
                      LBlockInfo.MediumBlockSequentialFeedSpanUnusedBytes := 0;
                      LBlockInfo.IsSequentialFeedSmallBlockSpan := False;
                      LBlockInfo.SmallBlockSpanBlockSize := 0;
                      LBlockInfo.SmallBlockSequentialFeedSpanUnusedBytes := 0;

                      FastMM_WalkBlocks_AdjustForDebugSubBlock(LBlockInfo);
                      ACallBack(LBlockInfo);
                    end;

                    Inc(LSmallBlockOffset, LPSmallBlockManager.BlockSize);
                  end;
                end;

                LPSmallBlockManager.SmallBlockManagerLocked := 0;
              end;

            end;

            Inc(LBlockOffsetFromMediumSpanStart, LMediumBlockSize);
          end;
        end;

        LPMediumBlockSpan := LPMediumBlockSpan.NextMediumBlockSpanHeader;
      end;

      LPMediumBlockManager.MediumBlockManagerLocked := 0;
    end;

  end;

end;

procedure FastMM_ScanDebugBlocksForCorruption_CallBack(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
begin
  {If it is not a debug mode block then there's nothing to check.}
  if ABlockInfo.DebugInformation = nil then
    Exit;

  {Check the block header and footer for corruption}
  if not CheckDebugBlockHeaderAndFooterCheckSumsValid(ABlockInfo.DebugInformation) then
    System.Error(reInvalidPtr);

  {If it is a free block, check whether it has been modified after being freed.}
  if ABlockInfo.BlockIsFree and (not CheckDebugBlockFillPatternIntact(ABlockInfo.DebugInformation)) then
    System.Error(reInvalidPtr);
end;

procedure FastMM_ScanDebugBlocksForCorruption;
begin
  FastMM_WalkBlocks(FastMM_ScanDebugBlocksForCorruption_CallBack, [btLargeBlock, btMediumBlock, btSmallBlock], False);
end;

procedure FastMM_GetHeapStatus_CallBack(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
var
  LPHeapStatus: ^THeapStatus;
begin
  LPHeapStatus := ABlockInfo.UserData;

  case ABlockInfo.BlockType of

    btLargeBlock:
    begin
      Inc(LPHeapStatus.TotalAddrSpace, ABlockInfo.BlockSize);
      Inc(LPHeapStatus.TotalCommitted, ABlockInfo.BlockSize);
      Inc(LPHeapStatus.TotalAllocated, ABlockInfo.UsableSize);
      Inc(LPHeapStatus.Overhead, ABlockInfo.BlockSize - ABlockInfo.UsableSize);
    end;

    btMediumBlockSpan:
    begin
      Inc(LPHeapStatus.TotalAddrSpace, ABlockInfo.BlockSize);
      Inc(LPHeapStatus.TotalCommitted, ABlockInfo.BlockSize);
      Inc(LPHeapStatus.Overhead, ABlockInfo.BlockSize);
      if ABlockInfo.IsSequentialFeedMediumBlockSpan then
      begin
        Inc(LPHeapStatus.Unused, ABlockInfo.MediumBlockSequentialFeedSpanUnusedBytes);
        Dec(LPHeapStatus.Overhead, ABlockInfo.MediumBlockSequentialFeedSpanUnusedBytes);
      end;
    end;

    btMediumBlock:
    begin
      Dec(LPHeapStatus.Overhead, ABlockInfo.UsableSize);
      if ABlockInfo.BlockIsFree then
        Inc(LPHeapStatus.FreeBig, ABlockInfo.UsableSize)
      else
        Inc(LPHeapStatus.TotalAllocated, ABlockInfo.UsableSize);
    end;

    btSmallBlockSpan:
    begin
      if ABlockInfo.IsSequentialFeedSmallBlockSpan then
      begin
        Inc(LPHeapStatus.Unused, ABlockInfo.SmallBlockSequentialFeedSpanUnusedBytes);
        Dec(LPHeapStatus.Overhead, ABlockInfo.SmallBlockSequentialFeedSpanUnusedBytes);
      end;
    end;

    btSmallBlock:
    begin
      Dec(LPHeapStatus.Overhead, ABlockInfo.UsableSize);
      if ABlockInfo.BlockIsFree then
        Inc(LPHeapStatus.FreeSmall, ABlockInfo.UsableSize)
      else
        Inc(LPHeapStatus.TotalAllocated, ABlockInfo.UsableSize);
    end;

  end;
end;

{Returns a THeapStatus structure with information about the current memory usage.}
function FastMM_GetHeapStatus: THeapStatus;
begin
  Result := Default(THeapStatus);

  FastMM_WalkBlocks(FastMM_GetHeapStatus_CallBack,
    [btLargeBlock, btMediumBlockSpan, btMediumBlock, btSmallBlockSpan, btSmallBlock], False, @Result);

  Result.TotalFree := Result.FreeSmall + Result.FreeBig + Result.Unused;
end;

{Returns True if there are live pointers using this memory manager.}
function FastMM_HasLivePointers: Boolean;
var
  i: Integer;
  LPMediumBlockManager: PMediumBlockManager;
  LPLargeBlockManager: PLargeBlockManager;
begin
  for i := 0 to CMediumBlockArenaCount - 1 do
  begin
    LPMediumBlockManager := @MediumBlockArenas[i];
    if NativeUInt(LPMediumBlockManager.FirstMediumBlockSpanHeader) <> NativeUInt(LPMediumBlockManager) then
      Exit(True);
  end;

  for i := 0 to CLargeBlockArenaCount - 1 do
  begin
    LPLargeBlockManager := @LargeBlockArenas[i];
    if NativeUInt(LPLargeBlockManager.FirstLargeBlockHeader) <> NativeUInt(LPLargeBlockManager) then
      Exit(True);
  end;

  Result := False;
end;

{Returns True if external code has changed the installed memory manager.}
function FastMM_InstalledMemoryManagerChangedExternally: Boolean;
var
  LCurrentMemoryManager: TMemoryManagerEx;
begin
  GetMemoryManager(LCurrentMemoryManager);
  Result := (@LCurrentMemoryManager.GetMem <> @InstalledMemoryManager.GetMem)
    or (@LCurrentMemoryManager.FreeMem <> @InstalledMemoryManager.FreeMem)
    or (@LCurrentMemoryManager.ReallocMem <> @InstalledMemoryManager.ReallocMem)
    or (@LCurrentMemoryManager.AllocMem <> @InstalledMemoryManager.AllocMem)
    or (@LCurrentMemoryManager.RegisterExpectedMemoryLeak <> @InstalledMemoryManager.RegisterExpectedMemoryLeak)
    or (@LCurrentMemoryManager.UnregisterExpectedMemoryLeak <> @InstalledMemoryManager.UnregisterExpectedMemoryLeak);
end;

{--------------------------------------------------------}
{----------------Memory Manager Sharing------------------}
{--------------------------------------------------------}

{Generates a string identifying the process}
procedure FastMM_BuildFileMappingObjectName;
var
  i, LProcessID: Cardinal;
begin
  LProcessID := GetCurrentProcessId;
  for i := 0 to 7 do
  begin
    SharingFileMappingObjectName[(High(SharingFileMappingObjectName) - 1) - i] :=
      AnsiChar(CHexDigits[((LProcessID shr (i * 4)) and $F)]);
  end;
end;

{Searches the current process for a shared memory manager}
function FastMM_FindSharedMemoryManager: PMemoryManagerEx;
var
  LPMapAddress: Pointer;
  LLocalMappingObjectHandle: NativeUInt;
begin
  {Try to open the shared memory manager file mapping}
  LLocalMappingObjectHandle := OpenFileMappingA(FILE_MAP_READ, False, SharingFileMappingObjectName);
  {Is a memory manager in this process sharing its memory manager?}
  if LLocalMappingObjectHandle = 0 then
  begin
    {There is no shared memory manager in the process.}
    Result := nil;
  end
  else
  begin
    {Map a view of the shared memory and get the address of the shared memory manager}
    LPMapAddress := MapViewOfFile(LLocalMappingObjectHandle, FILE_MAP_READ, 0, 0, 0);
    Result := PPointer(LPMapAddress)^;
    UnmapViewOfFile(LPMapAddress);
    CloseHandle(LLocalMappingObjectHandle);
  end;
end;

{Searches the current process for a shared memory manager.  If no memory has been allocated using this memory manager
it will switch to using the shared memory manager instead.  Returns True if another memory manager was found and it
could be shared.  If this memory manager instance *is* the shared memory manager, it will do nothing and return True.}
function FastMM_AttemptToUseSharedMemoryManager: Boolean;
const
  CTokenBufferSize = 65536;
var
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize - 1] of WideChar;
  LPMemoryManagerEx: PMemoryManagerEx;
begin
  if CurrentInstallationState = mmisInstalled then
  begin
    {Is this MM being shared?  If so, switching to another MM is not allowed}
    if SharingFileMappingObjectHandle = 0 then
    begin
      {May not switch memory manager after memory has been allocated}
      if not FastMM_HasLivePointers then
      begin
        LPMemoryManagerEx := FastMM_FindSharedMemoryManager;
        if LPMemoryManagerEx <> nil then
        begin

          InstalledMemoryManager := LPMemoryManagerEx^;
          SetMemoryManager(InstalledMemoryManager);
          CurrentInstallationState := mmisUsingSharedMemoryManager;

          {Free the address space slack, since it will not be needed.}
          ReleaseEmergencyReserveAddressSpace;

          Result := True;
        end
        else
          Result := False;
      end
      else
      begin
        {Memory has already been allocated using this memory manager.  We cannot rip the memory manager out from under
        live pointers.}

        LTokenValues := Default(TEventLogTokenValues);
        AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, @LTokenValueBuffer[High(LTokenValueBuffer)]);
        LogEvent(mmetCannotSwitchToSharedMemoryManagerWithLivePointers, LTokenValues);

        Result := False;
      end;
    end
    else
    begin
      {This memory manager is being shared, and an attempt is being made by the application to use the shared memory
      manager (which is this one):  Don't do anything and return success.  (This situation can occur when using
      SimpleShareMem in a DLL together with runtime packages.)}
      Result := True;
    end;
  end
  else
  begin
    {Another memory manager has already been installed.}
    Result := False;
  end;
end;

{Starts sharing this memory manager with other modules in the current process.  Only one memory manager may be shared
per process, so this function may fail.}
function FastMM_ShareMemoryManager: Boolean;
var
  LPMapAddress: Pointer;
begin
  if (CurrentInstallationState = mmisInstalled)
    and (not FastMM_InstalledMemoryManagerChangedExternally)
    and (SharingFileMappingObjectHandle = 0) then
  begin
    {Is any other module already sharing its MM?}
    if FastMM_FindSharedMemoryManager = nil then
    begin
      {Create the memory mapped file}
      SharingFileMappingObjectHandle := CreateFileMappingA(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0,
        SizeOf(Pointer), SharingFileMappingObjectName);
      {Map a view of the memory}
      LPMapAddress := MapViewOfFile(SharingFileMappingObjectHandle, FILE_MAP_WRITE, 0, 0, 0);
      {Set a pointer to the new memory manager}
      PPointer(LPMapAddress)^ := @InstalledMemoryManager;
      {Unmap the file}
      UnmapViewOfFile(LPMapAddress);
      {Sharing this MM}
      Result := True;
    end
    else
    begin
      {Another module is already sharing its memory manager}
      Result := False;
    end;
  end
  else
  begin
    {Either another memory manager has been set or this memory manager is
     already being shared}
    Result := False;
  end;
end;


{--------------------------------------------------}
{-------------Memory leak registration----------------}
{--------------------------------------------------}

{Adds a leak to the specified list}
function UpdateExpectedLeakList(APLeakList: PPExpectedMemoryLeak; APNewEntry: PExpectedMemoryLeak;
  AExactSizeMatch: Boolean = True): Boolean;
var
  LPInsertAfter, LPNewEntry: PExpectedMemoryLeak;
begin
  {Default to error}
  Result := False;

  {Find the insertion spot}
  LPInsertAfter := APLeakList^;
  while LPInsertAfter <> nil do
  begin
    {Too big?}
    if LPInsertAfter.LeakSize > APNewEntry.LeakSize then
    begin
      LPInsertAfter := LPInsertAfter.PreviousLeak;
      Break;
    end;
    {Find a matching entry.  If an exact size match is not required and the leak is larger than the current entry, use
    it if the expected size of the next entry is too large.}
    if (LPInsertAfter.LeakAddress = APNewEntry.LeakAddress)
      and ((LPInsertAfter.LeakedClass = APNewEntry.LeakedClass))
      and ((LPInsertAfter.LeakSize = APNewEntry.LeakSize)
        or ((not AExactSizeMatch)
          and (LPInsertAfter.LeakSize < APNewEntry.LeakSize)
          and ((LPInsertAfter.NextLeak = nil)
            or (LPInsertAfter.NextLeak.LeakSize > APNewEntry.LeakSize))
          )) then
    begin
      if (LPInsertAfter.LeakCount + APNewEntry.LeakCount) >= 0 then
      begin
        Inc(LPInsertAfter.LeakCount, APNewEntry.LeakCount);
        {Is the count now 0?}
        if LPInsertAfter.LeakCount = 0 then
        begin
          {Delete the entry}
          if LPInsertAfter.NextLeak <> nil then
            LPInsertAfter.NextLeak.PreviousLeak := LPInsertAfter.PreviousLeak;
          if LPInsertAfter.PreviousLeak <> nil then
            LPInsertAfter.PreviousLeak.NextLeak := LPInsertAfter.NextLeak
          else
            APLeakList^ := LPInsertAfter.NextLeak;
          {Insert it as the first free slot}
          LPInsertAfter.NextLeak := ExpectedMemoryLeaks.FirstFreeSlot;
          ExpectedMemoryLeaks.FirstFreeSlot := LPInsertAfter;
        end;
        Result := True;
      end;
      Exit;
    end;
    {Next entry}
    if LPInsertAfter.NextLeak <> nil then
      LPInsertAfter := LPInsertAfter.NextLeak
    else
      Break;
  end;
  if APNewEntry.LeakCount > 0 then
  begin
    {Get a position for the entry}
    LPNewEntry := ExpectedMemoryLeaks.FirstFreeSlot;
    if LPNewEntry <> nil then
    begin
      ExpectedMemoryLeaks.FirstFreeSlot := LPNewEntry.NextLeak;
    end
    else
    begin
      if ExpectedMemoryLeaks.EntriesUsed < Length(ExpectedMemoryLeaks.ExpectedLeaks) then
      begin
        LPNewEntry := @ExpectedMemoryLeaks.ExpectedLeaks[ExpectedMemoryLeaks.EntriesUsed];
        Inc(ExpectedMemoryLeaks.EntriesUsed);
      end
      else
      begin
        {No more space}
        Exit;
      end;
    end;
    {Set the entry}
    LPNewEntry^ := APNewEntry^;
    {Insert it into the list}
    LPNewEntry.PreviousLeak := LPInsertAfter;
    if LPInsertAfter <> nil then
    begin
      LPNewEntry.NextLeak := LPInsertAfter.NextLeak;
      if LPNewEntry.NextLeak <> nil then
        LPNewEntry.NextLeak.PreviousLeak := LPNewEntry;
      LPInsertAfter.NextLeak := LPNewEntry;
    end
    else
    begin
      LPNewEntry.NextLeak := APLeakList^;
      if LPNewEntry.NextLeak <> nil then
        LPNewEntry.NextLeak.PreviousLeak := LPNewEntry;
      APLeakList^ := LPNewEntry;
    end;
    Result := True;
  end;
end;

{Locks the expected leaks.  Returns False if the list could not be allocated.}
function LockExpectedMemoryLeaksList: Boolean;
begin
  {Lock the expected leaks list}
  while True do
  begin
    if AtomicCmpExchange(ExpectedMemoryLeaksListLocked, 1, 0) = 0 then
      Break;
  end;

  {Allocate the list if it does not exist}
  if ExpectedMemoryLeaks = nil then
    ExpectedMemoryLeaks := OS_AllocateVirtualMemory(CExpectedMemoryLeaksListSize, False, False);

  Result := ExpectedMemoryLeaks <> nil;
end;

{Registers expected memory leaks.  Returns True on success.  The list of leaked blocks is limited, so failure is
possible if the list is full.}
function FastMM_RegisterExpectedMemoryLeak(ALeakedPointer: Pointer): Boolean; overload;
var
  LNewEntry: TExpectedMemoryLeak;
begin
  {Fill out the structure}
  LNewEntry.LeakAddress := ALeakedPointer;
  LNewEntry.LeakedClass := nil;
  LNewEntry.LeakSize := 0;
  LNewEntry.LeakCount := 1;
  {Add it to the correct list}
  Result := LockExpectedMemoryLeaksList
    and UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryByAddress, @LNewEntry);
  ExpectedMemoryLeaksListLocked := 0;
end;

function FastMM_RegisterExpectedMemoryLeak(ALeakedObjectClass: TClass; ACount: Integer = 1): Boolean; overload;
var
  LNewEntry: TExpectedMemoryLeak;
begin
  {Fill out the structure}
  LNewEntry.LeakAddress := nil;
  LNewEntry.LeakedClass := ALeakedObjectClass;
  LNewEntry.LeakSize := ALeakedObjectClass.InstanceSize;
  LNewEntry.LeakCount := ACount;
  {Add it to the correct list}
  Result := LockExpectedMemoryLeaksList
    and UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryByClass, @LNewEntry);
  ExpectedMemoryLeaksListLocked := 0;
end;

function FastMM_RegisterExpectedMemoryLeak(ALeakedBlockSize: NativeInt; ACount: Integer = 1): Boolean; overload;
var
  LNewEntry: TExpectedMemoryLeak;
begin
  {Fill out the structure}
  LNewEntry.LeakAddress := nil;
  LNewEntry.LeakedClass := nil;
  LNewEntry.LeakSize := ALeakedBlockSize;
  LNewEntry.LeakCount := ACount;
  {Add it to the correct list}
  Result := LockExpectedMemoryLeaksList
    and UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryBySizeOnly, @LNewEntry);
  ExpectedMemoryLeaksListLocked := 0;
end;

function FastMM_UnregisterExpectedMemoryLeak(ALeakedPointer: Pointer): Boolean; overload;
var
  LNewEntry: TExpectedMemoryLeak;
begin
  {Fill out the structure}
  LNewEntry.LeakAddress := ALeakedPointer;
  LNewEntry.LeakedClass := nil;
  LNewEntry.LeakSize := 0;
  LNewEntry.LeakCount := -1;
  {Remove it from the list}
  Result := LockExpectedMemoryLeaksList
    and UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryByAddress, @LNewEntry);
  ExpectedMemoryLeaksListLocked := 0;
end;

function FastMM_UnregisterExpectedMemoryLeak(ALeakedObjectClass: TClass; ACount: Integer = 1): Boolean; overload;
begin
  Result := FastMM_RegisterExpectedMemoryLeak(ALeakedObjectClass, -ACount);
end;

function FastMM_UnregisterExpectedMemoryLeak(ALeakedBlockSize: NativeInt; ACount: Integer = 1): Boolean; overload;
begin
  Result := FastMM_RegisterExpectedMemoryLeak(ALeakedBlockSize, -ACount);
end;

{Returns a list of all expected memory leaks}
function FastMM_GetRegisteredMemoryLeaks: TFastMM_RegisteredMemoryLeaks;

  procedure AddEntries(AEntry: PExpectedMemoryLeak);
  var
    LInd: Integer;
  begin
    while AEntry <> nil do
    begin
      LInd := Length(Result);
      SetLength(Result, LInd + 1);
      {Add the entry}
      Result[LInd].LeakAddress := AEntry.LeakAddress;
      Result[LInd].LeakedClass := AEntry.LeakedClass;
      Result[LInd].LeakSize := AEntry.LeakSize;
      Result[LInd].LeakCount := AEntry.LeakCount;
      {Next entry}
      AEntry := AEntry.NextLeak;
    end;
  end;

begin
  SetLength(Result, 0);
  if (ExpectedMemoryLeaks <> nil) and LockExpectedMemoryLeaksList then
  begin
    {Add all entries}
    AddEntries(ExpectedMemoryLeaks.FirstEntryByAddress);
    AddEntries(ExpectedMemoryLeaks.FirstEntryByClass);
    AddEntries(ExpectedMemoryLeaks.FirstEntryBySizeOnly);
    {Unlock the list}
    ExpectedMemoryLeaksListLocked := 0;
  end;
end;


{--------------------------------------------------}
{-------------Memory leak reporting----------------}
{--------------------------------------------------}

{Tries to account for a memory leak.  If the block is an expected leak then it is removed from the list of leaks and
the leak type is returned.}
function FastMM_PerformMemoryLeakCheck_DetectLeakType(AAddress: Pointer; ASpaceInsideBlock: NativeUInt): TMemoryLeakType;
var
  LLeak: TExpectedMemoryLeak;
begin
  Result := mltUnexpectedLeak;

  if ExpectedMemoryLeaks <> nil then
  begin
    {Check by pointer address}
    LLeak.LeakAddress := AAddress;
    LLeak.LeakedClass := nil;
    LLeak.LeakSize := 0;
    LLeak.LeakCount := -1;
    if UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryByAddress, @LLeak, False) then
    begin
      Result := mltExpectedLeakRegisteredByPointer;
      Exit;
    end;

    {Check by class}
    LLeak.LeakAddress := nil;
    LLeak.LeakedClass := TClass(PNativeUInt(AAddress)^);
    LLeak.LeakSize := ASpaceInsideBlock;
    if UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryByClass, @LLeak, False) then
    begin
      Result := mltExpectedLeakRegisteredByClass;
      Exit;
    end;

    {Check by size:  The block must be large enough to hold the leak}
    LLeak.LeakedClass := nil;
    if UpdateExpectedLeakList(@ExpectedMemoryLeaks.FirstEntryBySizeOnly, @LLeak, False) then
      Result := mltExpectedLeakRegisteredBySize;
  end;
end;

procedure FastMM_PerformMemoryLeakCheck_AddBlockToLeakSummary(APLeakSummary: PMemoryLeakSummary;
  ABlockUsableSize: NativeInt; ABlockContentType: NativeUInt);
var
  LPSummaryEntry: PMemoryLeakSummaryEntry;
  LChildDirection: Boolean;
  i: Integer;
begin
  {If there's no space to add another entry then we need to abort in order to avoid a potential buffer overrun.}
  if APLeakSummary.LeakCount >= Length(APLeakSummary.MemoryLeakEntries) then
    Exit;

  {Try to find the block type in the list.}
  i := 0;
  if APLeakSummary.LeakCount > 0 then
  begin
    while True do
    begin
      LPSummaryEntry := @APLeakSummary.MemoryLeakEntries[i];

      if ABlockUsableSize <> LPSummaryEntry.BlockUsableSize then
      begin
        LChildDirection := ABlockUsableSize > LPSummaryEntry.BlockUsableSize;
      end
      else if ABlockContentType <> LPSummaryEntry.BlockContentType then
      begin
        LChildDirection := ABlockContentType > LPSummaryEntry.BlockContentType;
      end
      else
      begin
        {Found the leak type:  Bump the count.}
        Inc(LPSummaryEntry.NumLeaks);
        Exit;
      end;

      {Navigate in the correct direction, stopping if the end of the tree has been reached.}
      i := LPSummaryEntry.ChildIndexes[LChildDirection];
      if i = 0 then
      begin
        LPSummaryEntry.ChildIndexes[LChildDirection] := APLeakSummary.LeakCount;
        Break;
      end;
    end;
  end;

  {Need to add the block type.}
  LPSummaryEntry := @APLeakSummary.MemoryLeakEntries[APLeakSummary.LeakCount];
  LPSummaryEntry.BlockUsableSize := ABlockUsableSize;
  LPSummaryEntry.BlockContentType := ABlockContentType;
  LPSummaryEntry.NumLeaks := 1;
  LPSummaryEntry.ChildIndexes[False] := 0;
  LPSummaryEntry.ChildIndexes[True] := 0;

  Inc(APLeakSummary.LeakCount);
end;

procedure FastMM_PerformMemoryLeakCheck_CallBack(const ABlockInfo: TFastMM_WalkAllocatedBlocks_BlockInfo);
const
  CTokenBufferSize = 65536;
var
  LPLeakSummary: PMemoryLeakSummary;
  LBlockContentType: NativeUInt;
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize - 1] of WideChar;
  LPBufferPos, LPBufferEnd: PWideChar;
begin
  LPLeakSummary := ABlockInfo.UserData;

  {Is this an expected memory leak?  If so, ignore it.}
  if FastMM_PerformMemoryLeakCheck_DetectLeakType(ABlockInfo.BlockAddress, ABlockInfo.UsableSize) <> mltUnexpectedLeak then
    Exit;

  {If individual leaks must be reported, report the leak now.}
  if mmetUnexpectedMemoryLeakDetail in (FastMM_OutputDebugStringEvents + FastMM_LogToFileEvents + FastMM_MessageBoxEvents) then
  begin
    LTokenValues := Default(TEventLogTokenValues);

    LPBufferEnd := @LTokenValueBuffer[High(LTokenValueBuffer)];
    LPBufferPos := AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, LPBufferEnd);
    AddTokenValues_BlockTokens(LTokenValues, ABlockInfo.BlockAddress, LPBufferPos, LPBufferEnd);

    LogEvent(mmetUnexpectedMemoryLeakDetail, LTokenValues);
  end;

  {Add the block to the memory leak summary.}
  LBlockContentType := DetectBlockContentType(ABlockInfo.BlockAddress, ABlockInfo.UsableSize);
  FastMM_PerformMemoryLeakCheck_AddBlockToLeakSummary(LPLeakSummary, ABlockInfo.UsableSize, LBlockContentType);
end;

procedure FastMM_PerformMemoryLeakCheck_SortNodes(var ALeakSummary: TMemoryLeakSummary);
var
  LCurrentIndex, LInsertionIndex: Integer;
  LCurEntry: TMemoryLeakSummaryEntry;
begin
  {Performs an insertion sort.  After the sort the left and right child indexes will no longer be valid.}
  for LCurrentIndex := 1 to ALeakSummary.LeakCount - 1 do
  begin
    LCurEntry := ALeakSummary.MemoryLeakEntries[LCurrentIndex];

    LInsertionIndex := LCurrentIndex;
    while LInsertionIndex > 0 do
    begin
      if ALeakSummary.MemoryLeakEntries[LInsertionIndex - 1].BlockUsableSize < LCurEntry.BlockUsableSize then
        Break;

      if (ALeakSummary.MemoryLeakEntries[LInsertionIndex - 1].BlockUsableSize = LCurEntry.BlockUsableSize)
        and (ALeakSummary.MemoryLeakEntries[LInsertionIndex - 1].BlockContentType > LCurEntry.BlockContentType) then
      begin
        Break;
      end;

      ALeakSummary.MemoryLeakEntries[LInsertionIndex] := ALeakSummary.MemoryLeakEntries[LInsertionIndex - 1];
      Dec(LInsertionIndex);
    end;

    ALeakSummary.MemoryLeakEntries[LInsertionIndex] := LCurEntry;
  end;
end;

procedure FastMM_PerformMemoryLeakCheck_LogLeakSummary(var ALeakSummary: TMemoryLeakSummary);
const
  CLeakTextMaxSize = 32768;
  CLifeFeed = #13#10;
  CLeakSizeSuffix = ': ';
  CLeakSeparator = ', ';
  CLeakMultiple = ' x ';
var
  LCurrentLeakSize: NativeInt;
  LLeakIndex: Integer;
  LLeakEntriesText, LTokenValueBuffer: array[0..CLeakTextMaxSize] of WideChar;
  LPBufferPos, LPBufferEnd, LPTokenBufferPos: PWideChar;
  LTokenValues: TEventLogTokenValues;
begin
  {Sort the leaks in ascending size and descending type order.}
  FastMM_PerformMemoryLeakCheck_SortNodes(ALeakSummary);

  {Build the leak summary entries text:  Walk the blocks from small to large, grouping leaks of the same size.}
  LCurrentLeakSize := -1;
  LPBufferPos := @LLeakEntriesText;
  LPBufferEnd := @LLeakEntriesText[High(LLeakEntriesText)];
  for LLeakIndex := 0 to ALeakSummary.LeakCount - 1 do
  begin

    {Did the leak size change?  If so, add a new line.}
    if ALeakSummary.MemoryLeakEntries[LLeakIndex].BlockUsableSize <> LCurrentLeakSize then
    begin
      LCurrentLeakSize := ALeakSummary.MemoryLeakEntries[LLeakIndex].BlockUsableSize;

      LPBufferPos := AppendTextToBuffer(CLifeFeed, Length(CLifeFeed), LPBufferPos, LPBufferEnd);
      LPBufferPos := NativeIntToTextBuffer(LCurrentLeakSize, LPBufferPos, LPBufferEnd);
      LPBufferPos := AppendTextToBuffer(CLeakSizeSuffix, Length(CLeakSizeSuffix), LPBufferPos, LPBufferEnd);
    end
    else
    begin
      LPBufferPos := AppendTextToBuffer(CLeakSeparator, Length(CLeakSeparator), LPBufferPos, LPBufferEnd);
    end;

    LPBufferPos := NativeIntToTextBuffer(ALeakSummary.MemoryLeakEntries[LLeakIndex].NumLeaks, LPBufferPos, LPBufferEnd);
    LPBufferPos := AppendTextToBuffer(CLeakMultiple, Length(CLeakMultiple), LPBufferPos, LPBufferEnd);
    LPBufferPos := BlockContentTypeToTextBuffer(ALeakSummary.MemoryLeakEntries[LLeakIndex].BlockContentType, LPBufferPos, LPBufferEnd);
  end;

  {Build the token dictionary for the leak summary.}
  LTokenValues := Default(TEventLogTokenValues);
  LPTokenBufferPos := AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer,
    @LTokenValueBuffer[High(LTokenValueBuffer)]);
  AddTokenValue(LTokenValues, CEventLogTokenLeakSummaryEntries, @LLeakEntriesText,
    CharCount(LPBufferPos, @LLeakEntriesText), LPTokenBufferPos, @LTokenValueBuffer[High(LTokenValueBuffer)]);

  LogEvent(mmetUnexpectedMemoryLeakSummary, LTokenValues);
end;

procedure FastMM_PerformMemoryLeakCheck;
var
  LLeakSummary: TMemoryLeakSummary;
begin
  LLeakSummary := Default(TMemoryLeakSummary);

  FastMM_WalkBlocks(FastMM_PerformMemoryLeakCheck_CallBack, [btLargeBlock, btMediumBlock, btSmallBlock], True,
    @LLeakSummary);

  {Build the leak summary by walking all the block categories.}
  if (LLeakSummary.LeakCount > 0)
    and (mmetUnexpectedMemoryLeakSummary in (FastMM_OutputDebugStringEvents + FastMM_LogToFileEvents + FastMM_MessageBoxEvents)) then
  begin
    FastMM_PerformMemoryLeakCheck_LogLeakSummary(LLeakSummary);
  end;
end;


{--------------------------------------------------------}
{-------------Initialization/installation----------------}
{--------------------------------------------------------}

procedure FastMM_SetOptimizationStrategy(AStrategy: TFastMM_MemoryManagerOptimizationStrategy);
begin
  OptimizationStrategy := AStrategy;

  case AStrategy of

    mmosOptimizeForSpeed:
    begin
      DefaultMediumBlockSpanSize := 4 * 1024 * 1024;
    end;

    mmosOptimizeForLowMemoryUsage:
    begin
      DefaultMediumBlockSpanSize := 1024 * 1024 * 3 div 2;
    end;

  else
    begin
      DefaultMediumBlockSpanSize := 3 * 1024 * 1024;
    end;

  end;
end;

function FastMM_GetCurrentOptimizationStrategy: TFastMM_MemoryManagerOptimizationStrategy;
begin
  Result := OptimizationStrategy;
end;

{Returns the current minimum address alignment in effect.}
function FastMM_GetCurrentMinimumAddressAlignment: TFastMM_MinimumAddressAlignment;
begin
  if AlignmentRequestCounters[maa64Bytes] > 0 then
    Result := maa64Bytes
  else if AlignmentRequestCounters[maa32Bytes] > 0 then
    Result := maa32Bytes
  else if (SizeOf(Pointer) = 8) or (AlignmentRequestCounters[maa16Bytes] > 0) then
    Result := maa16Bytes
  else
    Result := maa8Bytes;
end;

{Builds the lookup table used for translating a small block allocation request size to a small block type.}
procedure FastMM_BuildSmallBlockTypeLookupTable;
var
  LBlockTypeInd, LStartIndex, LNextStartIndex, LAndValue: Integer;
begin
  {Determine the allowed small block alignments.  Under 64-bit the minimum alignment is always 16 bytes.}
  if AlignmentRequestCounters[maa64Bytes] > 0 then
    LAndValue := 63
  else if AlignmentRequestCounters[maa32Bytes] > 0 then
    LAndValue := 31
  else if (SizeOf(Pointer) = 8) or (AlignmentRequestCounters[maa16Bytes] > 0) then
    LAndValue := 15
  else
    LAndValue := 0;

  LStartIndex := 0;
  for LBlockTypeInd := 0 to High(CSmallBlockTypeInfo) do
  begin
    {Is this a valid block type for the alignment restriction?}
    if CSmallBlockTypeInfo[LBlockTypeInd].BlockSize and LAndValue = 0 then
    begin
      LNextStartIndex := CSmallBlockTypeInfo[LBlockTypeInd].BlockSize div CSmallBlockGranularity;
      {Store the block type index in the appropriate slots.}
      while LStartIndex < LNextStartIndex do
      begin
        SmallBlockTypeLookup[LStartIndex] := LBlockTypeInd;
        Inc(LStartIndex);
      end;
      {Set the start of the next block type}
      LStartIndex := LNextStartIndex;
    end;
  end;
end;

procedure FastMM_EnterMinimumAddressAlignment(AMinimumAddressAlignment: TFastMM_MinimumAddressAlignment);
var
  LOldMinimumAlignment: TFastMM_MinimumAddressAlignment;
begin
  LOldMinimumAlignment := FastMM_GetCurrentMinimumAddressAlignment;
  AtomicIncrement(AlignmentRequestCounters[AMinimumAddressAlignment]);

  {Rebuild the small block type lookup table if the minimum alignment changed.}
  if LOldMinimumAlignment <> FastMM_GetCurrentMinimumAddressAlignment then
    FastMM_BuildSmallBlockTypeLookupTable;
end;

procedure FastMM_ExitMinimumAddressAlignment(AMinimumAddressAlignment: TFastMM_MinimumAddressAlignment);
var
  LOldMinimumAlignment: TFastMM_MinimumAddressAlignment;
begin
  LOldMinimumAlignment := FastMM_GetCurrentMinimumAddressAlignment;
  AtomicDecrement(AlignmentRequestCounters[AMinimumAddressAlignment]);

  {Rebuild the small block type lookup table if the minimum alignment changed.}
  if LOldMinimumAlignment <> FastMM_GetCurrentMinimumAddressAlignment then
    FastMM_BuildSmallBlockTypeLookupTable;
end;

procedure FastMM_InitializeMemoryManager;
var
  LBlockTypeInd, LArenaInd, LMinimumSmallBlockSpanSize, LBinInd, LOptimalSmallBlockSpanSize, LBlocksPerSpan: Integer;
  LPSmallBlockTypeInfo: PSmallBlockTypeInfo;
  LPSmallBlockManager: PSmallBlockManager;
  LPMediumBlockManager: PMediumBlockManager;
  LPLargeBlockManager: PLargeBlockManager;
  LPBin: PPointer;
begin
  Assert(CSmallBlockHeaderSize = 2);
  Assert(CMediumBlockHeaderSize = 8);

  {Large blocks must be 64 byte aligned}
  Assert(CLargeBlockHeaderSize = 64);

  {In order to ensure minimum alignment is always honoured the debug block header must be a multiple of 64.}
  Assert(CDebugBlockHeaderSize and 63 = 0);

  {Span headers have to be a multiple of 64 bytes in order to ensure that 64-byte alignment of user data is possible.}
  Assert(CMediumBlockSpanHeaderSize = 64);
  Assert(CSmallBlockSpanHeaderSize = 64);

  Assert(CSmallBlockManagerSize = 64);

  FastMM_SetOptimizationStrategy(mmosBalanced);

  GetMemoryManager(PreviousMemoryManager);
  InstalledMemoryManager := PreviousMemoryManager;
  if IsMemoryManagerSet then
    CurrentInstallationState := mmisOtherThirdPartyMemoryManagerInstalled;

  {---------Small blocks-------}

  {Build the request size to small block type lookup table.}
  FastMM_BuildSmallBlockTypeLookupTable;

  {Initialize all the small block arenas}
  for LBlockTypeInd := 0 to CSmallBlockTypeCount - 1 do
  begin
    LPSmallBlockTypeInfo := @CSmallBlockTypeInfo[LBlockTypeInd];

    {The minimum useable small block span size.}
    LMinimumSmallBlockSpanSize := RoundUserSizeUpToNextMediumBlockBin(
      CMinimumSmallBlocksPerSpan * LPSmallBlockTypeInfo.BlockSize
      + (CSmallBlockSpanHeaderSize + CMediumBlockHeaderSize - CSmallBlockHeaderSize));
    if LMinimumSmallBlockSpanSize < CMinimumMediumBlockSize then
      LMinimumSmallBlockSpanSize := CMinimumMediumBlockSize;

    {The optimal small block span size is rounded so as to minimize wastage due to a partial last block.}
    LOptimalSmallBlockSpanSize := LPSmallBlockTypeInfo.BlockSize * COptimalSmallBlocksPerSpan;
    if LOptimalSmallBlockSpanSize < COptimalSmallBlockSpanSizeLowerLimit then
      LOptimalSmallBlockSpanSize := COptimalSmallBlockSpanSizeLowerLimit;
    if LOptimalSmallBlockSpanSize > COptimalSmallBlockSpanSizeUpperLimit then
      LOptimalSmallBlockSpanSize := COptimalSmallBlockSpanSizeUpperLimit;
    LBlocksPerSpan := LOptimalSmallBlockSpanSize div LPSmallBlockTypeInfo.BlockSize;
    LOptimalSmallBlockSpanSize := RoundUserSizeUpToNextMediumBlockBin(LBlocksPerSpan * LPSmallBlockTypeInfo.BlockSize
      + (CSmallBlockSpanHeaderSize + CMediumBlockHeaderSize - CSmallBlockHeaderSize));

    for LArenaInd := 0 to CSmallBlockArenaCount - 1 do
    begin
      LPSmallBlockManager := @SmallBlockArenas[LArenaInd, LBlockTypeInd];

      {The circular list is empty initially.}
      LPSmallBlockManager.FirstPartiallyFreeSpan := PSmallBlockSpanHeader(LPSmallBlockManager);
      LPSmallBlockManager.LastPartiallyFreeSpan := PSmallBlockSpanHeader(LPSmallBlockManager);

      LPSmallBlockManager.LastSequentialFeedBlockOffset.IntegerAndABACounter := 0; //superfluous
      LPSmallBlockManager.BlockSize := LPSmallBlockTypeInfo.BlockSize;
      LPSmallBlockManager.MinimumSpanSize := LMinimumSmallBlockSpanSize;
      LPSmallBlockManager.OptimalSpanSize := LOptimalSmallBlockSpanSize;

      if Assigned(LPSmallBlockTypeInfo.UpsizeMoveProcedure) then
        LPSmallBlockManager.UpsizeMoveProcedure := LPSmallBlockTypeInfo.UpsizeMoveProcedure
      else
        LPSmallBlockManager.UpsizeMoveProcedure := System.Move;

    end;
  end;

  {---------Medium blocks-------}
  for LArenaInd := 0 to CMediumBlockArenaCount - 1 do
  begin
    LPMediumBlockManager := @MediumBlockArenas[LArenaInd];

    {The circular list of spans is empty initially.}
    LPMediumBlockManager.FirstMediumBlockSpanHeader := PMediumBlockSpanHeader(LPMediumBlockManager);
    LPMediumBlockManager.LastMediumBlockSpanHeader := PMediumBlockSpanHeader(LPMediumBlockManager);

    {All the free block bins are empty.}
    for LBinInd := 0 to CMediumBlockBinCount - 1 do
    begin
      LPBin := @LPMediumBlockManager.FirstFreeBlockInBin[LBinInd];
      LPBin^ := LPBin;
    end;

  end;

  {---------Large blocks-------}

  {The circular list is empty initially.}
  for LArenaInd := 0 to CLargeBlockArenaCount - 1 do
  begin
    LPLargeBlockManager := @LargeBlockArenas[LArenaInd];

    LPLargeBlockManager.FirstLargeBlockHeader := PLargeBlockHeader(LPLargeBlockManager);
    LPLargeBlockManager.LastLargeBlockHeader := PLargeBlockHeader(LPLargeBlockManager)
  end;

  {---------Debug setup-------}
  {Reserve 64K starting at address $80800000.  $80808080 is the debug fill pattern under 32-bit, so we don't want any
  pointer dereferences at this address to succeed.  This is only necessary under 32-bit, since $8080808000000000 is
  already reserved for the OS under 64-bit.}
{$ifdef 32Bit}
  OS_AllocateVirtualMemoryAtAddress(Pointer($80800000), $10000, True);
{$endif}

  FastMM_GetStackTrace := @FastMM_NoOpGetStackTrace;
  FastMM_ConvertStackTraceToText := FastMM_NoOpConvertStackTraceToText;
  {The first time EnterDebugMode is called an attempt will be made to load the debug support DLL.}
  DebugSupportConfigured := False;

  FastMM_SetDefaultEventLogFileName;

  {---------Sharing setup-------}

  FastMM_BuildFileMappingObjectName;
end;

procedure FastMM_FreeAllMemory;
var
  LArenaIndex, LBinIndex, LBlockTypeIndex: Integer;
  LPMediumBlockManager: PMediumBlockManager;
  LPMediumBlockSpan, LPNextMediumBlockSpan: PMediumBlockSpanHeader;
  LPSmallBlockArena: PSmallBlockArena;
  LPSmallBlockManager: PSmallBlockManager;
  LPLargeBlockManager: PLargeBlockManager;
  LPLargeBlock, LPNextLargeBlock: PLargeBlockHeader;
begin
  {Free all medium block spans.}
  for LArenaIndex := 0 to CMediumBlockArenaCount - 1 do
  begin
    LPMediumBlockManager := @MediumBlockArenas[LArenaIndex];
    LPMediumBlockSpan := LPMediumBlockManager.FirstMediumBlockSpanHeader;
    while NativeUInt(LPMediumBlockSpan) <> NativeUInt(LPMediumBlockManager) do
    begin
      LPNextMediumBlockSpan := LPMediumBlockSpan.NextMediumBlockSpanHeader;
      OS_FreeVirtualMemory(LPMediumBlockSpan);
      LPMediumBlockSpan := LPNextMediumBlockSpan;
    end;

    LPMediumBlockManager.FirstMediumBlockSpanHeader := PMediumBlockSpanHeader(LPMediumBlockManager);
    LPMediumBlockManager.LastMediumBlockSpanHeader := PMediumBlockSpanHeader(LPMediumBlockManager);

    LPMediumBlockManager.MediumBlockBinGroupBitmap := 0;
    FilLChar(LPMediumBlockManager.MediumBlockBinBitmaps, SizeOf(LPMediumBlockManager.MediumBlockBinBitmaps), 0);
    for LBinIndex := 0 to CMediumBlockBinCount - 1 do
      LPMediumBlockManager.FirstFreeBlockInBin[LBinIndex] := @LPMediumBlockManager.FirstFreeBlockInBin[LBinIndex];
    LPMediumBlockManager.LastSequentialFeedBlockOffset.IntegerValue := 0;
    LPMediumBlockManager.SequentialFeedMediumBlockSpan := nil;
    LPMediumBlockManager.PendingFreeList := nil;
  end;

  {Clear all small block types}
  for LArenaIndex := 0 to High(SmallBlockArenas) do
  begin
    LPSmallBlockArena := @SmallBlockArenas[LArenaIndex];

    for LBlockTypeIndex := 0 to CSmallBlockTypeCount - 1 do
    begin
      LPSmallBlockManager := @LPSmallBlockArena[LBlockTypeIndex];
      LPSmallBlockManager.FirstPartiallyFreeSpan := PSmallBlockSpanHeader(LPSmallBlockManager);
      LPSmallBlockManager.LastPartiallyFreeSpan := PSmallBlockSpanHeader(LPSmallBlockManager);
      LPSmallBlockManager.LastSequentialFeedBlockOffset.IntegerValue := 0;
      LPSmallBlockManager.CurrentSequentialFeedSpan := nil;
      LPSmallBlockManager.PendingFreeList := nil;
    end;
  end;

  {Free all large blocks.}
  for LArenaIndex := 0 to CLargeBlockArenaCount - 1 do
  begin
    LPLargeBlockManager := @LargeBlockArenas[LArenaIndex];

    LPLargeBlock := LPLargeBlockManager.FirstLargeBlockHeader;
    while NativeUInt(LPLargeBlock) <> NativeUInt(LPLargeBlockManager) do
    begin
      LPNextLargeBlock := LPLargeBlock.NextLargeBlockHeader;
      FastMM_FreeMem_FreeLargeBlock_ReleaseVM(LPLargeBlock);
      LPLargeBlock := LPNextLargeBlock;
    end;

    LPLargeBlockManager.FirstLargeBlockHeader := PLargeBlockHeader(LPLargeBlockManager);
    LPLargeBlockManager.LastLargeBlockHeader := PLargeBlockHeader(LPLargeBlockManager);
  end;

end;

procedure FastMM_FinalizeMemoryManager;
begin
  ReleaseEmergencyReserveAddressSpace;

  if ExpectedMemoryLeaks <> nil then
  begin
    OS_FreeVirtualMemory(ExpectedMemoryLeaks);
    ExpectedMemoryLeaks := nil;
  end;

  FastMM_FreeDebugSupportLibrary;

  if SharingFileMappingObjectHandle <> 0 then
  begin
    CloseHandle(SharingFileMappingObjectHandle);
    SharingFileMappingObjectHandle := 0;
  end;

end;

{Returns True if FastMM was successfully installed.}
function FastMM_GetInstallationState: TFastMM_MemoryManagerInstallationState;
begin
  Result := CurrentInstallationState;
end;

function FastMM_SetNormalOrDebugMemoryManager: Boolean;
var
  LNewMemoryManager: TMemoryManagerEx;
begin
  {SetMemoryManager is not thread safe.}
  while True do
  begin
    if AtomicCmpExchange(SettingMemoryManager, 1, 0) = 0 then
      Break;
  end;

  {Check that the memory manager has not been changed since the last time it was set.}
  if FastMM_InstalledMemoryManagerChangedExternally then
  begin
    SettingMemoryManager := 0;
    Exit(False);
  end;

  {Debug mode or normal memory manager?}
  if DebugModeCounter <= 0 then
  begin
    LNewMemoryManager.GetMem := FastMM_GetMem;
    LNewMemoryManager.FreeMem := FastMM_FreeMem;
    LNewMemoryManager.ReallocMem := FastMM_ReallocMem;
    LNewMemoryManager.AllocMem := FastMM_AllocMem;
    LNewMemoryManager.RegisterExpectedMemoryLeak := FastMM_RegisterExpectedMemoryLeak;
    LNewMemoryManager.UnregisterExpectedMemoryLeak := FastMM_UnregisterExpectedMemoryLeak;
  end
  else
  begin
    LNewMemoryManager.GetMem := FastMM_DebugGetMem;
    LNewMemoryManager.FreeMem := FastMM_DebugFreeMem;
    LNewMemoryManager.ReallocMem := FastMM_DebugReallocMem;
    LNewMemoryManager.AllocMem := FastMM_DebugAllocMem;
    LNewMemoryManager.RegisterExpectedMemoryLeak := FastMM_RegisterExpectedMemoryLeak;
    LNewMemoryManager.UnregisterExpectedMemoryLeak := FastMM_UnregisterExpectedMemoryLeak;
  end;

  SetMemoryManager(LNewMemoryManager);
  InstalledMemoryManager := LNewMemoryManager;

  SettingMemoryManager := 0;

  Result := True;
end;

procedure FastMM_InstallMemoryManager;
const
  CTokenBufferSize = 2048;
var
  LTokenValues: TEventLogTokenValues;
  LTokenValueBuffer: array[0..CTokenBufferSize - 1] of WideChar;
begin
  {FastMM may only be installed if no other replacement memory manager has already been installed, and no memory has
  been allocated through the default memory manager.}
  if CurrentInstallationState <> mmisDefaultMemoryManagerInUse then
  begin
    LTokenValues := Default(TEventLogTokenValues);
    AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, @LTokenValueBuffer[High(LTokenValueBuffer)]);
    LogEvent(mmetAnotherThirdPartyMemoryManagerAlreadyInstalled, LTokenValues);

    Exit;
  end;

  if System.GetHeapStatus.TotalAllocated <> 0 then
  begin
    LTokenValues := Default(TEventLogTokenValues);
    AddTokenValues_GeneralTokens(LTokenValues, @LTokenValueBuffer, @LTokenValueBuffer[High(LTokenValueBuffer)]);
    LogEvent(mmetCannotInstallAfterDefaultMemoryManagerHasBeenUsed, LTokenValues);

    Exit;
  end;

  if FastMM_SetNormalOrDebugMemoryManager then
  begin
    CurrentInstallationState := mmisInstalled;

    EnsureEmergencyReserveAddressSpaceAllocated;
  end;
end;

procedure FastMM_UninstallMemoryManager;
begin
  if CurrentInstallationState in [mmisInstalled, mmisUsingSharedMemoryManager] then
  begin
    {Has another memory manager been installed by external code?  If so, it is not possible to uninstall.}
    if not FastMM_InstalledMemoryManagerChangedExternally then
    begin
      SetMemoryManager(PreviousMemoryManager);
      InstalledMemoryManager := PreviousMemoryManager;
      CurrentInstallationState := mmisDefaultMemoryManagerInUse;
    end;
  end;
end;

function FastMM_LoadDebugSupportLibrary: Boolean;
begin
  {Already loaded?  If so, return success.}
  if DebugSupportLibraryHandle <> 0 then
    Exit(True);

  DebugSupportLibraryHandle := LoadLibrary(FastMM_DebugSupportLibraryName);
  if DebugSupportLibraryHandle <> 0 then
  begin
    DebugLibrary_GetRawStackTrace := GetProcAddress(DebugSupportLibraryHandle, 'GetRawStackTrace');
    DebugLibrary_GetFrameBasedStackTrace := GetProcAddress(DebugSupportLibraryHandle, 'GetFrameBasedStackTrace');
    DebugLibrary_LogStackTrace_Legacy := GetProcAddress(DebugSupportLibraryHandle, 'LogStackTrace');

    {Try to use the stack trace routines from the debug support library, if available.}
    if (@FastMM_GetStackTrace = @FastMM_NoOpGetStackTrace)
      and Assigned(DebugLibrary_GetRawStackTrace) then
    begin
      FastMM_GetStackTrace := DebugLibrary_GetRawStackTrace;
    end;

    if (@FastMM_ConvertStackTraceToText = @FastMM_NoOpConvertStackTraceToText)
      and Assigned(DebugLibrary_LogStackTrace_Legacy) then
    begin
      FastMM_ConvertStackTraceToText := FastMM_DebugLibrary_LegacyLogStackTrace_Wrapper;
    end;

    Result := True;
  end
  else
    Result := False;
end;

function FastMM_FreeDebugSupportLibrary: Boolean;
begin
  if DebugSupportLibraryHandle = 0 then
    Exit(False);

  if (@FastMM_GetStackTrace = @DebugLibrary_GetRawStackTrace)
    or (@FastMM_GetStackTrace = @DebugLibrary_GetFrameBasedStackTrace) then
  begin
    FastMM_GetStackTrace := @FastMM_NoOpGetStackTrace;
  end;

  if @FastMM_ConvertStackTraceToText = @FastMM_DebugLibrary_LegacyLogStackTrace_Wrapper then
  begin
    FastMM_ConvertStackTraceToText := @FastMM_NoOpConvertStackTraceToText;
  end;

  FreeLibrary(DebugSupportLibraryHandle);
  DebugSupportLibraryHandle := 0;

  Result := True;
end;

procedure FastMM_ConfigureDebugMode;
begin
  {If both handlers have been assigned then we do not need to load the support DLL.}
  if (@FastMM_GetStackTrace = @FastMM_NoOpGetStackTrace)
    or (@FastMM_ConvertStackTraceToText = @FastMM_NoOpConvertStackTraceToText) then
  begin
    FastMM_LoadDebugSupportLibrary;
  end;

  DebugSupportConfigured := True;
end;

function FastMM_EnterDebugMode: Boolean;
begin
  if CurrentInstallationState = mmisInstalled then
  begin
    if AtomicIncrement(DebugModeCounter) = 1 then
    begin
      if not DebugSupportConfigured then
        FastMM_ConfigureDebugMode;

      Result := FastMM_SetNormalOrDebugMemoryManager
    end
    else
      Result := True;
  end
  else
    Result := False;
end;

function FastMM_ExitDebugMode: Boolean;
begin
  if CurrentInstallationState = mmisInstalled then
  begin
    if AtomicDecrement(DebugModeCounter) = 0 then
      Result := FastMM_SetNormalOrDebugMemoryManager
    else
      Result := True;
  end
  else
    Result := False;
end;

procedure FastMM_SetDefaultEventLogFileName(APathOverride: PWideChar);
const
  CLogFilePathEnvironmentVariable: PWideChar = 'FastMMLogFilePath';
  CLogFileExtension: PWideChar = '_MemoryManager_EventLog.txt';
var
  LPathOverrideBuffer, LFilenameBuffer: array[0..CFilenameMaxLength] of WideChar;
  LPBuffer, LPFilenameStart, LPFilenameEnd, LPBufferEnd: PWideChar;
begin
  {If no path override is specified then try to get it from the environment variable.}
  if APathOverride = nil then
  begin
    LPBuffer := OS_GetEnvironmentVariableValue(CLogFilePathEnvironmentVariable, @LPathOverrideBuffer,
      @LPathOverrideBuffer[High(LPathOverrideBuffer)]);
    LPBuffer^ := #0;
    if LPBuffer <> @LPathOverrideBuffer then
      APathOverride := @LPathOverrideBuffer;
  end;

  {Get the application path and name into a buffer.}
  LPBuffer := OS_GetApplicationFilename(False, @LFilenameBuffer, @LFilenameBuffer[High(LFilenameBuffer)]);
  LPBuffer^ := #0;

  {Drop the file extension from the filename.}
  LPFilenameEnd := LPBuffer;
  while NativeUInt(LPBuffer) > NativeUInt(@LFilenameBuffer) do
  begin
    if LPBuffer^ = '.' then
    begin
      LPFilenameEnd := LPBuffer;
      LPFilenameEnd^ := #0;
      Break;
    end;
    Dec(LPBuffer);
  end;

  {If there is path override find the start of the filename.}
  if APathOverride <> nil then
  begin
    LPFilenameStart := LPFilenameEnd;
    while NativeUInt(LPFilenameStart) > NativeUInt(@LFilenameBuffer) do
    begin
      if (LPFilenameStart^ = '\') or (LPFilenameStart^ = '/') then
        Break;
      Dec(LPFilenameStart);
    end;
  end
  else
    LPFilenameStart := @LFilenameBuffer;

  {Add the path override to the buffer.}
  LPBufferEnd := @DefaultEventLogFilename[High(DefaultEventLogFilename)];
  LPBuffer := AppendTextToBuffer(APathOverride, @DefaultEventLogFilename, LPBufferEnd);

  {Strip the trailing path separator for the path override.}
  if LPBuffer <> @DefaultEventLogFilename then
  begin
    Dec(LPBuffer);
    if (LPBuffer^ <> '\') and (LPBuffer^ <> '/') then
      Inc(LPBuffer);
  end;

  {Add the filename to the buffer, then the log file extension and file the #0 terminator.}
  LPBuffer := AppendTextToBuffer(LPFilenameStart, LPBuffer, LPBufferEnd);
  LPBuffer := AppendTextToBuffer(CLogFileExtension, LPBuffer, LPBufferEnd);
  LPBuffer^ := #0;

  FastMM_EventLogFilename := @DefaultEventLogFilename;
end;

initialization
  FastMM_InitializeMemoryManager;
  FastMM_InstallMemoryManager;

finalization

  {Prevent a potential crash when the finalization code in system.pas tries to free PreferredLanguagesOverride after
  FastMM has been uninstalled:  https://quality.embarcadero.com/browse/RSP-16796}
  if CurrentInstallationState = mmisInstalled then
    SetLocaleOverride('');

  {All pending frees must be released before we can do a leak check.}
  FastMM_ProcessAllPendingFrees;

  {Do a memory leak check if required.}
  if [mmetUnexpectedMemoryLeakDetail, mmetUnexpectedMemoryLeakSummary] * (FastMM_OutputDebugStringEvents + FastMM_LogToFileEvents + FastMM_MessageBoxEvents) <> [] then
    FastMM_PerformMemoryLeakCheck;

  FastMM_FinalizeMemoryManager;
  FastMM_UninstallMemoryManager;

  {Free all memory.  If this is a .DLL that owns its own MM, then it is necessary to prevent the main application from
  running out of address space.}
  FastMM_FreeAllMemory;

end.
