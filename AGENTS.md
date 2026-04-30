# AGENTS.md

## Scope

This repository contains only the open-source wrapper scripts, tests, and documentation for `wac-client-windows-setup`.

Do not add Microsoft Windows Admin Center binaries, extracted payloads, installer downloads, `innoextract.exe`, local logs, temporary files, secrets, personal paths, or agent working notes to the public repository.

## Language

Primary documentation is Russian. English versions live next to Russian files as `.en.md` sidecars.

For language cross-links, write the link label in the target language:

- Russian files linking to English: `English version: [...]`
- English files linking to Russian: `Русская версия: [...]`

## Checks

Before claiming publication readiness, run:

```powershell
.\scripts\test-release.ps1
.\scripts\build-dist.ps1
```

## Review guidelines

Codex Cloud and CodeRabbit reviews should follow this file plus `.coderabbit.yaml`.

Review focus:

- no bundled Microsoft WAC installers, extracted payloads, or `innoextract.exe`;
- Windows PowerShell 5.1 compatibility for install/runtime scripts;
- Russian primary documentation with `.en.md` English sidecars;
- release packages generated only by `scripts\build-dist.ps1`.

## Release Package

Release zip contents are controlled by `scripts\build-dist.ps1`.

Do not include repository-only files such as `AGENTS.md`, `CONTRIBUTING.md`, `CONTRIBUTING.en.md`, `.github`, `scripts`, `tests`, `.gitignore`, `.codex`, or `tmp` in the release zip unless the release policy is intentionally changed.
