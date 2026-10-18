$ErrorActionPreference = "Stop"
. (Join-Path $PSScriptRoot "../windows/Launcher.Common.ps1")

function Assert-Equal($Expected, $Actual, [string]$Label) {
    if ($Expected -cne $Actual) {
        throw "$Label -- expected: $Expected; actual: $Actual"
    }
}
function Assert-Throws([scriptblock]$Action, [string]$Label) {
    $failed = $false
    try { & $Action | Out-Null } catch { $failed = $true }
    if (-not $failed) { throw "$Label -- expected an error" }
}

$temp = Join-Path ([IO.Path]::GetTempPath()) ("launcher test " + [Guid]::NewGuid().ToString("N"))
$null = New-Item -ItemType Directory -Path $temp
$keys = @(
    "CODEX_PROXY_CONFIG", "CODEX_PROXY_PORT", "CODEX_PROXY_HOST", "CODEX_PROXY_SCHEME",
    "CODEX_PROXY_URL", "CODEX_EXE", "CHATGPT_EXE", "CODEX_NO_PROXY",
    "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "NO_PROXY", "LAUNCHER_TEST_OUTPUT"
)
$saved = @{}
foreach ($key in $keys) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, "Process")
    [Environment]::SetEnvironmentVariable($key, $null, "Process")
}

try {
    $proxy = Get-LauncherProxy @{} ""
    Assert-Equal "http://127.0.0.1:10808" $proxy.Url "Default proxy"
    Assert-Equal 7890 (Get-LauncherProxy @{ CODEX_PROXY_PORT = "10809" } "7890").Port "Argument wins"
    foreach ($case in @(
        @("http://127.0.0.1:7890/", "127.0.0.1", 7890),
        @("http://user:p%23ss@[::1]:7890", "::1", 7890),
        @("http://[::1]", "::1", 80),
        @("https://localhost/", "localhost", 443)
    )) {
        $proxy = Get-LauncherProxy @{ CODEX_PROXY_URL = $case[0] } "1234"
        Assert-Equal $case[1] $proxy.HostName "URL host"
        Assert-Equal $case[2] $proxy.Port "URL port"
    }
    foreach ($proxyHost in @("::1", "[::1]")) {
        Assert-Equal "http://[::1]:7890" (Get-LauncherProxy @{ CODEX_PROXY_HOST = $proxyHost } "7890").Url "IPv6 setting"
    }
    foreach ($port in @("0", "65536", "-1", "abc", "1.5", "999999999999999999999", " 80")) {
        Assert-Throws { Get-LauncherProxy @{} $port } "Invalid port $port"
    }
    foreach ($url in @(
        "localhost:7890", "socks5://localhost:7890", "http://:7890",
        "http://localhost:", "http://localhost:0", "http://localhost:65536",
        "http://localhost:abc", "http://::1:7890", "http://[::1",
        "http://localhost:7890/path", "http://localhost:7890?query",
        "http://localhost:7890#fragment", "http://-z:7890"
    )) {
        Assert-Throws { Get-LauncherProxy @{ CODEX_PROXY_URL = $url } "" } "Invalid URL $url"
    }

    $platform = Join-Path $temp "windows"
    $null = New-Item -ItemType Directory -Path $platform
    $configFile = Join-Path $temp "custom.env"
    $configText = @'
CODEX_PROXY_PORT=7890 # port
CHATGPT_EXE="Example #1.exe" # comment
CODEX_EXE='icon#1.exe'
UNRECOGNIZED_SETTING=ignored
CODEX_PROXY_PORT=9999
'@
    [IO.File]::WriteAllText($configFile, $configText, [Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $platform "codex-proxy-launcher.env"), "CODEX_PROXY_PORT=4567")
    $env:CODEX_PROXY_CONFIG = $configFile
    $portBeforeImport = [Environment]::GetEnvironmentVariable("CODEX_PROXY_PORT", "Process")
    $config = Import-LauncherConfig $platform
    Assert-Equal "7890" $config.CODEX_PROXY_PORT "Config priority and comments"
    Assert-Equal "Example #1.exe" $config.CHATGPT_EXE "Quoted hash"
    Assert-Equal "icon#1.exe" $config.CODEX_EXE "Unquoted hash"
    Assert-Equal $false $config.ContainsKey("UNRECOGNIZED_SETTING") "Allowed keys"
    Assert-Equal $portBeforeImport ([Environment]::GetEnvironmentVariable("CODEX_PROXY_PORT", "Process")) "Config must not change the parent environment"
    $env:CODEX_PROXY_PORT = "1234"
    Assert-Equal "1234" (Import-LauncherConfig $platform).CODEX_PROXY_PORT "Environment wins"
    $env:CODEX_PROXY_CONFIG = Join-Path $temp "missing.env"
    Assert-Throws { Import-LauncherConfig $platform } "Missing explicit config"

    $fakeExe = Join-Path $temp "Example #1.exe"
    [IO.File]::WriteAllText($fakeExe, "")
    Assert-Equal $fakeExe (@(Get-CodexExeCandidates @{ CHATGPT_EXE = $fakeExe })[0]) "Explicit executable"
    Assert-Throws { Get-CodexExeCandidates @{ CHATGPT_EXE = $temp } } "Directories cannot be executables"
    Assert-Throws { Get-CodexExeCandidates @{ CHATGPT_EXE = (Join-Path $temp "missing.exe") } } "No silent fallback"

    function Get-Process {
        param($Name, $ErrorAction)
        [pscustomobject]@{ Id = 1; Path = (Join-Path $temp "CLI/Codex.exe") }
        [pscustomobject]@{ Id = 2; Path = $fakeExe }
    }
    Assert-Equal 2 (@(Get-RunningDesktopApp $fakeExe)[0].Id) "Process matching uses path"
    Assert-Equal 1 (@(Get-RunningDesktopApp $fakeExe).Count) "Same-name CLI is ignored"
    Remove-Item Function:Get-Process

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    try {
        $settings = @{ HostName = "127.0.0.1"; Port = $listener.LocalEndpoint.Port }
        Assert-Equal $true (Test-LauncherProxy $settings) "Listening proxy"
    } finally {
        $listener.Stop()
    }
    Assert-Equal $false (Test-LauncherProxy $settings) "Closed proxy"

    if ($env:OS -eq "Windows_NT") {
        # Compile a small real .NET Framework executable for both PS 5.1 and PS 7.
        $source = Join-Path $temp "FakeApp.cs"
        $child = Join-Path $temp "fake desktop.exe"
        [IO.File]::WriteAllText($source, @'
using System;
using System.IO;
class FakeApp {
    static void Main() {
        File.WriteAllLines(Environment.GetEnvironmentVariable("LAUNCHER_TEST_OUTPUT"),
            new [] {
                Environment.GetEnvironmentVariable("HTTP_PROXY"),
                Environment.GetEnvironmentVariable("HTTPS_PROXY"),
                Environment.GetEnvironmentVariable("ALL_PROXY"),
                Environment.GetEnvironmentVariable("NO_PROXY")
            });
    }
}
'@)
        $compiler = Join-Path $env:SystemRoot "Microsoft.NET/Framework64/v4.0.30319/csc.exe"
        & $compiler /nologo /target:exe "/out:$child" $source
        if ($LASTEXITCODE -ne 0) { throw "Fake app compilation failed" }
        $env:LAUNCHER_TEST_OUTPUT = Join-Path $temp "child-env.txt"
        $env:HTTP_PROXY = "parent-value"
        Start-ProxiedApp $child @{ Url = "http://127.0.0.1:7890" } "localhost"
        $values = @()
        for ($attempt = 0; $attempt -lt 200; $attempt++) {
            try {
                $values = [IO.File]::ReadAllLines($env:LAUNCHER_TEST_OUTPUT)
                if ($values.Count -eq 4) { break }
            } catch {}
            Start-Sleep -Milliseconds 50
        }
        Assert-Equal 4 $values.Count "Child environment output"
        Assert-Equal "http://127.0.0.1:7890" $values[0] "Child HTTP_PROXY"
        Assert-Equal $values[0] $values[1] "Child HTTPS_PROXY"
        Assert-Equal $values[0] $values[2] "Child ALL_PROXY"
        Assert-Equal "localhost" $values[3] "Child NO_PROXY"
        Assert-Equal "parent-value" $env:HTTP_PROXY "Parent proxy is preserved"
        Get-Process -Name "fake desktop" -ErrorAction SilentlyContinue |
            Where-Object { $_.Path -eq $child } | Wait-Process -Timeout 10

        $storeRoot = Join-Path $temp "Store package"
        $null = New-Item -ItemType Directory -Path (Join-Path $storeRoot "custom")
        $storeExe = Join-Path $storeRoot "custom/ChatGPT.exe"
        [IO.File]::WriteAllText($storeExe, "")
        function Get-AppxPackage {
            param($Name, $ErrorAction)
            [pscustomobject]@{ PackageFullName = "OpenAI.Codex_test"; InstallLocation = $storeRoot; Version = [Version]"1.0" }
        }
        function Get-AppxPackageManifest {
            param($Package, $ErrorAction)
            [pscustomobject]@{ Package = @{ Applications = @{ Application = @(@{ Executable = "custom\ChatGPT.exe" }) } } }
        }
        $candidates = @(Get-CodexExeCandidates @{})
        Assert-Equal $true ($candidates -contains $storeExe) "Store manifest custom layout"
        Remove-Item Function:Get-AppxPackage, Function:Get-AppxPackageManifest
    }
    Write-Host "All Windows launcher regression checks passed."
} finally {
    foreach ($key in $keys) {
        [Environment]::SetEnvironmentVariable($key, $saved[$key], "Process")
    }
    Remove-Item -LiteralPath $temp -Recurse -Force
}
