param(
    [string]$ProxyPort = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Launcher.Common.ps1")

$launcherScript = Join-Path $PSScriptRoot "Launch-Codex-With-Proxy.ps1"
if (-not (Test-Path -LiteralPath $launcherScript -PathType Leaf)) {
    throw "Launcher script not found: $launcherScript"
}
if ($ProxyPort -and ($ProxyPort -notmatch '^[0-9]{1,5}$' -or [int]$ProxyPort -lt 1 -or [int]$ProxyPort -gt 65535)) {
    throw "Invalid proxy port: use a number from 1 to 65535."
}

$config = Import-LauncherConfig $PSScriptRoot
$desktop = [Environment]::GetFolderPath("Desktop")
$shortcutPath = Join-Path $desktop "Codex Launcher.lnk"
$powershell = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}"' -f $launcherScript
if ($ProxyPort) {
    $arguments += " -ProxyPort $ProxyPort"
}

$codexIconCandidates = @(Get-CodexExeCandidates $config | Select-Object -Unique)
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $powershell
$shortcut.Arguments = $arguments
$shortcut.WorkingDirectory = $PSScriptRoot
if ($codexIconCandidates) {
    $shortcut.IconLocation = "$($codexIconCandidates[0]),0"
}
$shortcut.Save()
Write-Host "Created: $shortcutPath"
