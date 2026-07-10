param(
    [int]$ProxyPort = 0
)

$ErrorActionPreference = "Stop"

function Show-Message($message) {
    try {
        Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
        [System.Windows.MessageBox]::Show($message, "Codex Launcher") | Out-Null
    } catch {
        Write-Host $message
        Read-Host "Press Enter to exit"
    }
}

function Import-LauncherConfig {
    $paths = @()
    if ($env:CODEX_PROXY_CONFIG) {
        $paths += $env:CODEX_PROXY_CONFIG
    }

    $paths += Join-Path $PSScriptRoot "codex-proxy-launcher.env"
    $parent = Split-Path -Parent $PSScriptRoot
    if ($parent) {
        $paths += Join-Path $parent "codex-proxy-launcher.env"
    }
    if ($HOME) {
        $paths += Join-Path $HOME ".codex-proxy-launcher.env"
    }

    foreach ($path in ($paths | Where-Object { $_ } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        foreach ($line in Get-Content -LiteralPath $path) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) {
                continue
            }

            $separator = $trimmed.IndexOf("=")
            $key = $trimmed.Substring(0, $separator).Trim()
            $value = $trimmed.Substring($separator + 1).Trim()
            if (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            ) {
                $value = $value.Substring(1, $value.Length - 2)
            }
            $allowed = @(
                "CODEX_PROXY_PORT",
                "CODEX_PROXY_HOST",
                "CODEX_PROXY_SCHEME",
                "CODEX_PROXY_URL",
                "CODEX_EXE",
                "CHATGPT_EXE",
                "CODEX_NO_PROXY"
            )

            if ($allowed -contains $key -and -not [Environment]::GetEnvironmentVariable($key, "Process")) {
                Set-Item -Path "Env:$key" -Value $value
            }
        }
    }
}

function Get-EnvOrDefault($name, $defaultValue) {
    $value = [Environment]::GetEnvironmentVariable($name, "Process")
    if ($value) {
        return $value
    }
    return $defaultValue
}

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
            # Non-Store installs and older Windows builds may not have this package.
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

Import-LauncherConfig

if ($ProxyPort -le 0) {
    if ($env:CODEX_PROXY_PORT) {
        $ProxyPort = [int]$env:CODEX_PROXY_PORT
    } else {
        $ProxyPort = 10808
    }
}

$proxyHost = Get-EnvOrDefault "CODEX_PROXY_HOST" "127.0.0.1"
$proxyScheme = Get-EnvOrDefault "CODEX_PROXY_SCHEME" "http"
$proxyUrl = Get-EnvOrDefault "CODEX_PROXY_URL" "$proxyScheme`://$proxyHost`:$ProxyPort"
$noProxyValue = Get-EnvOrDefault "CODEX_NO_PROXY" "localhost,127.0.0.1,::1"

$checkHost = $proxyHost
$checkPort = $ProxyPort
if ($env:CODEX_PROXY_URL) {
    try {
        $uri = [Uri]$proxyUrl
        if ($uri.Host) {
            $checkHost = $uri.Host
        }
        if ($uri.Port -gt 0) {
            $checkPort = $uri.Port
        }
    } catch {
        Show-Message "Invalid CODEX_PROXY_URL: $proxyUrl"
        exit 1
    }
}

try {
    $client = [Net.Sockets.TcpClient]::new()
    $client.Connect($checkHost, $checkPort)
    $client.Close()
} catch {
    Show-Message "Proxy $checkHost`:$checkPort is not listening. Start your proxy client first."
    exit 1
}

$candidatePaths = @(Get-CodexExeCandidates | Select-Object -Unique)

if (-not $candidatePaths) {
    Show-Message "ChatGPT.exe or Codex.exe was not found. Microsoft Store installs are supported, but you can set CHATGPT_EXE or CODEX_EXE if the app is installed somewhere unusual."
    exit 1
}

if (Get-Process -Name ChatGPT, Codex -ErrorAction SilentlyContinue) {
    Show-Message "ChatGPT or Codex is already running. Quit it completely, then use Codex Launcher so the new process can inherit the proxy environment."
    exit 1
}

$env:HTTP_PROXY = $proxyUrl
$env:HTTPS_PROXY = $proxyUrl
$env:ALL_PROXY = $proxyUrl
$env:NO_PROXY = $noProxyValue
$env:http_proxy = $proxyUrl
$env:https_proxy = $proxyUrl
$env:all_proxy = $proxyUrl
$env:no_proxy = $noProxyValue

Start-Process -FilePath $candidatePaths[0]
