<#
Setup engine for Windows Admin Center on client Windows x64.

This bypasses the WAC Inno preflight that currently rejects client
Windows SKUs by extracting the signed installer payload and applying the
same practical machine configuration directly.

Run elevated:
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1
  pwsh.exe       -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
  [string]$InstallerPath = "",
  [string]$InnoExtractPath = "",
  [string]$ExtractOut = "",
  [string]$InstallDir = "$env:ProgramFiles\WindowsAdminCenter",
  [string]$DataDir = "$env:ProgramData\WindowsAdminCenter",
  [int]$Port = 6600,
  [int]$ServicePortStart = 6601,
  [int]$ServicePortEnd = 6610,
  [string]$EndpointFqdn = $env:COMPUTERNAME,
  [string]$ServiceFqdn = "localhost",
  [string]$CertificateThumbprint = "",
  [string]$CertificateSubject = "WindowsAdminCenterSelfSigned",
  [ValidateSet("Automatic", "Manual", "Notification")]
  [string]$SoftwareUpdateMode = "Manual",
  [ValidateSet("Required", "Optional")]
  [string]$DiagnosticDataMode = "Required",
  [ValidateSet("LocalOnly", "LocalSubnet", "Any")]
  [string]$NetworkAccess = "LocalOnly",
  [ValidateSet("ConfigureTrustedHosts", "NotConfigureTrustedHosts")]
  [string]$TrustedHostsMode = "NotConfigureTrustedHosts",
  [ValidateSet("Enable", "Disable")]
  [string]$WinRmHttpsMode = "Disable",
  [switch]$TrustSelfSignedCertificate,
  [switch]$SkipExtraction,
  [switch]$SkipPsRemoting,
  [switch]$KeepExistingData,
  [switch]$SkipArchitectureCheck,
  [switch]$Uninstall,
  [switch]$PurgeData,
  [ValidateSet("Auto", "Ru", "En")]
  [string]$Language = "Auto",
  [string]$LogPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
function Get-NativeProcessOutputEncoding {
  try {
    $oemCodePage = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
    if ($oemCodePage -gt 0) {
      return [System.Text.Encoding]::GetEncoding($oemCodePage)
    }
  } catch {
  }

  return [Console]::OutputEncoding
}

$script:OriginalBoundParameters = @{}
foreach ($key in $PSBoundParameters.Keys) {
  $script:OriginalBoundParameters[$key] = $PSBoundParameters[$key]
}
$script:NativeProcessOutputEncoding = Get-NativeProcessOutputEncoding
try {
  [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $OutputEncoding = [Console]::OutputEncoding
} catch {
}

$script:ServiceName = "WindowsAdminCenter"
$script:AccountServiceName = "WindowsAdminCenterAccountManagement"
$script:UpdaterScheduledTaskName = "WindowsAdminCenterUpdater"
$script:UpdaterScheduledTaskSecurityDescriptor = "O:BAD:AI(A;;FR;;;SY)(A;;0x1200a9;;;NS)(A;ID;0x1f019f;;;BA)(A;ID;0x1f019f;;;SY)(A;ID;FA;;;BA)"
$script:AppId = "{13EF9EED-B613-4D2D-8B82-7E5B90BE4990}"
$script:InnoExtractVersion = "670"
$script:InnoExtractZipSha256 = "79B69B9B1FCD98F42CCD4B245EFDF6A03BCFB674BA6AF482F5A46891C9ED4D14"
$script:InnoExtractZipUrl = "https://github.com/UserUnknownFactor/innoextract_win/releases/download/670/innoextract670.zip"
$script:WingetDownloadTimeoutSeconds = 120
$script:PreviousTrustedHosts = $null
$script:Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
if ([string]::IsNullOrWhiteSpace($LogPath)) {
  $script:DiagDir = "C:\WAC-Diag"
  $script:LogPath = Join-Path $script:DiagDir ("wac-setup-install-{0}.log" -f $script:Stamp)
} else {
  $script:LogPath = $LogPath
  $script:DiagDir = Split-Path -Parent $script:LogPath
}
$script:Language = if ($Language -eq "Auto") {
  if ([Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName -eq "ru") { "Ru" } else { "En" }
} else {
  $Language
}
function ConvertFrom-CodePoint {
  param([Parameter(ValueFromRemainingArguments = $true)][int[]]$CodePoint)
  return -join ($CodePoint | ForEach-Object { [char]$_ })
}

$script:Text = @{
  RunningInstaller = @{
    En = "Running WAC setup engine."
    Ru = "Запуск установочного движка WAC."
  }
  Complete = @{
    En = "Windows Admin Center setup completed."
    Ru = "Установка Windows Admin Center завершена."
  }
  Open = @{
    En = "Open"
    Ru = ConvertFrom-CodePoint 0x041E 0x0442 0x043A 0x0440 0x044B 0x0442 0x044C
  }
  OpenUrl = @{
    En = "Open: https://localhost:{0}"
    Ru = ConvertFrom-CodePoint 0x041E 0x0442 0x043A 0x0440 0x044B 0x0442 0x044C 0x3A 0x20 0x68 0x74 0x74 0x70 0x73 0x3A 0x2F 0x2F 0x6C 0x6F 0x63 0x61 0x6C 0x68 0x6F 0x73 0x74 0x3A 0x7B 0x30 0x7D
  }
  Log = @{
    En = "Log"
    Ru = ConvertFrom-CodePoint 0x041B 0x043E 0x0433
  }
  LogPath = @{
    En = "Log:  {0}"
    Ru = ConvertFrom-CodePoint 0x041B 0x043E 0x0433 0x3A 0x20 0x20 0x7B 0x30 0x7D
  }
  Failed = @{
    En = "FAILED"
    Ru = ConvertFrom-CodePoint 0x041E 0x0428 0x0418 0x0411 0x041A 0x0410
  }
  FailedLog = @{
    En = "FAILED. Log: {0}"
    Ru = ConvertFrom-CodePoint 0x041E 0x0428 0x0418 0x0411 0x041A 0x0410 0x2E 0x20 0x041B 0x043E 0x0433 0x3A 0x20 0x7B 0x30 0x7D
  }
  InnoExtractDllFailure = @{
    En = "innoextract failed to start: a required DLL is missing. Check tools\libbz2-1.dll."
    Ru = ConvertFrom-CodePoint 0x0069 0x006E 0x006E 0x006F 0x0065 0x0078 0x0074 0x0072 0x0061 0x0063 0x0074 0x0020 0x043D 0x0435 0x0020 0x0437 0x0430 0x043F 0x0443 0x0441 0x0442 0x0438 0x043B 0x0441 0x044F 0x003A 0x0020 0x043D 0x0435 0x0020 0x043D 0x0430 0x0439 0x0434 0x0435 0x043D 0x0430 0x0020 0x043D 0x0443 0x0436 0x043D 0x0430 0x044F 0x0020 0x0044 0x004C 0x004C 0x002E 0x0020 0x041F 0x0440 0x043E 0x0432 0x0435 0x0440 0x044C 0x0442 0x0435 0x0020 0x0074 0x006F 0x006F 0x006C 0x0073 0x005C 0x006C 0x0069 0x0062 0x0062 0x007A 0x0032 0x002D 0x0031 0x002E 0x0064 0x006C 0x006C 0x002E
  }
  RequestingAdmin = @{
    En = "Requesting administrator privileges. UAC will open an elevated PowerShell window."
    Ru = ConvertFrom-CodePoint 0x0417 0x0430 0x043F 0x0440 0x0430 0x0448 0x0438 0x0432 0x0430 0x044E 0x0020 0x043F 0x0440 0x0430 0x0432 0x0430 0x0020 0x0430 0x0434 0x043C 0x0438 0x043D 0x0438 0x0441 0x0442 0x0440 0x0430 0x0442 0x043E 0x0440 0x0430 0x002E 0x0020 0x0055 0x0041 0x0043 0x0020 0x043E 0x0442 0x043A 0x0440 0x043E 0x0435 0x0442 0x0020 0x043F 0x043E 0x0432 0x044B 0x0448 0x0435 0x043D 0x043D 0x043E 0x0435 0x0020 0x043E 0x043A 0x043D 0x043E 0x0020 0x0050 0x006F 0x0077 0x0065 0x0072 0x0053 0x0068 0x0065 0x006C 0x006C 0x002E
  }
  PressEnter = @{
    En = "Press Enter to continue..."
    Ru = ConvertFrom-CodePoint 0x0414 0x043B 0x044F 0x0020 0x043F 0x0440 0x043E 0x0434 0x043E 0x043B 0x0436 0x0435 0x043D 0x0438 0x044F 0x0020 0x043D 0x0430 0x0436 0x043C 0x0438 0x0442 0x0435 0x0020 0x0045 0x006E 0x0074 0x0065 0x0072 0x002E 0x002E 0x002E
  }
  UninstallComplete = @{
    En = "Windows Admin Center uninstall completed."
    Ru = "Удаление Windows Admin Center завершено."
  }
}

function Get-Text {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [ValidateSet("Ru", "En")][string]$Lang = $script:Language
  )
  $entry = $script:Text[$Key]
  if ($entry -and $entry[$Lang]) { return $entry[$Lang] }
  if ($entry -and $entry["En"]) { return $entry["En"] }
  return $Key
}

function Add-LogContent {
  param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

  $encoding = [System.Text.UTF8Encoding]::new($false)
  $lastError = $null
  for ($attempt = 0; $attempt -lt 30; $attempt++) {
    try {
      $stream = [System.IO.File]::Open($script:LogPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
      try {
        $writer = New-Object System.IO.StreamWriter($stream, $encoding)
        try {
          $writer.WriteLine($Value)
        } finally {
          $writer.Dispose()
        }
      } finally {
        $stream.Dispose()
      }
      return
    } catch {
      $lastError = $_.Exception
      Start-Sleep -Milliseconds 100
    }
  }

  if ($lastError) { throw $lastError }
}

function Write-UserText {
  param(
    [Parameter(Mandatory = $true)][string]$Key,
    [object[]]$FormatArgs = @()
  )

  $line = Get-Text $Key
  if ($FormatArgs.Count -gt 0) {
    $line = $line -f $FormatArgs
  }
  Write-Host $line
  Add-LogContent -Value ("[{0}] [USER] {1}" -f (Get-Date -Format "HH:mm:ss"), $line)
}

function Write-Log {
  param(
    [Parameter(Mandatory = $true)][string]$Message,
    [ValidateSet("INFO", "WARN", "ERROR", "STEP")][string]$Level = "INFO"
  )
  $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
  Write-Host $line
  Add-LogContent -Value $line
}

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = New-Object Security.Principal.WindowsPrincipal($id)
  return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Join-CommandArgument {
  param([Parameter(Mandatory = $true)][string]$Value)
  if ($Value -notmatch '[\s"]') { return $Value }
  return '"' + ($Value -replace '\\(?=")', '$0' -replace '"', '\"') + '"'
}

function Get-ElevationArgumentString {
  $items = New-Object System.Collections.Generic.List[string]
  $baseArgs = @("-NoLogo", "-NoProfile")
  if ($env:WAC_WAIT_ON_EXIT -eq "1") {
    $baseArgs += "-NoExit"
  }
  $baseArgs += @("-ExecutionPolicy", "Bypass", "-File", $PSCommandPath)
  foreach ($item in $baseArgs) {
    [void]$items.Add((Join-CommandArgument $item))
  }

  foreach ($key in $script:OriginalBoundParameters.Keys) {
    if ($key -in @("WhatIf", "Confirm")) { continue }
    $value = $script:OriginalBoundParameters[$key]
    if ($value -is [System.Management.Automation.SwitchParameter]) {
      if ($value.IsPresent) { [void]$items.Add("-$key") }
      continue
    }
    if ($null -ne $value -and "$value" -ne "") {
      [void]$items.Add("-$key")
      [void]$items.Add((Join-CommandArgument ([string]$value)))
    }
  }
  return ($items -join " ")
}

function Get-WindowsTerminalPath {
  $command = Get-Command "wt.exe" -ErrorAction SilentlyContinue
  if ($command -and $command.Source) { return $command.Source }

  $candidate = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\wt.exe"
  if (Test-Path -LiteralPath $candidate) { return $candidate }

  return ""
}

function Get-WindowsTerminalElevationArgumentString {
  param([Parameter(Mandatory = $true)][string]$HostPath)

  $items = New-Object System.Collections.Generic.List[string]
  foreach ($item in @("new-tab", "--title", "WAC elevated - WAC", "--", $HostPath)) {
    [void]$items.Add((Join-CommandArgument $item))
  }
  [void]$items.Add((Get-ElevationArgumentString))
  return ($items -join " ")
}

function Invoke-SelfElevated {
  if (Test-Admin) { return }

  Write-Host (Get-Text "RequestingAdmin")
  $hostPath = (Get-Process -Id $PID).Path
  if ([string]::IsNullOrWhiteSpace($hostPath)) {
    $hostPath = Join-Path $PSHOME "powershell.exe"
  }

  $terminalPath = Get-WindowsTerminalPath
  if (-not [string]::IsNullOrWhiteSpace($terminalPath)) {
    try {
      Start-Process -FilePath $terminalPath -ArgumentList (Get-WindowsTerminalElevationArgumentString -HostPath $hostPath) -Verb RunAs
      exit 0
    } catch {
      Write-Host ("Windows Terminal elevation failed, falling back to PowerShell host: {0}" -f $_.Exception.Message)
    }
  }

  Start-Process -FilePath $hostPath -ArgumentList (Get-ElevationArgumentString) -Verb RunAs
  exit 0
}

function Wait-IfRequested {
  if ($env:WAC_WAIT_ON_EXIT -eq "1") {
    try { [void](Read-Host (Get-Text "PressEnter")) } catch {}
  }
}

Invoke-SelfElevated
New-Item -ItemType Directory -Path $script:DiagDir -Force | Out-Null

function Assert-Admin {
  if (-not (Test-Admin)) { throw "Run from an elevated PowerShell session." }
}

function Invoke-LoggedProcess {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [string[]]$ArgumentList = @(),
    [string]$WorkingDirectory = "",
    [int]$TimeoutSeconds = 0,
    [bool]$LogOutputOnSuccess = $true
  )

  Write-Log ("RUN: {0} {1}" -f $FilePath, ($ArgumentList -join " "))
  $previousLocation = Get-Location
  try {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = $script:NativeProcessOutputEncoding
    $psi.StandardErrorEncoding = $script:NativeProcessOutputEncoding
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
      $psi.WorkingDirectory = $WorkingDirectory
    }
    $psi.Arguments = (($ArgumentList | ForEach-Object {
      if ($_ -match '[\s"]') {
        '"' + ($_ -replace '"', '\"') + '"'
      } else {
        $_
      }
    }) -join " ")

    $process = [System.Diagnostics.Process]::Start($psi)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $completed = if ($TimeoutSeconds -gt 0) {
      $process.WaitForExit($TimeoutSeconds * 1000)
    } else {
      $process.WaitForExit()
      $true
    }

    if (-not $completed) {
      try { $process.Kill() } catch {}
      Write-Log ("TIMEOUT {0}: exceeded {1} seconds" -f $FilePath, $TimeoutSeconds) "WARN"
      return [pscustomobject]@{ ExitCode = -1; StdOut = ""; StdErr = "Timed out after $TimeoutSeconds seconds."; TimedOut = $true }
    }

    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    if ($stdout -and ($LogOutputOnSuccess -or $process.ExitCode -ne 0)) { Add-LogContent -Value $stdout }
    if ($stderr -and ($LogOutputOnSuccess -or $process.ExitCode -ne 0)) { Add-LogContent -Value $stderr }
    Write-Log ("EXIT {0}: {1}" -f $FilePath, $process.ExitCode)
    return [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr; TimedOut = $false }
  } finally {
    Set-Location -LiteralPath $previousLocation.Path
  }
}

function Get-DefaultInstallerPath {
  $searchRoots = @($PSScriptRoot)
  foreach ($root in $searchRoots) {
    if (-not (Test-Path -LiteralPath $root)) { continue }
    $candidate = Get-ChildItem -LiteralPath $root -File -Filter "WindowsAdminCenter*.exe" -ErrorAction SilentlyContinue |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if ($candidate) { return $candidate.FullName }
  }

  return ""
}

function Get-InstallerDownloadDirectory {
  return (Join-Path $env:ProgramData "WACSetup\downloads")
}

function Find-WacInstallerInDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  $installer = Find-WacInstallersInDirectory -Path $Path | Select-Object -First 1
  if ($installer) { return $installer }
  return ""
}

function Find-WacInstallersInDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return "" }

  $candidates = Get-ChildItem -LiteralPath $Path -Recurse -File -Filter "*.exe" -ErrorAction SilentlyContinue |
    Where-Object {
      $_.Name -match "WindowsAdminCenter|Windows Admin Center|WAC" -or
      $_.VersionInfo.ProductName -match "Windows Admin Center"
    } |
    Sort-Object LastWriteTime -Descending

  return @($candidates | ForEach-Object { $_.FullName })
}

function Test-WacInstallerAuthenticode {
  param([Parameter(Mandatory = $true)][string]$Path)

  try {
    $sig = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
  } catch {
    Write-Log "Ignoring cached Windows Admin Center installer that could not be validated: $Path" "WARN"
    return $false
  }

  if ($sig.Status -ne "Valid") {
    Write-Log "Ignoring cached Windows Admin Center installer with invalid signature: $Path ($($sig.Status))" "WARN"
    return $false
  }
  if ($null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch "(^|,\s*)O=Microsoft Corporation(,|$)") {
    Write-Log "Ignoring cached Windows Admin Center installer with unexpected signer: $Path" "WARN"
    return $false
  }

  return $true
}

function Get-CachedWacInstaller {
  $downloadDir = Get-InstallerDownloadDirectory
  $candidates = Find-WacInstallersInDirectory -Path $downloadDir

  foreach ($installer in @($candidates)) {
    if ([string]::IsNullOrWhiteSpace($installer)) { continue }
    if (Test-WacInstallerAuthenticode -Path $installer) {
      Write-Log "Using cached Windows Admin Center installer: $installer"
      return $installer
    }
  }

  return ""
}

function Save-WacInstallerFromWinget {
  $winget = Get-Command "winget.exe" -ErrorAction SilentlyContinue
  if (-not $winget) {
    Write-Log "winget.exe not found; skipping winget download" "WARN"
    return ""
  }

  $downloadDir = Get-InstallerDownloadDirectory
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

  Write-Log "Downloading Windows Admin Center installer with winget" "STEP"
  $arguments = @(
    "download",
    "--id", "Microsoft.WindowsAdminCenter",
    "--exact",
    "--source", "winget",
    "--architecture", "x64",
    "--download-directory", $downloadDir,
    "--accept-package-agreements",
    "--accept-source-agreements",
    "--disable-interactivity"
  )

  $result = Invoke-LoggedProcess -FilePath $winget.Source -ArgumentList $arguments -TimeoutSeconds $script:WingetDownloadTimeoutSeconds -LogOutputOnSuccess:$false
  if ($result.ExitCode -ne 0) {
    Write-Log "winget download failed with exit code $($result.ExitCode); falling back to cached installer or aka.ms" "WARN"
    $cachedInstaller = Get-CachedWacInstaller
    if (-not [string]::IsNullOrWhiteSpace($cachedInstaller)) {
      Write-Log "Using cached Windows Admin Center installer after winget failure"
      return $cachedInstaller
    }
    return ""
  }

  $installer = Find-WacInstallerInDirectory -Path $downloadDir
  if ([string]::IsNullOrWhiteSpace($installer)) {
    Write-Log "winget download completed but Windows Admin Center installer was not found; falling back to aka.ms" "WARN"
    return ""
  }

  Write-Log "Downloaded installer with winget: $installer"
  return $installer
}

function Save-WacInstallerFromAkaMs {
  $downloadDir = Get-InstallerDownloadDirectory
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

  $target = Join-Path $downloadDir "WindowsAdminCenter.exe"
  Write-Log "Downloading Windows Admin Center installer from https://aka.ms/WACDownload" "STEP"

  try {
    if (Get-Command "Start-BitsTransfer" -ErrorAction SilentlyContinue) {
      Start-BitsTransfer -Source "https://aka.ms/WACDownload" -Destination $target -ErrorAction Stop
    } else {
      Invoke-WebRequest -Uri "https://aka.ms/WACDownload" -OutFile $target -UseBasicParsing -ErrorAction Stop
    }
  } catch {
    Write-Log ("aka.ms download failed: {0}" -f $_.Exception.Message) "WARN"
    return ""
  }

  if (Test-Path -LiteralPath $target) {
    Write-Log "Downloaded installer from aka.ms: $target"
    return $target
  }

  Write-Log "aka.ms download finished but installer file was not found" "WARN"
  return ""
}

function Get-DefaultInnoExtractPath {
  $cmd = Get-Command innoextract.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }

  $candidates = @(
    (Join-Path $PSScriptRoot "innoextract670\innoextract.exe"),
    (Join-Path $PSScriptRoot "tools\innoextract.exe"),
    (Join-Path $PSScriptRoot "innoextract.exe")
  )
  foreach ($candidate in $candidates) {
    $resolved = Resolve-Path -LiteralPath $candidate -ErrorAction SilentlyContinue
    if ($resolved) { return $resolved.Path }
  }
  return ""
}

function Get-InnoExtractDownloadDirectory {
  return (Join-Path $env:ProgramData ("WACSetup\tools\innoextract-{0}" -f $script:InnoExtractVersion))
}

function Find-InnoExtractInDirectory {
  param([Parameter(Mandatory = $true)][string]$Path)

  if (-not (Test-Path -LiteralPath $Path)) { return "" }
  $candidate = Get-ChildItem -LiteralPath $Path -Recurse -File -Filter "innoextract.exe" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($candidate) { return $candidate.FullName }
  return ""
}

function Expand-InnoExtractZip {
  param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [Parameter(Mandatory = $true)][string]$DestinationPath
  )

  if (Test-Path -LiteralPath $DestinationPath) {
    Remove-Item -LiteralPath $DestinationPath -Recurse -Force
  }
  New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
  Expand-Archive -LiteralPath $ZipPath -DestinationPath $DestinationPath -Force
  return (Find-InnoExtractInDirectory -Path $DestinationPath)
}

function Save-InnoExtractFromOfficialZip {
  $downloadDir = Get-InnoExtractDownloadDirectory
  New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null

  $zipPath = Join-Path $downloadDir ("innoextract-{0}.zip" -f $script:InnoExtractVersion)
  Write-Log "Downloading innoextract from $script:InnoExtractZipUrl" "STEP"
  try {
    Invoke-WebRequest -Uri $script:InnoExtractZipUrl -OutFile $zipPath -UseBasicParsing -ErrorAction Stop
  } catch {
    Write-Log ("innoextract official zip download failed: {0}" -f $_.Exception.Message) "WARN"
    return ""
  }

  $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash
  if ($hash -ne $script:InnoExtractZipSha256) {
    throw "innoextract zip SHA256 mismatch. Expected $script:InnoExtractZipSha256, got $hash."
  }

  $expanded = Expand-InnoExtractZip -ZipPath $zipPath -DestinationPath (Join-Path $downloadDir "expanded-official")
  if ($expanded) {
    Write-Log "Downloaded and expanded innoextract official zip: $expanded"
    return $expanded
  }

  Write-Log "innoextract official zip expanded but innoextract.exe was not found" "WARN"
  return ""
}

function Save-InnoExtract {
  return (Save-InnoExtractFromOfficialZip)
}

function Test-TargetArchitecture {
  if ($SkipArchitectureCheck -or $env:WAC_SKIP_ARCHITECTURE_CHECK -eq "1") { return }

  $os = Get-CimInstance Win32_OperatingSystem
  $arch = $os.OSArchitecture
  Write-Log ("OS: {0}; Version={1}; Build={2}; Arch={3}; ProductType={4}; SKU={5}" -f $os.Caption, $os.Version, $os.BuildNumber, $arch, $os.ProductType, $os.OperatingSystemSKU)

  if ($arch -notmatch "64" -or $env:PROCESSOR_ARCHITECTURE -eq "ARM64") {
    throw "This script is intentionally scoped to Windows x64. Current OSArchitecture=$arch PROCESSOR_ARCHITECTURE=$env:PROCESSOR_ARCHITECTURE."
  }
}

function Set-JsonValue {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][object[]]$Path,
    [Parameter(Mandatory = $true)]$Value
  )

  $node = $Object
  for ($i = 0; $i -lt ($Path.Count - 1); $i++) {
    $key = $Path[$i]
    if ($key -is [int]) {
      $node = $node[$key]
    } else {
      if (-not ($node.PSObject.Properties.Name -contains $key)) {
        $node | Add-Member -NotePropertyName $key -NotePropertyValue ([pscustomobject]@{})
      }
      $node = $node.$key
    }
  }

  $leaf = $Path[$Path.Count - 1]
  if ($leaf -is [int]) {
    $node[$leaf] = $Value
  } elseif ($node.PSObject.Properties.Name -contains $leaf) {
    $node.$leaf = $Value
  } else {
    $node | Add-Member -NotePropertyName $leaf -NotePropertyValue $Value
  }
}

function Read-WacAppSettingsJson {
  param([Parameter(Mandatory = $true)][string]$AppSettingsPath)

  try {
    return (Get-Content -LiteralPath $AppSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop)
  } catch {
    throw "WAC appsettings.json is missing or invalid. Payload extraction may be incomplete or corrupt: $AppSettingsPath. $($_.Exception.Message)"
  }
}

function Get-InstallerProductVersion {
  param([Parameter(Mandatory = $true)][string]$Path)

  $version = (Get-Item -LiteralPath $Path -ErrorAction Stop).VersionInfo.ProductVersion
  if ([string]::IsNullOrWhiteSpace($version)) { return "" }
  return $version.Trim()
}

function Get-WacAppSettingsNuGetVersion {
  param(
    [Parameter(Mandatory = $true)]$AppSettings,
    [Parameter(Mandatory = $true)][string]$Fallback
  )

  $value = $null
  if ($AppSettings.PSObject.Properties.Name -contains "WindowsAdminCenter") {
    $wac = $AppSettings.WindowsAdminCenter
    if ($wac -and $wac.PSObject.Properties.Name -contains "System") {
      $system = $wac.System
      if ($system -and $system.PSObject.Properties.Name -contains "NuGetVersion") {
        $value = $system.NuGetVersion
      }
    }
  }

  if ([string]::IsNullOrWhiteSpace([string]$value)) { return $Fallback }
  return ([string]$value).Trim()
}

function Copy-DirectoryContents {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$Destination
  )

  if (-not (Test-Path -LiteralPath $Source)) { throw "Source directory not found: $Source" }
  New-Item -ItemType Directory -Path $Destination -Force | Out-Null
  Get-ChildItem -LiteralPath $Source -Force | Copy-Item -Destination $Destination -Recurse -Force
}

function Stop-And-DeleteService {
  param([Parameter(Mandatory = $true)][string]$Name)

  $svc = Get-Service -Name $Name -ErrorAction SilentlyContinue
  if ($svc) {
    Write-Log "Stopping service $Name"
    Stop-Service -Name $Name -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  [void](Invoke-LoggedProcess -FilePath "sc.exe" -ArgumentList @("delete", $Name) -LogOutputOnSuccess:$false)
    Start-Sleep -Seconds 2
  }
}

function Wait-WacServiceRunning {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [int]$TimeoutSeconds = 60
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $svc = Get-Service -Name $Name -ErrorAction Stop
    if ($svc.Status -eq "Running") { return $svc }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)

  return (Get-Service -Name $Name -ErrorAction Stop)
}

function Remove-HttpSysBinding {
  param([int]$BindingPort)

  [void](Invoke-LoggedProcess -FilePath "netsh.exe" -ArgumentList @("http", "delete", "sslcert", "ipport=0.0.0.0:$BindingPort") -LogOutputOnSuccess:$false)
  [void](Invoke-LoggedProcess -FilePath "netsh.exe" -ArgumentList @("http", "delete", "urlacl", "url=https://+:$BindingPort/") -LogOutputOnSuccess:$false)
}

function Grant-DirectoryAcl {
  param([Parameter(Mandatory = $true)][string]$Path)

  Write-Log "Granting ACLs on $Path"
  $args = @(
    $Path,
    "/grant",
    "*S-1-5-18:(OI)(CI)F",
    "*S-1-5-32-544:(OI)(CI)F",
    "*S-1-5-20:(OI)(CI)M",
    "*S-1-5-11:(OI)(CI)RX",
    "/T",
    "/C"
  )
  [void](Invoke-LoggedProcess -FilePath "icacls.exe" -ArgumentList $args -LogOutputOnSuccess:$false)
}

function Get-EffectiveCertificateSubject {
  if ($WinRmHttpsMode -eq "Enable" -and -not [string]::IsNullOrWhiteSpace($EndpointFqdn)) {
    if ($script:OriginalBoundParameters.ContainsKey("CertificateSubject") -and -not (Test-IsDefaultCertificateSubject -Subject $CertificateSubject)) {
      $subjectName = Get-CertificateSubjectCommonName -Subject $CertificateSubject
      if (-not (Test-CertificateDnsName -Pattern $subjectName -Name $EndpointFqdn)) {
        throw "CertificateSubject must match EndpointFqdn when WinRM over HTTPS is enabled. Omit -CertificateSubject or set it to $EndpointFqdn."
      }
    }
    return $EndpointFqdn
  }

  return $CertificateSubject
}

function Get-CertificateSubjectCommonName {
  param([AllowNull()][string]$Subject = "")

  $value = if ($null -eq $Subject) { "" } else { $Subject.Trim() }
  $match = [regex]::Match($value, "^\s*CN\s*=\s*([^,]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($match.Success) {
    return $match.Groups[1].Value.Trim()
  }
  return $value
}

function Test-IsDefaultCertificateSubject {
  param([AllowNull()][string]$Subject = "")

  return [string]::Equals(
    (Get-CertificateSubjectCommonName -Subject $Subject),
    "WindowsAdminCenterSelfSigned",
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function Get-RequiredGeneratedCertificateDnsNames {
  $serviceHostname = if ([string]::IsNullOrWhiteSpace($ServiceFqdn)) { "localhost" } else { $ServiceFqdn }
  $names = @($EndpointFqdn, $env:COMPUTERNAME, $serviceHostname, "localhost") |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    ForEach-Object { ([string]$_).Trim() } |
    Sort-Object -Unique
  return @($names)
}

function Get-CertificateDnsNames {
  param([Parameter(Mandatory = $true)]$Certificate)

  $names = New-Object System.Collections.Generic.List[string]
  if ($Certificate.PSObject.Properties.Name -contains "DnsNameList") {
    foreach ($name in @($Certificate.DnsNameList)) {
      if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
        [void]$names.Add(([string]$name).Trim())
      }
    }
  }

  if ($Certificate.Subject -match "(^|,\s*)CN=([^,]+)") {
    [void]$names.Add($matches[2].Trim())
  }

  return @($names | Sort-Object -Unique)
}

function Test-CertificateDnsName {
  param(
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Name
  )

  $patternValue = $Pattern.Trim().ToLowerInvariant()
  $nameValue = $Name.Trim().ToLowerInvariant()
  if ($patternValue -eq $nameValue) { return $true }

  if ($patternValue.StartsWith("*.")) {
    $suffix = $patternValue.Substring(1)
    if ($nameValue.EndsWith($suffix) -and (($nameValue.Length - $suffix.Length) -gt 0)) {
      $prefix = $nameValue.Substring(0, $nameValue.Length - $suffix.Length)
      return ($prefix -notmatch "\.")
    }
  }

  return $false
}

function Test-CertificateHasUsablePrivateKey {
  param([Parameter(Mandatory = $true)]$Certificate)

  if (-not $Certificate.HasPrivateKey) { return $false }

  $rsa = $null
  try {
    $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($rsa) { return $true }
  } catch {
  } finally {
    if ($rsa) { $rsa.Dispose() }
  }

  $ecdsa = $null
  try {
    $ecdsa = [System.Security.Cryptography.X509Certificates.ECDsaCertificateExtensions]::GetECDsaPrivateKey($Certificate)
    return ($null -ne $ecdsa)
  } catch {
    return $false
  } finally {
    if ($ecdsa) { $ecdsa.Dispose() }
  }
}

function Test-CertificateHasServerAuthentication {
  param([Parameter(Mandatory = $true)]$Certificate)

  if (-not ($Certificate.PSObject.Properties.Name -contains "EnhancedKeyUsageList")) {
    return $false
  }

  foreach ($usage in @($Certificate.EnhancedKeyUsageList)) {
    $oidValue = if ($usage.PSObject.Properties.Name -contains "ObjectId") { [string]$usage.ObjectId } else { "" }
    $friendlyName = if ($usage.PSObject.Properties.Name -contains "FriendlyName") { [string]$usage.FriendlyName } else { "" }
    if ($oidValue -eq "1.3.6.1.5.5.7.3.1" -or $friendlyName -eq "Server Authentication") {
      return $true
    }
  }

  return $false
}

function Test-CertificateUsableForWac {
  param(
    [Parameter(Mandatory = $true)]$Certificate,
    [Parameter(Mandatory = $true)][string[]]$RequiredDnsNames
  )

  if (-not $Certificate.HasPrivateKey) { return $false }
  if (-not (Test-CertificateHasServerAuthentication -Certificate $Certificate)) { return $false }

  $certNames = @(Get-CertificateDnsNames -Certificate $Certificate)
  foreach ($requiredName in $RequiredDnsNames) {
    $matched = $false
    foreach ($certName in $certNames) {
      if (Test-CertificateDnsName -Pattern $certName -Name $requiredName) {
        $matched = $true
        break
      }
    }
    if (-not $matched) { return $false }
  }

  return $true
}

function Test-ReusableGeneratedCertificate {
  param([Parameter(Mandatory = $true)]$Certificate)

  return (
    $Certificate.Issuer -eq $Certificate.Subject -and
    $Certificate.FriendlyName -eq "Windows Admin Center Self-Signed Certificate" -and
    (Test-CertificateHasServerAuthentication -Certificate $Certificate) -and
    (Test-CertificateHasUsablePrivateKey -Certificate $Certificate)
  )
}

function Assert-SuppliedCertificateUsableForWac {
  param([Parameter(Mandatory = $true)]$Certificate)

  if (-not (Test-CertificateHasUsablePrivateKey -Certificate $Certificate)) {
    throw "Supplied certificate $($Certificate.Thumbprint) does not have an accessible private key."
  }
  if (-not (Test-CertificateHasServerAuthentication -Certificate $Certificate)) {
    throw "Supplied certificate $($Certificate.Thumbprint) is not valid for Server Authentication."
  }
  $gatewayHostname = if ([string]::IsNullOrWhiteSpace($EndpointFqdn)) { $env:COMPUTERNAME } else { $EndpointFqdn }
  $serviceHostname = if ([string]::IsNullOrWhiteSpace($ServiceFqdn)) { "localhost" } else { $ServiceFqdn }
  $requiredNames = @($gatewayHostname, $serviceHostname) |
    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
    Sort-Object -Unique
  if (-not (Test-CertificateUsableForWac -Certificate $Certificate -RequiredDnsNames $requiredNames)) {
    throw "Supplied certificate $($Certificate.Thumbprint) does not cover required WAC names: $($requiredNames -join ', ')."
  }
}

function Write-CertificateDiagnostics {
  param([Parameter(Mandatory = $true)]$Certificate)

  $dnsNames = @(Get-CertificateDnsNames -Certificate $Certificate) -join ", "
  if ([string]::IsNullOrWhiteSpace($dnsNames)) { $dnsNames = "<none>" }
  Write-Log "Certificate selected: Thumbprint=$($Certificate.Thumbprint) Subject=$($Certificate.Subject)"
  Write-Log "Certificate DNS names: $dnsNames"
}

function Get-OrCreateCertificate {
  if (-not [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    $cert = Get-Item -LiteralPath ("Cert:\LocalMachine\My\{0}" -f $CertificateThumbprint) -ErrorAction Stop
    Assert-SuppliedCertificateUsableForWac -Certificate $cert
    Write-Log "Using supplied certificate thumbprint $($cert.Thumbprint)"
    return $cert
  }

  $effectiveSubject = Get-EffectiveCertificateSubject
  $subject = if ($effectiveSubject.StartsWith("CN=")) { $effectiveSubject } else { "CN=$effectiveSubject" }
  $requiredNames = Get-RequiredGeneratedCertificateDnsNames
  $cert = Get-ChildItem Cert:\LocalMachine\My\* -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date).AddDays(7) } |
    Where-Object { Test-ReusableGeneratedCertificate -Certificate $_ } |
    Where-Object { Test-CertificateUsableForWac -Certificate $_ -RequiredDnsNames $requiredNames } |
    Sort-Object NotAfter -Descending |
    Select-Object -First 1

  if ($cert) {
    Write-Log "Reusing self-signed certificate $($cert.Thumbprint)"
    return $cert
  }

  $staleCert = Get-ChildItem Cert:\LocalMachine\My\* -ErrorAction SilentlyContinue |
    Where-Object { $_.Subject -eq $subject -and $_.NotAfter -gt (Get-Date).AddDays(7) } |
    Where-Object { Test-ReusableGeneratedCertificate -Certificate $_ } |
    Select-Object -First 1
  if ($staleCert) {
    Write-Log "Existing certificate $($staleCert.Thumbprint) does not cover required WAC names; creating a new one" "WARN"
  }

  Write-Log "Creating self-signed certificate for $EndpointFqdn"
  $newCertSubject = if ($effectiveSubject.StartsWith("CN=")) { $effectiveSubject } else { "CN=$effectiveSubject" }
  $keySecurity = New-Object System.Security.AccessControl.FileSecurity
  $keySecurity.SetSecurityDescriptorSddlForm("O:SYG:SYD:AI(A;;GAGR;;;SY)(A;;GAGR;;;NS)(A;;GAGR;;;BA)(A;;GR;;;BU)")
  $certArgs = @{
    Subject           = $newCertSubject
    DnsName           = $requiredNames
    FriendlyName      = "Windows Admin Center Self-Signed Certificate"
    KeyAlgorithm      = "RSA"
    KeyLength         = 2048
    KeyUsage          = "DigitalSignature", "KeyEncipherment"
    TextExtension     = "2.5.29.37={text}1.3.6.1.5.5.7.3.1", "2.5.29.19={text}CA=false"
    HashAlgorithm     = "SHA256"
    Provider          = "Microsoft Enhanced RSA and AES Cryptographic Provider"
    CertStoreLocation = "Cert:\LocalMachine\My"
    NotAfter          = (Get-Date).AddDays(60)
    SecurityDescriptor = $keySecurity
  }
  $cert = New-SelfSignedCertificate @certArgs
  return $cert
}

function Ensure-TrustedCertificate {
  param([Parameter(Mandatory = $true)]$Certificate)

  $rootPath = "Cert:\LocalMachine\Root\{0}" -f $Certificate.Thumbprint
  $trusted = Get-Item -LiteralPath $rootPath -ErrorAction SilentlyContinue
  if ($trusted) {
    Write-Log "Certificate already trusted in LocalMachine Root: $($Certificate.Thumbprint)"
    return
  }

  Write-Log "Trusting certificate in LocalMachine Root: $($Certificate.Thumbprint)"
  $tmp = Join-Path $env:TEMP ("wac-{0}.cer" -f $Certificate.Thumbprint)
  try {
    Export-Certificate -Cert $Certificate -FilePath $tmp -Type CERT | Out-Null
    Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop | Out-Null
    $trusted = Get-Item -LiteralPath $rootPath -ErrorAction SilentlyContinue
    if (-not $trusted) {
      throw "Certificate was imported but is not visible in LocalMachine Root: $($Certificate.Thumbprint)"
    }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Get-CertificateCommonName {
  param([Parameter(Mandatory = $true)]$Certificate)

  if ($Certificate.Subject -match "(^|,\s*)CN=([^,]+)") {
    return $matches[2]
  }

  return $Certificate.Subject
}

function Grant-CertificatePrivateKeyAcl {
  param([Parameter(Mandatory = $true)]$Certificate)

  Write-Log "Granting NETWORK SERVICE access to certificate private key"
  $paths = New-Object System.Collections.Generic.List[string]
  $foundCandidates = 0

  function Add-PrivateKeyPathCandidate {
    param([Parameter(Mandatory = $true)][string]$Name)

    $trimmed = $Name.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) { return }
    [void]$paths.Add((Join-Path $env:ProgramData "Microsoft\Crypto\RSA\MachineKeys\$trimmed"))
    [void]$paths.Add((Join-Path $env:ProgramData "Microsoft\Crypto\Keys\$trimmed"))
  }

  $rsaKey = $null
  try {
    $rsaKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Certificate)
    if ($rsaKey -is [System.Security.Cryptography.RSACryptoServiceProvider]) {
      Add-PrivateKeyPathCandidate -Name $rsaKey.CspKeyContainerInfo.UniqueKeyContainerName
    } else {
      $keyProperty = $rsaKey.PSObject.Properties["Key"]
      if ($keyProperty -and $rsaKey.Key -and $rsaKey.Key.UniqueName) {
        Add-PrivateKeyPathCandidate -Name $rsaKey.Key.UniqueName
      }
    }
  } catch {
    Write-Log ("Could not resolve certificate private key via .NET API: {0}" -f $_.Exception.Message) "WARN"
  } finally {
    if ($rsaKey -and ($rsaKey -is [System.IDisposable])) {
      $rsaKey.Dispose()
    }
  }

  try {
    $keyName = $Certificate.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName
    if ($keyName) {
      Add-PrivateKeyPathCandidate -Name $keyName
    }
  } catch {}

  try {
    $certutil = Invoke-LoggedProcess -FilePath "certutil.exe" -ArgumentList @("-store", "My", $Certificate.Thumbprint) -LogOutputOnSuccess:$false
    foreach ($line in ($certutil.StdOut -split "`r?`n")) {
      if ($line -match "(?:Unique container name|Уникальное имя контейнера)\s*:\s*(.+)$") {
        Add-PrivateKeyPathCandidate -Name $matches[1]
      } elseif ($line -match "(?:Key Container|Контейнер ключа)\s*=\s*(.+)$") {
        Add-PrivateKeyPathCandidate -Name $matches[1]
      }
    }
  } catch {}

  if ($paths.Count -eq 0) {
    Write-Log "Could not resolve certificate private key file from certificate APIs or certutil output." "WARN"
  }

  foreach ($path in ($paths | Select-Object -Unique)) {
    if (Test-Path -LiteralPath $path) {
      [void](Invoke-LoggedProcess -FilePath "icacls.exe" -ArgumentList @($path, "/grant", "*S-1-5-20:R") -LogOutputOnSuccess:$false)
      $foundCandidates++
    }
  }

  if ($foundCandidates -eq 0) {
    Write-Log "No certificate private key ACL was changed; HTTPS may fail with Schannel 0x8009030D." "WARN"
  }
}

function Configure-AppSettings {
  param(
    [Parameter(Mandatory = $true)][string]$AppSettingsPath,
    [Parameter(Mandatory = $true)]$Certificate
  )

  Write-Log "Configuring appsettings.json"
  $json = Read-WacAppSettingsJson -AppSettingsPath $AppSettingsPath
  $certSubject = Get-CertificateCommonName -Certificate $Certificate
  $service0 = "https://{0}:{1}" -f $ServiceFqdn, $ServicePortStart
  $service1 = "https://{0}:{1}" -f $ServiceFqdn, ($ServicePortStart + 1)

  Set-JsonValue $json @("Kestrel", "Endpoints", "WindowsAdminCenter", "Url") "https://*:$Port"
  Set-JsonValue $json @("Kestrel", "Endpoints", "WindowsAdminCenter", "Certificate", "Subject") $certSubject
  Set-JsonValue $json @("Kestrel", "Endpoints", "WindowsAdminCenter", "Certificate", "Thumbprint") $Certificate.Thumbprint
  if ([string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
    Set-JsonValue $json @("Kestrel", "Endpoints", "WindowsAdminCenter", "Certificate", "AllowInvalid") $true
    Set-JsonValue $json @("WindowsAdminCenter", "ServiceCertificate", "AllowInvalid") $true
  }
  Set-JsonValue $json @("WindowsAdminCenter", "ServiceCertificate", "Subject") $certSubject
  Set-JsonValue $json @("WindowsAdminCenter", "ServiceCertificate", "Thumbprint") $Certificate.Thumbprint
  Set-JsonValue $json @("WindowsAdminCenter", "Http", "EndpointFqdn") $EndpointFqdn
  Set-JsonValue $json @("WindowsAdminCenter", "Http", "ServiceFqdn") $ServiceFqdn
  Set-JsonValue $json @("WindowsAdminCenter", "Http", "HttpSysUrls") @("https://+:$Port")
  Set-JsonValue $json @("WindowsAdminCenter", "System", "RuntimeMode") "Service"
  Set-JsonValue $json @("WindowsAdminCenter", "System", "InstallationType") "Standard"
  Set-JsonValue $json @("WindowsAdminCenter", "System", "OperationMode") "Production"
  Set-JsonValue $json @("WindowsAdminCenter", "System", "TokenAuthenticationMode") "FormLogin"
  Set-JsonValue $json @("WindowsAdminCenter", "System", "SoftwareUpdate") $SoftwareUpdateMode
  Set-JsonValue $json @("WindowsAdminCenter", "System", "TelemetryPrivacy") $DiagnosticDataMode
  Set-JsonValue $json @("WindowsAdminCenter", "System", "InstallDate") (Get-Date -Format "yyyyMMdd")
  Set-JsonValue $json @("WindowsAdminCenter", "System", "FileVersion") ((Get-Item -LiteralPath $InstallerPath).VersionInfo.ProductVersion)
  $nuGetVersion = Get-WacAppSettingsNuGetVersion -AppSettings $json -Fallback "2.6.6"
  Set-JsonValue $json @("WindowsAdminCenter", "System", "NuGetVersion") $nuGetVersion
  Set-JsonValue $json @("WindowsAdminCenter", "FileSystem", "ProgramDataPath") $DataDir
  Set-JsonValue $json @("WindowsAdminCenter", "FileSystem", "ProgramFilesPath") $InstallDir
  Set-JsonValue $json @("WindowsAdminCenter", "ServicePortRange", "Start") $ServicePortStart
  Set-JsonValue $json @("WindowsAdminCenter", "ServicePortRange", "End") $ServicePortEnd
  Set-JsonValue $json @("WindowsAdminCenter", "FeatureParameters", "Base", "WinRmOverHttps") ($WinRmHttpsMode -eq "Enable")
  Set-JsonValue $json @("WindowsAdminCenter", "Services", 0, "Endpoint") $service0
  Set-JsonValue $json @("WindowsAdminCenter", "Services", 1, "Endpoint") $service1

  $json | ConvertTo-Json -Depth 100 | Set-Content -LiteralPath $AppSettingsPath -Encoding UTF8
}

function Register-HttpSys {
  param([Parameter(Mandatory = $true)]$Certificate)

  Write-Log "Registering HTTP.SYS for port $Port"
  Remove-HttpSysBinding -BindingPort $Port
  [void](Invoke-LoggedProcess -FilePath "netsh.exe" -ArgumentList @("http", "add", "sslcert", "ipport=0.0.0.0:$Port", "certhash=$($Certificate.Thumbprint)", "appid=$script:AppId") -LogOutputOnSuccess:$false)
  [void](Invoke-LoggedProcess -FilePath "netsh.exe" -ArgumentList @("http", "add", "urlacl", "url=https://+:$Port/", "sddl=D:(A;;GX;;;NS)") -LogOutputOnSuccess:$false)
}

function Register-Firewall {
  Write-Log "Registering firewall rules"
  Get-NetFirewallRule -DisplayName "Windows Admin Center*" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue

  if ($NetworkAccess -eq "LocalOnly") {
    Write-Log "NetworkAccess=LocalOnly; skipping inbound Windows Admin Center firewall rules"
    return
  }

  $remoteAddress = if ($NetworkAccess -eq "LocalSubnet") { "LocalSubnet" } else { "Any" }
  Write-Log "NetworkAccess=$NetworkAccess RemoteAddress=$remoteAddress"
  New-NetFirewallRule -DisplayName "Windows Admin Center HTTPS $Port" -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -RemoteAddress $remoteAddress | Out-Null
  New-NetFirewallRule -DisplayName "Windows Admin Center service ports $ServicePortStart-$ServicePortEnd" -Direction Inbound -Action Allow -Protocol TCP -LocalPort "$ServicePortStart-$ServicePortEnd" -RemoteAddress $remoteAddress | Out-Null
}

function Set-WinRmTrustedHostsMode {
  if ($TrustedHostsMode -eq "NotConfigureTrustedHosts") {
    Write-Log "Leaving WinRM TrustedHosts unchanged"
    return
  }

  $policyPath = "HKLM:\Software\Policies\Microsoft\Windows\WinRM\Client"
  $trustedHostsPolicy = Get-ItemProperty -Path $policyPath -Name TrustedHosts -ErrorAction SilentlyContinue
  if ($trustedHostsPolicy) {
    Write-Log "WinRM TrustedHosts is controlled by policy; leaving it unchanged" "WARN"
    return
  }

  Write-Log "Configuring WinRM TrustedHosts=*"
  $current = Get-WinRmTrustedHostsValue
  if ($current -ne "*") {
    $script:PreviousTrustedHosts = $current
  }
  Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value "*" -Force
}

function Get-WinRmTrustedHostsValue {
  try {
    return [string](Get-Item -Path WSMan:\localhost\Client\TrustedHosts -ErrorAction Stop).Value
  } catch {
    Write-Log ("Could not read WinRM TrustedHosts: {0}" -f $_.Exception.Message) "WARN"
    return $null
  }
}

function Restore-WinRmTrustedHosts {
  param([AllowNull()][string]$PreviousValue)

  if ($null -eq $PreviousValue) {
    Write-Log "TrustedHosts backup is not available; leaving current value unchanged" "WARN"
    return
  }

  $current = Get-WinRmTrustedHostsValue
  if ($current -ne "*") {
    Write-Log "TrustedHosts changed after setup; leaving current value unchanged" "WARN"
    return
  }

  Write-Log "Restoring WinRM TrustedHosts to previous value"
  Set-Item -Path WSMan:\localhost\Client\TrustedHosts -Value $PreviousValue -Force
}

function Get-WinRmCommandPath {
  $command = Get-Command "winrm.cmd" -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  $command = Get-Command "winrm" -ErrorAction SilentlyContinue
  if ($command) { return $command.Source }

  throw "WinRM command-line tool was not found. Expected winrm.cmd in the Windows system directory."
}

function Set-WinRmHttpsMode {
  param([Parameter(Mandatory = $true)]$Certificate)

  if ($WinRmHttpsMode -eq "Disable") {
    Write-Log "WinRM over HTTPS disabled in WAC configuration; existing WinRM HTTPS listeners are left unchanged"
    return
  }

  Write-Log "Configuring WinRM HTTPS listener on port 5986"
  $hostname = if ([string]::IsNullOrWhiteSpace($EndpointFqdn)) { $env:COMPUTERNAME } else { $EndpointFqdn }
  $listenerResource = "winrm/config/Listener?Address=*+Transport=HTTPS"
  $winrm = Get-WinRmCommandPath
  [void](Invoke-LoggedProcess -FilePath $winrm -ArgumentList @("delete", $listenerResource) -LogOutputOnSuccess:$false)
  $createResult = Invoke-LoggedProcess -FilePath $winrm -ArgumentList @("create", $listenerResource, "@{Hostname=`"$hostname`";CertificateThumbprint=`"$($Certificate.Thumbprint)`"}") -LogOutputOnSuccess:$false
  if ($createResult.ExitCode -ne 0) {
    throw "Failed to create WinRM HTTPS listener with certificate $($Certificate.Thumbprint). See $script:LogPath"
  }

  Get-NetFirewallRule -DisplayName "Windows Remote Management HTTPS*" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
  New-NetFirewallRule -DisplayName "Windows Remote Management HTTPS 5986" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 5986 | Out-Null
}

function Register-Services {
  $svcExe = Join-Path $InstallDir "Service\WindowsAdminCenter.exe"
  $accountExe = Join-Path $InstallDir "Service\WindowsAdminCenterAccountManagement.exe"

  Write-Log "Registering services"
  [void](Invoke-LoggedProcess -FilePath "sc.exe" -ArgumentList @("create", $script:ServiceName, "type=", "own", "start=", "auto", "depend=", "winrm", "obj=", "NT AUTHORITY\NetworkService", "binPath=", "`"$svcExe`"", "DisplayName=", "Windows Admin Center") -LogOutputOnSuccess:$false)
  [void](Invoke-LoggedProcess -FilePath "sc.exe" -ArgumentList @("description", $script:ServiceName, "Manage remote Windows computers from web service.") -LogOutputOnSuccess:$false)

  [void](Invoke-LoggedProcess -FilePath "sc.exe" -ArgumentList @("create", $script:AccountServiceName, "type=", "own", "start=", "demand", "binPath=", "`"$accountExe`"", "DisplayName=", "Windows Admin Center Account Management") -LogOutputOnSuccess:$false)
  [void](Invoke-LoggedProcess -FilePath "sc.exe" -ArgumentList @("description", $script:AccountServiceName, "Manage AAD token and account for Windows Admin Center.") -LogOutputOnSuccess:$false)
  [void](Invoke-LoggedProcess -FilePath "sc.exe" -ArgumentList @("sdset", $script:AccountServiceName, "D:(A;;CCLCSWRPWPLO;;;NS)(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)S:(AU;FA;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;WD)") -LogOutputOnSuccess:$false)
}

function Unregister-UpdaterScheduledTask {
  $task = Get-ScheduledTask -TaskName $script:UpdaterScheduledTaskName -ErrorAction SilentlyContinue
  if (-not $task) { return }

  Write-Log "Unregistering Windows Admin Center updater scheduled task"
  Stop-ScheduledTask -TaskName $script:UpdaterScheduledTaskName -ErrorAction SilentlyContinue
  Unregister-ScheduledTask -TaskName $script:UpdaterScheduledTaskName -Confirm:$false -ErrorAction Stop
}

function Copy-UpdaterFiles {
  $serviceDir = Join-Path $InstallDir "Service"
  $updaterDir = Join-Path $DataDir "Updater"
  $updaterExe = Join-Path $serviceDir "WindowsAdminCenterUpdater.exe"
  if (-not (Test-Path -LiteralPath $updaterExe)) {
    Write-Log "WindowsAdminCenterUpdater.exe not found; skipping updater scheduled task" "WARN"
    return $false
  }

  Write-Log "Copying Windows Admin Center updater files"
  New-Item -ItemType Directory -Path $updaterDir -Force | Out-Null
  Copy-Item -Path (Join-Path $serviceDir "*") -Destination $updaterDir -Recurse -Force -Exclude @("WindowsAdminCenter.exe", "WindowsAdminCenterAccountManagement.exe", "WindowsAdminCenterLauncher.exe", "efbundle.exe")
  Copy-Item -LiteralPath $updaterExe -Destination $updaterDir -Force
  return $true
}

function Register-UpdaterScheduledTask {
  $updaterExe = Join-Path (Join-Path $DataDir "Updater") "WindowsAdminCenterUpdater.exe"
  if (-not (Test-Path -LiteralPath $updaterExe)) {
    Write-Log "WindowsAdminCenterUpdater.exe not found in updater data directory; skipping scheduled task" "WARN"
    return
  }

  Unregister-UpdaterScheduledTask
  Write-Log "Registering Windows Admin Center updater scheduled task"
  $action = New-ScheduledTaskAction -Execute ([System.IO.Path]::GetFullPath($updaterExe))
  Register-ScheduledTask -TaskName $script:UpdaterScheduledTaskName -Action $action -User "SYSTEM" -RunLevel Highest -Force | Out-Null

  $scheduler = New-Object -ComObject Schedule.Service
  $scheduler.Connect()
  $task = $scheduler.GetFolder("\").GetTask($script:UpdaterScheduledTaskName)
  $task.SetSecurityDescriptor($script:UpdaterScheduledTaskSecurityDescriptor, 0)
}

function Initialize-Database {
  $serviceDir = Join-Path $InstallDir "Service"
  $efBundle = Join-Path $serviceDir "efbundle.exe"
  if (-not (Test-Path -LiteralPath $efBundle)) {
    Write-Log "efbundle.exe not found; skipping database initialization" "WARN"
    return
  }

  Write-Log "Initializing WAC database"
  $result = Invoke-LoggedProcess -FilePath $efBundle -WorkingDirectory $serviceDir -LogOutputOnSuccess:$false
  if ($result.ExitCode -ne 0) {
    throw "efbundle.exe failed with exit code $($result.ExitCode). See $script:LogPath"
  }
}

function Test-TcpPort {
  param([int]$TcpPort)
  try {
    $client = New-Object System.Net.Sockets.TcpClient
    $async = $client.BeginConnect("127.0.0.1", $TcpPort, $null, $null)
    $ok = $async.AsyncWaitHandle.WaitOne(3000, $false)
    if ($ok) { $client.EndConnect($async) }
    $client.Close()
    return $ok
  } catch {
    return $false
  }
}

function Get-WacSetupMarkerPath {
  param([string]$MarkerDataDir = $DataDir)
  return [System.IO.Path]::Combine($MarkerDataDir, "wac-setup.json")
}

function Read-WacSetupMarker {
  param([string]$MarkerDataDir = $DataDir)

  $path = Get-WacSetupMarkerPath -MarkerDataDir $MarkerDataDir
  if (-not (Test-Path -LiteralPath $path)) { return $null }
  try {
    $marker = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($marker.installedBy -ne "wac-client-windows-setup") { return $null }
    return $marker
  } catch {
    Write-Log ("Could not read setup marker {0}: {1}" -f $path, $_.Exception.Message) "WARN"
    return $null
  }
}

function Get-WacMarkerValue {
  param(
    [AllowNull()]$Marker,
    [Parameter(Mandatory = $true)][string]$Name
  )

  if ($null -eq $Marker) { return $null }
  if ($Marker.PSObject.Properties.Name -notcontains $Name) { return $null }
  return $Marker.$Name
}

function Apply-WacSetupMarkerDefaults {
  param($Marker)

  if ($null -eq $Marker) { return }
  if (-not $script:OriginalBoundParameters.ContainsKey("InstallDir") -and $Marker.installDir) { Set-Variable -Name InstallDir -Scope Script -Value ([string]$Marker.installDir) }
  if (-not $script:OriginalBoundParameters.ContainsKey("DataDir") -and $Marker.dataDir) { Set-Variable -Name DataDir -Scope Script -Value ([string]$Marker.dataDir) }
  if (-not $script:OriginalBoundParameters.ContainsKey("Port") -and $Marker.port) { Set-Variable -Name Port -Scope Script -Value ([int]$Marker.port) }
  if (-not $script:OriginalBoundParameters.ContainsKey("ServicePortStart") -and $Marker.servicePortStart) { Set-Variable -Name ServicePortStart -Scope Script -Value ([int]$Marker.servicePortStart) }
  if (-not $script:OriginalBoundParameters.ContainsKey("ServicePortEnd") -and $Marker.servicePortEnd) { Set-Variable -Name ServicePortEnd -Scope Script -Value ([int]$Marker.servicePortEnd) }
  if (-not $script:OriginalBoundParameters.ContainsKey("EndpointFqdn") -and $Marker.endpointFqdn) { Set-Variable -Name EndpointFqdn -Scope Script -Value ([string]$Marker.endpointFqdn) }
  if (-not $script:OriginalBoundParameters.ContainsKey("ServiceFqdn") -and $Marker.serviceFqdn) { Set-Variable -Name ServiceFqdn -Scope Script -Value ([string]$Marker.serviceFqdn) }
  if (-not $script:OriginalBoundParameters.ContainsKey("CertificateThumbprint") -and $Marker.certificateThumbprint) { Set-Variable -Name CertificateThumbprint -Scope Script -Value ([string]$Marker.certificateThumbprint) }
  if (-not $script:OriginalBoundParameters.ContainsKey("CertificateSubject") -and $Marker.certificateSubject) { Set-Variable -Name CertificateSubject -Scope Script -Value ([string]$Marker.certificateSubject) }
  if (-not $script:OriginalBoundParameters.ContainsKey("TrustSelfSignedCertificate") -and $Marker.trustSelfSignedCertificate) { Set-Variable -Name TrustSelfSignedCertificate -Scope Script -Value ([bool]$Marker.trustSelfSignedCertificate) }
  if (-not $script:OriginalBoundParameters.ContainsKey("SoftwareUpdateMode") -and $Marker.softwareUpdateMode) { Set-Variable -Name SoftwareUpdateMode -Scope Script -Value ([string]$Marker.softwareUpdateMode) }
  if (-not $script:OriginalBoundParameters.ContainsKey("DiagnosticDataMode") -and $Marker.diagnosticDataMode) { Set-Variable -Name DiagnosticDataMode -Scope Script -Value ([string]$Marker.diagnosticDataMode) }
  if (-not $script:OriginalBoundParameters.ContainsKey("NetworkAccess") -and $Marker.networkAccess) { Set-Variable -Name NetworkAccess -Scope Script -Value ([string]$Marker.networkAccess) }
  if (-not $script:OriginalBoundParameters.ContainsKey("TrustedHostsMode") -and $Marker.trustedHostsMode) { Set-Variable -Name TrustedHostsMode -Scope Script -Value ([string]$Marker.trustedHostsMode) }
  if (-not $script:OriginalBoundParameters.ContainsKey("WinRmHttpsMode") -and $Marker.winRmHttpsMode) { Set-Variable -Name WinRmHttpsMode -Scope Script -Value ([string]$Marker.winRmHttpsMode) }
  if (-not $script:OriginalBoundParameters.ContainsKey("SkipPsRemoting") -and $Marker.skipPsRemoting) { Set-Variable -Name SkipPsRemoting -Scope Script -Value ([bool]$Marker.skipPsRemoting) }
  if (-not $script:OriginalBoundParameters.ContainsKey("KeepExistingData") -and $Marker.keepExistingData) { Set-Variable -Name KeepExistingData -Scope Script -Value ([bool]$Marker.keepExistingData) }
  if (-not $script:OriginalBoundParameters.ContainsKey("SkipArchitectureCheck") -and $Marker.architectureOverride) { Set-Variable -Name SkipArchitectureCheck -Scope Script -Value ([bool]$Marker.architectureOverride) }
}

function Write-WacSetupMarker {
  param(
    [string]$ProductVersion = "",
    [string]$CertificateHash = ""
  )

  New-Item -ItemType Directory -Path $DataDir -Force | Out-Null
  $markerPath = Get-WacSetupMarkerPath
  $marker = [ordered]@{
    markerVersion = 1
    installedBy = "wac-client-windows-setup"
    installedAt = (Get-Date).ToString("o")
    productVersion = $ProductVersion
    installDir = $InstallDir
    dataDir = $DataDir
    port = $Port
    servicePortStart = $ServicePortStart
    servicePortEnd = $ServicePortEnd
    endpointFqdn = $EndpointFqdn
    serviceFqdn = $ServiceFqdn
    certificateThumbprint = $CertificateHash
    certificateSubject = Get-EffectiveCertificateSubject
    trustSelfSignedCertificate = [bool]$TrustSelfSignedCertificate
    softwareUpdateMode = $SoftwareUpdateMode
    diagnosticDataMode = $DiagnosticDataMode
    networkAccess = $NetworkAccess
    trustedHostsMode = $TrustedHostsMode
    previousTrustedHosts = $script:PreviousTrustedHosts
    winRmHttpsMode = $WinRmHttpsMode
    skipPsRemoting = [bool]$SkipPsRemoting
    keepExistingData = [bool]$KeepExistingData
    architectureOverride = [bool]$SkipArchitectureCheck
  }
  $marker | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $markerPath -Encoding UTF8
  Write-Log "Wrote setup marker: $markerPath"
}

function Remove-WacSetupMarker {
  $markerPath = Get-WacSetupMarkerPath
  Remove-Item -LiteralPath $markerPath -Force -ErrorAction SilentlyContinue
}

function Remove-WacFirewallRules {
  Write-Log "Removing Windows Admin Center firewall rules"
  Get-NetFirewallRule -DisplayName "Windows Admin Center*" -ErrorAction SilentlyContinue |
    Remove-NetFirewallRule -ErrorAction SilentlyContinue
}

function Invoke-WacUninstall {
  Write-Log "Uninstalling Windows Admin Center" "STEP"
  Stop-And-DeleteService $script:ServiceName
  Stop-And-DeleteService $script:AccountServiceName
  Unregister-UpdaterScheduledTask
  Remove-HttpSysBinding -BindingPort $Port
  Remove-WacFirewallRules
  $previousTrustedHosts = Get-WacMarkerValue -Marker $setupMarker -Name "previousTrustedHosts"
  Restore-WinRmTrustedHosts -PreviousValue $previousTrustedHosts

  Write-Log "Removing install directory: $InstallDir"
  Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue

  if ($PurgeData) {
    Write-Log "Removing WAC data directory: $DataDir" "WARN"
    Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue
  } else {
    Write-Log "Keeping WAC data directory: $DataDir"
    Remove-WacSetupMarker
  }
}

try {
  Assert-Admin

  $setupMarker = Read-WacSetupMarker -MarkerDataDir $DataDir
  if ($setupMarker) {
    Apply-WacSetupMarkerDefaults -Marker $setupMarker
    $existingPreviousTrustedHosts = Get-WacMarkerValue -Marker $setupMarker -Name "previousTrustedHosts"
    if ($null -ne $existingPreviousTrustedHosts) { $script:PreviousTrustedHosts = [string]$existingPreviousTrustedHosts }
  }

  if ($Uninstall) {
    Write-Log "InstallDir=$InstallDir" "STEP"
    Write-Log "DataDir=$DataDir"
    Write-Log "Port=$Port PurgeData=$([bool]$PurgeData)"
    if ($PSCmdlet.ShouldProcess($InstallDir, "Uninstall Windows Admin Center")) {
      Invoke-WacUninstall
    }
    Write-Host ""
    Write-UserText "UninstallComplete"
    Write-UserText "LogPath" @($script:LogPath)
    Wait-IfRequested
    return
  }

  Test-TargetArchitecture

  if ([string]::IsNullOrWhiteSpace($InstallerPath)) { $InstallerPath = Get-DefaultInstallerPath }
  if ([string]::IsNullOrWhiteSpace($InstallerPath)) { $InstallerPath = Get-CachedWacInstaller }
  if ([string]::IsNullOrWhiteSpace($InstallerPath)) { $InstallerPath = Save-WacInstallerFromWinget }
  if ([string]::IsNullOrWhiteSpace($InstallerPath)) { $InstallerPath = Save-WacInstallerFromAkaMs }
  if ([string]::IsNullOrWhiteSpace($InstallerPath) -or -not (Test-Path -LiteralPath $InstallerPath)) {
    throw "Windows Admin Center installer was not found locally and download failed. Pass -InstallerPath."
  }
  $InstallerPath = (Resolve-Path -LiteralPath $InstallerPath).Path

  if ([string]::IsNullOrWhiteSpace($ExtractOut)) {
    $ExtractOut = Join-Path $env:ProgramData "WACSetup\payload"
  }

  Write-Log "InstallerPath=$InstallerPath" "STEP"
  Write-Log "ExtractOut=$ExtractOut"
  Write-Log "InstallDir=$InstallDir"
  Write-Log "DataDir=$DataDir"
  Write-Log "Port=$Port ServicePortRange=$ServicePortStart-$ServicePortEnd EndpointFqdn=$EndpointFqdn ServiceFqdn=$ServiceFqdn"
  Write-Log "SoftwareUpdateMode=$SoftwareUpdateMode DiagnosticDataMode=$DiagnosticDataMode NetworkAccess=$NetworkAccess TrustedHostsMode=$TrustedHostsMode WinRmHttpsMode=$WinRmHttpsMode"
  Write-Log ("Language={0}" -f $script:Language)
  Write-UserText "RunningInstaller"

  $sig = Get-AuthenticodeSignature -LiteralPath $InstallerPath
  Write-Log "Installer signature status: $($sig.Status)"
  if ($sig.Status -ne "Valid") { throw "Installer signature is not valid: $($sig.StatusMessage)" }
  if ($null -eq $sig.SignerCertificate -or $sig.SignerCertificate.Subject -notmatch "(^|,\s*)O=Microsoft Corporation(,|$)") {
    throw "Installer signature is valid, but the signer is not Microsoft Corporation."
  }
  Write-Log "Installer signature signer: $($sig.SignerCertificate.Subject)"

  if (-not $SkipExtraction) {
    if ([string]::IsNullOrWhiteSpace($InnoExtractPath)) { $InnoExtractPath = Get-DefaultInnoExtractPath }
    if ([string]::IsNullOrWhiteSpace($InnoExtractPath)) { $InnoExtractPath = Save-InnoExtract }
    if ([string]::IsNullOrWhiteSpace($InnoExtractPath) -or -not (Test-Path -LiteralPath $InnoExtractPath)) {
      throw "innoextract.exe not found locally and download failed. Put it next to this script or pass -InnoExtractPath."
    }
    $InnoExtractPath = (Resolve-Path -LiteralPath $InnoExtractPath).Path
    Write-Log "Extracting installer payload with $InnoExtractPath" "STEP"
    New-Item -ItemType Directory -Path $ExtractOut -Force | Out-Null
    $extractResult = Invoke-LoggedProcess -FilePath $InnoExtractPath -ArgumentList @("--silent", "--output-dir", $ExtractOut, $InstallerPath)
    if ($extractResult.ExitCode -eq -1073741515) { throw (Get-Text "InnoExtractDllFailure") }
    if ($extractResult.ExitCode -ne 0) { throw "innoextract failed with exit code $($extractResult.ExitCode)" }
  }

  $payloadApp = Join-Path $ExtractOut "app"
  $payloadData = Join-Path $ExtractOut "commonappdata\WindowsAdminCenter"
  $payloadSvc = Join-Path $payloadApp "Service\WindowsAdminCenter.exe"
  if (-not (Test-Path -LiteralPath $payloadSvc)) {
    throw "Extracted payload is incomplete. Missing: $payloadSvc"
  }

  if ($PSCmdlet.ShouldProcess($InstallDir, "Install Windows Admin Center")) {
    Write-Log "Stopping/removing previous WAC services and bindings" "STEP"
    Stop-And-DeleteService $script:ServiceName
    Stop-And-DeleteService $script:AccountServiceName
    Unregister-UpdaterScheduledTask
    Remove-HttpSysBinding -BindingPort $Port

    Write-Log "Copying files" "STEP"
    if (-not $KeepExistingData) {
      Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
      Remove-Item -LiteralPath $DataDir -Recurse -Force -ErrorAction SilentlyContinue
    } else {
      Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $InstallDir, $DataDir -Force | Out-Null
    Copy-DirectoryContents -Source $payloadApp -Destination $InstallDir
    if ((-not $KeepExistingData) -and (Test-Path -LiteralPath $payloadData)) {
      Copy-DirectoryContents -Source $payloadData -Destination $DataDir
    }
    New-Item -ItemType Directory -Path (Join-Path $DataDir "Logs"), (Join-Path $DataDir "Database"), (Join-Path $DataDir "Updater") -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $DataDir "Logs\Configuration.log") -Force | Out-Null

    Grant-DirectoryAcl -Path $InstallDir
    Grant-DirectoryAcl -Path $DataDir

    try { New-EventLog -LogName Application -Source "WAC-Configuration" -ErrorAction SilentlyContinue } catch {}

    $cert = Get-OrCreateCertificate
    Write-CertificateDiagnostics -Certificate $cert
    if ($TrustSelfSignedCertificate -and [string]::IsNullOrWhiteSpace($CertificateThumbprint)) {
      Ensure-TrustedCertificate -Certificate $cert
    }
    Grant-CertificatePrivateKeyAcl -Certificate $cert
    Configure-AppSettings -AppSettingsPath (Join-Path $InstallDir "Service\appsettings.json") -Certificate $cert
    Register-HttpSys -Certificate $cert
    Register-Firewall

    if (-not $SkipPsRemoting) {
      Write-Log "Enabling PowerShell remoting" "STEP"
      Enable-PSRemoting -SkipNetworkProfileCheck -Force
      Set-Service -Name WinRM -StartupType Automatic
      Start-Service -Name WinRM
      Set-WinRmTrustedHostsMode
      Set-WinRmHttpsMode -Certificate $cert
    } else {
      if ($TrustedHostsMode -eq "ConfigureTrustedHosts") {
        Write-Log "Skipping TrustedHosts configuration because PowerShell Remoting step is disabled" "WARN"
      }
      if ($WinRmHttpsMode -eq "Enable") {
        Write-Log "Skipping WinRM HTTPS listener because PowerShell Remoting step is disabled" "WARN"
      }
    }

    Initialize-Database
    if (Copy-UpdaterFiles) {
      Register-UpdaterScheduledTask
    }
    Register-Services

    Write-Log "Starting WindowsAdminCenter service" "STEP"
    Start-Service -Name $script:ServiceName
    $svc = Wait-WacServiceRunning -Name $script:ServiceName
    Write-Log "Service status: $($svc.Status)"
    if ($svc.Status -ne "Running") {
      throw "WindowsAdminCenter service is not running. Status=$($svc.Status). See $script:LogPath"
    }

    if (Test-TcpPort -TcpPort $Port) {
      Write-Log "TCP port $Port is listening"
    } else {
      Write-Log "Service is running but TCP port $Port did not accept a local connection yet" "WARN"
    }

    $productVersion = Get-InstallerProductVersion -Path $InstallerPath
    Write-WacSetupMarker -ProductVersion $productVersion -CertificateHash $cert.Thumbprint
  }

  Write-Host ""
  Write-UserText "Complete"
  Write-UserText "OpenUrl" @($Port)
  Write-UserText "LogPath" @($script:LogPath)
  Wait-IfRequested
} catch {
  Write-Log $_.Exception.Message "ERROR"
  Write-Host ""
  Write-UserText "FailedLog" @($script:LogPath)
  Wait-IfRequested
  exit 1
}








