# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A packaging project that bundles a developer toolchain (Git, Node.js, npm, Python, AWS CLI, Claude Code CLI) into a single ZIP that a Windows user **without administrator rights** can install. There is no application code here — the "product" is the installer and the artifact it produces.

The defining constraint that shapes every script: **everything must run in Windows user-mode — no admin, no UAC, no machine-wide changes.** When modifying any script, preserve this. Concretely it means: install into `%USERPROFILE%\ai-devkit`, write only to user-scope PATH (`HKCU\Environment`), and use per-user MSI flags (`ALLUSERS=2 MSIINSTALLPERUSER=1`) so msiexec never elevates.

## Two-sided architecture

The repo is built on one OS and consumed on another:

- **Build side (`build.sh`)** — runs on Linux/macOS/WSL. Downloads pinned upstream Windows binaries into `build/payload/`, packs the Claude Code npm tarball offline (`npm pack`), writes `versions.json`, copies the three `.ps1` scripts + `README.txt`, and zips `build/` into `dist/ai-devkit-win-portable-YYYYMMDD.zip` (~170 MB).
- **Install side (`install.ps1`, `activate.ps1`, `uninstall.ps1`)** — run on Windows from inside the extracted ZIP. The install is fully **offline**: every binary is pre-downloaded in `payload/`, nothing is fetched at install time.

**`versions.json` is the contract between the two sides.** `build.sh` generates it from the pinned version variables at the top of the file; `install.ps1` reads it (`$V.git_file`, `$V.node_file`, `$V.python_file`, etc.) to locate payload files and print versions. If you change a payload filename or add a tool in `build.sh`, you must update both the `versions.json` writer (build.sh) and its readers (install.ps1) in lockstep, or the installer will fail with "missing <file>".

Pinned versions live **only** at the top of `build.sh` (lines ~9-14). That is the single source of truth — `README.txt` lists them for humans but is not read by any script.

## Common commands

```bash
./build.sh          # build dist/ai-devkit-win-portable-YYYYMMDD.zip (needs: curl, zip, npm)
```

`build.sh` caches downloads in `build/payload/` and skips re-fetching existing files — but note it runs `rm -rf build dist` at the start, so the cache does not survive between runs. There is no test suite; verification is manual (extract the ZIP on Windows and run `install.ps1`).

Windows install/uninstall (run by the end user, not in this dev environment):

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1            # default install to %USERPROFILE%\ai-devkit
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force     # overwrite existing
powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoPathUpdate   # don't touch PATH; use activate.ps1 instead
. .\activate.ps1                                                  # session-only PATH (dot-sourced)
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

`build/` and `dist/` are gitignored build artifacts — do not edit files under `build/` (they are overwritten copies of the root `.ps1`/`README.txt`/generated `versions.json`).

## Install-side conventions to preserve

- **PATH handling** is duplicated across three scripts and must stay consistent: `install.ps1` prepends six dirs to user PATH (`git\cmd`, `node`, `npm-global`, `python`, `python\Scripts`, `aws`), `activate.ps1` prepends the same set to the session only, `uninstall.ps1` removes exactly that set. Adding a tool means touching the dir list in all three.
- **npm is redirected into the portable tree** via a generated `%USERPROFILE%\.npmrc` (`prefix=...\npm-global`, `cache=...\npm-cache`) so Claude Code installs without admin. `uninstall.ps1` intentionally leaves `.npmrc` in place.
- **AWS CLI has a fallback path**: if the per-user MSI fails (corporate policy → exit 1625/1603), `install.ps1` falls back to `pip install awscli` (v1) inside the portable Python, and points PATH at `python\Scripts` instead of `aws\`. Keep both branches working.
- **Python is the embeddable distribution** — pip is bootstrapped by un-commenting `import site` in `python*._pth` then running `get-pip.py`. The embeddable build has no pip by default; don't assume a normal Python layout.

## Documentation workspace

`docs/` follows the ai-devkit convention (scaffolded by `/kickoff`): `architecture/` (design decisions), `analyzes/` (pre-decision research snapshots), `reference/` (vendor/operational specs), `work/` (initiatives as `NNN-<slug>/` folders managed by `/atomize` and `/implement`). See `docs/README.md`.
