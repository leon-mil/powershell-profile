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
# Internal helpers
# =============================================================================

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

    Set-Location -LiteralPath $Path
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
        predproj
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

# =============================================================================
# CPRS build and deployment
# =============================================================================

function global:Build-CprsRelease {
    <#
    .SYNOPSIS
        Builds the CPRS client solution in Release mode.

    .DESCRIPTION
        Locates the full Visual Studio MSBuild executable and builds the
        CPRS .NET Framework solution in Release mode for the win-x86 runtime.

    .EXAMPLE
        Build-CprsRelease

    .EXAMPLE
        cprs-build
    #>

    [CmdletBinding()]
    param()

    $solutionPath = 'C:\Development-CPRS\Cprs\cprs-client.sln'
    $outputDirectory = 'C:\Development-CPRS\Cprs\UI\bin\Release'
    $executablePath = Join-Path $outputDirectory 'Cprs.exe'

    $vsWherePath = Join-Path `
        ${env:ProgramFiles(x86)} `
        'Microsoft Visual Studio\Installer\vswhere.exe'

    if (-not (Test-Path -LiteralPath $solutionPath -PathType Leaf)) {
        throw "CPRS solution was not found: $solutionPath"
    }

    if (-not (Test-Path -LiteralPath $vsWherePath -PathType Leaf)) {
        throw "Visual Studio locator was not found: $vsWherePath"
    }

    $msBuildPath = & $vsWherePath `
        -latest `
        -products '*' `
        -requires Microsoft.Component.MSBuild `
        -find 'MSBuild\**\Bin\MSBuild.exe' |
        Select-Object -First 1

    if ([string]::IsNullOrWhiteSpace($msBuildPath)) {
        throw 'A compatible Visual Studio MSBuild installation was not found.'
    }

    Write-Host ''
    Write-Host 'Building CPRS in Release mode...' -ForegroundColor Cyan
    Write-Host "Solution: $solutionPath"
    Write-Host "MSBuild:  $msBuildPath"
    Write-Host ''

    & $msBuildPath `
        $solutionPath `
        /restore `
        /t:Rebuild `
        /p:Configuration=Release `
        /p:RuntimeIdentifier=win-x86 `
        /m:1

    if ($LASTEXITCODE -ne 0) {
        throw "CPRS Release build failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
        throw "The build succeeded, but Cprs.exe was not found: $executablePath"
    }

    $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
        $executablePath
    )

    Write-Host ''
    Write-Host 'CPRS Release build succeeded.' -ForegroundColor Green
    Write-Host "Version: $($versionInfo.FileVersion)"
    Write-Host "Output:  $outputDirectory"
    Write-Host ''

    [pscustomobject]@{
        Application     = 'CPRS'
        Configuration   = 'Release'
        Version         = $versionInfo.FileVersion
        Solution        = $solutionPath
        OutputDirectory = $outputDirectory
        Executable      = $executablePath
        BuildTime       = Get-Date
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
            Archives the existing V:\TEST\EXE\Current build.
            Replaces V:\TEST\EXE\Current.

        -SkipBuild:
            Uses the existing local Release build.
            Archives the existing Current build.
            Replaces Current.

        -Folder <folder>:
            Builds CPRS.
            Replaces V:\TEST\EXE\<folder>.
            Does NOT modify Current.
            Does NOT create a Current archive.

        -Folder <folder> -SkipBuild:
            Uses the existing Release build.
            Replaces V:\TEST\EXE\<folder>.
            Does NOT modify Current.

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

        When Folder is supplied, Current and Builds are not modified.

    .EXAMPLE
        cprs-test-deploy

        Build CPRS, archive the existing Current build, and deploy the new
        build to V:\TEST\EXE\Current.

    .EXAMPLE
        cprs-test-deploy -SkipBuild

        Use the existing Release build, archive Current, and replace Current.

    .EXAMPLE
        cprs-test-deploy -Folder <folder>

        Build CPRS and replace V:\TEST\EXE\<folder>.
        Current is not touched.

    .EXAMPLE
        cprs-test-deploy -Folder <folder> -SkipBuild

        Use the existing Release build and replace
        V:\TEST\EXE\<folder>.

    .EXAMPLE
        cprs-test-deploy -WhatIf

        Preview a normal Current deployment without building or copying.

    .EXAMPLE
        cprs-test-deploy -Folder <folder> -WhatIf

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
        [string]$Folder
    )

    $sourceDirectory =
        'C:\Development-CPRS\Cprs\UI\bin\Release'

    $sourceExecutable =
        Join-Path $sourceDirectory 'Cprs.exe'

    $testRoot =
        'V:\TEST\EXE'

    $currentDirectory =
        Join-Path $testRoot 'Current'

    $buildArchiveRoot =
        Join-Path $testRoot 'Builds'


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

        if ($Folder -in @('Current', 'Builds')) {
            throw (
                "'$Folder' is reserved. " +
                'Omit -Folder to deploy to Current.'
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
            $currentDirectory
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
        Write-Host 'Current     : NOT MODIFIED'
    }
    else {
        Write-Host "Archive     : $buildArchiveRoot"
        Write-Host 'Current     : REPLACED'
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
                -LiteralPath $currentDirectory `
                -PathType Container)
        ) {
            Write-Host ''
            Write-Host (
                "WHAT IF: Existing $currentDirectory " +
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
    # Archive existing Current
    #
    # Only normal Current deployments archive.
    # Custom folders NEVER touch Current or Builds.
    # -------------------------------------------------------------------------

    $archiveDirectory = $null

    if (
        -not $isCustomFolder -and
        (Test-Path `
            -LiteralPath $currentDirectory `
            -PathType Container)
    ) {

        $currentFiles =
            Get-ChildItem `
                -LiteralPath $currentDirectory `
                -Force `
                -ErrorAction Stop

        if ($currentFiles.Count -gt 0) {

            $currentExecutable =
                Join-Path $currentDirectory 'Cprs.exe'

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


            Write-Host 'Archiving existing Current build...' `
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
                -LiteralPath $currentDirectory `
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
        Promotes a verified CPRS TEST build to the CPRS production directory.

    .DESCRIPTION
        Promotes an existing CPRS client build from V:\TEST\EXE to:

            V:\PROD\EXE\CPRS II

        The production root is:

            V:\PROD\EXE

        Production build archives are stored separately under:

            V:\PROD\EXE\Builds

        The default TEST source is:

            V:\TEST\EXE\Current

        A TEST folder name can also be supplied:

            cprs-prod-deploy -Source <folder>

        which resolves to:

            V:\TEST\EXE\<folder>

        A complete TEST path is also accepted:

            cprs-prod-deploy -Source 'V:\TEST\EXE\<folder>'

        Before the live production application is replaced, the complete
        contents of V:\PROD\EXE\CPRS II are copied to a timestamped archive
        under V:\PROD\EXE\Builds and verified.

        The selected TEST build is also staged and verified before the
        production application is touched.

        A production deployment requires two explicit confirmations:

            1. Type REVIEWED
            2. Type DEPLOY PROD

        If the deployment fails after the live production replacement has
        started, the function attempts to restore the archived production
        build automatically.

    .PARAMETER Source
        Specifies the TEST build to promote.

        If omitted:

            V:\TEST\EXE\Current

        If a folder name is supplied:

            <folder>

        it resolves to:

            V:\TEST\EXE\<folder>

        A complete directory under V:\TEST\EXE can also be supplied:

            V:\TEST\EXE\<folder>

        For safety, production promotion is restricted to directories
        underneath V:\TEST\EXE.

    .EXAMPLE
        cprs-prod-deploy

        Promotes V:\TEST\EXE\Current to:

            V:\PROD\EXE\CPRS II

    .EXAMPLE
        cprs-prod-deploy -Source <folder>

        Promotes:

            V:\TEST\EXE\<folder>

        to:

            V:\PROD\EXE\CPRS II

    .EXAMPLE
        cprs-prod-deploy -Source 'V:\TEST\EXE\<folder>'

        Uses the supplied TEST path directly.

    .EXAMPLE
        cprs-prod-deploy -Folder <folder>

        -Folder is an alias for -Source.

    .EXAMPLE
        cprs-prod-deploy -WhatIf

        Displays the complete production deployment plan for TEST Current
        without making changes.

    .EXAMPLE
        cprs-prod-deploy -Source <folder> -WhatIf

        Displays the production deployment plan for a specific TEST build
        without making changes.
    #>

    [CmdletBinding(
        SupportsShouldProcess = $true,
        ConfirmImpact = 'Medium'
    )]
    param(
        [Parameter(Position = 0)]
        [Alias('Folder', 'SourceFolder')]
        [ValidateNotNullOrEmpty()]
        [string]$Source = 'Current'
    )


    # =========================================================================
    # CPRS deployment locations
    #
    # TEST builds:
    #     V:\TEST\EXE
    #
    # Production root:
    #     V:\PROD\EXE
    #
    # Live production CPRS application:
    #     V:\PROD\EXE\CPRS II
    #
    # Archived production builds:
    #     V:\PROD\EXE\Builds
    # =========================================================================

    $testRoot =
        'V:\TEST\EXE'

    $productionRoot =
        'V:\PROD\EXE'

    $productionDirectory =
        Join-Path $productionRoot 'CPRS II'

    $productionBuildsRoot =
        Join-Path $productionRoot 'Builds'


    # These are initialized now so the catch/finally blocks can safely
    # determine what work was completed if an error occurs.

    $archiveDirectory = $null
    $stagingDirectory = $null
    $archiveCreated = $false
    $deploymentStarted = $false


    # =========================================================================
    # Internal helper
    #
    # Returns useful statistics for a deployment directory.
    #
    # These statistics are used when:
    #
    #   - reporting the selected TEST build,
    #   - verifying the staging copy,
    #   - verifying the production archive,
    #   - verifying the final production deployment.
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
                Measure-Object `
                    -Property Length `
                    -Sum
        ).Sum

        if ($null -eq $bytes) {
            $bytes = 0
        }

        [pscustomobject]@{
            TopLevelItems = $topLevelItems.Count
            Files         = $files.Count
            Bytes         = [int64]$bytes
            Megabytes     = [math]::Round(
                $bytes / 1MB,
                2
            )
        }
    }


    # =========================================================================
    # Validate required environment roots
    # =========================================================================

    if (-not (
        Test-Path `
            -LiteralPath $testRoot `
            -PathType Container
    )) {
        throw (
            "CPRS TEST deployment root is not available: $testRoot"
        )
    }


    if (-not (
        Test-Path `
            -LiteralPath $productionRoot `
            -PathType Container
    )) {
        throw (
            "CPRS production root is not available: $productionRoot"
        )
    }


    # =========================================================================
    # Resolve the TEST source
    #
    # Supported forms:
    #
    #     cprs-prod-deploy
    #
    #         -> V:\TEST\EXE\Current
    #
    #     cprs-prod-deploy -Source <folder>
    #
    #         -> V:\TEST\EXE\<folder>
    #
    #     cprs-prod-deploy -Source 'V:\TEST\EXE\<folder>'
    #
    #         -> complete path is used directly
    # =========================================================================

    $Source = $Source.Trim()


    if ([System.IO.Path]::IsPathRooted($Source)) {

        $sourceCandidate =
            $Source
    }
    else {

        # A relative value must be a folder NAME only.
        #
        # This prevents values such as:
        #
        #     ..\something
        #
        # from being interpreted as a path.

        if (
            $Source.Contains('\') -or
            $Source.Contains('/')
        ) {
            throw (
                'Specify either a TEST folder name or a complete TEST path. ' +
                'Examples: <folder> or V:\TEST\EXE\<folder>.'
            )
        }

        $sourceCandidate =
            Join-Path $testRoot $Source
    }


    if (-not (
        Test-Path `
            -LiteralPath $sourceCandidate `
            -PathType Container
    )) {
        throw (
            "CPRS TEST source directory was not found: $sourceCandidate"
        )
    }


    # Resolve both paths to their actual filesystem representations before
    # performing the safety comparison.

    $resolvedTestRoot =
        (
            Resolve-Path `
                -LiteralPath $testRoot `
                -ErrorAction Stop
        ).Path.TrimEnd('\')


    $sourceDirectory =
        (
            Resolve-Path `
                -LiteralPath $sourceCandidate `
                -ErrorAction Stop
        ).Path.TrimEnd('\')


    # Production promotion is intentionally restricted to builds that reside
    # underneath V:\TEST\EXE.
    #
    # This prevents someone from accidentally supplying an unrelated folder
    # elsewhere on V: or on a local drive.

    $sourceIsUnderTest =
        $sourceDirectory.StartsWith(
            $resolvedTestRoot + '\',
            [System.StringComparison]::OrdinalIgnoreCase
        )


    if (-not $sourceIsUnderTest) {
        throw (
            'Production deployment sources must be underneath ' +
            "$testRoot. Resolved source: $sourceDirectory"
        )
    }


    # =========================================================================
    # Validate selected TEST build
    # =========================================================================

    $sourceExecutable =
        Join-Path $sourceDirectory 'Cprs.exe'


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


    $sourceVersion =
        [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
            $sourceExecutable
        ).FileVersion


    $sourceHash =
        (
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


    # =========================================================================
    # Inspect current production application
    #
    # IMPORTANT:
    #
    # We inspect ONLY:
    #
    #     V:\PROD\EXE\CPRS II
    #
    # We do NOT treat V:\PROD\EXE itself as the live application directory.
    #
    # Therefore V:\PROD\EXE\Builds and any other sibling directories are not
    # part of the production application replacement.
    # =========================================================================

    $productionExists =
        Test-Path `
            -LiteralPath $productionDirectory `
            -PathType Container


    $productionExecutable =
        Join-Path $productionDirectory 'Cprs.exe'


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


    $productionItems = @()


    if ($productionExists) {

        $productionItems = @(
            Get-ChildItem `
                -LiteralPath $productionDirectory `
                -Force `
                -ErrorAction Stop
        )


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


            $productionHash =
                (
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


    # An archive is needed whenever the existing production application
    # directory contains anything.

    $archiveRequired =
        $productionExists -and
        $productionItems.Count -gt 0


    # =========================================================================
    # Determine production archive location
    # =========================================================================

    $timestamp =
        Get-Date -Format 'yyyyMMdd-HHmmss'


    $archiveName =
        "CPRS_v${productionVersion}_build${timestamp}_${productionHashShort}"


    $archiveDirectory =
        Join-Path `
            $productionBuildsRoot `
            $archiveName


    # =========================================================================
    # Determine staging directory
    #
    # The TEST build is copied to a temporary directory on the production
    # filesystem and verified BEFORE the live CPRS II directory is changed.
    #
    # The staging directory is temporary and is removed when the operation
    # completes or is cancelled.
    # =========================================================================

    $stagingDirectory =
        Join-Path `
            $productionBuildsRoot `
            (
                '_CPRS_STAGING_' +
                [guid]::NewGuid().ToString('N')
            )


    # =========================================================================
    # Complete pre-deployment report
    #
    # Nothing has been changed at this point.
    # =========================================================================

    Write-Host ''
    Write-Host '============================================================' `
        -ForegroundColor Red

    Write-Host '              CPRS PRODUCTION DEPLOYMENT' `
        -ForegroundColor Red

    Write-Host '============================================================' `
        -ForegroundColor Red

    Write-Host ''

    Write-Host (
        'WARNING: This operation can modify the live CPRS production ' +
        'application.'
    ) -ForegroundColor Yellow

    Write-Host ''


    # -------------------------------------------------------------------------
    # Source report
    # -------------------------------------------------------------------------

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


    # -------------------------------------------------------------------------
    # Destination report
    # -------------------------------------------------------------------------

    Write-Host 'PRODUCTION DESTINATION' `
        -ForegroundColor Cyan

    Write-Host ''

    Write-Host "  PROD root       : $productionRoot"
    Write-Host "  Live directory  : $productionDirectory"
    Write-Host "  Cprs.exe        : $productionExecutable"
    Write-Host "  Exists          : $productionExists"
    Write-Host "  Current version : $productionVersion"
    Write-Host "  Current files   : $($productionSummary.Files)"
    Write-Host "  Current size    : $($productionSummary.Megabytes) MB"

    if ($productionHash) {
        Write-Host "  Current SHA256  : $productionHash"
    }

    Write-Host ''


    # -------------------------------------------------------------------------
    # Archive report
    # -------------------------------------------------------------------------

    Write-Host 'PRODUCTION ARCHIVE' `
        -ForegroundColor Cyan

    Write-Host ''

    Write-Host "  Builds root     : $productionBuildsRoot"

    if ($archiveRequired) {
        Write-Host "  Archive target  : $archiveDirectory"
        Write-Host '  Archive required: YES'
    }
    else {
        Write-Host '  Archive required: NO'
        Write-Host (
            '  Reason          : No existing production application ' +
            'content was found.'
        )
    }

    Write-Host ''


    # -------------------------------------------------------------------------
    # Deployment flow
    # -------------------------------------------------------------------------

    Write-Host 'DEPLOYMENT FLOW' `
        -ForegroundColor Cyan

    Write-Host ''

    @(
        [pscustomobject]@{
            Step        = 1
            Action      = 'STAGE'
            Source      = $sourceDirectory
            Destination = $stagingDirectory
        }

        [pscustomobject]@{
            Step        = 2
            Action      = if ($archiveRequired) {
                'ARCHIVE'
            }
            else {
                'SKIP ARCHIVE'
            }
            Source      = $productionDirectory
            Destination = if ($archiveRequired) {
                $archiveDirectory
            }
            else {
                'Not required'
            }
        }

        [pscustomobject]@{
            Step        = 3
            Action      = 'DEPLOY'
            Source      = $stagingDirectory
            Destination = $productionDirectory
        }

        [pscustomobject]@{
            Step        = 4
            Action      = 'VERIFY'
            Source      = $sourceExecutable
            Destination = $productionExecutable
        }
    ) |
        Format-Table `
            Step,
            Action,
            Source,
            Destination `
            -AutoSize `
            -Wrap |
        Out-Host


    # -------------------------------------------------------------------------
    # Show exactly what the selected TEST build contains at the top level.
    # -------------------------------------------------------------------------

    Write-Host ''
    Write-Host 'TEST BUILD TOP-LEVEL CONTENTS' `
        -ForegroundColor Cyan

    Write-Host ''


    $sourceItems |
        Select-Object `
            @{
                Name = 'Type'
                Expression = {
                    if ($_.PSIsContainer) {
                        'Directory'
                    }
                    else {
                        'File'
                    }
                }
            },
            Name |
        Format-Table `
            -AutoSize |
        Out-Host


    # -------------------------------------------------------------------------
    # Warn when source and production executables appear identical.
    # -------------------------------------------------------------------------

    if (
        $productionHash -and
        $sourceHash -eq $productionHash
    ) {

        Write-Warning (
            'The selected TEST Cprs.exe has the same SHA256 hash as ' +
            'the current production Cprs.exe.'
        )

        Write-Warning (
            'Review whether a production deployment is actually necessary.'
        )
    }


    # =========================================================================
    # WhatIf
    #
    # A WhatIf invocation stops here.
    #
    # No directory is created.
    # No staging copy is performed.
    # No production archive is created.
    # No production files are changed.
    # =========================================================================

    if ($WhatIfPreference) {

        Write-Host ''
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

        Write-Host "Would stage   : $sourceDirectory"
        Write-Host "                 -> $stagingDirectory"

        Write-Host ''

        if ($archiveRequired) {
            Write-Host "Would archive : $productionDirectory"
            Write-Host "                 -> $archiveDirectory"
            Write-Host ''
        }

        Write-Host "Would deploy  : $sourceDirectory"
        Write-Host "                 -> $productionDirectory"

        Write-Host ''

        Write-Host 'To perform the actual deployment, run the same command' `
            -ForegroundColor Yellow

        Write-Host 'without -WhatIf.' `
            -ForegroundColor Yellow

        Write-Host ''

        return
    }


    # =========================================================================
    # CONFIRMATION 1 OF 2
    #
    # The operator must confirm that the report above has actually been
    # reviewed.
    #
    # Production has NOT been changed yet.
    # =========================================================================

    Write-Host ''
    Write-Host '============================================================' `
        -ForegroundColor Yellow

    Write-Host '                 CONFIRMATION 1 OF 2' `
        -ForegroundColor Yellow

    Write-Host '============================================================' `
        -ForegroundColor Yellow

    Write-Host ''

    Write-Host 'Review the information above carefully:'
    Write-Host ''
    Write-Host "  Source      : $sourceDirectory"
    Write-Host "  Destination : $productionDirectory"

    if ($archiveRequired) {
        Write-Host "  Archive     : $archiveDirectory"
    }
    else {
        Write-Host '  Archive     : Not required'
    }

    Write-Host "  Version     : $sourceVersion"
    Write-Host "  SHA256      : $sourceHash"

    Write-Host ''

    Write-Host (
        'Nothing in the live production application has been modified.'
    ) -ForegroundColor Green

    Write-Host ''


    $reviewConfirmation =
        Read-Host 'Type REVIEWED to stage and verify this build'


    if ($reviewConfirmation -cne 'REVIEWED') {

        Write-Host ''
        Write-Host 'PRODUCTION DEPLOYMENT CANCELLED.' `
            -ForegroundColor Yellow

        Write-Host 'The live CPRS production application was not modified.' `
            -ForegroundColor Green

        Write-Host ''

        return
    }


    # =========================================================================
    # Stage and verify selected TEST build
    #
    # Staging occurs before the final production authorization.
    #
    # The live production directory remains untouched.
    # =========================================================================

    try {

        if (-not (
            Test-Path `
                -LiteralPath $productionBuildsRoot `
                -PathType Container
        )) {

            Write-Host ''
            Write-Host (
                "Creating production Builds directory: " +
                $productionBuildsRoot
            ) -ForegroundColor Cyan


            New-Item `
                -ItemType Directory `
                -Path $productionBuildsRoot `
                -Force `
                -ErrorAction Stop |
                Out-Null
        }


        Write-Host ''
        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host '               STAGING TEST BUILD' `
            -ForegroundColor Cyan

        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host ''

        Write-Host "Source : $sourceDirectory"
        Write-Host "Stage  : $stagingDirectory"

        Write-Host ''


        New-Item `
            -ItemType Directory `
            -Path $stagingDirectory `
            -Force `
            -ErrorAction Stop |
            Out-Null


        foreach ($item in $sourceItems) {

            Write-Host "  Staging: $($item.Name)"

            Copy-Item `
                -LiteralPath $item.FullName `
                -Destination $stagingDirectory `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }


        # ---------------------------------------------------------------------
        # Verify staging
        # ---------------------------------------------------------------------

        $stagedExecutable =
            Join-Path $stagingDirectory 'Cprs.exe'


        if (-not (
            Test-Path `
                -LiteralPath $stagedExecutable `
                -PathType Leaf
        )) {
            throw (
                'Staging verification failed. ' +
                'Cprs.exe was not found in the staging directory.'
            )
        }


        $stagedHash =
            (
                Get-FileHash `
                    -LiteralPath $stagedExecutable `
                    -Algorithm SHA256 `
                    -ErrorAction Stop
            ).Hash


        $stagedSummary =
            Get-CprsDirectorySummary `
                -Path $stagingDirectory


        if ($stagedHash -ne $sourceHash) {
            throw (
                'Staging verification failed. ' +
                'Cprs.exe SHA256 does not match the TEST source.'
            )
        }


        if (
            $stagedSummary.Files -ne
            $sourceSummary.Files
        ) {
            throw (
                'Staging verification failed. ' +
                'The staged file count does not match the TEST source.'
            )
        }


        if (
            $stagedSummary.Bytes -ne
            $sourceSummary.Bytes
        ) {
            throw (
                'Staging verification failed. ' +
                'The staged byte count does not match the TEST source.'
            )
        }


        Write-Host ''
        Write-Host 'STAGING VERIFICATION SUCCEEDED' `
            -ForegroundColor Green

        Write-Host ''

        Write-Host "  Files  : $($stagedSummary.Files)"
        Write-Host "  Size   : $($stagedSummary.Megabytes) MB"
        Write-Host "  SHA256 : $stagedHash"

        Write-Host ''


        # =====================================================================
        # CONFIRMATION 2 OF 2
        #
        # This is the final authorization before the live production
        # application is touched.
        # =====================================================================

        Write-Host '============================================================' `
            -ForegroundColor Red

        Write-Host '                 CONFIRMATION 2 OF 2' `
            -ForegroundColor Red

        Write-Host '============================================================' `
            -ForegroundColor Red

        Write-Host ''

        Write-Host 'THE SELECTED TEST BUILD HAS BEEN STAGED AND VERIFIED.' `
            -ForegroundColor Green

        Write-Host ''

        Write-Host 'The next step WILL modify the live production application.' `
            -ForegroundColor Yellow

        Write-Host ''

        Write-Host "Source      : $sourceDirectory"
        Write-Host "Destination : $productionDirectory"

        if ($archiveRequired) {
            Write-Host "Archive     : $archiveDirectory"
        }

        Write-Host "Version     : $sourceVersion"
        Write-Host "SHA256      : $sourceHash"

        Write-Host ''

        Write-Host (
            'If you do not want to modify production, enter anything ' +
            'other than DEPLOY PROD.'
        ) -ForegroundColor Yellow

        Write-Host ''


        $deployConfirmation =
            Read-Host 'Type DEPLOY PROD to authorize production deployment'


        if ($deployConfirmation -cne 'DEPLOY PROD') {

            Write-Host ''
            Write-Host 'PRODUCTION DEPLOYMENT CANCELLED.' `
                -ForegroundColor Yellow

            Write-Host (
                'The live CPRS production application was not modified.'
            ) -ForegroundColor Green

            Write-Host ''

            return
        }


        # SupportsShouldProcess gives the command standard PowerShell
        # -Confirm support in addition to the two explicit confirmations above.

        if (-not (
            $PSCmdlet.ShouldProcess(
                $productionDirectory,
                (
                    "Archive current CPRS production build and deploy " +
                    "CPRS $sourceVersion"
                )
            )
        )) {
            return
        }


        # =====================================================================
        # STEP 1
        # Archive current V:\PROD\EXE\CPRS II
        #
        # The archive is stored under:
        #
        #     V:\PROD\EXE\Builds
        #
        # The live directory is NOT removed until the archive copy has been
        # verified.
        # =====================================================================

        if ($archiveRequired) {

            Write-Host ''
            Write-Host '============================================================' `
                -ForegroundColor Cyan

            Write-Host '        STEP 1 - ARCHIVING CURRENT PRODUCTION' `
                -ForegroundColor Cyan

            Write-Host '============================================================' `
                -ForegroundColor Cyan

            Write-Host ''

            Write-Host "From : $productionDirectory"
            Write-Host "To   : $archiveDirectory"

            Write-Host ''


            New-Item `
                -ItemType Directory `
                -Path $archiveDirectory `
                -Force `
                -ErrorAction Stop |
                Out-Null


            foreach ($item in $productionItems) {

                Write-Host "  Archiving: $($item.Name)"

                Copy-Item `
                    -LiteralPath $item.FullName `
                    -Destination $archiveDirectory `
                    -Recurse `
                    -Force `
                    -ErrorAction Stop
            }


            # -----------------------------------------------------------------
            # Verify archive before touching live production
            # -----------------------------------------------------------------

            $archiveSummary =
                Get-CprsDirectorySummary `
                    -Path $archiveDirectory


            if (
                $archiveSummary.Files -ne
                $productionSummary.Files
            ) {
                throw (
                    'Production archive verification failed. ' +
                    'Archived file count does not match current production.'
                )
            }


            if (
                $archiveSummary.Bytes -ne
                $productionSummary.Bytes
            ) {
                throw (
                    'Production archive verification failed. ' +
                    'Archived byte count does not match current production.'
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


                $archivedHash =
                    (
                        Get-FileHash `
                            -LiteralPath $archivedExecutable `
                            -Algorithm SHA256 `
                            -ErrorAction Stop
                    ).Hash


                if ($archivedHash -ne $productionHash) {
                    throw (
                        'Production archive verification failed. ' +
                        'Archived Cprs.exe does not match current production.'
                    )
                }
            }


            $archiveCreated = $true


            Write-Host ''
            Write-Host 'PRODUCTION ARCHIVE VERIFIED' `
                -ForegroundColor Green

            Write-Host ''

            Write-Host "  Archive : $archiveDirectory"
            Write-Host "  Files   : $($archiveSummary.Files)"
            Write-Host "  Size    : $($archiveSummary.Megabytes) MB"

            Write-Host ''
        }
        else {

            Write-Host ''
            Write-Host 'STEP 1 - ARCHIVE NOT REQUIRED' `
                -ForegroundColor Yellow

            Write-Host (
                'No existing production application content was found.'
            )

            Write-Host ''
        }


        # =====================================================================
        # STEP 2
        # Replace the live CPRS II application directory
        #
        # ONLY this directory is replaced:
        #
        #     V:\PROD\EXE\CPRS II
        #
        # Neither V:\PROD\EXE nor V:\PROD\EXE\Builds is removed.
        # =====================================================================

        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host '           STEP 2 - DEPLOYING TO PRODUCTION' `
            -ForegroundColor Cyan

        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host ''

        Write-Host "Source      : $stagingDirectory"
        Write-Host "Destination : $productionDirectory"

        Write-Host ''


        # From this point forward a failure requires rollback.

        $deploymentStarted = $true


        if (
            Test-Path `
                -LiteralPath $productionDirectory
        ) {

            Write-Host (
                "Removing existing live directory: " +
                $productionDirectory
            )

            Remove-Item `
                -LiteralPath $productionDirectory `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }


        New-Item `
            -ItemType Directory `
            -Path $productionDirectory `
            -Force `
            -ErrorAction Stop |
            Out-Null


        $stagedItems = @(
            Get-ChildItem `
                -LiteralPath $stagingDirectory `
                -Force `
                -ErrorAction Stop
        )


        foreach ($item in $stagedItems) {

            Write-Host "  Deploying: $($item.Name)"

            Copy-Item `
                -LiteralPath $item.FullName `
                -Destination $productionDirectory `
                -Recurse `
                -Force `
                -ErrorAction Stop
        }


        # =====================================================================
        # STEP 3
        # Verify final production deployment
        # =====================================================================

        Write-Host ''
        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host '          STEP 3 - VERIFYING PRODUCTION' `
            -ForegroundColor Cyan

        Write-Host '============================================================' `
            -ForegroundColor Cyan

        Write-Host ''


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


        $deployedHash =
            (
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
                'The deployed Cprs.exe SHA256 does not match TEST.'
            )
        }


        if (
            $deployedSummary.Files -ne
            $sourceSummary.Files
        ) {
            throw (
                'Production verification failed. ' +
                'The production file count does not match TEST.'
            )
        }


        if (
            $deployedSummary.Bytes -ne
            $sourceSummary.Bytes
        ) {
            throw (
                'Production verification failed. ' +
                'The production byte count does not match TEST.'
            )
        }


        $deployedVersion =
            [System.Diagnostics.FileVersionInfo]::GetVersionInfo(
                $productionExecutable
            ).FileVersion


        Write-Host 'PRODUCTION VERIFICATION SUCCEEDED' `
            -ForegroundColor Green

        Write-Host ''

        Write-Host "  Version : $deployedVersion"
        Write-Host "  Files   : $($deployedSummary.Files)"
        Write-Host "  Size    : $($deployedSummary.Megabytes) MB"
        Write-Host "  SHA256  : $deployedHash"

        Write-Host ''


        # =====================================================================
        # Final success report
        # =====================================================================

        Write-Host '============================================================' `
            -ForegroundColor Green

        Write-Host '        CPRS PRODUCTION DEPLOYMENT SUCCEEDED' `
            -ForegroundColor Green

        Write-Host '============================================================' `
            -ForegroundColor Green

        Write-Host ''

        Write-Host "Source           : $sourceDirectory"
        Write-Host "Production root  : $productionRoot"
        Write-Host "Live application : $productionDirectory"
        Write-Host "Builds root      : $productionBuildsRoot"

        if ($archiveCreated) {
            Write-Host "Archived build   : $archiveDirectory"
        }

        Write-Host "Version          : $deployedVersion"
        Write-Host "Files            : $($deployedSummary.Files)"
        Write-Host "SHA256           : $deployedHash"
        Write-Host "Completed        : $(Get-Date)"

        Write-Host ''


        [pscustomobject]@{
            Application         = 'CPRS'
            Environment         = 'PROD'
            Source              = $sourceDirectory
            ProductionRoot      = $productionRoot
            Destination         = $productionDirectory
            BuildsRoot          = $productionBuildsRoot
            ArchivedTo          = if ($archiveCreated) {
                $archiveDirectory
            }
            else {
                $null
            }
            Version             = $deployedVersion
            SHA256              = $deployedHash
            FileCount           = $deployedSummary.Files
            DeploymentTime      = Get-Date
            Status              = 'SUCCESS'
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


        # =====================================================================
        # Automatic rollback
        #
        # Rollback is necessary only if replacement of the live CPRS II
        # directory had already started.
        # =====================================================================

        if ($deploymentStarted) {

            Write-Warning (
                'The live production replacement had started. ' +
                'Automatic rollback will be attempted.'
            )

            Write-Host ''


            try {

                # Remove the incomplete/new production application.

                if (
                    Test-Path `
                        -LiteralPath $productionDirectory
                ) {

                    Remove-Item `
                        -LiteralPath $productionDirectory `
                        -Recurse `
                        -Force `
                        -ErrorAction Stop
                }


                if ($archiveCreated) {

                    # Restore the complete archived application.

                    New-Item `
                        -ItemType Directory `
                        -Path $productionDirectory `
                        -Force `
                        -ErrorAction Stop |
                        Out-Null


                    $archivedItems = @(
                        Get-ChildItem `
                            -LiteralPath $archiveDirectory `
                            -Force `
                            -ErrorAction Stop
                    )


                    foreach ($item in $archivedItems) {

                        Write-Host "  Restoring: $($item.Name)"

                        Copy-Item `
                            -LiteralPath $item.FullName `
                            -Destination $productionDirectory `
                            -Recurse `
                            -Force `
                            -ErrorAction Stop
                    }


                    # Verify that the restored application matches the
                    # production application captured before deployment.

                    $restoredSummary =
                        Get-CprsDirectorySummary `
                            -Path $productionDirectory


                    if (
                        $restoredSummary.Files -ne
                        $productionSummary.Files
                    ) {
                        throw (
                            'Rollback verification failed. ' +
                            'Restored file count does not match the archive.'
                        )
                    }


                    if (
                        $restoredSummary.Bytes -ne
                        $productionSummary.Bytes
                    ) {
                        throw (
                            'Rollback verification failed. ' +
                            'Restored byte count does not match the archive.'
                        )
                    }


                    if ($productionHash) {

                        $restoredExecutable =
                            Join-Path `
                                $productionDirectory `
                                'Cprs.exe'


                        $restoredHash =
                            (
                                Get-FileHash `
                                    -LiteralPath $restoredExecutable `
                                    -Algorithm SHA256 `
                                    -ErrorAction Stop
                            ).Hash


                        if ($restoredHash -ne $productionHash) {
                            throw (
                                'Rollback verification failed. ' +
                                'Restored Cprs.exe does not match the ' +
                                'original production executable.'
                            )
                        }
                    }


                    Write-Host ''
                    Write-Host 'AUTOMATIC ROLLBACK SUCCEEDED' `
                        -ForegroundColor Yellow

                    Write-Host ''

                    Write-Host "Restored from : $archiveDirectory"
                    Write-Host "Restored to   : $productionDirectory"

                    Write-Host ''
                }
                elseif ($productionExists) {

                    # The previous production directory existed but was empty.
                    # Restore that original empty directory.

                    New-Item `
                        -ItemType Directory `
                        -Path $productionDirectory `
                        -Force `
                        -ErrorAction Stop |
                        Out-Null


                    Write-Host (
                        'The original empty production directory was restored.'
                    ) -ForegroundColor Yellow
                }
                else {

                    # Production did not exist before the deployment, so after
                    # removing the failed deployment there is nothing else to
                    # restore.

                    Write-Host (
                        'No previous production application existed. ' +
                        'The failed deployment directory was removed.'
                    ) -ForegroundColor Yellow
                }
            }
            catch {

                Write-Host ''
                Write-Host 'AUTOMATIC ROLLBACK FAILED' `
                    -ForegroundColor Red

                Write-Host ''

                if ($archiveCreated) {
                    Write-Host (
                        'Manual recovery archive: ' +
                        $archiveDirectory
                    ) -ForegroundColor Red
                }

                Write-Host ''

                throw
            }
        }


        throw $deploymentError
    }
    finally {

        # =====================================================================
        # Always remove temporary staging data.
        #
        # This does NOT remove permanent archives.
        # =====================================================================

        if (
            $stagingDirectory -and
            (Test-Path `
                -LiteralPath $stagingDirectory)
        ) {

            Remove-Item `
                -LiteralPath $stagingDirectory `
                -Recurse `
                -Force `
                -ErrorAction SilentlyContinue
        }
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

    Set-Location ..
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

    Set-Location ..\..
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

    Set-Location -LiteralPath $HOME
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

    Set-Location -LiteralPath $repositoryRoot
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
            Description = 'Open the profile in VS Code'
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
            Alias       = 'predproj'
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
        Write-Host '  2. eprof       Open profile.ps1 in Visual Studio Code'
        Write-Host '  3. Edit and save profile.ps1'
        Write-Host '  4. rprof       Reload the profile'
        Write-Host '  5. Test the changed aliases or functions'
        Write-Host ''

        Write-Host 'ProfileAliasPredictor .NET project' -ForegroundColor Cyan
        Write-Host '  1. predcd       Go to the ProfileAliasPredictor project'
        Write-Host '  2. predproj     Open the project in Visual Studio Code'
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
        Write-Host '      Archive the existing V:\TEST\EXE\Current build.'
        Write-Host '      Replace V:\TEST\EXE\Current with the new build.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -SkipBuild' -ForegroundColor Cyan
        Write-Host '      Do NOT build CPRS.'
        Write-Host '      Use the existing local Release build.'
        Write-Host '      Archive the existing Current build.'
        Write-Host '      Replace V:\TEST\EXE\Current.'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -Folder <folder>' -ForegroundColor Cyan
        Write-Host '      Build CPRS.'
        Write-Host '      Deploy to V:\TEST\EXE\<folder>.'
        Write-Host '      Replace the folder if it already exists.'
        Write-Host '      Do NOT touch Current.'
        Write-Host '      Do NOT create a Current archive.'
        Write-Host ''
        Write-Host '      Example:'
        Write-Host '        cprs-test-deploy -Folder <folder>'
        Write-Host ''
    
        Write-Host '  cprs-test-deploy -Folder <folder> -SkipBuild' -ForegroundColor Cyan
        Write-Host '      Do NOT build CPRS.'
        Write-Host '      Use the existing local Release build.'
        Write-Host '      Replace V:\TEST\EXE\<folder>.'
        Write-Host '      Do NOT touch Current or Builds.'
        Write-Host ''
    
        Write-Host 'PREVIEW OPTIONS' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  cprs-test-deploy -WhatIf'
        Write-Host '      Preview deployment to Current.'
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
        Write-Host '      Deploy to V:\TEST\EXE\<folder> instead of Current.'
        Write-Host '      Current and Builds are never modified.'
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

        Write-Host '  Default promotion:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy'
        Write-Host ''
        Write-Host '      Source      : V:\TEST\EXE\Current'
        Write-Host '      Destination : V:\PROD\EXE\CPRS II'
        Write-Host '      Archive     : V:\PROD\EXE\Builds'
        Write-Host '      Archives the current V:\PROD\EXE\CPRS II before replacement.'
        Write-Host ''

        Write-Host '  Named TEST folder:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -Source <folder>'
        Write-Host ''
        Write-Host '      Resolves source as:'
        Write-Host '        V:\TEST\EXE\<folder>'
        Write-Host ''
        Write-Host '      Example pattern:'
        Write-Host '        <folder> -> V:\TEST\EXE\<folder>'
        Write-Host ''

        Write-Host '  Complete TEST path:' -ForegroundColor Cyan
        Write-Host "    cprs-prod-deploy -Source 'V:\TEST\EXE\<folder>'"
        Write-Host ''
        Write-Host '      Uses the supplied TEST directory directly.'
        Write-Host '      The path must remain under V:\TEST\EXE.'
        Write-Host ''

        Write-Host '  Folder parameter alias:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -Folder <folder>'
        Write-Host ''
        Write-Host '      -Folder is an alias for -Source.'
        Write-Host ''

        Write-Host '  Preview default promotion:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -WhatIf'
        Write-Host ''
        Write-Host '      Preview V:\TEST\EXE\Current -> V:\PROD\EXE\CPRS II.'
        Write-Host '      No PROD files are modified.'
        Write-Host ''

        Write-Host '  Preview a named TEST build:' -ForegroundColor Cyan
        Write-Host '    cprs-prod-deploy -Source <folder> -WhatIf'
        Write-Host ''
        Write-Host '      Preview V:\TEST\EXE\<folder> -> V:\PROD\EXE\CPRS II.'
        Write-Host '      No PROD files are modified.'
        Write-Host ''

        Write-Host 'PRODUCTION SAFETY' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  1. Source must be underneath V:\TEST\EXE.'
        Write-Host '  2. Cprs.exe must exist in the selected TEST build.'
        Write-Host '  3. Source version, SHA256, size, and file count are displayed.'
        Write-Host '  4. Current PROD contents are archived to V:\PROD\EXE\Builds.'
        Write-Host '  5. Only V:\PROD\EXE\CPRS II is replaced; sibling folders are untouched.'
        Write-Host '  6. Operator must type REVIEWED before staging.'
        Write-Host '  7. TEST build is staged and SHA256 verified.'
        Write-Host '  8. Operator must type DEPLOY PROD before live replacement.'
        Write-Host '  9. Deployed Cprs.exe is SHA256 verified.'
        Write-Host ' 10. Automatic rollback is attempted if deployment fails.'
        Write-Host ''

        Write-Host 'PRODUCTION ARCHIVE' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Archive root:'
        Write-Host '    V:\PROD\EXE\Builds'
        Write-Host ''
        Write-Host '  Archive naming pattern:'
        Write-Host '    CPRS_v<version>_build<timestamp>_<hash>'
        Write-Host ''

        Write-Host 'FULL POWERSHELL HELP' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Get-Help Deploy-CprsProductionClient -Full'
        Write-Host ''
    
        Write-Host 'ARCHIVE FORMAT' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  Normal Current deployments archive the previous build under:'
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
        'cprsdeploy'
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

        Set-Alias `
            -Name $definition.Alias `
            -Value $definition.Command `
            -Description $definition.Description `
            -Scope Global `
            -Force
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
