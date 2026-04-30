# Security Policy

Русская версия: [SECURITY.md](SECURITY.md)

## Scope

This project is a PowerShell setup wrapper for Windows Admin Center on Windows
client systems. It does not redistribute Microsoft Windows Admin Center binaries.
The installer downloads the official Microsoft installer at runtime or accepts a
local path to an installer supplied by the user.

## Reporting Vulnerabilities

After publication, use the repository's GitHub Security Advisories feature if it
is enabled. If private advisories are not available yet, open a minimal public
issue that does not include exploit details or sensitive diagnostics and ask for
a private disclosure channel.

Do not publish active exploit details until the issue has been triaged and a fix
or mitigation path is available.

## Reporting Diagnostics

Do not publish sensitive logs, certificate private keys, local account names, or
machine-specific paths in public issues. Redact local paths, hostnames, account
names, certificate thumbprints, and IP addresses before sharing diagnostics.

## Local Security Effects

The setup flow can enable WinRM, add firewall rules, register HTTP.SYS bindings,
create or trust a self-signed certificate, and run services as `NETWORK SERVICE`.
Review the ready-to-install screen before applying changes.

The Microsoft Windows Admin Center installer is checked with Authenticode before
extraction. The signature must be valid and the signer certificate must identify
`O=Microsoft Corporation`. This check protects the local-installer path as well
as the downloaded installer path; it does not replace Microsoft's own EULA or
licensing terms.

If `-TrustSelfSignedCertificate` is used, the generated or reused self-signed
certificate is added to `Cert:\LocalMachine\Root`. That store is a machine-wide
trust store: adding a certificate there makes Windows trust chains that end at
that certificate. The private key remains in `Cert:\LocalMachine\My`, and the
setup grants `NETWORK SERVICE` access to that key so the WAC service can use it.

Uninstall removes Windows Admin Center services, HTTP.SYS bindings, firewall
rules, and project markers, but it does not automatically remove certificates
from `Cert:\LocalMachine\My` or `Cert:\LocalMachine\Root`. Review those stores
by thumbprint and remove the certificate manually if you no longer trust it.

If TrustedHosts management is enabled, the setup can change the WinRM client
TrustedHosts value. Broad values such as `*` mean the WinRM client can trust any
remote host for workgroup/NTLM-style connections; this does not mean the WAC web
server is opened to everyone, but it is still a security-sensitive local machine
setting. The setup stores the previous value in the project marker and uninstall
restores it only when the current value is still `*`; if the value changed after
setup, uninstall leaves it unchanged. Review it after testing.
