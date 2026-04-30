[CmdletBinding()]
param(
  [string]$OutputRoot = "",
  [string]$PackageName = "wac-client-windows-setup"
)

$ErrorActionPreference = "Stop"

function Resolve-RepoRoot {
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path
}

function Copy-PackageItem {
  param(
    [Parameter(Mandatory = $true)][string]$RepoRoot,
    [Parameter(Mandatory = $true)][string]$Destination,
    [Parameter(Mandatory = $true)][string]$RelativePath
  )

  $source = Join-Path $RepoRoot $RelativePath
  if (-not (Test-Path -LiteralPath $source)) {
    throw "Required package item is missing: $RelativePath"
  }

  Copy-Item -LiteralPath $source -Destination $Destination -Recurse -Force
}

function Assert-NoForbiddenReleaseFiles {
  param([Parameter(Mandatory = $true)][string]$Path)

  $forbidden = Get-ChildItem -LiteralPath $Path -Recurse -Force -File |
    Where-Object {
      $_.Extension -in @(".exe", ".msi", ".msix", ".appx", ".cab") -or
      $_.FullName -match "\\payload-[^\\]+\\"
    }

  if ($forbidden) {
    $list = ($forbidden | Select-Object -ExpandProperty FullName) -join [Environment]::NewLine
    throw "Release package contains forbidden binary/payload files:$([Environment]::NewLine)$list"
  }
}

$repoRoot = Resolve-RepoRoot
if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $repoRoot "dist"
}

$packageRoot = Join-Path $OutputRoot $PackageName
$zipPath = Join-Path $OutputRoot "$PackageName.zip"
$hashPath = "$zipPath.sha256"

if (Test-Path -LiteralPath $OutputRoot) {
  $resolvedOutput = Resolve-Path -LiteralPath $OutputRoot
  if (-not $resolvedOutput.Path.StartsWith($repoRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to clean output outside repository: $resolvedOutput"
  }
  Remove-Item -LiteralPath $resolvedOutput.Path -Recurse -Force
}

New-Item -ItemType Directory -Path $packageRoot -Force | Out-Null

foreach ($item in @(
  "install-wac.cmd",
  "interactive-installer.ps1",
  "wac-setup-engine.ps1",
  "README.md",
  "README.en.md",
  "VERSION",
  "SECURITY.md",
  "SECURITY.en.md",
  "LICENSE",
  "NOTICE.md",
  "NOTICE.en.md",
  "tui"
)) {
  Copy-PackageItem -RepoRoot $repoRoot -Destination $packageRoot -RelativePath $item
}

Assert-NoForbiddenReleaseFiles -Path $packageRoot

Compress-Archive -Path (Join-Path $packageRoot "*") -DestinationPath $zipPath -Force
$hash = Get-FileHash -Algorithm SHA256 -LiteralPath $zipPath
Set-Content -LiteralPath $hashPath -Encoding ASCII -Value ("{0}  {1}" -f $hash.Hash, (Split-Path -Leaf $zipPath))

Write-Host ("Package: {0}" -f $packageRoot)
Write-Host ("Zip:     {0}" -f $zipPath)
Write-Host ("SHA256:  {0}" -f $hash.Hash)
