# Contribution Notes

Русская версия: [CONTRIBUTING.md](CONTRIBUTING.md)

This repository contains only the open-source wrapper scripts, tests, and documentation for `wac-client-windows-setup`.

Do not add Microsoft Windows Admin Center binaries, extracted payloads, `innoextract.exe`, local logs, temporary downloads, machine-specific diagnostics, personal paths, secrets, or agent working notes to the public repository.

Before publishing a release, run from the repository root:

```powershell
.\scripts\test-release.ps1
.\scripts\build-dist.ps1
```

Required release checks:

- `.coderabbit.yaml`, `AGENTS.md`, `CONTRIBUTING.md`, `CONTRIBUTING.en.md`, `install-wac.cmd`, `interactive-installer.ps1`, `wac-setup-engine.ps1`, `tui\*.ps1`, `README.md`, `README.en.md`, `VERSION`, `SECURITY.md`, `SECURITY.en.md`, `LICENSE`, `NOTICE.md`, and `NOTICE.en.md` are present.
- No Microsoft WAC installer binary, extracted WAC payload, MSI/MSIX/AppX/CAB, or `innoextract.exe` is present in the repository or release zip.
- No old version-pinned package names or legacy offline-installer naming remains in public files.
- No developer workstation paths, user-profile paths, downloads-folder examples, or machine-specific diagnostics remain in public files.
- Pester tests pass.
- PowerShell files parse under Windows PowerShell.
- PSScriptAnalyzer reports no `Error` severity diagnostics when the module is available.
- The release zip is generated under `dist\wac-client-windows-setup.zip` with a matching `.sha256` file.

## Versioning

The project uses SemVer in the `VERSION` file without a leading `v`; release git tags use the same number with a leading `v`, for example `v0.1.0`.

- `PATCH`: fixes to our scripts, documentation, CI, and release process without changing the user-facing contract.
- `MINOR`: support for a new Windows Admin Center version or new backward-compatible installer capabilities.
- `MAJOR`: incompatible CLI, package layout, setup-logic changes, or a large refactor that needs careful migration.
