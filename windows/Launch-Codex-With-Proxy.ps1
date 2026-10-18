param(
    [string]$ProxyPort = ""
)

$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "Launcher.Common.ps1")

function Show-Message($Message) {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($Message, "Codex Launcher") | Out-Null
    } catch {
        Write-Host $Message
    }
}

try {
    $config = Import-LauncherConfig $PSScriptRoot
    $proxy = Get-LauncherProxy $config $ProxyPort
    $candidatePaths = @(Get-CodexExeCandidates $config | Select-Object -Unique)
    if (-not $candidatePaths) {
        throw "ChatGPT.exe or Codex.exe was not found. Set CHATGPT_EXE or CODEX_EXE in the launcher config for a custom installation."
    }
    $executable = $candidatePaths[0]
    $running = @(Get-RunningDesktopApp $executable)
    if ($running) {
        $processIds = ($running.Id -join ", ")
        throw "The desktop app is already running (PID $processIds). Quit it completely, then open Codex Launcher so the new process can inherit the proxy environment."
    }
    if (-not (Test-LauncherProxy $proxy)) {
        throw "Proxy $($proxy.HostName):$($proxy.Port) is not listening. Start your proxy client first."
    }
    $noProxyValue = Get-ConfigValue $config "CODEX_NO_PROXY" "localhost,127.0.0.1,::1"
    Start-ProxiedApp $executable $proxy $noProxyValue
} catch {
    Show-Message $_.Exception.Message
    exit 1
}
