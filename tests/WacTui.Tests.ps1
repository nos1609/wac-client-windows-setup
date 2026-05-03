$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $RepoRoot "tui\WacTui.Locale.ps1")
. (Join-Path $RepoRoot "tui\WacTui.Model.ps1")
. (Join-Path $RepoRoot "tui\WacTui.Validation.ps1")
. (Join-Path $RepoRoot "tui\WacTui.Render.ps1")
. (Join-Path $RepoRoot "tui\WacTui.Progress.ps1")

Describe "WacTui.Locale" {
  It "selects Ru for Russian UI culture when language is Auto" {
    $culture = [pscustomobject]@{ TwoLetterISOLanguageName = "ru" }
    Get-WacTuiLanguage -Language "Auto" -Culture $culture | Should Be "Ru"
  }

  It "selects En for non-Russian UI culture when language is Auto" {
    $culture = [pscustomobject]@{ TwoLetterISOLanguageName = "en" }
    Get-WacTuiLanguage -Language "Auto" -Culture $culture | Should Be "En"
  }

  It "returns localized text from the selected pool" {
    $text = Get-WacTuiText -Key "Title" -Language "En"
    $text | Should Be "Windows Admin Center Setup"
  }

  It "falls back to English when a localized string is missing" {
    $text = Get-WacTuiText -Key "EnglishOnlyProbe" -Language "Ru"
    $text | Should Be "English fallback"
  }

  It "returns Russian license screen text from the locale pool" {
    $text = Get-WacTuiText -Key "LicenseTitle" -Language "Ru"
    $expected = ConvertFrom-WacTuiCodePoint @(0x041B, 0x0438, 0x0446, 0x0435, 0x043D, 0x0437, 0x0438, 0x044F, 0x0020, 0x0438, 0x0020, 0x043A, 0x043E, 0x043D, 0x0444, 0x0438, 0x0434, 0x0435, 0x043D, 0x0446, 0x0438, 0x0430, 0x043B, 0x044C, 0x043D, 0x043E, 0x0441, 0x0442, 0x044C)
    $text | Should Be $expected
  }

  It "does not advertise incomplete numeric quick jump shortcuts" {
    (Get-WacTuiText -Key "CustomPrompt" -Language "En").Contains("digits") | Should Be $false
    (Get-WacTuiText -Key "CustomPrompt" -Language "Ru").Contains("цифры") | Should Be $false
  }

  It "uses a non-toggle prompt for navigation-only screens" {
    (Get-WacTuiText -Key "NavigationPrompt" -Language "En").Contains("Space") | Should Be $false
    (Get-WacTuiText -Key "NavigationPrompt" -Language "Ru").Contains("Space") | Should Be $false
  }

  It "has localized error text for failed apply" {
    Get-WacTuiText -Key "ErrorPrefix" -Language "Ru" | Should Be "ОШИБКА"
    ((Get-WacTuiText -Key "ApplyFailed" -Language "Ru") -f 1, "C:\WAC-Diag\wac.log").Contains("Offline") | Should Be $false
    ((Get-WacTuiText -Key "ApplyFailed" -Language "Ru") -f 1, "C:\WAC-Diag\wac.log").Contains("Журнал") | Should Be $true
  }

  It "has localized wait-on-exit prompt" {
    Get-WacTuiText -Key "PressEnterToClose" -Language "Ru" | Should Be "Нажмите Enter, чтобы закрыть"
    Get-WacTuiText -Key "PressEnterToClose" -Language "En" | Should Be "Press Enter to close"
  }
}

Describe "WacTui.Model" {
  It "creates client Windows x64 defaults for the setup engine" {
    $config = New-WacTuiConfig
    $config.InstallerPath | Should Be ""
    $config.InnoExtractPath | Should Be ""
    $config.ExtractOut | Should Be ""
    $config.InstallDir | Should Be "$env:ProgramFiles\WindowsAdminCenter"
    $config.DataDir | Should Be "$env:ProgramData\WindowsAdminCenter"
    $config.Port | Should Be 6600
    $config.ServicePortStart | Should Be 6601
    $config.ServicePortEnd | Should Be 6610
    $config.EndpointFqdn | Should Be $env:COMPUTERNAME
    $config.ServiceFqdn | Should Be "localhost"
    $config.CertificateThumbprint | Should Be ""
    $config.CertificateSubject | Should Be "WindowsAdminCenterSelfSigned"
    $config.SoftwareUpdateMode | Should Be "Manual"
    $config.TrustSelfSignedCertificate | Should Be $false
    $config.SkipExtraction | Should Be $false
    $config.SkipPsRemoting | Should Be $false
    $config.KeepExistingData | Should Be $false
    $config.SkipArchitectureCheck | Should Be $false
    $config.Language | Should Be "Auto"
    $config.AcceptedTerms | Should Be $false
    $config.DiagnosticDataMode | Should Be "Required"
    $config.NetworkAccess | Should Be "LocalOnly"
    $config.TrustedHostsMode | Should Be "NotConfigureTrustedHosts"
    $config.WinRmHttpsMode | Should Be "Disable"
    $config.InstallMode | Should Be "Express"
    $config.ExperimentalArm64 | Should Be $false
  }

  It "classifies Windows x64 as OK" {
    $risk = Get-WacTuiPlatformRisk -OSArchitecture "64-bit" -ProcessorArchitecture "AMD64" -ProductType 1
    $risk.Level | Should Be "OK"
    $risk.Code | Should Be "WinClientX64"
  }

  It "classifies ARM64 as RISK instead of blocking it" {
    $risk = Get-WacTuiPlatformRisk -OSArchitecture "64-bit ARM processor" -ProcessorArchitecture "ARM64" -ProductType 1
    $risk.Level | Should Be "RISK"
    $risk.Code | Should Be "Arm64Experimental"
  }

  It "allows uninstall before enforcing the install architecture gate" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $uninstallIndex = $text.IndexOf('if ($Uninstall) {')
    $architectureIndex = $text.IndexOf("Test-TargetArchitecture", $uninstallIndex)
    $uninstallIndex | Should BeGreaterThan 0
    $architectureIndex | Should BeGreaterThan $uninstallIndex
  }

  It "generates setup engine arguments as an array" {
    $config = New-WacTuiConfig
    $config.InstallerPath = "D:\pkg\WindowsAdminCenter.exe"
    $config.InnoExtractPath = "D:\pkg\tools\innoextract.exe"
    $config.TrustSelfSignedCertificate = $true
    $args = ConvertTo-WacSetupEngineArguments -Config $config
    $args -is [string[]] | Should Be $true
    $args -contains "-InstallerPath" | Should Be $true
    $args -contains "D:\pkg\WindowsAdminCenter.exe" | Should Be $true
    $args -contains "-TrustSelfSignedCertificate" | Should Be $true
    $args -contains "-DiagnosticDataMode" | Should Be $true
    $args -contains "Required" | Should Be $true
    $args -contains "-NetworkAccess" | Should Be $true
    $args -contains "LocalOnly" | Should Be $true
    $args -contains "-TrustedHostsMode" | Should Be $true
    $args -contains "NotConfigureTrustedHosts" | Should Be $true
    $args -contains "-WinRmHttpsMode" | Should Be $true
    $args -contains "Disable" | Should Be $true
  }

  It "does not pass the default generated certificate subject as an explicit engine argument" {
    $config = New-WacTuiConfig
    $config.EndpointFqdn = "server.example.test"
    $config.WinRmHttpsMode = "Enable"
    $args = ConvertTo-WacSetupEngineArguments -Config $config
    $args -contains "-CertificateSubject" | Should Be $false
    $args -contains "WindowsAdminCenterSelfSigned" | Should Be $false
  }

  It "treats the default generated certificate subject case-insensitively" {
    Test-WacDefaultCertificateSubject -Subject "CN=windowsadmincenterselfsigned" | Should Be $true
    Test-WacDefaultCertificateSubject -Subject "WINDOWSADMINCENTERSELFSIGNED" | Should Be $true
    Test-WacDefaultCertificateSubject -Subject "CN=windowsadmincenterselfsigned, O=Local" | Should Be $true
  }

  It "passes a non-default generated certificate subject as an explicit engine argument" {
    $config = New-WacTuiConfig
    $config.CertificateSubject = "custom-wac.test"
    $args = ConvertTo-WacSetupEngineArguments -Config $config
    $subjectIndex = [array]::IndexOf($args, "-CertificateSubject")
    $subjectIndex | Should BeGreaterThan -1
    $args[$subjectIndex + 1] | Should Be "custom-wac.test"
  }

  It "does not emit TUI-only fields as setup engine arguments" {
    $config = New-WacTuiConfig
    $config.AcceptedTerms = $true
    $config.InstallMode = "Custom"
    $config.ExperimentalArm64 = $true
    $args = ConvertTo-WacSetupEngineArguments -Config $config
    $args -contains "-AcceptedTerms" | Should Be $false
    $args -contains "-InstallMode" | Should Be $false
    $args -contains "-ExperimentalArm64" | Should Be $false
  }

  It "stores setup marker under the selected WAC data directory" {
    Get-WacSetupMarkerPath -DataDir "X:\WacData" | Should Be "X:\WacData\wac-setup.json"
  }

  It "loads installation parameters from the current setup marker" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wac-marker-test-" + [guid]::NewGuid().ToString("N"))
    $dataDir = Join-Path $root "Data"
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    try {
      $markerPath = Get-WacSetupMarkerPath -DataDir $dataDir
      @{
        markerVersion = 1
        installedBy = "wac-client-windows-setup"
        installDir = "Y:\Apps\WAC"
        dataDir = $dataDir
        port = 7443
        servicePortStart = 7701
        servicePortEnd = 7710
        endpointFqdn = "client.local"
        serviceFqdn = "localhost"
        certificateThumbprint = "ABCDEF0123456789"
        certificateSubject = "custom-wac.local"
        softwareUpdateMode = "Notification"
        diagnosticDataMode = "Optional"
        networkAccess = "LocalSubnet"
        trustedHostsMode = "ConfigureTrustedHosts"
        winRmHttpsMode = "Enable"
        architectureOverride = $true
      } | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8

      $state = Get-WacTuiInstallState -DataDir $dataDir
      $state.IsInstalledByThisSetup | Should Be $true
      $state.Config.InstallDir | Should Be "Y:\Apps\WAC"
      $state.Config.Port | Should Be 7443
      $state.Config.CertificateSubject | Should Be "custom-wac.local"
      $state.Config.SoftwareUpdateMode | Should Be "Notification"
      $state.Config.NetworkAccess | Should Be "LocalSubnet"
      $state.Config.SkipArchitectureCheck | Should Be $true
    } finally {
      Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
  }

  It "does not treat foreign setup markers as ours" {
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("wac-marker-test-" + [guid]::NewGuid().ToString("N"))
    $dataDir = Join-Path $root "Data"
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    try {
      $markerPath = Get-WacSetupMarkerPath -DataDir $dataDir
      @{
        markerVersion = 1
        installedBy = "some-other-setup"
        installDir = "Y:\Apps\WAC"
        dataDir = $dataDir
      } | ConvertTo-Json | Set-Content -LiteralPath $markerPath -Encoding UTF8

      $state = Get-WacTuiInstallState -DataDir $dataDir
      $state.IsInstalledByThisSetup | Should Be $false
    } finally {
      Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
  }
}

Describe "WacTui.Validation" {
  It "normalizes certificate thumbprints copied with spaces and hidden marks" {
    $raw = ([char]0x200E) + " 0E 7E B7 41 2A 93 E2 E3 8D AF 43 D4 FA 09 E0 E0 C9 DB 3F BF "
    Normalize-WacCertificateThumbprint -Thumbprint $raw | Should Be "0E7EB7412A93E2E38DAF43D4FA09E0E0C9DB3FBF"
  }

  It "accepts a valid port and service range" {
    $result = Test-WacPortPlan -Port 6600 -ServicePortStart 6601 -ServicePortEnd 6610
    $result.Level | Should Be "OK"
  }

  It "blocks a reversed service range" {
    $result = Test-WacPortPlan -Port 6600 -ServicePortStart 6610 -ServicePortEnd 6601
    $result.Level | Should Be "BLOCKED"
  }

  It "warns for a WAC port below 1024" {
    $result = Test-WacPortPlan -Port 443 -ServicePortStart 6601 -ServicePortEnd 6610
    $result.Level | Should Be "WARN"
  }
}

Describe "WacTui.Render" {
  It "wraps text without exceeding the requested width" {
    $lines = Split-WacTuiText -Text "Windows Admin Center setup needs a normal password for WinRM sign-in." -Width 24
    @($lines | Where-Object { $_.Length -gt 24 }).Count | Should Be 0
    $lines.Count -gt 1 | Should Be $true
  }

  It "shortens long paths with middle ellipsis" {
    $short = Format-WacTuiEllipsis -Text "X:\Package\wac-client-windows-setup\WindowsAdminCenter.exe" -Width 32
    $short.Length | Should BeLessThan 33
    $short.Contains("...") | Should Be $true
  }

  It "renders an ASCII frame when Unicode is disabled" {
    $frame = New-WacTuiFrame -Title "Setup" -Lines @("Hello") -Width 30 -UseUnicode:$false
    $frame[0] | Should Be "+----------------------------+"
    $frame[-1] | Should Be "+----------------------------+"
  }

  It "preserves leading spaces in framed menu lines" {
    $frame = New-WacTuiFrame -Title "Setup" -Lines @("  > Express setup") -Width 30 -UseUnicode:$false
    $frame[2] | Should Be "|  > Express setup           |"
  }

  It "renders selected rows with inverse highlight without changing text alignment" {
    $selected = New-WacTuiSelectedLine -Text "  1. Express setup"
    $frame = New-WacTuiFrame -Title "Setup" -Lines @($selected) -Width 30 -UseUnicode:$false
    $frame[2].Contains(">") | Should Be $false
    $frame[2].Contains("  1. Express setup") | Should Be $true
    $frame[2].Contains("$([char]27)[7m") | Should Be $true
  }

  It "pads ANSI-styled inline controls by visible width" {
    $button = Format-WacTuiButton -Text "Next" -Selected:$true
    $frame = New-WacTuiFrame -Title "Setup" -Lines @("    $button") -Width 30 -UseUnicode:$false
    (Remove-WacTuiAnsi -Text $frame[2]).Length | Should Be 30
    $frame[2].Contains("$([char]27)[7m") | Should Be $true
  }

  It "renders warning and danger ANSI styles" {
    (Add-WacTuiWarning -Text "warn").Contains("$([char]27)[33m") | Should Be $true
    (Add-WacTuiDanger -Text "danger").Contains("$([char]27)[31m") | Should Be $true
  }

  It "accounts for emoji and dim ANSI sequences in visible width" {
    Get-WacTuiVisibleLength -Text "📦 Source" | Should Be 9
    Get-WacTuiVisibleLength -Text (Add-WacTuiDim -Text "подсказка") | Should Be 9
    $frame = New-WacTuiFrame -Title "Setup" -Lines @("📦 Source", (Add-WacTuiDim -Text "подсказка")) -Width 40 -UseUnicode:$false
    foreach ($line in $frame) {
      (Get-WacTuiVisibleLength -Text $line) | Should Be 40
    }
  }

  It "renders progress as a fixed width bar" {
    $bar = New-WacTuiProgressBar -Percent 45 -Width 20 -UseUnicode:$false
    $bar | Should Be "[#########-----------] 45%"
  }
}

Describe "WacTui.Progress" {
  It "returns stable install phases from extraction to port check" {
    $phases = Get-WacTuiInstallPhases
    $phases[0].Name | Should Be "Extract"
    $phases[-1].Name | Should Be "PortCheck"
  }

  It "maps known phases to increasing percentages" {
    $copy = Get-WacTuiPhasePercent -Name "CopyFiles"
    $services = Get-WacTuiPhasePercent -Name "Services"
    $services -gt $copy | Should Be $true
  }

  It "keeps cleanup as an internal non-redrawing phase" {
    Get-WacTuiPhasePercent -Name "Extract" | Should Be 5
    Get-WacTuiPhasePercent -Name "Cleanup" | Should Be 5
  }

  It "maps unknown phase to zero percent" {
    Get-WacTuiPhasePercent -Name "Unexpected" | Should Be 0
  }

  It "derives progress from real setup engine log phases" {
    $lines = @(
      "[23:24:01] [STEP] Extracting installer payload with tools\innoextract.exe",
      "[23:24:28] [STEP] Copying files",
      "[23:24:43] [INFO] Registering services",
      "[23:24:54] [INFO] TCP port 6600 is listening"
    )
    $progress = Get-WacTuiProgressFromLogLines -Lines $lines
    $progress.PhaseName | Should Be "PortCheck"
    $progress.Percent | Should Be 100
  }

  It "returns localized install phase labels" {
    Get-WacTuiPhaseLabel -Name "Extract" -Language "Ru" | Should Be "Распаковка установщика"
    Get-WacTuiPhaseLabel -Name "PortCheck" -Language "Ru" | Should Be "Проверка HTTPS-порта"
    Get-WacTuiPhaseLabel -Name "Extract" -Language "En" | Should Be "Extracting payload"
  }
}

Describe "interactive-installer.ps1" {
  It "exists beside the setup engine" {
    Test-Path (Join-Path $RepoRoot "interactive-installer.ps1") | Should Be $true
  }

  It "parses without executing the wizard" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $errors.Count | Should Be 0
  }

  It "defines terminal title handling for wizard screens" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Set-WacTuiTerminalTitle") | Should Be $true
    $text.Contains("function Get-WacTuiSpinnerFrame") | Should Be $true
    $text.Contains("function Set-WacTuiAnimatedTerminalTitle") | Should Be $true
    $text.Contains("RawUI.WindowTitle") | Should Be $true
    $text.Contains('WindowTitle = "WAC - $Title"') | Should Be $true
    $text.Contains('WindowTitle = "{0} WAC - {1}"') | Should Be $true
  }

  It "uses non-blocking input polling so resize can trigger redraw" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Read-WacTuiInput") | Should Be $true
    $text.Contains("function Get-WacTuiConsoleSnapshot") | Should Be $true
    $text.Contains("function Get-WacTuiConsoleSizeKey") | Should Be $true
    $text.Contains("[Console]::WindowWidth") | Should Be $true
    $text.Contains('$Host.UI.RawUI.WindowSize.Width') | Should Be $true
    $text.Contains("[Console]::KeyAvailable") | Should Be $true
    $text.Contains('$Host.UI.RawUI.KeyAvailable') | Should Be $false
    $text.Contains('Kind = "Resize"') | Should Be $true
    $text.Contains("Read-WacTuiInput") | Should Be $true
  }

  It "pre-sizes the console for the largest wizard screen" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-WacTuiPreferredLayout") | Should Be $true
    $text.Contains("function Set-WacTuiPreferredWindowSize") | Should Be $true
    $text.Contains("MaxPhysicalWindowSize") | Should Be $true
    $text.Contains("RawUI.WindowSize") | Should Be $true
    $text.Contains("BufferSize") | Should Be $true
    $text.Contains("Set-WacTuiWizardWindowSize -Config `$config -Language `$resolvedLanguage") | Should Be $true
  }
}

Describe "wac-setup-engine.ps1" {
  It "parses without executing the installer" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    $errors.Count | Should Be 0
  }

  It "prefers Windows Terminal for elevated rerun when wt.exe is available" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-WindowsTerminalPath") | Should Be $true
    $text.Contains("wt.exe") | Should Be $true
    $text.Contains("function Get-WindowsTerminalElevationArgumentString") | Should Be $true
    $text.Contains("WAC elevated - WAC") | Should Be $true
  }

  It "recognizes localized certutil private-key container names" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("RSACertificateExtensions") | Should Be $true
    $text.Contains("GetRSAPrivateKey") | Should Be $true
    $text.Contains("ECDsaCertificateExtensions") | Should Be $true
    $text.Contains("GetECDsaPrivateKey") | Should Be $true
    $text.Contains("UniqueName") | Should Be $true
    $text.Contains("Key Container") | Should Be $true
    $text.Contains("Контейнер ключа") | Should Be $true
    $text.Contains("Unique container name") | Should Be $true
    $text.Contains("Уникальное имя контейнера") | Should Be $true
    $text.Contains("0x8009030D") | Should Be $true
  }

  It "trusts reused generated self-signed certificates when requested" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Ensure-TrustedCertificate") | Should Be $true
    $text.Contains('Get-Item -LiteralPath $rootPath') | Should Be $true
    $text.Contains('Import-Certificate -FilePath $tmp -CertStoreLocation Cert:\LocalMachine\Root -ErrorAction Stop') | Should Be $true
    $text.Contains('if ($TrustSelfSignedCertificate -and [string]::IsNullOrWhiteSpace($CertificateThumbprint))') | Should Be $true
    $trustCall = $text.IndexOf("Ensure-TrustedCertificate -Certificate `$cert")
    $aclCall = $text.IndexOf("Grant-CertificatePrivateKeyAcl -Certificate `$cert")
    $trustCall -ge 0 | Should Be $true
    $aclCall -gt $trustCall | Should Be $true
  }

  It "registers the stock Windows Admin Center updater scheduled task" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Register-UpdaterScheduledTask") | Should Be $true
    $text.Contains("WindowsAdminCenterUpdater") | Should Be $true
    $text.Contains("Register-ScheduledTask") | Should Be $true
    $text.Contains("SetSecurityDescriptor") | Should Be $true
  }

  It "does not keep legacy setup marker cleanup plumbing" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $legacyMarkerName = ("wac" + "2511" + "-setup.json")
    $text.Contains("LegacyWacSetupMarker") | Should Be $false
    $text.Contains($legacyMarkerName) | Should Be $false
  }

  It "requires the WAC installer signature to belong to Microsoft" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("Get-AuthenticodeSignature -LiteralPath `$InstallerPath") | Should Be $true
    $text.Contains("O=Microsoft Corporation") | Should Be $true
    $text.Contains("Installer signature is valid, but the signer is not Microsoft Corporation.") | Should Be $true
  }

  It "restores persisted setup marker options before direct engine repair" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $restoreMatch = [regex]::Match($text, "function Apply-WacSetupMarkerDefaults \{(?s).*?\n\}")
    $restoreMatch.Success | Should Be $true
    $restoreBody = $restoreMatch.Value

    foreach ($field in @(
      "installDir",
      "dataDir",
      "port",
      "servicePortStart",
      "servicePortEnd",
      "endpointFqdn",
      "serviceFqdn",
      "certificateThumbprint",
      "certificateSubject",
      "trustSelfSignedCertificate",
      "softwareUpdateMode",
      "diagnosticDataMode",
      "networkAccess",
      "trustedHostsMode",
      "winRmHttpsMode",
      "skipPsRemoting",
      "keepExistingData",
      "architectureOverride"
    )) {
      $restoreBody.Contains("Marker.$field") | Should Be $true
    }
  }

  It "polls for the WAC service to reach Running instead of sleeping once" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Wait-WacServiceRunning") | Should Be $true
    $text.Contains("Wait-WacServiceRunning -Name `$script:ServiceName") | Should Be $true
    $text.Contains("Start-Sleep -Seconds 5") | Should Be $false
  }

  It "backs up and conditionally restores WinRM TrustedHosts" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-WinRmTrustedHostsValue") | Should Be $true
    $text.Contains("previousTrustedHosts = `$script:PreviousTrustedHosts") | Should Be $true
    $text.Contains("function Restore-WinRmTrustedHosts") | Should Be $true
    $text.Contains('Get-WacMarkerValue -Marker $setupMarker -Name "previousTrustedHosts"') | Should Be $true
    $text.Contains('$current -ne "*"') | Should Be $true
  }

  It "uses the Windows winrm command script for HTTPS listener configuration" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-WinRmCommandPath") | Should Be $true
    $text.Contains('Get-Command "winrm.cmd"') | Should Be $true
    $text.Contains("winrm.exe") | Should Be $false
    $text.Contains('$winrm = Get-WinRmCommandPath') | Should Be $true
    $text.Contains('Invoke-LoggedProcess -FilePath $winrm -ArgumentList @("create", $listenerResource') | Should Be $true
  }

  It "uses the endpoint FQDN as the generated certificate subject for WinRM HTTPS" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-EffectiveCertificateSubject") | Should Be $true
    $text.Contains('$WinRmHttpsMode -eq "Enable"') | Should Be $true
    $text.Contains("return `$EndpointFqdn") | Should Be $true
    $text.Contains('Test-IsDefaultCertificateSubject -Subject $CertificateSubject') | Should Be $true
    $text.Contains('CertificateSubject must match EndpointFqdn when WinRM over HTTPS is enabled') | Should Be $true
    $text.Contains('$effectiveSubject = Get-EffectiveCertificateSubject') | Should Be $true
    $text.Contains('certificateSubject = Get-EffectiveCertificateSubject') | Should Be $true
  }

  It "does not reuse generated certificates that miss required WAC DNS names" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Test-CertificateDnsName") | Should Be $true
    $text.Contains("function Test-CertificateUsableForWac") | Should Be $true
    $text.Contains('$requiredNames = Get-RequiredGeneratedCertificateDnsNames') | Should Be $true
    $text.Contains('Test-CertificateUsableForWac -Certificate $_ -RequiredDnsNames $requiredNames') | Should Be $true
    $text.Contains('does not cover required WAC names; creating a new one') | Should Be $true
  }

  It "includes the service FQDN in generated certificate DNS names" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $dnsMatch = [regex]::Match($text, "function Get-RequiredGeneratedCertificateDnsNames \{(?s).*?\n\}")
    $dnsMatch.Success | Should Be $true
    $dnsBody = $dnsMatch.Value
    $dnsBody.Contains('$serviceHostname = if ([string]::IsNullOrWhiteSpace($ServiceFqdn)) { "localhost" } else { $ServiceFqdn }') | Should Be $true
    $dnsBody.Contains('$names = @($EndpointFqdn, $env:COMPUTERNAME, $serviceHostname, "localhost")') | Should Be $true
  }

  It "only reuses generated self-signed certificates" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Test-ReusableGeneratedCertificate") | Should Be $true
    $text.Contains('$Certificate.Issuer -eq $Certificate.Subject') | Should Be $true
    $text.Contains('$Certificate.FriendlyName -eq "Windows Admin Center Self-Signed Certificate"') | Should Be $true
    $text.Contains('Test-CertificateHasServerAuthentication -Certificate $Certificate') | Should Be $true
    $text.Contains('Test-CertificateHasUsablePrivateKey -Certificate $Certificate') | Should Be $true
    $text.Contains('Test-ReusableGeneratedCertificate -Certificate $_') | Should Be $true
  }

  It "treats the default generated certificate subject case-insensitively in the engine" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $subjectMatch = [regex]::Match($text, "function Test-IsDefaultCertificateSubject \{(?s).*?\n\}")
    $subjectMatch.Success | Should Be $true
    $subjectBody = $subjectMatch.Value
    $subjectBody.Contains("[System.StringComparison]::OrdinalIgnoreCase") | Should Be $true
    $subjectBody.Contains('WindowsAdminCenterSelfSigned') | Should Be $true
  }

  It "extracts the common name from full certificate subject DNs" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $subjectMatch = [regex]::Match($text, "function Get-CertificateSubjectCommonName \{(?s).*?\n\}")
    $subjectMatch.Success | Should Be $true

    Invoke-Expression $subjectMatch.Value

    Get-CertificateSubjectCommonName -Subject "CN=wac.example.com, O=Contoso" | Should Be "wac.example.com"
    Get-CertificateSubjectCommonName -Subject "CN=WindowsAdminCenterSelfSigned" | Should Be "WindowsAdminCenterSelfSigned"
    Get-CertificateSubjectCommonName -Subject "wac.example.com" | Should Be "wac.example.com"
  }

  It "validates supplied certificates before WinRM HTTPS listener creation" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains('Assert-SuppliedCertificateUsableForWac -Certificate $cert') | Should Be $true
    $text.Contains('Supplied certificate $($Certificate.Thumbprint) does not cover required WAC names') | Should Be $true
  }

  It "validates supplied certificates for WAC HTTPS even when WinRM HTTPS is disabled" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $assertMatch = [regex]::Match($text, "function Assert-SuppliedCertificateUsableForWac \{(?s).*?\n\}")
    $assertMatch.Success | Should Be $true
    $assertBody = $assertMatch.Value
    $assertBody.Contains('Test-CertificateUsableForWac -Certificate $Certificate -RequiredDnsNames $requiredNames') | Should Be $true
    $assertBody.Contains('if ($WinRmHttpsMode -eq "Enable")') | Should Be $false
  }

  It "validates supplied certificates against gateway and service names" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $assertMatch = [regex]::Match($text, "function Assert-SuppliedCertificateUsableForWac \{(?s).*?\n\}")
    $assertMatch.Success | Should Be $true
    $assertBody = $assertMatch.Value
    $assertBody.Contains('Test-CertificateHasUsablePrivateKey -Certificate $Certificate') | Should Be $true
    $assertBody.Contains('$gatewayHostname = if ([string]::IsNullOrWhiteSpace($EndpointFqdn)) { $env:COMPUTERNAME } else { $EndpointFqdn }') | Should Be $true
    $assertBody.Contains('$serviceHostname = if ([string]::IsNullOrWhiteSpace($ServiceFqdn)) { "localhost" } else { $ServiceFqdn }') | Should Be $true
    $assertBody.Contains('$requiredNames = @($gatewayHostname, $serviceHostname)') | Should Be $true
    $assertBody.Contains('Supplied certificate $($Certificate.Thumbprint) does not cover required WAC names') | Should Be $true
  }

  It "logs the selected certificate subject and DNS names before WinRM HTTPS configuration" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains('function Write-CertificateDiagnostics') | Should Be $true
    $text.Contains('Certificate selected: Thumbprint=') | Should Be $true
    $text.Contains('Certificate DNS names:') | Should Be $true
    $text.IndexOf('Write-CertificateDiagnostics -Certificate $cert') -lt $text.IndexOf('Set-WinRmHttpsMode -Certificate $cert') | Should Be $true
  }

  It "exits with a clean error instead of rethrowing PowerShell stack traces" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains('} catch {') | Should Be $true
    $text.Contains('exit 1') | Should Be $true
    $text.Contains('Wait-IfRequested' + "`r`n  throw") | Should Be $false
  }

  It "preserves the original TrustedHosts backup across direct engine repair" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains('$existingPreviousTrustedHosts = Get-WacMarkerValue -Marker $setupMarker -Name "previousTrustedHosts"') | Should Be $true
    $text.Contains('if ($null -ne $existingPreviousTrustedHosts) { $script:PreviousTrustedHosts = [string]$existingPreviousTrustedHosts }') | Should Be $true
    $text.Contains('if ($current -ne "*") {') | Should Be $true
    $text.Contains('$script:PreviousTrustedHosts = $current') | Should Be $true
  }

  It "reads optional marker fields without breaking old markers under StrictMode" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-WacMarkerValue") | Should Be $true
    $text.Contains('Get-WacMarkerValue -Marker $setupMarker -Name "previousTrustedHosts"') | Should Be $true
    $text.Contains("Restore-WinRmTrustedHosts -PreviousValue `$setupMarker.previousTrustedHosts") | Should Be $false
  }

  It "wraps malformed appsettings.json errors with setup context" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Read-WacAppSettingsJson") | Should Be $true
    $text.Contains("WAC appsettings.json is missing or invalid") | Should Be $true
    $text.Contains('$json = Read-WacAppSettingsJson -AppSettingsPath $AppSettingsPath') | Should Be $true
  }

  It "does not discover default installers from the parent directory" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $lookupMatch = [regex]::Match($text, "function Get-DefaultInstallerPath \{(?s).*?\n\}")
    $lookupMatch.Success | Should Be $true
    $lookupBody = $lookupMatch.Value
    $lookupBody.Contains('Join-Path $PSScriptRoot ".."') | Should Be $false
    $lookupBody.Contains('$searchRoots = @($PSScriptRoot)') | Should Be $true
  }

  It "handles installer ProductVersion missing from file metadata" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-InstallerProductVersion") | Should Be $true
    $text.Contains('$productVersion = Get-InstallerProductVersion -Path $InstallerPath') | Should Be $true
    $text.Contains("VersionInfo.ProductVersion).Trim()") | Should Be $false
  }

  It "preserves payload NuGetVersion instead of hardcoding it" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-WacAppSettingsNuGetVersion") | Should Be $true
    $text.Contains('$nuGetVersion = Get-WacAppSettingsNuGetVersion -AppSettings $json -Fallback "2.6.6"') | Should Be $true
    $text.Contains('Set-JsonValue $json @("WindowsAdminCenter", "System", "NuGetVersion") "2.6.6"') | Should Be $false
  }

  It "can download the stock installer with winget before falling back to aka.ms" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Get-CachedWacInstaller") | Should Be $true
    $text.Contains("function Save-WacInstallerFromWinget") | Should Be $true
    $text.Contains("winget.exe") | Should Be $true
    $text.Contains("download") | Should Be $true
    $text.Contains("Microsoft.WindowsAdminCenter") | Should Be $true
    $text.Contains("Windows Admin Center") | Should Be $true
    $text.Contains("https://aka.ms/WACDownload") | Should Be $true
    $text.Contains('$script:WingetDownloadTimeoutSeconds = 120') | Should Be $true
    $text.Contains('-TimeoutSeconds $script:WingetDownloadTimeoutSeconds') | Should Be $true
    $text.Contains('$cachedInstaller = Get-CachedWacInstaller') | Should Be $true
    $text.Contains('Using cached Windows Admin Center installer after winget failure') | Should Be $true
    $text.IndexOf("Save-WacInstallerFromWinget") -lt $text.IndexOf("Save-WacInstallerFromAkaMs") | Should Be $true
  }

  It "can reuse the cached installer before failing after network download errors" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains('if ([string]::IsNullOrWhiteSpace($InstallerPath)) { $InstallerPath = Get-CachedWacInstaller }') | Should Be $true
    $text.Contains('Using cached Windows Admin Center installer: $installer') | Should Be $true
  }

  It "rejects cached installers that fail Authenticode validation before download fallback" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $cacheMatch = [regex]::Match($text, "function Get-CachedWacInstaller \{(?s).*?\n\}")
    $cacheMatch.Success | Should Be $true
    $cacheBody = $cacheMatch.Value
    $text.Contains('function Test-WacInstallerAuthenticode') | Should Be $true
    $text.Contains('Get-AuthenticodeSignature -LiteralPath $Path') | Should Be $true
    $cacheBody.Contains('Test-WacInstallerAuthenticode -Path $installer') | Should Be $true
    $text.Contains('Ignoring cached Windows Admin Center installer') | Should Be $true
    $cacheBody.Contains('return ""') | Should Be $true
    $text.IndexOf('$InstallerPath = Get-CachedWacInstaller') -lt $text.IndexOf('$InstallerPath = Save-WacInstallerFromWinget') | Should Be $true
  }

  It "continues scanning cached installers after a failed Authenticode validation" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $cacheMatch = [regex]::Match($text, "function Get-CachedWacInstaller \{(?s).*?\n\}")
    $cacheMatch.Success | Should Be $true
    $cacheBody = $cacheMatch.Value
    $cacheBody.Contains('$candidates = Find-WacInstallersInDirectory -Path $downloadDir') | Should Be $true
    $cacheBody.Contains('foreach ($installer in @($candidates))') | Should Be $true
    $cacheBody.Contains('if (Test-WacInstallerAuthenticode -Path $installer)') | Should Be $true
    $cacheBody.Contains('return $installer') | Should Be $true
  }

  It "keeps successful noisy external tool output out of the main log unless needed" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("[bool]`$LogOutputOnSuccess = `$true") | Should Be $true
    $text.Contains('$script:NativeProcessOutputEncoding') | Should Be $true
    $text.Contains('function Get-NativeProcessOutputEncoding') | Should Be $true
    $text.Contains('[Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage') | Should Be $true
    $text.Contains('[Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage') | Should Be $false
    $text.Contains('$psi.StandardOutputEncoding = $script:NativeProcessOutputEncoding') | Should Be $true
    $text.Contains('$stdoutTask = $process.StandardOutput.ReadToEndAsync()') | Should Be $true
    $text.Contains('$stderrTask = $process.StandardError.ReadToEndAsync()') | Should Be $true
    $text.Contains('$output = & $FilePath @ArgumentList 2>&1') | Should Be $false
    $text.Contains('-LogOutputOnSuccess:$false') | Should Be $true
  }

  It "downloads the compatible innoextract Windows fork directly instead of the old winget package" {
    $scriptPath = Join-Path $RepoRoot "wac-setup-engine.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Save-InnoExtractFromWinget") | Should Be $false
    $text.Contains("dscharrer.innoextract") | Should Be $false
    $text.Contains("function Save-InnoExtractFromOfficialZip") | Should Be $true
    $text.Contains("https://github.com/UserUnknownFactor/innoextract_win/releases/download/670/innoextract670.zip") | Should Be $true
    $text.Contains("79B69B9B1FCD98F42CCD4B245EFDF6A03BCFB674BA6AF482F5A46891C9ED4D14") | Should Be $true
  }
}

Describe "WacTui apply planning" {
  BeforeAll {
    . (Join-Path $RepoRoot "interactive-installer.ps1")
  }

  It "builds license lines with a checkbox and without typed ACCEPT" {
    $lines = New-WacTuiLicenseLines -Language "En" -Accepted $false
    ($lines -join "`n") | Should Match "\[ \] I accept"
    ($lines -join "`n").Contains("ACCEPT") | Should Be $false
  }

  It "shows current Microsoft licensing, EULA, and privacy links on the license screen" {
    $lines = New-WacTuiLicenseLines -Language "En" -Accepted $true
    ($lines -join "`n").Contains("https://learn.microsoft.com/windows-server/windows-server-licensing/windows-admin-center-licensing") | Should Be $true
    ($lines -join "`n").Contains("https://learn.microsoft.com/legal/windows-server/windows-admin-center/wac-product-ga-eula") | Should Be $true
    ($lines -join "`n").Contains("https://privacy.microsoft.com/privacystatement") | Should Be $true

    $ruLines = New-WacTuiLicenseLines -Language "Ru" -Accepted $true
    ($ruLines -join "`n").Contains("https://learn.microsoft.com/windows-server/windows-server-licensing/windows-admin-center-licensing") | Should Be $true
    ($ruLines -join "`n").Contains("https://learn.microsoft.com/legal/windows-server/windows-admin-center/wac-product-ga-eula") | Should Be $true
    ($ruLines -join "`n").Contains("https://learn.microsoft.com/ru-ru/") | Should Be $false
  }

  It "renders license and details screens with wizard buttons" {
    $config = New-WacTuiConfig
    $licenseFrame = New-WacTuiFrame -Title "License" -Lines (New-WacTuiLicenseLines -Language "En" -Accepted $false -SelectedIndex 1) -Width 100 -UseUnicode:$false
    $detailsFrame = New-WacTuiFrame -Title "Details" -Lines (New-WacTuiDetailsLines -Config $config -Language "En" -SelectedIndex 0) -Width 100 -UseUnicode:$false
    $licenseLine = (@($licenseFrame | ForEach-Object { Remove-WacTuiAnsi -Text $_ } | Where-Object { $_ -match '\[ Back \].*\[ Next \].*\[ Cancel \]' }))[0]
    $detailsLine = (@($detailsFrame | ForEach-Object { Remove-WacTuiAnsi -Text $_ } | Where-Object { $_ -match '\[ Back \]' }))[0]
    $licenseLine.StartsWith("|    ") | Should Be $true
    $detailsLine.StartsWith("|    ") | Should Be $true
  }

  It "does not show toggle hints on navigation-only screens" {
    $config = New-WacTuiConfig
    $screens = @(
      (New-WacTuiWelcomeLines -Language "En" -SelectedIndex 0),
      (New-WacTuiModeLines -Language "En" -SelectedIndex 3),
      (New-WacTuiReadyLines -Config $config -Language "En" -SelectedIndex 2),
      (New-WacTuiDetailsLines -Config $config -Language "En" -SelectedIndex 0)
    )
    foreach ($screen in $screens) {
      ($screen -join "`n").Contains("Space") | Should Be $false
    }
  }

  It "shows editable custom setup options from the stock wizard surface" {
    $config = New-WacTuiConfig
    $lines = New-WacTuiCustomLines -Config $config -Language "En" -SelectedIndex 0
    $text = $lines -join "`n"
    $text.Contains("Gateway HTTPS port") | Should Be $true
    $text.Contains("TLS certificate mode") | Should Be $true
    $text.Contains("Endpoint FQDN") | Should Be $true
    $text.Contains("Trusted hosts mode") | Should Be $true
    $text.Contains("WinRM over HTTPS") | Should Be $true
  }

  It "renders custom setup as a selectable TUI list with buttons" {
    $config = New-WacTuiConfig
    $lines = New-WacTuiCustomLines -Config $config -Language "En" -SelectedIndex 0
    $optionLines = @($lines | Where-Object { (Remove-WacTuiAnsi -Text (Remove-WacTuiNoWrapLinePrefix -Text (Remove-WacTuiSelectedLinePrefix -Text $_))).Contains("Install directory") -or (Remove-WacTuiAnsi -Text (Remove-WacTuiNoWrapLinePrefix -Text (Remove-WacTuiSelectedLinePrefix -Text $_))).Contains("Data directory") })
    $optionLines[0].Contains(" 1. Install directory") | Should Be $true
    (Remove-WacTuiNoWrapLinePrefix -Text (Remove-WacTuiSelectedLinePrefix -Text $optionLines[1])).IndexOf(":") | Should Be ((Remove-WacTuiNoWrapLinePrefix -Text (Remove-WacTuiSelectedLinePrefix -Text $optionLines[0])).IndexOf(":"))
    $optionLines[0].StartsWith("> ") | Should Be $false
    $buttonLines = New-WacTuiCustomLines -Config $config -Language "En" -SelectedIndex 19
    ($buttonLines -join "`n").Contains("[ Next ]") | Should Be $true
    ($buttonLines -join "`n").Contains("< Next >") | Should Be $false
    ($buttonLines -join "`n").Contains("$([char]27)[7m") | Should Be $true
    ($lines -join "`n").Contains("Space") | Should Be $true
  }

  It "renders frames for different widths without drifting the right border" {
    $config = New-WacTuiConfig
    foreach ($width in @(60, 78, 100, 120)) {
      $frame = New-WacTuiFrame -Title "Resize" -Lines (New-WacTuiCustomLines -Config $config -Language "En" -SelectedIndex 0) -Width $width -UseUnicode:$false
      foreach ($line in $frame) {
        (Remove-WacTuiAnsi -Text $line).Length | Should Be $width
      }
    }
  }

  It "keeps oversized frames inside the current viewport" {
    $config = New-WacTuiConfig
    $frame = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width 100 -UseUnicode:$false
    $viewport = Select-WacTuiFrameViewport -Frame $frame -Height 20
    $viewport.Count | Should Be 20
    $viewport[0] | Should Be $frame[0]
    $viewport[1] | Should Be $frame[1]
    $viewport[-1] | Should Be $frame[-1]
    ($viewport -join "`n").Contains("[ Далее ]") | Should Be $true
  }

  It "calculates a preferred layout tall enough for custom setup" {
    $config = New-WacTuiConfig
    $layout = Get-WacTuiPreferredLayout -Config $config -Language "Ru"
    $customFrame = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width $layout.Width -UseUnicode:$false
    $layout.Width | Should Be 100
    $layout.Height | Should BeGreaterThan ($customFrame.Count - 1)
  }

  It "keeps custom option rows aligned after frame rendering" {
    $config = New-WacTuiConfig
    $frame = New-WacTuiFrame -Title "Resize" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width 100 -UseUnicode:$false
    $visible = $frame | ForEach-Object { Remove-WacTuiAnsi -Text $_ }
    @($visible | Where-Object { $_ -match '^\|16\.' }).Count | Should Be 0
    @($visible | Where-Object { $_ -match '^\|  16\.' }).Count | Should Be 1
    ($visible -join "`n").Contains("...") | Should Be $false
    @($visible | Where-Object { $_ -match '^\|(setup engine|\()' }).Count | Should Be 0
    ($visible -join "`n").Contains("не применяется") | Should Be $false
    foreach ($number in 16..18) {
      @($visible | Where-Object { $_ -match ("^\|  {0}\." -f $number) }).Count | Should Be 1
    }
    @($visible | Where-Object { $_ -match '^\| +применяется\)' }).Count | Should Be 0
  }

  It "uses natural Russian text on the custom setup screen" {
    $config = New-WacTuiConfig
    $frame = New-WacTuiFrame -Title "Resize" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width 140 -UseUnicode:$false
    $text = ($frame | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $text.Contains("gateway") | Should Be $false
    $text.Contains("thumbprint") | Should Be $false
    $text.Contains("wizard") | Should Be $false
    $text.Contains("setup engine") | Should Be $false
    $text.Contains("NotApplied") | Should Be $false
    $text.Contains("Manual") | Should Be $false
    $text.Contains("default") | Should Be $false
    $text.Contains("HTTPS-порт шлюза") | Should Be $true
    $text.Contains("Отпечаток сертификата") | Should Be $true
    $text.Contains("вручную") | Should Be $true
    $text.Contains("не применяется") | Should Be $false
  }

  It "colors risky custom options according to their selected state" {
    $config = New-WacTuiConfig
    $script:WacTuiUseVisuals = $true
    $lines = New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19
    $text = $lines -join "`n"
    $psRemotingLine = (@($lines | Where-Object { (Remove-WacTuiAnsi -Text $_).Contains("Включить PowerShell Remoting") }))[0]
    $psRemotingLine.Contains("$([char]27)[33m") | Should Be $true

    $trustLine = (@($lines | Where-Object { (Remove-WacTuiAnsi -Text $_).Contains("Доверять созданному") }))[0]
    $trustLine.Contains("$([char]27)[33m") | Should Be $false

    $config.TrustSelfSignedCertificate = $true
    $lines = New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19
    $trustLine = (@($lines | Where-Object { (Remove-WacTuiAnsi -Text $_).Contains("Доверять созданному") }))[0]
    $trustLine.Contains("$([char]27)[33m") | Should Be $true

    $config.SkipPsRemoting = $true
    $lines = New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19
    $psRemotingLine = (@($lines | Where-Object { (Remove-WacTuiAnsi -Text $_).Contains("Включить PowerShell Remoting") }))[0]
    $psRemotingLine.Contains("$([char]27)[33m") | Should Be $false
  }

  It "does not leak internal render markers in framed risky custom options" {
    $config = New-WacTuiConfig
    $config.TrustSelfSignedCertificate = $true
    $script:WacTuiUseVisuals = $true
    $frame = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width 120 -UseUnicode:$true
    $visible = ($frame | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $visible.Contains("[[WAC_TUI_NOWRAP]]") | Should Be $false
    $visible.Contains("[[WAC_TUI_SELECTED]]") | Should Be $false
    $visible.Contains("[[WAC_TUI_BUTTON_ROW]]") | Should Be $false
    $visible.Contains("12. Доверять созданному") | Should Be $true
    $visible.Contains("ARM64") | Should Be $false
  }

  It "shows an early ARM64 runtime warning on the setup mode screen" {
    $risk = [pscustomobject]@{ Level = "RISK"; Code = "Arm64Experimental"; ProductType = 1 }
    $lines = New-WacTuiModeLines -Language "Ru" -SelectedIndex 0 -PlatformRisk $risk
    $visible = ($lines | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $visible.Contains("Обнаружена ARM64") | Should Be $true
    $visible.Contains("работа Windows Admin Center на ARM64 не гарантируется") | Should Be $true
  }

  It "does not render ARM64 as a custom setup option" {
    $config = New-WacTuiConfig
    $lines = New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 0
    $visible = ($lines | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $visible.Contains("ARM64") | Should Be $false
  }

  It "shows uninstall actions first only for installations made by this setup" {
    $config = New-WacTuiConfig
    $notInstalled = [pscustomobject]@{ IsInstalledByThisSetup = $false; Config = $config }
    $installed = [pscustomobject]@{ IsInstalledByThisSetup = $true; Config = $config }

    $plain = (New-WacTuiActionLines -Language "Ru" -SelectedIndex 0 -InstallState $notInstalled | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $plain.Contains("Быстрая установка") | Should Be $true
    $plain.Contains("Удалить") | Should Be $false

    $withUninstall = New-WacTuiActionLines -Language "Ru" -SelectedIndex 0 -InstallState $installed | ForEach-Object { Remove-WacTuiSelectedLinePrefix -Text (Remove-WacTuiAnsi -Text $_) }
    ($withUninstall | Where-Object { $_ -match "Удалить Windows Admin Center" } | Select-Object -First 1).Trim().StartsWith("1.") | Should Be $true
    (($withUninstall -join "`n").Contains("Удалить полностью")) | Should Be $true
  }

  It "uses Russian text on welcome, detailed plan, and install status screens" {
    $config = New-WacTuiConfig
    $config.Language = "Ru"
    $welcome = (New-WacTuiWelcomeLines -Language "Ru") -join "`n"
    $welcome.Contains("Source:") | Should Be $false
    $welcome.Contains("Источник:") | Should Be $true

    $details = (New-WacTuiDetailedPlan -Config $config -Language "Ru") -join "`n"
    $details.Contains("InstallDir") | Should Be $false
    $details.Contains("Каталог установки") | Should Be $true
    $details.Contains("Права доступа") | Should Be $true

    $ready = (New-WacTuiReadyLines -Config $config -Language "Ru" -SelectedIndex 0) -join "`n"
    $ready.Contains("Express") | Should Be $false
    $ready.Contains("быстрая установка") | Should Be $true

    $logPath = Join-Path $env:TEMP "wac-ru-status-test.log"
    Set-Content -LiteralPath $logPath -Encoding UTF8 -Value @(
      "[01:00:00] [STEP] Extracting installer payload with D:\pkg\tools\innoextract.exe",
      "[01:00:01] [INFO] RUN: sc.exe query WindowsAdminCenter",
      "[01:00:02] [INFO] EXIT sc.exe: 0",
      "[01:00:03] [INFO] TCP port 6600 is listening",
      "Лог:  C:\WAC-Diag\wac.log"
    )
    $plan = [pscustomobject]@{ LogPath = $logPath; UsesSudo = $true }
    $status = (New-WacTuiInstallStatusLines -Plan $plan -Config $config) -join "`n"
    $status.Contains("Extract") | Should Be $false
    $status.Contains("PortCheck") | Should Be $false
    $status.Contains("Проверка HTTPS-порта") | Should Be $true
    $status.Contains("EXIT sc.exe") | Should Be $false
    $status.Contains("TCP-порт 6600 слушает подключения") | Should Be $true
    $status.Contains("Лог:") | Should Be $false
    $status.Contains("Журнал: C:\WAC-Diag\wac.log") | Should Be $true
  }

  It "translates internal setup engine log lines in the Russian install status tail" {
    Convert-WacTuiInstallLogLine -Language "Ru" -Line "[01:00:00] [INFO] Installer signature signer: CN=Microsoft Corporation" | Should Be ""
    Convert-WacTuiInstallLogLine -Language "Ru" -Line "[01:00:00] [STEP] Downloading innoextract from https://example.invalid/inno.zip" | Should Be "Загрузка innoextract: https://example.invalid/inno.zip"
    Convert-WacTuiInstallLogLine -Language "Ru" -Line "[01:00:00] [INFO] Downloaded and expanded innoextract official zip: C:\WAC\innoextract.exe" | Should Be "innoextract готов: C:\WAC\innoextract.exe"
    Convert-WacTuiInstallLogLine -Language "Ru" -Line "[01:00:00] [STEP] Extracting installer payload with C:\WAC\innoextract.exe" | Should Be "Извлечение файлов WAC: C:\WAC\innoextract.exe"
  }

  It "keeps install status height stable before log tail appears" {
    $config = New-WacTuiConfig
    $config.Language = "Ru"
    $logPath = Join-Path $env:TEMP "wac-empty-tail-test.log"
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    $plan = [pscustomobject]@{ LogPath = $logPath; UsesSudo = $true; UsesRunAs = $false }
    $emptyLines = New-WacTuiInstallStatusLines -Plan $plan -Config $config
    Set-Content -LiteralPath $logPath -Encoding UTF8 -Value @(
      "[01:00:00] [STEP] Extracting installer payload with tools\innoextract.exe",
      "[01:00:01] [INFO] Copying files",
      "[01:00:02] [INFO] Registering services",
      "[01:00:03] [INFO] TCP port 6600 is listening"
    )
    $filledLines = New-WacTuiInstallStatusLines -Plan $plan -Config $config
    $emptyLines.Count | Should Be $filledLines.Count
    $emptyLines.Count | Should BeGreaterThan 7
  }

  It "adds visual tone while preserving ASCII mode fallback" {
    $config = New-WacTuiConfig
    $config.Language = "Ru"
    $script:WacTuiUseVisuals = $true
    $script:WacTuiUseEmoji = $true
    $welcome = New-WacTuiFrame -Title "Welcome" -Lines (New-WacTuiWelcomeLines -Language "Ru" -SelectedIndex 0) -Width 120 -UseUnicode:$false
    ($welcome -join "`n").Contains("📦") | Should Be $true
    ($welcome -join "`n").Contains("$([char]27)[2m") | Should Be $true
    $mode = New-WacTuiFrame -Title "Mode" -Lines (New-WacTuiModeLines -Language "Ru" -SelectedIndex 3) -Width 120 -UseUnicode:$false
    $custom = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width 120 -UseUnicode:$false
    $details = New-WacTuiFrame -Title "Details" -Lines (New-WacTuiDetailsLines -Config $config -Language "Ru" -SelectedIndex 0) -Width 120 -UseUnicode:$false
    $statusPlan = [pscustomobject]@{ LogPath = "C:\WAC-Diag\missing-wac-visual-test.log"; UsesSudo = $true; UsesRunAs = $false }
    $status = New-WacTuiFrame -Title "Install" -Lines (New-WacTuiInstallStatusLines -Plan $statusPlan -Config $config) -Width 120 -UseUnicode:$false
    (($mode -join "`n").Contains("🧭")) | Should Be $true
    (($custom -join "`n").Contains("⚙️") -or ($custom -join "`n").Contains("⚙")) | Should Be $true
    (($details -join "`n").Contains("📋")) | Should Be $true
    (($status -join "`n").Contains("🚀")) | Should Be $true
    foreach ($line in $welcome) {
      (Get-WacTuiVisibleLength -Text $line) | Should Be 120
    }

    $script:WacTuiUseVisuals = $false
    $script:WacTuiUseEmoji = $false
    $plain = New-WacTuiFrame -Title "Welcome" -Lines (New-WacTuiWelcomeLines -Language "Ru" -SelectedIndex 0) -Width 120 -UseUnicode:$false
    ($plain -join "`n").Contains("📦") | Should Be $false
    ($plain -join "`n").Contains("$([char]27)[2m") | Should Be $false
    $plainCustom = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width 120 -UseUnicode:$false
    ($plainCustom -join "`n").Contains("⚙") | Should Be $false
  }

  It "uses the same button row style on welcome, mode, custom, and ready screens" {
    $config = New-WacTuiConfig
    $welcomeFrame = New-WacTuiFrame -Title "Welcome" -Lines (New-WacTuiWelcomeLines -Language "En" -SelectedIndex 0) -Width 100 -UseUnicode:$false
    $modeFrame = New-WacTuiFrame -Title "Mode" -Lines (New-WacTuiModeLines -Language "En" -SelectedIndex 2) -Width 100 -UseUnicode:$false
    $customFrame = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "En" -SelectedIndex 19) -Width 100 -UseUnicode:$false
    $readyFrame = New-WacTuiFrame -Title "Ready" -Lines (New-WacTuiReadyLines -Config $config -Language "En" -SelectedIndex 1) -Width 100 -UseUnicode:$false
    $welcomeLine = (@($welcomeFrame | ForEach-Object { Remove-WacTuiAnsi -Text $_ } | Where-Object { $_ -match '\[ Next \].*\[ Cancel \]' }))[0]
    $modeLine = (@($modeFrame | ForEach-Object { Remove-WacTuiAnsi -Text $_ } | Where-Object { $_ -match '\[ Back \].*\[ Cancel \]' }))[0]
    $customLine = (@($customFrame | ForEach-Object { Remove-WacTuiAnsi -Text $_ } | Where-Object { $_ -match '\[ Next \]' }))[0]
    $readyLine = (@($readyFrame | ForEach-Object { Remove-WacTuiAnsi -Text $_ } | Where-Object { $_ -match '\[ Back \].*\[ Details \].*\[ Install \].*\[ Cancel \]' }))[0]
    $welcomeLine.StartsWith("|    ") | Should Be $true
    $modeLine.StartsWith("|    ") | Should Be $true
    $customLine.StartsWith("|    ") | Should Be $true
    $readyLine.StartsWith("|    ") | Should Be $true
    $welcomeLine.Contains("<") | Should Be $false
    $modeLine.Contains("<") | Should Be $false
    $customLine.Contains("<") | Should Be $false
    $readyLine.Contains("<") | Should Be $false
  }

  It "does not render setup mode choices as checkboxes" {
    $lines = New-WacTuiModeLines -Language "En" -SelectedIndex 0
    ($lines -join "`n").Contains("[x]") | Should Be $false
    ($lines -join "`n").Contains("[ ]") | Should Be $false
  }

  It "renders selected danger actions as white text on red background" {
    $config = New-WacTuiConfig
    $script:WacTuiUseVisuals = $true
    $installed = [pscustomobject]@{ IsInstalledByThisSetup = $true; Config = $config }
    $frame = New-WacTuiFrame -Title "Mode" -Lines (New-WacTuiModeLines -Language "Ru" -SelectedIndex 1 -InstallState $installed) -Width 120 -UseUnicode:$false
    $dangerLine = (@($frame | Where-Object { (Remove-WacTuiAnsi -Text $_).Contains("Удалить полностью") }))[0]
    $dangerLine.Contains("$([char]27)[37;41m") | Should Be $true
    $dangerLine.Contains("$([char]27)[7m") | Should Be $false
    (($frame | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n").Contains("[ Next ]") | Should Be $false
  }

  It "wraps narrow button rows only between complete buttons" {
    $config = New-WacTuiConfig
    $visible = New-WacTuiFrame -Title "Ready" -Lines (New-WacTuiReadyLines -Config $config -Language "Ru" -SelectedIndex 2) -Width 50 -UseUnicode:$false |
      ForEach-Object { Remove-WacTuiAnsi -Text $_ }
    @($visible | Where-Object { $_ -match '\[ Назад \]' }).Count | Should Be 1
    @($visible | Where-Object { $_ -match '\[ Подробно \]' }).Count | Should Be 1
    @($visible | Where-Object { $_ -match '\[ Установить \]' }).Count | Should Be 1
    @($visible | Where-Object { $_ -match '\[ Отмена \]' }).Count | Should Be 1
    @($visible | Where-Object { $_ -match '^\| *\[ [^]]*$' }).Count | Should Be 0
  }

  It "keeps narrow custom option values readable without single-character value wraps" {
    $config = New-WacTuiConfig
    foreach ($width in @(40, 50, 60)) {
      $frame = New-WacTuiFrame -Title "Custom" -Lines (New-WacTuiCustomLines -Config $config -Language "Ru" -SelectedIndex 19) -Width $width -UseUnicode:$false
      $visible = $frame | ForEach-Object { Remove-WacTuiAnsi -Text $_ }
      ($visible -join "`n").Contains("defaul`n") | Should Be $false
      @($visible | Where-Object { $_ -match '^\| +[A-Za-zА-Яа-я]\s+\|$' }).Count | Should Be 0
      foreach ($line in $visible) {
        $line.Length | Should Be $width
      }
    }
  }

  It "moves custom setup selection by rows instead of requiring numbers" {
    Move-WacTuiSelection -SelectedIndex 0 -Delta 1 -ItemCount 21 | Should Be 1
    Move-WacTuiSelection -SelectedIndex 0 -Delta -1 -ItemCount 21 | Should Be 20
    Move-WacTuiSelection -SelectedIndex 20 -Delta 1 -ItemCount 21 | Should Be 0
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("key.Character -match '^[0-9]$'") | Should Be $false
  }

  It "formats checkbox-backed options from current config values" {
    $config = New-WacTuiConfig
    $config.KeepExistingData = $true
    Format-WacTuiConfigValue -Config $config -Key "KeepExistingData" -Language "En" | Should Be "[x]"
    $config.KeepExistingData = $false
    Format-WacTuiConfigValue -Config $config -Key "KeepExistingData" -Language "En" | Should Be "[ ]"
  }

  It "creates a short ready summary without low-level ACL details" {
    $config = New-WacTuiConfig
    $config.Port = 6600
    $summary = New-WacTuiReadySummary -Config $config
    ($summary -join "`n").Contains("ACL") | Should Be $false
    ($summary -join "`n").Contains("https://localhost:6600") | Should Be $true
  }

  It "uses uninstall-specific ready and progress text" {
    $config = New-WacTuiConfig
    $config.Language = "Ru"
    $config.Action = "UninstallFull"
    $config.InstallMode = "UninstallFull"
    $ready = New-WacTuiFrame -Title (Get-WacTuiReadyTitle -Config $config -Language "Ru") -Lines (New-WacTuiReadyLines -Config $config -Language "Ru" -SelectedIndex 2) -Width 120 -UseUnicode:$false
    $readyText = ($ready | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $readyText.Contains("Готово к удалению") | Should Be $true
    $readyText.Contains("[ Установить ]") | Should Be $false
    $readyText.Contains("[ Удалить полностью ]") | Should Be $true
    $readyText.Contains("После установки") | Should Be $false
    $readyText.Contains("Удаление") | Should Be $false
    $readyText.Contains("Данные: удалить") | Should Be $true

    $plan = [pscustomobject]@{ LogPath = "C:\WAC-Diag\missing-wac-uninstall-test.log"; UsesSudo = $true; UsesRunAs = $false }
    $status = New-WacTuiFrame -Title (Get-WacTuiOperationTitle -Config $config -Language "Ru") -Lines (New-WacTuiInstallStatusLines -Plan $plan -Config $config) -Width 120 -UseUnicode:$false
    $statusText = ($status | ForEach-Object { Remove-WacTuiAnsi -Text $_ }) -join "`n"
    $statusText.Contains("Удаление Windows Admin Center") | Should Be $true
    $statusText.Contains("Запускаю удаление") | Should Be $true
    $statusText.Contains("ход установки") | Should Be $false
  }

  It "creates detailed plan with low-level engine actions" {
    $config = New-WacTuiConfig
    $details = New-WacTuiDetailedPlan -Config $config
    ($details -join "`n").Contains("HTTP.SYS") | Should Be $true
    ($details -join "`n").Contains("ACL") | Should Be $true
  }

  It "refuses apply when terms were not accepted" {
    $config = New-WacTuiConfig
    $config.Language = "En"
    try {
      Assert-WacTuiCanApply -Config $config
      throw "Apply assertion did not fail."
    } catch {
      $_.Exception.Message | Should Match "License terms"
    }
  }
}

Describe "WacTui process invocation" {
  BeforeAll {
    . (Join-Path $RepoRoot "interactive-installer.ps1")
  }

  It "builds a PowerShell process invocation without string-joining arguments" {
    $config = New-WacTuiConfig
    $config.AcceptedTerms = $true
    $plan = New-WacTuiApplyProcessPlan -Config $config -PowerShellPath "powershell.exe" -SetupEnginePath "D:\pkg\wac-setup-engine.ps1" -LogPath "C:\WAC-Diag\wac-test.log" -IsAdmin:$true
    $plan.FilePath | Should Be "powershell.exe"
    $plan.ArgumentList -is [string[]] | Should Be $true
    $plan.ArgumentList[0] | Should Be "-NoLogo"
    $plan.ArgumentList -contains "-File" | Should Be $true
    $plan.ArgumentList -contains "D:\pkg\wac-setup-engine.ps1" | Should Be $true
    $plan.ArgumentList -contains "-LogPath" | Should Be $true
    $plan.ArgumentList -contains "C:\WAC-Diag\wac-test.log" | Should Be $true
    $plan.UsesSudo | Should Be $false
  }

  It "builds uninstall process arguments without purging data by default" {
    $config = New-WacTuiConfig
    $config.AcceptedTerms = $true
    $config.Action = "Uninstall"
    $plan = New-WacTuiApplyProcessPlan -Config $config -PowerShellPath "powershell.exe" -SetupEnginePath "D:\pkg\wac-setup-engine.ps1" -LogPath "C:\WAC-Diag\wac-test.log" -IsAdmin:$true
    $plan.ArgumentList -contains "-Uninstall" | Should Be $true
    $plan.ArgumentList -contains "-PurgeData" | Should Be $false
  }

  It "builds full uninstall process arguments with data purge" {
    $config = New-WacTuiConfig
    $config.AcceptedTerms = $true
    $config.Action = "UninstallFull"
    $plan = New-WacTuiApplyProcessPlan -Config $config -PowerShellPath "powershell.exe" -SetupEnginePath "D:\pkg\wac-setup-engine.ps1" -LogPath "C:\WAC-Diag\wac-test.log" -IsAdmin:$true
    $plan.ArgumentList -contains "-Uninstall" | Should Be $true
    $plan.ArgumentList -contains "-PurgeData" | Should Be $true
  }

  It "wraps the setup engine in sudo instead of opening a second admin window" {
    $config = New-WacTuiConfig
    $config.AcceptedTerms = $true
    $plan = New-WacTuiApplyProcessPlan -Config $config -PowerShellPath "powershell.exe" -SetupEnginePath "D:\pkg\wac-setup-engine.ps1" -LogPath "C:\WAC-Diag\wac-test.log" -SudoPath "sudo.exe" -IsAdmin:$false
    $plan.FilePath | Should Be "sudo.exe"
    $plan.ArgumentList[0] | Should Be "powershell.exe"
    $plan.ArgumentList -contains "-File" | Should Be $true
    $plan.UsesSudo | Should Be $true
    $plan.UsesRunAs | Should Be $false
  }

  It "falls back to runas elevation when Windows sudo is not available" {
    $config = New-WacTuiConfig
    $config.AcceptedTerms = $true
    $plan = New-WacTuiApplyProcessPlan -Config $config -PowerShellPath "powershell.exe" -SetupEnginePath "D:\pkg\wac-setup-engine.ps1" -LogPath "C:\WAC-Diag\wac-test.log" -SudoPath "" -IsAdmin:$false
    $plan.FilePath | Should Be "powershell.exe"
    $plan.ArgumentList[0] | Should Be "-NoLogo"
    $plan.ArgumentList -contains "-File" | Should Be $true
    $plan.UsesSudo | Should Be $false
    $plan.UsesRunAs | Should Be $true
  }

  It "keeps redirected process output away from the TUI console" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("function Clear-WacTuiScreen") | Should Be $true
    $text.Contains("function Invoke-WacTuiProcessHidden") | Should Be $true
    $text.Contains("function Invoke-WacTuiProcessRunAs") | Should Be $true
    $text.Contains("function New-WacTuiInstallRenderState") | Should Be $true
    $text.Contains("function Test-WacTuiShouldRenderInstallStatus") | Should Be $true
    $text.Contains("function Get-WacTuiInstallRenderSignature") | Should Be $true
    $text.Contains("function Set-WacTuiCursorVisible") | Should Be $true
    $text.Contains("CreateNoWindow = `$true") | Should Be $true
    $text.Contains("RedirectStandardOutput = `$true") | Should Be $true
    $text.Contains("RedirectStandardError = `$true") | Should Be $true
    $text.Contains("Verb = `"runas`"") | Should Be $true
    $text.Contains("ProcessWindowStyle]::Hidden") | Should Be $true
    $text.Contains("function Wait-WacTuiOnExit") | Should Be $true
    $text.Contains("PressEnterToClose") | Should Be $true
  }

  It "treats user cancellation as a normal exit without an error stack" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains("throw (Get-WacTuiUiText -Key `"Cancelled`"") | Should Be $false
    $text.Contains("if (`$null -eq `$wizardResult)") | Should Be $true
    $text.Contains("exit 0") | Should Be $true
    $text.Contains("ScriptStackTrace") | Should Be $true
  }

  It "can run a hidden child process under Windows PowerShell 5.1" {
    $powerShellPath = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
    $plan = [pscustomobject]@{
      FilePath = $powerShellPath
      ArgumentList = [string[]]@("-NoProfile", "-Command", "Write-Output ok")
      LogPath = "C:\WAC-Diag\wac-test.log"
      UsesSudo = $false
    }
    $runner = Invoke-WacTuiProcessHidden -Plan $plan
    $runner.Process.WaitForExit()
    $runner.StdOutTask.Wait(2000) | Out-Null
    $runner.StdErrTask.Wait(2000) | Out-Null
    $runner.Process.ExitCode | Should Be 0
    $runner.StdOutTask.Result.Trim() | Should Be "ok"
    $runner.Process.Dispose()
  }

  It "decodes hidden child stdout and stderr as UTF-8" {
    $scriptPath = Join-Path $RepoRoot "interactive-installer.ps1"
    $text = Get-Content -LiteralPath $scriptPath -Raw
    $text.Contains('$utf8NoBom = [System.Text.UTF8Encoding]::new($false)') | Should Be $true
    $text.Contains('$process.StartInfo.StandardOutputEncoding = $utf8NoBom') | Should Be $true
    $text.Contains('$process.StartInfo.StandardErrorEncoding = $utf8NoBom') | Should Be $true
  }

  It "builds install status lines under Windows PowerShell 5.1-compatible ToArray usage" {
    $config = New-WacTuiConfig
    $config.Language = "En"
    $plan = [pscustomobject]@{
      LogPath = "C:\WAC-Diag\missing-wac-test.log"
      UsesSudo = $true
    }
    $lines = New-WacTuiInstallStatusLines -Plan $plan -Config $config
    $lines -is [string[]] | Should Be $true
    ($lines -join "`n") | Should Match "UAC"
  }

  It "shows a localized runas fallback hint when sudo is unavailable" {
    $config = New-WacTuiConfig
    $config.Language = "Ru"
    $plan = [pscustomobject]@{
      LogPath = "C:\WAC-Diag\missing-wac-test.log"
      UsesSudo = $false
      UsesRunAs = $true
    }
    $lines = New-WacTuiInstallStatusLines -Plan $plan -Config $config
    ($lines -join "`n").Contains("Windows sudo не найден") | Should Be $true
    ($lines -join "`n").Contains("журнал") | Should Be $true
  }

  It "keeps install progress monotonic when the log is temporarily unreadable" {
    $config = New-WacTuiConfig
    $config.Language = "Ru"
    $logPath = Join-Path $env:TEMP "wac-monotonic-progress-test.log"
    Set-Content -LiteralPath $logPath -Encoding UTF8 -Value @(
      "[01:00:00] [STEP] Extracting installer payload with tools\innoextract.exe",
      "[01:00:01] [INFO] Registering services"
    )
    $plan = [pscustomobject]@{ LogPath = $logPath; UsesSudo = $true }
    $state = New-WacTuiInstallRenderState
    [void](New-WacTuiInstallStatusLines -Plan $plan -Config $config -RenderState $state)
    $state.LastPercent | Should Be 88
    $state.LastPhaseName | Should Be "Services"

    Remove-Item -LiteralPath $logPath -Force
    $lines = New-WacTuiInstallStatusLines -Plan $plan -Config $config -RenderState $state
    ($lines -join "`n").Contains("88%") | Should Be $true
    ($lines -join "`n").Contains("Регистрация служб") | Should Be $true
    $state.LastPercent | Should Be 88
  }

  It "throttles install status redraws for line-by-line log churn" {
    $state = New-WacTuiInstallRenderState
    $t0 = [datetime]"2026-04-29T00:00:00Z"
    Test-WacTuiShouldRenderInstallStatus -State $state -Lines @("bar 5%", "status", "log", "", "tail 1") -NowUtc $t0 | Should Be $true
    Test-WacTuiShouldRenderInstallStatus -State $state -Lines @("bar 5%", "status", "log", "", "tail 2") -NowUtc $t0.AddMilliseconds(950) | Should Be $false
    Test-WacTuiShouldRenderInstallStatus -State $state -Lines @("bar 5%", "new status", "log", "", "tail 2") -NowUtc $t0.AddMilliseconds(1200) | Should Be $false
    Test-WacTuiShouldRenderInstallStatus -State $state -Lines @("bar 25%", "new status", "log", "", "tail 2") -NowUtc $t0.AddMilliseconds(1500) | Should Be $true
  }

  It "accepts blank separator lines in install status redraw checks" {
    $state = New-WacTuiInstallRenderState
    $t0 = [datetime]"2026-04-29T00:00:00Z"
    Test-WacTuiShouldRenderInstallStatus -State $state -Lines @("progress", "", "log tail") -NowUtc $t0 | Should Be $true
  }

  It "builds install redraw signatures without volatile log tail lines" {
    $signature = Get-WacTuiInstallRenderSignature -Lines @("bar", "status", "log", "", "tail 1", "tail 2")
    $signature.Contains("bar") | Should Be $true
    $signature.Contains("status") | Should Be $false
    $signature.Contains("tail") | Should Be $false
  }

  It "appends hidden child stderr but not duplicated setup engine stdout to the install log on failure" {
    $logPath = Join-Path $env:TEMP "wac-child-output-test.log"
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $logPath -Value "[00:00:00] [INFO] before" -Encoding UTF8
    $plan = [pscustomobject]@{ LogPath = $logPath }
    $runner = [pscustomobject]@{
      StdOutTask = [System.Threading.Tasks.Task[string]]::FromResult("out-line")
      StdErrTask = [System.Threading.Tasks.Task[string]]::FromResult("err-line")
    }
    Add-WacTuiChildProcessOutputToLog -Plan $plan -Runner $runner
    $text = Get-Content -LiteralPath $logPath -Raw
    $text.Contains("[CHILD-STDOUT]") | Should Be $false
    $text.Contains("out-line") | Should Be $false
    $text.Contains("[CHILD-STDERR]") | Should Be $true
    $text.Contains("err-line") | Should Be $true
  }

  It "reads install logs without blocking concurrent writer access" {
    $logPath = Join-Path $env:TEMP "wac-shared-log-test.log"
    Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $logPath -Value "[00:00:00] [INFO] first" -Encoding UTF8
    [void](Get-WacTuiInstallLogLines -LogPath $logPath)
    Add-Content -LiteralPath $logPath -Value "[00:00:01] [INFO] second" -Encoding UTF8
    $lines = Get-WacTuiInstallLogLines -LogPath $logPath
    ($lines -join "`n") | Should Match "second"
  }
}

Describe "Publish path hygiene" {
  It "does not contain user or drive-specific workspace paths in publish scripts" {
    $files = Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Include *.ps1,*.cmd,*.md |
      Where-Object {
        $_.FullName -notmatch "\\dist\\" -and
        $_.FullName -notmatch "\\tmp\\" -and
        $_.FullName -notmatch "\\local\\" -and
        $_.FullName -notmatch "\\.codex\\" -and
        $_.FullName -notmatch "\\.tools\\"
      }
    $workspacePath = "D:" + "\" + $env:USERNAME
    $userRoot = "C:" + "\Users\" + $env:USERNAME
    $downloadsPath = "Downloads" + "\"
    $experimentPath = "WAC" + "_experiments"
    $matches = Select-String -Path $files.FullName -Pattern $workspacePath,$userRoot,$downloadsPath,$experimentPath -SimpleMatch
    @($matches).Count | Should Be 0
  }
}





