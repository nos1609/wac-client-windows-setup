[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tracked = & git -C $root ls-files
if ($LASTEXITCODE -ne 0 -or -not $tracked) { throw 'Cannot enumerate the release sources.' }
foreach ($name in $tracked) {
  if ($name -match '(^|/)(tmp|dist|\.codex|\.vscode|payload[^/]*)/|\.(exe|dll|msi|msix|appx|appxbundle|msixbundle|cab|pfx|p12|log|zip)$') {
    throw "Forbidden tracked file: $name"
  }
  if ($name -match '\.ps(m)?1$') {
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile((Join-Path $root $name), [ref]$null, [ref]$errors) | Out-Null
    if ($errors.Count) { throw $errors[0] }
  }
}
Import-Module Pester -MinimumVersion 6.2 -ErrorAction Stop
$result = Invoke-Pester -Path (Join-Path $root 'tests/WacMaintenance.Tests.ps1') -PassThru
if ($result.Result -ne 'Passed' -or $result.PassedCount -eq 0) {
  throw "Portable WAC tests did not pass: $($result.Result)"
}

# The reusable workflow requires a clean checkout before and after the job.
$work = Join-Path ([IO.Path]::GetTempPath()) ('wac-build-' + [guid]::NewGuid().ToString('N'))
try {
  & (Join-Path $PSScriptRoot 'build-dist.ps1') -OutputRoot $work
  $zip = Join-Path $work 'wac-client-windows-setup.zip'
  $expected = ((Get-Content -LiteralPath "$zip.sha256" -Raw).Trim() -split '\s+')[0]
  if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $expected) {
    throw 'Release archive SHA256 mismatch.'
  }
  $expectedFiles = @('install-wac.cmd','interactive-installer.ps1','wac-setup-engine.ps1','wac-certificate.ps1',
    'LICENSE','VERSION','README.md','README.en.md','NOTICE.md','NOTICE.en.md','SECURITY.md','SECURITY.en.md',
    'tui/WacTui.Locale.ps1','tui/WacTui.Model.ps1','tui/WacTui.Progress.ps1','tui/WacTui.Render.ps1','tui/WacTui.Validation.ps1')
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [IO.Compression.ZipFile]::OpenRead($zip)
  try {
    $files = @($archive.Entries | Where-Object Name | ForEach-Object { $_.FullName.Replace('\','/') })
    if (Compare-Object $expectedFiles $files) { throw 'Release archive contents do not match the public package.' }
  } finally { $archive.Dispose() }
} finally {
  if (Test-Path -LiteralPath $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
