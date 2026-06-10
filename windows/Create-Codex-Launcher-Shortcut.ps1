param(
    [int]$ProxyPort = 0
)

$ErrorActionPreference = "Stop"

$launcherScript = Join-Path $PSScriptRoot "Launch-Codex-With-Proxy.ps1"
if (-not (Test-Path -LiteralPath $launcherScript)) {
    throw "Launcher script not found: $launcherScript"
}

$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "Codex Launcher.lnk"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"

function Get-CodexExeCandidates {
    if ($env:CODEX_EXE -and (Test-Path -LiteralPath $env:CODEX_EXE)) {
        $env:CODEX_EXE
    }

    $fixedPaths = @(
        "$env:LOCALAPPDATA\Programs\Codex\Codex.exe",
        "$env:LOCALAPPDATA\Programs\OpenAI Codex\Codex.exe",
        "$env:LOCALAPPDATA\OpenAI\Codex\Codex.exe",
        "$env:ProgramFiles\Codex\Codex.exe",
        "${env:ProgramFiles(x86)}\Codex\Codex.exe"
    )

    foreach ($path in $fixedPaths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            $path
        }
    }

    try {
        Get-AppxPackage -Name OpenAI.Codex -ErrorAction Stop |
            Sort-Object Version -Descending |
            ForEach-Object {
                $exe = Join-Path $_.InstallLocation "app\Codex.exe"
                if (Test-Path -LiteralPath $exe) {
                    $exe
                }
            }
    } catch {
    }

    $wildcards = @(
        "$env:LOCALAPPDATA\Programs\*Codex*\Codex.exe",
        "$env:LOCALAPPDATA\*Codex*\Codex.exe",
        "$env:ProgramFiles\*Codex*\Codex.exe",
        "${env:ProgramFiles(x86)}\*Codex*\Codex.exe",
        "$env:ProgramFiles\WindowsApps\OpenAI.Codex_*\app\Codex.exe"
    )

    foreach ($path in $wildcards) {
        if ($path) {
            Get-ChildItem -Path $path -ErrorAction SilentlyContinue |
                Sort-Object FullName -Descending |
                Select-Object -ExpandProperty FullName
        }
    }
}

$arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcherScript`""
if ($ProxyPort -gt 0) {
    $arguments += " -ProxyPort $ProxyPort"
}

$codexIconCandidates = @(Get-CodexExeCandidates | Select-Object -Unique)

$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershell
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $PSScriptRoot
if ($codexIconCandidates) {
    $shortcut.IconLocation = $codexIconCandidates[0]
}
$shortcut.Save()

Write-Host "Created: $shortcutPath"
