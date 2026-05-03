function New-WacTuiConfig {
  return [pscustomobject]@{
    InstallerPath = ""
    InnoExtractPath = ""
    ExtractOut = ""
    InstallDir = "$env:ProgramFiles\WindowsAdminCenter"
    DataDir = "$env:ProgramData\WindowsAdminCenter"
    Port = 6600
    ServicePortStart = 6601
    ServicePortEnd = 6610
    EndpointFqdn = $env:COMPUTERNAME
    ServiceFqdn = "localhost"
    CertificateThumbprint = ""
    CertificateSubject = "WindowsAdminCenterSelfSigned"
    SoftwareUpdateMode = "Manual"
    TrustSelfSignedCertificate = $false
    SkipExtraction = $false
    SkipPsRemoting = $false
    KeepExistingData = $false
    SkipArchitectureCheck = $false
    Language = "Auto"
    AcceptedTerms = $false
    DiagnosticDataMode = "Required"
    NetworkAccess = "LocalOnly"
    TrustedHostsMode = "NotConfigureTrustedHosts"
    WinRmHttpsMode = "Disable"
    InstallMode = "Express"
    Action = "Express"
    ExperimentalArm64 = $false
  }
}

function Get-WacSetupMarkerPath {
  param([string]$DataDir = "$env:ProgramData\WindowsAdminCenter")
  return [System.IO.Path]::Combine($DataDir, "wac-setup.json")
}

function ConvertFrom-WacSetupMarker {
  param([Parameter(Mandatory = $true)]$Marker)

  $config = New-WacTuiConfig
  if ($Marker.installDir) { $config.InstallDir = [string]$Marker.installDir }
  if ($Marker.dataDir) { $config.DataDir = [string]$Marker.dataDir }
  if ($Marker.port) { $config.Port = [int]$Marker.port }
  if ($Marker.servicePortStart) { $config.ServicePortStart = [int]$Marker.servicePortStart }
  if ($Marker.servicePortEnd) { $config.ServicePortEnd = [int]$Marker.servicePortEnd }
  if ($Marker.endpointFqdn) { $config.EndpointFqdn = [string]$Marker.endpointFqdn }
  if ($Marker.serviceFqdn) { $config.ServiceFqdn = [string]$Marker.serviceFqdn }
  if ($Marker.certificateThumbprint) { $config.CertificateThumbprint = [string]$Marker.certificateThumbprint }
  if ($Marker.certificateSubject) { $config.CertificateSubject = [string]$Marker.certificateSubject }
  if ($Marker.softwareUpdateMode) { $config.SoftwareUpdateMode = [string]$Marker.softwareUpdateMode }
  if ($Marker.diagnosticDataMode) { $config.DiagnosticDataMode = [string]$Marker.diagnosticDataMode }
  if ($Marker.networkAccess) { $config.NetworkAccess = [string]$Marker.networkAccess }
  if ($Marker.trustedHostsMode) { $config.TrustedHostsMode = [string]$Marker.trustedHostsMode }
  if ($Marker.winRmHttpsMode) { $config.WinRmHttpsMode = [string]$Marker.winRmHttpsMode }
  if ($Marker.architectureOverride) { $config.SkipArchitectureCheck = [bool]$Marker.architectureOverride }
  return $config
}

function Get-WacTuiInstallState {
  param(
    [string]$DataDir = "$env:ProgramData\WindowsAdminCenter",
    [string]$InstallDir = "$env:ProgramFiles\WindowsAdminCenter"
  )

  $markerPath = Get-WacSetupMarkerPath -DataDir $DataDir
  $config = New-WacTuiConfig
  $isInstalledByThisSetup = $false
  if (Test-Path -LiteralPath $markerPath) {
    try {
      $marker = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
      if ($marker.installedBy -eq "wac-client-windows-setup") {
        $config = ConvertFrom-WacSetupMarker -Marker $marker
        $isInstalledByThisSetup = $true
      }
    } catch {
      $isInstalledByThisSetup = $false
    }
  }

  $service = Get-Service -Name WindowsAdminCenter -ErrorAction SilentlyContinue
  $exePath = Join-Path $InstallDir "Service\WindowsAdminCenter.exe"
  return [pscustomobject]@{
    IsInstalledByThisSetup = $isInstalledByThisSetup
    IsWacPresent = [bool]($service -or (Test-Path -LiteralPath $exePath))
    MarkerPath = $markerPath
    Config = $config
  }
}

function Get-WacTuiPlatformRisk {
  param(
    [string]$OSArchitecture = "",
    [string]$ProcessorArchitecture = "",
    [int]$ProductType = 0
  )

  if (($ProcessorArchitecture -match 'ARM64|ARM') -or ($OSArchitecture -match 'ARM')) {
    return [pscustomobject]@{
      Level = "RISK"
      Code = "Arm64Experimental"
      ProductType = $ProductType
    }
  }

  if (($ProcessorArchitecture -match 'AMD64|x64') -or ($OSArchitecture -match '64')) {
    return [pscustomobject]@{
      Level = "OK"
      Code = "WinClientX64"
      ProductType = $ProductType
    }
  }

  return [pscustomobject]@{
    Level = "BLOCKED"
    Code = "UnsupportedArchitecture"
    ProductType = $ProductType
  }
}

function Add-WacArgument {
  param(
    [System.Collections.ArrayList]$Arguments,
    [Parameter(Mandatory = $true)][string]$Name,
    $Value
  )

  if ($null -eq $Value) { return }
  if (($Value -is [string]) -and [string]::IsNullOrWhiteSpace($Value)) { return }

  [void]$Arguments.Add("-$Name")
  [void]$Arguments.Add([string]$Value)
}

function Add-WacSwitchArgument {
  param(
    [System.Collections.ArrayList]$Arguments,
    [Parameter(Mandatory = $true)][string]$Name,
    [bool]$Enabled = $false
  )

  if ($Enabled) {
    [void]$Arguments.Add("-$Name")
  }
}

function Test-WacDefaultCertificateSubject {
  param([AllowNull()][string]$Subject = "")

  $value = if ($null -eq $Subject) { "" } else { $Subject.Trim() }
  $match = [regex]::Match($value, "^\s*CN\s*=\s*([^,]+)", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
  if ($match.Success) {
    $value = $match.Groups[1].Value.Trim()
  }

  return [string]::Equals(
    $value,
    "WindowsAdminCenterSelfSigned",
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function ConvertTo-WacSetupEngineArguments {
  param(
    [Parameter(Mandatory = $true)]$Config
  )

  $arguments = New-Object System.Collections.ArrayList

  Add-WacArgument $arguments "InstallerPath" $Config.InstallerPath
  Add-WacArgument $arguments "InnoExtractPath" $Config.InnoExtractPath
  Add-WacArgument $arguments "ExtractOut" $Config.ExtractOut
  Add-WacArgument $arguments "InstallDir" $Config.InstallDir
  Add-WacArgument $arguments "DataDir" $Config.DataDir
  Add-WacArgument $arguments "Port" $Config.Port
  Add-WacArgument $arguments "ServicePortStart" $Config.ServicePortStart
  Add-WacArgument $arguments "ServicePortEnd" $Config.ServicePortEnd
  Add-WacArgument $arguments "EndpointFqdn" $Config.EndpointFqdn
  Add-WacArgument $arguments "ServiceFqdn" $Config.ServiceFqdn
  Add-WacArgument $arguments "CertificateThumbprint" $Config.CertificateThumbprint
  if ([string]::IsNullOrWhiteSpace($Config.CertificateThumbprint) -and -not (Test-WacDefaultCertificateSubject -Subject $Config.CertificateSubject)) {
    Add-WacArgument $arguments "CertificateSubject" $Config.CertificateSubject
  }
  Add-WacArgument $arguments "SoftwareUpdateMode" $Config.SoftwareUpdateMode
  Add-WacArgument $arguments "DiagnosticDataMode" $Config.DiagnosticDataMode
  Add-WacArgument $arguments "NetworkAccess" $Config.NetworkAccess
  Add-WacArgument $arguments "TrustedHostsMode" $Config.TrustedHostsMode
  Add-WacArgument $arguments "WinRmHttpsMode" $Config.WinRmHttpsMode
  Add-WacSwitchArgument $arguments "TrustSelfSignedCertificate" $Config.TrustSelfSignedCertificate
  Add-WacSwitchArgument $arguments "SkipExtraction" $Config.SkipExtraction
  Add-WacSwitchArgument $arguments "SkipPsRemoting" $Config.SkipPsRemoting
  Add-WacSwitchArgument $arguments "KeepExistingData" $Config.KeepExistingData
  Add-WacSwitchArgument $arguments "SkipArchitectureCheck" $Config.SkipArchitectureCheck
  Add-WacSwitchArgument $arguments "Uninstall" ($Config.Action -eq "Uninstall" -or $Config.Action -eq "UninstallFull")
  Add-WacSwitchArgument $arguments "PurgeData" ($Config.Action -eq "UninstallFull")
  Add-WacArgument $arguments "Language" $Config.Language

  return ,([string[]]$arguments.ToArray())
}

