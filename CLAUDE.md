# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A packaging project that sets up a developer toolchain (Git, Node.js, npm, Python, AWS CLI, Claude Code CLI) on Windows for a user **without administrator rights**. There is no application code here — the "product" is the installer scripts. The package is distributed via git (clone or GitHub "Download ZIP"); the repo holds only the scripts + `versions.json`, and `install.ps1` downloads the tool binaries from upstream at install time.

The defining constraint that shapes every script: **everything must run in Windows user-mode — no admin, no UAC, no machine-wide changes.** When modifying any script, preserve this. Concretely it means: install into `%USERPROFILE%\ai-devkit`, write only to user-scope PATH (`HKCU\Environment`), and use per-user MSI flags (`ALLUSERS=2 MSIINSTALLPERUSER=1`) so msiexec never elevates.

## Architecture

- **`build.sh`** — runs on Linux/macOS/WSL. Its primary job is to (re)generate `versions.json` from the pinned version variables at the top of the file (no network needed). With `--prefetch` it also downloads the binaries into `./payload` (and `npm pack`s the Claude Code tarball) to enable a fully offline install — but that folder is gitignored and optional.
- **Install side (`install.ps1`, `activate.ps1`, `uninstall.ps1`)** — run on Windows from inside the cloned/extracted folder. `install.ps1` **downloads** each binary from the URLs in `versions.json` into `./payload` (reusing any file already present, so a pre-staged `payload/` makes it offline), then installs into `%USERPROFILE%\ai-devkit`. Claude Code is installed from the npm registry unless an `anthropic-ai-claude-code-*.tgz` is staged in `payload/`. An internet connection is required at install time.

**`versions.json` is the contract.** `build.sh` generates it from the pinned variables; `install.ps1` reads both the filenames (`$V.git_file`, …) and the download URLs (`$V.git_url`, `$V.node_url`, `$V.python_url`, `$V.getpip_url`, `$V.awscli_url`). If you change a pinned version, filename, or add a tool, update the `versions.json` writer (build.sh) and its readers (install.ps1) in lockstep, then re-run `./build.sh` and commit the regenerated `versions.json`.

Pinned versions live **only** at the top of `build.sh`. That is the single source of truth — `README.txt` lists them for humans but is not read by any script. `versions.json` is committed and is the generated artifact of that source.

## Common commands

```bash
./build.sh              # regenerate versions.json (no network; commit the result)
./build.sh --prefetch   # also download binaries into ./payload for offline installs (needs: curl, npm)
```

There is no ZIP build and no test suite; verification is manual (clone/extract on Windows and run `install.ps1`).

Windows install/uninstall (run by the end user, not in this dev environment):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1            # default install to %USERPROFILE%\ai-devkit
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force     # overwrite existing
powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoPathUpdate   # don't touch PATH; use activate.ps1 instead
. .\activate.ps1                                                  # session-only PATH (dot-sourced)
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

`payload/` is gitignored — it holds binaries downloaded by `install.ps1` (or pre-staged via `build.sh --prefetch`), never commit it. (`build/` and `dist/` are legacy ignores from the old ZIP build and are no longer produced.)

## Install-side conventions to preserve

- **PATH handling** is duplicated across three scripts and must stay consistent: `install.ps1` prepends six dirs to user PATH (`git\cmd`, `node`, `npm-global`, `python`, `python\Scripts`, `aws`), `activate.ps1` prepends the same set to the session only, `uninstall.ps1` removes exactly that set. Adding a tool means touching the dir list in all three.
- **npm is redirected into the portable tree** via a generated `%USERPROFILE%\.npmrc` (`prefix=...\npm-global`, `cache=...\npm-cache`) so Claude Code installs without admin. `uninstall.ps1` intentionally leaves `.npmrc` in place.
- **AWS CLI has a fallback path**: if the per-user MSI fails (corporate policy → exit 1625/1603), `install.ps1` falls back to `pip install awscli` (v1) inside the portable Python, and points PATH at `python\Scripts` instead of `aws\`. Keep both branches working.
- **Python is the embeddable distribution** — pip is bootstrapped by un-commenting `import site` in `python*._pth` then running `get-pip.py`. The embeddable build has no pip by default; don't assume a normal Python layout.

## Documentation workspace

`docs/` follows the ai-devkit convention (scaffolded by `/kickoff`): `architecture/` (design decisions), `analyzes/` (pre-decision research snapshots), `reference/` (vendor/operational specs), `work/` (initiatives as `NNN-<slug>/` folders managed by `/atomize` and `/implement`). See `docs/README.md`.
