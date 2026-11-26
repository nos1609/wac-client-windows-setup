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

## Verify a candidate across two repositories

Develop in private Forgejo. Push the candidate to a branch with the `feature/` prefix. The workflow calls a SHA-pinned `fj-actions-common/pester-ci`, checks the commit range, runs the portable tests, and checks the ZIP contents and SHA256. For a manual run, supply the full ancestor SHA in `base_commit`. The runner must provide Bash, Node, pwsh 7.7+, and Pester 6.2+ as required by the common workflow.

Each push to a private `feature/**` branch or to `main` runs the shared `coderabbit-review.yml` after Pester passes. CodeRabbit reviews the full diff from the merge base with `main` for a feature branch and the pushed range for `main`. Each review uses CodeRabbit quota. A successful review requires a `clean` result. Reviews for the same branch share a queue. A manual run of `ci.yml` runs only the portable checks. For a manual review, dispatch `review.yml` with full SHAs in `base_commit` and `expected_head_sha`. CodeRabbit runs on `common-review` by default. After the review, `review-policy` checks the receipt against the task, base commit, and candidate SHA.

Set the Forgejo Actions variable `COMMON_LIGHT_RUNNER` to the light runner label for short checks. An empty value selects `self-hosted`. The main runner builds the ZIP and runs Pester. The `package.yml` workflow keeps the ZIP and SHA-256 file in the `wac-distribution` artifact for 14 days. The light runner downloads the artifact and compares it with the files in the source commit. For a `v<VERSION>` tag on the history of `main`, the `generic-package-publish` action publishes the verified files to Forgejo Packages. Set the repository secret `PACKAGE_TOKEN` with package write access. Use the private workflow run to download candidate builds.

GitHub hosts public PRs, Dependabot, and Windows CI. Promote the same verified commit. Before publication, check the ancestry of both `main` branches. Compare their SHAs after promotion. Include commits accepted through GitHub PRs in the next private verification. Stop promotion if the branches diverge. Tagging and publishing a release ZIP require a separate decision.
