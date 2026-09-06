#Requires -Version 7.2

<#
.SYNOPSIS
    Leon Mil's PowerShell 7 profile.

.DESCRIPTION
    Provides reusable profile management, predictive command completion,
    command-history tools, development and production navigation shortcuts,
    Git helpers, centrally managed aliases, and an interactive help menu.

.NOTES
    Recommended profile location:
    C:\Users\mil00001\Documents\PowerShell\profile.ps1

    This is the CurrentUserAllHosts profile, so it is loaded for the current
    user by PowerShell hosts that support profiles.
#>

# =============================================================================
# Profile feature settings
# =============================================================================

# Automatically run "git pull --ff-only" when entering a Git repository.
# Change to $false if auto-pull should be disabled by default.
$global:ProfileGitAutoPullEnabled = $true

# Tracks the repository already visited so moving between folders inside the
# same repository does not repeatedly pull.
$global:ProfileGitAutoPullLastRoot = $null

# =============================================================================
# Internal helpers
# =============================================================================
function global:Invoke-GitAutoPull {
    <#
    .SYNOPSIS
        Pulls the current Git repository when auto-pull is enabled.

    .DESCRIPTION
        Detects whether the current directory is inside a Git repository.

        When entering a different repository, runs:

            git pull --ff-only

        Moving between subdirectories of the same repository does not trigger
        another pull.

        Leaving a repository resets the tracked repository so entering it again
        later triggers another pull.
    #>

    [CmdletBinding()]
    param()

    if (-not $global:ProfileGitAutoPullEnabled) {
        return
    }

    if ($null -eq (
        Get-Command git -ErrorAction SilentlyContinue
    )) {
        return
    }

    $gitRoot = & git rev-parse --show-toplevel 2>$null

    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($gitRoot)
    ) {
        $global:ProfileGitAutoPullLastRoot = $null
        return
    }

    $gitRoot = ([string]$gitRoot).Trim()

    if (
        $global:ProfileGitAutoPullLastRoot -and
        $global:ProfileGitAutoPullLastRoot.Equals(
            $gitRoot,
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        return
    }

    $global:ProfileGitAutoPullLastRoot = $gitRoot

    Write-Host ''
    Write-Host 'GIT AUTO-PULL' -ForegroundColor Cyan
    Write-Host '=============' -ForegroundColor Cyan
    Write-Host "Repository: $gitRoot"
    Write-Host ''

    & git -C $gitRoot pull --ff-only

    if ($LASTEXITCODE -ne 0) {
        Write-Warning (
            "Git auto-pull did not complete successfully for: $gitRoot"
        )
    }
}

function global:Set-LocationAndGitPull {
    <#
    .SYNOPSIS
        Changes directory and automatically pulls a newly entered Git repository.

    .DESCRIPTION
        Changes to the requested directory and then checks whether the new
        location is inside a Git repository.

        If Git auto-pull is enabled and this is a different repository from
        the last one visited, runs:

            git pull --ff-only

    .PARAMETER Path
        Directory to enter.

    .EXAMPLE
        cd C:\Development-CPRS\cprs-sasprogs

    .EXAMPLE
        cd ..

    .EXAMPLE
        cd .\ce
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.'
    )

    Microsoft.PowerShell.Management\Set-Location `
        -Path $Path

    Invoke-GitAutoPull
}


function global:Set-ProfileLocation {
    <#
    .SYNOPSIS
        Changes location after verifying that the target directory exists.

    .PARAMETER Path
        Directory to open.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Directory is not available: $Path"
        return
    }

    Microsoft.PowerShell.Management\Set-Location `
        -LiteralPath $Path

    Invoke-GitAutoPull
}


function global:Test-GitRepository {
    <#
    .SYNOPSIS
        Tests whether the current directory is inside a Git working tree.
    #>

    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        return $false
    }

    # Keep native-command redirection outside a conditional statement so
    # PSScriptAnalyzer does not mistake it for a comparison operator.
    $insideWorkTree = & git rev-parse --is-inside-work-tree 2>&1

    return ($LASTEXITCODE -eq 0 -and [string]$insideWorkTree -eq 'true')
}


# =============================================================================
# Profile management
# =============================================================================

function global:Get-ProfilePath {
    <#
    .SYNOPSIS
        Displays the main profile path or all standard profile paths.

    .PARAMETER All
        Displays all four standard PowerShell profile locations.

    .EXAMPLE
        Get-ProfilePath

    .EXAMPLE
        Get-ProfilePath -All
    #>

    [CmdletBinding()]
    param(
        [switch]$All
    )

    if (-not $All) {
        [pscustomobject]@{
            Profile = 'CurrentUserAllHosts'
            Path    = $PROFILE.CurrentUserAllHosts
            Exists  = Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts
        }

        return
    }

    @(
        [pscustomobject]@{
            Profile = 'CurrentUserAllHosts'
            Path    = $PROFILE.CurrentUserAllHosts
            Exists  = Test-Path -LiteralPath $PROFILE.CurrentUserAllHosts
        }
        [pscustomobject]@{
            Profile = 'CurrentUserCurrentHost'
            Path    = $PROFILE.CurrentUserCurrentHost
            Exists  = Test-Path -LiteralPath $PROFILE.CurrentUserCurrentHost
        }
        [pscustomobject]@{
            Profile = 'AllUsersAllHosts'
            Path    = $PROFILE.AllUsersAllHosts
            Exists  = Test-Path -LiteralPath $PROFILE.AllUsersAllHosts
        }
        [pscustomobject]@{
            Profile = 'AllUsersCurrentHost'
            Path    = $PROFILE.AllUsersCurrentHost
            Exists  = Test-Path -LiteralPath $PROFILE.AllUsersCurrentHost
        }
    )
}


function global:Edit-Profile {
    <#
    .SYNOPSIS
        Opens the PowerShell development workspace in Visual Studio Code.

    .DESCRIPTION
        Opens the PowerShell.code-workspace file located in the main
        PowerShell profile directory.

        This provides access to the complete PowerShell development
        environment instead of opening only profile.ps1.

    .EXAMPLE
        eprof
    #>

    [CmdletBinding()]
    param()

    $workspacePath =
        Join-Path `
            (Split-Path $PROFILE.CurrentUserAllHosts -Parent) `
            'PowerShell.code-workspace'

    if (-not (
        Test-Path `
            -LiteralPath $workspacePath `
            -PathType Leaf
    )) {
        throw "PowerShell workspace not found: $workspacePath"
    }

    $codeCommand =
        Get-Command code `
            -ErrorAction SilentlyContinue

    if ($null -eq $codeCommand) {
        throw (
            'Visual Studio Code command "code" was not found in PATH.'
        )
    }

    & $codeCommand.Source $workspacePath
}


function global:Import-Profile {
    <#
    .SYNOPSIS
        Reloads the main profile in the current PowerShell session.

    .DESCRIPTION
        Dot-sources the CurrentUserAllHosts profile. Profile functions and
        aliases are registered in global scope so they remain available after
        this function finishes.

    .EXAMPLE
        Import-Profile

    .EXAMPLE
        rprof
    #>

    [CmdletBinding()]
    param()

    $profilePath = $PROFILE.CurrentUserAllHosts

    if (-not (Test-Path -LiteralPath $profilePath -PathType Leaf)) {
        Write-Warning "Profile not found: $profilePath"
        return
    }

    . $profilePath

    Write-Host 'PowerShell profile reloaded.' -ForegroundColor Green
}

# =============================================================================
# PowerShell profile development
# =============================================================================

function global:Set-PowerShellProfileDirectory {
    <#
    .SYNOPSIS
        Opens the PowerShell profile development directory.

    .DESCRIPTION
        Changes the current directory to the folder containing profile.ps1
        and the ProfileAliasPredictor project.

    .EXAMPLE
        pdir
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path (
        Join-Path $HOME 'Documents\PowerShell'
    )
}

function global:Set-ProfileAliasPredictorDirectory {
    <#
    .SYNOPSIS
        Opens the ProfileAliasPredictor project directory.

    .DESCRIPTION
        Changes the current directory to the .NET project used to build
        predictive IntelliSense for PowerShell profile aliases.

    .EXAMPLE
        predcd
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path (
        Join-Path `
            $HOME `
            'Documents\PowerShell\Projects\ProfileAliasPredictor'
    )
}

function global:Open-ProfileAliasPredictorCommandPrompt {
    <#
    .SYNOPSIS
        Opens Command Prompt in the ProfileAliasPredictor project directory.

    .DESCRIPTION
        Starts cmd.exe and changes directly to the ProfileAliasPredictor
        project directory. Useful for rebuilding the predictor DLL when
        PowerShell processes need to be closed first.

    .EXAMPLE
        predcmd
    #>

    [CmdletBinding()]
    param()

    $projectPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor'

    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        Write-Warning "ProfileAliasPredictor project is not available: $projectPath"
        return
    }

    Start-Process `
        -FilePath 'cmd.exe' `
        -ArgumentList '/K', "cd /d `"$projectPath`""
}

function global:Build-ProfileAliasPredictor {
    <#
    .SYNOPSIS
        Builds the ProfileAliasPredictor .NET project in Release mode.

    .DESCRIPTION
        Runs dotnet build for ProfileAliasPredictor.csproj using the Release
        configuration.

        If the predictor DLL is currently loaded by PowerShell, the build may
        fail because the DLL is locked. Use predrebuild for the complete
        kill-and-rebuild workflow.

    .EXAMPLE
        predbuild
    #>

    [CmdletBinding()]
    param()

    $projectPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor'

    $projectFile = Join-Path `
        $projectPath `
        'ProfileAliasPredictor.csproj'

    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        Write-Warning "ProfileAliasPredictor project was not found: $projectFile"
        return
    }

    Write-Host ''
    Write-Host 'Building ProfileAliasPredictor...' -ForegroundColor Cyan
    Write-Host "Project: $projectFile"
    Write-Host ''

    & dotnet build $projectFile -c Release

    if ($LASTEXITCODE -ne 0) {
        Write-Warning 'ProfileAliasPredictor build failed.'
        Write-Warning 'If the DLL is locked, use predrebuild instead.'
        return
    }

    Write-Host ''
    Write-Host 'ProfileAliasPredictor build succeeded.' -ForegroundColor Green
    Write-Host ''
}

function global:Stop-ProfilePowerShellProcesses {
    <#
    .SYNOPSIS
        Stops all PowerShell 7 processes.

    .DESCRIPTION
        Starts a separate Command Prompt process that terminates all pwsh.exe
        processes.

        This is primarily used to release the ProfileAliasPredictor DLL before
        rebuilding the .NET project.

        WARNING:
        This closes all PowerShell 7 windows, including the current session.
        Save any work before running this command.

    .PARAMETER Force
        Skips the confirmation prompt.

    .EXAMPLE
        predkill

    .EXAMPLE
        predkill -Force
    #>

    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if (-not $Force) {
        Write-Host ''
        Write-Warning 'This will close ALL PowerShell 7 processes.'
        Write-Warning 'Save any work in other PowerShell windows before continuing.'
        Write-Host ''

        $response = Read-Host 'Continue? (Y/N)'

        if ($response -notmatch '^(Y|YES)$') {
            Write-Host 'Operation cancelled.' -ForegroundColor Yellow
            return
        }
    }

    Write-Host ''
    Write-Host 'Stopping PowerShell 7 processes...' -ForegroundColor Yellow
    Write-Host 'The current PowerShell window will close.'
    Write-Host ''

    $command =
        'timeout /t 1 /nobreak >nul & taskkill /IM pwsh.exe /F'

    Start-Process `
        -FilePath 'cmd.exe' `
        -ArgumentList '/C', $command `
        -WindowStyle Hidden
}

function global:Invoke-ProfileAliasPredictorRebuild {
    <#
    .SYNOPSIS
        Stops PowerShell 7 and rebuilds ProfileAliasPredictor.

    .DESCRIPTION
        Performs the complete ProfileAliasPredictor rebuild workflow:

            1. Creates a temporary CMD rebuild script.
            2. Opens Command Prompt.
            3. Stops all pwsh.exe processes to release the predictor DLL.
            4. Changes to the ProfileAliasPredictor project directory.
            5. Builds ProfileAliasPredictor.csproj in Release mode.
            6. Leaves Command Prompt open so the build result can be reviewed.

        WARNING:
        All PowerShell 7 windows, including the current session, will close.

    .PARAMETER Force
        Skips the confirmation prompt.

    .EXAMPLE
        predrebuild

    .EXAMPLE
        predrebuild -Force
    #>

    [CmdletBinding()]
    param(
        [switch]$Force
    )

    $projectPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor'

    $projectFile = Join-Path `
        $projectPath `
        'ProfileAliasPredictor.csproj'

    if (-not (Test-Path -LiteralPath $projectFile -PathType Leaf)) {
        Write-Warning "ProfileAliasPredictor project was not found: $projectFile"
        return
    }

    if (-not $Force) {
        Write-Host ''
        Write-Warning 'This will close ALL PowerShell 7 processes.'
        Write-Warning 'Save any work in other PowerShell windows before continuing.'
        Write-Host ''

        $response = Read-Host 'Continue with predictor rebuild? (Y/N)'

        if ($response -notmatch '^(Y|YES)$') {
            Write-Host 'Rebuild cancelled.' -ForegroundColor Yellow
            return
        }
    }

    $batchFile = Join-Path `
        $env:TEMP `
        'ProfileAliasPredictor-Rebuild.cmd'

    $batchContent = @"
@echo off
title ProfileAliasPredictor Rebuild

echo.
echo ========================================
echo ProfileAliasPredictor Rebuild
echo ========================================
echo.
echo Project:
echo $projectPath
echo.

echo Closing PowerShell 7 processes...
timeout /t 2 /nobreak >nul
taskkill /IM pwsh.exe /F

echo.
echo Changing to project directory...
cd /d "$projectPath"

echo.
echo Building ProfileAliasPredictor...
echo.

dotnet build ProfileAliasPredictor.csproj -c Release

set BUILD_EXIT=%ERRORLEVEL%

echo.

if %BUILD_EXIT% EQU 0 (
    echo ========================================
    echo BUILD SUCCEEDED
    echo ========================================
    echo.
    echo Starting PowerShell 7...
    start "" pwsh.exe
) else (
    echo ========================================
    echo BUILD FAILED - Exit code %BUILD_EXIT%
    echo ========================================
    echo.
    echo Fix the build error and run predrebuild again.
)

echo.
"@

    Set-Content `
        -LiteralPath $batchFile `
        -Value $batchContent `
        -Encoding ASCII

    Write-Host ''
    Write-Host 'Starting ProfileAliasPredictor rebuild...' -ForegroundColor Cyan
    Write-Host "Build script: $batchFile"
    Write-Host ''
    Write-Host 'PowerShell will close in approximately 2 seconds.'
    Write-Host ''

    Start-Process `
        -FilePath 'cmd.exe' `
        -ArgumentList '/K', "call `"$batchFile`""
}

function global:Get-ProfileAliasPredictorInfo {
    <#
    .SYNOPSIS
        Displays ProfileAliasPredictor project and build information.

    .EXAMPLE
        predinfo
    #>

    [CmdletBinding()]
    param()

    $projectPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor'

    $sourceFile = Join-Path `
        $projectPath `
        'ProfileAliasPredictor.cs'

    $projectFile = Join-Path `
        $projectPath `
        'ProfileAliasPredictor.csproj'

    $dllPath = Join-Path `
        $projectPath `
        'bin\Release\net10.0\ProfileAliasPredictor.dll'

    $dllItem = Get-Item `
        -LiteralPath $dllPath `
        -ErrorAction SilentlyContinue

    [pscustomobject]@{
        Project      = $projectPath
        Source       = $sourceFile
        ProjectFile  = $projectFile
        DLL          = $dllPath
        DLLExists    = $null -ne $dllItem
        DLLModified  = if ($dllItem) { $dllItem.LastWriteTime } else { $null }
        ModuleLoaded = $null -ne (
            Get-Module -Name ProfileAliasPredictor
        )
    }
}


function global:Test-ProfileAliasPredictor {
    <#
    .SYNOPSIS
        Verifies the PowerShell profile and ProfileAliasPredictor configuration.

    .DESCRIPTION
        Checks the predictor DLL, module, registered CommandPredictor,
        PSReadLine prediction settings, and profile aliases.

    .EXAMPLE
        predtest
    #>

    [CmdletBinding()]
    param()

    $dllPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor\bin\Release\net10.0\ProfileAliasPredictor.dll'

    $dllExists = Test-Path `
        -LiteralPath $dllPath `
        -PathType Leaf

    $moduleLoaded = $null -ne (
        Get-Module -Name ProfileAliasPredictor
    )

    $predictorRegistered = $false

    if ($null -ne (
        Get-Command Get-PSSubsystem -ErrorAction SilentlyContinue
    )) {
        $subsystem = Get-PSSubsystem `
            -Kind CommandPredictor `
            -ErrorAction SilentlyContinue

        $predictorRegistered = @(
            $subsystem.Implementations |
                Where-Object Name -EQ 'ProfileAliases'
        ).Count -gt 0
    }

    $predictionSource = 'Unavailable'

    if ($null -ne (
        Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue
    )) {
        $predictionSource = [string](
            Get-PSReadLineOption
        ).PredictionSource
    }

    $historyEnabled = $predictionSource -in @(
        'History',
        'HistoryAndPlugin'
    )

    $pluginEnabled = $predictionSource -in @(
        'Plugin',
        'HistoryAndPlugin'
    )

    $missingAliases = @(
        Get-ProfileAliasDefinition |
            Where-Object {
                $null -eq (
                    Get-Alias `
                        -Name $_.Alias `
                        -ErrorAction SilentlyContinue
                )
            }
    )

    $aliasesRegistered = $missingAliases.Count -eq 0

    $status = if (
        $dllExists -and
        $moduleLoaded -and
        $predictorRegistered -and
        $pluginEnabled -and
        $aliasesRegistered
    ) {
        'OK'
    }
    else {
        'CHECK'
    }

    [pscustomobject]@{
        DLLExists           = $dllExists
        ModuleLoaded        = $moduleLoaded
        PredictorRegistered = $predictorRegistered
        PluginPredictions   = $pluginEnabled
        HistoryPredictions  = $historyEnabled
        PredictionSource    = $predictionSource
        AliasesRegistered   = $aliasesRegistered
        MissingAliases      = if ($missingAliases.Count -gt 0) {
            $missingAliases.Alias -join ', '
        }
        else {
            ''
        }
        Status              = $status
    }
}

# =============================================================================
# Command history
# =============================================================================

function global:Get-CommandHistoryPath {
    <#
    .SYNOPSIS
        Displays the persistent PSReadLine history-file path.

    .EXAMPLE
        Get-CommandHistoryPath
    #>

    [CmdletBinding()]
    param()

    if ($null -eq (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue)) {
        Write-Warning 'PSReadLine is not available in this session.'
        return
    }

    (Get-PSReadLineOption).HistorySavePath
}


function global:Search-CommandHistory {
    <#
    .SYNOPSIS
        Searches the persistent PSReadLine command history.

    .PARAMETER Pattern
        Text to locate in command history.

    .PARAMETER Regex
        Treats Pattern as a regular expression. By default, Pattern is treated
        as literal text.

    .EXAMPLE
        Search-CommandHistory -Pattern 'git log'

    .EXAMPLE
        hsearch 'centurion'

    .EXAMPLE
        Search-CommandHistory -Pattern '^git ' -Regex
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Pattern,

        [switch]$Regex
    )

    $historyPath = Get-CommandHistoryPath

    if (-not $historyPath -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning 'The PSReadLine history file was not found.'
        return
    }

    $selectStringParameters = @{
        Path        = $historyPath
        Pattern     = $Pattern
        ErrorAction = 'Stop'
    }

    if (-not $Regex) {
        $selectStringParameters.SimpleMatch = $true
    }

    Select-String @selectStringParameters |
        Select-Object LineNumber, Line
}


function global:Edit-CommandHistory {
    <#
    .SYNOPSIS
        Opens the persistent PSReadLine history file.

    .EXAMPLE
        Edit-CommandHistory
    #>

    [CmdletBinding()]
    param()

    $historyPath = Get-CommandHistoryPath

    if (-not $historyPath -or -not (Test-Path -LiteralPath $historyPath -PathType Leaf)) {
        Write-Warning 'The PSReadLine history file was not found.'
        return
    }

    if ($null -ne (Get-Command code -ErrorAction SilentlyContinue)) {
        & code $historyPath
        return
    }

    Invoke-Item -LiteralPath $historyPath
}


# =============================================================================
# Development navigation
# =============================================================================

function global:Set-DevelopmentRoot {
    <#
    .SYNOPSIS
        Opens the main CPRS development directory.
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path 'C:\Development-CPRS'
}


function global:Set-SasProgramsRepository {
    <#
    .SYNOPSIS
        Opens the local CPRS SAS programs repository.
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path 'C:\Development-CPRS\cprs-sasprogs'
}


function global:Set-BatchRepository {
    <#
    .SYNOPSIS
        Opens the local CPRS batch repository.
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path 'C:\Development-CPRS\cprs-batch'
}


function global:Open-FileOpsWorkspace {
    <#
    .SYNOPSIS
        Opens the FileOps Manager VS Code workspace.

    .EXAMPLE
        Open-FileOpsWorkspace

    .EXAMPLE
        fileops
    #>

    [CmdletBinding()]
    param()

    $workspacePath = 'V:\DEV\Utilities\FileOpsTool\FileOpsManager.code-workspace'

    if (-not (Test-Path -LiteralPath $workspacePath -PathType Leaf)) {
        Write-Warning "VS Code workspace is not available: $workspacePath"
        return
    }

    if ($null -ne (Get-Command code -ErrorAction SilentlyContinue)) {
        & code $workspacePath
        return
    }

    Invoke-Item -LiteralPath $workspacePath
}


function global:Open-ProfileAliasPredictorProject {
    <#
    .SYNOPSIS
        Opens the ProfileAliasPredictor project in Visual Studio Code.

    .EXAMPLE
        Open-ProfileAliasPredictorProject

    .EXAMPLE
        epred
    #>

    [CmdletBinding()]
    param()

    $projectPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor'

    if (-not (Test-Path -LiteralPath $projectPath -PathType Container)) {
        Write-Warning "ProfileAliasPredictor project is not available: $projectPath"
        return
    }

    if ($null -ne (Get-Command code -ErrorAction SilentlyContinue)) {
        & code $projectPath
        return
    }

    Invoke-Item -LiteralPath $projectPath
}


# =============================================================================
# Production navigation
# =============================================================================

function global:Set-ProductionBatchDirectory {
    <#
    .SYNOPSIS
        Opens the production batch directory.
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path 'V:\PROD\BATCH'
}


function global:Set-ProductionSasProgramsDirectory {
    <#
    .SYNOPSIS
        Opens the production SAS programs directory.
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path 'V:\PROD\SASPRGS'
}


function global:Set-ProductionSasLogsDirectory {
    <#
    .SYNOPSIS
        Opens the production SAS logs directory.
    #>

    [CmdletBinding()]
    param()

    Set-ProfileLocation -Path 'V:\PROD\LOGS\SASLOGS'
}


# =============================================================================
# Git helpers
# =============================================================================

function global:Get-GitRepositoryStatus {
    <#
    .SYNOPSIS
        Displays the current Git branch and working-tree status.

    .EXAMPLE
        Get-GitRepositoryStatus

    .EXAMPLE
        gst
    #>

    [CmdletBinding()]
    param()

    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning 'Git is not installed or is not available in PATH.'
        return
    }

    if (-not (Test-GitRepository)) {
        Write-Warning 'The current directory is not inside a Git repository.'
        return
    }

    & git status --short --branch
}


function global:Get-GitRecentCommit {
    <#
    .SYNOPSIS
        Displays recent commits with dates and changed files.

    .PARAMETER Count
        Number of commits to display. The default is 5.

    .EXAMPLE
        Get-GitRecentCommit

    .EXAMPLE
        Get-GitRecentCommit -Count 2

    .EXAMPLE
        glog 2
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateRange(1, 50)]
        [int]$Count = 5
    )

    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning 'Git is not installed or is not available in PATH.'
        return
    }

    if (-not (Test-GitRepository)) {
        Write-Warning 'The current directory is not inside a Git repository.'
        return
    }

    $prettyFormat = '%C(cyan)%h%C(reset)  %ad  %C(yellow)%s%C(reset)'

    & git --no-pager log "-$Count" `
        --date=local `
        "--pretty=format:$prettyFormat" `
        --name-status
}


function global:Get-GitChangedFile {
    <#
    .SYNOPSIS
        Displays staged, unstaged, and untracked files.

    .EXAMPLE
        Get-GitChangedFile

    .EXAMPLE
        gfile
    #>

    [CmdletBinding()]
    param()

    if ($null -eq (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-Warning 'Git is not installed or is not available in PATH.'
        return
    }

    if (-not (Test-GitRepository)) {
        Write-Warning 'The current directory is not inside a Git repository.'
        return
    }

    & git status --short
}

function global:Enable-GitAutoPull {
    <#
    .SYNOPSIS
        Enables automatic Git pull when entering repositories.

    .EXAMPLE
        gitpullon
    #>

    [CmdletBinding()]
    param()

    Set-Variable `
        -Name ProfileGitAutoPullEnabled `
        -Value $true `
        -Scope Global

    Set-Variable `
        -Name ProfileGitAutoPullLastRoot `
        -Value $null `
        -Scope Global

    Write-Host 'Git auto-pull enabled.' -ForegroundColor Green
}


function global:Disable-GitAutoPull {
    <#
    .SYNOPSIS
        Disables automatic Git pull when entering repositories.

    .EXAMPLE
        gitpulloff
    #>

    [CmdletBinding()]
    param()

    Set-Variable `
        -Name ProfileGitAutoPullEnabled `
        -Value $false `
        -Scope Global

    Set-Variable `
        -Name ProfileGitAutoPullLastRoot `
        -Value $null `
        -Scope Global

    Write-Host 'Git auto-pull disabled.' -ForegroundColor Yellow
}


function global:Get-GitAutoPullStatus {
    <#
    .SYNOPSIS
        Displays the current Git auto-pull configuration.

    .EXAMPLE
        gitpullstate
    #>

    [CmdletBinding()]
    param()

    [pscustomobject]@{
        Enabled        = $global:ProfileGitAutoPullEnabled
        LastRepository = $global:ProfileGitAutoPullLastRoot
        PullCommand    = 'git pull --ff-only'
    }
}

# =============================================================================
# CPRS build and deployment
# =============================================================================

function global:Build-CprsRelease {
    <#
    .SYNOPSIS
        Builds the CPRS client solution in Release mode.

    .DESCRIPTION
        Builds the CPRS .NET Framework solution in Release mode.

        The CPRS executable version is generated from the Git commit count:

            1.0.<commit count>.0

        Example:

            Git commit count: 341
            CPRS version:     1.0.341.0

        AssemblyInfo.cs is modified only during the build and is restored
        immediately afterward.
    #>

    [CmdletBinding()]
    param()

    $repositoryRoot =
        'C:\Development-CPRS\Cprs'

    $solutionPath =
        Join-Path $repositoryRoot 'cprs-client.sln'

    $assemblyInfoPath =
        Join-Path $repositoryRoot 'UI\Properties\AssemblyInfo.cs'

    $outputDirectory =
        Join-Path $repositoryRoot 'UI\bin\Release'

    $executablePath =
        Join-Path $outputDirectory 'Cprs.exe'

    $vsWherePath =
        Join-Path `
            ${env:ProgramFiles(x86)} `
            'Microsoft Visual Studio\Installer\vswhere.exe'

    # -------------------------------------------------------------------------
    # Validate required files
    # -------------------------------------------------------------------------

    if (-not (
        Test-Path `
            -LiteralPath $solutionPath `
            -PathType Leaf
    )) {
        throw "CPRS solution was not found: $solutionPath"
    }

    if (-not (
        Test-Path `
            -LiteralPath $assemblyInfoPath `
            -PathType Leaf
    )) {
        throw "CPRS AssemblyInfo.cs was not found: $assemblyInfoPath"
    }

    if (-not (
        Test-Path `
            -LiteralPath $vsWherePath `
            -PathType Leaf
    )) {
        throw "Visual Studio locator was not found: $vsWherePath"
    }

    if (-not (
        Get-Command git -ErrorAction SilentlyContinue
    )) {
        throw 'Git was not found.'
    }

    # -------------------------------------------------------------------------
    # Generate version from Git commit count
    # -------------------------------------------------------------------------

    $gitCommitCount =
        & git `
            -C $repositoryRoot `
            rev-list `
            --count `
            HEAD

    if (
        $LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($gitCommitCount)
    ) {
        throw 'Unable to determine the CPRS Git commit count.'
    }

    $gitCommitCount =
        ([string]$gitCommitCount).Trim()

    $buildVersion =
        "1.0.$gitCommitCount.0"

    # -------------------------------------------------------------------------
    # Locate MSBuild
    # -------------------------------------------------------------------------

    $msBuildPath =
        & $vsWherePath `
            -latest `
            -products '*' `
            -requires Microsoft.Component.MSBuild `
            -find 'MSBuild\**\Bin\MSBuild.exe' |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($msBuildPath)) {
        throw 'A compatible Visual Studio MSBuild installation was not found.'
    }

    # -------------------------------------------------------------------------
    # Temporarily apply generated version
    # -------------------------------------------------------------------------

    $originalAssemblyInfo =
        [System.IO.File]::ReadAllBytes(
            $assemblyInfoPath
        )

    try {
        $assemblyText =
            [System.IO.File]::ReadAllText(
                $assemblyInfoPath
            )

        $assemblyText =
            [regex]::Replace(
                $assemblyText,
                '(?m)^\s*\[assembly:\s*AssemblyVersion\("[^"]+"\)\]\s*$',
                "[assembly: AssemblyVersion(`"$buildVersion`")]"
            )

        $assemblyText =
            [regex]::Replace(
                $assemblyText,
                '(?m)^\s*\[assembly:\s*AssemblyFileVersion\("[^"]+"\)\]\s*$',
                "[assembly: AssemblyFileVersion(`"$buildVersion`")]"
            )

        [System.IO.File]::WriteAllText(
            $assemblyInfoPath,
            $assemblyText
        )

        # ---------------------------------------------------------------------
        # Build
        # ---------------------------------------------------------------------

        Write-Host ''
        Write-Host 'Building CPRS in Release mode...' `
            -ForegroundColor Cyan

        Write-Host "Solution: $solutionPath"
        Write-Host "Version:  $buildVersion"
        Write-Host "MSBuild:  $msBuildPath"
        Write-Host ''

        & $msBuildPath `
            $solutionPath `
            /restore `
            /t:Rebuild `
            /p:Configuration=Release `
            /p:RuntimeIdentifier=win-x86 `
            /m:1

        $buildExitCode =
            $LASTEXITCODE

        if ($buildExitCode -ne 0) {
            throw (
                "CPRS Release build failed with exit code " +
                "$buildExitCode."
            )
        }

        if (-not (
            Test-Path `
                -LiteralPath $executablePath `
                -PathType Leaf
        )) {
            throw (
                'The build succeeded, but Cprs.exe was not found: ' +
                $executablePath
            )
        }
    }
    finally {
        # Restore the original tracked AssemblyInfo.cs exactly as it was.
        [System.IO.File]::WriteAllBytes(
            $assemblyInfoPath,
            $originalAssemblyInfo
        )
    }

    # -------------------------------------------------------------------------
    # Verify generated executable version
    # -------------------------------------------------------------------------

    $versionInfo =
        [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
            $executablePath
        )

    if ($versionInfo.FileVersion -ne $buildVersion) {
        throw (
            'CPRS version verification failed. ' +
            "Expected $buildVersion but Cprs.exe reports " +
            "$($versionInfo.FileVersion)."
        )
    }

    Write-Host ''
    Write-Host 'CPRS Release build succeeded.' `
        -ForegroundColor Green

    Write-Host "Version: $($versionInfo.FileVersion)"
    Write-Host "Output:  $outputDirectory"
    Write-Host ''

    [pscustomobject]@{
        Application     = 'CPRS'
        Configuration   = 'Release'
        Version         = $versionInfo.FileVersion
        GitCommitCount  = [int]$gitCommitCount
        Solution        = $solutionPath
        OutputDirectory = $outputDirectory
        Executable      = $executablePath
        BuildTime       = Get-Date
    }
}

function global:Get-CprsDeploymentEmailRecipients {
    <#
    .SYNOPSIS
        Retrieves CPRS deployment email recipients from CCMAIL.
    #>

    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$JobFlag = 'DEV'
    )

    $sqlServer = 'SQLSL,5034'
    $sqlDatabase = 'cprsdev'

    $connectionString =
        'Driver={ODBC Driver 17 for SQL Server};' +
        "Server=$sqlServer;" +
        "Database=$sqlDatabase;" +
        'Trusted_Connection=Yes;'

    $connection =
        [System.Data.Odbc.OdbcConnection]::new(
            $connectionString
        )

    $command = $null
    $reader = $null

    try {
        $connection.Open()

        $command =
            $connection.CreateCommand()

        $command.CommandText = @"
SELECT DISTINCT
    LTRIM(RTRIM(EMAIL)) AS EMAIL
FROM dbo.CCMAIL
WHERE JOBFLAG = ?
  AND EMAIL IS NOT NULL
  AND LTRIM(RTRIM(EMAIL)) <> ''
ORDER BY EMAIL;
"@

        $parameter =
            $command.Parameters.Add(
                '@JobFlag',
                [System.Data.Odbc.OdbcType]::VarChar,
                20
            )

        $parameter.Value =
            $JobFlag.Trim().ToUpperInvariant()

        $reader =
            $command.ExecuteReader()

        $recipients = @()

        while ($reader.Read()) {

            $email =
                ([string]$reader['EMAIL']).Trim()

            if (-not [string]::IsNullOrWhiteSpace($email)) {
                $recipients += $email
            }
        }

        $recipients =
            @(
                $recipients |
                    Sort-Object -Unique
            )

        if ($recipients.Count -eq 0) {
            throw (
                "No email recipients were found in dbo.CCMAIL " +
                "for JOBFLAG='$($JobFlag.ToUpperInvariant())'."
            )
        }

        $invalidRecipients =
            @(
                $recipients |
                    Where-Object {
                        $_ -notmatch `
                            '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
                    }
            )

        if ($invalidRecipients.Count -gt 0) {
            throw (
                'Invalid email recipient value(s) returned by CCMAIL: ' +
                ($invalidRecipients -join ', ')
            )
        }

        return $recipients
    }
    finally {

        if ($reader) {
            $reader.Dispose()
        }

        if ($command) {
            $command.Dispose()
        }

        if ($connection) {
            $connection.Dispose()
        }
    }
}

function global:Send-CprsDeploymentEmail {
    <#
    .SYNOPSIS
        Sends CPRS deployment statistics by HTML email.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [psobject]$Statistics,

        [Parameter(Mandatory)]
        [string[]]$Recipients
    )

    $smtpServer = 'mailout.census.gov'
    $smtpPort = 25
    $fromAddress = 'leon.mil@census.gov'
    $fromName = 'CPRS Deployment'

    if (-not $Recipients -or $Recipients.Count -eq 0) {
        Write-Warning 'No CPRS deployment email recipients are configured.'
        return
    }

    $subject =
        "[CPRS $($Statistics.DeploymentRoute)] Client Deployment - $($Statistics.Status)"

    function ConvertTo-HtmlValue {
        param(
            [object]$Value
        )

        return [System.Net.WebUtility]::HtmlEncode(
            [string]$Value
        )
    }

    # -------------------------------------------------------------------------
    # Deployment statistics
    # -------------------------------------------------------------------------

    $rows = @(
        ,@('Deployment Route', $Statistics.DeploymentRoute)
        ,@('Source Environment', $Statistics.SourceEnvironment)
        ,@('Target Environment', $Statistics.TargetEnvironment)
        ,@('Status', $Statistics.Status)
        ,@('Deployment Message', $Statistics.DeploymentMessage)
        ,@('Version', $Statistics.Version)
        ,@('Build', $Statistics.Build)
    )

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$Statistics.GitBranch
        )
    ) {
        $rows += ,@(
            'Git Branch',
            $Statistics.GitBranch
        )
    }

    if (
        -not [string]::IsNullOrWhiteSpace(
            [string]$Statistics.GitCommit
        )
    ) {
        $rows += ,@(
            'Git Commit',
            $Statistics.GitCommit
        )
    }

    $rows += @(
        ,@('Files Deployed', $Statistics.FilesDeployed)
        ,@('Deployment Size', "$($Statistics.DeploymentSizeMB) MB")
        ,@('Started', $Statistics.Started)
        ,@('Completed', $Statistics.Completed)
        ,@('Total Duration', $Statistics.Duration)
        ,@('Source', $Statistics.Source)
        ,@('Destination', $Statistics.Destination)
        ,@('Archive Root', $Statistics.ArchiveRoot)
        ,@('Archived To', $Statistics.ArchivedTo)
    )

    $tableRows = foreach ($row in $rows) {
        $rowName =
            [string]$row[0]

        $name =
            ConvertTo-HtmlValue $rowName

        $value =
            ConvertTo-HtmlValue $row[1]

        $rowStyle =
            if ($rowName -eq 'Deployment Message') {
                'background:#fafafa;'
            }
            else {
                ''
            }

        (
            '<tr style="{0}">' +
            '<td nowrap style="width:180px;white-space:nowrap;padding:8px 12px;border-bottom:1px solid #e5e7eb;font-weight:600;vertical-align:top;">{1}</td>' +
            '<td style="padding:8px 12px;border-bottom:1px solid #e5e7eb;vertical-align:top;">{2}</td>' +
            '</tr>'
        ) -f $rowStyle, $name, $value
    }

    # -------------------------------------------------------------------------
    # HTML email
    # -------------------------------------------------------------------------

    $statusHtml =
        ConvertTo-HtmlValue $Statistics.Status

    $routeHtml =
        ConvertTo-HtmlValue $Statistics.DeploymentRoute

    $body = @(
        '<!DOCTYPE html>'
        '<html>'
        '<body style="margin:0;padding:20px;background:#f3f4f6;font-family:Calibri,Arial,sans-serif;color:#111827;">'
        ''
        '<div style="max-width:850px;margin:auto;background:white;border:1px solid #d1d5db;">'
        ''
        '    <div style="background:#16365c;color:white;padding:20px 24px;">'
        ''
        '        <div style="font-size:22px;font-weight:bold;">'
        '            CPRS Client Build & Deployment'
        '        </div>'
        ''
        '        <div style="font-size:18px;font-weight:bold;margin-top:8px;">'
        "            $statusHtml"
        '        </div>'
        ''
        '        <div style="margin-top:6px;">'
        "            $routeHtml"
        '        </div>'
        ''
        '    </div>'
        ''
        '    <div style="padding:20px 24px;">'
        ''
        '        <table style="width:100%;border-collapse:collapse;font-size:14px;">'
        ($tableRows -join [Environment]::NewLine)
        '        </table>'
        ''
        '    </div>'
        ''
        '    <div style="padding:12px 24px;background:#f9fafb;border-top:1px solid #e5e7eb;font-size:12px;color:#6b7280;">'
        '        Automated CPRS deployment notification.'
        '    </div>'
        ''
        '</div>'
        ''
        '</body>'
        '</html>'
    ) -join [Environment]::NewLine

    # -------------------------------------------------------------------------
    # Send email
    # -------------------------------------------------------------------------

    $message = $null
    $smtpClient = $null

    try {
        $message =
            [System.Net.Mail.MailMessage]::new()

        $message.From =
            [System.Net.Mail.MailAddress]::new(
                $fromAddress,
                $fromName
            )

        foreach ($recipient in $Recipients) {
            [void]$message.To.Add(
                $recipient
            )
        }

        $message.Subject = $subject
        $message.Body = $body
        $message.IsBodyHtml = $true

        $smtpClient =
            [System.Net.Mail.SmtpClient]::new(
                $smtpServer,
                $smtpPort
            )

        $smtpClient.EnableSsl = $false

        $smtpClient.Send(
            $message
        )

        Write-Host ''
        Write-Host `
            'Deployment email sent successfully.' `
            -ForegroundColor Green

        Write-Host "Recipients : $($Recipients -join '; ')"
        Write-Host "Subject    : $subject"
        Write-Host ''
    }
    catch {
        # Deployment has already succeeded. Email failure must not change
        # the deployment result.
        Write-Warning (
            'Deployment succeeded, but the email could not be sent: ' +
            $_.Exception.Message
        )
    }
    finally {
        if ($message) {
            $message.Dispose()
        }

        if ($smtpClient) {
            $smtpClient.Dispose()
        }
    }
}

function global:Deploy-CprsTestClient {
    <#
    .SYNOPSIS
        Builds and/or deploys the CPRS client to V:\TEST\EXE.

    .DESCRIPTION
        Deploys the CPRS Release build from:

            C:\Development-CPRS\Cprs\UI\bin\Release

        DEFAULT:
            Builds CPRS.
            Archives the existing V:\TEST\EXE\CPRS II build.
            Replaces V:\TEST\EXE\CPRS II.

        -SkipBuild:
            Uses the existing local Release build.
            Archives the existing CPRS II build.
            Replaces CPRS II.

        -Folder <folder>:
            Builds CPRS.
            Replaces V:\TEST\EXE\<folder>.
            Does NOT modify CPRS II.
            Does NOT create a CPRS II archive.

        -Folder <folder> -SkipBuild:
            Uses the existing Release build.
            Replaces V:\TEST\EXE\<folder>.
            Does NOT modify CPRS II.

        -WhatIf:
            Preview only.
            Does NOT build CPRS.
            Does NOT archive, remove, create, or copy files.

    .PARAMETER SkipBuild
        Uses the existing CPRS Release build instead of rebuilding CPRS.

    .PARAMETER Folder
        Deploys to a named folder directly below V:\TEST\EXE.

        Example:

            -Folder <folder>

        Destination:

            V:\TEST\EXE\<folder>

        When Folder is supplied, CPRS II and Builds are not modified.

    .EXAMPLE
        cprs-test-deploy `
            -Message "CR2249 deployment"

        Build CPRS, archive the existing CPRS II build, and deploy the new
        build to V:\TEST\EXE\CPRS II.

    .EXAMPLE
        cprs-test-deploy `
            -SkipBuild `
            -Message "CR2249 deployment"

        Use the existing Release build, archive CPRS II, and replace CPRS II.

    .EXAMPLE
        cprs-test-deploy `
            -Folder CR2249 `
            -Message "CR2249 deployment"

        Build CPRS and replace V:\TEST\EXE\CR2249.
        CPRS II is not touched.

    .EXAMPLE
        cprs-test-deploy `
            -Folder CR2249 `
            -SkipBuild `
            -Message "CR2249 deployment"

        Use the existing Release build and replace V:\TEST\EXE\CR2249.

    .EXAMPLE
        cprs-test-deploy `
            -Message "CR2249 deployment" `
            -WhatIf

        Preview a normal CPRS II deployment without building or copying.

    .EXAMPLE
        cprs-test-deploy `
            -Folder CR2249 `
            -Message "CR2249 deployment" `
            -WhatIf

        Preview deployment to the CR2249 folder without making changes.
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [switch]$SkipBuild,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Folder,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    $sourceDirectory =
        'C:\Development-CPRS\Cprs\UI\bin\Release'

    $sourceExecutable =
        Join-Path $sourceDirectory 'Cprs.exe'

    $testRoot =
        'V:\TEST\EXE'

    $testApplicationDirectory =
        Join-Path $testRoot 'CPRS II'

    $buildArchiveRoot =
        Join-Path $testRoot 'Builds'

    $deploymentEmailJobFlag = 'DEPL'

    # -------------------------------------------------------------------------
    # Validate TEST deployment root
    # -------------------------------------------------------------------------

    if (-not (
        Test-Path `
            -LiteralPath $testRoot `
            -PathType Container
    )) {
        throw "CPRS TEST deployment root is not available: $testRoot"
    }


    # -------------------------------------------------------------------------
    # Validate optional custom folder
    # -------------------------------------------------------------------------

    $isCustomFolder =
        -not [string]::IsNullOrWhiteSpace($Folder)

    if ($isCustomFolder) {

        $Folder = $Folder.Trim()

        if (
            $Folder.Contains('\') -or
            $Folder.Contains('/') -or
            $Folder -in @('.', '..')
        ) {
            throw (
                'Folder must be a folder name only. ' +
                'Example: <folder>'
            )
        }

        $invalidCharacters =
            [System.IO.Path]::GetInvalidFileNameChars()

        if ($Folder.IndexOfAny($invalidCharacters) -ge 0) {
            throw "Invalid folder name: $Folder"
        }

        if ($Folder -in @('CPRS II', 'Builds')) {
            throw (
                "'$Folder' is reserved. " +
                'Omit -Folder to deploy to CPRS II.'
            )
        }
    }


    # -------------------------------------------------------------------------
    # Resolve destination
    # -------------------------------------------------------------------------

    if ($isCustomFolder) {
        $destinationDirectory =
            Join-Path $testRoot $Folder
    }
    else {
        $destinationDirectory =
            $testApplicationDirectory
    }


    # -------------------------------------------------------------------------
    # Display requested operation
    # -------------------------------------------------------------------------

    Write-Host ''
    Write-Host 'CPRS TEST Client Deployment' -ForegroundColor Cyan
    Write-Host '===========================' -ForegroundColor Cyan
    Write-Host ''

    Write-Host "Source      : $sourceDirectory"
    Write-Host "Destination : $destinationDirectory"

    if ($WhatIfPreference) {
        Write-Host 'Build       : WOULD BUILD' -ForegroundColor Yellow
    }
    elseif ($SkipBuild) {
        Write-Host 'Build       : SKIPPED'
    }
    else {
        Write-Host 'Build       : YES'
    }

    if ($isCustomFolder) {
        Write-Host 'Archive     : NO - custom TEST folder'
        Write-Host 'CPRS II     : NOT MODIFIED'
    }
    else {
        Write-Host "Archive     : $buildArchiveRoot"
        Write-Host 'CPRS II     : REPLACED'
    }

    Write-Host ''


    # -------------------------------------------------------------------------
    # WhatIf is a true preview.
    #
    # Do not build or modify any files.
    # -------------------------------------------------------------------------

    if ($WhatIfPreference) {

        if (
            Test-Path `
                -LiteralPath $sourceExecutable `
                -PathType Leaf
        ) {
            $previewVersion =
                [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                    $sourceExecutable
                ).FileVersion

            Write-Host "Existing local build version: $previewVersion"
        }

        if (
            -not $isCustomFolder -and
            (Test-Path `
                -LiteralPath $testApplicationDirectory `
                -PathType Container)
        ) {
            Write-Host ''
            Write-Host (
                "WHAT IF: Existing $testApplicationDirectory " +
                'would be archived before replacement.'
            )
        }

        Write-Host (
            "WHAT IF: $sourceDirectory would be copied to " +
            "$destinationDirectory"
        )

        Write-Host ''
        Write-Host 'CPRS TEST deployment preview completed.' `
            -ForegroundColor Yellow
        Write-Host ''

        return
    }

    $deploymentStart = Get-Date

    # -------------------------------------------------------------------------
    # Build unless -SkipBuild was requested
    # -------------------------------------------------------------------------

    if (-not $SkipBuild) {

        Write-Host 'Building CPRS Release...' -ForegroundColor Cyan
        Write-Host ''

        Build-CprsRelease | Out-Host
    }
    else {
        Write-Host 'Using existing CPRS Release build.' `
            -ForegroundColor Yellow
        Write-Host ''
    }


    # -------------------------------------------------------------------------
    # Validate Release output
    # -------------------------------------------------------------------------

    if (-not (
        Test-Path `
            -LiteralPath $sourceExecutable `
            -PathType Leaf
    )) {
        throw (
            'CPRS Release executable was not found: ' +
            $sourceExecutable
        )
    }

    $versionInfo =
        [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
            $sourceExecutable
        )

    $sourceVersion =
        $versionInfo.FileVersion


    # -------------------------------------------------------------------------
    # Archive existing CPRS II
    #
    # Only normal CPRS II deployments archive.
    # Custom folders NEVER touch CPRS II or Builds.
    # -------------------------------------------------------------------------

    $archiveDirectory = $null

    if (
        -not $isCustomFolder -and
        (Test-Path `
            -LiteralPath $testApplicationDirectory `
            -PathType Container)
    ) {

        $currentFiles =
            Get-ChildItem `
                -LiteralPath $testApplicationDirectory `
                -Force `
                -ErrorAction Stop

        if ($currentFiles.Count -gt 0) {

            $currentExecutable =
                Join-Path $testApplicationDirectory 'Cprs.exe'

            $archiveVersion = 'unknown'
            $archiveHash = 'unknown'

            if (
                Test-Path `
                    -LiteralPath $currentExecutable `
                    -PathType Leaf
            ) {

                $currentVersion =
                    [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                        $currentExecutable
                    )

                if (-not [string]::IsNullOrWhiteSpace(
                    $currentVersion.FileVersion
                )) {
                    $archiveVersion =
                        $currentVersion.FileVersion
                }

                $hash =
                    Get-FileHash `
                        -LiteralPath $currentExecutable `
                        -Algorithm SHA256

                $archiveHash =
                    $hash.Hash.Substring(0, 7).ToLowerInvariant()
            }

            $timestamp =
                Get-Date -Format 'yyyyMMdd-HHmmss'

            $archiveName =
                "CPRS_v${archiveVersion}_build${timestamp}_${archiveHash}"

            $archiveDirectory =
                Join-Path $buildArchiveRoot $archiveName


            Write-Host 'Archiving existing CPRS II build...' `
                -ForegroundColor Cyan

            if (-not (
                Test-Path `
                    -LiteralPath $buildArchiveRoot `
                    -PathType Container
            )) {
                New-Item `
                    -ItemType Directory `
                    -Path $buildArchiveRoot `
                    -Force `
                    -ErrorAction Stop |
                    Out-Null
            }

            New-Item `
                -ItemType Directory `
                -Path $archiveDirectory `
                -Force `
                -ErrorAction Stop |
                Out-Null

            Get-ChildItem `
                -LiteralPath $testApplicationDirectory `
                -Force `
                -ErrorAction Stop |
                Copy-Item `
                    -Destination $archiveDirectory `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop

            Write-Host "Archived to : $archiveDirectory" `
                -ForegroundColor Green
            Write-Host ''
        }
    }


    # -------------------------------------------------------------------------
    # Replace destination
    # -------------------------------------------------------------------------

    Write-Host 'Deploying CPRS build...' -ForegroundColor Cyan

    if (
        Test-Path `
            -LiteralPath $destinationDirectory
    ) {
        Remove-Item `
            -LiteralPath $destinationDirectory `
            -Recurse `
            -Force `
            -ErrorAction Stop
    }

    New-Item `
        -ItemType Directory `
        -Path $destinationDirectory `
        -Force `
        -ErrorAction Stop |
        Out-Null

    Get-ChildItem `
        -LiteralPath $sourceDirectory `
        -Force `
        -ErrorAction Stop |
        Copy-Item `
            -Destination $destinationDirectory `
            -Recurse `
            -Force `
            -ErrorAction Stop


    # -------------------------------------------------------------------------
    # Verify deployed executable
    # -------------------------------------------------------------------------

    $deployedExecutable =
        Join-Path $destinationDirectory 'Cprs.exe'

    if (-not (
        Test-Path `
            -LiteralPath $deployedExecutable `
            -PathType Leaf
    )) {
        throw (
            'Deployment copy completed but Cprs.exe was not found: ' +
            $deployedExecutable
        )
    }

    # -------------------------------------------------------------------------
    # Collect deployment statistics
    # -------------------------------------------------------------------------

    $deploymentEnd = Get-Date

    $elapsed =
        $deploymentEnd - $deploymentStart

    $duration =
        '{0:00}:{1:00}:{2:00}' -f `
            [math]::Floor($elapsed.TotalHours),
            $elapsed.Minutes,
            $elapsed.Seconds

    $deployedFiles = @(
        Get-ChildItem `
            -LiteralPath $destinationDirectory `
            -File `
            -Recurse `
            -Force `
            -ErrorAction Stop
    )

    $totalBytes =
        (
            $deployedFiles |
                Measure-Object `
                    -Property Length `
                    -Sum
        ).Sum

    if ($null -eq $totalBytes) {
        $totalBytes = 0
    }

    $deploymentSizeMB =
        [math]::Round(
            $totalBytes / 1MB,
            2
    )

    # -------------------------------------------------------------------------
    # Git information
    # -------------------------------------------------------------------------

    $repositoryRoot =
        'C:\Development-CPRS\Cprs'

    $gitBranch = 'UNKNOWN'
    $gitCommit = 'UNKNOWN'

    if (Get-Command git -ErrorAction SilentlyContinue) {

        $branch =
            & git -C $repositoryRoot branch --show-current 2>$null

        if ($LASTEXITCODE -eq 0 -and $branch) {
            $gitBranch = ([string]$branch).Trim()
        }

        $commit =
            & git -C $repositoryRoot rev-parse --short HEAD 2>$null

        if ($LASTEXITCODE -eq 0 -and $commit) {
            $gitCommit = ([string]$commit).Trim()
        }
    }

    # -------------------------------------------------------------------------
    # Build deployment statistics
    # -------------------------------------------------------------------------

    $deploymentStatistics =
        [pscustomobject]@{
            DeploymentRoute   = 'LOCAL -> TEST'
            SourceEnvironment = 'LOCAL'
            TargetEnvironment = 'TEST'
            Status            = 'SUCCESS'
            DeploymentMessage = $Message
            Version           = $sourceVersion
            Build             = if ($SkipBuild) {
                'SKIPPED - existing Release build used'
            }
            else {
                'Release build completed'
            }
            GitBranch         = $gitBranch
            GitCommit         = $gitCommit
            FilesDeployed     = $deployedFiles.Count
            DeploymentSizeMB  = $deploymentSizeMB
            Started           = $deploymentStart.ToString(
                'MM/dd/yyyy hh:mm:ss tt'
            )
            Completed         = $deploymentEnd.ToString(
                'MM/dd/yyyy hh:mm:ss tt'
            )
            Duration          = $duration
            Source            = $sourceDirectory
            Destination       = $destinationDirectory
            ArchiveRoot       = $buildArchiveRoot
            ArchivedTo        = if ($archiveDirectory) {
                $archiveDirectory
            }
            elseif ($isCustomFolder) {
                'Not archived - custom TEST folder'
            }
            else {
                'No previous build required archiving'
            }
        }

    # -------------------------------------------------------------------------
    # Email deployment statistics
    # -------------------------------------------------------------------------

    try {
        $deploymentEmailRecipients =
            Get-CprsDeploymentEmailRecipients `
                -JobFlag $deploymentEmailJobFlag

        Send-CprsDeploymentEmail `
            -Statistics $deploymentStatistics `
            -Recipients $deploymentEmailRecipients
    }
    catch {
        Write-Warning (
            'Deployment succeeded, but CCMAIL recipients could not be loaded: ' +
            $_.Exception.Message
        )
    }

    # -------------------------------------------------------------------------
    # Final result
    # -------------------------------------------------------------------------

    Write-Host ''
    Write-Host 'CPRS TEST deployment succeeded.' `
        -ForegroundColor Green

    Write-Host "Version     : $sourceVersion"
    Write-Host "Destination : $destinationDirectory"

    if ($archiveDirectory) {
        Write-Host "Archived    : $archiveDirectory"
    }

    Write-Host ''

    [pscustomobject]@{
        Application    = 'CPRS'
        Version        = $sourceVersion
        Source         = $sourceDirectory
        Destination    = $destinationDirectory
        ArchivedTo     = $archiveDirectory
        BuildSkipped   = [bool]$SkipBuild
        CustomFolder   = if ($isCustomFolder) {
            $Folder
        }
        else {
            $null
        }
        DeploymentTime = Get-Date
    }
}

function global:Deploy-CprsProductionClient {
    <#
    .SYNOPSIS
        Promotes a verified CPRS TEST build to production.

    .DESCRIPTION
        Promotes an existing CPRS client build from:

            V:\TEST\EXE\<Source>

        to:

            V:\PROD\EXE\<DestinationFolder>

        Defaults:

            Source            = CPRS II
            DestinationFolder = CPRS II

        Production safety rules:
            - Reads CURRENT_USERS from SSQLL,5026 / cprsprod.
            - Deployment is blocked unless CURRENT_USERS count is 0.
            - CURRENT_USERS is checked once before confirmation and again
              immediately after the DEPLOY confirmation.
            - Uses one confirmation: DEPLOY.
            - Does not use a staging copy.
            - Existing destination is moved into V:\PROD\EXE\Builds.
            - The TEST build is copied to PROD only once.
            - The deployment is verified after the copy.
            - If deployment fails after the old destination was archived,
              automatic rollback attempts to move the archive back into place.
            - Existing live CPRS shortcut is preserved.
            - A successful deployment sends the existing HTML deployment email.
            - Email failure does not fail or roll back a successful deployment.

        A custom production destination can be used, for example:

            cprs-prod-deploy `
                -DestinationFolder CR2249 `
                -Message "CR2249 validation"

        This deploys to:

            V:\PROD\EXE\CR2249

        and does not modify:

            V:\PROD\EXE\CPRS II

    .PARAMETER Source
        TEST folder name or complete TEST path underneath V:\TEST\EXE.
        Defaults to CPRS II.

    .PARAMETER DestinationFolder
        Folder directly underneath V:\PROD\EXE.
        Defaults to CPRS II.

    .PARAMETER Message
        Required deployment message included in the deployment report and email.

    .EXAMPLE
        cprs-prod-deploy `
            -Message "CR2249 production deployment"

    .EXAMPLE
        cprs-prod-deploy `
            -DestinationFolder CR2249 `
            -Message "CR2249 production validation"

    .EXAMPLE
        cprs-prod-deploy `
            -Message "CR2249 production deployment" `
            -WhatIf
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [Parameter(Position = 0)]
        [Alias('Folder', 'SourceFolder')]
        [ValidateNotNullOrEmpty()]
        [string]$Source = 'CPRS II',

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationFolder = 'CPRS II',

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Message
    )

    # =========================================================================
    # Deployment configuration
    # =========================================================================

    $testRoot = 'V:\TEST\EXE'
    $productionRoot = 'V:\PROD\EXE'
    $productionBuildsRoot = Join-Path $productionRoot 'Builds'

    $productionSqlServer = 'SSQLL,5026'
    $productionSqlDatabase = 'cprsprod'

    $deploymentEmailJobFlag = 'LOG'
    $shortcutName = 'Cprs - Shortcut.lnk'

    $deploymentStart = Get-Date

    $archiveDirectory = $null
    $failedDirectory = $null
    $archiveMoved = $false
    $copyStarted = $false

    # =========================================================================
    # Local helpers
    # =========================================================================

    function Get-CprsDirectorySummary {
        param(
            [Parameter(Mandatory)]
            [string]$Path
        )

        $topLevelItems = @(
            Get-ChildItem `
                -LiteralPath $Path `
                -Force `
                -ErrorAction Stop
        )

        $files = @(
            Get-ChildItem `
                -LiteralPath $Path `
                -File `
                -Recurse `
                -Force `
                -ErrorAction Stop
        )

        $bytes = (
            $files |
                Measure-Object -Property Length -Sum
        ).Sum

        if ($null -eq $bytes) {
            $bytes = 0
        }

        [pscustomobject]@{
            TopLevelItems = $topLevelItems.Count
            Files         = $files.Count
            Bytes         = [int64]$bytes
            Megabytes     = [math]::Round($bytes / 1MB, 2)
        }
    }

    function New-CprsProductionSqlConnection {
        $connectionString =
            'Driver={ODBC Driver 17 for SQL Server};' +
            "Server=$productionSqlServer;" +
            "Database=$productionSqlDatabase;" +
            'Trusted_Connection=Yes;'

        return [System.Data.Odbc.OdbcConnection]::new(
            $connectionString
        )
    }

    function Get-CprsProductionCurrentUserCount {
        $connection = New-CprsProductionSqlConnection
        $command = $null

        try {
            $connection.Open()

            $command = $connection.CreateCommand()

            $command.CommandText = @"
SELECT COUNT(*) AS user_count
FROM CURRENT_USERS;
"@

            $result = $command.ExecuteScalar()

            if ($null -eq $result -or $result -is [System.DBNull]) {
                throw 'CURRENT_USERS query returned no count.'
            }

            $userCount = [int]$result

            if ($userCount -lt 0) {
                throw 'CURRENT_USERS query returned an invalid negative count.'
            }

            return $userCount
        }
        finally {
            if ($command) {
                $command.Dispose()
            }

            if ($connection) {
                $connection.Dispose()
            }
        }
    }

    function Get-CprsProductionEmailRecipients {
        param(
            [Parameter(Mandatory)]
            [ValidateNotNullOrEmpty()]
            [string]$JobFlag
        )

        $connection = New-CprsProductionSqlConnection
        $command = $null
        $reader = $null

        try {
            $connection.Open()

            $command = $connection.CreateCommand()

            $command.CommandText = @"
SELECT DISTINCT
    LTRIM(RTRIM(EMAIL)) AS EMAIL
FROM dbo.CCMAIL
WHERE JOBFLAG = ?
  AND EMAIL IS NOT NULL
  AND LTRIM(RTRIM(EMAIL)) <> ''
ORDER BY EMAIL;
"@

            $parameter = $command.Parameters.Add(
                '@JobFlag',
                [System.Data.Odbc.OdbcType]::VarChar,
                20
            )

            $parameter.Value =
                $JobFlag.Trim().ToUpperInvariant()

            $reader =
                $command.ExecuteReader()

            $recipients = @()

            while ($reader.Read()) {
                $email =
                    ([string]$reader['EMAIL']).Trim()

                if (-not [string]::IsNullOrWhiteSpace($email)) {
                    $recipients += $email
                }
            }

            $recipients = @(
                $recipients |
                    Sort-Object -Unique
            )

            if ($recipients.Count -eq 0) {
                throw (
                    'No email recipients were found in ' +
                    "$productionSqlDatabase.dbo.CCMAIL for " +
                    "JOBFLAG='$($JobFlag.ToUpperInvariant())'."
                )
            }

            $invalidRecipients = @(
                $recipients |
                    Where-Object {
                        $_ -notmatch `
                            '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
                    }
            )

            if ($invalidRecipients.Count -gt 0) {
                throw (
                    'Invalid email recipient value(s) returned by CCMAIL: ' +
                    ($invalidRecipients -join ', ')
                )
            }

            return $recipients
        }
        finally {
            if ($reader) {
                $reader.Dispose()
            }

            if ($command) {
                $command.Dispose()
            }

            if ($connection) {
                $connection.Dispose()
            }
        }
    }

    function Show-CprsDeploymentBlocked {
        param(
            [Parameter(Mandatory)]
            [int]$CurrentUsers,
    
            [Parameter()]
            [switch]$Preview
        )
    
        Write-Host ''
        Write-Host '============================================================' `
            -ForegroundColor Red
    
        Write-Host '       CPRS PRODUCTION DEPLOYMENT BLOCKED' `
            -ForegroundColor Red
    
        Write-Host '============================================================' `
            -ForegroundColor Red
    
        Write-Host ''
    
        Write-Host (
            '{0,-18}: {1}' -f
            'Active CPRS users',
            $CurrentUsers
        ) -ForegroundColor Yellow
    
        if ($Preview) {
            Write-Host (
                '{0,-18}: {1}' -f
                'Preview result',
                'Deployment would be blocked.'
            ) -ForegroundColor Yellow
        }
        else {
            Write-Host (
                '{0,-18}: {1}' -f
                'Deployment status',
                'NOT STARTED'
            ) -ForegroundColor Yellow
        }
    
        Write-Host ''
    
        Write-Host (
            'Production deployment requires CURRENT_USERS to return 0. ' +
            'Wait until all CPRS users have logged out and try again.'
        ) -ForegroundColor Yellow
    
        Write-Host ''
    }

    # =========================================================================
    # Validate environment roots
    # =========================================================================

    if (-not (
        Test-Path `
            -LiteralPath $testRoot `
            -PathType Container
    )) {
        throw "CPRS TEST deployment root is not available: $testRoot"
    }

    if (-not (
        Test-Path `
            -LiteralPath $productionRoot `
            -PathType Container
    )) {
        throw "CPRS production root is not available: $productionRoot"
    }

    # =========================================================================
    # Validate destination folder
    # =========================================================================

    $DestinationFolder =
        $DestinationFolder.Trim()

    if (
        $DestinationFolder.Contains('\') -or
        $DestinationFolder.Contains('/') -or
        $DestinationFolder -in @('.', '..')
    ) {
        throw (
            'DestinationFolder must be a folder name only. ' +
            'Example: CR2249'
        )
    }

    $invalidCharacters =
        [System.IO.Path]::GetInvalidFileNameChars()

    if (
        $DestinationFolder.IndexOfAny(
            $invalidCharacters
        ) -ge 0
    ) {
        throw (
            'Invalid production destination folder: ' +
            $DestinationFolder
        )
    }

    if (
        $DestinationFolder.Equals(
            'Builds',
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw (
            'Builds is reserved and cannot be used as a ' +
            'production destination.'
        )
    }

    if (
        $DestinationFolder.StartsWith(
            '_CPRS_',
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw (
            'DestinationFolder cannot use the reserved ' +
            '_CPRS_ prefix.'
        )
    }

    $isLiveDestination =
        $DestinationFolder.Equals(
            'CPRS II',
            [System.StringComparison]::OrdinalIgnoreCase
        )

    $productionDirectory =
        Join-Path `
            $productionRoot `
            $DestinationFolder

    $productionExecutable =
        Join-Path `
            $productionDirectory `
            'Cprs.exe'

    $productionShortcut =
        Join-Path `
            $productionDirectory `
            $shortcutName

    # =========================================================================
    # Resolve and validate TEST source
    # =========================================================================

    $Source =
        $Source.Trim()

    if ([System.IO.Path]::IsPathRooted($Source)) {
        $sourceCandidate =
            $Source
    }
    else {
        if (
            $Source.Contains('\') -or
            $Source.Contains('/')
        ) {
            throw (
                'Specify either a TEST folder name or a complete TEST path ' +
                'underneath V:\TEST\EXE.'
            )
        }

        $sourceCandidate =
            Join-Path `
                $testRoot `
                $Source
    }

    if (-not (
        Test-Path `
            -LiteralPath $sourceCandidate `
            -PathType Container
    )) {
        throw (
            'CPRS TEST source directory was not found: ' +
            $sourceCandidate
        )
    }

    $resolvedTestRoot =
        [System.IO.Path]::GetFullPath(
            $testRoot
        ).TrimEnd('\')

    $sourceDirectory =
        [System.IO.Path]::GetFullPath(
            $sourceCandidate
        ).TrimEnd('\')

    if (-not (
        $sourceDirectory.StartsWith(
            $resolvedTestRoot + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        )
    )) {
        throw (
            'Production deployment sources must be underneath ' +
            "$testRoot. Resolved source: $sourceDirectory"
        )
    }

    $sourceExecutable =
        Join-Path `
            $sourceDirectory `
            'Cprs.exe'

    if (-not (
        Test-Path `
            -LiteralPath $sourceExecutable `
            -PathType Leaf
    )) {
        throw (
            'The selected TEST build does not contain Cprs.exe: ' +
            $sourceExecutable
        )
    }

    # =========================================================================
    # Inspect TEST source
    # =========================================================================

    $sourceVersion =
        [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
            $sourceExecutable
        ).FileVersion

    if ([string]::IsNullOrWhiteSpace($sourceVersion)) {
        throw (
            'Unable to read the TEST Cprs.exe version: ' +
            $sourceExecutable
        )
    }

    $sourceHash = (
        Get-FileHash `
            -LiteralPath $sourceExecutable `
            -Algorithm SHA256 `
            -ErrorAction Stop
    ).Hash

    $sourceSummary =
        Get-CprsDirectorySummary `
            -Path $sourceDirectory

    $sourceItems = @(
        Get-ChildItem `
            -LiteralPath $sourceDirectory `
            -Force `
            -ErrorAction Stop
    )

    if ($sourceItems.Count -eq 0) {
        throw (
            'The selected TEST build is empty: ' +
            $sourceDirectory
        )
    }

    $sourceItemPaths = @(
        $sourceItems |
            ForEach-Object {
                $_.FullName
            }
    )

    # =========================================================================
    # CURRENT_USERS preflight check
    #
    # Fail closed before inspecting or modifying the current PROD application.
    # =========================================================================

    try {
        $currentUsers =
            Get-CprsProductionCurrentUserCount
    }
    catch {
        throw (
            'Unable to verify CURRENT_USERS in ' +
            "$productionSqlServer / $productionSqlDatabase. " +
            'Production deployment is blocked. ' +
            $_.Exception.Message
        )
    }

    $deploymentBlocked = $currentUsers -gt 0

    # A real deployment stops immediately when CPRS users are active.
    # WhatIf continues so the complete deployment plan can be displayed.
    if (
        $deploymentBlocked -and
        -not $WhatIfPreference
    ) {
        Show-CprsDeploymentBlocked `
            -CurrentUsers $currentUsers

        return
    }

    # =========================================================================
    # Inspect selected PROD destination
    # =========================================================================

    $productionExists =
        Test-Path `
            -LiteralPath $productionDirectory `
            -PathType Container

    if (
        (Test-Path -LiteralPath $productionDirectory) -and
        -not $productionExists
    ) {
        throw (
            'Production destination exists but is not a directory: ' +
            $productionDirectory
        )
    }

    $productionVersion =
        'not found'

    $productionHash =
        $null

    $productionHashShort =
        'unknown'

    $productionSummary =
        [pscustomobject]@{
            TopLevelItems = 0
            Files         = 0
            Bytes         = [int64]0
            Megabytes     = 0
        }

    if ($productionExists) {
        $productionSummary =
            Get-CprsDirectorySummary `
                -Path $productionDirectory

        if (
            Test-Path `
                -LiteralPath $productionExecutable `
                -PathType Leaf
        ) {
            $productionVersion =
                [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                    $productionExecutable
                ).FileVersion

            if ([string]::IsNullOrWhiteSpace($productionVersion)) {
                $productionVersion =
                    'unknown'
            }

            $productionHash = (
                Get-FileHash `
                    -LiteralPath $productionExecutable `
                    -Algorithm SHA256 `
                    -ErrorAction Stop
            ).Hash

            $productionHashShort =
                $productionHash.
                    Substring(0, 7).
                    ToLowerInvariant()
        }
    }

    $shortcutExists =
        $isLiveDestination -and
        $productionExists -and
        (
            Test-Path `
                -LiteralPath $productionShortcut `
                -PathType Leaf
        )

    # =========================================================================
    # Determine archive destination
    # =========================================================================

    $archiveRequired =
        $productionExists

    $timestamp =
        Get-Date `
            -Format 'yyyyMMdd-HHmmss'

    $uniqueSuffix =
        [guid]::NewGuid().
            ToString('N').
            Substring(0, 8)

    $safeDestinationName =
        $DestinationFolder -replace `
            '[^A-Za-z0-9._-]',
            '_'

    $safeProductionVersion =
        ([string]$productionVersion) -replace `
            '[^A-Za-z0-9._-]',
            '_'

    if ($isLiveDestination) {
        $archiveName =
            "CPRS_v${safeProductionVersion}_build${timestamp}_" +
            "${productionHashShort}_${uniqueSuffix}"
    }
    else {
        $archiveName =
            "CPRS_${safeDestinationName}_v${safeProductionVersion}_" +
            "build${timestamp}_${productionHashShort}_${uniqueSuffix}"
    }

    $archiveDirectory =
        Join-Path `
            $productionBuildsRoot `
            $archiveName

    # =========================================================================
    # Deployment report
    # =========================================================================

    Write-Host ''
    Write-Host '============================================================' `
        -ForegroundColor Red

    Write-Host '              CPRS PRODUCTION DEPLOYMENT' `
        -ForegroundColor Red

    Write-Host '============================================================' `
        -ForegroundColor Red

    Write-Host ''

    if ($isLiveDestination) {
        Write-Host (
            'WARNING: This operation targets the LIVE CPRS production ' +
            'application.'
        ) -ForegroundColor Yellow
    }
    else {
        Write-Host (
            'CUSTOM PROD FOLDER MODE: Live V:\PROD\EXE\CPRS II ' +
            'will NOT be modified.'
        ) -ForegroundColor Green
    }

    Write-Host ''
    Write-Host "Deployment message : $Message"
    Write-Host ''

    Write-Host 'SOURCE BUILD' `
        -ForegroundColor Cyan

    Write-Host ''
    Write-Host "  TEST root       : $testRoot"
    Write-Host "  Source          : $sourceDirectory"
    Write-Host "  Cprs.exe        : $sourceExecutable"
    Write-Host "  Version         : $sourceVersion"
    Write-Host "  Top-level items : $($sourceSummary.TopLevelItems)"
    Write-Host "  Files           : $($sourceSummary.Files)"
    Write-Host "  Size            : $($sourceSummary.Megabytes) MB"
    Write-Host "  SHA256          : $sourceHash"
    Write-Host ''

    Write-Host 'PRODUCTION DESTINATION' `
        -ForegroundColor Cyan

    Write-Host ''
    Write-Host "  PROD root       : $productionRoot"
    Write-Host "  Folder          : $DestinationFolder"
    Write-Host "  Destination     : $productionDirectory"
    Write-Host "  Live CPRS II    : $isLiveDestination"
    Write-Host "  Exists          : $productionExists"
    Write-Host "  Current version : $productionVersion"
    Write-Host "  Current files   : $($productionSummary.Files)"
    Write-Host "  Current size    : $($productionSummary.Megabytes) MB"

    if ($productionHash) {
        Write-Host "  Current SHA256  : $productionHash"
    }

    if ($isLiveDestination) {
        Write-Host "  Shortcut exists : $shortcutExists"

        if ($shortcutExists) {
            Write-Host '  Shortcut action : PRESERVE'
        }
    }

    Write-Host ''

    Write-Host 'PRODUCTION DATABASE SAFETY CHECK' `
        -ForegroundColor Cyan

    Write-Host ''
    Write-Host "  SQL Server      : $productionSqlServer"
    Write-Host "  Database        : $productionSqlDatabase"
    Write-Host "  CURRENT_USERS   : $currentUsers"
    Write-Host ''

    Write-Host 'ARCHIVE/COPY PLAN' `
        -ForegroundColor Cyan

    Write-Host ''

    if ($archiveRequired) {
        Write-Host "  Archive move    : $productionDirectory -> $archiveDirectory"
    }
    else {
        Write-Host '  Archive move    : NONE - destination does not exist'
    }

    Write-Host "  Application copy: $sourceDirectory -> $productionDirectory"
    Write-Host ''

    # =========================================================================
    # WhatIf
    #
    # True preview. No filesystem changes and no email.
    # =========================================================================

    if ($WhatIfPreference) {
        Write-Host '============================================================' `
            -ForegroundColor Yellow
    
        Write-Host '                    PREVIEW ONLY' `
            -ForegroundColor Yellow
    
        Write-Host '============================================================' `
            -ForegroundColor Yellow
    
        Write-Host ''
    
        Write-Host 'NO FILESYSTEM CHANGES WERE MADE.' `
            -ForegroundColor Green
    
        Write-Host ''
    
        if ($deploymentBlocked) {
            Show-CprsDeploymentBlocked `
                -CurrentUsers $currentUsers `
                -Preview
        }
        else {
            Write-Host (
                '{0,-18}: {1}' -f
                'Active CPRS users',
                $currentUsers
            ) -ForegroundColor Green
    
            Write-Host (
                '{0,-18}: {1}' -f
                'Preview result',
                'Deployment would be allowed.'
            ) -ForegroundColor Green
    
            Write-Host ''
        }
    
        Write-Host (
            '{0,-18}: {1}' -f
            'Deployment email',
            'NOT SENT IN PREVIEW MODE'
        ) -ForegroundColor Yellow
    
        Write-Host ''
    
        return
    }

    # =========================================================================
    # Single deployment confirmation
    # =========================================================================

    Write-Host '============================================================' `
        -ForegroundColor Yellow

    Write-Host '                DEPLOYMENT CONFIRMATION' `
        -ForegroundColor Yellow

    Write-Host '============================================================' `
        -ForegroundColor Yellow

    Write-Host ''
    Write-Host "Source      : $sourceDirectory"
    Write-Host "Destination : $productionDirectory"
    Write-Host "Version     : $sourceVersion"
    Write-Host "SHA256      : $sourceHash"
    Write-Host "Users       : $currentUsers"
    Write-Host "Message     : $Message"

    if ($archiveRequired) {
        Write-Host "Archive     : $archiveDirectory"
    }

    Write-Host ''

    $deployConfirmation =
        Read-Host 'Type DEPLOY to authorize production deployment'

    if ($deployConfirmation -cne 'DEPLOY') {
        Write-Host ''

        Write-Host 'PRODUCTION DEPLOYMENT CANCELLED.' `
            -ForegroundColor Yellow

        Write-Host ''

        return
    }

    # =========================================================================
    # Recheck CURRENT_USERS immediately before changing PROD
    # =========================================================================

    try {
        $currentUsersAfterConfirmation =
            Get-CprsProductionCurrentUserCount
    }
    catch {
        throw (
            'Unable to recheck CURRENT_USERS in ' +
            "$productionSqlServer / $productionSqlDatabase. " +
            'Production deployment is blocked. No PROD files were changed. ' +
            $_.Exception.Message
        )
    }

    if ($currentUsersAfterConfirmation -gt 0) {
        Show-CprsDeploymentBlocked `
            -CurrentUsers $currentUsersAfterConfirmation

        return
    }

    Write-Host ''
    Write-Host 'CURRENT_USERS recheck: 0' `
        -ForegroundColor Green

    Write-Host 'Proceeding with production deployment.' `
        -ForegroundColor Green

    Write-Host ''

    if (-not (
        $PSCmdlet.ShouldProcess(
            $productionDirectory,
            "Deploy CPRS $sourceVersion from TEST"
        )
    )) {
        return
    }

    # =========================================================================
    # Production cutover
    # =========================================================================

    try {
        # ---------------------------------------------------------------------
        # Create Builds root only when an archive is required
        # ---------------------------------------------------------------------

        if ($archiveRequired) {
            if (-not (
                Test-Path `
                    -LiteralPath $productionBuildsRoot `
                    -PathType Container
            )) {
                New-Item `
                    -ItemType Directory `
                    -Path $productionBuildsRoot `
                    -Force `
                    -ErrorAction Stop |
                    Out-Null
            }

            if (
                Test-Path `
                    -LiteralPath $archiveDirectory
            ) {
                throw (
                    'Archive destination already exists: ' +
                    $archiveDirectory
                )
            }

            # -----------------------------------------------------------------
            # Move existing destination to archive.
            #
            # This is a same-share move, not a second application copy.
            # If the destination is locked, the move should fail before the
            # TEST application is copied into PROD.
            # -----------------------------------------------------------------

            Write-Host '============================================================' `
                -ForegroundColor Cyan

            Write-Host '        ARCHIVING CURRENT DESTINATION' `
                -ForegroundColor Cyan

            Write-Host '============================================================' `
                -ForegroundColor Cyan

            Write-Host ''
            Write-Host "Move from : $productionDirectory"
            Write-Host "Move to   : $archiveDirectory"
            Write-Host ''

            Move-Item `
                -LiteralPath $productionDirectory `
                -Destination $archiveDirectory `
                -ErrorAction Stop

            $archiveMoved =
                $true

            if (-not (
                Test-Path `
                    -LiteralPath $archiveDirectory `
                    -PathType Container
            )) {
                throw (
                    'Production archive move verification failed.'
                )
            }

            if (
                Test-Path `
                    -LiteralPath $productionDirectory
            ) {
                throw (
                    'Production archive move verification failed. ' +
                    'The original destination still exists.'
                )
            }

            $archiveSummary =
                Get-CprsDirectorySummary `
                    -Path $archiveDirectory

            if (
                $archiveSummary.Files -ne
                $productionSummary.Files
            ) {
                throw (
                    'Production archive verification failed. ' +
                    'File count does not match the original destination.'
                )
            }

            if (
                $archiveSummary.Bytes -ne
                $productionSummary.Bytes
            ) {
                throw (
                    'Production archive verification failed. ' +
                    'Byte count does not match the original destination.'
                )
            }

            if ($productionHash) {
                $archivedExecutable =
                    Join-Path `
                        $archiveDirectory `
                        'Cprs.exe'

                if (-not (
                    Test-Path `
                        -LiteralPath $archivedExecutable `
                        -PathType Leaf
                )) {
                    throw (
                        'Production archive verification failed. ' +
                        'Archived Cprs.exe is missing.'
                    )
                }

                $archivedHash = (
                    Get-FileHash `
                        -LiteralPath $archivedExecutable `
                        -Algorithm SHA256 `
                        -ErrorAction Stop
                ).Hash

                if ($archivedHash -ne $productionHash) {
                    throw (
                        'Production archive verification failed. ' +
                        'Archived Cprs.exe does not match the original.'
                    )
                }
            }

            if (
                $isLiveDestination -and
                $shortcutExists
            ) {
                $archivedShortcut =
                    Join-Path `
                        $archiveDirectory `
                        $shortcutName

                if (-not (
                    Test-Path `
                        -LiteralPath $archivedShortcut `
                        -PathType Leaf
                )) {
                    throw (
                        'Production archive verification failed. ' +
                        'The CPRS shortcut was not archived.'
                    )
                }
            }

            Write-Host 'PRODUCTION ARCHIVE MOVE VERIFIED' `
                -ForegroundColor Green

            Write-Host ''
        }

        # ---------------------------------------------------------------------
        # One application copy: TEST -> PROD
        # ---------------------------------------------------------------------

        if (
            Test-Path `
                -LiteralPath $productionDirectory
        ) {
            throw (
                'Production destination unexpectedly exists immediately ' +
                'before the TEST copy: ' +
                $productionDirectory
            )
        }

        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host '            COPYING TEST TO PRODUCTION' `
            -ForegroundColor Cyan

        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host ''
        Write-Host "Source      : $sourceDirectory"
        Write-Host "Destination : $productionDirectory"
        Write-Host ''

        New-Item `
            -ItemType Directory `
            -Path $productionDirectory `
            -ErrorAction Stop |
            Out-Null

        $copyStarted =
            $true

        Copy-Item `
            -LiteralPath $sourceItemPaths `
            -Destination $productionDirectory `
            -Recurse `
            -Force `
            -ErrorAction Stop

        # ---------------------------------------------------------------------
        # Verify deployed TEST contents
        # ---------------------------------------------------------------------

        if (-not (
            Test-Path `
                -LiteralPath $productionExecutable `
                -PathType Leaf
        )) {
            throw (
                'Production verification failed. ' +
                "Cprs.exe was not found: $productionExecutable"
            )
        }

        $deployedHash = (
            Get-FileHash `
                -LiteralPath $productionExecutable `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash

        $deployedSummary =
            Get-CprsDirectorySummary `
                -Path $productionDirectory

        if ($deployedHash -ne $sourceHash) {
            throw (
                'Production verification failed. ' +
                'Deployed Cprs.exe SHA256 does not match TEST.'
            )
        }

        if (
            $deployedSummary.Files -ne
            $sourceSummary.Files
        ) {
            throw (
                'Production verification failed. ' +
                'Deployed file count does not match TEST.'
            )
        }

        if (
            $deployedSummary.Bytes -ne
            $sourceSummary.Bytes
        ) {
            throw (
                'Production verification failed. ' +
                'Deployed byte count does not match TEST.'
            )
        }

        $deployedVersion =
            [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                $productionExecutable
            ).FileVersion

        if ($deployedVersion -ne $sourceVersion) {
            throw (
                'Production verification failed. ' +
                "Expected version $sourceVersion but found " +
                "$deployedVersion."
            )
        }

        Write-Host 'PRODUCTION APPLICATION VERIFICATION SUCCEEDED' `
            -ForegroundColor Green

        Write-Host ''

        # ---------------------------------------------------------------------
        # Preserve existing live CPRS shortcut
        # ---------------------------------------------------------------------

        $shortcutPreserved =
            $false

        if (
            $isLiveDestination -and
            $shortcutExists
        ) {
            if (-not $archiveMoved) {
                throw (
                    'Shortcut preservation requires the previous production ' +
                    'destination to have been archived.'
                )
            }

            $archivedShortcut =
                Join-Path `
                    $archiveDirectory `
                    $shortcutName

            Copy-Item `
                -LiteralPath $archivedShortcut `
                -Destination $productionShortcut `
                -Force `
                -ErrorAction Stop

            if (-not (
                Test-Path `
                    -LiteralPath $productionShortcut `
                    -PathType Leaf
            )) {
                throw (
                    'Shortcut preservation failed. ' +
                    "$shortcutName was not restored."
                )
            }

            $shell =
                $null

            $shortcut =
                $null

            try {
                $shell =
                    New-Object `
                        -ComObject WScript.Shell

                $shortcut =
                    $shell.CreateShortcut(
                        $productionShortcut
                    )

                if (-not (
                    $shortcut.TargetPath.Equals(
                        $productionExecutable,
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                )) {
                    throw (
                        'Shortcut verification failed. Target is: ' +
                        $shortcut.TargetPath
                    )
                }
            }
            finally {
                if ($shortcut) {
                    [void][System.Runtime.InteropServices.Marshal]::
                        FinalReleaseComObject(
                            $shortcut
                        )
                }

                if ($shell) {
                    [void][System.Runtime.InteropServices.Marshal]::
                        FinalReleaseComObject(
                            $shell
                        )
                }
            }

            $shortcutPreserved =
                $true

            Write-Host (
                "Shortcut preserved: $productionShortcut"
            ) -ForegroundColor Green

            Write-Host ''
        }

        # ---------------------------------------------------------------------
        # Final statistics
        # ---------------------------------------------------------------------

        $finalSummary =
            Get-CprsDirectorySummary `
                -Path $productionDirectory

        $deploymentEnd =
            Get-Date

        $elapsed =
            $deploymentEnd - $deploymentStart

        $duration =
            '{0:00}:{1:00}:{2:00}' -f `
                [math]::Floor($elapsed.TotalHours),
                $elapsed.Minutes,
                $elapsed.Seconds

        $deploymentStatistics =
            [pscustomobject]@{
                DeploymentRoute   = 'TEST -> PROD'
                SourceEnvironment = 'TEST'

                TargetEnvironment = if ($isLiveDestination) {
                    'PROD'
                }
                else {
                    "PROD/$DestinationFolder"
                }

                Status            = 'SUCCESS'
                DeploymentMessage = $Message
                Version           = $deployedVersion
                Build             = 'Promoted verified TEST build'
                GitBranch         = $null
                GitCommit         = $null
                FilesDeployed     = $sourceSummary.Files
                DeploymentSizeMB  = $sourceSummary.Megabytes

                Started =
                    $deploymentStart.ToString(
                        'MM/dd/yyyy hh:mm:ss tt'
                    )

                Completed =
                    $deploymentEnd.ToString(
                        'MM/dd/yyyy hh:mm:ss tt'
                    )

                Duration =
                    $duration

                Source =
                    $sourceDirectory

                Destination =
                    $productionDirectory

                ArchiveRoot =
                    $productionBuildsRoot

                ArchivedTo = if ($archiveMoved) {
                    $archiveDirectory
                }
                else {
                    'No previous destination required archiving'
                }
            }
    }
    catch {
        $deploymentError =
            $_

        Write-Host ''
        Write-Host '============================================================' `
            -ForegroundColor Red

        Write-Host '         CPRS PRODUCTION DEPLOYMENT FAILED' `
            -ForegroundColor Red

        Write-Host '============================================================' `
            -ForegroundColor Red

        Write-Host ''

        Write-Host "Error: $($deploymentError.Exception.Message)" `
            -ForegroundColor Red

        Write-Host ''

        # ---------------------------------------------------------------------
        # Defensive state recovery
        #
        # If the directory move completed but PowerShell threw before the
        # archive flag was assigned, recognize the actual filesystem state.
        # ---------------------------------------------------------------------

        if (
            -not $archiveMoved -and
            $archiveRequired -and
            (
                Test-Path `
                    -LiteralPath $archiveDirectory `
                    -PathType Container
            ) -and
            -not (
                Test-Path `
                    -LiteralPath $productionDirectory
            )
        ) {
            $archiveMoved =
                $true
        }

        # ---------------------------------------------------------------------
        # Rollback
        #
        # Never recursively delete the live destination as the first rollback
        # step. Move any failed/new destination aside, then move the archived
        # destination back into place.
        # ---------------------------------------------------------------------

        if (
            $copyStarted -or
            $archiveMoved
        ) {
            Write-Warning (
                'Automatic rollback will be attempted.'
            )

            try {
                if (
                    Test-Path `
                        -LiteralPath $productionDirectory
                ) {
                    $failedTimestamp =
                        Get-Date `
                            -Format 'yyyyMMdd-HHmmss'

                    $failedSuffix =
                        [guid]::NewGuid().
                            ToString('N').
                            Substring(0, 8)

                    $failedDirectory =
                        Join-Path `
                            $productionRoot `
                            (
                                '_CPRS_FAILED_' +
                                $safeDestinationName + '_' +
                                $failedTimestamp + '_' +
                                $failedSuffix
                            )

                    Move-Item `
                        -LiteralPath $productionDirectory `
                        -Destination $failedDirectory `
                        -ErrorAction Stop

                    Write-Host (
                        "Failed deployment moved aside: $failedDirectory"
                    ) -ForegroundColor Yellow
                }

                if ($archiveMoved) {
                    if (-not (
                        Test-Path `
                            -LiteralPath $archiveDirectory `
                            -PathType Container
                    )) {
                        throw (
                            'Rollback cannot find the archived destination: ' +
                            $archiveDirectory
                        )
                    }

                    if (
                        Test-Path `
                            -LiteralPath $productionDirectory
                    ) {
                        throw (
                            'Rollback destination is still occupied: ' +
                            $productionDirectory
                        )
                    }

                    Move-Item `
                        -LiteralPath $archiveDirectory `
                        -Destination $productionDirectory `
                        -ErrorAction Stop

                    $restoredSummary =
                        Get-CprsDirectorySummary `
                            -Path $productionDirectory

                    if (
                        $restoredSummary.Files -ne
                        $productionSummary.Files
                    ) {
                        throw (
                            'Rollback verification failed. ' +
                            'Restored file count does not match.'
                        )
                    }

                    if (
                        $restoredSummary.Bytes -ne
                        $productionSummary.Bytes
                    ) {
                        throw (
                            'Rollback verification failed. ' +
                            'Restored byte count does not match.'
                        )
                    }

                    if ($productionHash) {
                        $restoredExecutable =
                            Join-Path `
                                $productionDirectory `
                                'Cprs.exe'

                        if (-not (
                            Test-Path `
                                -LiteralPath $restoredExecutable `
                                -PathType Leaf
                        )) {
                            throw (
                                'Rollback verification failed. ' +
                                'Restored Cprs.exe is missing.'
                            )
                        }

                        $restoredHash = (
                            Get-FileHash `
                                -LiteralPath $restoredExecutable `
                                -Algorithm SHA256 `
                                -ErrorAction Stop
                        ).Hash

                        if ($restoredHash -ne $productionHash) {
                            throw (
                                'Rollback verification failed. ' +
                                'Restored Cprs.exe does not match.'
                            )
                        }
                    }

                    Write-Host ''
                    Write-Host 'AUTOMATIC ROLLBACK SUCCEEDED' `
                        -ForegroundColor Yellow

                    Write-Host ''
                    Write-Host "Restored to : $productionDirectory"
                    Write-Host ''
                }
                elseif ($copyStarted) {
                    Write-Host ''

                    Write-Host (
                        'No previous production destination existed. ' +
                        'The failed deployment was moved aside.'
                    ) -ForegroundColor Yellow

                    Write-Host ''
                }
            }
            catch {
                Write-Host ''

                Write-Host 'AUTOMATIC ROLLBACK FAILED' `
                    -ForegroundColor Red

                Write-Host ''

                if ($archiveMoved) {
                    Write-Host (
                        'Manual recovery archive: ' +
                        $archiveDirectory
                    ) -ForegroundColor Red
                }

                if ($failedDirectory) {
                    Write-Host (
                        'Failed deployment folder: ' +
                        $failedDirectory
                    ) -ForegroundColor Red
                }

                Write-Host ''

                Write-Host (
                    'Rollback error: ' +
                    $_.Exception.Message
                ) -ForegroundColor Red

                Write-Host ''
            }
        }

        throw $deploymentError
    }

    # =========================================================================
    # Email successful deployment
    #
    # Existing HTML email sender is preserved.
    #
    # PROD recipients are read from:
    #
    #     SSQLL,5026
    #     cprsprod
    #     dbo.CCMAIL
    #
    # using the configured JOBFLAG.
    #
    # Email failure never changes a successful deployment into a failed one.
    # =========================================================================

    try {
        $deploymentEmailRecipients =
            Get-CprsProductionEmailRecipients `
                -JobFlag $deploymentEmailJobFlag

        Send-CprsDeploymentEmail `
            -Statistics $deploymentStatistics `
            -Recipients $deploymentEmailRecipients
    }
    catch {
        Write-Warning (
            'Production deployment succeeded, but the deployment email ' +
            'could not be sent: ' +
            $_.Exception.Message
        )
    }

    # =========================================================================
    # Final success report
    # =========================================================================

    Write-Host ''
    Write-Host '============================================================' `
        -ForegroundColor Green

    Write-Host '        CPRS PRODUCTION DEPLOYMENT SUCCEEDED' `
        -ForegroundColor Green

    Write-Host '============================================================' `
        -ForegroundColor Green

    Write-Host ''
    Write-Host "Source             : $sourceDirectory"
    Write-Host "Destination        : $productionDirectory"
    Write-Host "Live CPRS II       : $isLiveDestination"
    Write-Host "Version            : $deployedVersion"
    Write-Host "Application files  : $($sourceSummary.Files)"
    Write-Host "Total files        : $($finalSummary.Files)"
    Write-Host "SHA256             : $deployedHash"
    Write-Host "Deployment message : $Message"
    Write-Host "CURRENT_USERS      : $currentUsersAfterConfirmation"

    if ($archiveMoved) {
        Write-Host "Archived build     : $archiveDirectory"
    }

    if ($isLiveDestination) {
        Write-Host "Shortcut preserved : $shortcutPreserved"
    }

    Write-Host "Completed          : $deploymentEnd"
    Write-Host ''

    [pscustomobject]@{
        Application       = 'CPRS'
        Environment       = 'PROD'
        Source            = $sourceDirectory
        Destination       = $productionDirectory
        DestinationFolder = $DestinationFolder
        LiveDestination   = $isLiveDestination
        Version           = $deployedVersion
        SHA256            = $deployedHash
        ApplicationFiles  = $sourceSummary.Files
        TotalFiles        = $finalSummary.Files
        CurrentUsers      = $currentUsersAfterConfirmation
        ShortcutPreserved = $shortcutPreserved

        ArchivedTo = if ($archiveMoved) {
            $archiveDirectory
        }
        else {
            $null
        }

        DeploymentMessage = $Message
        DeploymentTime    = $deploymentEnd
        Status            = 'SUCCESS'
    }
}

function global:Invoke-CprsDeployment {
    <#
    .SYNOPSIS
        Previews or deploys Residential Improvements between CPRS environments.

    .DESCRIPTION
        Provides a simple wrapper around the canonical Residential Improvements
        deployment script.

        Valid routes:

            FEATURE -> LOCAL
            FEATURE -> DEV
            FEATURE -> TEST
            FEATURE -> PROD

            LOCAL   -> DEV
            LOCAL   -> TEST
            LOCAL   -> PROD

            DEV     -> TEST
            DEV     -> PROD

            TEST    -> PROD

        Preview mode passes -WhatIf to the deployment script.

        Deploy mode performs the actual deployment and preserves the confirmation
        protection implemented by deploy.ps1.

        Configuration files are not deployed unless -Config is specified.

        -Force is never enabled automatically.
    .PARAMETER Action
    Specifies whether to preview or perform the deployment.

    PREVIEW
        Runs the deployment script with -WhatIf and makes no changes.

    DEPLOY
        Performs the actual deployment.

    .PARAMETER Source
        Specifies the source environment.

        Valid values:
            FEATURE
            LOCAL
            DEV
            TEST

    .PARAMETER Destination
        Specifies the destination environment.

        Valid values:
            LOCAL
            DEV
            TEST
            PROD

        The source and destination must form one of the supported deployment routes.

    .PARAMETER Config
        Deploys configuration files.

        By default, DeployConfig is NO and existing destination configuration
        files are preserved.

        When -Config is specified, DeployConfig is set to YES.

    .PARAMETER All
        Deploys all files for the selected workload instead of only updated files.

        This is equivalent to:
            -DeploymentMode ALL

    .PARAMETER Workload
        Specifies which Residential Improvements workload to deploy.

        Valid values:
            COMPONENT_ESTIMATION
            FORECASTING
            ALL

        If omitted, deploy.ps1 uses its configured default workload.

    .PARAMETER DeploymentMode
        Controls which files are selected for deployment.

        UPDATED
            Deploys only new and changed files.

        ALL
            Deploys all eligible files for the selected workload.

    .PARAMETER Force
        Passes -Force to deploy.ps1 and bypasses its interactive deployment
        confirmation.

        This option is never enabled automatically and should be used only when
        confirmation bypass is intentional.

    .EXAMPLE
        cprs-ce-deploy preview feature local

    .EXAMPLE
        cprs-ce-deploy deploy local dev

    .EXAMPLE
        cprs-ce-deploy preview dev test -All

    .EXAMPLE
        cprs-ce-deploy deploy test prod -Config

    .EXAMPLE
        cprs-ce-deploy preview dev test -Workload ALL

    .EXAMPLE
        cprs-ce-deploy deploy dev test -Workload COMPONENT_ESTIMATION

    .EXAMPLE
        cprs-ce-deploy preview local dev -DeploymentMode ALL
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('PREVIEW', 'DEPLOY')]
        [string]$Action,

        [Parameter(Mandatory, Position = 1)]
        [ValidateSet('FEATURE', 'LOCAL', 'DEV', 'TEST')]
        [string]$Source,

        [Parameter(Mandatory, Position = 2)]
        [ValidateSet('LOCAL', 'DEV', 'TEST', 'PROD')]
        [string]$Destination,

        [switch]$Config,

        [switch]$All,

        [Parameter(Mandatory)]
        [ValidateSet(
            'COMPONENT_ESTIMATION',
            'FORECASTING',
            'ALL'
        )]
        [string]$Workload,

        [ValidateSet(
            'UPDATED',
            'ALL'
        )]
        [string]$DeploymentMode,

        [switch]$Force
    )

    $deployScript =
        'C:\Development-CPRS\Features\residential-improvements\scripts\deployment\deploy.ps1'

    if (-not (Test-Path -LiteralPath $deployScript -PathType Leaf)) {
        throw "CPRS deployment script was not found: $deployScript"
    }

    $sourceName = $Source.ToUpperInvariant()
    $destinationName = $Destination.ToUpperInvariant()

    $route = "$sourceName->$destinationName"

    $validRoutes = @(
        'FEATURE->LOCAL'
        'FEATURE->DEV'
        'FEATURE->TEST'
        'FEATURE->PROD'
        'LOCAL->DEV'
        'LOCAL->TEST'
        'LOCAL->PROD'
        'DEV->TEST'
        'DEV->PROD'
        'TEST->PROD'
    )

    if ($route -notin $validRoutes) {
        throw "Invalid CPRS deployment route: $route"
    }

    $deployParameters = @{
        Source       = $sourceName
        Destination  = $destinationName
        DeployConfig = if ($Config) { 'YES' } else { 'NO' }
    }

    if ($PSBoundParameters.ContainsKey('Workload')) {
        $deployParameters['Workload'] =
            $Workload.ToUpperInvariant()
    }

    if ($All) {
        $deployParameters['DeploymentMode'] = 'ALL'
    }
    elseif ($PSBoundParameters.ContainsKey('DeploymentMode')) {
        $deployParameters['DeploymentMode'] =
            $DeploymentMode.ToUpperInvariant()
    }

    if ($Force) {
        $deployParameters['Force'] = $true
    }

    if ($Action -ieq 'PREVIEW') {
        $deployParameters['WhatIf'] = $true
    }

    Write-Host ''
    Write-Host 'CPRS Deployment' -ForegroundColor Cyan
    Write-Host "Action:      $($Action.ToUpperInvariant())"
    Write-Host "Route:       $route"
    Write-Host "Config:      $($deployParameters.DeployConfig)"

    if ($deployParameters.ContainsKey('Workload')) {
        Write-Host "Workload:    $($deployParameters.Workload)"
    }

    if ($deployParameters.ContainsKey('DeploymentMode')) {
        Write-Host "Mode:        $($deployParameters.DeploymentMode)"
    }

    Write-Host ''

    & $deployScript @deployParameters
}

# =============================================================================
# General utilities
# =============================================================================

# =============================================================================
# Backup and archive utilities
# =============================================================================

function global:New-FileBackup {
    <#
    .SYNOPSIS
        Creates a verified, timestamped backup of a file.

    .DESCRIPTION
        Copies a file to a backup directory using a timestamped file name.

        By default:

            C:\Work\report.txt

        becomes:

            C:\Work\Backups\report_20260815-094500.txt

        A different backup directory can be supplied with -Destination.

        The copied file is verified using:
            - file size
            - SHA256 hash

        Supports -WhatIf.

    .PARAMETER Path
        File to back up.

    .PARAMETER Destination
        Backup directory.

        If omitted, a Backups directory is created beside the source file.

    .EXAMPLE
        backup-file .\profile.ps1

    .EXAMPLE
        backup-file .\profile.ps1 -Destination C:\Backups

    .EXAMPLE
        backup-file .\profile.ps1 -WhatIf
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Destination
    )

    $resolvedPath =
        (
            Resolve-Path `
                -LiteralPath $Path `
                -ErrorAction Stop
        ).Path

    $source =
        Get-Item `
            -LiteralPath $resolvedPath `
            -Force `
            -ErrorAction Stop

    if ($source.PSIsContainer) {
        throw (
            "'$resolvedPath' is a directory. " +
            'Use backup-dir for directories.'
        )
    }

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        $backupRoot =
            Join-Path $source.DirectoryName 'Backups'
    }
    else {
        $backupRoot =
            $ExecutionContext.SessionState.Path.
                GetUnresolvedProviderPathFromPSPath(
                    $Destination
                )
    }

    if (
        (Test-Path -LiteralPath $backupRoot) -and
        -not (
            Test-Path `
                -LiteralPath $backupRoot `
                -PathType Container
        )
    ) {
        throw (
            "Backup destination is not a directory: $backupRoot"
        )
    }

    $timestamp =
        Get-Date -Format 'yyyyMMdd-HHmmssfff'

    $backupName =
        '{0}_{1}{2}' -f `
            $source.BaseName,
            $timestamp,
            $source.Extension

    $backupPath =
        Join-Path $backupRoot $backupName

    $sourceHash =
        (
            Get-FileHash `
                -LiteralPath $source.FullName `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash

    Write-Host ''
    Write-Host 'FILE BACKUP' -ForegroundColor Cyan
    Write-Host '===========' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Source      : $($source.FullName)"
    Write-Host "Destination : $backupPath"
    Write-Host "Size        : $($source.Length) bytes"
    Write-Host "SHA256      : $sourceHash"
    Write-Host ''

    if (-not (
        $PSCmdlet.ShouldProcess(
            $backupPath,
            "Back up file $($source.FullName)"
        )
    )) {
        return
    }

    if (-not (
        Test-Path `
            -LiteralPath $backupRoot `
            -PathType Container
    )) {
        New-Item `
            -ItemType Directory `
            -Path $backupRoot `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    Copy-Item `
        -LiteralPath $source.FullName `
        -Destination $backupPath `
        -Force `
        -ErrorAction Stop

    $backup =
        Get-Item `
            -LiteralPath $backupPath `
            -Force `
            -ErrorAction Stop

    if ($backup.Length -ne $source.Length) {
        throw (
            'Backup verification failed: file sizes do not match.'
        )
    }

    $backupHash =
        (
            Get-FileHash `
                -LiteralPath $backupPath `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash

    if ($backupHash -ne $sourceHash) {
        throw (
            'Backup verification failed: SHA256 hashes do not match.'
        )
    }

    Write-Host 'Backup verified successfully.' `
        -ForegroundColor Green
    Write-Host ''

    [pscustomobject]@{
        Type        = 'File Backup'
        Source      = $source.FullName
        Destination = $backupPath
        Bytes       = $backup.Length
        SHA256      = $backupHash
        Verified    = $true
        Created     = Get-Date
        Status      = 'SUCCESS'
    }
}


function global:New-DirectoryBackup {
    <#
    .SYNOPSIS
        Creates a verified, timestamped backup of a complete directory.

    .DESCRIPTION
        Copies an entire directory to a timestamped backup directory.

        Example:

            C:\Projects\MyProject

        becomes:

            C:\Projects\Backups\MyProject_20260815-094500

        The default verification checks every copied file by:
            - relative path
            - file size
            - SHA256 hash

        Use -SkipHashVerification for a faster verification that compares
        paths and sizes without hashing every file.

        The backup destination is not allowed to be inside the source
        directory because that could cause recursive self-copying.

        Supports -WhatIf.

    .PARAMETER Path
        Directory to back up.

    .PARAMETER Destination
        Root directory in which the timestamped backup is created.

        If omitted, a Backups directory is created beside the source
        directory.

    .PARAMETER SkipHashVerification
        Skips per-file SHA256 comparison.

    .EXAMPLE
        backup-dir C:\Development-CPRS\Cprs

    .EXAMPLE
        backup-dir C:\Development-CPRS\Cprs -Destination D:\Backups

    .EXAMPLE
        backup-dir C:\Development-CPRS\Cprs -WhatIf

    .EXAMPLE
        backup-dir C:\Development-CPRS\Cprs -SkipHashVerification
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [switch]$SkipHashVerification
    )

    $resolvedPath =
        (
            Resolve-Path `
                -LiteralPath $Path `
                -ErrorAction Stop
        ).Path

    $source =
        Get-Item `
            -LiteralPath $resolvedPath `
            -Force `
            -ErrorAction Stop

    if (-not $source.PSIsContainer) {
        throw (
            "'$resolvedPath' is a file. " +
            'Use backup-file for files.'
        )
    }

    if ($null -eq $source.Parent) {
        throw (
            'Backing up an entire filesystem root is not supported.'
        )
    }

    $sourceDirectory =
        $source.FullName.TrimEnd('\')

    if ([string]::IsNullOrWhiteSpace($Destination)) {
        $backupRoot =
            Join-Path $source.Parent.FullName 'Backups'
    }
    else {
        $backupRoot =
            $ExecutionContext.SessionState.Path.
                GetUnresolvedProviderPathFromPSPath(
                    $Destination
                )
    }

    $backupRoot =
        $backupRoot.TrimEnd('\')

    if (
        $backupRoot.Equals(
            $sourceDirectory,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $backupRoot.StartsWith(
            $sourceDirectory + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw (
            'The backup destination cannot be the source directory ' +
            'or a directory underneath the source.'
        )
    }

    $timestamp =
        Get-Date -Format 'yyyyMMdd-HHmmssfff'

    $backupDirectory =
        Join-Path `
            $backupRoot `
            "$($source.Name)_$timestamp"

    $sourceFiles = @(
        Get-ChildItem `
            -LiteralPath $sourceDirectory `
            -File `
            -Recurse `
            -Force `
            -ErrorAction Stop
    )

    $sourceBytes =
        (
            $sourceFiles |
                Measure-Object `
                    -Property Length `
                    -Sum
        ).Sum

    if ($null -eq $sourceBytes) {
        $sourceBytes = 0
    }

    # Build a source manifest BEFORE copying.
    $sourceManifest = @{}

    foreach ($file in $sourceFiles) {

        $relativePath =
            [System.IO.Path]::GetRelativePath(
                $sourceDirectory,
                $file.FullName
            )

        $hash = $null

        if (-not $SkipHashVerification) {
            $hash =
                (
                    Get-FileHash `
                        -LiteralPath $file.FullName `
                        -Algorithm SHA256 `
                        -ErrorAction Stop
                ).Hash
        }

        $sourceManifest[$relativePath] =
            [pscustomobject]@{
                Length = $file.Length
                SHA256 = $hash
            }
    }

    Write-Host ''
    Write-Host 'DIRECTORY BACKUP' -ForegroundColor Cyan
    Write-Host '================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Source      : $sourceDirectory"
    Write-Host "Destination : $backupDirectory"
    Write-Host "Files       : $($sourceFiles.Count)"
    Write-Host "Size        : $sourceBytes bytes"

    if ($SkipHashVerification) {
        Write-Host 'Verification: relative path + file size'
    }
    else {
        Write-Host 'Verification: relative path + file size + SHA256'
    }

    Write-Host ''

    if (-not (
        $PSCmdlet.ShouldProcess(
            $backupDirectory,
            "Back up directory $sourceDirectory"
        )
    )) {
        return
    }

    if (-not (
        Test-Path `
            -LiteralPath $backupRoot `
            -PathType Container
    )) {
        New-Item `
            -ItemType Directory `
            -Path $backupRoot `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    New-Item `
        -ItemType Directory `
        -Path $backupDirectory `
        -Force `
        -ErrorAction Stop |
        Out-Null

    Get-ChildItem `
        -LiteralPath $sourceDirectory `
        -Force `
        -ErrorAction Stop |
        ForEach-Object {
            Copy-Item `
                -LiteralPath $_.FullName `
                -Destination $backupDirectory `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }

    $backupFiles = @(
        Get-ChildItem `
            -LiteralPath $backupDirectory `
            -File `
            -Recurse `
            -Force `
            -ErrorAction Stop
    )

    if ($backupFiles.Count -ne $sourceFiles.Count) {
        throw (
            'Backup verification failed: file counts do not match.'
        )
    }

    foreach ($relativePath in $sourceManifest.Keys) {

        $backupFile =
            Join-Path `
                $backupDirectory `
                $relativePath

        if (-not (
            Test-Path `
                -LiteralPath $backupFile `
                -PathType Leaf
        )) {
            throw (
                "Backup verification failed. Missing file: " +
                $relativePath
            )
        }

        $expected =
            $sourceManifest[$relativePath]

        $actual =
            Get-Item `
                -LiteralPath $backupFile `
                -Force `
                -ErrorAction Stop

        if ($actual.Length -ne $expected.Length) {
            throw (
                "Backup verification failed. Size mismatch: " +
                $relativePath
            )
        }

        if (-not $SkipHashVerification) {

            $actualHash =
                (
                    Get-FileHash `
                        -LiteralPath $backupFile `
                        -Algorithm SHA256 `
                        -ErrorAction Stop
                ).Hash

            if ($actualHash -ne $expected.SHA256) {
                throw (
                    "Backup verification failed. SHA256 mismatch: " +
                    $relativePath
                )
            }
        }
    }

    Write-Host ''
    Write-Host 'Directory backup verified successfully.' `
        -ForegroundColor Green
    Write-Host ''

    [pscustomobject]@{
        Type        = 'Directory Backup'
        Source      = $sourceDirectory
        Destination = $backupDirectory
        FileCount   = $backupFiles.Count
        Bytes       = [int64]$sourceBytes
        Verification = if ($SkipHashVerification) {
            'PATH_AND_SIZE'
        }
        else {
            'PATH_SIZE_SHA256'
        }
        Verified    = $true
        Created     = Get-Date
        Status      = 'SUCCESS'
    }
}


function global:Compress-FileArchive {
    <#
    .SYNOPSIS
        Creates a timestamped ZIP archive containing one file.

    .DESCRIPTION
        Creates a ZIP archive from a single file.

        Default:

            C:\Work\report.txt

        becomes:

            C:\Work\Archives\report_20260815-094500.zip

        -Destination may be either:
            - an archive directory
            - a complete .zip file path

        The archive is opened after creation and the archived file is
        verified by name, size, and SHA256.

    .PARAMETER Path
        File to compress.

    .PARAMETER Destination
        Destination directory or complete .zip path.

    .PARAMETER Force
        Replaces an explicitly supplied ZIP file if it already exists.

    .EXAMPLE
        zip-file C:\Work\report.txt

    .EXAMPLE
        zip-file C:\Work\report.txt -Destination D:\Archives

    .EXAMPLE
        zip-file C:\Work\report.txt -Destination D:\Archives\report.zip

    .EXAMPLE
        zip-file C:\Work\report.txt -WhatIf
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [switch]$Force
    )

    $resolvedPath =
        (
            Resolve-Path `
                -LiteralPath $Path `
                -ErrorAction Stop
        ).Path

    $source =
        Get-Item `
            -LiteralPath $resolvedPath `
            -Force `
            -ErrorAction Stop

    if ($source.PSIsContainer) {
        throw (
            "'$resolvedPath' is a directory. " +
            'Use zip-dir for directories.'
        )
    }

    $timestamp =
        Get-Date -Format 'yyyyMMdd-HHmmssfff'

    $defaultZipName =
        "$($source.BaseName)_$timestamp.zip"

    if ([string]::IsNullOrWhiteSpace($Destination)) {

        $archiveRoot =
            Join-Path $source.DirectoryName 'Archives'

        $zipPath =
            Join-Path $archiveRoot $defaultZipName
    }
    else {

        $resolvedDestination =
            $ExecutionContext.SessionState.Path.
                GetUnresolvedProviderPathFromPSPath(
                    $Destination
                )

        if (
            [System.IO.Path]::GetExtension(
                $resolvedDestination
            ) -ieq '.zip'
        ) {
            $zipPath =
                $resolvedDestination

            $archiveRoot =
                Split-Path `
                    -Path $zipPath `
                    -Parent
        }
        else {
            $archiveRoot =
                $resolvedDestination

            $zipPath =
                Join-Path `
                    $archiveRoot `
                    $defaultZipName
        }
    }

    if (
        Test-Path `
            -LiteralPath $zipPath `
            -PathType Leaf
    ) {
        if (-not $Force) {
            throw (
                "ZIP archive already exists: $zipPath. " +
                'Use -Force to replace it.'
            )
        }
    }

    $sourceHash =
        (
            Get-FileHash `
                -LiteralPath $source.FullName `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash

    Write-Host ''
    Write-Host 'FILE ZIP ARCHIVE' -ForegroundColor Cyan
    Write-Host '================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Source      : $($source.FullName)"
    Write-Host "Destination : $zipPath"
    Write-Host "Source size : $($source.Length) bytes"
    Write-Host "SHA256      : $sourceHash"
    Write-Host ''

    if (-not (
        $PSCmdlet.ShouldProcess(
            $zipPath,
            "Create ZIP archive from $($source.FullName)"
        )
    )) {
        return
    }

    if (-not (
        Test-Path `
            -LiteralPath $archiveRoot `
            -PathType Container
    )) {
        New-Item `
            -ItemType Directory `
            -Path $archiveRoot `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    if (
        Test-Path `
            -LiteralPath $zipPath `
            -PathType Leaf
    ) {
        Remove-Item `
            -LiteralPath $zipPath `
            -Force `
            -ErrorAction Stop
    }

    Add-Type `
        -AssemblyName System.IO.Compression `
        -ErrorAction SilentlyContinue

    Add-Type `
        -AssemblyName System.IO.Compression.FileSystem `
        -ErrorAction SilentlyContinue

    $zipStream =
        [System.IO.File]::Open(
            $zipPath,
            [System.IO.FileMode]::CreateNew
        )

    $archive =
        [System.IO.Compression.ZipArchive]::new(
            $zipStream,
            [System.IO.Compression.ZipArchiveMode]::Create,
            $false
        )

    try {
        [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $archive,
            $source.FullName,
            $source.Name,
            [System.IO.Compression.CompressionLevel]::Optimal
        ) |
            Out-Null
    }
    finally {
        $archive.Dispose()
        $zipStream.Dispose()
    }

    # Verify the ZIP contents.
    $archive =
        [System.IO.Compression.ZipFile]::OpenRead(
            $zipPath
        )

    try {

        $entry =
            $archive.GetEntry(
                $source.Name
            )

        if ($null -eq $entry) {
            throw (
                'ZIP verification failed: archived file was not found.'
            )
        }

        if ($entry.Length -ne $source.Length) {
            throw (
                'ZIP verification failed: file size does not match.'
            )
        }

        $entryStream =
            $entry.Open()

        $sha256 =
            [System.Security.Cryptography.SHA256]::Create()

        try {
            $entryHashBytes =
                $sha256.ComputeHash(
                    $entryStream
                )

            $entryHash =
                [System.BitConverter]::ToString(
                    $entryHashBytes
                ).Replace('-', '')
        }
        finally {
            $sha256.Dispose()
            $entryStream.Dispose()
        }

        if ($entryHash -ne $sourceHash) {
            throw (
                'ZIP verification failed: SHA256 does not match.'
            )
        }
    }
    finally {
        $archive.Dispose()
    }

    $zipHash =
        (
            Get-FileHash `
                -LiteralPath $zipPath `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash

    $zipItem =
        Get-Item `
            -LiteralPath $zipPath `
            -ErrorAction Stop

    Write-Host ''
    Write-Host 'ZIP archive verified successfully.' `
        -ForegroundColor Green
    Write-Host ''

    [pscustomobject]@{
        Type        = 'File ZIP'
        Source      = $source.FullName
        Destination = $zipPath
        ZipBytes    = $zipItem.Length
        ZipSHA256   = $zipHash
        Verified    = $true
        Created     = Get-Date
        Status      = 'SUCCESS'
    }
}


function global:Compress-DirectoryArchive {
    <#
    .SYNOPSIS
        Creates a timestamped ZIP archive of a complete directory.

    .DESCRIPTION
        Creates a ZIP containing the selected directory and its contents.

        Default:

            C:\Projects\MyProject

        becomes:

            C:\Projects\Archives\MyProject_20260815-094500.zip

        The top-level source directory is preserved inside the ZIP.

        The ZIP destination is not allowed inside the source directory.

        Verification checks:
            - source file count
            - ZIP file-entry count
            - uncompressed byte count
            - final ZIP SHA256

    .PARAMETER Path
        Directory to archive.

    .PARAMETER Destination
        Destination directory or complete .zip path.

    .PARAMETER Force
        Replaces an explicitly supplied ZIP file if it already exists.

    .EXAMPLE
        zip-dir C:\Development-CPRS\Cprs

    .EXAMPLE
        zip-dir C:\Development-CPRS\Cprs -Destination D:\Archives

    .EXAMPLE
        zip-dir C:\Development-CPRS\Cprs -Destination D:\Archives\Cprs.zip

    .EXAMPLE
        zip-dir C:\Development-CPRS\Cprs -WhatIf
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [switch]$Force
    )

    $resolvedPath =
        (
            Resolve-Path `
                -LiteralPath $Path `
                -ErrorAction Stop
        ).Path

    $source =
        Get-Item `
            -LiteralPath $resolvedPath `
            -Force `
            -ErrorAction Stop

    if (-not $source.PSIsContainer) {
        throw (
            "'$resolvedPath' is a file. " +
            'Use zip-file for files.'
        )
    }

    if ($null -eq $source.Parent) {
        throw (
            'Creating an archive of an entire filesystem root ' +
            'is not supported.'
        )
    }

    $sourceDirectory =
        $source.FullName.TrimEnd('\')

    $timestamp =
        Get-Date -Format 'yyyyMMdd-HHmmssfff'

    $defaultZipName =
        "$($source.Name)_$timestamp.zip"

    if ([string]::IsNullOrWhiteSpace($Destination)) {

        $archiveRoot =
            Join-Path `
                $source.Parent.FullName `
                'Archives'

        $zipPath =
            Join-Path `
                $archiveRoot `
                $defaultZipName
    }
    else {

        $resolvedDestination =
            $ExecutionContext.SessionState.Path.
                GetUnresolvedProviderPathFromPSPath(
                    $Destination
                )

        if (
            [System.IO.Path]::GetExtension(
                $resolvedDestination
            ) -ieq '.zip'
        ) {
            $zipPath =
                $resolvedDestination

            $archiveRoot =
                Split-Path `
                    -Path $zipPath `
                    -Parent
        }
        else {
            $archiveRoot =
                $resolvedDestination

            $zipPath =
                Join-Path `
                    $archiveRoot `
                    $defaultZipName
        }
    }

    $zipDirectory =
        (
            Split-Path `
                -Path $zipPath `
                -Parent
        ).TrimEnd('\')

    if (
        $zipDirectory.Equals(
            $sourceDirectory,
            [System.StringComparison]::OrdinalIgnoreCase
        ) -or
        $zipDirectory.StartsWith(
            $sourceDirectory + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw (
            'The ZIP archive cannot be created inside the source ' +
            'directory.'
        )
    }

    if (
        Test-Path `
            -LiteralPath $zipPath `
            -PathType Leaf
    ) {
        if (-not $Force) {
            throw (
                "ZIP archive already exists: $zipPath. " +
                'Use -Force to replace it.'
            )
        }
    }

    $sourceFiles = @(
        Get-ChildItem `
            -LiteralPath $sourceDirectory `
            -File `
            -Recurse `
            -Force `
            -ErrorAction Stop
    )

    $sourceBytes =
        (
            $sourceFiles |
                Measure-Object `
                    -Property Length `
                    -Sum
        ).Sum

    if ($null -eq $sourceBytes) {
        $sourceBytes = 0
    }

    Write-Host ''
    Write-Host 'DIRECTORY ZIP ARCHIVE' -ForegroundColor Cyan
    Write-Host '=====================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "Source      : $sourceDirectory"
    Write-Host "Destination : $zipPath"
    Write-Host "Files       : $($sourceFiles.Count)"
    Write-Host "Source size : $sourceBytes bytes"
    Write-Host ''

    if (-not (
        $PSCmdlet.ShouldProcess(
            $zipPath,
            "Create ZIP archive from $sourceDirectory"
        )
    )) {
        return
    }

    if (-not (
        Test-Path `
            -LiteralPath $archiveRoot `
            -PathType Container
    )) {
        New-Item `
            -ItemType Directory `
            -Path $archiveRoot `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    if (
        Test-Path `
            -LiteralPath $zipPath `
            -PathType Leaf
    ) {
        Remove-Item `
            -LiteralPath $zipPath `
            -Force `
            -ErrorAction Stop
    }

    Add-Type `
        -AssemblyName System.IO.Compression `
        -ErrorAction SilentlyContinue

    Add-Type `
        -AssemblyName System.IO.Compression.FileSystem `
        -ErrorAction SilentlyContinue

    [System.IO.Compression.ZipFile]::CreateFromDirectory(
        $sourceDirectory,
        $zipPath,
        [System.IO.Compression.CompressionLevel]::Optimal,
        $true
    )

    $archive =
        [System.IO.Compression.ZipFile]::OpenRead(
            $zipPath
        )

    try {

        $fileEntries = @(
            $archive.Entries |
                Where-Object {
                    -not $_.FullName.EndsWith('/')
                }
        )

        $archiveBytes =
            (
                $fileEntries |
                    Measure-Object `
                        -Property Length `
                        -Sum
            ).Sum

        if ($null -eq $archiveBytes) {
            $archiveBytes = 0
        }

        if ($fileEntries.Count -ne $sourceFiles.Count) {
            throw (
                'ZIP verification failed: file counts do not match.'
            )
        }

        if ($archiveBytes -ne $sourceBytes) {
            throw (
                'ZIP verification failed: uncompressed byte counts ' +
                'do not match.'
            )
        }
    }
    finally {
        $archive.Dispose()
    }

    $zipItem =
        Get-Item `
            -LiteralPath $zipPath `
            -ErrorAction Stop

    $zipHash =
        (
            Get-FileHash `
                -LiteralPath $zipPath `
                -Algorithm SHA256 `
                -ErrorAction Stop
        ).Hash

    Write-Host ''
    Write-Host 'Directory ZIP archive verified successfully.' `
        -ForegroundColor Green
    Write-Host ''

    [pscustomobject]@{
        Type          = 'Directory ZIP'
        Source        = $sourceDirectory
        Destination   = $zipPath
        SourceFiles   = $sourceFiles.Count
        SourceBytes   = [int64]$sourceBytes
        ZipBytes      = $zipItem.Length
        ZipSHA256     = $zipHash
        Verified      = $true
        Created       = Get-Date
        Status        = 'SUCCESS'
    }
}

function global:Expand-DirectoryArchive {
    <#
    .SYNOPSIS
        Extracts a ZIP archive using a safe automatic destination.

    .DESCRIPTION
        Extracts a ZIP archive and automatically determines the most useful
        destination when -Destination is not supplied.

        DEFAULT BEHAVIOR:

        1. If the ZIP already contains exactly one top-level directory and
           no loose top-level files, the ZIP is extracted beside the archive.

           Example:

               Project.zip
                   Project\
                       src\
                       README.md

           becomes:

               Project\
                   src\
                   README.md

           This avoids creating:

               Project\Project\

        2. If the ZIP contains multiple top-level items or loose files, a
           directory named after the ZIP file is created.

           Example:

               Project.zip
                   README.md
                   config.ini
                   src\

           becomes:

               Project\
                   README.md
                   config.ini
                   src\

        3. If -Destination is supplied, that directory is used exactly as
           specified and automatic destination selection is disabled.

        Existing destination files are not overwritten unless -Force is used.

        Supports -WhatIf.

    .PARAMETER Path
        ZIP archive to extract.

    .PARAMETER Destination
        Optional directory to extract into.

        When omitted, the function inspects the ZIP contents and determines
        whether to extract beside the ZIP or create a directory named after
        the archive.

    .PARAMETER Force
        Allows files in an existing destination to be overwritten.

    .EXAMPLE
        unzip-dir .\Project.zip

    .EXAMPLE
        unzip-dir .\Project.zip -Destination C:\Temp\Project

    .EXAMPLE
        unzip-dir .\Project.zip -Force

    .EXAMPLE
        unzip-dir .\Project.zip -WhatIf
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Low'
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Destination,

        [switch]$Force
    )

    # -------------------------------------------------------------------------
    # Resolve and validate ZIP archive
    # -------------------------------------------------------------------------

    $resolvedPath =
        (
            Resolve-Path `
                -LiteralPath $Path `
                -ErrorAction Stop
        ).Path

    $archiveFile =
        Get-Item `
            -LiteralPath $resolvedPath `
            -Force `
            -ErrorAction Stop

    if ($archiveFile.PSIsContainer) {
        throw (
            "'$resolvedPath' is a directory. " +
            'Specify a .zip archive.'
        )
    }

    if ($archiveFile.Extension -ine '.zip') {
        throw (
            "Archive must be a .zip file: $resolvedPath"
        )
    }

    # -------------------------------------------------------------------------
    # Load ZIP support and inspect archive contents before extracting
    # -------------------------------------------------------------------------

    Add-Type `
        -AssemblyName System.IO.Compression `
        -ErrorAction SilentlyContinue

    Add-Type `
        -AssemblyName System.IO.Compression.FileSystem `
        -ErrorAction SilentlyContinue

    $zip =
        [System.IO.Compression.ZipFile]::OpenRead(
            $archiveFile.FullName
        )

    try {

        $entries = @(
            $zip.Entries
        )

        if ($entries.Count -eq 0) {
            throw (
                "ZIP archive is empty: $($archiveFile.FullName)"
            )
        }

        # Get meaningful archive paths.
        #
        # ZIP paths use "/" regardless of Windows path separators.

        $entryPaths = @(
            $entries |
                ForEach-Object {
                    $_.FullName.Trim('/')
                } |
                Where-Object {
                    -not [string]::IsNullOrWhiteSpace($_)
                }
        )

        # Determine each top-level name.

        $topLevelNames = @(
            $entryPaths |
                ForEach-Object {
                    ($_ -split '/')[0]
                } |
                Sort-Object -Unique
        )

        # A top-level file has no "/" in its archive path.

        $topLevelFiles = @(
            $entries |
                Where-Object {
                    -not $_.FullName.EndsWith('/') -and
                    $_.FullName.Trim('/').IndexOf('/') -lt 0
                }
        )

        # ZIP contains exactly one top-level directory when:
        #
        #   - only one unique top-level name exists
        #   - there are no loose files at the archive root

        $hasSingleTopLevelDirectory =
            $topLevelNames.Count -eq 1 -and
            $topLevelFiles.Count -eq 0

        $singleTopLevelName =
            if ($hasSingleTopLevelDirectory) {
                $topLevelNames[0]
            }
            else {
                $null
            }

        $fileEntries = @(
            $entries |
                Where-Object {
                    -not $_.FullName.EndsWith('/')
                }
        )

        $uncompressedBytes =
            (
                $fileEntries |
                    Measure-Object `
                        -Property Length `
                        -Sum
            ).Sum

        if ($null -eq $uncompressedBytes) {
            $uncompressedBytes = 0
        }
    }
    finally {
        $zip.Dispose()
    }

    # -------------------------------------------------------------------------
    # Determine extraction destination
    # -------------------------------------------------------------------------

    $archiveParent =
        $archiveFile.DirectoryName

    $archiveBaseName =
        $archiveFile.BaseName

    $automaticMode =
        [string]::IsNullOrWhiteSpace(
            $Destination
        )

    if (-not $automaticMode) {

        # Explicit destination:
        #
        #     unzip-dir file.zip -Destination C:\Temp\Output

        $destinationDirectory =
            $ExecutionContext.SessionState.Path.
                GetUnresolvedProviderPathFromPSPath(
                    $Destination
                )

        $destinationReason =
            'EXPLICIT DESTINATION'
    }
    elseif ($hasSingleTopLevelDirectory) {

        # The ZIP already contains its own wrapper directory.
        #
        # Extract into the archive's parent so we do not create:
        #
        #     Project\Project\

        $destinationDirectory =
            $archiveParent

        $finalContentDirectory =
            Join-Path `
                $archiveParent `
                $singleTopLevelName

        $destinationReason =
            'ZIP ALREADY CONTAINS ONE TOP-LEVEL DIRECTORY'
    }
    else {

        # Loose files or multiple top-level items need containment.
        #
        # Create a directory named after the ZIP.

        $destinationDirectory =
            Join-Path `
                $archiveParent `
                $archiveBaseName

        $finalContentDirectory =
            $destinationDirectory

        $destinationReason =
            'CREATING DIRECTORY TO CONTAIN ZIP CONTENTS'
    }

    if (-not $automaticMode) {
        $finalContentDirectory =
            $destinationDirectory
    }

    # -------------------------------------------------------------------------
    # Display extraction plan
    # -------------------------------------------------------------------------

    Write-Host ''
    Write-Host 'ZIP EXTRACTION' `
        -ForegroundColor Cyan

    Write-Host '==============' `
        -ForegroundColor Cyan

    Write-Host ''

    Write-Host "Archive      : $($archiveFile.FullName)"
    Write-Host "Files        : $($fileEntries.Count)"
    Write-Host "Size         : $uncompressedBytes bytes"

    Write-Host ''

    Write-Host "Mode         : $destinationReason"

    if ($hasSingleTopLevelDirectory) {
        Write-Host "Top folder   : $singleTopLevelName"
    }

    Write-Host "Extract to   : $destinationDirectory"
    Write-Host "Final content: $finalContentDirectory"

    Write-Host ''

    # -------------------------------------------------------------------------
    # Check destination conflicts
    # -------------------------------------------------------------------------

    if (
        $automaticMode -and
        $hasSingleTopLevelDirectory
    ) {

        if (
            Test-Path `
                -LiteralPath $finalContentDirectory
        ) {

            if (-not $Force) {
                throw (
                    "Destination already exists: " +
                    "$finalContentDirectory. " +
                    'Use -Force to allow extraction into it.'
                )
            }
        }
    }
    elseif (
        Test-Path `
            -LiteralPath $destinationDirectory `
            -PathType Container
    ) {

        $existingItems = @(
            Get-ChildItem `
                -LiteralPath $destinationDirectory `
                -Force `
                -ErrorAction Stop
        )

        if (
            $existingItems.Count -gt 0 -and
            -not $Force
        ) {
            throw (
                "Destination is not empty: " +
                "$destinationDirectory. " +
                'Use -Force to allow overwrite.'
            )
        }
    }

    # -------------------------------------------------------------------------
    # WhatIf / confirmation support
    # -------------------------------------------------------------------------

    if (-not (
        $PSCmdlet.ShouldProcess(
            $destinationDirectory,
            "Extract $($archiveFile.FullName)"
        )
    )) {
        return
    }

    # -------------------------------------------------------------------------
    # Create explicit/container destination when necessary
    # -------------------------------------------------------------------------

    if (-not (
        Test-Path `
            -LiteralPath $destinationDirectory `
            -PathType Container
    )) {

        New-Item `
            -ItemType Directory `
            -Path $destinationDirectory `
            -Force `
            -ErrorAction Stop |
            Out-Null
    }

    # -------------------------------------------------------------------------
    # Extract ZIP
    #
    # Expand-Archive handles file creation and -Force allows replacement
    # when explicitly requested.
    # -------------------------------------------------------------------------

    $expandParameters = @{
        LiteralPath = $archiveFile.FullName
        DestinationPath = $destinationDirectory
        ErrorAction = 'Stop'
    }

    if ($Force) {
        $expandParameters.Force = $true
    }

    Expand-Archive @expandParameters

    # -------------------------------------------------------------------------
    # Verify expected destination exists
    # -------------------------------------------------------------------------

    if (-not (
        Test-Path `
            -LiteralPath $finalContentDirectory
    )) {
        throw (
            'ZIP extraction completed, but the expected destination ' +
            "was not found: $finalContentDirectory"
        )
    }

    # Count extracted files for the final report.

    if (
        Test-Path `
            -LiteralPath $finalContentDirectory `
            -PathType Container
    ) {
        $extractedFiles = @(
            Get-ChildItem `
                -LiteralPath $finalContentDirectory `
                -File `
                -Recurse `
                -Force `
                -ErrorAction Stop
        )
    }
    else {
        $extractedFiles = @(
            Get-Item `
                -LiteralPath $finalContentDirectory `
                -ErrorAction Stop
        )
    }

    Write-Host ''
    Write-Host 'ZIP extraction completed successfully.' `
        -ForegroundColor Green

    Write-Host ''

    Write-Host "Archive      : $($archiveFile.FullName)"
    Write-Host "Destination  : $finalContentDirectory"
    Write-Host "Files        : $($extractedFiles.Count)"

    Write-Host ''

    [pscustomobject]@{
        Type            = 'ZIP Extraction'
        Archive         = $archiveFile.FullName
        Destination     = $finalContentDirectory
        ExtractionRoot  = $destinationDirectory
        Automatic       = $automaticMode
        SingleRoot      = $hasSingleTopLevelDirectory
        RootName        = $singleTopLevelName
        FileCount       = $extractedFiles.Count
        Completed       = Get-Date
        Status          = 'SUCCESS'
    }
}

function global:Clear-DirectoryContents {
    <#
    .SYNOPSIS
        Removes all contents from a directory while preserving the directory.

    .DESCRIPTION
        Deletes all files, hidden items, and subdirectories contained within
        the specified directory.

        The target directory itself is preserved.

        If no path is supplied, the current directory is used.

        The function supports -WhatIf and -Confirm and refuses to clear a
        filesystem root such as C:\.

    .PARAMETER Path
        Directory whose contents should be removed.

        Defaults to the current directory.

    .EXAMPLE
        clear-dir

        Clears the current directory.

    .EXAMPLE
        clear-dir "C:\Users\mil00001\Pictures\Screenshots"

        Removes everything inside the Screenshots directory while preserving
        the Screenshots directory itself.

    .EXAMPLE
        clear-dir "C:\Users\mil00001\Pictures\Screenshots" -WhatIf

        Previews what would be removed without deleting anything.

    .EXAMPLE
        clear-dir .\temp -Confirm

        Clears the temp directory and explicitly requests confirmation.
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [Parameter(
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [ValidateNotNullOrEmpty()]
        [string]$Path = '.'
    )

    process {
        $target = Get-Item `
            -LiteralPath $Path `
            -Force `
            -ErrorAction Stop

        if (-not $target.PSIsContainer) {
            throw "Path is not a directory: $($target.FullName)"
        }

        $fullPath = $target.FullName

        $rootPath = [System.IO.Path]::GetPathRoot($fullPath)

        if (
            $fullPath.TrimEnd('\') -eq
            $rootPath.TrimEnd('\')
        ) {
            throw (
                "Refusing to clear filesystem root: $fullPath"
            )
        }

        $items = @(
            Get-ChildItem `
                -LiteralPath $fullPath `
                -Force `
                -ErrorAction Stop
        )

        if ($items.Count -eq 0) {
            Write-Host "Directory is already empty: $fullPath"
            return
        }

        Write-Host ''
        Write-Host 'CLEAR DIRECTORY' -ForegroundColor Cyan
        Write-Host '===============' -ForegroundColor Cyan
        Write-Host "Directory: $fullPath"
        Write-Host "Items:     $($items.Count)"
        Write-Host ''

        foreach ($item in $items) {
            if (
                $PSCmdlet.ShouldProcess(
                    $item.FullName,
                    'Remove'
                )
            ) {
                Remove-Item `
                    -LiteralPath $item.FullName `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }
        }

        if (-not $WhatIfPreference) {
            Write-Host ''
            Write-Host (
                "Directory cleared successfully: $fullPath"
            ) -ForegroundColor Green
        }
    }
}

function global:Get-AllChildItem {
    <#
    .SYNOPSIS
        Lists all files and directories, including hidden items.

    .EXAMPLE
        la

    .EXAMPLE
        la C:\Development-CPRS
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.'
    )

    Get-ChildItem -Path $Path -Force
}


function global:Set-ParentLocation {
    <#
    .SYNOPSIS
        Moves up one directory.

    .EXAMPLE
        up
    #>

    [CmdletBinding()]
    param()

    Set-LocationAndGitPull ..
}


function global:Set-GrandparentLocation {
    <#
    .SYNOPSIS
        Moves up two directories.

    .EXAMPLE
        up2
    #>

    [CmdletBinding()]
    param()

    Set-LocationAndGitPull ..\..
}

function global:Set-HomeLocation {
    <#
    .SYNOPSIS
        Opens the current user's home directory.

    .EXAMPLE
        home
    #>

    [CmdletBinding()]
    param()

    Set-LocationAndGitPull -Path $HOME
}


function global:Open-CurrentDirectory {
    <#
    .SYNOPSIS
        Opens the current directory in Windows File Explorer.

    .EXAMPLE
        here
    #>

    [CmdletBinding()]
    param()

    Invoke-Item .
}


function global:Open-CurrentDirectoryInCode {
    <#
    .SYNOPSIS
        Opens the current directory in Visual Studio Code.

    .EXAMPLE
        codehere
    #>

    [CmdletBinding()]
    param()

    if ($null -eq (Get-Command code -ErrorAction SilentlyContinue)) {
        Write-Warning 'Visual Studio Code is not available in PATH.'
        return
    }

    & code .
}


function global:Get-PathEntry {
    <#
    .SYNOPSIS
        Displays PATH entries one per line.

    .EXAMPLE
        path
    #>

    [CmdletBinding()]
    param()

    $env:PATH -split ';' |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}


function global:Start-ElevatedPowerShell {
    <#
    .SYNOPSIS
        Opens a new elevated PowerShell 7 session.

    .EXAMPLE
        admin
    #>

    [CmdletBinding()]
    param()

    $pwsh = (Get-Command pwsh -ErrorAction Stop).Source

    Start-Process `
        -FilePath $pwsh `
        -Verb RunAs
}


function global:Set-GitRepositoryRoot {
    <#
    .SYNOPSIS
        Moves to the root directory of the current Git repository.

    .EXAMPLE
        groot
    #>

    [CmdletBinding()]
    param()

    if (-not (Test-GitRepository)) {
        Write-Warning 'The current directory is not inside a Git repository.'
        return
    }

    $repositoryRoot = & git rev-parse --show-toplevel

    if ($LASTEXITCODE -ne 0 -or
        [string]::IsNullOrWhiteSpace($repositoryRoot)) {
        Write-Warning 'Unable to determine the Git repository root.'
        return
    }

    Set-LocationAndGitPull -Path $repositoryRoot
}

function global:Get-LongTimeListing {
    <#
    .SYNOPSIS
        Displays a detailed directory listing sorted by modification time.

    .DESCRIPTION
        PowerShell equivalent of:

            ls -ltr

        Displays the oldest modified items first and the newest items last.

    .PARAMETER Path
        Directory to list. Defaults to the current directory.

    .EXAMPLE
        ltr

    .EXAMPLE
        ltr C:\Development-CPRS
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.'
    )

    Get-ChildItem -Path $Path -Force |
        Sort-Object LastWriteTime |
        Format-Table `
            Mode,
            LastWriteTime,
            Length,
            Name `
            -AutoSize
}


function global:Show-DirectoryTree {
    <#
    .SYNOPSIS
        Displays a directory tree.

    .DESCRIPTION
        Displays the folder hierarchy beneath a directory using the Windows
        tree command.

        By default only directories are displayed. Use -Files to include files.

    .PARAMETER Path
        Directory to display. Defaults to the current directory.

    .PARAMETER Files
        Includes files in the tree.

    .EXAMPLE
        dtree

    .EXAMPLE
        dtree C:\Development-CPRS

    .EXAMPLE
        dtree -Files

    .EXAMPLE
        dtree C:\Development-CPRS -Files
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [switch]$Files
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "Directory is not available: $Path"
        return
    }

    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path

    if ($Files) {
        & tree.com $resolvedPath /F /A
    }
    else {
        & tree.com $resolvedPath /A
    }
}

function global:Clear-UserRecycleBin {
    <#
    .SYNOPSIS
        Empties the Windows Recycle Bin.

    .DESCRIPTION
        Permanently removes items currently stored in the Windows Recycle Bin
        for the current user.

        Supports -WhatIf and -Confirm so the operation can be previewed before
        anything is permanently deleted.

    .EXAMPLE
        clear-bin

        Empties the Recycle Bin.

    .EXAMPLE
        clear-bin -WhatIf

        Previews the Recycle Bin operation without deleting anything.

    .EXAMPLE
        clear-bin -Confirm

        Empties the Recycle Bin with explicit confirmation.
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'High'
    )]
    param()

    if ($null -eq (
        Get-Command `
            -Name Clear-RecycleBin `
            -ErrorAction SilentlyContinue
    )) {
        throw 'Clear-RecycleBin is not available on this system.'
    }

    if (
        $PSCmdlet.ShouldProcess(
            'Windows Recycle Bin',
            'Permanently remove all Recycle Bin contents'
        )
    ) {
        Clear-RecycleBin `
            -Force `
            -ErrorAction Stop

        Write-Host ''
        Write-Host 'Recycle Bin cleared successfully.' `
            -ForegroundColor Green
    }
}

# =============================================================================
# Alias registry and help menu
# =============================================================================

function global:Get-ProfileAliasDefinition {
    <#
    .SYNOPSIS
        Returns the aliases managed by this profile.
    #>

    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{
            Category    = 'Profile'
            Alias       = 'phelp'
            Command     = 'Show-ProfileHelp'
            Description = 'Display the profile help menu'
        }
        [pscustomobject]@{
            Category    = 'Profile'
            Alias       = 'palias'
            Command     = 'Get-ProfileAlias'
            Description = 'List or search profile aliases'
        }
        [pscustomobject]@{
            Category    = 'Profile'
            Alias       = 'ppath'
            Command     = 'Get-ProfilePath'
            Description = 'Display the active profile path'
        }
        [pscustomobject]@{
            Category    = 'Profile'
            Alias       = 'eprof'
            Command     = 'Edit-Profile'
            Description = 'Open the PowerShell development workspace in Visual Studio Code'
        }
        [pscustomobject]@{
            Category    = 'Profile'
            Alias       = 'rprof'
            Command     = 'Import-Profile'
            Description = 'Reload the profile in the current shell'
        }


        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'pdir'
            Command     = 'Set-PowerShellProfileDirectory'
            Description = 'Open the PowerShell profile development directory'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predcd'
            Command     = 'Set-ProfileAliasPredictorDirectory'
            Description = 'Open the ProfileAliasPredictor project directory'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predcmd'
            Command     = 'Open-ProfileAliasPredictorCommandPrompt'
            Description = 'Open Command Prompt in the predictor project'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predbuild'
            Command     = 'Build-ProfileAliasPredictor'
            Description = 'Build ProfileAliasPredictor in Release mode'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predkill'
            Command     = 'Stop-ProfilePowerShellProcesses'
            Description = 'Stop all PowerShell 7 processes to release the predictor DLL'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predrebuild'
            Command     = 'Invoke-ProfileAliasPredictorRebuild'
            Description = 'Stop PowerShell and rebuild ProfileAliasPredictor in Release mode'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predinfo'
            Command     = 'Get-ProfileAliasPredictorInfo'
            Description = 'Display ProfileAliasPredictor project and build information'
        }
        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'predtest'
            Command     = 'Test-ProfileAliasPredictor'
            Description = 'Verify the PowerShell profile and predictor configuration'
        }


        [pscustomobject]@{
            Category    = 'History'
            Alias       = 'hpath'
            Command     = 'Get-CommandHistoryPath'
            Description = 'Display the persistent history-file path'
        }
        [pscustomobject]@{
            Category    = 'History'
            Alias       = 'hsearch'
            Command     = 'Search-CommandHistory'
            Description = 'Search persistent PowerShell command history'
        }
        [pscustomobject]@{
            Category    = 'History'
            Alias       = 'ehist'
            Command     = 'Edit-CommandHistory'
            Description = 'Open persistent command history in VS Code'
        }

        [pscustomobject]@{
            Category    = 'Prediction'
            Alias       = 'histon'
            Command     = 'Enable-HistoryPrediction'
            Description = 'Enable history-based command suggestions'
        }
        [pscustomobject]@{
            Category    = 'Prediction'
            Alias       = 'histoff'
            Command     = 'Disable-HistoryPrediction'
            Description = 'Hide history suggestions without deleting history'
        }
        [pscustomobject]@{
            Category    = 'Prediction'
            Alias       = 'predon'
            Command     = 'Enable-PluginPrediction'
            Description = 'Enable ProfileAliases and other predictor plug-ins'
        }
        [pscustomobject]@{
            Category    = 'Prediction'
            Alias       = 'predoff'
            Command     = 'Disable-PluginPrediction'
            Description = 'Disable predictor plug-ins'
        }
        [pscustomobject]@{
            Category    = 'Prediction'
            Alias       = 'predstate'
            Command     = 'Get-ProfilePredictionStatus'
            Description = 'Display the current prediction configuration'
        }

        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'c'
            Command     = 'Clear-Host'
            Description = 'Clear the PowerShell console'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'which'
            Command     = 'Get-Command'
            Description = 'Find a command, alias, function, or executable'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'la'
            Command     = 'Get-AllChildItem'
            Description = 'List all files and directories, including hidden items'
        }       
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'up'
            Command     = 'Set-ParentLocation'
            Description = 'Move up one directory'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'up2'
            Command     = 'Set-GrandparentLocation'
            Description = 'Move up two directories'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'home'
            Command     = 'Set-HomeLocation'
            Description = 'Open the current user home directory'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'here'
            Command     = 'Open-CurrentDirectory'
            Description = 'Open the current directory in File Explorer'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'codehere'
            Command     = 'Open-CurrentDirectoryInCode'
            Description = 'Open the current directory in Visual Studio Code'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'path'
            Command     = 'Get-PathEntry'
            Description = 'Display PATH entries one per line'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'admin'
            Command     = 'Start-ElevatedPowerShell'
            Description = 'Open an elevated PowerShell 7 session'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'groot'
            Command     = 'Set-GitRepositoryRoot'
            Description = 'Move to the root of the current Git repository'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'ltr'
            Command     = 'Get-LongTimeListing'
            Description = 'Detailed listing sorted oldest to newest like ls -ltr'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'dtree'
            Command     = 'Show-DirectoryTree'
            Description = 'Display a directory tree; use -Files to include files'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'backup-file'
            Command     = 'New-FileBackup'
            Description = 'Create a verified timestamped backup of a file'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'backup-dir'
            Command     = 'New-DirectoryBackup'
            Description = 'Create a verified timestamped backup of a directory'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'zip-file'
            Command     = 'Compress-FileArchive'
            Description = 'Create and verify a ZIP archive containing one file'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'zip-dir'
            Command     = 'Compress-DirectoryArchive'
            Description = 'Create and verify a ZIP archive of a directory'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'unzip'
            Command     = 'Expand-DirectoryArchive'
            Description = 'Extract a ZIP using automatic destination selection'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'clear-dir'
            Command     = 'Clear-DirectoryContents'
            Description = 'Remove all contents from a directory while preserving the directory'
        }
        [pscustomobject]@{
            Category    = 'Utilities'
            Alias       = 'clear-bin'
            Command     = 'Clear-UserRecycleBin'
            Description = 'Permanently empty the Windows Recycle Bin'
        }


        [pscustomobject]@{
            Category    = 'CPRS'
            Alias       = 'cprs-build'
            Command     = 'Build-CprsRelease'
            Description = 'Build the CPRS client solution in Release mode'
        }
        [pscustomobject]@{
            Category    = 'CPRS'
            Alias       = 'cprs-test-deploy'
            Command     = 'Deploy-CprsTestClient'
            Description = 'Build or deploy the CPRS client to V:\TEST\EXE'
        }
        [pscustomobject]@{
            Category    = 'CPRS'
            Alias       = 'cprs-prod-deploy'
            Command     = 'Deploy-CprsProductionClient'
            Description = 'Promote a verified CPRS TEST build to production'
        }
        [pscustomobject]@{
            Category    = 'CPRS'
            Alias       = 'cprs-ce-deploy'
            Command     = 'Invoke-CprsDeployment'
            Description = 'Preview or deploy CE Residential Improvements between CPRS environments'
        }

        [pscustomobject]@{
            Category    = 'Development'
            Alias       = 'cdev'
            Command     = 'Set-DevelopmentRoot'
            Description = 'Open C:\Development-CPRS'
        }
        [pscustomobject]@{
            Category    = 'Development'
            Alias       = 'csas'
            Command     = 'Set-SasProgramsRepository'
            Description = 'Open the local cprs-sasprogs repository'
        }
        [pscustomobject]@{
            Category    = 'Development'
            Alias       = 'cbatch'
            Command     = 'Set-BatchRepository'
            Description = 'Open the local cprs-batch repository'
        }
        [pscustomobject]@{
            Category    = 'Development'
            Alias       = 'fileops'
            Command     = 'Open-FileOpsWorkspace'
            Description = 'Open the FileOps Manager VS Code workspace'
        }


        [pscustomobject]@{
            Category    = 'ProfileDev'
            Alias       = 'epred'
            Command     = 'Open-ProfileAliasPredictorProject'
            Description = 'Open the ProfileAliasPredictor project in VS Code'
        }


        [pscustomobject]@{
            Category    = 'Production'
            Alias       = 'pbatch'
            Command     = 'Set-ProductionBatchDirectory'
            Description = 'Open V:\PROD\BATCH'
        }
        [pscustomobject]@{
            Category    = 'Production'
            Alias       = 'psas'
            Command     = 'Set-ProductionSasProgramsDirectory'
            Description = 'Open V:\PROD\SASPRGS'
        }
        [pscustomobject]@{
            Category    = 'Production'
            Alias       = 'plogs'
            Command     = 'Set-ProductionSasLogsDirectory'
            Description = 'Open V:\PROD\LOGS\SASLOGS'
        }

        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'gst'
            Command     = 'Get-GitRepositoryStatus'
            Description = 'Show the current branch and repository status'
        }
        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'glog'
            Command     = 'Get-GitRecentCommit'
            Description = 'Show recent commits, dates, and changed files'
        }
        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'gfile'
            Command     = 'Get-GitChangedFile'
            Description = 'Show staged, unstaged, and untracked files'
        }
        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'gitpullon'
            Command     = 'Enable-GitAutoPull'
            Description = 'Enable automatic git pull when entering repositories'
        }    
        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'gitpulloff'
            Command     = 'Disable-GitAutoPull'
            Description = 'Disable automatic git pull when entering repositories'
        }        
        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'gitpullstate'
            Command     = 'Get-GitAutoPullStatus'
            Description = 'Display Git auto-pull status'
        }        
        [pscustomobject]@{
            Category    = 'Git'
            Alias       = 'cd'
            Command     = 'Set-LocationAndGitPull'
            Description = 'Change directory and automatically pull a newly entered Git repository'
        }
    )
}

# =============================================================================
# Prediction controls
# =============================================================================

function global:Get-ProfilePredictionStatus {
    <#
    .SYNOPSIS
        Displays the current history and plug-in prediction status.

    .EXAMPLE
        Get-ProfilePredictionStatus

    .EXAMPLE
        predstate
    #>

    [CmdletBinding()]
    param()

    if ($null -eq (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue)) {
        Write-Warning 'PSReadLine is not available in this session.'
        return
    }

    $source = [string](Get-PSReadLineOption).PredictionSource

    [pscustomobject]@{
        HistoryPredictions = $source -in @(
            'History',
            'HistoryAndPlugin'
        )
        PluginPredictions  = $source -in @(
            'Plugin',
            'HistoryAndPlugin'
        )
        PredictionSource   = $source
        PredictionView     = [string](Get-PSReadLineOption).PredictionViewStyle
    }
}


function global:Set-ProfilePredictionFeature {
    <#
    .SYNOPSIS
        Enables or disables one PSReadLine prediction source.

    .PARAMETER Feature
        Prediction source to change: History or Plugin.

    .PARAMETER Enabled
        Indicates whether the selected source should be enabled.
    #>

    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('History', 'Plugin')]
        [string]$Feature,

        [Parameter(Mandatory)]
        [bool]$Enabled
    )

    if ($null -eq (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue)) {
        Write-Warning 'PSReadLine is not available in this session.'
        return
    }

    $currentSource = [string](Get-PSReadLineOption).PredictionSource

    $historyEnabled = $currentSource -in @(
        'History',
        'HistoryAndPlugin'
    )

    $pluginEnabled = $currentSource -in @(
        'Plugin',
        'HistoryAndPlugin'
    )

    switch ($Feature) {
        'History' {
            $historyEnabled = $Enabled
        }

        'Plugin' {
            $pluginEnabled = $Enabled
        }
    }

    $newSource = if ($historyEnabled -and $pluginEnabled) {
        'HistoryAndPlugin'
    }
    elseif ($historyEnabled) {
        'History'
    }
    elseif ($pluginEnabled) {
        'Plugin'
    }
    else {
        'None'
    }

    Set-PSReadLineOption `
        -PredictionSource $newSource `
        -PredictionViewStyle ListView

    Get-ProfilePredictionStatus
}


function global:Enable-HistoryPrediction {
    <#
    .SYNOPSIS
        Enables history-based command predictions.

    .EXAMPLE
        histon
    #>

    [CmdletBinding()]
    param()

    Set-ProfilePredictionFeature -Feature History -Enabled $true
}


function global:Disable-HistoryPrediction {
    <#
    .SYNOPSIS
        Hides history-based predictions without deleting command history.

    .EXAMPLE
        histoff
    #>

    [CmdletBinding()]
    param()

    Set-ProfilePredictionFeature -Feature History -Enabled $false
}


function global:Enable-PluginPrediction {
    <#
    .SYNOPSIS
        Enables registered predictor plug-ins, including ProfileAliases.

    .EXAMPLE
        predon
    #>

    [CmdletBinding()]
    param()

    Set-ProfilePredictionFeature -Feature Plugin -Enabled $true
}


function global:Disable-PluginPrediction {
    <#
    .SYNOPSIS
        Disables predictor plug-ins while preserving history predictions.

    .EXAMPLE
        predoff
    #>

    [CmdletBinding()]
    param()

    Set-ProfilePredictionFeature -Feature Plugin -Enabled $false
}


function global:Get-ProfileAlias {
    <#
    .SYNOPSIS
        Lists or searches aliases managed by this profile.

    .PARAMETER Name
        Alias-name pattern. Wildcards are supported. The default is '*'.

    .PARAMETER Category
        Limits results to one command category.

    .EXAMPLE
        Get-ProfileAlias

    .EXAMPLE
        palias 'p*'

    .EXAMPLE
        palias -Category Git
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name = '*',

       [ValidateSet(
            'Profile',
            'ProfileDev',
            'History',
            'Prediction',
            'Utilities',
            'CPRS',
            'Development',
            'Production',
            'Git'
        )]
        [string]$Category
    )

    $definitions = Get-ProfileAliasDefinition |
        Where-Object Alias -Like $Name

    if ($Category) {
        $definitions = $definitions |
            Where-Object Category -EQ $Category
    }

    $definitions |
        Sort-Object Category, Alias
}


function global:Show-ProfileHelp {
    <#
    .SYNOPSIS
        Displays the profile command and alias help menu.

    .PARAMETER Category
        Optionally displays only one command category.

    .EXAMPLE
        Show-ProfileHelp

    .EXAMPLE
        phelp

    .EXAMPLE
        phelp Git
    #>

    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ValidateSet(
            'Profile',
            'ProfileDev',
            'History',
            'Prediction',
            'Utilities',
            'CPRS',
            'Development',
            'Production',
            'Git'
        )]
        [string]$Category
    )

    $definitions = Get-ProfileAliasDefinition

    if ($Category) {
        $definitions = $definitions |
            Where-Object Category -EQ $Category
    }

    Write-Host ''
    Write-Host 'POWERSHELL PROFILE HELP' -ForegroundColor Cyan
    Write-Host '=======================' -ForegroundColor Cyan

    foreach ($group in ($definitions | Sort-Object Category, Alias | Group-Object Category)) {
        Write-Host ''
        Write-Host $group.Name.ToUpperInvariant() -ForegroundColor Yellow

        $group.Group |
            Select-Object Alias, Description, Command |
            Format-Table -AutoSize -Wrap |
            Out-Host
    }

    if (-not $Category -or $Category -eq 'ProfileDev') {
        Write-Host ''
        Write-Host 'PROFILE DEVELOPMENT WORKFLOW' -ForegroundColor Yellow
        Write-Host ''

        Write-Host 'PowerShell profile.ps1' -ForegroundColor Cyan
        Write-Host '  1. pdir        Go to the PowerShell profile directory'
        Write-Host '  2. eprof       Open the PowerShell development workspace in Visual Studio Code'
        Write-Host '  3. Edit and save profile.ps1'
        Write-Host '  4. rprof       Reload the profile'
        Write-Host '  5. Test the changed aliases or functions'
        Write-Host ''

        Write-Host 'ProfileAliasPredictor .NET project' -ForegroundColor Cyan
        Write-Host '  1. predcd       Go to the ProfileAliasPredictor project'
        Write-Host '  2. epred     Open the project in Visual Studio Code'
        Write-Host '  3. Edit and save ProfileAliasPredictor.cs'
        Write-Host '  4. predrebuild  Close PowerShell and rebuild the predictor'
        Write-Host '  5. Open a new PowerShell 7 window'
        Write-Host '  6. predstate    Verify HistoryAndPlugin prediction is enabled'
        Write-Host '  7. Type part of an alias to test ProfileAliases suggestions'
        Write-Host ''

        Write-Host 'BUILD COMMANDS' -ForegroundColor Cyan
        Write-Host '  predbuild      Build the predictor when the DLL is not locked'
        Write-Host '  predrebuild    Kill PowerShell processes and rebuild in CMD'
        Write-Host '  predcmd        Open CMD directly in the predictor project'
        Write-Host ''

        Write-Host 'VERIFY COMMANDS' -ForegroundColor Cyan
        Write-Host '  predinfo       Display predictor paths and DLL build information'
        Write-Host '  predtest       Verify DLL, module, predictor, PSReadLine, and aliases'
        Write-Host '  predstate      Display the current prediction configuration'
        Write-Host ''

        Write-Host 'PROCESS COMMANDS' -ForegroundColor Cyan
        Write-Host '  predkill       Stop all PowerShell 7 processes'
        Write-Host '  predkill -Force'
        Write-Host '                 Stop them without confirmation'
        Write-Host ''

        Write-Host 'IMPORTANT' -ForegroundColor Cyan
        Write-Host '  predkill and predrebuild close ALL PowerShell 7 windows.'
        Write-Host '  Save work in every PowerShell session before using them.'
        Write-Host ''
    }

    if (-not $Category -or $Category -eq 'Utilities') {

        Write-Host ''
        Write-Host 'BACKUP AND ARCHIVE UTILITIES' `
            -ForegroundColor Yellow
        Write-Host ''
    
        Write-Host 'BACK UP A FILE' -ForegroundColor Cyan
        Write-Host '  backup-file <file>'
        Write-Host '  backup-file <file> -Destination <directory>'
        Write-Host '  backup-file <file> -WhatIf'
        Write-Host ''
        Write-Host '  Default destination:'
        Write-Host '    <source directory>\Backups'
        Write-Host ''
    
        Write-Host 'BACK UP A DIRECTORY' -ForegroundColor Cyan
        Write-Host '  backup-dir <directory>'
        Write-Host '  backup-dir <directory> -Destination <directory>'
        Write-Host '  backup-dir <directory> -WhatIf'
        Write-Host '  backup-dir <directory> -SkipHashVerification'
        Write-Host ''
        Write-Host '  Default destination:'
        Write-Host '    <source parent>\Backups'
        Write-Host ''
    
        Write-Host 'ZIP A FILE' -ForegroundColor Cyan
        Write-Host '  zip-file <file>'
        Write-Host '  zip-file <file> -Destination <directory>'
        Write-Host '  zip-file <file> -Destination <archive.zip>'
        Write-Host '  zip-file <file> -WhatIf'
        Write-Host ''
    
        Write-Host 'ZIP A DIRECTORY' -ForegroundColor Cyan
        Write-Host '  zip-dir <directory>'
        Write-Host '  zip-dir <directory> -Destination <directory>'
        Write-Host '  zip-dir <directory> -Destination <archive.zip>'
        Write-Host '  zip-dir <directory> -WhatIf'
        Write-Host ''
    
        Write-Host 'DEFAULT ARCHIVE LOCATION' -ForegroundColor Cyan
        Write-Host '  Files       -> <source directory>\Archives'
        Write-Host '  Directories -> <source parent>\Archives'
        Write-Host ''
    
        Write-Host 'VERIFICATION' -ForegroundColor Cyan
        Write-Host '  backup-file'
        Write-Host '      File size + SHA256'
        Write-Host ''
        Write-Host '  backup-dir'
        Write-Host '      Relative path + size + SHA256 for every file'
        Write-Host ''
        Write-Host '  zip-file'
        Write-Host '      Archived entry + size + SHA256'
        Write-Host ''
        Write-Host '  zip-dir'
        Write-Host '      File count + uncompressed byte count + ZIP SHA256'
        Write-Host ''
    }

    if (-not $Category -or $Category -eq 'CPRS') {
        Write-Host ''
        Write-Host 'CPRS CLIENT BUILD' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  cprs-build'
        Write-Host '      Rebuild the CPRS client in Release mode.'
        Write-Host ''
        Write-Host '      Solution:'
        Write-Host '        C:\Development-CPRS\Cprs\cprs-client.sln'
        Write-Host ''
        Write-Host '      Build output:'
        Write-Host '        C:\Development-CPRS\Cprs\UI\bin\Release'
        Write-Host ''
    
        Write-Host 'CPRS TEST CLIENT DEPLOYMENT' -ForegroundColor Yellow
        Write-Host ''
        Write-Host '  TEST root:'
        Write-Host '    V:\TEST\EXE'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy' -ForegroundColor Cyan
        Write-Host '      Build CPRS.'
        Write-Host '      Archive the existing V:\TEST\EXE\CPRS II build.'
        Write-Host '      Replace V:\TEST\EXE\CPRS II with the new build.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -SkipBuild' -ForegroundColor Cyan
        Write-Host '      Do NOT build CPRS.'
        Write-Host '      Use the existing local Release build.'
        Write-Host '      Archive the existing CPRS II build.'
        Write-Host '      Replace V:\TEST\EXE\CPRS II.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -Folder <folder>' -ForegroundColor Cyan
        Write-Host '      Build CPRS.'
        Write-Host '      Deploy to V:\TEST\EXE\<folder>.'
        Write-Host '      Replace the folder if it already exists.'
        Write-Host '      Do NOT touch CPRS II.'
        Write-Host '      Do NOT create a CPRS II archive.'
        Write-Host ''
        Write-Host '      Example:'
        Write-Host '        cprs-test-deploy -Folder <folder>'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -Folder <folder> -SkipBuild' -ForegroundColor Cyan
        Write-Host '      Do NOT build CPRS.'
        Write-Host '      Use the existing local Release build.'
        Write-Host '      Replace V:\TEST\EXE\<folder>.'
        Write-Host '      Do NOT touch CPRS II or Builds.'
        Write-Host ''
    
        Write-Host 'PREVIEW OPTIONS' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  cprs-test-deploy -WhatIf'
        Write-Host '      Preview deployment to CPRS II.'
        Write-Host '      Does not build, archive, delete, or copy anything.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -SkipBuild -WhatIf'
        Write-Host '      Preview using the existing Release build.'
        Write-Host '      Does not modify anything.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -Folder <folder> -WhatIf'
        Write-Host '      Preview a build/deployment to a custom TEST folder.'
        Write-Host '      Does not build or modify anything.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -Folder <folder> -SkipBuild -WhatIf'
        Write-Host '      Preview deploying the existing Release build'
        Write-Host '      to a custom TEST folder.'
        Write-Host '      Does not modify anything.'
        Write-Host ''
    
        Write-Host 'CPRS TEST DEPLOYMENT PARAMETERS' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  -Folder <folder>'
        Write-Host '      Deploy to V:\TEST\EXE\<folder> instead of CPRS II.'
        Write-Host '      CPRS II and Builds are never modified.'
        Write-Host ''
        Write-Host '  -SkipBuild'
        Write-Host '      Skip MSBuild and use the existing Release build.'
        Write-Host ''
        Write-Host '  -WhatIf'
        Write-Host '      Preview the operation without making changes.'
        Write-Host ''

        Write-Host 'CPRS PRODUCTION CLIENT DEPLOYMENT' `
            -ForegroundColor Yellow
        Write-Host ''

        Write-Host '  Default production deployment:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -Message "<deployment message>"'
        Write-Host ''
        Write-Host '      Source      : V:\TEST\EXE\CPRS II'
        Write-Host '      Destination : V:\PROD\EXE\CPRS II'
        Write-Host '      Archive     : V:\PROD\EXE\Builds'
        Write-Host ''

        Write-Host '  Deploy a named TEST build:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -Source <folder> -Message "<deployment message>"'
        Write-Host ''
        Write-Host '      Source resolves to:'
        Write-Host '        V:\TEST\EXE\<folder>'
        Write-Host ''
        Write-Host '      Destination defaults to:'
        Write-Host '        V:\PROD\EXE\CPRS II'
        Write-Host ''

        Write-Host '  Deploy to a custom PROD folder:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -DestinationFolder <folder> -Message "<deployment message>"'
        Write-Host ''
        Write-Host '      Example destination:'
        Write-Host '        V:\PROD\EXE\<folder>'
        Write-Host ''
        Write-Host '      Live V:\PROD\EXE\CPRS II is not modified.'
        Write-Host ''

        Write-Host '  Named TEST source and custom PROD destination:' `
            -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -Source <test-folder> -DestinationFolder <prod-folder> -Message "<deployment message>"'
        Write-Host ''

        Write-Host '  Complete TEST source path:' -ForegroundColor Cyan
        Write-Host "    cprs-prod-deploy -Source 'V:\TEST\EXE\<folder>' -Message `"<deployment message>`""
        Write-Host ''
        Write-Host '      The source path must remain underneath V:\TEST\EXE.'
        Write-Host ''

        Write-Host '  Folder parameter alias:' -ForegroundColor Cyan
        Write-Host '    -Folder is an alias for -Source.'
        Write-Host ''

        Write-Host 'CPRS PRODUCTION DEPLOYMENT PARAMETERS' `
            -ForegroundColor Cyan
        Write-Host ''

        Write-Host '  -Source <folder-or-path>'
        Write-Host '      TEST build to promote.'
        Write-Host '      Default: V:\TEST\EXE\CPRS II'
        Write-Host ''

        Write-Host '  -DestinationFolder <folder>'
        Write-Host '      PROD destination folder.'
        Write-Host '      Default: V:\PROD\EXE\CPRS II'
        Write-Host ''

        Write-Host '  -Message "<message>"'
        Write-Host '      Required deployment message.'
        Write-Host '      Included in the deployment report and email.'
        Write-Host ''

        Write-Host '  -WhatIf'
        Write-Host '      Preview the production deployment without modifying files.'
        Write-Host '      CURRENT_USERS is still checked.'
        Write-Host '      Deployment email is not sent.'
        Write-Host ''

        Write-Host 'PRODUCTION PREVIEW EXAMPLES' -ForegroundColor Cyan
        Write-Host ''

        Write-Host '  Preview default promotion:'
        Write-Host '    cprs-prod-deploy -Message "<deployment message>" -WhatIf'
        Write-Host ''

        Write-Host '  Preview a named TEST build:'
        Write-Host '    cprs-prod-deploy -Source <folder> -Message "<deployment message>" -WhatIf'
        Write-Host ''

        Write-Host '  Preview a custom PROD destination:'
        Write-Host '    cprs-prod-deploy -DestinationFolder <folder> -Message "<deployment message>" -WhatIf'
        Write-Host ''

        Write-Host 'PRODUCTION SAFETY' -ForegroundColor Cyan
        Write-Host ''

        Write-Host '  1. Source must be underneath V:\TEST\EXE.'
        Write-Host '  2. Cprs.exe must exist in the selected TEST build.'
        Write-Host '  3. Source version, SHA256, size, and file count are verified.'
        Write-Host '  4. CURRENT_USERS is read from SSQLL,5026 / cprsprod.'
        Write-Host '  5. Deployment is blocked unless CURRENT_USERS count is 0.'
        Write-Host '  6. Operator must type DEPLOY to authorize deployment.'
        Write-Host '  7. CURRENT_USERS is checked again immediately after confirmation.'
        Write-Host '  8. Existing PROD destination is moved to V:\PROD\EXE\Builds.'
        Write-Host '  9. TEST is copied directly to PROD once; no staging copy is used.'
        Write-Host ' 10. Version, SHA256, file count, and total size are verified after deployment.'
        Write-Host ' 11. The existing CPRS shortcut is preserved for live CPRS II deployments.'
        Write-Host ' 12. Automatic rollback is attempted if deployment fails after cutover begins.'
        Write-Host ' 13. A successful deployment sends the configured HTML deployment email.'
        Write-Host ' 14. Email failure does not roll back a successful deployment.'
        Write-Host ''

        Write-Host 'PRODUCTION ARCHIVE' -ForegroundColor Cyan
        Write-Host ''

        Write-Host '  Archive root:'
        Write-Host '    V:\PROD\EXE\Builds'
        Write-Host ''

        Write-Host '  Live CPRS II archive pattern:'
        Write-Host '    CPRS_v<version>_build<timestamp>_<hash>_<unique>'
        Write-Host ''

        Write-Host '  Custom destination archive pattern:'
        Write-Host '    CPRS_<folder>_v<version>_build<timestamp>_<hash>_<unique>'
        Write-Host ''

        Write-Host 'FULL POWERSHELL HELP' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Get-Help Deploy-CprsProductionClient -Full'
        Write-Host ''

        Write-Host 'CPRS TEST ARCHIVE FORMAT' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Normal CPRS TEST deployments archive the previous build under:'
        Write-Host ''
        Write-Host '    V:\TEST\EXE\Builds'
        Write-Host ''
        Write-Host '  Example archive name:'
        Write-Host '    CPRS_v1.0.0.0_build20260806-184036_74b5cca'
        Write-Host ''
    
        Write-Host 'ADDITIONAL HELP' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Get-Help Deploy-CprsTestClient -Full'
        Write-Host '      Display full PowerShell help for cprs-test-deploy.'
        Write-Host ''
        Write-Host '  Get-Help Build-CprsRelease -Full'
        Write-Host '      Display full PowerShell help for cprs-build.'
        Write-Host ''
    
        Write-Host 'RESIDENTIAL IMPROVEMENTS DEPLOYMENT ROUTES' `
            -ForegroundColor Yellow
    
        @(
            [pscustomobject]@{
                Source      = 'FEATURE'
                Destination = 'LOCAL'
                Preview     = 'cprs-ce-deploy preview feature local'
                Deploy      = 'cprs-ce-deploy deploy feature local'
            }
            [pscustomobject]@{
                Source      = 'FEATURE'
                Destination = 'DEV'
                Preview     = 'cprs-ce-deploy preview feature dev'
                Deploy      = 'cprs-ce-deploy deploy feature dev'
            }
            [pscustomobject]@{
                Source      = 'FEATURE'
                Destination = 'TEST'
                Preview     = 'cprs-ce-deploy preview feature test'
                Deploy      = 'cprs-ce-deploy deploy feature test'
            }
            [pscustomobject]@{
                Source      = 'FEATURE'
                Destination = 'PROD'
                Preview     = 'cprs-ce-deploy preview feature prod'
                Deploy      = 'cprs-ce-deploy deploy feature prod'
            }
            [pscustomobject]@{
                Source      = 'LOCAL'
                Destination = 'DEV'
                Preview     = 'cprs-ce-deploy preview local dev'
                Deploy      = 'cprs-ce-deploy deploy local dev'
            }
            [pscustomobject]@{
                Source      = 'LOCAL'
                Destination = 'TEST'
                Preview     = 'cprs-ce-deploy preview local test'
                Deploy      = 'cprs-ce-deploy deploy local test'
            }
            [pscustomobject]@{
                Source      = 'LOCAL'
                Destination = 'PROD'
                Preview     = 'cprs-ce-deploy preview local prod'
                Deploy      = 'cprs-ce-deploy deploy local prod'
            }
            [pscustomobject]@{
                Source      = 'DEV'
                Destination = 'TEST'
                Preview     = 'cprs-ce-deploy preview dev test'
                Deploy      = 'cprs-ce-deploy deploy dev test'
            }
            [pscustomobject]@{
                Source      = 'DEV'
                Destination = 'PROD'
                Preview     = 'cprs-ce-deploy preview dev prod'
                Deploy      = 'cprs-ce-deploy deploy dev prod'
            }
            [pscustomobject]@{
                Source      = 'TEST'
                Destination = 'PROD'
                Preview     = 'cprs-ce-deploy preview test prod'
                Deploy      = 'cprs-ce-deploy deploy test prod'
            }
        ) |
            Format-Table `
                @{
                    Label = 'Route'
                    Expression = {
                        '{0,7} -> {1}' -f $_.Source, $_.Destination
                    }
                },
                Preview,
                Deploy `
                -AutoSize `
                -Wrap |
            Out-Host
    
        Write-Host 'RESIDENTIAL IMPROVEMENTS OPTIONS' `
            -ForegroundColor Yellow
        Write-Host '  -Config                  Deploy configuration files'
        Write-Host '  -All                     Deploy all eligible files'
        Write-Host '  -Workload <name>         COMPONENT_ESTIMATION, FORECASTING, or ALL'
        Write-Host '  -DeploymentMode <mode>   UPDATED or ALL'
        Write-Host '  -Force                   Bypass deployment confirmation'
        Write-Host ''
    }

    Write-Host 'KEYBOARD SHORTCUTS' -ForegroundColor Yellow
    Write-Host '  Up/Down Arrow   Search history using the text already typed'
    Write-Host '  Ctrl+Space      Display command-completion choices'
    Write-Host '  Right Arrow     Accept the current prediction'
    Write-Host '  F2              Switch prediction view'
    Write-Host '  Ctrl+D          Delete a character or exit an empty prompt'
    Write-Host ''
    Write-Host 'HELP EXAMPLES' -ForegroundColor Yellow
    Write-Host '  phelp ProfileDev'
    Write-Host '  phelp Utilities'
    Write-Host '  phelp CPRS'
    Write-Host '  palias p*'
    Write-Host '  predinfo'
    Write-Host '  predtest'
    Write-Host '  predrebuild'
    Write-Host '  ltr'
    Write-Host '  dtree'
    Write-Host '  dtree -Files'
    Write-Host '  Get-Help Get-GitRecentCommit -Full'
    Write-Host ''
}


function global:Register-ProfileAlias {
    <#
    .SYNOPSIS
        Registers all aliases defined by this profile.

    .DESCRIPTION
        Removes deprecated CPRS aliases from the current PowerShell session and
        then registers the current centrally managed alias definitions.
    #>

    [CmdletBinding()]
    param()

    # Remove the pre-dash CPRS aliases when an existing PowerShell session
    # reloads the profile with rprof. New sessions would not contain these
    # aliases, but cleanup here prevents both old and new names from appearing
    # together after a profile reload.
    $deprecatedCprsAliases = @(
        'cprsbuild',
        'cprstestdeploy',
        'cprsproddeploy',
        'cprsdeploy',
        'predproj'
    )

    foreach ($aliasName in $deprecatedCprsAliases) {
        Remove-Item "Alias:$aliasName" `
            -Force `
            -ErrorAction SilentlyContinue
    }

    foreach ($definition in (Get-ProfileAliasDefinition)) {
        if ($null -eq (Get-Command $definition.Command -ErrorAction SilentlyContinue)) {
            Write-Warning "Cannot register alias '$($definition.Alias)'. Command not found: $($definition.Command)"
            continue
        }

        if ($definition.Alias -eq 'cd') {
            Set-Alias `
                -Name $definition.Alias `
                -Value $definition.Command `
                -Description $definition.Description `
                -Option AllScope `
                -Scope Global `
                -Force
        }
        else {
            Set-Alias `
                -Name $definition.Alias `
                -Value $definition.Command `
                -Description $definition.Description `
                -Scope Global `
                -Force
        }
    }
}


# =============================================================================
# PSReadLine and predictive IntelliSense
# =============================================================================

function global:Initialize-ProfilePSReadLine {
    <#
    .SYNOPSIS
        Configures PSReadLine and predictive command completion.
    #>

    [CmdletBinding()]
    param()

    if ($null -eq (Get-Module -ListAvailable -Name PSReadLine)) {
        return
    }

    try {
        Import-Module PSReadLine -ErrorAction Stop

        $profileAliasPredictorPath = Join-Path `
        $HOME `
        'Documents\PowerShell\Projects\ProfileAliasPredictor\bin\Release\net10.0\ProfileAliasPredictor.dll'

        if (
            (Test-Path -LiteralPath $profileAliasPredictorPath -PathType Leaf) -and
            $null -eq (Get-Module -Name ProfileAliasPredictor)
        ) {
            try {
                Import-Module $profileAliasPredictorPath -ErrorAction Stop
            }
            catch {
                Write-Verbose "ProfileAliasPredictor could not be imported: $($_.Exception.Message)"
            }
        }

        Set-PSReadLineOption -EditMode Windows
        Set-PSReadLineOption -HistoryNoDuplicates
        Set-PSReadLineOption -HistorySearchCursorMovesToEnd
        Set-PSReadLineOption -HistorySaveStyle SaveIncrementally
        Set-PSReadLineOption -MaximumHistoryCount 10000
        Set-PSReadLineOption -BellStyle None
        Set-PSReadLineOption -ShowToolTips

        $predictionSource = 'History'

        if ($null -ne (Get-Module -ListAvailable -Name CompletionPredictor)) {
            try {
                Import-Module CompletionPredictor -ErrorAction Stop
                $predictionSource = 'HistoryAndPlugin'
            }
            catch {
                Write-Verbose "CompletionPredictor could not be imported: $($_.Exception.Message)"
            }
        }

        Set-PSReadLineOption `
            -PredictionSource $predictionSource `
            -PredictionViewStyle ListView

        Set-PSReadLineKeyHandler `
            -Key UpArrow `
            -Function HistorySearchBackward

        Set-PSReadLineKeyHandler `
            -Key DownArrow `
            -Function HistorySearchForward

        Set-PSReadLineKeyHandler `
            -Chord 'Ctrl+Spacebar' `
            -Function MenuComplete

        Set-PSReadLineKeyHandler `
            -Chord 'Ctrl+d' `
            -Function DeleteCharOrExit
    }
    catch {
        Write-Verbose "PSReadLine could not be configured: $($_.Exception.Message)"
    }
}


# =============================================================================
# Profile initialization
# =============================================================================

Register-ProfileAlias
Initialize-ProfilePSReadLine
