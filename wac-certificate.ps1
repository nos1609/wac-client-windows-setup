# Shared by the terminal wizard and the elevated setup engine.
function Test-WacEndEntityCertificate {
  param([Parameter(Mandatory = $true)]$Certificate)
  $basic = $Certificate.Extensions | Where-Object { $_.Oid.Value -eq '2.5.29.19' } | Select-Object -First 1
  if (-not $basic) { return $false }
  $constraints = [Security.Cryptography.X509Certificates.X509BasicConstraintsExtension]::new($basic, $basic.Critical)
  return -not $constraints.CertificateAuthority
}

function Get-WacMarkerCertificateSource {
  param([Parameter(Mandatory = $true)]$Marker)

  if ($Marker.PSObject.Properties['certificateSource']) {
    if ($Marker.certificateSource -eq 'Generated') { return 'Generated' }
    return 'Explicit'
  }
  # Version 1 stored the selected thumbprint for both certificate modes.
  if (-not $Marker.PSObject.Properties['certificateThumbprint']) { return 'Explicit' }
  $hash = [string]$Marker.certificateThumbprint
  if ($hash -match '^[0-9a-fA-F]{40}$') {
    $cert = Get-Item -LiteralPath "Cert:\LocalMachine\My\$hash" -ErrorAction SilentlyContinue
    if ($cert -and $cert.Issuer -eq $cert.Subject -and
        $cert.FriendlyName -eq 'Windows Admin Center Self-Signed Certificate' -and (Test-WacEndEntityCertificate $cert)) { return 'Generated' }
  }
  return 'Explicit'
}

function Get-WacMaintenanceDirectory {
  $parent = [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
  return [IO.Path]::Combine($parent, 'WacClientCertificateMaintenance')
}

function Get-WacSetupMarkerPath {
  param([string]$DataDir = "$env:ProgramData\WindowsAdminCenter")
  return [IO.Path]::Combine($DataDir, 'wac-setup.json')
}

function Get-WacProtectedMarkerPath {
  return [IO.Path]::Combine((Get-WacMaintenanceDirectory), 'wac-setup.json')
}

function Get-WacReadableMarkerPath {
  param([string]$DataDir, [string]$ProtectedPath = (Get-WacProtectedMarkerPath))
  if (Test-Path -LiteralPath $ProtectedPath -ErrorAction Stop) { return $ProtectedPath }
  return Get-WacSetupMarkerPath $DataDir
}

function Read-WacSetupMarker {
  param([string]$Path = (Get-WacReadableMarkerPath $DataDir))

  try {
    if (-not (Test-Path -LiteralPath $Path -ErrorAction Stop)) { return $null }
    Assert-WacLocalPath $Path
    $marker = Get-Content -LiteralPath $Path -Encoding UTF8 -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    if ($marker.installedBy -ne "wac-client-windows-setup") { throw 'Unexpected setup marker identity.' }
    return $marker
  } catch {
    throw ("Could not read setup marker {0}: {1}" -f $Path, $_.Exception.Message)
  }
}

function Assert-WacLocalPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.Substring(2).Contains(':')) {
    throw "Maintenance requires a local absolute path: $Path"
  }
  for ($current = [IO.Path]::GetFullPath($Path); $current; $current = Split-Path -Parent $current) {
    if ([IO.File]::GetAttributes($current) -band [IO.FileAttributes]::ReparsePoint) {
      throw "Refusing a reparse point in a maintenance path: $current"
    }
  }
}

function Enter-WacMaintenanceLock {
  $dir = Get-WacMaintenanceDirectory
  if (-not (Test-Path -LiteralPath $dir)) {
    $acl = [Security.AccessControl.DirectorySecurity]::new()
    $admins = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')
    $acl.SetOwner($admins)
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($sid in @($admins, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
      $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
    }
    # An elevated administrator may own new files under their individual SID.
    # Restrict the owner's implicit WRITE_DAC right to the two trusted groups above.
    $ownerRights = [Security.Principal.SecurityIdentifier]::new('S-1-3-4')
    $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($ownerRights, 'ReadPermissions', 'ContainerInherit, ObjectInherit', 'None', 'Allow'))
    [void][IO.Directory]::CreateDirectory($dir)
    Set-Acl -LiteralPath $dir -AclObject $acl
  }
  Assert-WacLocalPath $dir
  # The scheduled code and its configuration live outside WAC's service-writable trees.
  $allowed = @('S-1-5-18','S-1-5-32-544','S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464')
  foreach ($item in @((Get-Item -LiteralPath $dir)) + @(Get-ChildItem -LiteralPath $dir -Force)) {
    Assert-WacLocalPath $item.FullName
    $acl = Get-Acl -LiteralPath $item.FullName
    $restrictedOwner = $false
    foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
      if ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
      if ($rule.IdentityReference.Value -eq 'S-1-3-4') { $restrictedOwner = $true }
      if ($rule.AccessControlType -eq 'Allow' -and ([int]$rule.FileSystemRights -band 0xD0156) -and
          $rule.IdentityReference.Value -notin $allowed) { throw "Unsafe write access to $($item.Name)" }
    }
    if (-not $restrictedOwner -and $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $allowed) {
      throw "Unexpected owner of maintenance path: $($item.Name)"
    }
  }
  return [IO.File]::Open((Join-Path $dir 'setup.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
}

function Write-WacJsonAtomic {
  param([string]$Path, $Value)
  $tmp = Join-Path (Split-Path -Parent $Path) ([guid]::NewGuid().ToString('N') + '.tmp')
  try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 100))
    $stream = [IO.File]::Open($tmp, 'CreateNew', 'Write', 'None')
    try { $stream.Write($bytes, 0, $bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if ([IO.File]::Exists($Path)) {
      # PowerShell coerces $null into the empty string for this overload.
      [IO.File]::Replace($tmp, $Path, [System.Management.Automation.Language.NullString]::Value)
    } else { [IO.File]::Move($tmp, $Path) }
  } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}

function Assert-WacServedCertificate {
  param($Certificate, [string[]]$Names, [int]$Port, [switch]$AllowUntrustedRoot)
  $expected = $Certificate.Thumbprint
  foreach ($name in @($Names | Where-Object { $_ } | Sort-Object -Unique)) {
    $ready = $false
    for ($attempt = 0; $attempt -lt 12; $attempt++) {
      $tcp = [Net.Sockets.TcpClient]::new()
      $tls = $null
      try {
        $tcp.ReceiveTimeout = 3000
        $tcp.SendTimeout = 3000
        $tcp.Connect([Net.IPAddress]::Loopback, $Port)
        $validate = [Net.Security.RemoteCertificateValidationCallback]{
          param($sender, $peer, $chain, $errors)
          if (-not $peer -or $peer.GetCertHashString() -ne $expected) { return $false }
          if ($errors -eq [Net.Security.SslPolicyErrors]::None) { return $true }
          if (-not $AllowUntrustedRoot -or $errors -ne [Net.Security.SslPolicyErrors]::RemoteCertificateChainErrors) { return $false }
          return ($null -ne $chain -and $chain.ChainStatus.Count -eq 1 -and
            $chain.ChainStatus[0].Status -eq [Security.Cryptography.X509Certificates.X509ChainStatusFlags]::UntrustedRoot)
        }
        $tls = [Net.Security.SslStream]::new($tcp.GetStream(), $false, $validate)
        $tls.AuthenticateAsClient($name)
        $ready = $true
        break
      } catch {
        $reason = $_.Exception.GetBaseException().Message
        if ($attempt -lt 11) { Start-Sleep -Milliseconds 500 }
      } finally {
        if ($tls) { $tls.Dispose() }
        $tcp.Dispose()
      }
    }
    if (-not $ready) { throw "TLS verification failed for $name on port $Port (expected $expected): $reason" }
  }
}

function Grant-WacMarkerReadAccess {
  param([string]$Path)
  # The unelevated wizard reads this file. Its parent only permits trusted writers.
  $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
  $readers = [Security.Principal.SecurityIdentifier]::new('S-1-5-11')
  $acl.SetAccessRule([Security.AccessControl.FileSystemAccessRule]::new($readers, 'Read', 'Allow'))
  Set-Acl -LiteralPath $path -AclObject $acl -ErrorAction Stop
}

function Write-WacProtectedMarker {
  param($Marker)
  $path = Get-WacProtectedMarkerPath
  Write-WacJsonAtomic $path $Marker
  Grant-WacMarkerReadAccess $path
  $legacy = Get-WacSetupMarkerPath $Marker.dataDir
  if ([IO.File]::Exists($legacy) -and [IO.Path]::GetFullPath($legacy) -ne $path) {
    Assert-WacLocalPath $Marker.dataDir
    [IO.File]::Delete($legacy)
  }
}

function Move-WacLegacyMarker {
  param($Marker)
  # Keep a verified installation record if setup stops after deleting the service.
  if ($Marker -and -not [IO.File]::Exists((Get-WacProtectedMarkerPath))) {
    Write-WacProtectedMarker $Marker
  }
}

function Install-WacRenewalScripts {
  param([string]$EnginePath)
  $dir = Get-WacMaintenanceDirectory
  $installedEngine = Join-Path $dir 'wac-setup-engine.ps1'
  if ([IO.Path]::GetFullPath($EnginePath) -ne $installedEngine) {
    Copy-Item -LiteralPath $EnginePath -Destination $installedEngine -Force
    Copy-Item -LiteralPath (Join-Path (Split-Path -Parent $EnginePath) 'wac-certificate.ps1') -Destination $dir -Force
  }
  foreach ($scriptName in @('wac-setup-engine.ps1', 'wac-certificate.ps1')) {
    $installedScript = Join-Path $dir $scriptName
    Assert-WacLocalPath $installedScript
    Assert-WacCodeAccess $installedScript
    Unblock-File -LiteralPath $installedScript -ErrorAction Stop
  }
  return $installedEngine
}

function Register-WacRenewalTask {
  param($Marker, [string]$EnginePath)
  if (-not $Marker -or (Get-WacMarkerCertificateSource $Marker) -ne 'Generated') {
    throw 'Scheduled renewal requires a wrapper-managed certificate.'
  }
  $dir = Get-WacMaintenanceDirectory
  $installedEngine = Install-WacRenewalScripts -EnginePath $EnginePath
  Write-WacJsonAtomic (Join-Path $dir 'settings.json') $Marker
  $journal = Join-Path $dir 'rotation.json'
  if (Test-Path -LiteralPath $journal) { Remove-Item -LiteralPath $journal -Force }
  $exe = Join-Path ([Environment]::GetFolderPath('System')) 'WindowsPowerShell\v1.0\powershell.exe'
  $argsText = '-NoProfile -NonInteractive -ExecutionPolicy RemoteSigned -File "{0}" -ScheduledRenewal -LogPath "{1}"' -f $installedEngine,(Join-Path $dir 'renewal.log')
  $action = New-ScheduledTaskAction -Execute $exe -Argument $argsText -WorkingDirectory $dir
  $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
  $trigger = New-ScheduledTaskTrigger -Daily -At '03:00'
  Register-ScheduledTask -TaskName 'WacClientCertificateRenewal' -Action $action -Trigger $trigger -Settings $settings -User 'SYSTEM' -RunLevel Highest -Force | Out-Null
}

function Remove-WacRenewalTask {
  $name = 'WacClientCertificateRenewal'
  if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
  }
  $dir = Get-WacMaintenanceDirectory
  foreach ($file in @('settings.json','rotation.json','wac-setup-engine.ps1','wac-certificate.ps1')) {
    $path = Join-Path $dir $file
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
  }
}

function Get-WacHttpBindingHash {
  param([int]$Port)
  $netsh = Join-Path ([Environment]::GetFolderPath('System')) 'netsh.exe'
  $argsList = @('http','show','sslcert',"ipport=0.0.0.0:$Port")
  $output = & $netsh @argsList
  if ($LASTEXITCODE -ne 0) { throw "Cannot read the HTTP.SYS binding on port $Port." }
  $text = $output -join [Environment]::NewLine
  $hash = [regex]::Match($text, '(?im):\s*([0-9a-f]{40})\s*$')
  if (-not $hash.Success -or $text -notmatch [regex]::Escape($script:AppId)) {
    throw "HTTP.SYS binding on port $Port does not belong to this installation."
  }
  return $hash.Groups[1].Value
}

function Set-WacHttpBindingHash {
  param([int]$Port, [string]$Hash)
  $netsh = Join-Path ([Environment]::GetFolderPath('System')) 'netsh.exe'
  $argsList = @('http','update','sslcert',"ipport=0.0.0.0:$Port","certhash=$Hash","appid=$script:AppId",'certstorename=MY')
  & $netsh @argsList | Out-Null
  if ($LASTEXITCODE -ne 0 -or (Get-WacHttpBindingHash $Port) -ne $Hash) {
    throw "Could not update the existing HTTP.SYS binding on port $Port."
  }
}

function Invoke-WacLockedCertificateRotation {
  param($State)
  # Pin each directory before traversing the next. WAC can write its service/data
  # directories, so a path check alone cannot protect a later privileged rename.
  if (-not ('WacMaintenance.DirectoryHandle' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace WacMaintenance {
    public static class DirectoryHandle {
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        public static extern SafeFileHandle CreateFile(string path, uint access, uint share,
            IntPtr security, uint disposition, uint flags, IntPtr template);
    }
}
'@
  }
  $handles = [Collections.Generic.List[IDisposable]]::new()
  try {
    foreach ($leaf in @((Join-Path $State.installDir 'Service'), $State.dataDir)) {
      Assert-WacLocalPath $leaf
      $path = [IO.Path]::GetPathRoot($leaf)
      foreach ($part in [IO.Path]::GetFullPath($leaf).Substring($path.Length).Split('\', [StringSplitOptions]::RemoveEmptyEntries)) {
        $path = Join-Path $path $part
        $handle = [WacMaintenance.DirectoryHandle]::CreateFile($path, 0, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
        if ($handle.IsInvalid) { throw "Cannot lock maintenance directory: $path" }
        $handles.Add($handle)
        if ([IO.File]::GetAttributes($path) -band [IO.FileAttributes]::ReparsePoint) { throw "Unexpected reparse point: $path" }
      }
    }
    Invoke-WacCertificateRotation -State $State
  } finally { foreach ($handle in $handles) { $handle.Dispose() } }
}

function Invoke-WacManualRenewal {
  param($Marker, [string]$EnginePath)
  if ((Get-WacMarkerCertificateSource $Marker) -ne 'Generated') {
    throw 'This certificate is externally managed. Supply a valid replacement with -CertificateThumbprint.'
  }
  $dir = Get-WacMaintenanceDirectory
  $statePath = Join-Path $dir 'settings.json'
  if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($state.dataDir -ne $Marker.dataDir) { throw 'Existing renewal state belongs to a different installation.' }
  } else { $state = $Marker }
  if ($script:OriginalBoundParameters.ContainsKey('TrustSelfSignedCertificate')) {
    $state | Add-Member trustSelfSignedCertificate ([bool]$TrustSelfSignedCertificate) -Force
  }
  Invoke-WacLockedCertificateRotation -State $state
  Register-WacRenewalTask -Marker $state -EnginePath $EnginePath
}

function Invoke-WacScheduledRenewal {
  $state = Get-Content -LiteralPath (Join-Path (Get-WacMaintenanceDirectory) 'settings.json') -Encoding UTF8 -Raw | ConvertFrom-Json
  Invoke-WacLockedCertificateRotation -State $state
}

function Invoke-WacCertificateRotation {
  param([Parameter(Mandatory = $true)]$State)
  if ($State.installedBy -ne 'wac-client-windows-setup' -or (Get-WacMarkerCertificateSource $State) -ne 'Generated') {
    throw 'A generated certificate and a matching wrapper installation are required.'
  }
  $old = [string]$State.certificateThumbprint
  if ($old -notmatch '^[0-9a-f]{40}$') { throw 'Invalid certificate thumbprint in the renewal state.' }
  $EndpointFqdn = [string]$State.endpointFqdn
  $ServiceFqdn = [string]$State.serviceFqdn
  $CertificateSubject = [string]$State.certificateSubject
  $CertificateThumbprint = ''
  $WinRmHttpsMode = [string]$State.winRmHttpsMode
  $trust = [bool]$State.trustSelfSignedCertificate
  $port = [int]$State.port
  $markerPath = Get-WacReadableMarkerPath $State.dataDir
  $settingsPath = Join-Path $State.installDir 'Service\appsettings.json'
  Assert-WacLocalPath $markerPath
  Assert-WacLocalPath $settingsPath
  $svc = Get-CimInstance -ClassName Win32_Service -Filter "Name='WindowsAdminCenter'" -ErrorAction Stop
  if (-not $svc -or $svc.PathName.Trim('"') -ne (Join-Path $State.installDir 'Service\WindowsAdminCenter.exe')) {
    throw 'Renewal state does not match the installed gateway service.'
  }
  $marker = Get-Content -LiteralPath $markerPath -Encoding UTF8 -Raw | ConvertFrom-Json
  if ($marker.dataDir -ne $State.dataDir -or $marker.installDir -ne $State.installDir) {
    throw 'The WAC marker directories do not match the renewal state.'
  }
  if ($marker.installedBy -ne $State.installedBy -or (Get-WacMarkerCertificateSource $marker) -ne 'Generated') {
    throw 'The gateway certificate is no longer managed by the wrapper.'
  }

  $dir = Get-WacMaintenanceDirectory
  $pendingPath = Join-Path $dir 'rotation.json'
  $pending = $null
  if (Test-Path -LiteralPath $pendingPath) {
    $pending = Get-Content -LiteralPath $pendingPath -Encoding UTF8 -Raw | ConvertFrom-Json
    if ($pending.old -ne $old -and $pending.next -ne $old) { throw 'Renewal journal belongs to a different certificate.' }
    if ($pending.next -notmatch '^[0-9a-f]{40}$') { throw 'Invalid renewal journal.' }
  }
  $allowed = @($old)
  if ($pending) { $allowed += @($pending.old,$pending.next) }
  $json = Read-WacAppSettingsJson -AppSettingsPath $settingsPath
  $gateway = $json.Kestrel.Endpoints.WindowsAdminCenter.Certificate
  $service = $json.WindowsAdminCenter.ServiceCertificate
  $httpHash = Get-WacHttpBindingHash $port
  $previousBindings = @($gateway.Thumbprint, $service.Thumbprint, $marker.certificateThumbprint, $httpHash)
  foreach ($bound in $previousBindings) {
    if ($bound -notin $allowed) { throw 'The certificate binding changed outside the wrapper. Review the live gateway before retrying.' }
  }
  $wsPath = $null
  $previousWinRm = $null
  if ($WinRmHttpsMode -eq 'Enable' -and -not (Get-WacMarkerValue $State 'skipPsRemoting')) {
    $listener = @(Get-ChildItem WSMan:\localhost\Listener | Where-Object {
      $_.Keys -contains 'Transport=HTTPS' -and $_.Keys -contains 'Address=*'
    })
    if ($listener.Count -ne 1) { throw 'Cannot identify the existing WinRM HTTPS listener.' }
    $wsPath = Join-Path $listener[0].PSPath 'CertificateThumbprint'
    $previousWinRm = (Get-Item -LiteralPath $wsPath).Value
    if ($previousWinRm -notin $allowed) { throw 'WinRM uses a different certificate.' }
    $previousBindings += $previousWinRm
  }

  $current = Get-Item -LiteralPath "Cert:\LocalMachine\My\$old" -ErrorAction SilentlyContinue
  $names = @(Get-RequiredGeneratedCertificateDnsNames)
  if (-not $pending -and $current -and $current.NotBefore -le (Get-Date) -and
      $current.NotAfter -gt (Get-Date).AddDays(7) -and (Test-ReusableGeneratedCertificate $current) -and
      (Test-CertificateUsableForWac $current $names)) {
    if ($trust) { Ensure-TrustedCertificate $current }
    Assert-WacServedCertificate $current $names $port -AllowUntrustedRoot:(!$trust)
    $State | Add-Member certificateSource 'Generated' -Force
    if ($markerPath -ne (Get-WacProtectedMarkerPath) -or $marker.markerVersion -lt 2 -or $marker.trustSelfSignedCertificate -ne $trust) {
      $marker.markerVersion = $State.markerVersion = 2
      $marker | Add-Member certificateSource 'Generated' -Force
      $marker | Add-Member trustSelfSignedCertificate $trust -Force
      Write-WacProtectedMarker $marker
    }
    return
  }

  if ($pending) {
    $next = Get-Item -LiteralPath ("Cert:\LocalMachine\My\" + $pending.next) -ErrorAction Stop
    if (-not (Test-ReusableGeneratedCertificate $next)) { throw 'Pending certificate is unusable.' }
  } else {
    $next = Get-OrCreateCertificate
    if ($next.Thumbprint -eq $old) { throw 'No suitable replacement was created.' }
    $pending = [pscustomobject]@{ old=$old; next=$next.Thumbprint }
    Write-WacJsonAtomic $pendingPath $pending
  }
  # The journal pins both ends. An interrupted run can finish from either binding.
  $previousJson = Get-Content -LiteralPath $settingsPath -Encoding UTF8 -Raw | ConvertFrom-Json
  $configChanged = $false
  $wsChanged = $false
  $httpChanged = $false
  try {
    if ($trust) { Ensure-TrustedCertificate $next }
    Grant-CertificatePrivateKeyAcl $next
    $gateway.Subject = $service.Subject = Get-CertificateCommonName $next
    $gateway.Thumbprint = $service.Thumbprint = $next.Thumbprint
    Write-WacJsonAtomic $settingsPath $json
    $configChanged = $true
    if ($httpHash -ne $next.Thumbprint) {
      $httpChanged = $true
      Set-WacHttpBindingHash $port $next.Thumbprint
    }
    if ($wsPath -and $previousWinRm -ne $next.Thumbprint) {
      $wsChanged = $true
      Set-Item -LiteralPath $wsPath -Value $next.Thumbprint -Force
    }
    Restart-Service -Name WindowsAdminCenter -ErrorAction Stop
    Assert-WacServedCertificate $next $names $port -AllowUntrustedRoot:(!$trust)
  } catch {
    $failure = $_
    $recoveryErrors = @()
    if ($wsChanged) {
      try { Set-Item -LiteralPath $wsPath -Value $previousWinRm -Force } catch { $recoveryErrors += $_.Exception.Message }
    }
    if ($httpChanged) {
      try { Set-WacHttpBindingHash $port $httpHash } catch { $recoveryErrors += $_.Exception.Message }
    }
    if ($configChanged) {
      try {
        Write-WacJsonAtomic $settingsPath $previousJson
        Restart-Service -Name WindowsAdminCenter -ErrorAction Stop
      } catch { $recoveryErrors += $_.Exception.Message }
    }
    # An interrupted rotation can start with mixed bindings. It still needs the journal after rollback.
    if ($recoveryErrors.Count -eq 0 -and -not ($previousBindings -ne $old)) {
      try { Remove-Item -LiteralPath $pendingPath -Force -ErrorAction Stop } catch { $recoveryErrors += $_.Exception.Message }
    }
    if ($recoveryErrors.Count) { throw "$failure. Rollback needs attention: $($recoveryErrors -join ', ')" }
    throw $failure
  }
  foreach ($record in @($marker,$State)) {
    $record.certificateThumbprint = $next.Thumbprint
    $record | Add-Member certificateSource 'Generated' -Force
    $record | Add-Member trustSelfSignedCertificate $trust -Force
    $record.markerVersion = 2
  }
  Write-WacProtectedMarker $marker
  Write-WacJsonAtomic (Join-Path $dir 'settings.json') $State
  Remove-Item -LiteralPath $pendingPath -Force
  Write-Log ("Renewed WAC certificate, expires {0:o}" -f $next.NotAfter)
}
