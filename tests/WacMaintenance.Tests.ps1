Describe 'WAC certificate maintenance' {
  BeforeAll {
    function Assert-FailsWith {
      param([scriptblock]$Operation, [string]$Expected)
      try { & $Operation } catch {
        $_.Exception.Message | Should -Match ([regex]::Escape($Expected))
        return
      }
      throw "Expected an error containing '$Expected'."
    }
    $root = Split-Path -Parent $PSScriptRoot
    . (Join-Path $root 'wac-certificate.ps1')
    . (Join-Path $root 'tui/WacTui.Model.ps1')
    # Load the production functions without executing the elevated installer.
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'wac-setup-engine.ps1'), [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw $errors[0] }
    $functions = $ast.FindAll({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst]}, $false)
    foreach ($fn in $functions) { . ([scriptblock]::Create($fn.Extent.Text)) }
  }

  It 'validates conflicting arguments during preview before elevation or log creation' {
    $engine = Join-Path $root 'wac-setup-engine.ps1'
    $logPath = Join-Path $TestDrive 'preview/setup.log'
    Assert-FailsWith { & $engine -WhatIf -GenerateCertificate -CertificateThumbprint ('A'*40) -LogPath $logPath } 'Conflicting certificate'
    & $engine -WhatIf -RenewCertificate -LogPath $logPath
    (Test-Path -LiteralPath (Split-Path $logPath)) | Should -Be $false
  }

  It 'rejects an expired supplied certificate before accessing its private key' {
    $cert = [pscustomobject]@{ Thumbprint=('A'*40); NotBefore=(Get-Date).AddDays(-61); NotAfter=(Get-Date).AddDays(-1) }
    Assert-FailsWith { Assert-SuppliedCertificateUsableForWac $cert } 'outside its validity period'
  }

  It 'rejects a supplied certificate whose validity has not started' {
    $cert = [pscustomobject]@{ Thumbprint=('B'*40); NotBefore=(Get-Date).AddDays(1); NotAfter=(Get-Date).AddDays(60) }
    Assert-FailsWith { Assert-SuppliedCertificateUsableForWac $cert } 'outside its validity period'
  }

  Context 'Supplied certificates and legacy markers' {
    It 'rejects an untrusted operator certificate even when its key and names are usable' {
      $rsa = if ($env:OS -eq 'Windows_NT') {
        [Security.Cryptography.RSACng]::new(2048)
      } else { [Security.Cryptography.RSA]::Create(2048) }
      $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
        'CN=localhost', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
      $cert = $request.CreateSelfSigned([DateTimeOffset]::Now.AddHours(-1), [DateTimeOffset]::Now.AddHours(1))
      Mock Test-CertificateHasUsablePrivateKey { $true }
      Mock Test-CertificateHasServerAuthentication { $true }
      Mock Test-CertificateUsableForWac { $true }
      try {
        Assert-FailsWith { Assert-SuppliedCertificateUsableForWac $cert } 'trusted server authentication chain'
      } finally { $cert.Dispose(); $rsa.Dispose() }
    }

    It 'reads UTF-8 marker and appsettings paths when the shell defaults to another encoding' {
      $PSDefaultParameterValues = @{'Get-Content:Encoding' = 'ASCII'}
      $label = -join ([char[]](0x041F,0x0443,0x0442,0x044C))
      $path = Join-Path $TestDrive 'utf8.json'
      Mock Assert-WacLocalPath {}
      Write-WacJsonAtomic $path @{installedBy='wac-client-windows-setup'; dataDir=$label}
      (Read-WacSetupMarker -Path $path).dataDir | Should -BeExactly $label
      (Read-WacAppSettingsJson -AppSettingsPath $path).dataDir | Should -BeExactly $label
    }

    It 'prefers the protected marker after migrating legacy state' {
      $data = Join-Path $TestDrive 'old-data'
      $safe = Join-Path $TestDrive 'protected'
      $null = New-Item -ItemType Directory -Path $data,$safe -Force
      Mock Get-WacMaintenanceDirectory { $safe }
      Mock Assert-WacLocalPath {}
      Mock Grant-WacMarkerReadAccess {}
      $old = Join-Path $data 'wac-setup.json'
      Write-WacJsonAtomic $old @{dataDir=$data; port=6600}
      (Get-WacReadableMarkerPath $data) | Should -Be $old
      Write-WacProtectedMarker ([pscustomobject]@{dataDir=$data; port=7443})
      (Test-Path -LiteralPath $old) | Should -Be $false
      Write-WacJsonAtomic $old @{dataDir=$data; port=8080}
      $selected = Get-WacReadableMarkerPath $data
      $selected | Should -Be (Join-Path $safe 'wac-setup.json')
      (Get-Content -LiteralPath $selected -Raw | ConvertFrom-Json).port | Should -Be 7443
    }

    It 'distinguishes an absent legacy marker from foreign or unreadable installation state' {
      $DataDir = Join-Path $TestDrive 'legacy-marker'
      $null = New-Item -ItemType Directory -Path $DataDir
      Mock Get-WacProtectedMarkerPath { Join-Path $TestDrive 'no-protected-marker.json' }
      Mock Assert-WacLocalPath {}
      $path = Get-WacSetupMarkerPath $DataDir
      Read-WacSetupMarker | Should -BeNullOrEmpty
      [IO.File]::WriteAllText($path, '{"installedBy":"another-package"}')
      Assert-FailsWith { Read-WacSetupMarker } 'Unexpected setup marker identity'
      [IO.File]::WriteAllText($path, '{')
      Assert-FailsWith { Read-WacSetupMarker } 'Could not read setup marker'
      [IO.File]::WriteAllText($path, '{"installedBy":"wac-client-windows-setup","port":7443}')
      (Read-WacSetupMarker).port | Should -Be 7443
    }

    It 'uses a custom data directory from a protected marker when no directory was specified' {
      if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($ClassName,$Filter) }
      }
      $DataDir = Join-Path $TestDrive 'default-data'
      $marker = [pscustomobject]@{installDir=(Join-Path $TestDrive 'program'); dataDir=(Join-Path $TestDrive 'custom-data')}
      $script:OriginalBoundParameters = @{}
      Mock Get-CimInstance { [pscustomobject]@{PathName=[IO.Path]::Combine($TestDrive,'program','Service','WindowsAdminCenter.exe')} }
      Assert-WacMarkerDirectories -Marker $marker -ProtectedMarker
      Assert-FailsWith { Assert-WacMarkerDirectories -Marker $marker } 'selected data directory'
      $script:OriginalBoundParameters = @{DataDir=$DataDir}
      Assert-FailsWith { Assert-WacMarkerDirectories -Marker $marker -ProtectedMarker } 'selected data directory'
      $DataDir = $marker.dataDir
      Assert-WacMarkerDirectories -Marker $marker -ProtectedMarker
    }

    It 'rejects an unverified legacy removal path before touching the installation' {
      if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($ClassName,$Filter) }
      }
      $DataDir = Join-Path $TestDrive 'data'
      $marker = [pscustomobject]@{installDir=(Join-Path $TestDrive 'other'); dataDir=$DataDir}
      $script:OriginalBoundParameters = @{}
      Mock Get-WacProtectedMarkerPath { Join-Path $TestDrive 'missing.json' }
      Mock Get-CimInstance { [pscustomobject]@{PathName=[IO.Path]::Combine($TestDrive,'program','Service','WindowsAdminCenter.exe')} }
      Assert-FailsWith { Assert-WacMarkerDirectories $marker } 'registered gateway service'
      $marker.installDir = Join-Path $TestDrive 'program'
      Assert-WacMarkerDirectories $marker
      Mock Get-CimInstance { $null }
      Assert-FailsWith { Assert-WacMarkerDirectories $marker } 'without the registered gateway service'
    }
  }

  Context 'Wizard marker checks' {
    BeforeAll {
      . (Join-Path $root 'interactive-installer.ps1')
      if (-not (Get-Command Get-Service -ErrorAction SilentlyContinue)) {
        function Get-Service { param($Name) }
      }
    }
    BeforeEach {
      $fixture = New-Item -ItemType Directory -Path (Join-Path $TestDrive ([guid]::NewGuid().ToString('N')))
      $data = $fixture.FullName
      $protected = Join-Path $data 'protected.json'
      $legacy = Join-Path $data 'wac-setup.json'
      Mock Get-WacProtectedMarkerPath { $protected }
      Mock Get-Service { $null }
      Mock Assert-WacLocalPath {}
    }
    It 'distinguishes absent, owned and conflicting legacy markers' {
      (Get-WacTuiInstallState -DataDir $data).MarkerStatus | Should -Be 'Absent'
      Write-WacJsonAtomic $legacy @{installedBy='wac-client-windows-setup'; dataDir=$data; port=7443}
      $state = Get-WacTuiInstallState -DataDir $data
      $state.MarkerStatus | Should -Be 'Valid'
      $state.Config.Port | Should -Be 7443
      Write-WacJsonAtomic $legacy @{installedBy='wac-client-windows-setup'; dataDir=(Join-Path $data 'other')}
      (Get-WacTuiInstallState -DataDir $data).MarkerStatus | Should -Be 'Invalid'
    }
    It 'adopts the protected data directory and rejects a conflicting custom selection' {
      Write-WacJsonAtomic $protected @{installedBy='wac-client-windows-setup'; dataDir=$data; port=7443}
      $state = Get-WacTuiInstallState
      $state.MarkerStatus | Should -Be 'Valid'
      $state.Config.DataDir | Should -Be $data
      (Get-WacTuiInstallState -DataDir $data).MarkerStatus | Should -Be 'Valid'
      (Get-WacTuiInstallState -DataDir (Join-Path $data 'other')).MarkerStatus | Should -Be 'Invalid'
    }
    It 'blocks a foreign protected marker before the wizard offers actions' {
      Write-WacJsonAtomic $protected @{installedBy='another-package'}
      Mock Get-WacTuiCurrentPlatformRisk { throw 'Wizard advanced past marker check' }
      Assert-FailsWith { Start-WacTuiWizard } $protected
    }
    It 'blocks an unreadable protected marker even when a valid legacy marker exists' {
      Write-WacJsonAtomic $legacy @{installedBy='wac-client-windows-setup'; dataDir=$data}
      Write-WacJsonAtomic $protected @{installedBy='wac-client-windows-setup'; dataDir=$data}
      Mock Get-Content { throw 'Access denied' } -ParameterFilter { $LiteralPath -eq $protected }
      $state = Get-WacTuiInstallState -DataDir $data
      $state.MarkerStatus | Should -Be 'Invalid'
      $state.MarkerPath | Should -Be $protected
    }
    It 'reports a malformed marker in the selected directory before launching setup' {
      [IO.File]::WriteAllText($legacy, '{')
      $config = New-WacTuiConfig
      $config.DataDir = $data
      $config.Language = 'En'
      Mock Get-WacTuiWindowsPowerShellPath { throw 'Wizard started building a process plan' }
      Assert-FailsWith { Invoke-WacTuiApply -Config $config } $legacy
    }
  }

  Context 'Final gateway verification' {
    It 'records the installed certificate and renewal mode before a failing TLS check (<mode>)' -TestCases @(
      @{mode='Generated'}, @{mode='Explicit'}
    ) {
      param($mode)
      $cert = [pscustomobject]@{Thumbprint=('B'*40)}
      $CertificateThumbprint = if ($mode -eq 'Explicit') { $cert.Thumbprint } else { '' }
      $EndpointFqdn = 'gateway.example.test'
      $ServiceFqdn = 'localhost'
      $Port = 7443
      $TrustSelfSignedCertificate = $false
      $script:record = [pscustomobject]@{productVersion='old'; certificateThumbprint=('A'*40)}
      $script:taskMode = 'old'
      Mock Write-WacSetupMarker {
        $script:record.productVersion = $ProductVersion
        $script:record.certificateThumbprint = $CertificateHash
      }
      Mock Read-WacSetupMarker { $script:record }
      Mock Register-WacRenewalTask { $script:taskMode = $Marker.certificateThumbprint }
      Mock Remove-WacRenewalTask { $script:taskMode = 'removed' }
      Mock Write-Log {}
      Mock Test-TcpPort { $true }
      Mock Get-RequiredGeneratedCertificateDnsNames { @('gateway.example.test','localhost') }
      Mock Assert-WacServedCertificate { throw 'TLS check failed' }
      Assert-FailsWith { Complete-WacGatewaySetup -Certificate $cert -ProductVersion '2611' -EnginePath 'engine.ps1' } 'TLS check failed'
      $script:record.productVersion | Should -Be '2611'
      $script:record.certificateThumbprint | Should -Be $cert.Thumbprint
      $expectedTask = if ($mode -eq 'Explicit') { 'removed' } else { $cert.Thumbprint }
      $script:taskMode | Should -Be $expectedTask
    }
  }

  It 'classifies a legacy wrapper certificate even when it has expired' {
    Mock Get-Item { [pscustomobject]@{ Issuer='CN=test'; Subject='CN=test'; FriendlyName='Windows Admin Center Self-Signed Certificate'; Extensions=@([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true)) } } -ParameterFilter { $LiteralPath -like 'Cert:*' }
    $marker = [pscustomobject]@{ certificateThumbprint=('A'*40) }
    Get-WacMarkerCertificateSource $marker | Should -Be 'Generated'
  }

  It 'does not adopt a self-signed CA with the wrapper friendly name' {
    Mock Get-Item {
      $constraint = [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($true,$false,0,$true)
      [pscustomobject]@{Issuer='CN=test'; Subject='CN=test'; FriendlyName='Windows Admin Center Self-Signed Certificate'; Extensions=@($constraint)}
    } -ParameterFilter { $LiteralPath -like 'Cert:*' }
    Get-WacMarkerCertificateSource ([pscustomobject]@{certificateThumbprint=('A'*40)}) | Should -Be 'Explicit'
  }

  It 'keeps unknown legacy certificates pinned and honors explicit ownership' {
    Mock Get-Item { $null } -ParameterFilter { $LiteralPath -like 'Cert:*' }
    $marker = [pscustomobject]@{ certificateThumbprint=('A'*40) }
    Get-WacMarkerCertificateSource $marker | Should -Be 'Explicit'
    $marker | Add-Member certificateSource 'Explicit'
    Get-WacMarkerCertificateSource $marker | Should -Be 'Explicit'
  }

  It 'keeps generated mode and the trust setting through the wizard' {
    $marker = [pscustomobject]@{ certificateSource='Generated'; certificateThumbprint=('A'*40); trustSelfSignedCertificate=$true }
    $config = ConvertFrom-WacSetupMarker $marker
    $argsList = ConvertTo-WacSetupEngineArguments $config
    ($argsList -contains '-GenerateCertificate') | Should -Be $false
    ($argsList -contains '-CertificateThumbprint') | Should -Be $false
    ($argsList -contains '-TrustSelfSignedCertificate') | Should -Be $true
  }

  It 'leaves explicitly selected certificates outside renewal' {
    $marker = [pscustomobject]@{ certificateSource='Explicit'; certificateThumbprint=('A'*40) }
    Assert-FailsWith { Invoke-WacManualRenewal $marker 'engine.ps1' } 'externally managed'
  }

  It 'forwards an explicit wizard change from a pinned certificate to generated mode' {
    $marker = [pscustomobject]@{ certificateSource='Explicit'; certificateThumbprint=('A'*40) }
    $config = ConvertFrom-WacSetupMarker $marker
    $config.CertificateThumbprint = ''
    ((ConvertTo-WacSetupEngineArguments $config) -contains '-GenerateCertificate') | Should -Be $true
  }

  It 'atomically updates an existing marker while retaining unrelated fields' {
    $file = Join-Path $TestDrive 'marker.json'
    $marker = [pscustomobject]@{ port=6600; certificateThumbprint=('A'*40) }
    Write-WacJsonAtomic $file $marker
    $marker.certificateThumbprint = 'B'*40
    Write-WacJsonAtomic $file $marker
    $saved = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    $saved.port | Should -Be 6600
    $saved.certificateThumbprint | Should -Be ('B'*40)
  }
  It 'selects the two Administration Mode services from a combined installer' {
    $services = @(@{Name='WinREST'},@{Name='WinStream'})
    $admin = [pscustomobject]@{WindowsAdminCenter=[pscustomobject]@{Services=$services}}
    $other = [pscustomobject]@{WindowsAdminCenter=[pscustomobject]@{Services=($services + @{Name='EnterpriseData'}); EnterpriseService=@{}}}
    (Test-WacAdministrationTemplate $admin) | Should -Be $true
    (Test-WacAdministrationTemplate $other) | Should -Be $false
  }
  It 'recovers a colliding Administration Mode template before installing any services' {
    $ExtractOut = Join-Path $TestDrive 'combined'
    $PayloadApp = Join-Path $ExtractOut 'app'
    $SkipExtraction = $false
    $InnoExtractPath = 'innoextract.exe'
    $InstallerPath = 'sample.exe'
    $null = New-Item -ItemType Directory -Path (Join-Path $PayloadApp 'Service') -Force
    $virtual = @{WindowsAdminCenter=@{Services=@(@{Name='EnterpriseData'}); EnterpriseService=@{}}}
    Write-WacJsonAtomic (Join-Path $PayloadApp 'Service/appsettings.json') $virtual
    Mock Invoke-LoggedProcess {
      # The Windows build exits successfully even when the include filter matches no entry.
      $include = $ArgumentList[[Array]::IndexOf($ArgumentList,'--include') + 1]
      if ($include -cne 'app\Service\appsettings.json') { return [pscustomobject]@{ExitCode=0} }
      $out = $ArgumentList[[Array]::IndexOf($ArgumentList,'--output-dir') + 1]
      $variants = Join-Path $out 'app/Service'
      $null = New-Item -ItemType Directory -Path $variants -Force
      Write-WacJsonAtomic (Join-Path $variants 'appsettings.json') $virtual
      $admin = @{WindowsAdminCenter=@{Services=@(@{Name='WinREST'},@{Name='WinStream'})}}
      Write-WacJsonAtomic (Join-Path $variants 'appsettings.json$0') $admin
      [pscustomobject]@{ExitCode=0}
    }
    $selected = Resolve-WacAdministrationTemplate $PayloadApp
    (Split-Path -Leaf $selected) | Should -Be 'appsettings.json$0'
    Mock Invoke-LoggedProcess { [pscustomobject]@{ExitCode=0} }
    Assert-FailsWith { Resolve-WacAdministrationTemplate $PayloadApp } 'No Administration Mode configuration variants'
    $SkipExtraction = $true
    Assert-FailsWith { Resolve-WacAdministrationTemplate $PayloadApp } 'Offline payload'
  }
  It 'allows scheduled renewal to start and finish on battery power' {
    $command = (Get-Command Register-WacRenewalTask).ScriptBlock.Ast.Find({
      param($node)
      $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -eq 'New-ScheduledTaskSettingsSet'
    }, $true)
    $switches = @($command.CommandElements | Where-Object { $_ -is [Management.Automation.Language.CommandParameterAst] } |
      ForEach-Object { $_.ParameterName })
    $switches | Should -Contain 'AllowStartIfOnBatteries'
    $switches | Should -Contain 'DontStopIfGoingOnBatteries'
  }

  It 'ignores DELETE only on the volume root and keeps child replacement rights blocked' {
    $rootPath = [IO.Path]::GetPathRoot($TestDrive)
    $rootMask = Get-WacUnsafeAccessMask $rootPath -Ancestor
    $parentMask = Get-WacUnsafeAccessMask $TestDrive -Ancestor
    ($rootMask -band 0x1301bf) | Should -Be 0
    ($rootMask -band 0xC0040) | Should -Be 0xC0040
    ($parentMask -band 0x1301bf) | Should -Be 0x10000
    ((Get-WacUnsafeAccessMask $TestDrive) -band 0x156) | Should -Be 0x156
  }

  Context 'Upgrade directory fixtures' {
    It 'preserves data for this install and persists the chosen default (<case>)' -TestCases @(
      @{case='refresh existing data'; refresh=$true; existing=$true; marked=$false; keep=$false; preserve=$true}
      @{case='refresh with marker'; refresh=$true; existing=$false; marked=$true; keep=$false; preserve=$true}
      @{case='fresh install via refresh'; refresh=$true; existing=$false; marked=$false; keep=$false; preserve=$false}
      @{case='explicit keep'; refresh=$false; existing=$true; marked=$false; keep=$true; preserve=$true}
      @{case='ordinary reinstall'; refresh=$false; existing=$true; marked=$true; keep=$false; preserve=$false}
    ) {
      param($case, $refresh, $existing, $marked, $keep, $preserve)
      $work = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
      $DataDir = Join-Path $work 'data'
      $InstallDir = Join-Path $work 'program'
      $RefreshInstaller = $refresh
      $KeepExistingData = $keep
      $marker = if ($marked) { [pscustomobject]@{keepExistingData=$keep} }
      $app = Join-Path $work 'app'
      $payload = Join-Path $work 'payload-data'
      $template = Join-Path $app 'Service/appsettings.json'
      $uxFile = Join-Path $payload 'UX/index.html'
      $null = New-Item -ItemType Directory -Path (Split-Path $template),(Split-Path $uxFile) -Force
      [IO.File]::WriteAllText($template, '{}')
      [IO.File]::WriteAllText($uxFile, 'updated')
      [IO.File]::WriteAllText((Join-Path $payload 'seed.txt'), 'seed')
      $connection = Join-Path $DataDir 'connection.txt'
      if ($existing) {
        $null = New-Item -ItemType Directory -Path $DataDir
        [IO.File]::WriteAllText($connection, 'saved')
      }
      $markerPath = Join-Path $work 'protected-marker.json'
      Mock Assert-WacLocalPath {}
      Mock Set-WacDirectorySecurity {}
      Mock Assert-WacCodeAccess {}
      Mock Get-WacProtectedMarkerPath { $markerPath }
      Mock Grant-WacMarkerReadAccess {}
      Mock Write-Log {}

      Install-WacPayload -PayloadApp $app -PayloadData $payload -AdminTemplate $template -SetupMarker $marker
      Write-WacSetupMarker
      (Read-WacSetupMarker -Path $markerPath).keepExistingData | Should -Be $keep
      (Test-Path -LiteralPath $connection) | Should -Be ($existing -and $preserve)
      (Test-Path -LiteralPath (Join-Path $DataDir 'seed.txt')) | Should -Be (-not $preserve)
      [IO.File]::ReadAllText((Join-Path $DataDir 'UX/index.html')) | Should -Be 'updated'
    }

    It 'rebuilds legacy code trees while preserving the database on upgrade' {
      $InstallDir = Join-Path $TestDrive 'program'
      $DataDir = Join-Path $TestDrive 'data'
      $updater = Join-Path $DataDir 'Updater'
      $database = Join-Path $DataDir 'Database'
      $null = New-Item -ItemType Directory -Path $updater,$database,$InstallDir -Force
      foreach ($dir in @($updater,$InstallDir)) { [IO.File]::WriteAllText((Join-Path $dir 'old.dll'),'obsolete') }
      $saved = Join-Path $database 'saved.txt'
      [IO.File]::WriteAllText($saved,'saved connection')
      Mock Assert-WacLocalPath {}
      Mock Set-WacDirectorySecurity {}
      Mock Assert-WacCodeAccess {}
      Initialize-WacInstallationDirectories -PreserveData $true
      [IO.File]::ReadAllText($saved) | Should -Be 'saved connection'
      foreach ($dir in @($updater,$InstallDir)) {
        (Test-Path -LiteralPath $dir -PathType Container) | Should -Be $true
        (Test-Path -LiteralPath (Join-Path $dir 'old.dll')) | Should -Be $false
      }
    }
  }

  It 'enforces the Windows ACL boundary on the updater, its parent, and service code' -Skip:($env:OS -ne 'Windows_NT' -or
    -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $InstallDir = Join-Path $TestDrive 'acl-program'
    $DataDir = Join-Path $TestDrive 'acl-data'
    $ns = [Security.Principal.SecurityIdentifier]::new('S-1-5-20')
    $db = Join-Path $DataDir 'Database'
    $updater = Join-Path $DataDir 'Updater'
    $null = New-Item -ItemType Directory -Path $db,$updater,$InstallDir -Force
    $old = Join-Path $updater 'obsolete.dll'
    [IO.File]::WriteAllText($old,'old')
    $fileAcl = Get-Acl -LiteralPath $old
    $fileAcl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($ns, 'Modify', 'Allow'))
    Set-Acl -LiteralPath $old -AclObject $fileAcl
    Assert-FailsWith { Assert-WacCodeAccess $old } 'Unsafe access'
    Initialize-WacInstallationDirectories -PreserveData $true
    (Test-Path -LiteralPath $old) | Should -Be $false
    foreach ($codeDir in @($InstallDir,$updater)) {
      $exe = Join-Path $codeDir 'probe.exe'
      [IO.File]::WriteAllText($exe,'fixture')
      Assert-WacExecutableTree $codeDir
      (Get-Acl -LiteralPath $codeDir).AreAccessRulesProtected | Should -Be $true
    }
    Mock Get-WacMaintenanceDirectory { $InstallDir }
    $legacy = Join-Path $DataDir 'wac-setup.json'
    Write-WacJsonAtomic $legacy @{dataDir=$DataDir}
    $marker = [pscustomobject]@{dataDir=$DataDir; port=6600}
    Write-WacProtectedMarker $marker
    $marker.port = 7443
    Write-WacProtectedMarker $marker
    Assert-WacCodeAccess (Get-WacProtectedMarkerPath)
    (Test-Path -LiteralPath $legacy) | Should -Be $false
    $source = Join-Path $TestDrive 'download'
    $null = New-Item -ItemType Directory -Path $source
    foreach ($name in @('wac-setup-engine.ps1', 'wac-certificate.ps1')) {
      $file = Join-Path $source $name
      Set-Content -LiteralPath $file -Value '# fixture'
      Set-Content -LiteralPath $file -Stream Zone.Identifier -Value "[ZoneTransfer]`r`nZoneId=3"
    }
    $entry = Install-WacRenewalScripts (Join-Path $source 'wac-setup-engine.ps1')
    $entry | Should -Be (Join-Path $InstallDir 'wac-setup-engine.ps1')
    foreach ($name in @('wac-setup-engine.ps1', 'wac-certificate.ps1')) {
      $dest = Join-Path $InstallDir $name
      (Get-FileHash -LiteralPath $dest).Hash | Should -Be (Get-FileHash -LiteralPath (Join-Path $source $name)).Hash
      @(Get-Item -LiteralPath $dest -Stream Zone.Identifier -ErrorAction SilentlyContinue).Count | Should -Be 0
      @(Get-Item -LiteralPath (Join-Path $source $name) -Stream Zone.Identifier).Count | Should -Be 1
    }
    Assert-WacCodeAccess $DataDir -Ancestor
    $dbFile = Join-Path $db 'connection.db'
    [IO.File]::WriteAllText($dbFile,'fixture')
    $rules = (Get-Acl -LiteralPath $dbFile).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $modify = [Security.AccessControl.FileSystemRights]::Modify
    @($rules | Where-Object { $_.IdentityReference.Value -eq $ns.Value -and ($_.FileSystemRights -band $modify) -eq $modify }).Count | Should -BeGreaterThan 0
  }

  It 'verifies the served leaf, TLS name and trust policy on loopback' {
    # Desktop .NET's default RSA provider cannot resize an existing key.
    $rsa = if ($env:OS -eq 'Windows_NT') {
      [Security.Cryptography.RSACng]::new(2048)
    } else { [Security.Cryptography.RSA]::Create(2048) }
    $request = [Security.Cryptography.X509Certificates.CertificateRequest]::new(
      'CN=localhost', $rsa, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $san = [Security.Cryptography.X509Certificates.SubjectAlternativeNameBuilder]::new()
    $san.AddDnsName('localhost')
    $request.CertificateExtensions.Add($san.Build())
    $leaf = $request.CreateSelfSigned([DateTimeOffset]::Now.AddHours(-1), [DateTimeOffset]::Now.AddHours(1))
    if ($env:OS -eq 'Windows_NT') {
      # Schannel needs a key container for the server side of the TLS fixture.
      $pfx = $leaf.Export([Security.Cryptography.X509Certificates.X509ContentType]::Pfx)
      $leaf.Dispose()
      $leaf = [Security.Cryptography.X509Certificates.X509Certificate2]::new($pfx, [string]::Empty, [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet)
    }
    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = $listener.LocalEndpoint.Port
    $server = [PowerShell]::Create()
    $null = $server.AddScript({
      param($socket, $cert)
      while ($true) {
        try { $client = $socket.AcceptTcpClient() } catch { return }
        try {
          $stream = [Net.Security.SslStream]::new($client.GetStream())
          try { $stream.AuthenticateAsServer($cert) } finally { $stream.Dispose() }
        } catch { } finally { $client.Dispose() }
      }
    }).AddArgument($listener).AddArgument($leaf)
    $running = $server.BeginInvoke()
    Mock Start-Sleep {}
    try {
      Assert-WacServedCertificate $leaf @('localhost') $port -AllowUntrustedRoot
      Assert-FailsWith { Assert-WacServedCertificate $leaf @('localhost') $port } 'TLS verification failed'
      Assert-FailsWith { Assert-WacServedCertificate $leaf @('other.example.test') $port -AllowUntrustedRoot } 'TLS verification failed'
      $wrongLeaf = [pscustomobject]@{Thumbprint=('F'*40)}
      Assert-FailsWith { Assert-WacServedCertificate $wrongLeaf @('localhost') $port -AllowUntrustedRoot } 'TLS verification failed'
    } finally {
      $listener.Stop()
      $null = $server.EndInvoke($running)
      $server.Dispose()
      $leaf.Dispose()
      $rsa.Dispose()
    }
  }
  Context 'Rotation of an installed gateway' {
    BeforeAll {
      # The portable runner supplies stateful doubles for Windows-only operations.
      if (-not (Get-Command Get-CimInstance -ErrorAction SilentlyContinue)) {
        function Get-CimInstance { param($ClassName, $Filter) }
      }
      if (-not (Get-Command Restart-Service -ErrorAction SilentlyContinue)) {
        function Restart-Service { param($Name) }
      }
    }
    BeforeEach {
      $script:oldHash = 'A' * 40
      $script:newHash = 'B' * 40
      $script:boundHash = $oldHash
      $script:probes = @()
      $script:restarts = 0
      $script:fixture = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
      $svcDir = Join-Path $fixture 'Service'
      [void][IO.Directory]::CreateDirectory($svcDir)
      $script:state = [pscustomobject]@{
        installedBy='wac-client-windows-setup'; markerVersion=1; installDir=$fixture; dataDir=$fixture
        port=6600; endpointFqdn='gateway.example.test'; serviceFqdn='localhost'
        certificateThumbprint=$oldHash; certificateSubject='WACTest'; trustSelfSignedCertificate=$true
        winRmHttpsMode='Disable'; productVersion='2.6.6.18'
      }
      $script:safeDir = Join-Path $fixture 'private'
      $null = New-Item -ItemType Directory -Path $safeDir
      $script:markerPathTest = Join-Path $fixture 'wac-setup.json'
      Write-WacJsonAtomic $markerPathTest $state
      $block = @{ Subject='WACTest'; Thumbprint=$oldHash }
      $script:confPathTest = Join-Path $svcDir 'appsettings.json'
      $script:settingValue = 'setting-' + [char]0x0416
      Write-WacJsonAtomic $confPathTest @{
        Kestrel=@{Endpoints=@{WindowsAdminCenter=@{Certificate=$block}}}
        WindowsAdminCenter=@{ServiceCertificate=$block}; preserve=$settingValue
      }
      Mock Assert-WacLocalPath {}
      Mock Get-WacMaintenanceDirectory { $script:safeDir }
      Mock Get-WacProtectedMarkerPath { Join-Path $script:safeDir 'wac-setup.json' }
      Mock Grant-WacMarkerReadAccess {}
      Mock Get-CimInstance { [pscustomobject]@{PathName=(Join-Path $fixture 'Service/WindowsAdminCenter.exe')} }
      Mock Get-Item {
        [pscustomobject]@{ Issuer='CN=WACTest'; Subject='CN=WACTest'; FriendlyName='Windows Admin Center Self-Signed Certificate'
          Extensions=@([Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($false,$false,0,$true))
          Thumbprint=$oldHash; NotBefore=(Get-Date).AddDays(-61); NotAfter=(Get-Date).AddDays(-1) }
      } -ParameterFilter { $LiteralPath -like 'Cert:*' }
      Mock Get-WacHttpBindingHash { $boundHash }
      Mock Set-WacHttpBindingHash { $script:boundHash = $Hash }
      Mock Get-OrCreateCertificate { [pscustomobject]@{Thumbprint=$newHash; Subject='CN=WACTest'} }
      Mock Ensure-TrustedCertificate {}
      Mock Grant-CertificatePrivateKeyAcl {}
      Mock Restart-Service { $script:restarts++ }
      Mock Assert-WacServedCertificate { $script:probes = @($Certificate.Thumbprint) + $Names }
      Mock Write-Log {}
    }
    It 'rotates a v1 installation, verifies the new endpoint and persists both bindings' {
      Invoke-WacCertificateRotation $state
      $conf = Get-Content -LiteralPath $confPathTest -Encoding UTF8 -Raw | ConvertFrom-Json
      $marker = Get-Content -LiteralPath (Get-WacProtectedMarkerPath) -Raw | ConvertFrom-Json
      $marker.certificateSource | Should -Be 'Generated'
      $marker.certificateThumbprint | Should -Be $newHash
      $marker.productVersion | Should -Be '2.6.6.18'
      $conf.Kestrel.Endpoints.WindowsAdminCenter.Certificate.Thumbprint | Should -Be $newHash
      $conf.WindowsAdminCenter.ServiceCertificate.Thumbprint | Should -Be $newHash
      $conf.preserve | Should -BeExactly $settingValue
      $boundHash | Should -Be $newHash
      ($probes -contains $newHash) | Should -Be $true
      ($probes -contains 'localhost') | Should -Be $true
      ($probes -contains 'gateway.example.test') | Should -Be $true
      $restarts | Should -Be 1
      (Test-Path -LiteralPath (Join-Path $safeDir 'rotation.json')) | Should -Be $false
    }
    It 'renews the gateway without accessing a WinRM listener excluded at setup' {
      $state.winRmHttpsMode = 'Enable'
      $state | Add-Member skipPsRemoting $true
      Mock Get-ChildItem { throw 'Unexpected WinRM access' } -ParameterFilter { $Path -like 'WSMan:*' }
      Invoke-WacCertificateRotation $state
      $boundHash | Should -Be $newHash
      $restarts | Should -Be 1
    }
    It 'restores the previous bindings when TLS verification fails' {
      $PSDefaultParameterValues = @{'Get-Content:Encoding' = 'ASCII'}
      Mock Assert-WacServedCertificate { throw 'TLS probe failed' }
      Assert-FailsWith { Invoke-WacCertificateRotation $state } 'TLS probe failed'
      $conf = Get-Content -LiteralPath $confPathTest -Encoding UTF8 -Raw | ConvertFrom-Json
      $conf.Kestrel.Endpoints.WindowsAdminCenter.Certificate.Thumbprint | Should -Be $oldHash
      $conf.WindowsAdminCenter.ServiceCertificate.Thumbprint | Should -Be $oldHash
      $conf.preserve | Should -BeExactly $settingValue
      $boundHash | Should -Be $oldHash
      (Get-Content -LiteralPath $markerPathTest -Raw | ConvertFrom-Json).certificateThumbprint | Should -Be $oldHash
      $restarts | Should -Be 2
      (Test-Path -LiteralPath (Join-Path $safeDir 'rotation.json')) | Should -Be $false
    }
    It 'keeps the journal when rollback fails' {
      Mock Assert-WacServedCertificate { throw 'TLS probe failed' }
      Mock Set-WacHttpBindingHash {
        if ($Hash -eq $oldHash) { throw 'HTTP rollback failed' }
        $script:boundHash = $Hash
      }
      Assert-FailsWith { Invoke-WacCertificateRotation $state } 'HTTP rollback failed'
      $journal = Get-Content -LiteralPath (Join-Path $safeDir 'rotation.json') -Encoding UTF8 -Raw | ConvertFrom-Json
      $journal.old | Should -Be $oldHash
      $journal.next | Should -Be $newHash
    }
    It 'keeps the journal when rollback restores a partially switched gateway' {
      $journalPath = Join-Path $safeDir 'rotation.json'
      Write-WacJsonAtomic $journalPath @{old=$oldHash; next=$newHash}
      $script:boundHash = $newHash
      Mock Get-Item { [pscustomobject]@{Thumbprint=$newHash; Subject='CN=WACTest'} } -ParameterFilter { $LiteralPath -like "Cert:*$newHash" }
      Mock Test-ReusableGeneratedCertificate { $true }
      Mock Assert-WacServedCertificate { throw 'TLS probe failed' }
      Assert-FailsWith { Invoke-WacCertificateRotation $state } 'TLS probe failed'
      $boundHash | Should -Be $newHash
      (Test-Path -LiteralPath $journalPath) | Should -Be $true
    }
    It 'refuses to overwrite a foreign HTTP binding' {
      $script:boundHash = 'C' * 40
      Assert-FailsWith { Invoke-WacCertificateRotation $state } 'changed outside the wrapper'
      $restarts | Should -Be 0
      $boundHash | Should -Be ('C' * 40)
    }
  }

}
