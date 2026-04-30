[CmdletBinding()]
param(
  [switch]$SkipPester,
  [switch]$SkipScriptAnalyzer
)

$ErrorActionPreference = "Stop"
$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Write-Check {
  param([Parameter(Mandatory = $true)][string]$Message)
  Write-Host ("[check] {0}" -f $Message)
}

function Get-PublicFiles {
  $publicRootFiles = @(
    "CONTRIBUTING.md",
    "CONTRIBUTING.en.md",
    ".coderabbit.yaml",
    "AGENTS.md",
    "install-wac.cmd",
    "interactive-installer.ps1",
    "LICENSE",
    "NOTICE.md",
    "NOTICE.en.md",
    "README.md",
    "README.en.md",
    "VERSION",
    "SECURITY.md",
    "SECURITY.en.md",
    "wac-setup-engine.ps1"
  )

  foreach ($relativePath in $publicRootFiles) {
    $path = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $path) {
      Get-Item -LiteralPath $path
    }
  }

  foreach ($relativePath in @(".github", "scripts", "tests", "tui")) {
    $path = Join-Path $repoRoot $relativePath
    if (Test-Path -LiteralPath $path) {
      Get-ChildItem -LiteralPath $path -Recurse -Force -File
    }
  }
}

function Get-TextFiles {
  Get-PublicFiles |
    Where-Object { $_.Extension -in @(".ps1", ".psm1", ".cmd", ".md", ".txt", ".json", ".toml", ".yml", ".yaml") }
}

Write-Check "required files"
foreach ($relativePath in @(
  "install-wac.cmd",
  ".coderabbit.yaml",
  "AGENTS.md",
  "interactive-installer.ps1",
  "wac-setup-engine.ps1",
  "tui\WacTui.Locale.ps1",
  "tui\WacTui.Model.ps1",
  "tui\WacTui.Progress.ps1",
  "tui\WacTui.Render.ps1",
  "tui\WacTui.Validation.ps1",
  "README.md",
  "README.en.md",
  "VERSION",
  "CONTRIBUTING.md",
  "CONTRIBUTING.en.md",
  "SECURITY.md",
  "SECURITY.en.md",
  "LICENSE",
  "NOTICE.md",
  "NOTICE.en.md"
)) {
  if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $relativePath))) {
    throw "Missing required file: $relativePath"
  }
}

Write-Check "SemVer version file"
$versionText = (Get-Content -LiteralPath (Join-Path $repoRoot "VERSION") -Raw).Trim()
if ($versionText -notmatch "^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$") {
  throw "VERSION must contain SemVer without a leading v. Current value: $versionText"
}

Write-Check "PowerShell parser"
$parseErrors = New-Object System.Collections.Generic.List[string]
Get-PublicFiles |
  Where-Object { $_.Extension -in @(".ps1", ".psm1") } |
  ForEach-Object {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($error in $errors) {
      [void]$parseErrors.Add(("{0}: {1}" -f $_.FullName, $error.Message))
    }
  }
if ($parseErrors.Count -gt 0) {
  throw ($parseErrors -join [Environment]::NewLine)
}

if (-not $SkipScriptAnalyzer) {
  $analyzer = Get-Module -ListAvailable -Name PSScriptAnalyzer | Select-Object -First 1
  if ($analyzer) {
    Write-Check "PSScriptAnalyzer Error severity"
    $scriptFiles = Get-PublicFiles |
      Where-Object { $_.Extension -in @(".ps1", ".psm1") }
    $diagnostics = foreach ($scriptFile in $scriptFiles) {
      Invoke-ScriptAnalyzer -Path $scriptFile.FullName -Severity Error
    }
    if ($diagnostics) {
      $diagnostics | Format-Table -AutoSize | Out-String | Write-Host
      throw "PSScriptAnalyzer reported Error severity diagnostics."
    }
  } else {
    Write-Warning "PSScriptAnalyzer is not installed; skipping analyzer check."
  }
}

if (-not $SkipPester) {
  $pester = Get-Module -ListAvailable -Name Pester | Select-Object -First 1
  if ($pester) {
    Write-Check "Pester"
    $pesterResult = Invoke-Pester -Path (Join-Path $repoRoot "tests") -EnableExit:$false -PassThru
    $failedCount = 0
    if ($null -ne $pesterResult.FailedCount) {
      $failedCount = [int]$pesterResult.FailedCount
    } elseif ($null -ne $pesterResult.TestResult) {
      $failedCount = @($pesterResult.TestResult | Where-Object { $_.Result -eq "Failed" }).Count
    }
    if ($failedCount -gt 0) {
      throw "Pester reported $failedCount failed test(s)."
    }
  } else {
    Write-Warning "Pester is not installed; skipping Pester tests."
  }
}

Write-Check "forbidden binaries"
$forbiddenFiles = Get-PublicFiles |
  Where-Object {
    ($_.Extension -in @(".exe", ".msi", ".msix", ".appx", ".cab") -or $_.FullName -match "\\payload-[^\\]+\\")
  }
if ($forbiddenFiles) {
  $forbiddenFiles | Select-Object FullName,Length | Format-Table -AutoSize | Out-String | Write-Host
  throw "Repository contains forbidden binary or extracted payload files."
}

Write-Check "public naming and local paths"
$badPatterns = @(
  ("WAC" + "2511"),
  ("wac" + "2511"),
  ("WAC" + "2511-Win11-x64-" + "offline"),
  ("install-wac" + "2511"),
  ("D:" + "\" + $env:USERNAME),
  ("C:" + "\Users\" + $env:USERNAME),
  ("C:" + "\Users\user\Downloads")
)
$violations = New-Object System.Collections.Generic.List[string]
foreach ($file in Get-TextFiles) {
  $content = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
  foreach ($pattern in $badPatterns) {
    if ($content -like "*$pattern*") {
      [void]$violations.Add(("{0}: contains {1}" -f $file.FullName, $pattern))
    }
  }
}
if ($violations.Count -gt 0) {
  throw ($violations -join [Environment]::NewLine)
}

Write-Check "launcher plan-only smoke"
$cmd = Join-Path $repoRoot "install-wac.cmd"
& cmd.exe /c "`"$cmd`" -PlanOnly -Ascii -Language Ru"
if ($LASTEXITCODE -ne 0) { throw "Russian plan-only launcher smoke failed with exit code $LASTEXITCODE" }
& cmd.exe /c "`"$cmd`" -PlanOnly -Ascii -Language En"
if ($LASTEXITCODE -ne 0) { throw "English plan-only launcher smoke failed with exit code $LASTEXITCODE" }

Write-Host "All release checks passed."
