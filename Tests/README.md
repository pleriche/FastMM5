# FastMM5 test suite

Console test programs for FastMM5, plus a script that builds and runs them with
every Delphi installation it finds.

Each test is a standalone console application that exits with **0 when every
check passed** and with the number of failed checks otherwise, so the suite
needs no test framework and plugs into any CI step that looks at exit codes.

## Running

```powershell
pwsh -File RunTests.ps1                  # every configured compiler, Win32 and Win64
pwsh -File RunTests.ps1 -Only D13.1      # a single compiler
pwsh -File RunTests.ps1 -Platforms Win32 # a single platform
pwsh -File RunTests.ps1 -Quick           # shorter stress runs (for a quick check)
pwsh -File RunTests.ps1 -VerboseOutput   # print the full output of every test
```

The exit code of the script is the number of failed test runs. Edit the
`$Compilers` table at the top of the script if your Delphi installations are not
under `C:\Delphi\...`.

A single test can also be built and run by hand:

```
dcc32 -B -U..;<lib\win32\release> -NSSystem;System.Win;Winapi;Vcl FastMM5Test_DebugMode.dpr
FastMM5Test_DebugMode.exe
```

Compile from within the `Tests` directory - older compilers resolve the
`in 'FastMM_TestUtils.pas'` clause relative to the current directory.

## The tests

| Program | What it covers |
|---|---|
| `FastMM5Test_DebugMode.dpr` | Smoke test: entering and leaving debug mode, allocating, writing, reallocating and freeing in both modes, and the allocated byte count returning to its starting value. |
| `FastMM5Test_SizeClasses.dpr` | Every size class from 1 byte to 2 MB, plus reallocations across the class boundaries, each verified by a size dependent fill pattern. |
| `FastMM5Test_UsagePerSizeClass.dpr` | Churns each size class in turn and asserts that nothing stays allocated and that the committed address space does not keep growing from phase to phase. |
| `FastMM5Test_ModeTransition.dpr` | The contract of the debug and erase mode switches (issue #85): the nesting counter follows the calls, not their success, so a failed Begin still has to be balanced with an End. Guards against the "roll back on failure" idea, which drives the counter negative under correct usage. |
| `FastMM5Test_DoubleFree.dpr` | Double free handling (issue #73): the second free must be rejected *and* must leave the pending free list intact, in particular without the block ending up pointing at itself. Uses a walker thread that sleeps on the block under test to force the pending free path deterministically. |
| `FastMM5Test_ScanCoverage.dpr` | `FastMM_ScanDebugBlocksForCorruption` must detect a corrupted header checksum, an overrun into the debug footer and a write into a freed block - for small, medium and large blocks (issue #102, where the small block cases silently stopped being detected). |
| `FastMM5Test_ScanRace.dpr` | The other direction: while threads churn small debug blocks, a scanning thread must not report corruption that is not there, and must not crash. |
| `FastMM5Test_ScanHeaderBounds.dpr` | Corrupts the size fields in the debug header (`UserSize`, `StackTraceEntryCount`), which is what decides where the scan reads. Each case must produce a clean corruption report rather than an access violation. |
| `FastMM5Test_MultiThreadStress.dpr` | Multithreaded allocation stress with optional cross thread frees through a lock free mailbox; asserts content integrity and the closing balance. Parameters: `Threads Iterations MaxBlockSize DebugMode CrossThreadFree`. |

`FastMM_TestUtils.pas` holds the shared scaffolding: the assertions, the failure
counter and the exit code convention. It also silences message boxes and the
event log file, because several tests corrupt blocks on purpose and a modal
dialog would hang an unattended run.

## Notes for writing further tests

Two things cost time to work out and are easy to trip over again:

* **Corrupting a *freed* small block is not observable.** The block sits in the
  debug free queue and is a candidate for the next allocation of that size. When
  the scan reports the corruption it raises an exception, and raising allocates
  the exception object - which hands out exactly that block, so the corruption is
  detected again while an exception is already in flight and the process dies
  before any handler runs. That is the memory manager doing its job; the test
  simply cannot see it. Use medium or large blocks for freed block cases.
* **A corruption test that uses a large block proves nothing about small
  blocks.** The walk treats the three size classes differently, which is exactly
  how issue #102 stayed unnoticed. Every corruption test here therefore runs
  across all three classes.

## Compiler support

The tests build with Delphi XE3 and later, matching FastMM5 itself, and are
verified against Delphi 10 Seattle and Delphi 13.1 on Win32 and Win64.

The version guards in the sources (`{$if CompilerVersion >= ...}`) are there so
that the same files also work in forks that support older compilers; on XE3 and
later they are inert.
