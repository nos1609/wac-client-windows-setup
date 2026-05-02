# wac-client-windows-setup

Русская версия: [README.md](README.md)

Unofficial setup package for installing Windows Admin Center v2 on Windows client x64 systems.

The stock WAC installer can reject client Windows editions and require a server SKU. This package does not patch Microsoft binaries. The local PowerShell script extracts the Inno Setup payload from the signed Microsoft installer and applies the required machine configuration directly.

## Project Status and Boundaries

This is an unofficial setup script and not a Microsoft product. The repository must not contain the official Windows Admin Center installer, extracted WAC payload, or the `innoextract` binary. Those components are downloaded at install time or supplied explicitly by the user.

This project's own source code and documentation are distributed under the MIT license, see `LICENSE`. That license applies only to this project's own code and documentation. It does not apply to Microsoft Windows, Windows Admin Center, the official Windows Admin Center installer, extracted WAC payloads, Microsoft extensions, Microsoft third-party notices, or any other Microsoft software.

Windows Admin Center is Microsoft software and is governed by the Microsoft Windows Admin Center license terms and other applicable Microsoft and Windows license terms. Project-specific legal notices are in `NOTICE.md` and `NOTICE.en.md`.

## Target System

- Windows 10 x64, version 1709 or later.
- Windows 11 x64.
- Latest locally tested system: Windows 11 x64 26H1.
- Run as local administrator.
- ARM64 is not a supported WAC target platform; the install path is verified best-effort.

## Official Windows Client Support

Microsoft's current documentation describes the `Local client` scenario: installing Windows Admin Center on a local Windows 10 or 11 client for quick start, testing, ad-hoc, or small-scale scenarios:

[Microsoft Learn: Windows Admin Center installation options](https://learn.microsoft.com/windows-server/manage/windows-admin-center/plan/installation-options)

The Microsoft FAQ explicitly says Windows Admin Center can be installed on Windows 10 version 1709 or later, and Windows 11:

[Microsoft Learn: Windows Admin Center FAQ](https://learn.microsoft.com/windows-server/manage/windows-admin-center/understand/faq)

According to the release history, Windows Admin Center became GA in version 1804. Windows 11 as a supported platform for installing and managing with Windows Admin Center was called out separately in the 2110 release:

- [Microsoft Learn: Windows Admin Center release history](https://learn.microsoft.com/windows-server/manage/windows-admin-center/support/release-history)
- [Microsoft Tech Community: Windows Admin Center version 2110 is now generally available](https://techcommunity.microsoft.com/t5/windows-admin-center-blog/windows-admin-center-version-2110-is-now-generally-available/ba-p/2911579)

For that reason, a recent installer rejecting a Windows client system is treated here as installer-version behavior, not as an attempt to bypass licensing restrictions or redistribute a modified Microsoft binary.

## Package Contents

- `install-wac.cmd` - thin ASCII-only launcher. It removes `Zone.Identifier` with `Unblock-File` and starts the interactive TUI wizard through PowerShell with `-ExecutionPolicy Bypass`.
- `interactive-installer.ps1` and `tui\*.ps1` - interactive terminal wizard with no external PowerShell modules. It follows the Microsoft-documented setup flow and runs `wac-setup-engine.ps1` as a hidden process after the final confirmation, keeping progress and log status in the main window.
- `wac-setup-engine.ps1` - main setup script. You can run it directly for automation, uninstall, certificate repair, and best-effort ARM64 runs.
- `LICENSE`, `NOTICE.md`, and `NOTICE.en.md` - project license and boundaries between this open-source code and Microsoft software.

## Release Checks and Build

Before publishing, run from the repository root:

```powershell
.\scripts\test-release.ps1
.\scripts\build-dist.ps1
```

`test-release.ps1` checks PowerShell syntax, Pester tests, PSScriptAnalyzer when the module is available, local-path leaks, and forbidden binaries. `build-dist.ps1` creates `dist\wac-client-windows-setup.zip` and a matching SHA256 file.

## Quick Start

1. Extract the zip to a local folder, for example:

```text
C:\Temp\wac-client-windows-setup
```

2. Run `install-wac.cmd`.
3. Accept the UAC prompt.
4. Wait for completion.
5. Open:

```text
https://localhost:6600
```

The generated self-signed certificate is valid for 60 days. The browser will show a certificate warning unless you provide a trusted certificate or trust the generated one.

If WAC must open both as `https://localhost:6600` and through an external DNS alias, for example behind a router reverse proxy, set that name as `Endpoint FQDN`. A generated self-signed certificate includes the endpoint FQDN, the internal service FQDN, the computer name, and `localhost`, so local access through `localhost` remains usable.

## TUI Installer

`install-wac.cmd` opens the interactive terminal wizard by default. The wizard uses only built-in PowerShell features, shows a short ready-to-install summary, and keeps the full low-level plan behind a separate `Details` action.

During installation, the wizard avoids opening a separate administrator console when Windows allows it. If the current terminal is already elevated, the engine runs directly from it. If the current terminal is not elevated and Windows sudo is enabled, the wizard only shows the UAC consent prompt and then continues updating the same screen. If Windows sudo is unavailable, the wizard falls back to standard `runas` elevation: UAC starts an elevated child process, while the main window keeps reading the shared setup log. The installer engine itself is run with Windows PowerShell 5.1 so `Enable-PSRemoting` configures classic WinRM instead of only PowerShell 7 configurations.

The install progress is driven by the real `C:\WAC-Diag\wac-setup-install-*.log` file: the progress bar moves only when actual setup phases appear in the log, and the bottom of the screen shows cleaned recent log lines without low-level `RUN`/`EXIT` noise.

In `Custom setup`, values are changed directly inside the wizard. Use arrow keys to move by row, `Space` to toggle checkboxes and cycle values, and `Enter` to edit the selected field or press the selected button. Digits and letters remain only as accelerators.

Available fields: install directory, data directory, gateway HTTPS port, service port range, endpoint FQDN, internal service FQDN, TLS certificate mode, certificate thumbprint, generated certificate subject, update mode, diagnostic data setting, network access, self-signed certificate trust, PowerShell Remoting, TrustedHosts mode, WinRM over HTTPS, and existing data preservation.

When the wizard runs on ARM64, the first action screen shows a separate red warning. There is no ARM64 checkbox in custom setup: the interactive wizard adds `-SkipArchitectureCheck` automatically, while direct `wac-setup-engine.ps1` runs still require that switch explicitly.

If WAC was already installed by this package, the wizard detects `C:\ProgramData\WindowsAdminCenter\wac-setup.json` and shows uninstall as the first action. Normal uninstall removes services, the scheduled task, HTTP.SYS binding, firewall rules, and program files, while keeping WAC data. Full uninstall also removes the WAC data directory and is highlighted as a risky action.

The canonical Microsoft installer URL is `https://aka.ms/WACDownload`. Microsoft Learn uses this URL for the PowerShell installation path for Windows Admin Center.

The official WAC installer is not bundled as a binary in the publish package. `wac-setup-engine.ps1` first uses Windows Package Manager only to download the installer:

```cmd
winget download --id Microsoft.WindowsAdminCenter --exact --source winget --architecture x64 --download-directory <directory>
```

If `winget.exe` is unavailable or the download fails, the script falls back to `https://aka.ms/WACDownload`. In both cases the stock WAC installer is not executed: the downloaded Microsoft binary is only extracted by the setup engine.

To run without downloading WAC, pass the path to a previously downloaded official installer explicitly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -InstallerPath C:\Temp\WindowsAdminCenter.exe
```

`innoextract` is not bundled as a binary in the publish package. If `-InnoExtractPath` is not passed explicitly, the script downloads the Windows `innoextract` build for Inno Setup 6.7.0 from `https://github.com/UserUnknownFactor/innoextract_win/releases/download/670/innoextract670.zip`, verifies SHA256 `79B69B9B1FCD98F42CCD4B245EFDF6A03BCFB674BA6AF482F5A46891C9ED4D14`, and extracts it under `C:\ProgramData\WACSetup\tools`. To use an already downloaded `innoextract.exe` without network access, pass `-InnoExtractPath` explicitly. Source code for this build: `https://github.com/UserUnknownFactor/innoextract_win`.

The terms screen does not ask you to type `ACCEPT`: the TUI uses a normal `[ ]` checkbox row, toggled with Space and confirmed with Enter. The wizard shows the Windows Admin Center licensing page on Microsoft Learn, the separate product EULA, and the Microsoft privacy statement:

- [Microsoft Learn: Windows Admin Center licensing](https://learn.microsoft.com/windows-server/windows-server-licensing/windows-admin-center-licensing)
- [Microsoft EULA: Windows Admin Center product GA EULA](https://learn.microsoft.com/legal/windows-server/windows-admin-center/wac-product-ga-eula)
- [Microsoft Privacy Statement](https://privacy.microsoft.com/privacystatement)

WAC third-party component notices remain inside the official Microsoft installer and are not duplicated in the publish package. After payload extraction or installation, they can be found under a dynamic directory, usually:

```text
C:\ProgramData\WACSetup\payload*\commonappdata\WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html
C:\ProgramData\WindowsAdminCenter\UX\legal\3rdPartyDisclosure.html
```

If this file already exists from a previous extraction or installation, the TUI shows its path on the license screen.

For automation or diagnostics, you can still run the setup engine directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1
```

## Custom Setup Options

On the `Custom setup` screen, every row is selectable with the arrow keys. `Enter` edits text/numeric fields or presses the selected button. `Space` toggles checkboxes and cycles fixed-value fields. TUI colors are meaningful: yellow marks system options that affect security or remote management; red marks destructive or unsupported actions.

| Option | Meaning | What the installer does |
| --- | --- | --- |
| `Install directory` | Program files location for WAC. | Copies service and web UI files. Default: `C:\Program Files\WindowsAdminCenter`. |
| `Data directory` | WAC data directory. | Copies/creates WAC data, extensions, and service state. Default: `C:\ProgramData\WindowsAdminCenter`. |
| `Gateway HTTPS port` | Port used by the WAC web UI. | Configures `appsettings.json`, HTTP.SYS SSL binding, URL ACL, and firewall rule. Default: `6600`. |
| `Service port range start` | First internal WAC service port. | Written to WAC configuration. Default: `6601`. |
| `Service port range end` | Last internal WAC service port. | Written to WAC configuration. The range must not be reversed and should follow the gateway port. Default: `6610`. |
| `Endpoint FQDN` | Name users use to open WAC. | Written to gateway settings. If WAC is opened through a DNS alias and a reverse proxy, set the external CNAME here. Defaults to the computer name. |
| `Internal service FQDN` | Name used for internal WAC service calls. | Written to service settings. Usually keep `localhost`. If you use another name, the TLS certificate must cover it too. |
| `TLS certificate mode` | Use an existing certificate or create a self-signed one. | If a thumbprint is set, uses a certificate from `LocalMachine\My`; otherwise creates a self-signed certificate. |
| `Certificate thumbprint` | Thumbprint of an existing TLS certificate. | Looked up in `LocalMachine\My`. The certificate must be valid for Server Authentication, have an accessible private key, and cover all WAC names, including `Endpoint FQDN`, `Internal service FQDN`, the computer name, and `localhost`. |
| `Generated certificate subject` | Subject for a new self-signed certificate. | Used only when no thumbprint is provided. The normal TUI value is not passed as an explicit parameter. If WinRM over HTTPS is enabled, CN is taken from `Endpoint FQDN`; SAN also includes `Internal service FQDN`, the computer name, and `localhost`. If a custom `-CertificateSubject` is passed manually, it must match `-EndpointFqdn`; the installer adds the other names to SAN. |
| `Automatic updates` | Stock wizard update-mode field. | Stored as the selected configuration value for setup; this package does not provide an update service. |
| `Trust generated self-signed certificate` | Add the generated certificate to trusted roots. | Yellow option. Applies only to a generated/reused self-signed certificate; adds it to `LocalMachine\Root` to reduce browser warnings and internal .NET TLS failures. Uninstall does not remove this certificate from `LocalMachine\My` or `LocalMachine\Root`; remove it manually by thumbprint if you no longer need it. |
| `Enable PowerShell Remoting` | Enable WinRM/PowerShell Remoting. | Yellow option. Enabled by default because WAC uses WinRM even for local management. If disabled, the installer passes `-SkipPsRemoting`, and some WAC flows may not work. |
| `Keep existing WAC data` | Preserve the current `C:\ProgramData\WindowsAdminCenter`. | Useful for repair/reinstall. If the old data is corrupted, preserving it can preserve the problem. |
| `Diagnostic data setting` | Stock Microsoft wizard choice: required or optional diagnostic data. | Writes `WindowsAdminCenter.System.TelemetryPrivacy` to `appsettings.json`. |
| `Network access` | Inbound access scope for the WAC web UI. | `local only` removes/skips WAC inbound firewall rules; `local subnet` creates rules with `RemoteAddress=LocalSubnet`; `any address` opens rules for `Any`. HTTP.SYS is still reserved for the selected WAC port. |
| `TrustedHosts mode` | Allow WAC to manage WinRM `TrustedHosts` for workgroup/local-account scenarios. | Yellow option. `manage automatically (*)` sets `WSMan:\localhost\Client\TrustedHosts` to `*` unless policy owns the setting. This means the WinRM client can trust any remote host for workgroup/NTLM-style connections; it does not open the WAC web UI to everyone, but it is still a sensitive machine setting. The setup stores the previous value in the marker and uninstall restores it only when the current value is still `*`. `do not change` leaves the current value untouched. |
| `WinRM over HTTPS` | Use HTTPS for WAC WinRM connections. | Yellow option. Writes `WindowsAdminCenter.FeatureParameters.Base.WinRmOverHttps=true`, creates a WinRM HTTPS listener on `5986` with the WAC TLS certificate, and opens a firewall rule for `5986`. The disabled value does not remove existing WinRM listeners. |

For a router reverse-proxy setup, usually set `Endpoint FQDN` to the external CNAME and keep `Internal service FQDN` as `localhost`. The external proxy sends user traffic to WAC, while WAC itself and local checks keep using `localhost`. If `WinRM over HTTPS` is enabled, the WinRM listener hostname must match the certificate CN or SAN; for that mode, the automatically generated certificate uses the external FQDN as CN and also includes `Internal service FQDN`, the computer name, and `localhost`. An old generated certificate is reused only when it already covers the required names and is valid for Server Authentication; otherwise the installer creates a new certificate.

Command-line mapping:

| TUI option | `wac-setup-engine.ps1` parameter |
| --- | --- |
| `Install directory` | `-InstallDir` |
| `Data directory` | `-DataDir` |
| `Gateway HTTPS port` | `-Port` |
| `Service port range start` | `-ServicePortStart` |
| `Service port range end` | `-ServicePortEnd` |
| `Endpoint FQDN` | `-EndpointFqdn` |
| `Internal service FQDN` | `-ServiceFqdn` |
| `Certificate thumbprint` | `-CertificateThumbprint` |
| `Generated certificate subject` | `-CertificateSubject` |
| `Automatic updates` | <code>-SoftwareUpdateMode Automatic&#124;Manual&#124;Notification</code> |
| `Diagnostic data setting` | <code>-DiagnosticDataMode Required&#124;Optional</code> |
| `Network access` | <code>-NetworkAccess LocalOnly&#124;LocalSubnet&#124;Any</code> |
| `Trust generated self-signed certificate` | `-TrustSelfSignedCertificate` |
| `Enable PowerShell Remoting` | disabled value maps to `-SkipPsRemoting` |
| `TrustedHosts mode` | <code>-TrustedHostsMode ConfigureTrustedHosts&#124;NotConfigureTrustedHosts</code> |
| `WinRM over HTTPS` | <code>-WinRmHttpsMode Enable&#124;Disable</code> |
| `Keep existing WAC data` | `-KeepExistingData` |

Command-line uninstall:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -Uninstall
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -Uninstall -PurgeData
```

`-Uninstall` keeps WAC data and removes only this package marker. `-PurgeData` also removes the data directory, so use it only when you really want a clean start. If the setup changed `TrustedHosts` to `*`, uninstall tries to restore the previous marker value but does not overwrite the setting if it changed after setup. Neither normal nor full uninstall removes certificates from `Cert:\LocalMachine\My` or `Cert:\LocalMachine\Root`; if you trusted a self-signed certificate, review those stores by thumbprint and remove the certificate manually when it is no longer needed.

## WAC Sign-In

WAC in this mode shows a regular form-login page and validates a local Windows account. On the local machine, use the username in one of these forms:

```text
.\USERNAME
COMPUTERNAME\USERNAME
```

For example:

```text
.\wacadmin
PC-NAME\wacadmin
```

If Windows is configured for Windows Hello/PIN, the result can look odd: the username still comes from the local account, while the password field needs the secret Windows accepts for local sign-in for that account. This does not mean WAC supports Windows Hello as a WebAuthn/biometric flow; the WAC page still posts `username/password` to `/api/user/login`.

If sign-in fails, first verify that the internal WAC services are running:

```cmd
curl -k -I https://localhost:6601
curl -k -I https://localhost:6602
```

Both should return `HTTP/1.1 200 OK`. If 6601/6602 are not listening, the problem is not the password; it is the internal WAC service startup.

## System Changes

The script performs these machine-level actions:

- stops and removes existing `WindowsAdminCenter` and `WindowsAdminCenterAccountManagement` services;
- removes the old WAC HTTP.SYS binding on port `6600`;
- copies WAC files to `C:\Program Files\WindowsAdminCenter`;
- copies WAC data to `C:\ProgramData\WindowsAdminCenter`;
- creates or reuses a TLS certificate for the selected WAC names;
- grants `NETWORK SERVICE` access to the certificate private key;
- configures `appsettings.json` for ports `6600-6610`;
- registers HTTP.SYS SSL and URL ACL;
- creates or removes Windows Firewall inbound rules according to `-NetworkAccess`;
- enables WinRM/PowerShell Remoting unless `-SkipPsRemoting` is specified;
- optionally changes WinRM `TrustedHosts`;
- optionally enables WinRM over HTTPS and opens port `5986`; for a generated certificate, accounts for the endpoint FQDN, the internal service FQDN, the computer name, and `localhost`;
- verifies the WAC installer Authenticode signature before extraction: the
  signature must be valid and the publisher must be `O=Microsoft Corporation`;
- runs `efbundle.exe` to initialize the WAC database;
- copies updater files and registers the `WindowsAdminCenterUpdater` scheduled task;
- creates and starts the WAC services.

Logs are written to:

```text
C:\WAC-Diag
```

## Parameters

In interactive mode, change options in the TUI. For automation, pass parameters directly to `wac-setup-engine.ps1`:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -Port 8443 -ServicePortStart 8444 -ServicePortEnd 8453
```

Useful parameters:

```powershell
-Port 6600
-ServicePortStart 6601
-ServicePortEnd 6610
-EndpointFqdn <name>
-CertificateThumbprint <thumbprint>
-SoftwareUpdateMode Automatic|Manual|Notification
-DiagnosticDataMode Required|Optional
-NetworkAccess LocalOnly|LocalSubnet|Any
-TrustSelfSignedCertificate
-TrustedHostsMode ConfigureTrustedHosts|NotConfigureTrustedHosts
-WinRmHttpsMode Enable|Disable
-KeepExistingData
-SkipPsRemoting
-SkipExtraction
-Language Auto|Ru|En
```

`-Language Auto` is the default mode: the script uses Russian for a Russian Windows UI locale and English otherwise. Use `-Language Ru` or `-Language En` to force a specific language.

If you already have a proper Server Authentication TLS certificate in `LocalMachine\My`, prefer passing its thumbprint:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -CertificateThumbprint YOUR_CERT_THUMBPRINT
```

## Manual PowerShell Run

From an elevated PowerShell session:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
Get-ChildItem -LiteralPath . -Recurse -File | Unblock-File -ErrorAction SilentlyContinue
.\wac-setup-engine.ps1
```

## ARM64 Best-Effort Install

Windows 11 ARM64 does not ship a separate `.cmd` launcher, to avoid duplicating the main entry point. Run the best-effort path directly through the setup engine:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -SkipArchitectureCheck
```

This is not a native ARM64 installation. The current WAC payload ships its main executables and native dependencies as `win-x64`; it can only run through Windows 11 ARM64 x64 emulation. The installer path with `-SkipArchitectureCheck` has been verified on ARM64, but Windows Admin Center runtime behavior on ARM64 is not guaranteed.

Known ARM64 limitations:

- **Apps & Features** can take several minutes to open. WAC calls the system `aeinv.dll` (`Application Inventory Component`) through PowerShell remoting; on ARM64 this can hang much longer than on x64. Normal Windows compatibility settings apply to `.exe` files, not to `aeinv.dll` loaded inside `wsmprovhost.exe`, so applying a compatibility layer here is not recommended.
- Overview and Network pages can show an error such as `Network performance class was not found`. On a Russian Windows installation the counter exists as `Сетевой интерфейс`, while parts of WAC extensions can request the English `Network Interface` name. This is a WAC/localization limitation, not evidence that system performance counters are broken.
- WAC uses WinRM/PowerShell remoting heavily even for the local computer. A local account without a normal password, a Microsoft account alias, and Windows Hello/PIN can produce unstable `New-PSSession`/`WSMan` errors. For sign-in and Manage as, prefer explicit `COMPUTERNAME\user` syntax and the password Windows accepts for that account.

## Credentials for Managed Nodes

Signing in to the WAC web UI and connecting to a selected managed node are separate checks. The account that can open the web UI may still lack rights to manage the computer. To connect through WAC, the account must be an administrator on the target machine.

For a local account, use an explicit name:

```text
COMPUTERNAME\user
```

The short `user` name may work for the web UI sign-in and still fail when WAC connects to the node through WinRM. The `Use my Windows account for this connection` option depends on pass-through authentication and Kerberos delegation; in standalone/workgroup scenarios without domain configuration, choose `use another account` and enter a target-machine administrator explicitly.

## Why Not Winget Install

`winget install --id Microsoft.WindowsAdminCenter` runs the stock Windows Admin Center installer. On the locally tested Windows 11 x64 26H1 system, that path can hit the WAC preflight that checks for server SKUs.

`winget download` is used differently: it only downloads the official installer to `C:\ProgramData\WACSetup\downloads`, after which this setup engine takes over. Microsoft binaries are not modified.

## Reinstall and Repair

To repair or reinstall through the TUI, run:

```cmd
install-wac.cmd
```

By default, existing WAC files and data are replaced. To preserve `C:\ProgramData\WindowsAdminCenter`, enable `Preserve existing WAC data` in the TUI or run the setup engine directly:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -KeepExistingData
```

If WAC services are running and port `6600` is listening, but the browser or `curl -k -I https://localhost:6600` fails during TLS handshake, check Schannel in the System Event Log. Error `0x8009030D` usually means the HTTPS layer cannot read the WAC certificate private key as `NETWORK SERVICE`.

In that case, the clean repair path is to rotate WAC to a new certificate instead of reusing the old key binding:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -KeepExistingData -TrustSelfSignedCertificate
```

On ARM64:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\wac-setup-engine.ps1 -SkipArchitectureCheck -KeepExistingData -TrustSelfSignedCertificate
```

These commands preserve `C:\ProgramData\WindowsAdminCenter` and create or reuse a certificate for the current `Endpoint FQDN`. If WAC must open through an external CNAME, pass it explicitly with `-EndpointFqdn`; with WinRM over HTTPS enabled, that FQDN becomes the CN of the generated certificate, while `Internal service FQDN` and `localhost` remain in SAN. If the machine already has an old generated WAC certificate with unsuitable names, it is not reused.
The repair flow also adds the generated self-signed certificate to `LocalMachine\Root`, because some internal WAC/.NET TLS calls can still reject an untrusted chain even when the gateway itself is running. This trust anchor remains in the store after WAC uninstall until you remove the certificate manually.








