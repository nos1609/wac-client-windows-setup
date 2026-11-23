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

  It 'rejects an expired supplied certificate before accessing its private key' {
    $cert = [pscustomobject]@{ Thumbprint=('A'*40); NotBefore=(Get-Date).AddDays(-61); NotAfter=(Get-Date).AddDays(-1) }
    Assert-FailsWith { Assert-SuppliedCertificateUsableForWac $cert } 'outside its validity period'
  }

  It 'rejects a supplied certificate whose validity has not started' {
    $cert = [pscustomobject]@{ Thumbprint=('B'*40); NotBefore=(Get-Date).AddDays(1); NotAfter=(Get-Date).AddDays(60) }
    Assert-FailsWith { Assert-SuppliedCertificateUsableForWac $cert } 'outside its validity period'
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

  It 'rebuilds legacy code trees while preserving the database on upgrade' {
    $InstallDir = Join-Path $TestDrive 'program'
    $DataDir = Join-Path $TestDrive 'data'
    $updater = Join-Path $DataDir 'Updater'
    $database = Join-Path $DataDir 'Database'
    $KeepExistingData = $true
    $null = New-Item -ItemType Directory -Path $updater,$database,$InstallDir -Force
    foreach ($dir in @($updater,$InstallDir)) { [IO.File]::WriteAllText((Join-Path $dir 'old.dll'),'obsolete') }
    $saved = Join-Path $database 'saved.txt'
    [IO.File]::WriteAllText($saved,'saved connection')
    Mock Assert-WacLocalPath {}
    Mock Set-WacDirectorySecurity {}
    Mock Assert-WacCodeAccess {}
    Initialize-WacInstallationDirectories
    [IO.File]::ReadAllText($saved) | Should -Be 'saved connection'
    foreach ($dir in @($updater,$InstallDir)) {
      (Test-Path -LiteralPath $dir -PathType Container) | Should -Be $true
      (Test-Path -LiteralPath (Join-Path $dir 'old.dll')) | Should -Be $false
    }
  }

  It 'enforces the Windows ACL boundary on the updater, its parent, and service code' -Skip:($env:OS -ne 'Windows_NT' -or
    -not ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $InstallDir = Join-Path $TestDrive 'acl-program'
    $DataDir = Join-Path $TestDrive 'acl-data'
    $KeepExistingData = $true
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
    Initialize-WacInstallationDirectories
    (Test-Path -LiteralPath $old) | Should -Be $false
    foreach ($codeDir in @($InstallDir,$updater)) {
      $exe = Join-Path $codeDir 'probe.exe'
      [IO.File]::WriteAllText($exe,'fixture')
      Assert-WacExecutableTree $codeDir
      (Get-Acl -LiteralPath $codeDir).AreAccessRulesProtected | Should -Be $true
    }
    Assert-WacCodeAccess $DataDir -Ancestor
    $dbFile = Join-Path $db 'connection.db'
    [IO.File]::WriteAllText($dbFile,'fixture')
    $rules = (Get-Acl -LiteralPath $dbFile).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
    $modify = [Security.AccessControl.FileSystemRights]::Modify
    @($rules | Where-Object { $_.IdentityReference.Value -eq $ns.Value -and ($_.FileSystemRights -band $modify) -eq $modify }).Count | Should -BeGreaterThan 0
  }

  It 'verifies the served leaf, TLS name and trust policy on loopback' {
    $rsa = [Security.Cryptography.RSA]::Create()
    $rsa.KeySize = 2048
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
      $script:markerPathTest = Join-Path $fixture 'wac-setup.json'
      Write-WacJsonAtomic $markerPathTest $state
      $block = @{ Subject='WACTest'; Thumbprint=$oldHash }
      $script:confPathTest = Join-Path $svcDir 'appsettings.json'
      Write-WacJsonAtomic $confPathTest @{
        Kestrel=@{Endpoints=@{WindowsAdminCenter=@{Certificate=$block}}}
        WindowsAdminCenter=@{ServiceCertificate=$block}; preserve='unrelated setting'
      }
      Mock Assert-WacLocalPath {}
      Mock Get-WacMaintenanceDirectory { $fixture }
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
      $conf = Get-Content -LiteralPath $confPathTest -Raw | ConvertFrom-Json
      $marker = Get-Content -LiteralPath $markerPathTest -Raw | ConvertFrom-Json
      $marker.certificateSource | Should -Be 'Generated'
      $marker.certificateThumbprint | Should -Be $newHash
      $marker.productVersion | Should -Be '2.6.6.18'
      $conf.Kestrel.Endpoints.WindowsAdminCenter.Certificate.Thumbprint | Should -Be $newHash
      $conf.WindowsAdminCenter.ServiceCertificate.Thumbprint | Should -Be $newHash
      $conf.preserve | Should -Be 'unrelated setting'
      $boundHash | Should -Be $newHash
      ($probes -contains $newHash) | Should -Be $true
      ($probes -contains 'localhost') | Should -Be $true
      ($probes -contains 'gateway.example.test') | Should -Be $true
      $restarts | Should -Be 1
      (Test-Path -LiteralPath (Join-Path $fixture 'rotation.json')) | Should -Be $false
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
      Mock Assert-WacServedCertificate { throw 'TLS probe failed' }
      Assert-FailsWith { Invoke-WacCertificateRotation $state } 'TLS probe failed'
      $conf = Get-Content -LiteralPath $confPathTest -Raw | ConvertFrom-Json
      $conf.Kestrel.Endpoints.WindowsAdminCenter.Certificate.Thumbprint | Should -Be $oldHash
      $conf.WindowsAdminCenter.ServiceCertificate.Thumbprint | Should -Be $oldHash
      $boundHash | Should -Be $oldHash
      (Get-Content -LiteralPath $markerPathTest -Raw | ConvertFrom-Json).certificateThumbprint | Should -Be $oldHash
      $restarts | Should -Be 2
    }
    It 'refuses to overwrite a foreign HTTP binding' {
      $script:boundHash = 'C' * 40
      Assert-FailsWith { Invoke-WacCertificateRotation $state } 'changed outside the wrapper'
      $restarts | Should -Be 0
      $boundHash | Should -Be ('C' * 40)
    }
  }

}
