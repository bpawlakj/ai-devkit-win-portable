# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A packaging project that sets up a developer toolchain (Git, Node.js, npm, Python, AWS CLI, Claude Code CLI) on Windows for a user **without administrator rights**. There is no application code here — the "product" is the installer scripts. The package is distributed via git (clone or GitHub "Download ZIP"); the repo holds only the scripts + `versions.json`, and `install.ps1` downloads the tool binaries from upstream at install time.

The defining constraint that shapes every script: **everything must run in Windows user-mode — no admin, no UAC, no machine-wide changes.** When modifying any script, preserve this. Concretely it means: install into `%USERPROFILE%\ai-devkit`, write only to user-scope PATH (`HKCU\Environment`), and use per-user MSI flags (`ALLUSERS=2 MSIINSTALLPERUSER=1`) so msiexec never elevates.

## Architecture

- **`build.sh`** — runs on Linux/macOS/WSL. Its primary job is to (re)generate `versions.json` from the pinned version variables at the top of the file (no network needed). With `--prefetch` it also downloads the Git/Node/Python/AWS/get-pip binaries into `./payload` to enable an offline install of those tools — but that folder is gitignored and optional. Claude Code is **not** pre-staged (see below).
- **Install side (`install.ps1`, `install-claude.ps1`, `activate.ps1`, `uninstall.ps1`)** — run on Windows from inside the cloned/extracted folder. `install.ps1` **downloads** each binary from the URLs in `versions.json` into `./payload` (reusing any file already present, so a pre-staged `payload/` makes those tools offline), then installs into `%USERPROFILE%\ai-devkit`. **Claude Code lives in its own `install-claude.ps1`** (it can be run standalone) and is installed via the official installer (`irm https://claude.ai/install.ps1 | iex`): the bootstrap downloads a native `claude.exe`, verifies its SHA256, and runs `claude install` — placing the launcher in `%USERPROFILE%\.local\bin` (outside the `ai-devkit\` tree) and adding it to the user PATH itself. There is **no Node.js dependency** for Claude Code, and it always needs internet (version + checksum are resolved live, so it cannot be pre-staged offline).
  - `install.ps1` runs Claude Code **first** (delegating to `install-claude.ps1` as a child process, since it has no dependency on Git/Node/Python/AWS — so the CLI is usable even if a later step fails), then installs the rest. Switches: **`-SkipClaude`** installs everything except Claude; **`-Claude`** installs only Claude (delegates and exits); the two are mutually exclusive. `install-claude.ps1` resolves its target from `versions.json` (`claude_code`) or an explicit `-Target`, defaulting to `stable`.
  - An internet connection is required at install time.

**`versions.json` is the contract.** `build.sh` generates it from the pinned variables; `install.ps1` reads both the filenames (`$V.git_file`, …) and the download URLs (`$V.git_url`, `$V.node_url`, `$V.python_url`, `$V.getpip_url`, `$V.awscli_url`). The `claude_code` field is special: it is **not** a URL/filename but the install target passed to the official Claude Code installer — a pinned semver (`"2.1.76"`) or the channel keywords `"stable"` / `"latest"` (install.ps1 falls back to `stable` if it's empty/absent). If you change a pinned version, filename, or add a tool, update the `versions.json` writer (build.sh) and its readers (install.ps1) in lockstep, then re-run `./build.sh` and commit the regenerated `versions.json`.

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

- **ASCII-only in the `.ps1` files.** Windows PowerShell 5.1 reads a BOM-less `.ps1` as the system ANSI codepage (cp1252), not UTF-8. A multi-byte char like `->` (arrow) or `-` (em-dash) then mojibakes; worse, an em-dash's bytes decode to a sequence ending in U+201D `"`, which the PS parser treats as a **string delimiter** — silently breaking string/brace matching far away in the file. Use plain ASCII (`->`, `-`, straight quotes) in all scripts. If you must add non-ASCII, save the file UTF-8 **with BOM**.
- **PATH handling** is duplicated across `install.ps1` / `activate.ps1` / `uninstall.ps1` and must stay consistent. The set: `git\cmd`, `node`, `npm-global`, `python`, `python\Scripts`, the **resolved AWS dir** (see below), and `%USERPROFILE%\.local\bin`. `install.ps1` prepends them to user PATH, `activate.ps1` to the session only. **Asymmetry to preserve:** `uninstall.ps1` removes the `ai-devkit\` dirs **and** the AWS dir but intentionally leaves `.local\bin` alone, because Claude Code's own installer owns that dir and its PATH entry (a separately-installed claude must keep working). `.local\bin` is added by install/activate for convenience but is not ours to remove.
- **npm is redirected into the portable tree** via a generated `%USERPROFILE%\.npmrc` (`prefix=...\npm-global`, `cache=...\npm-cache`) so user-mode `npm -g` installs work without admin. (Claude Code no longer uses this — it is a native binary in `.local\bin` — but the redirect stays for any other global npm packages.) `uninstall.ps1` intentionally leaves `.npmrc` in place.
- **AWS CLI install dir is resolved, not assumed.** The v2 per-user MSI **ignores `INSTALLDIR`** and always lands in `%LOCALAPPDATA%\Programs\Amazon\AWSCLIV2`; `install.ps1` locates `aws.exe` there (checking the requested dir first) and that resolved dir is what goes on PATH. If the MSI fails (corporate policy → exit 1625/1603) or `aws.exe` isn't found, it falls back to `pip install awscli` (v1) inside the portable Python and points PATH at `python\Scripts`. Keep all branches working; `activate.ps1`/`uninstall.ps1` reference the `%LOCALAPPDATA%` path too.
- **PortableGit is a 7-Zip SFX** extracted via `Start-Process -FilePath $GitExe -ArgumentList '-y',"-o`"$GitDir`"" -Wait` — it **must** be `-Wait`ed (the SFX is a GUI-subsystem exe that detaches from `&`, so the script would race ahead and see an empty dir) and the only valid switches are `-y` and `-o"<dir>"` (no `-gm2`).
- **Python is the embeddable distribution** — pip is bootstrapped by un-commenting `import site` in `python*._pth` then running `get-pip.py`. The embeddable build has no pip by default; don't assume a normal Python layout.

## Documentation workspace

`docs/` follows the ai-devkit convention (scaffolded by `/kickoff`): `architecture/` (design decisions), `analyzes/` (pre-decision research snapshots), `reference/` (vendor/operational specs), `work/` (initiatives as `NNN-<slug>/` folders managed by `/atomize` and `/implement`). See `docs/README.md`.
