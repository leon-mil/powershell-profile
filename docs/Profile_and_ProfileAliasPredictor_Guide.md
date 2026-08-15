# PowerShell Profile & ProfileAliasPredictor — Complete User and Setup Guide

**Guide version:** 2.0  
**Updated:** August 15, 2026  
**Profile repository:** `leon-mil/powershell-profile`  
**Primary profile:** `$HOME\Documents\PowerShell\profile.ps1`  
**Predictor project:** `$HOME\Documents\PowerShell\Projects\ProfileAliasPredictor`

> This guide documents the current shared profile baseline plus the finalized backup/archive command family (`backup-file`, `backup-dir`, `zip-file`, `zip-dir`, and `unzip`). It is designed both as a daily reference and as a start-to-finish installation guide for a new user.

## Contents

1. [What this profile provides](#1-what-this-profile-provides)
2. [Architecture and how the pieces work together](#2-architecture-and-how-the-pieces-work-together)
3. [Recommended repository and directory layout](#3-recommended-repository-and-directory-layout)
4. [New user setup — start to finish](#4-new-user-setup--start-to-finish)
5. [Five-minute daily quick start](#5-five-minute-daily-quick-start)
6. [Complete alias reference](#6-complete-alias-reference)
7. [Backup, ZIP, and unzip workflows](#7-backup-zip-and-unzip-workflows)
8. [CPRS build and deployment workflows](#8-cprs-build-and-deployment-workflows)
9. [ProfileAliasPredictor project](#9-profilealiaspredictor-project)
10. [Prediction and PSReadLine behavior](#10-prediction-and-psreadline-behavior)
11. [Complete PowerShell function reference](#11-complete-powershell-function-reference)
12. [Complete predictor suggestion catalog](#12-complete-predictor-suggestion-catalog)
13. [Adding or changing commands](#13-adding-or-changing-commands)
14. [Git workflow for the two repositories](#14-git-workflow-for-the-two-repositories)
15. [Troubleshooting](#15-troubleshooting)
16. [Portability and machine-specific paths](#16-portability-and-machine-specific-paths)
17. [New-user completion checklist](#17-new-user-completion-checklist)

## 1. What this profile provides

The profile turns frequently repeated PowerShell, Git, CPRS, navigation, build, deployment, history, backup, archive, and predictor-development tasks into short commands. The short command is normally an alias such as `gst`, `predtest`, `cprs-test-deploy`, `backup-file`, or `unzip`; the actual behavior lives in a PowerShell function or built-in command.

The documented command surface contains **54 managed aliases**, **58 custom global functions**, and **94 predictor suggestion templates**. The predictor is intentionally separate from command execution: it suggests commands while you type, but the PowerShell profile performs the work.

The main design goals are: easy-to-remember commands, centralized alias registration, reusable functions, safe preview/verification for destructive operations, a self-documenting `phelp` menu, and predictive IntelliSense that exposes valid command forms as the user types.

## 2. Architecture and how the pieces work together

```text
You type a command, for example:
    cprs-test-deploy -WhatIf
              |
              v
Get-ProfileAliasDefinition in profile.ps1
              |
              v
Alias resolves to a PowerShell function
              |
              v
Deploy-CprsTestClient performs the work

At the same time:
ProfileAliasPredictor.dll watches the typed prefix and can suggest
"cprs-test-deploy -WhatIf" with a description.

```

There are three important layers:

| Layer | Responsibility | When to change it |
|---|---|---|
| `profile.ps1` | Functions, aliases, help, paths, PSReadLine configuration, CPRS workflows, backup/archive tools | Change when behavior, paths, parameters, aliases, or help changes |
| `ProfileAliasPredictor.cs` | Predictive command strings and descriptions | Change when predictive suggestions need to be added, renamed, or clarified |
| `ProfileAliasPredictor.dll` | Compiled predictor loaded by PowerShell | Rebuild after changing the C# source |

A profile-only change normally needs `rprof`. A predictor source change needs `predrebuild` and then `predtest`. If an alias and its predictor description both change, update both repositories so actual behavior and predictive help stay synchronized.

## 3. Recommended repository and directory layout

```text
C:\Users\<user>\Documents\PowerShell\
│   profile.ps1
│   README.md
│   .gitignore
│
├── docs\
│   └── PowerShell_Profile_and_ProfileAliasPredictor_Guide.md
│
└── Projects\
    └── ProfileAliasPredictor\          <- separate Git repository
        │   ProfileAliasPredictor.cs
        │   ProfileAliasPredictor.csproj
        │
        ├── bin\
        │   └── Release\
        │       └── net10.0\
        │           └── ProfileAliasPredictor.dll
        └── obj

```

The predictor project is intentionally a **separate Git repository** nested under `Projects\ProfileAliasPredictor`. The outer profile repository should not accidentally track the predictor repository. Add `Projects/` or at minimum `Projects/ProfileAliasPredictor/` to the profile repository `.gitignore`. Likewise, the predictor repository should ignore `bin/` and `obj/`.

The profile is written around `$HOME` for the PowerShell development paths, so the same layout works for another Windows user without changing the username. CPRS and V-drive paths are organization-specific and must be reviewed separately.

## 4. New user setup — start to finish

### 4.1 Prerequisites

Install or make available: PowerShell 7.2 or newer, Git, Visual Studio Code with the `code` command on PATH, and the .NET SDK required by `ProfileAliasPredictor.csproj` (the current build output is `net10.0`, so the matching .NET 10 SDK is expected). CPRS-specific commands additionally require the CPRS source repositories, Visual Studio/MSBuild, and access to the appropriate V: drive locations.

Verify the key tools:

```powershell
$PSVersionTable.PSVersion
git --version
code --version
dotnet --version

```

### 4.2 Confirm the profile location

```powershell
$PROFILE.CurrentUserAllHosts

```

The intended location is normally `C:\Users\<user>\Documents\PowerShell\profile.ps1`. The repository should be placed so that its `profile.ps1` is exactly at `$PROFILE.CurrentUserAllHosts`.

### 4.3 Preserve an existing profile before installation

If the user already has a profile, back it up before replacing or merging it. A simple first-install backup can be made manually before this custom profile is loaded:

```powershell
$profilePath = $PROFILE.CurrentUserAllHosts
if (Test-Path $profilePath) {
    Copy-Item $profilePath "$profilePath.before-leon-profile.bak"
}

```

### 4.4 Clone the profile repository

For a clean machine where the PowerShell profile directory is empty or does not yet exist:

```powershell
$profileRoot = Split-Path $PROFILE.CurrentUserAllHosts -Parent
New-Item -ItemType Directory -Path (Split-Path $profileRoot -Parent) -Force | Out-Null
git clone https://github.com/leon-mil/powershell-profile.git $profileRoot

```

If `Documents\PowerShell` already contains other modules or scripts, do not blindly clone over it. Clone the repository to a temporary directory and copy/merge `profile.ps1`, `README.md`, and `docs` into the existing profile root, or initialize the existing directory as the repository only after reviewing its contents.

### 4.5 Clone the predictor repository into the required location

Create the `Projects` folder and clone the separate predictor repository into the exact directory expected by the profile:

```powershell
$predictorRoot = Join-Path $HOME 'Documents\PowerShell\Projects\ProfileAliasPredictor'
New-Item -ItemType Directory -Path (Split-Path $predictorRoot -Parent) -Force | Out-Null

git clone <ProfileAliasPredictor-repository-URL> $predictorRoot

```

Replace `<ProfileAliasPredictor-repository-URL>` with the GitHub URL after that repository is created. The directory name should remain `ProfileAliasPredictor` unless the profile functions are changed.

### 4.6 Build the predictor before relying on plug-in suggestions

```powershell
cd "$HOME\Documents\PowerShell\Projects\ProfileAliasPredictor"
dotnet restore
dotnet build .\ProfileAliasPredictor.csproj --configuration Release

```

The expected DLL is `Projects\ProfileAliasPredictor\bin\Release\net10.0\ProfileAliasPredictor.dll`.

### 4.7 Start a fresh PowerShell 7 session

Close the setup shell if necessary and open a new PowerShell 7 window. The profile initialization should register aliases, configure PSReadLine, and load the predictor DLL when it is available.

Then run:

```powershell
ppath
predinfo
predtest
predstate
phelp

```

A healthy setup should show the profile path, an existing predictor DLL, the `ProfileAliases` predictor registered, aliases registered, and prediction source normally set to `HistoryAndPlugin` with `ListView`.

### 4.8 Review machine-specific paths

Before a new user relies on CPRS/navigation commands, review the CPRS development root, SAS/batch repositories, FileOps workspace, production directories, TEST deployment directories, and production deployment directories. These are not portable just because the profile itself is portable.

### 4.9 Recommended `.gitignore` boundaries

Because the profile repository lives at the PowerShell root and the predictor is a separate nested repository, a safe starting point is:

```gitignore
# Separate repository
Projects/

# Build/runtime artifacts
Backups/
Archives/
*.log
*.tmp

# Never version local command history
*history*.txt

```

Review `Modules/`, `Scripts/`, and `powershell.config.json` before deciding whether they belong in the public profile repository. Do not commit secrets, credentials, tokens, certificates, private configuration, or command history.

## 5. Five-minute daily quick start

| Task | Command |
|---|---|
| Show all profile help | `phelp` |
| Search/list aliases | `palias` |
| Edit profile | `eprof` |
| Reload profile after PowerShell-only changes | `rprof` |
| Go to profile repository | `pdir` |
| Open predictor project in VS Code | `predproj` |
| Build predictor normally | `predbuild` |
| Safely rebuild a loaded predictor DLL | `predrebuild` |
| Check predictor/profile health | `predtest` |
| Show prediction state | `predstate` |
| Show Git status | `gst` |
| Show recent Git commits | `glog 2` |
| Back up a file | `backup-file .\file.txt` |
| Back up a directory | `backup-dir .\folder` |
| ZIP a file | `zip-file .\file.txt` |
| ZIP a directory | `zip-dir .\folder` |
| Extract a ZIP safely | `unzip .\archive.zip` |
| Preview CPRS TEST deployment | `cprs-test-deploy -WhatIf` |
| Preview CE deployment | `cprs-ce-deploy preview feature local` |

## 6. Complete alias reference

These are the short commands intended for interactive use. The **Command/Function** column shows what each alias invokes. All aliases are centrally defined through `Get-ProfileAliasDefinition` and registered by `Register-ProfileAlias`.

### Profile

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `phelp` | `Show-ProfileHelp` | Display the profile help menu | `phelp CPRS` |
| `palias` | `Get-ProfileAlias` | List or search profile aliases | `palias -Category Utilities` |
| `ppath` | `Get-ProfilePath` | Display the active profile path | `ppath` |
| `eprof` | `Edit-Profile` | Open the profile in VS Code | `eprof` |
| `rprof` | `Import-Profile` | Reload the profile in the current shell | `rprof` |

### ProfileDev

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `pdir` | `Set-PowerShellProfileDirectory` | Open the PowerShell profile development directory | `pdir` |
| `predcd` | `Set-ProfileAliasPredictorDirectory` | Open the ProfileAliasPredictor project directory | `predcd` |
| `predcmd` | `Open-ProfileAliasPredictorCommandPrompt` | Open Command Prompt in the predictor project | `predcmd` |
| `predbuild` | `Build-ProfileAliasPredictor` | Build ProfileAliasPredictor in Release mode | `predbuild` |
| `predkill` | `Stop-ProfilePowerShellProcesses` | Stop all PowerShell 7 processes to release the predictor DLL | `predkill` |
| `predrebuild` | `Invoke-ProfileAliasPredictorRebuild` | Stop PowerShell and rebuild ProfileAliasPredictor in Release mode | `predrebuild` |
| `predinfo` | `Get-ProfileAliasPredictorInfo` | Display ProfileAliasPredictor project and build information | `predinfo` |
| `predtest` | `Test-ProfileAliasPredictor` | Verify the PowerShell profile and predictor configuration | `predtest` |
| `predproj` | `Open-ProfileAliasPredictorProject` | Open the ProfileAliasPredictor project in VS Code | `predproj` |

### History

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `hpath` | `Get-CommandHistoryPath` | Display the persistent history-file path | `hpath` |
| `hsearch` | `Search-CommandHistory` | Search persistent PowerShell command history | `hsearch 'git log'` |
| `ehist` | `Edit-CommandHistory` | Open persistent command history in VS Code | `ehist` |

### Prediction

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `histon` | `Enable-HistoryPrediction` | Enable history-based command suggestions | `histon` |
| `histoff` | `Disable-HistoryPrediction` | Hide history suggestions without deleting history | `histoff` |
| `predon` | `Enable-PluginPrediction` | Enable ProfileAliases and other predictor plug-ins | `predon` |
| `predoff` | `Disable-PluginPrediction` | Disable predictor plug-ins | `predoff` |
| `predstate` | `Get-ProfilePredictionStatus` | Display the current prediction configuration | `predstate` |

### Utilities

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `c` | `Clear-Host` | Clear the PowerShell console | `c` |
| `which` | `Get-Command` | Find a command, alias, function, or executable | `which git` |
| `la` | `Get-AllChildItem` | List all files and directories, including hidden items | `la` |
| `up` | `Set-ParentLocation` | Move up one directory | `up` |
| `up2` | `Set-GrandparentLocation` | Move up two directories | `up2` |
| `home` | `Set-HomeLocation` | Open the current user home directory | `home` |
| `here` | `Open-CurrentDirectory` | Open the current directory in File Explorer | `here` |
| `codehere` | `Open-CurrentDirectoryInCode` | Open the current directory in Visual Studio Code | `codehere` |
| `path` | `Get-PathEntry` | Display PATH entries one per line | `path` |
| `admin` | `Start-ElevatedPowerShell` | Open an elevated PowerShell 7 session | `admin` |
| `groot` | `Set-GitRepositoryRoot` | Move to the root of the current Git repository | `groot` |
| `ltr` | `Get-LongTimeListing` | Detailed listing sorted oldest to newest like ls -ltr | `ltr` |
| `dtree` | `Show-DirectoryTree` | Display a directory tree; use -Files to include files | `dtree -Files` |
| `backup-file` | `New-FileBackup` | Create a verified timestamped backup of a file | `backup-file .\report.docx` |
| `backup-dir` | `New-DirectoryBackup` | Create a verified timestamped backup of a directory | `backup-dir .\Project` |
| `zip-file` | `Compress-FileArchive` | Create and verify a ZIP archive containing one file | `zip-file .\report.docx` |
| `zip-dir` | `Compress-DirectoryArchive` | Create and verify a ZIP archive of a directory | `zip-dir .\Project` |
| `unzip` | `Expand-DirectoryArchive` | Extract a ZIP using automatic destination selection | `unzip .\Project.zip -WhatIf` |

### CPRS

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `cprs-build` | `Build-CprsRelease` | Build the CPRS client solution in Release mode | `cprs-build` |
| `cprs-test-deploy` | `Deploy-CprsTestClient` | Build or deploy the CPRS client to V:\TEST\EXE | `cprs-test-deploy -WhatIf` |
| `cprs-prod-deploy` | `Deploy-CprsProductionClient` | Promote a verified CPRS TEST build to production | `cprs-prod-deploy -WhatIf` |
| `cprs-ce-deploy` | `Invoke-CprsDeployment` | Preview or deploy CE Residential Improvements between CPRS environments | `cprs-ce-deploy preview feature local` |

### Development

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `cdev` | `Set-DevelopmentRoot` | Open C:\Development-CPRS | `cdev` |
| `csas` | `Set-SasProgramsRepository` | Open the local cprs-sasprogs repository | `csas` |
| `cbatch` | `Set-BatchRepository` | Open the local cprs-batch repository | `cbatch` |
| `fileops` | `Open-FileOpsWorkspace` | Open the FileOps Manager VS Code workspace | `fileops` |

### Production

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `pbatch` | `Set-ProductionBatchDirectory` | Open V:\PROD\BATCH | `pbatch` |
| `psas` | `Set-ProductionSasProgramsDirectory` | Open V:\PROD\SASPRGS | `psas` |
| `plogs` | `Set-ProductionSasLogsDirectory` | Open V:\PROD\LOGS\SASLOGS | `plogs` |

### Git

| Alias | Command/Function | Purpose | Typical use |
|---|---|---|---|
| `gst` | `Get-GitRepositoryStatus` | Show the current branch and repository status | `gst` |
| `glog` | `Get-GitRecentCommit` | Show recent commits, dates, and changed files | `glog 2` |
| `gfile` | `Get-GitChangedFile` | Show staged, unstaged, and untracked files | `gfile` |

## 7. Backup, ZIP, and unzip workflows

This command family is designed so the normal case is short while the underlying functions still provide verification and preview behavior.

### 7.1 `backup-file` — verified file backup

```powershell
backup-file .\MARTS_Knowledge_Transfer.docx
backup-file .\MARTS_Knowledge_Transfer.docx -Destination C:\Backups
backup-file .\MARTS_Knowledge_Transfer.docx -WhatIf

```

Without `-Destination`, a `Backups` directory is created beside the source file. A source such as `C:\Work\report.txt` becomes a timestamped file such as `C:\Work\Backups\report_20260815-100506409.txt`. The function verifies both file size and SHA256. `-WhatIf` prints the planned source and destination without copying.

**Important naming rule:** the user-facing alias is `backup-file`, while the underlying function is `New-FileBackup`. They intentionally have different names because PowerShell command names are case-insensitive; an alias named `backup-file` pointing to a function named `Backup-File` would create a self-referential alias collision.

### 7.2 `backup-dir` — verified directory backup

```powershell
backup-dir .\Project
backup-dir .\Project -Destination D:\Backups
backup-dir .\Project -WhatIf
backup-dir .\Project -SkipHashVerification

```

The directory backup captures a source manifest before copying. The default backup root is `Backups` under the source parent, with the source folder name and timestamp appended. Relative file paths and sizes are checked, and SHA256 verification is performed by default. `-SkipHashVerification` is available when a large tree makes full hashing unnecessarily expensive.

### 7.3 `zip-file` — one file into a verified ZIP

```powershell
zip-file .\report.docx
zip-file .\report.docx -Destination C:\Archives
zip-file .\report.docx -Destination C:\Archives\report.zip
zip-file .\report.docx -WhatIf

```

By default the archive goes under an `Archives` directory beside the source file and receives a timestamped name. A custom destination can be either a directory or a full `.zip` path. The archive is verified against the source file and the completed ZIP receives its own SHA256.

### 7.4 `zip-dir` — complete directory into a verified ZIP

```powershell
zip-dir .\Project
zip-dir .\Project -Destination D:\Archives
zip-dir .\Project -WhatIf

```

The directory itself is preserved as the top-level folder in the ZIP. This is deliberate: it makes extracted archives self-contained. Verification checks archived file count and total uncompressed bytes. The function also prevents placing the output ZIP inside the directory being compressed, avoiding recursive/self-inclusion problems.

### 7.5 `unzip` — smart extraction

```powershell
unzip .\Project.zip
unzip .\Project.zip -Destination C:\Temp\Project
unzip .\Project.zip -WhatIf
unzip .\Project.zip -Force

```

When `-Destination` is omitted, the function inspects the ZIP first:

- If the ZIP already has **exactly one top-level directory** and no loose root files, it extracts beside the ZIP so it does not create `Project\Project\...`.
- If the ZIP contains loose files or multiple top-level items, it creates a directory named after the ZIP and extracts into it so files are not dumped loosely into the current directory.
- If `-Destination` is supplied, automatic destination selection is disabled and the requested directory is used.
- If destination content already exists, use `-Force` only when replacement is intentional.
- Use `-WhatIf` whenever you want to see the decision before extraction.

## 8. CPRS build and deployment workflows

The CPRS commands are intentionally separated by purpose: client build, TEST deployment, production promotion, and CE/Residential Improvements source-code deployment.

### 8.1 `cprs-build`

Builds `C:\Development-CPRS\Cprs\cprs-client.sln` in Release mode using the full Visual Studio MSBuild executable and the `win-x86` runtime settings used by the profile.

```powershell
cprs-build

```

### 8.2 `cprs-test-deploy`

Default workflow: build CPRS, archive the current `V:\TEST\EXE\Current` build under `V:\TEST\EXE\Builds`, then replace `Current`. `-SkipBuild` uses the existing local Release output. `-Folder <folder>` deploys to a named TEST folder without touching `Current` or its archive history. `-WhatIf` is a true preview and does not build or change files.

```powershell
cprs-test-deploy
cprs-test-deploy -SkipBuild
cprs-test-deploy -Folder CR2249
cprs-test-deploy -Folder CR2249 -SkipBuild
cprs-test-deploy -WhatIf
cprs-test-deploy -Folder CR2249 -WhatIf

```

### 8.3 `cprs-prod-deploy`

Promotes a verified build from `V:\TEST\EXE` to the live production application `V:\PROD\EXE\CPRS II`. The production root is `V:\PROD\EXE`; archived production builds are stored under `V:\PROD\EXE\Builds`. The live application directory itself is **not** the archive root.

The default source is `V:\TEST\EXE\Current`. `-Source <folder>` resolves below `V:\TEST\EXE`; a complete path under that TEST root is also accepted. Before replacement, the live production application is archived and verified, the TEST source is staged and verified, and production deployment uses explicit confirmation plus rollback protection. Preview with `-WhatIf` before a real promotion.

```powershell
cprs-prod-deploy -WhatIf
cprs-prod-deploy
cprs-prod-deploy -Source CR2249 -WhatIf
cprs-prod-deploy -Source CR2249
cprs-prod-deploy -Source 'V:\TEST\EXE\CR2249' -WhatIf

```

### 8.4 `cprs-ce-deploy`

Wraps the canonical Residential Improvements deployment script and supports the following routes: FEATURE→LOCAL/DEV/TEST/PROD, LOCAL→DEV/TEST/PROD, DEV→TEST/PROD, and TEST→PROD. Use `preview` first; `deploy` performs the actual deployment. Configuration is preserved unless `-Config` is specified. `-All` or `-DeploymentMode ALL` deploys all eligible files; otherwise the configured/default UPDATED behavior is used. Workload can be `COMPONENT_ESTIMATION`, `FORECASTING`, or `ALL`.

```powershell
cprs-ce-deploy preview feature local
cprs-ce-deploy deploy local dev
cprs-ce-deploy preview dev test -All
cprs-ce-deploy deploy test prod -Config
cprs-ce-deploy preview dev test -Workload ALL
cprs-ce-deploy deploy dev test -Workload COMPONENT_ESTIMATION

```

## 9. ProfileAliasPredictor project

`ProfileAliasPredictor` implements PowerShell `ICommandPredictor`. Its definition array contains user-facing command strings and descriptions. When the typed input is non-empty, matching definitions whose command begins with the current input are returned as suggestions. Matching is case-insensitive and supports multi-word prefixes, which is why typing part of `cprs-test-deploy -Fol` can surface a complete command template.

### Project files

| Item | Expected location | Purpose |
|---|---|---|
| C# source | `Projects\ProfileAliasPredictor\ProfileAliasPredictor.cs` | Predictor implementation and suggestion definitions |
| Project file | `Projects\ProfileAliasPredictor\ProfileAliasPredictor.csproj` | .NET build configuration/dependencies |
| Release DLL | `Projects\ProfileAliasPredictor\bin\Release\net10.0\ProfileAliasPredictor.dll` | DLL imported by the profile |

### Normal development commands

| Command | Purpose |
|---|---|
| `predproj` | Open the predictor project in VS Code |
| `predcd` | Change to the predictor project directory |
| `predcmd` | Open Command Prompt in the predictor directory |
| `predbuild` | Normal Release build |
| `predkill` | Close PowerShell 7 processes to release a locked DLL |
| `predrebuild` | Safe kill/build/reopen workflow after C# changes |
| `predinfo` | Show source/project/DLL locations and DLL state |
| `predtest` | Health check for DLL, module, registration, PSReadLine, and aliases |

Use `predrebuild` rather than repeatedly calling `dotnet build` when the current PowerShell process has already imported the DLL, because the loaded DLL can be locked.

## 10. Prediction and PSReadLine behavior

The intended normal state combines history predictions with plug-in predictions. `histoff` hides history suggestions without deleting history; `predoff` disables plug-in suggestions without disabling history. `predstate` reports the resulting configuration.

| Command | Result | Deletes history? |
|---|---|---|
| `histon` | Enable history predictions | No |
| `histoff` | Hide history predictions | No |
| `predon` | Enable registered predictor plug-ins | No |
| `predoff` | Disable predictor plug-ins | No |
| `predstate` | Display current prediction state | No |

The healthy target is normally `PredictionSource = HistoryAndPlugin` and `PredictionView = ListView`. The profile also configures useful PSReadLine keys such as Up/Down history search, `Ctrl+Space` completion, Right Arrow prediction acceptance, `F2` prediction-view switching, and `Ctrl+D` character deletion/exit behavior.

## 11. Complete PowerShell function reference

This section documents every custom global function in the current shared profile baseline and the finalized backup/archive additions. Functions without a user-facing alias are internal/support functions but are included because they are part of the profile API and maintenance surface.

### Internal helpers

#### `Set-ProfileLocation`

**Purpose:** Changes location after verifying that the target directory exists.

##### Parameters for `Set-ProfileLocation`

| Parameter | Meaning |
|---|---|
| `-Path` | Directory to open. |

#### `Test-GitRepository`

**Purpose:** Tests whether the current directory is inside a Git working tree.

### Profile management

#### `Get-ProfilePath` — alias: `ppath`

**Purpose:** Displays the main profile path or all standard profile paths.

##### Parameters for `Get-ProfilePath`

| Parameter | Meaning |
|---|---|
| `-All` | Displays all four standard PowerShell profile locations. |

##### Examples for `Get-ProfilePath`

```powershell
Get-ProfilePath

```

```powershell
Get-ProfilePath -All

```

#### `Edit-Profile` — alias: `eprof`

**Purpose:** Opens the main PowerShell profile for editing.

##### Examples for `Edit-Profile`

```powershell
Edit-Profile

```

#### `Import-Profile` — alias: `rprof`

**Purpose:** Reloads the main profile in the current PowerShell session.

Dot-sources the CurrentUserAllHosts profile. Profile functions and aliases are registered in global scope so they remain available after this function finishes.

##### Examples for `Import-Profile`

```powershell
Import-Profile

```

```powershell
rprof

```

### PowerShell profile development

#### `Set-PowerShellProfileDirectory` — alias: `pdir`

**Purpose:** Opens the PowerShell profile development directory.

Changes the current directory to the folder containing profile.ps1 and the ProfileAliasPredictor project.

##### Examples for `Set-PowerShellProfileDirectory`

```powershell
pdir

```

#### `Set-ProfileAliasPredictorDirectory` — alias: `predcd`

**Purpose:** Opens the ProfileAliasPredictor project directory.

Changes the current directory to the .NET project used to build predictive IntelliSense for PowerShell profile aliases.

##### Examples for `Set-ProfileAliasPredictorDirectory`

```powershell
predcd

```

#### `Open-ProfileAliasPredictorCommandPrompt` — alias: `predcmd`

**Purpose:** Opens Command Prompt in the ProfileAliasPredictor project directory.

Starts cmd.exe and changes directly to the ProfileAliasPredictor project directory. Useful for rebuilding the predictor DLL when PowerShell processes need to be closed first.

##### Examples for `Open-ProfileAliasPredictorCommandPrompt`

```powershell
predcmd

```

#### `Build-ProfileAliasPredictor` — alias: `predbuild`

**Purpose:** Builds the ProfileAliasPredictor .NET project in Release mode.

Runs dotnet build for ProfileAliasPredictor.csproj using the Release configuration. If the predictor DLL is currently loaded by PowerShell, the build may fail because the DLL is locked. Use predrebuild for the complete kill-and-rebuild workflow.

##### Examples for `Build-ProfileAliasPredictor`

```powershell
predbuild

```

#### `Stop-ProfilePowerShellProcesses` — alias: `predkill`

**Purpose:** Stops all PowerShell 7 processes.

Starts a separate Command Prompt process that terminates all pwsh.exe processes. This is primarily used to release the ProfileAliasPredictor DLL before rebuilding the .NET project. WARNING: This closes all PowerShell 7 windows, including the current session. Save any work before running this command.

##### Parameters for `Stop-ProfilePowerShellProcesses`

| Parameter | Meaning |
|---|---|
| `-Force` | Skips the confirmation prompt. |

##### Examples for `Stop-ProfilePowerShellProcesses`

```powershell
predkill

```

```powershell
predkill -Force

```

#### `Invoke-ProfileAliasPredictorRebuild` — alias: `predrebuild`

**Purpose:** Stops PowerShell 7 and rebuilds ProfileAliasPredictor.

Performs the complete ProfileAliasPredictor rebuild workflow: 1. Creates a temporary CMD rebuild script. 2. Opens Command Prompt. 3. Stops all pwsh.exe processes to release the predictor DLL. 4. Changes to the ProfileAliasPredictor project directory. 5. Builds ProfileAliasPredictor.csproj in Release mode. 6. Leaves Command Prompt open so the build result can be reviewed. WARNING: All PowerShell 7 windows, including the current session, will close.

##### Parameters for `Invoke-ProfileAliasPredictorRebuild`

| Parameter | Meaning |
|---|---|
| `-Force` | Skips the confirmation prompt. |

##### Examples for `Invoke-ProfileAliasPredictorRebuild`

```powershell
predrebuild

```

```powershell
predrebuild -Force

```

#### `Get-ProfileAliasPredictorInfo` — alias: `predinfo`

**Purpose:** Displays ProfileAliasPredictor project and build information.

##### Examples for `Get-ProfileAliasPredictorInfo`

```powershell
predinfo

```

#### `Test-ProfileAliasPredictor` — alias: `predtest`

**Purpose:** Verifies the PowerShell profile and ProfileAliasPredictor configuration.

Checks the predictor DLL, module, registered CommandPredictor, PSReadLine prediction settings, and profile aliases.

##### Examples for `Test-ProfileAliasPredictor`

```powershell
predtest

```

### Command history

#### `Get-CommandHistoryPath` — alias: `hpath`

**Purpose:** Displays the persistent PSReadLine history-file path.

##### Examples for `Get-CommandHistoryPath`

```powershell
Get-CommandHistoryPath

```

#### `Search-CommandHistory` — alias: `hsearch`

**Purpose:** Searches the persistent PSReadLine command history.

##### Parameters for `Search-CommandHistory`

| Parameter | Meaning |
|---|---|
| `-Pattern` | Text to locate in command history. |
| `-Regex` | Treats Pattern as a regular expression. By default, Pattern is treated as literal text. |

##### Examples for `Search-CommandHistory`

```powershell
Search-CommandHistory -Pattern 'git log'

```

```powershell
hsearch 'centurion'

```

```powershell
Search-CommandHistory -Pattern '^git ' -Regex

```

#### `Edit-CommandHistory` — alias: `ehist`

**Purpose:** Opens the persistent PSReadLine history file.

##### Examples for `Edit-CommandHistory`

```powershell
Edit-CommandHistory

```

### Development navigation

#### `Set-DevelopmentRoot` — alias: `cdev`

**Purpose:** Opens the main CPRS development directory.

#### `Set-SasProgramsRepository` — alias: `csas`

**Purpose:** Opens the local CPRS SAS programs repository.

#### `Set-BatchRepository` — alias: `cbatch`

**Purpose:** Opens the local CPRS batch repository.

#### `Open-FileOpsWorkspace` — alias: `fileops`

**Purpose:** Opens the FileOps Manager VS Code workspace.

##### Examples for `Open-FileOpsWorkspace`

```powershell
Open-FileOpsWorkspace

```

```powershell
fileops

```

#### `Open-ProfileAliasPredictorProject` — alias: `predproj`

**Purpose:** Opens the ProfileAliasPredictor project in Visual Studio Code.

##### Examples for `Open-ProfileAliasPredictorProject`

```powershell
Open-ProfileAliasPredictorProject

```

```powershell
predproj

```

### Production navigation

#### `Set-ProductionBatchDirectory` — alias: `pbatch`

**Purpose:** Opens the production batch directory.

#### `Set-ProductionSasProgramsDirectory` — alias: `psas`

**Purpose:** Opens the production SAS programs directory.

#### `Set-ProductionSasLogsDirectory` — alias: `plogs`

**Purpose:** Opens the production SAS logs directory.

### Git helpers

#### `Get-GitRepositoryStatus` — alias: `gst`

**Purpose:** Displays the current Git branch and working-tree status.

##### Examples for `Get-GitRepositoryStatus`

```powershell
Get-GitRepositoryStatus

```

```powershell
gst

```

#### `Get-GitRecentCommit` — alias: `glog`

**Purpose:** Displays recent commits with dates and changed files.

##### Parameters for `Get-GitRecentCommit`

| Parameter | Meaning |
|---|---|
| `-Count` | Number of commits to display. The default is 5. |

##### Examples for `Get-GitRecentCommit`

```powershell
Get-GitRecentCommit

```

```powershell
Get-GitRecentCommit -Count 2

```

```powershell
glog 2

```

#### `Get-GitChangedFile` — alias: `gfile`

**Purpose:** Displays staged, unstaged, and untracked files.

##### Examples for `Get-GitChangedFile`

```powershell
Get-GitChangedFile

```

```powershell
gfile

```

### CPRS build and deployment

#### `Build-CprsRelease` — alias: `cprs-build`

**Purpose:** Builds the CPRS client solution in Release mode.

Locates the full Visual Studio MSBuild executable and builds the CPRS .NET Framework solution in Release mode for the win-x86 runtime.

##### Examples for `Build-CprsRelease`

```powershell
Build-CprsRelease

```

```powershell
cprs-build

```

#### `Deploy-CprsTestClient` — alias: `cprs-test-deploy`

**Purpose:** Builds and/or deploys the CPRS client to V:\TEST\EXE.

Deploys the CPRS Release build from: C:\Development-CPRS\Cprs\UI\bin\Release DEFAULT: Builds CPRS. Archives the existing V:\TEST\EXE\Current build. Replaces V:\TEST\EXE\Current. -SkipBuild: Uses the existing local Release build. Archives the existing Current build. Replaces Current. -Folder \<folder\>: Builds CPRS. Replaces V:\TEST\EXE\\<folder\>. Does NOT modify Current. Does NOT create a Current archive. -Folder \<folder\> -SkipBuild: Uses the existing Release build. Replaces V:\TEST\EXE\\<folder\>. Does NOT modify Current. -WhatIf: Preview only. Does NOT build CPRS. Does NOT archive, remove, create, or copy files.

##### Parameters for `Deploy-CprsTestClient`

| Parameter | Meaning |
|---|---|
| `-SkipBuild` | Uses the existing CPRS Release build instead of rebuilding CPRS. |
| `-Folder` | Deploys to a named folder directly below V:\TEST\EXE. Example: -Folder \<folder\> Destination: V:\TEST\EXE\\<folder\> When Folder is supplied, Current and Builds are not modified. |

##### Examples for `Deploy-CprsTestClient`

```powershell
cprs-test-deploy

Build CPRS, archive the existing Current build, and deploy the new
build to V:\TEST\EXE\Current.

```

```powershell
cprs-test-deploy -SkipBuild

Use the existing Release build, archive Current, and replace Current.

```

```powershell
cprs-test-deploy -Folder <folder>

Build CPRS and replace V:\TEST\EXE\<folder>.
Current is not touched.

```

```powershell
cprs-test-deploy -Folder <folder> -SkipBuild

Use the existing Release build and replace
V:\TEST\EXE\<folder>.

```

```powershell
cprs-test-deploy -WhatIf

Preview a normal Current deployment without building or copying.

```

```powershell
cprs-test-deploy -Folder <folder> -WhatIf

Preview deployment to the CR2249 folder without making changes.

```

#### `Deploy-CprsProductionClient` — alias: `cprs-prod-deploy`

**Purpose:** Promotes a verified CPRS TEST build to the CPRS production directory.

Promotes an existing CPRS client build from V:\TEST\EXE to: V:\PROD\EXE\CPRS II The production root is: V:\PROD\EXE Production build archives are stored separately under: V:\PROD\EXE\Builds The default TEST source is: V:\TEST\EXE\Current A TEST folder name can also be supplied: cprs-prod-deploy -Source \<folder\> which resolves to: V:\TEST\EXE\\<folder\> A complete TEST path is also accepted: cprs-prod-deploy -Source 'V:\TEST\EXE\\<folder\>' Before the live production application is replaced, the complete contents of V:\PROD\EXE\CPRS II are copied to a timestamped archive under V:\PROD\EXE\Builds and verified. The selected TEST build is also staged and verified before the production application is touched. A production deployment requires two explicit confirmations: 1. Type REVIEWED 2. Type DEPLOY PROD If the deployment fails after the live production replacement has started, the function attempts to restore the archived production build automatically.

##### Parameters for `Deploy-CprsProductionClient`

| Parameter | Meaning |
|---|---|
| `-Source` | Specifies the TEST build to promote. If omitted: V:\TEST\EXE\Current If a folder name is supplied: \<folder\> it resolves to: V:\TEST\EXE\\<folder\> A complete directory under V:\TEST\EXE can also be supplied: V:\TEST\EXE\\<folder\> For safety, production promotion is restricted to directories underneath V:\TEST\EXE. |

##### Examples for `Deploy-CprsProductionClient`

```powershell
cprs-prod-deploy

Promotes V:\TEST\EXE\Current to:

V:\PROD\EXE\CPRS II

```

```powershell
cprs-prod-deploy -Source <folder>

Promotes:

V:\TEST\EXE\<folder>

to:

V:\PROD\EXE\CPRS II

```

```powershell
cprs-prod-deploy -Source 'V:\TEST\EXE\<folder>'

Uses the supplied TEST path directly.

```

```powershell
cprs-prod-deploy -Folder <folder>

-Folder is an alias for -Source.

```

```powershell
cprs-prod-deploy -WhatIf

Displays the complete production deployment plan for TEST Current
without making changes.

```

```powershell
cprs-prod-deploy -Source <folder> -WhatIf

Displays the production deployment plan for a specific TEST build
without making changes.

```

#### `Invoke-CprsDeployment` — alias: `cprs-ce-deploy`

**Purpose:** Previews or deploys Residential Improvements between CPRS environments.

Provides a simple wrapper around the canonical Residential Improvements deployment script. Valid routes: FEATURE -> LOCAL FEATURE -> DEV FEATURE -> TEST FEATURE -> PROD LOCAL   -> DEV LOCAL   -> TEST LOCAL   -> PROD DEV     -> TEST DEV     -> PROD TEST    -> PROD Preview mode passes -WhatIf to the deployment script. Deploy mode performs the actual deployment and preserves the confirmation protection implemented by deploy.ps1. Configuration files are not deployed unless -Config is specified. -Force is never enabled automatically.

##### Parameters for `Invoke-CprsDeployment`

| Parameter | Meaning |
|---|---|
| `-Action` | Specifies whether to preview or perform the deployment. PREVIEW Runs the deployment script with -WhatIf and makes no changes. DEPLOY Performs the actual deployment. |
| `-Source` | Specifies the source environment. Valid values: FEATURE LOCAL DEV TEST |
| `-Destination` | Specifies the destination environment. Valid values: LOCAL DEV TEST PROD The source and destination must form one of the supported deployment routes. |
| `-Config` | Deploys configuration files. By default, DeployConfig is NO and existing destination configuration files are preserved. When -Config is specified, DeployConfig is set to YES. |
| `-All` | Deploys all files for the selected workload instead of only updated files. This is equivalent to: -DeploymentMode ALL |
| `-Workload` | Specifies which Residential Improvements workload to deploy. Valid values: COMPONENT_ESTIMATION FORECASTING ALL If omitted, deploy.ps1 uses its configured default workload. |
| `-DeploymentMode` | Controls which files are selected for deployment. UPDATED Deploys only new and changed files. ALL Deploys all eligible files for the selected workload. |
| `-Force` | Passes -Force to deploy.ps1 and bypasses its interactive deployment confirmation. This option is never enabled automatically and should be used only when confirmation bypass is intentional. |

##### Examples for `Invoke-CprsDeployment`

```powershell
cprs-ce-deploy preview feature local

```

```powershell
cprs-ce-deploy deploy local dev

```

```powershell
cprs-ce-deploy preview dev test -All

```

```powershell
cprs-ce-deploy deploy test prod -Config

```

```powershell
cprs-ce-deploy preview dev test -Workload ALL

```

```powershell
cprs-ce-deploy deploy dev test -Workload COMPONENT_ESTIMATION

```

```powershell
cprs-ce-deploy preview local dev -DeploymentMode ALL

```

### General utilities

#### `Get-AllChildItem` — alias: `la`

**Purpose:** Lists all files and directories, including hidden items.

##### Examples for `Get-AllChildItem`

```powershell
la

```

```powershell
la C:\Development-CPRS

```

#### `Set-ParentLocation` — alias: `up`

**Purpose:** Moves up one directory.

##### Examples for `Set-ParentLocation`

```powershell
up

```

#### `Set-GrandparentLocation` — alias: `up2`

**Purpose:** Moves up two directories.

##### Examples for `Set-GrandparentLocation`

```powershell
up2

```

#### `Set-HomeLocation` — alias: `home`

**Purpose:** Opens the current user's home directory.

##### Examples for `Set-HomeLocation`

```powershell
home

```

#### `Open-CurrentDirectory` — alias: `here`

**Purpose:** Opens the current directory in Windows File Explorer.

##### Examples for `Open-CurrentDirectory`

```powershell
here

```

#### `Open-CurrentDirectoryInCode` — alias: `codehere`

**Purpose:** Opens the current directory in Visual Studio Code.

##### Examples for `Open-CurrentDirectoryInCode`

```powershell
codehere

```

#### `Get-PathEntry` — alias: `path`

**Purpose:** Displays PATH entries one per line.

##### Examples for `Get-PathEntry`

```powershell
path

```

#### `Start-ElevatedPowerShell` — alias: `admin`

**Purpose:** Opens a new elevated PowerShell 7 session.

##### Examples for `Start-ElevatedPowerShell`

```powershell
admin

```

#### `Set-GitRepositoryRoot` — alias: `groot`

**Purpose:** Moves to the root directory of the current Git repository.

##### Examples for `Set-GitRepositoryRoot`

```powershell
groot

```

#### `Get-LongTimeListing` — alias: `ltr`

**Purpose:** Displays a detailed directory listing sorted by modification time.

PowerShell equivalent of: ls -ltr Displays the oldest modified items first and the newest items last.

##### Parameters for `Get-LongTimeListing`

| Parameter | Meaning |
|---|---|
| `-Path` | Directory to list. Defaults to the current directory. |

##### Examples for `Get-LongTimeListing`

```powershell
ltr

```

```powershell
ltr C:\Development-CPRS

```

#### `Show-DirectoryTree` — alias: `dtree`

**Purpose:** Displays a directory tree.

Displays the folder hierarchy beneath a directory using the Windows tree command. By default only directories are displayed. Use -Files to include files.

##### Parameters for `Show-DirectoryTree`

| Parameter | Meaning |
|---|---|
| `-Path` | Directory to display. Defaults to the current directory. |
| `-Files` | Includes files in the tree. |

##### Examples for `Show-DirectoryTree`

```powershell
dtree

```

```powershell
dtree C:\Development-CPRS

```

```powershell
dtree -Files

```

```powershell
dtree C:\Development-CPRS -Files

```

### Backup and archive utilities

#### `New-FileBackup` — alias: `backup-file`

**Purpose:** Creates a verified, timestamped backup of a file.

Copies a single file to a backup directory using a timestamped name. The default destination is a Backups directory beside the source file. The copy is verified by file size and SHA256 hash. Supports -WhatIf through ShouldProcess.

##### Parameters for `New-FileBackup`

| Parameter | Meaning |
|---|---|
| `-Path` | File to back up. Mandatory; position 0. |
| `-Destination` | Optional backup directory. If omitted, a Backups directory is created beside the source file. |

##### Examples for `New-FileBackup`

```powershell
backup-file .\profile.ps1

```

```powershell
backup-file .\profile.ps1 -Destination C:\Backups

```

```powershell
backup-file .\profile.ps1 -WhatIf

```

#### `New-DirectoryBackup` — alias: `backup-dir`

**Purpose:** Creates a verified, timestamped backup of a complete directory.

Copies a directory tree to a timestamped backup directory. By default the backup is placed under a Backups directory in the source directory parent. A source manifest is captured before the copy. Relative paths and file sizes are verified and SHA256 verification is performed by default. Safety checks reject backing up a filesystem root and prevent choosing a destination inside the source tree. Supports -WhatIf.

##### Parameters for `New-DirectoryBackup`

| Parameter | Meaning |
|---|---|
| `-Path` | Directory to back up. Mandatory; position 0. |
| `-Destination` | Optional backup root. If omitted, uses \<source-parent\>\Backups. |
| `-SkipHashVerification` | Skips per-file SHA256 verification while still checking the copied file manifest and file sizes. |

##### Examples for `New-DirectoryBackup`

```powershell
backup-dir .\Project

```

```powershell
backup-dir .\Project -Destination D:\Backups

```

```powershell
backup-dir .\Project -WhatIf

```

```powershell
backup-dir .\Project -SkipHashVerification

```

#### `Compress-FileArchive` — alias: `zip-file`

**Purpose:** Creates and verifies a ZIP archive containing one file.

Creates a timestamped ZIP archive for a single file. The default output is an Archives directory beside the source file. The destination may be a directory or a complete .zip path. Verification checks the ZIP entry, uncompressed size and SHA256 of the archived file and also calculates the final ZIP SHA256. Supports -Force and -WhatIf.

##### Parameters for `Compress-FileArchive`

| Parameter | Meaning |
|---|---|
| `-Path` | File to compress. Mandatory; position 0. |
| `-Destination` | Optional destination directory or complete .zip file path. |
| `-Force` | Allows replacement when the requested archive path already exists. |

##### Examples for `Compress-FileArchive`

```powershell
zip-file .\report.docx

```

```powershell
zip-file .\report.docx -Destination C:\Archives

```

```powershell
zip-file .\report.docx -Destination C:\Archives\report.zip

```

```powershell
zip-file .\report.docx -WhatIf

```

#### `Compress-DirectoryArchive` — alias: `zip-dir`

**Purpose:** Creates and verifies a ZIP archive of a directory.

Creates a ZIP archive of an entire directory while preserving the source folder as the top-level folder in the archive. By default the archive is written to an Archives directory under the source directory parent. Verification checks the archived file count and total uncompressed bytes and calculates the final ZIP SHA256. The destination is not allowed to be inside the source directory. Supports -Force and -WhatIf.

##### Parameters for `Compress-DirectoryArchive`

| Parameter | Meaning |
|---|---|
| `-Path` | Directory to compress. Mandatory; position 0. |
| `-Destination` | Optional destination directory or complete .zip file path. |
| `-Force` | Allows replacement when the requested archive path already exists. |

##### Examples for `Compress-DirectoryArchive`

```powershell
zip-dir .\Project

```

```powershell
zip-dir .\Project -Destination D:\Archives

```

```powershell
zip-dir .\Project -WhatIf

```

#### `Expand-DirectoryArchive` — alias: `unzip`

**Purpose:** Extracts a ZIP archive using a safe automatic destination.

Inspects ZIP contents before extraction. If the ZIP already contains exactly one top-level directory and no loose root files, it extracts beside the ZIP without creating a second wrapper folder. If the ZIP contains loose files or multiple top-level items, it creates a folder named after the ZIP and extracts into that folder. -Destination disables automatic destination selection and extracts exactly to the requested directory. Existing destination content requires -Force. Supports -WhatIf.

##### Parameters for `Expand-DirectoryArchive`

| Parameter | Meaning |
|---|---|
| `-Path` | ZIP archive to extract. Mandatory; position 0. |
| `-Destination` | Optional directory to extract into. When omitted, smart destination selection is used. |
| `-Force` | Allows extraction into an existing destination and replacement of existing files. |

##### Examples for `Expand-DirectoryArchive`

```powershell
unzip .\Project.zip

```

```powershell
unzip .\Project.zip -Destination C:\Temp\Project

```

```powershell
unzip .\Project.zip -WhatIf

```

```powershell
unzip .\Project.zip -Force

```

### Alias registry and help menu

#### `Get-ProfileAliasDefinition`

**Purpose:** Returns the aliases managed by this profile.

### Prediction controls

#### `Get-ProfilePredictionStatus` — alias: `predstate`

**Purpose:** Displays the current history and plug-in prediction status.

##### Examples for `Get-ProfilePredictionStatus`

```powershell
Get-ProfilePredictionStatus

```

```powershell
predstate

```

#### `Set-ProfilePredictionFeature`

**Purpose:** Enables or disables one PSReadLine prediction source.

##### Parameters for `Set-ProfilePredictionFeature`

| Parameter | Meaning |
|---|---|
| `-Feature` | Prediction source to change: History or Plugin. |
| `-Enabled` | Indicates whether the selected source should be enabled. |

#### `Enable-HistoryPrediction` — alias: `histon`

**Purpose:** Enables history-based command predictions.

##### Examples for `Enable-HistoryPrediction`

```powershell
histon

```

#### `Disable-HistoryPrediction` — alias: `histoff`

**Purpose:** Hides history-based predictions without deleting command history.

##### Examples for `Disable-HistoryPrediction`

```powershell
histoff

```

#### `Enable-PluginPrediction` — alias: `predon`

**Purpose:** Enables registered predictor plug-ins, including ProfileAliases.

##### Examples for `Enable-PluginPrediction`

```powershell
predon

```

#### `Disable-PluginPrediction` — alias: `predoff`

**Purpose:** Disables predictor plug-ins while preserving history predictions.

##### Examples for `Disable-PluginPrediction`

```powershell
predoff

```

#### `Get-ProfileAlias` — alias: `palias`

**Purpose:** Lists or searches aliases managed by this profile.

##### Parameters for `Get-ProfileAlias`

| Parameter | Meaning |
|---|---|
| `-Name` | Alias-name pattern. Wildcards are supported. The default is '*'. |
| `-Category` | Limits results to one command category. |

##### Examples for `Get-ProfileAlias`

```powershell
Get-ProfileAlias

```

```powershell
palias 'p*'

```

```powershell
palias -Category Git

```

#### `Show-ProfileHelp` — alias: `phelp`

**Purpose:** Displays the profile command and alias help menu.

##### Parameters for `Show-ProfileHelp`

| Parameter | Meaning |
|---|---|
| `-Category` | Optionally displays only one command category. |

##### Examples for `Show-ProfileHelp`

```powershell
Show-ProfileHelp

```

```powershell
phelp

```

```powershell
phelp Git

```

#### `Register-ProfileAlias`

**Purpose:** Registers all aliases defined by this profile.

Removes deprecated CPRS aliases from the current PowerShell session and then registers the current centrally managed alias definitions.

### PSReadLine and predictive IntelliSense

#### `Initialize-ProfilePSReadLine`

**Purpose:** Configures PSReadLine and predictive command completion.

## 12. Complete predictor suggestion catalog

These are the command templates intended to appear under the custom `ProfileAliases` predictor. Templates with placeholders such as `<folder>` are examples to complete, not literal folder names.

| # | Suggested command | Description |
|---:|---|---|
| 1 | `phelp` | Display the PowerShell profile help menu |
| 2 | `palias` | List aliases managed by the PowerShell profile |
| 3 | `ppath` | Display the active PowerShell profile path |
| 4 | `eprof` | Open the PowerShell profile in Visual Studio Code |
| 5 | `rprof` | Reload the PowerShell profile |
| 6 | `hpath` | Display the persistent PowerShell history-file path |
| 7 | `hsearch` | Search persistent PowerShell command history |
| 8 | `ehist` | Open persistent PowerShell command history in Visual Studio Code |
| 9 | `histon` | Enable history-based command suggestions |
| 10 | `histoff` | Hide history suggestions without deleting history |
| 11 | `predon` | Enable ProfileAliases and other predictor plug-ins |
| 12 | `predoff` | Disable predictor plug-ins |
| 13 | `predstate` | Display the current prediction configuration |
| 14 | `cprs-build` | Rebuild the CPRS client in Release mode |
| 15 | `cprs-test-deploy` | Build CPRS, archive Current, and deploy to V:\TEST\EXE\Current |
| 16 | `cprs-test-deploy -SkipBuild` | Use the existing Release build, archive Current, and replace Current |
| 17 | `cprs-test-deploy -WhatIf` | Preview a Current deployment without building or changing files |
| 18 | `cprs-test-deploy -SkipBuild -WhatIf` | Preview deploying the existing Release build to Current |
| 19 | `cprs-test-deploy -Folder <folder>` | Build CPRS and replace V:\TEST\EXE\\<folder\> without touching Current |
| 20 | `cprs-test-deploy -Folder <folder> -SkipBuild` | Use the existing Release build and replace V:\TEST\EXE\\<folder\> |
| 21 | `cprs-test-deploy -Folder <folder> -WhatIf` | Preview building and deploying CPRS to a custom TEST folder |
| 22 | `cprs-test-deploy -Folder <folder> -SkipBuild -WhatIf` | Preview deploying the existing Release build to a custom TEST folder |
| 23 | `cprs-prod-deploy` | Promote V:\TEST\EXE\Current to V:\PROD\EXE\CPRS II |
| 24 | `cprs-prod-deploy -WhatIf` | Preview V:\TEST\EXE\Current -> V:\PROD\EXE\CPRS II |
| 25 | `cprs-prod-deploy -Source <folder>` | Promote V:\TEST\EXE\\<folder\> to V:\PROD\EXE\CPRS II |
| 26 | `cprs-prod-deploy -Source <folder> -WhatIf` | Preview V:\TEST\EXE\\<folder\> -> V:\PROD\EXE\CPRS II |
| 27 | `cprs-prod-deploy -Source V:\TEST\EXE\<folder>` | Promote a full TEST path to V:\PROD\EXE\CPRS II |
| 28 | `cprs-prod-deploy -Source V:\TEST\EXE\<folder> -WhatIf` | Preview promotion from a full TEST path |
| 29 | `cprs-prod-deploy -Folder <folder>` | Promote V:\TEST\EXE\\<folder\>; -Folder is an alias for -Source |
| 30 | `cprs-prod-deploy -Folder <folder> -WhatIf` | Preview production promotion using the -Folder alias |
| 31 | `cprs-ce-deploy` | CE Residential Improvements deployment commands |
| 32 | `cprs-ce-deploy preview feature local` | PREVIEW  FEATURE -> LOCAL |
| 33 | `cprs-ce-deploy deploy feature local` | DEPLOY   FEATURE -> LOCAL |
| 34 | `cprs-ce-deploy preview feature dev` | PREVIEW  FEATURE -> DEV |
| 35 | `cprs-ce-deploy deploy feature dev` | DEPLOY   FEATURE -> DEV |
| 36 | `cprs-ce-deploy preview feature test` | PREVIEW  FEATURE -> TEST |
| 37 | `cprs-ce-deploy deploy feature test` | DEPLOY   FEATURE -> TEST |
| 38 | `cprs-ce-deploy preview feature prod` | PREVIEW  FEATURE -> PROD |
| 39 | `cprs-ce-deploy deploy feature prod` | DEPLOY   FEATURE -> PROD |
| 40 | `cprs-ce-deploy preview local dev` | PREVIEW  LOCAL -> DEV |
| 41 | `cprs-ce-deploy deploy local dev` | DEPLOY   LOCAL -> DEV |
| 42 | `cprs-ce-deploy preview local test` | PREVIEW  LOCAL -> TEST |
| 43 | `cprs-ce-deploy deploy local test` | DEPLOY   LOCAL -> TEST |
| 44 | `cprs-ce-deploy preview local prod` | PREVIEW  LOCAL -> PROD |
| 45 | `cprs-ce-deploy deploy local prod` | DEPLOY   LOCAL -> PROD |
| 46 | `cprs-ce-deploy preview dev test` | PREVIEW  DEV -> TEST |
| 47 | `cprs-ce-deploy deploy dev test` | DEPLOY   DEV -> TEST |
| 48 | `cprs-ce-deploy preview dev prod` | PREVIEW  DEV -> PROD |
| 49 | `cprs-ce-deploy deploy dev prod` | DEPLOY   DEV -> PROD |
| 50 | `cprs-ce-deploy preview test prod` | PREVIEW  TEST -> PROD |
| 51 | `cprs-ce-deploy deploy test prod` | DEPLOY   TEST -> PROD |
| 52 | `c` | Clear the PowerShell console |
| 53 | `which` | Find a command, alias, function, or executable |
| 54 | `la` | List all files and directories, including hidden items |
| 55 | `up` | Move up one directory |
| 56 | `up2` | Move up two directories |
| 57 | `home` | Open the current user home directory |
| 58 | `here` | Open the current directory in File Explorer |
| 59 | `codehere` | Open the current directory in Visual Studio Code |
| 60 | `path` | Display PATH entries one per line |
| 61 | `admin` | Open an elevated PowerShell 7 session |
| 62 | `groot` | Move to the root of the current Git repository |
| 63 | `ltr` | Detailed listing sorted oldest to newest like ls -ltr |
| 64 | `dtree` | Display the current directory tree |
| 65 | `dtree -Files` | Display the directory tree including files |
| 66 | `cdev` | Open C:\Development-CPRS |
| 67 | `csas` | Open C:\Development-CPRS\cprs-sasprogs |
| 68 | `cbatch` | Open C:\Development-CPRS\cprs-batch |
| 69 | `fileops` | Open V:\DEV\Utilities\FileOpsTool\FileOpsManager.code-workspace |
| 70 | `pdir` | Open the PowerShell profile development directory |
| 71 | `predcd` | Open the ProfileAliasPredictor project directory |
| 72 | `predcmd` | Open Command Prompt in the predictor project |
| 73 | `predbuild` | Build ProfileAliasPredictor in Release mode |
| 74 | `predkill` | Stop all PowerShell 7 processes to release the predictor DLL |
| 75 | `predkill -Force` | Stop all PowerShell 7 processes without confirmation |
| 76 | `predrebuild` | Stop PowerShell and rebuild ProfileAliasPredictor |
| 77 | `predrebuild -Force` | Stop PowerShell and rebuild ProfileAliasPredictor without confirmation |
| 78 | `predproj` | Open the ProfileAliasPredictor project in Visual Studio Code |
| 79 | `predinfo` | Display ProfileAliasPredictor project and build information |
| 80 | `predtest` | Verify the PowerShell profile and predictor configuration |
| 81 | `pbatch` | Open V:\PROD\BATCH |
| 82 | `psas` | Open V:\PROD\SASPRGS |
| 83 | `plogs` | Open V:\PROD\LOGS\SASLOGS |
| 84 | `gst` | Show the current Git branch and repository status |
| 85 | `glog` | Show recent Git commits with dates and changed files |
| 86 | `gfile` | Show staged, unstaged, and untracked Git files |
| 87 | `backup-file` | Create a verified timestamped backup of a file |
| 88 | `backup-dir` | Create a verified timestamped backup of a directory |
| 89 | `zip-file` | Create and verify a ZIP archive containing one file |
| 90 | `zip-dir` | Create and verify a ZIP archive of a directory |
| 91 | `unzip` | Extract a ZIP using automatic destination selection |
| 92 | `unzip -Destination <path>` | Extract a ZIP to a specific directory |
| 93 | `unzip -WhatIf` | Preview ZIP extraction without changing files |
| 94 | `unzip -Force` | Extract and allow existing destination files to be replaced |

## 13. Adding or changing commands

Use the following workflow so behavior, aliases, help, and predictive suggestions stay synchronized:

1. **Implement or update the PowerShell function** in `profile.ps1` when custom behavior is required. Use an approved PowerShell verb/noun name and avoid making the function name case-insensitively identical to its alias.
2. **Add or update the alias definition** in `Get-ProfileAliasDefinition`. This is the central registry used by alias registration and help.
3. **Update `phelp` special workflow text** when the command has non-trivial modes, safety rules, paths, or deployment routes.
4. **Save and run `rprof`** for profile-only changes.
5. **Update `ProfileAliasPredictor.cs`** when the user-facing command or its useful option templates should be suggested while typing.
6. **Run `predrebuild`** after C# changes. The current PowerShell processes may need to close because the DLL is loaded.
7. **Run `predtest` and `predstate`** in the fresh PowerShell session.
8. **Update this guide** whenever the public command surface changes.

### Alias collision rule

PowerShell command names are case-insensitive. Therefore an alias named `backup-file` cannot safely point to a function named `Backup-File`; they are treated as the same command name and the alias can shadow itself. The adopted pattern avoids this: `backup-file -> New-FileBackup`, `backup-dir -> New-DirectoryBackup`, `zip-file -> Compress-FileArchive`, `zip-dir -> Compress-DirectoryArchive`, and `unzip -> Expand-DirectoryArchive`.

## 14. Git workflow for the two repositories

Treat the profile and predictor as independent repositories because they have different change/build lifecycles.

### Profile repository

```powershell
cd "$HOME\Documents\PowerShell"
git status
git add profile.ps1 README.md docs
git commit -m "Document PowerShell profile and command reference"
git push

```

### Predictor repository

```powershell
cd "$HOME\Documents\PowerShell\Projects\ProfileAliasPredictor"
git status
git add ProfileAliasPredictor.cs ProfileAliasPredictor.csproj
git commit -m "Update profile alias predictor commands"
git push

```

Do not commit `bin/` or `obj/` unless there is an explicit release policy requiring compiled binaries. Source + project file is normally enough because a new user can rebuild the DLL.

### Recommended change sequence when both repositories change

1. Change/test `profile.ps1`; run `rprof`. 2. Change predictor source; run `predrebuild`. 3. Run `predtest`. 4. Commit the profile repository. 5. Commit the predictor repository. 6. Push both. Keeping commit messages related makes cross-repository changes easy to trace.

## 15. Troubleshooting

### Alias is suggested but the command fails

The predictor and PowerShell alias registry are separate. A predictor suggestion only proves the C# predictor knows the text; it does not prove the function is loaded. Check the actual alias and function independently:

```powershell
Get-Command <alias> -ErrorAction SilentlyContinue
Get-Command <FunctionName> -CommandType Function -ErrorAction SilentlyContinue

```

If the alias points to a function whose name differs only by case, fix the alias/function naming collision rather than repeatedly reloading the profile.

### Profile change does not appear

```powershell
rprof
Get-Command <name>
palias <alias>

```

If `rprof` reports an error, fix that error first; later functions/aliases in the profile may not have been initialized.

### Predictor suggestion is missing

```powershell
predtest
predstate
predinfo

```

Confirm the command text exists in `ProfileAliasPredictor.cs`; if the C# file changed, run `predrebuild`. `histoff` can temporarily hide history suggestions so it is easier to see whether `[ProfileAliases]` is contributing the expected suggestion.

### Predictor DLL is locked during build

Use `predrebuild`. The loaded predictor DLL can be held open by one or more `pwsh.exe` processes, so a normal direct build may fail until those processes close.

### `cd /d` fails

`cd /d` is `cmd.exe` syntax. In PowerShell use `cd C:\path` or `Set-Location C:\path`. Use `predcmd` when you intentionally want Command Prompt in the predictor directory.

### Backup or unzip destination already exists

Preview first with `-WhatIf`. For archive extraction, `-Force` is the explicit opt-in when existing destination content may be replaced. For backups, timestamped defaults normally avoid collisions.

### CPRS deployment should not change files during review

Use the preview form: `cprs-test-deploy -WhatIf`, `cprs-prod-deploy -WhatIf`, or `cprs-ce-deploy preview ...`. Review source, destination, archive, and workload/configuration information before using the real deployment form.

## 16. Portability and machine-specific paths

Most profile-development paths use `$HOME`, which makes the profile portable across Windows usernames. The following dependencies are intentionally environment-specific and must be reviewed for another user or machine:

| Area | Current expected path/pattern |
|---|---|
| Profile root | `$HOME\Documents\PowerShell` |
| Predictor project | `$HOME\Documents\PowerShell\Projects\ProfileAliasPredictor` |
| CPRS development | `C:\Development-CPRS` |
| CPRS client | `C:\Development-CPRS\Cprs` |
| SAS repository | `C:\Development-CPRS\cprs-sasprogs` |
| Batch repository | `C:\Development-CPRS\cprs-batch` |
| TEST CPRS builds | `V:\TEST\EXE` |
| Live PROD CPRS | `V:\PROD\EXE\CPRS II` |
| PROD CPRS archives | `V:\PROD\EXE\Builds` |
| Production batch | `V:\PROD\BATCH` |
| Production SAS programs | `V:\PROD\SASPRGS` |
| Production SAS logs | `V:\PROD\LOGS\SASLOGS` |

The navigation functions use `Set-ProfileLocation`, which checks that a directory exists before changing location. Missing organization-specific drives therefore produce a warning instead of silently moving somewhere unexpected.

## 17. New-user completion checklist

| Check | Verification |
|---|---|
| PowerShell loads the intended profile | `ppath` |
| Profile reload works | `rprof` |
| Alias registry is available | `palias` |
| Full help is available | `phelp` |
| Predictor project paths are correct | `predinfo` |
| Release DLL exists | `predinfo` |
| Predictor is registered | `predtest` |
| Aliases are all registered | `predtest` |
| History + plug-in prediction state is correct | `predstate` |
| Predictor suggestions appear | Type `pred`, `cprs-`, `backup-`, or `unzip` |
| File backup preview works | `backup-file .\README.md -WhatIf` |
| ZIP extraction preview works | `unzip .\sample.zip -WhatIf` when a test ZIP is available |
| Git profile repo is clean after setup | `pdir; gst` |
| CPRS paths reviewed for this user | `phelp CPRS` and path checks |

When `predtest` reports a healthy configuration, normal aliases execute correctly, and the machine-specific paths have been reviewed, the installation is complete.

---

### Documentation maintenance note

Whenever `Get-ProfileAliasDefinition`, a global function, CPRS workflow, backup/archive behavior, or `ProfileAliasPredictor.cs` changes, update this guide in the same development cycle. The guide should describe the commands a new user will actually receive, not historical aliases.
