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
    if ($env:CHATGPT_EXE -and (Test-Path -LiteralPath $env:CHATGPT_EXE)) {
        $env:CHATGPT_EXE
    }
    if ($env:CODEX_EXE -and (Test-Path -LiteralPath $env:CODEX_EXE)) {
        $env:CODEX_EXE
    }

    $fixedPaths = @(
        "$env:LOCALAPPDATA\Programs\ChatGPT\ChatGPT.exe",
        "$env:LOCALAPPDATA\Programs\OpenAI ChatGPT\ChatGPT.exe",
        "$env:LOCALAPPDATA\OpenAI\ChatGPT\ChatGPT.exe",
        "$env:ProgramFiles\ChatGPT\ChatGPT.exe",
        "${env:ProgramFiles(x86)}\ChatGPT\ChatGPT.exe",
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

    foreach ($packageName in @("OpenAI.ChatGPT", "OpenAI.Codex")) {
        try {
            Get-AppxPackage -Name $packageName -ErrorAction Stop |
                Sort-Object Version -Descending |
                ForEach-Object {
                    $package = $_
                    try {
                        $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
                        foreach ($application in @($manifest.Package.Applications.Application)) {
                            $relativeExe = [string]$application.Executable
                            if ($relativeExe -match '(?i)(ChatGPT|Codex)\.exe$') {
                                $manifestExe = Join-Path $package.InstallLocation $relativeExe
                                if (Test-Path -LiteralPath $manifestExe) {
                                    $manifestExe
                                }
                            }
                        }
                    } catch {
                    }

                    foreach ($relativePath in @("app\ChatGPT.exe", "app\Codex.exe", "ChatGPT.exe", "Codex.exe")) {
                        $exe = Join-Path $package.InstallLocation $relativePath
                        if (Test-Path -LiteralPath $exe) {
                            $exe
                        }
                    }
                }
        } catch {
        }
    }

    $wildcards = @(
        "$env:LOCALAPPDATA\Programs\*ChatGPT*\ChatGPT.exe",
        "$env:LOCALAPPDATA\*ChatGPT*\ChatGPT.exe",
        "$env:ProgramFiles\*ChatGPT*\ChatGPT.exe",
        "${env:ProgramFiles(x86)}\*ChatGPT*\ChatGPT.exe",
        "$env:LOCALAPPDATA\Programs\*Codex*\Codex.exe",
        "$env:LOCALAPPDATA\*Codex*\Codex.exe",
        "$env:ProgramFiles\*Codex*\Codex.exe",
        "${env:ProgramFiles(x86)}\*Codex*\Codex.exe",
        "$env:ProgramFiles\WindowsApps\OpenAI.ChatGPT_*\app\ChatGPT.exe",
        "$env:ProgramFiles\WindowsApps\OpenAI.Codex_*\app\ChatGPT.exe",
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
