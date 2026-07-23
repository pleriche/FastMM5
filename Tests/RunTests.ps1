<#
  RunTests.ps1 - builds and runs the FastMM5 test suite.

  Every test program is a console application that exits with 0 when all of its
  checks passed, so this script only has to build it, run it, and look at the
  exit code.  The summary at the end lists one line per test per target.

  Usage:
      pwsh -File RunTests.ps1                     # every compiler below that exists, Win32 and Win64
      pwsh -File RunTests.ps1 -Only D13.1         # a single compiler
      pwsh -File RunTests.ps1 -Platforms Win32    # a single platform
      pwsh -File RunTests.ps1 -Quick              # shorter stress runs
      pwsh -File RunTests.ps1 -Verbose            # show the full output of every test

  Exit code = the number of failed test runs, so this can be used as a CI step.

  Adjust the $Compilers table below if your Delphi installations live elsewhere.
#>

param(
  [string]$Only = '',
  [string[]]$Platforms = @('Win32', 'Win64'),
  [switch]$Quick,
  [switch]$VerboseOutput
)

$ErrorActionPreference = 'Stop'
$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $srcDir
$work = Join-Path ([IO.Path]::GetTempPath()) 'FastMM5Tests'

# name -> @{ root }   The compiler binaries and the RTL are located from the root.
$Compilers = [ordered]@{
  'Seattle' = @{ root = 'C:\Delphi\10' }
  'D13.1'   = @{ root = 'C:\Delphi\13.1' }
}

# The tests, with the arguments to run them with.  The stress tests take a while,
# so -Quick shortens them;  everything else ignores its arguments.
$Tests = @(
  @{ name = 'FastMM5Test_DebugMode';          args = @();                    quickArgs = @() }
  @{ name = 'FastMM5Test_SizeClasses';        args = @();                    quickArgs = @() }
  @{ name = 'FastMM5Test_UsagePerSizeClass';  args = @();                    quickArgs = @() }
  @{ name = 'FastMM5Test_ModeTransition';     args = @();                    quickArgs = @() }
  @{ name = 'FastMM5Test_DoubleFree';         args = @('2000');              quickArgs = @('2000') }
  @{ name = 'FastMM5Test_ScanCoverage';       args = @();                    quickArgs = @() }
  @{ name = 'FastMM5Test_ScanHeaderBounds';   args = @();                    quickArgs = @() }
  @{ name = 'FastMM5Test_ScanRace';           args = @('10', '4');           quickArgs = @('3', '4') }
  @{ name = 'FastMM5Test_MultiThreadStress';  args = @('4', '20000', '70000', '1', '1')
                                              quickArgs = @('4', '5000', '70000', '1', '1') }
)

function Get-CompilerInfo($cfg, $platform) {
  if ($platform -eq 'Win64') {
    return @{
      exe = Join-Path $cfg.root 'bin\dcc64.exe'
      lib = Join-Path $cfg.root 'lib\win64\release'
    }
  }
  return @{
    exe = Join-Path $cfg.root 'bin\dcc32.exe'
    lib = Join-Path $cfg.root 'lib\win32\release'
  }
}

if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work | Out-Null }

$results = New-Object System.Collections.Generic.List[object]

foreach ($name in $Compilers.Keys) {
  if ($Only -and ($Only -ne $name)) { continue }

  foreach ($platform in $Platforms) {
    $info = Get-CompilerInfo $Compilers[$name] $platform
    if (-not (Test-Path $info.exe)) {
      Write-Host "[$name/$platform] compiler not found at $($info.exe) - skipped"
      continue
    }

    $outDir = Join-Path $work "$name-$platform"
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir | Out-Null

    Write-Host ''
    Write-Host "===================== $name / $platform ====================="

    foreach ($test in $Tests) {
      $dpr = Join-Path $srcDir "$($test.name).dpr"
      $exe = Join-Path $outDir "$($test.name).exe"

      # Compile from the source directory:  older compilers resolve the "in
      # 'FastMM_TestUtils.pas'" clause relative to the current directory rather
      # than to the .dpr.
      Push-Location $srcDir
      try {
        $buildOutput = & $info.exe -B -Q "-U$($srcDir);$($rootDir);$($info.lib)" `
          '-NSSystem;System.Win;Winapi;Vcl' "-N$outDir" "-E$outDir" $dpr 2>&1
      } finally { Pop-Location }
      if (-not (Test-Path $exe)) {
        Write-Host ("  {0,-34} BUILD FAILED" -f $test.name)
        $buildOutput | Select-Object -Last 5 | ForEach-Object { Write-Host "      $_" }
        $results.Add([pscustomobject]@{ Compiler = $name; Platform = $platform; Test = $test.name; Outcome = 'build failed' })
        continue
      }

      $testArgs = if ($Quick) { $test.quickArgs } else { $test.args }
      $output = & $exe @testArgs 2>&1
      $code = $LASTEXITCODE
      if ($VerboseOutput) { $output | ForEach-Object { Write-Host "      $_" } }

      if ($code -eq 0) {
        $summary = ($output | Select-String -Pattern '^PASSED' | Select-Object -Last 1)
        Write-Host ("  {0,-34} ok    {1}" -f $test.name, $summary)
        $results.Add([pscustomobject]@{ Compiler = $name; Platform = $platform; Test = $test.name; Outcome = 'passed' })
      } else {
        Write-Host ("  {0,-34} FAILED (exit code {1})" -f $test.name, $code)
        # Show what failed, so a red run is diagnosable without rerunning it.
        $output | Select-String -Pattern 'FAIL' | ForEach-Object { Write-Host "      $_" }
        $results.Add([pscustomobject]@{ Compiler = $name; Platform = $platform; Test = $test.name; Outcome = "failed ($code)" })
      }
    }
  }
}

Write-Host ''
Write-Host '===================== Summary ====================='
$failed = @($results | Where-Object { $_.Outcome -ne 'passed' })
if ($results.Count -eq 0) {
  Write-Host 'No test ran - no configured compiler was found.'
  exit 1
}
Write-Host ("{0} of {1} test runs passed." -f ($results.Count - $failed.Count), $results.Count)
foreach ($f in $failed) {
  Write-Host ("  {0}/{1}  {2}  {3}" -f $f.Compiler, $f.Platform, $f.Test, $f.Outcome)
}
Write-Host ''
Write-Host "Build artifacts are in: $work"
exit $failed.Count
