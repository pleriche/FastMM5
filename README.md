# FastMM5
A fast replacement memory manager for Embarcadero Delphi applications that scales well across multiple threads and CPU cores, is not prone to memory fragmentation, and supports shared memory without the use of external .DLL files.

### Developed by
Pierre le Riche

### Sponsored by
gs-soft AG

### Licence
FastMM 5 is dual-licensed.  You may choose to use it under the restrictions of the [GPL v3](https://www.gnu.org/licenses/gpl-3.0.en.html) licence at no cost to you, or you may purchase a commercial licence.  The commercial licence pricing is as follows:
Number Of Developers|Price (USD)
--------------------|-----------
1 developer|$99
2 developers|$189
3 developers|$269
4 developers|$339
5 developers|$399
More than 5 developers|$399 + $50 per developer from the 6th onwards

Once payment has been made at https://www.paypal.me/fastmm (paypal@leriche.org), please send an e-mail to fastmm@leriche.org for confirmation.  Support is available for users with a commercial licence via the same e-mail address.

### Usage Instructions
Add FastMM5.pas as the first unit in your project's DPR file.  It will install itself automatically during startup, replacing the default memory manager.

In order to share the memory manager between the main application and libraries call FastMM_AttemptToUseSharedMemoryManager (in order to use the memory manager of another module in the process) or FastMM_ShareMemoryManager (to share the memory manager instance of the current module with other modules).  It is important to share the memory manager between modules where memory allocated in the one module may be freed by the other.

If the application requires memory alignment greater than the default, call FastMM_EnterMinimumAddressAlignment and once the greater alignment is no longer required call FastMM_ExitMinimumAddressAlignment.  Calls may be nested.  The coarsest memory alignment requested takes precedence.

At the cost of performance and increased memory usage FastMM can log additional metadata together with every block.  In order to enable this mode call FastMM_EnterDebugMode and to exit debug mode call FastMM_ExitDebugMode.  Calls may be nested in which case debug mode will be active as long as the number of FastMM_EnterDebugMode calls exceed the number of FastMM_ExitDebugMode calls.  In debug mode freed memory blocks will be filled with the byte pattern $808080... so that usage of a freed memory block or object, as well as corruption of the block header and/or footer will likely be detected.  If the debug support library, FastMM_FullDebugMode.dll, is available and the application has not specified its own handlers for FastMM_GetStackTrace and FastMM_ConvertStackTraceToText then the support library will be loaded during the first call to FastMM_EnterDebugMode.

Events (memory leaks, errors, etc.) may be logged to file, displayed on-screen, passed to the debugger or any combination of the three.  Specify how each event should be handled via the FastMM_LogToFileEvents, FastMM_MessageBoxEvents and FastMM_OutputDebugStringEvents variables.  The default event log filename will be built from the application filepath, but may be overridden via FastMM_SetEventLogFilename.  Messages are built from templates that may be changed/translated by the application.

The optimization strategy of the memory manager may be tuned via FastMM_SetOptimizationStrategy.  It can be set to favour performance, low memory usage, or a blend of both.  The default strategy is to blend the performance and low memory usage goals.

### Supported Compilers
Delphi XE3 and later

### Supported Platforms
Windows, 32-bit and 64-bit

### Change Log
##### Version 5.00
* Version 5 is a complete rewrite of FastMM. It is designed from the ground up to simultaneously keep the strengths and address the shortcomings of version 4.
* Multithreaded scaling across multiple CPU cores is massively improved, without memory usage blowout. It can be configured to scale close to linearly for any number of CPU cores.
* In the Fastcode memory manager benchmark tool FastMM 5 scores 15% higher than FastMM 4.992 on the single threaded benchmarks, and 30% higher on the multithreaded benchmarks. (I7-8700K CPU, EnableMMX and AssumeMultithreaded options enabled.)
* It is fully configurable runtime. There is no need to change conditional defines and recompile to change options. (It is however backward compatible with many of the version 4 conditional defines.) 
* Debug mode uses the same debug support library as version 4 (FastMM_FullDebugMode.dll) by default, but custom stack trace routines are also supported. Call FastMM_EnterDebugMode to switch to debug mode ("FullDebugMode") and call FastMM_ExitDebugMode to return to performance mode. Calls may be nested, in which case debug mode will be exited after the last FastMM_ExitDebugMode call.
* Supports 8, 16, 32 or 64 byte alignment of all blocks. Call FastMM_EnterMinimumAddressAlignment to request a minimum block alignment, and FastMM_ExitMinimumAddressAlignment to rescind a prior request. Calls may be nested, in which case the coarsest alignment request will be in effect.
* All event notifications (errors, memory leak messages, etc.) may be routed to the debugger (via OutputDebugString), a log file, the screen or any combination of the three. Messages are built using templates containing mail-merge tokens. Templates may be changed runtime to facilitate different layouts and/or translation into any language. Templates fully support Unicode, and the log file may be configured to be written in UTF-8 or UTF-16 format, with or without a BOM.
* It may be configured runtime to favour speed, memory usage efficiency or a blend of the two via the FastMM_SetOptimizationStrategy call.
