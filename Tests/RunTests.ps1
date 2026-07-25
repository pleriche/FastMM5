<#
  RunTests.ps1 - builds and runs the FastMM5 test suite.

  Every test program is a console application that exits with 0 when all of its
  checks passed, so this script only has to build it, run it and look at the exit
  code.  The summary at the end lists one line per test per target, and the exit
  code of the script is the number of failed runs, so it can serve as a CI step
  as it is.

  Which compilers are used:

    1. The installations listed in CompilerPaths.txt next to this script, if that
       file exists - one installation root per line, optionally "Name = Path".
       All of them are used.  The file is in .gitignore, so a local setup never
       shows up as a change.
    2. Otherwise the installed versions are found automatically (from the
       registry, and from %EmbarcaderoRoot% if it is set) and the newest one is
       used.  -AllCompilers uses all of them instead.

  Usage:
      pwsh -File RunTests.ps1                      # newest installed compiler, Win32 and Win64
      pwsh -File RunTests.ps1 -AllCompilers        # every installation that was found
      pwsh -File RunTests.ps1 -Only 23.0           # one specific installation
      pwsh -File RunTests.ps1 -Platforms Win32     # one platform only
      pwsh -File RunTests.ps1 -Quick               # shorter stress runs
      pwsh -File RunTests.ps1 -VerboseOutput       # full output of every test
      pwsh -File RunTests.ps1 -ListCompilers       # only report what was found
#>

param(
  [string]$Only = '',
  [string[]]$Platforms = @('Win32', 'Win64'),
  [switch]$AllCompilers,
  [switch]$Quick,
  [switch]$VerboseOutput,
  [switch]$ListCompilers
)

$ErrorActionPreference = 'Stop'
$srcDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$rootDir = Split-Path -Parent $srcDir
$work = Join-Path ([IO.Path]::GetTempPath()) 'FastMM5Tests'
$compilerPathsFile = Join-Path $srcDir 'CompilerPaths.txt'

# The tests, with the arguments to run them with.  The stress tests take a while,
# so -Quick shortens them;  the others ignore their arguments.
$Tests = @(
  @{ name = 'FastMM5Test_DebugMode';          args = @();            quickArgs = @() }
  @{ name = 'FastMM5Test_SizeClasses';        args = @();            quickArgs = @() }
  @{ name = 'FastMM5Test_UsagePerSizeClass';  args = @();            quickArgs = @() }
  @{ name = 'FastMM5Test_ModeTransition';     args = @();            quickArgs = @() }
  @{ name = 'FastMM5Test_DoubleFree';         args = @('2000');      quickArgs = @('2000') }
  @{ name = 'FastMM5Test_ScanCoverage';       args = @();            quickArgs = @() }
  @{ name = 'FastMM5Test_ScanHeaderBounds';   args = @();            quickArgs = @() }
  @{ name = 'FastMM5Test_ScanRace';           args = @('10', '4');   quickArgs = @('3', '4') }
  @{ name = 'FastMM5Test_MultiThreadStress';  args = @('4', '20000', '70000', '1', '1')
                                              quickArgs = @('4', '5000', '70000', '1', '1') }
)

# A sortable numeric key from a version string like "23.0" or "10.4".  Parsed by
# hand rather than cast to a number, because a cast would depend on the locale's
# decimal separator.
function Get-VersionKey([string]$version) {
  $parts = $version -split '[.,]'
  $major = 0
  $minor = 0
  [void][int]::TryParse($parts[0], [ref]$major)
  if ($parts.Count -gt 1) { [void][int]::TryParse($parts[1], [ref]$minor) }
  return $major * 1000 + $minor
}

# An installation is usable if it has a 32 bit compiler.  The Win64 compiler is
# checked per platform later, since old versions do not have one.
function New-Installation([string]$name, [string]$root, [string]$version, [string]$compilerVersion, [int]$sortKey) {
  if (-not $root) { return $null }
  $root = $root.TrimEnd('\')
  if (-not (Test-Path (Join-Path $root 'bin\dcc32.exe'))) { return $null }
  return [pscustomobject]@{
    Name            = $name
    Root            = $root
    Version         = $version
    CompilerVersion = $compilerVersion
    SortKey         = $sortKey
  }
}

function Read-CompilerPathsFile {
  $result = New-Object System.Collections.Generic.List[object]
  foreach ($line in (Get-Content -LiteralPath $compilerPathsFile)) {
    $text = $line.Trim()
    if (($text -eq '') -or $text.StartsWith('#') -or $text.StartsWith(';')) { continue }

    $name = ''
    $path = $text
    # "Name = Path".  Only split on an "=" that comes before any colon, so that a
    # bare path such as C:\Delphi\13.1 is never taken apart.
    $equals = $text.IndexOf('=')
    $colon = $text.IndexOf(':')
    if (($equals -gt 0) -and (($colon -lt 0) -or ($equals -lt $colon))) {
      $name = $text.Substring(0, $equals).Trim()
      $path = $text.Substring($equals + 1).Trim()
    }
    $path = [Environment]::ExpandEnvironmentVariables($path).Trim('"')
    if ($name -eq '') { $name = Split-Path -Leaf $path }

    $install = New-Installation $name $path '' '' $result.Count
    if ($install) {
      $result.Add($install)
    } else {
      Write-Host "  CompilerPaths.txt: no bin\dcc32.exe under '$path' - entry ignored"
    }
  }
  return $result
}

function Find-Installations {
  $found = [ordered]@{}   # lowercased root -> installation

  # The registry is the reliable source:  every Delphi since 2005 registers its
  # root directory under its IDE version number, and ProductVersion there is the
  # number the CompilerVersion define in the sources uses.
  $keys = @(
    'HKCU:\SOFTWARE\Embarcadero\BDS',
    'HKLM:\SOFTWARE\Embarcadero\BDS',
    'HKLM:\SOFTWARE\WOW6432Node\Embarcadero\BDS'
  )
  foreach ($key in $keys) {
    if (-not (Test-Path $key)) { continue }
    foreach ($child in (Get-ChildItem $key -ErrorAction SilentlyContinue)) {
      $props = Get-ItemProperty $child.PSPath -ErrorAction SilentlyContinue
      if (-not $props) { continue }
      $version = $child.PSChildName
      $install = New-Installation $version $props.RootDir $version `
        ([string]$props.ProductVersion) (Get-VersionKey $version)
      if ($install) {
        $lookup = $install.Root.ToLowerInvariant()
        if (-not $found.Contains($lookup)) { $found[$lookup] = $install }
      }
    }
  }

  # %EmbarcaderoRoot% points at the shared Studio directory, with one numbered
  # subdirectory per version.  Only contributes on machines where the registry
  # did not answer.
  if ($env:EmbarcaderoRoot) {
    $studio = Join-Path ($env:EmbarcaderoRoot.Trim('"')) 'Studio'
    if (Test-Path $studio) {
      foreach ($dir in (Get-ChildItem $studio -Directory -ErrorAction SilentlyContinue)) {
        $install = New-Installation $dir.Name $dir.FullName $dir.Name '' (Get-VersionKey $dir.Name)
        if ($install) {
          $lookup = $install.Root.ToLowerInvariant()
          if (-not $found.Contains($lookup)) { $found[$lookup] = $install }
        }
      }
    }
  }

  return @($found.Values | Sort-Object -Property SortKey -Descending)
}

function Get-CompilerInfo($install, [string]$platform) {
  if ($platform -eq 'Win64') {
    return @{
      exe = Join-Path $install.Root 'bin\dcc64.exe'
      lib = Join-Path $install.Root 'lib\win64\release'
    }
  }
  return @{
    exe = Join-Path $install.Root 'bin\dcc32.exe'
    lib = Join-Path $install.Root 'lib\win32\release'
  }
}

function Format-Installation($install) {
  $text = $install.Name
  if ($install.CompilerVersion) { $text += " (compiler version $($install.CompilerVersion))" }
  return "$text  $($install.Root)"
}

# --------------------------------------------------------- select the compilers

$fromFile = Test-Path $compilerPathsFile
if ($fromFile) {
  Write-Host "Using the installations listed in $compilerPathsFile"
  $installations = @(Read-CompilerPathsFile)
} else {
  $installations = @(Find-Installations)
}

if ($installations.Count -eq 0) {
  Write-Host 'No usable Delphi installation found.'
  Write-Host "Create $compilerPathsFile with one installation root per line, for example:"
  Write-Host '    C:\Program Files (x86)\Embarcadero\Studio\23.0'
  exit 1
}

if ($Only) {
  $selected = @($installations | Where-Object { $_.Name -eq $Only })
  if ($selected.Count -eq 0) {
    Write-Host "No installation named '$Only'.  Available:"
    $installations | ForEach-Object { Write-Host "    $(Format-Installation $_)" }
    exit 1
  }
} elseif ($AllCompilers -or $fromFile) {
  # An explicit list in CompilerPaths.txt means "use all of these";  an
  # automatically detected list defaults to the newest, which is the common case.
  $selected = $installations
} else {
  $selected = @($installations[0])
}

if ($ListCompilers -or $VerboseOutput) {
  Write-Host 'Delphi installations found (* = selected):'
  foreach ($install in $installations) {
    $mark = ' '
    if ($selected -contains $install) { $mark = '*' }
    Write-Host "  $mark $(Format-Installation $install)"
  }
  if ($ListCompilers) { exit 0 }
}

# ------------------------------------------------------------- build and run

if (-not (Test-Path $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
$results = New-Object System.Collections.Generic.List[object]

foreach ($install in $selected) {
  foreach ($platform in $Platforms) {
    $info = Get-CompilerInfo $install $platform
    if (-not (Test-Path $info.exe)) {
      Write-Host ''
      Write-Host "[$($install.Name)/$platform] no compiler at $($info.exe) - skipped"
      continue
    }

    $outDir = Join-Path $work "$($install.Name)-$platform"
    if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
    New-Item -ItemType Directory -Path $outDir | Out-Null

    Write-Host ''
    Write-Host "===================== $(Format-Installation $install) / $platform ====================="

    foreach ($test in $Tests) {
      $dpr = Join-Path $srcDir "$($test.name).dpr"
      $exe = Join-Path $outDir "$($test.name).exe"

      # Compile from the source directory:  the "in 'FastMM_TestUtils.pas'"
      # clause is resolved relative to the current directory, not to the .dpr.
      Push-Location $srcDir
      try {
        $buildOutput = & $info.exe -B -Q "-U$($srcDir);$($rootDir);$($info.lib)" `
          '-NSSystem;System.Win;Winapi;Vcl' "-N$outDir" "-E$outDir" $dpr 2>&1
      } finally { Pop-Location }

      if (-not (Test-Path $exe)) {
        Write-Host ("  {0,-34} BUILD FAILED" -f $test.name)
        $buildOutput | Select-Object -Last 5 | ForEach-Object { Write-Host "      $_" }
        $results.Add([pscustomobject]@{ Compiler = $install.Name; Platform = $platform; Test = $test.name; Outcome = 'build failed' })
        continue
      }

      $testArgs = if ($Quick) { $test.quickArgs } else { $test.args }
      $output = & $exe @testArgs 2>&1
      $code = $LASTEXITCODE
      if ($VerboseOutput) { $output | ForEach-Object { Write-Host "      $_" } }

      if ($code -eq 0) {
        $summary = ($output | Select-String -Pattern '^PASSED' | Select-Object -Last 1)
        Write-Host ("  {0,-34} ok    {1}" -f $test.name, $summary)
        $results.Add([pscustomobject]@{ Compiler = $install.Name; Platform = $platform; Test = $test.name; Outcome = 'passed' })
      } else {
        Write-Host ("  {0,-34} FAILED (exit code {1})" -f $test.name, $code)
        # Show what failed, so a red run is diagnosable without rerunning it.
        $output | Select-String -Pattern 'FAIL' | ForEach-Object { Write-Host "      $_" }
        $results.Add([pscustomobject]@{ Compiler = $install.Name; Platform = $platform; Test = $test.name; Outcome = "failed ($code)" })
      }
    }
  }
}

Write-Host ''
Write-Host '===================== Summary ====================='
if ($results.Count -eq 0) {
  Write-Host 'No test ran - none of the selected installations had a usable compiler.'
  exit 1
}
$failed = @($results | Where-Object { $_.Outcome -ne 'passed' })
Write-Host ("{0} of {1} test runs passed." -f ($results.Count - $failed.Count), $results.Count)
foreach ($f in $failed) {
  Write-Host ("  {0}/{1}  {2}  {3}" -f $f.Compiler, $f.Platform, $f.Test, $f.Outcome)
}
Write-Host ''
Write-Host "Build artifacts are in: $work"
exit $failed.Count
