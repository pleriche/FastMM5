(*

  FastMM_TestUtils
  ----------------

  The small shared scaffolding for the FastMM5 test programs:  assertions, a
  failure counter, and the exit code convention the test runner relies on.

    - Every test program calls TestsBegin at the start and TestsEnd at the very
      end.  TestsEnd sets ExitCode to the number of failed checks, so the runner
      (and any CI) only has to look at the exit code:  0 = passed.
    - Check / CheckEquals print one line per assertion, so a failing run says
      which case failed and with which values, not just that something failed.
    - TestsBegin also silences the message boxes and the event log file:  several
      tests deliberately corrupt blocks, and a modal dialog would hang an
      unattended run.

  No test framework dependency on purpose:  these are plain console programs
  that build with nothing but the RTL, so they run anywhere FastMM5 does.

  Compiles with Delphi 7 and later.  The version guards are there so that the
  same sources also serve forks that support older compilers;  on XE3 and later
  they are inert.

*)

unit FastMM_TestUtils;

interface

uses
  {$if CompilerVersion >= 23}System.SysUtils{$else}SysUtils{$ifend};

{Initialises the test run:  prints the title and suppresses on-screen and
 on-disk error reporting for the duration of the run.}
procedure TestsBegin(const ATitle: string);

{Prints the summary and sets ExitCode to the number of failures.}
procedure TestsEnd;

{Starts a named group of checks.  Purely cosmetic, but it makes a failing run
 much easier to read.}
procedure Section(const ATitle: string);

{The basic assertion:  prints ADescription with its outcome and counts a
 failure if ACondition is False.}
procedure Check(ACondition: Boolean; const ADescription: string);

{Assertions that report the offending values, so a failure is diagnosable from
 the log alone.}
procedure CheckEqualsInt(AExpected, AActual: Int64; const ADescription: string);
procedure CheckEqualsStr(const AExpected, AActual, ADescription: string);

{Records a failure that is not expressed as a condition (an unexpected
 exception, for instance).}
procedure Fail(const ADescription: string);

{Prints an informational line that is not a check.}
procedure Info(const ADescription: string);

{The number of failed checks so far.}
function FailureCount: Integer;

implementation

uses
  FastMM5;

var
  GFailures: Integer = 0;
  GChecks: Integer = 0;

procedure Flush;
begin
  {A test that corrupts the heap may take the process down;  everything printed
   up to that point must already have left the buffer, which it has not when the
   output is redirected to a file or a pipe.}
  System.Flush(Output);
end;

procedure TestsBegin(const ATitle: string);
begin
  {These tests provoke errors on purpose.  Without this an unattended run would
   stop at a modal message box, and every run would litter the directory with
   event log files.}
  FastMM_MessageBoxEvents := [];
  FastMM_LogToFileEvents := [];
  FastMM_OutputDebugStringEvents := [];

  GFailures := 0;
  GChecks := 0;
  WriteLn(ATitle);
  WriteLn(StringOfChar('=', Length(ATitle)));
  Flush;
end;

procedure Section(const ATitle: string);
begin
  WriteLn;
  WriteLn(ATitle);
  Flush;
end;

procedure Check(ACondition: Boolean; const ADescription: string);
begin
  Inc(GChecks);
  if ACondition then
    WriteLn('  ok    ', ADescription)
  else
  begin
    Inc(GFailures);
    WriteLn('  FAIL  ', ADescription);
  end;
  Flush;
end;

procedure CheckEqualsInt(AExpected, AActual: Int64; const ADescription: string);
begin
  if AExpected = AActual then
    Check(True, ADescription)
  else
    Check(False, ADescription + Format('  (expected %d, got %d)', [AExpected, AActual]));
end;

procedure CheckEqualsStr(const AExpected, AActual, ADescription: string);
begin
  if AExpected = AActual then
    Check(True, ADescription)
  else
    Check(False, ADescription + Format('  (expected "%s", got "%s")', [AExpected, AActual]));
end;

procedure Fail(const ADescription: string);
begin
  Check(False, ADescription);
end;

procedure Info(const ADescription: string);
begin
  WriteLn('        ', ADescription);
  Flush;
end;

function FailureCount: Integer;
begin
  Result := GFailures;
end;

procedure TestsEnd;
begin
  WriteLn;
  if GFailures = 0 then
    WriteLn(Format('PASSED - %d check(s)', [GChecks]))
  else
    WriteLn(Format('FAILED - %d of %d check(s) failed', [GFailures, GChecks]));
  Flush;
  ExitCode := GFailures;
end;

end.
