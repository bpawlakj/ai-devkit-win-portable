================================================================
  ai-devkit portable for Windows
  Step-by-step installation guide
================================================================

WHAT IS IN THIS PACKAGE?
------------------------

A bundle of developer tools that install WITHOUT administrator
rights. You do NOT need the admin password. No "Run as
administrator", no UAC prompt.

Tools included (all pre-downloaded, no internet needed during
install):

   * Git              2.54.0
   * Node.js          24.16.0
   * npm              11.13.x   (bundled with Node.js)
   * Python           3.14.3
   * AWS CLI v2       latest
   * Claude Code      2.1.76    (CLI)

Everything is installed into:

   C:\Users\<your-username>\ai-devkit

and added to your personal PATH (no machine-wide changes).


================================================================
  INSTALLATION
================================================================

STEP 1.  Extract the ZIP archive
--------------------------------
   1. Right-click "ai-devkit-win-portable-*.zip"
      -> "Extract All..." -> pick a writable location (Desktop
      or Downloads is fine).
   2. Open the extracted folder. You will see:
         install.ps1
         activate.ps1
         uninstall.ps1
         README.txt
         versions.json
         payload\

STEP 2.  Open a regular PowerShell window
-----------------------------------------
   1. Press the Windows key.
   2. Type:  powershell
   3. Press Enter.
   IMPORTANT: do NOT pick "Run as administrator". A normal
   user-mode PowerShell window is exactly what you want.

STEP 3.  Change directory to the extracted folder
-------------------------------------------------
   In the PowerShell window, type (replace the path with yours):

      cd $env:USERPROFILE\Desktop\ai-devkit-win-portable

   Tip: you can drag the folder from File Explorer onto the
   PowerShell window — the path will be pasted. Remember to type
   "cd " before it.

STEP 4.  Run the installer
--------------------------
   Type exactly:

      powershell -ExecutionPolicy Bypass -File .\install.ps1

   Press Enter. The script will:
      - copy Git, Node.js, Python, AWS CLI, Claude Code into
        C:\Users\<you>\ai-devkit
      - bootstrap pip for Python
      - install claude-code locally via npm
      - add the tools to your user PATH

   Typical runtime: 2-5 minutes. No UAC prompts will appear.

STEP 5.  Close PowerShell and open a NEW window
-----------------------------------------------
   PATH is loaded when a terminal starts. Close the current
   window and open a new one (Windows key -> powershell).

STEP 6.  Verify it works
------------------------
   In the new PowerShell, run each command:

      git --version
      node --version
      npm --version
      python --version
      aws --version
      claude --version

   Each should print a version string. If yes — done.

STEP 7.  First-time Claude Code login
-------------------------------------
   Claude Code requires an Anthropic account:

      claude login

   A browser tab opens for sign-in. Once signed in, return to
   the terminal — you are ready to go.


================================================================
  ADVANCED OPTIONS
================================================================

Install to a different location:

   powershell -ExecutionPolicy Bypass -File .\install.ps1 `
              -InstallRoot 'D:\portable\ai-devkit'

Do NOT modify user PATH (use activate.ps1 instead):

   powershell -ExecutionPolicy Bypass -File .\install.ps1 -NoPathUpdate

Then, per PowerShell session:

   . .\activate.ps1

Force reinstall (overwrite existing):

   powershell -ExecutionPolicy Bypass -File .\install.ps1 -Force


================================================================
  UNINSTALL
================================================================

   powershell -ExecutionPolicy Bypass -File .\uninstall.ps1

Removes C:\Users\<you>\ai-devkit and cleans your user PATH.
Nothing system-wide is touched.


================================================================
  TROUBLESHOOTING
================================================================

"running scripts is disabled on this system"
   You forgot -ExecutionPolicy Bypass on the command line. Use
   the exact command from STEP 4. The Bypass flag is scoped to
   that single run only — no permanent policy change.

"git: command not found" after install
   You did not open a NEW PowerShell window. PATH updates only
   apply to terminals started AFTER install.ps1 finished.

AWS CLI MSI fails with error 1625 or 1603
   Corporate policy blocks even per-user MSI installs. The
   installer auto-falls back to "pip install awscli" (v1) inside
   the portable Python. You will still get an "aws" command.

"claude: command not found"
   Run:  echo $env:Path
   Confirm that the path ending in "ai-devkit\npm-global" is
   present. If not — re-open PowerShell, or run activate.ps1.

Antivirus quarantines PortableGit-*.7z.exe
   Some corporate AVs flag self-extracting 7z files. Whitelist
   the payload folder, or unblock the file with PowerShell:
      Unblock-File .\payload\PortableGit-*.7z.exe
   then re-run install.ps1.


================================================================
  WHAT GOES WHERE?
================================================================

   C:\Users\<you>\ai-devkit\
      git\        PortableGit
      node\       Node.js + npm
      npm-global\ npm "global" packages (claude-code lives here)
      npm-cache\  npm cache
      python\     Python embeddable + pip + site-packages
      aws\        AWS CLI v2 (or pip-installed awscli fallback)

   C:\Users\<you>\.npmrc
      Generated by install.ps1. Tells npm to use the portable
      tree for global installs.

   User PATH (HKCU\Environment\Path)
      Six new entries appended (git\cmd, node, npm-global,
      python, python\Scripts, aws). Cleanly removed by
      uninstall.ps1.


================================================================
  MAINTAINERS — rebuilding the package
================================================================

On Linux / macOS / WSL:

   ./build.sh

Produces dist/ai-devkit-win-portable-YYYYMMDD.zip (~170 MB).

Pinned versions live at the top of build.sh.
