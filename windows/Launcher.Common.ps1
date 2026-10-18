function Get-LauncherSettingsPath {
    $directory = [Environment]::GetFolderPath("ApplicationData")
    if (-not $directory) { $directory = Join-Path $HOME ".config" }
    return Join-Path $directory "codex-local-proxy-launcher/settings.json"
}

function Import-LauncherConfig([string]$ScriptDirectory) {
    $allowed = @(
        "CODEX_PROXY_PORT", "CODEX_PROXY_HOST", "CODEX_PROXY_SCHEME",
        "CODEX_PROXY_URL", "CODEX_EXE", "CHATGPT_EXE", "CODEX_NO_PROXY"
    )
    $config = @{}
    $guiAppPath = $false
    $settingsPath = Get-LauncherSettingsPath
    if (Test-Path -LiteralPath $settingsPath -PathType Leaf) {
        $settings = Get-Content -LiteralPath $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $settings.PSObject.Properties) {
            if ($property.Name -in @("CHATGPT_EXE", "CODEX_EXE")) { $guiAppPath = $true }
            if ($allowed -contains $property.Name -and $property.Value) {
                $config[$property.Name] = [string]$property.Value
            }
        }
    }
    $paths = @()
    if ($env:CODEX_PROXY_CONFIG) {
        if (-not (Test-Path -LiteralPath $env:CODEX_PROXY_CONFIG -PathType Leaf)) {
            throw "Config file not found: $env:CODEX_PROXY_CONFIG"
        }
        $paths += $env:CODEX_PROXY_CONFIG
    }
    $paths += Join-Path $ScriptDirectory "codex-proxy-launcher.env"
    $paths += Join-Path (Split-Path -Parent $ScriptDirectory) "codex-proxy-launcher.env"
    $paths += Join-Path $HOME ".codex-proxy-launcher.env"

    foreach ($path in ($paths | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            continue
        }
        foreach ($line in Get-Content -LiteralPath $path -Encoding UTF8) {
            $trimmed = $line.Trim().TrimStart([char]0xFEFF)
            if (-not $trimmed -or $trimmed.StartsWith("#") -or -not $trimmed.Contains("=")) {
                continue
            }
            $separator = $trimmed.IndexOf("=")
            $key = $trimmed.Substring(0, $separator).Trim()
            if ($guiAppPath -and $key -in @("CHATGPT_EXE", "CODEX_EXE")) { continue }
            $value = $trimmed.Substring($separator + 1).Trim()
            if ($value -match '^"(.*)"(\s+#.*)?$' -or $value -match "^'(.*)'(\s+#.*)?$") {
                $value = $Matches[1]
            } else {
                $value = ($value -replace '\s+#.*$', '').Trim()
            }
            if ($allowed -contains $key -and -not $config[$key]) {
                $config[$key] = $value
            }
        }
    }
    foreach ($key in $allowed) {
        $value = [Environment]::GetEnvironmentVariable($key, "Process")
        if ($value) {
            $config[$key] = $value
        }
    }
    return $config
}

function Get-ConfigValue($Config, [string]$Name, [string]$DefaultValue) {
    if ($Config[$Name]) {
        return $Config[$Name]
    }
    return $DefaultValue
}

function Get-CodexExeCandidates($Config) {
    $override = Get-ConfigValue $Config "CHATGPT_EXE" $Config["CODEX_EXE"]
    if ($override) {
        if (-not (Test-Path -LiteralPath $override -PathType Leaf)) {
            throw "Configured application not found: $override"
        }
        $override
        return
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
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $path
        }
    }
    foreach ($packageName in @("OpenAI.ChatGPT", "OpenAI.Codex")) {
        try {
            Get-AppxPackage -Name $packageName -ErrorAction Stop |
                Sort-Object Version -Descending |
                ForEach-Object {
                    $package = $_
                    if (-not $package.InstallLocation) {
                        return
                    }
                    try {
                        $manifest = Get-AppxPackageManifest -Package $package.PackageFullName -ErrorAction Stop
                        foreach ($application in @($manifest.Package.Applications.Application)) {
                            $relativeExe = [string]$application.Executable
                            if ($relativeExe -match '(?i)(^|[\\/])(ChatGPT|Codex)\.exe$') {
                                $exe = Join-Path $package.InstallLocation $relativeExe
                                if (Test-Path -LiteralPath $exe -PathType Leaf) {
                                    $exe
                                }
                            }
                        }
                    } catch {
                        # Fall back to known layouts if the manifest cannot be read.
                    }
                    foreach ($relativePath in @("app\ChatGPT.exe", "app\Codex.exe", "ChatGPT.exe", "Codex.exe")) {
                        $exe = Join-Path $package.InstallLocation $relativePath
                        if (Test-Path -LiteralPath $exe -PathType Leaf) {
                            $exe
                        }
                    }
                }
        } catch {
            # AppX commands are unavailable on some non-Store installations.
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
        Get-ChildItem -Path $path -File -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -ExpandProperty FullName
    }
}

function Get-LauncherProxy($Config, [string]$PortArgument) {
    $proxyHost = Get-ConfigValue $Config "CODEX_PROXY_HOST" "127.0.0.1"
    $scheme = Get-ConfigValue $Config "CODEX_PROXY_SCHEME" "http"
    $portText = Get-ConfigValue $Config "CODEX_PROXY_PORT" "10808"
    if ($PortArgument) {
        $portText = $PortArgument
    }
    $proxyUrl = $Config["CODEX_PROXY_URL"]
    if (-not $proxyUrl) {
        $proxyHost = $proxyHost.Trim([char[]]"[]")
        if ($proxyHost.Contains(":")) {
            $proxyHost = "[$proxyHost]"
        }
        $proxyUrl = "{0}://{1}:{2}" -f $scheme, $proxyHost, $portText
    }
    $uri = $null
    if (
        -not [Uri]::TryCreate($proxyUrl, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -notin @("http", "https") -or
        -not $uri.Host -or $uri.Host.StartsWith("-") -or
        $uri.AbsolutePath -ne "/" -or $uri.Query -or $uri.Fragment -or
        $proxyUrl -match '\s|://[^/?#]*:/$|://[^/?#]*:$'
    ) {
        throw "Invalid proxy URL. Use http://host:port or https://host:port (IPv6 addresses need brackets)."
    }
    if (-not $Config["CODEX_PROXY_URL"] -and $portText -notmatch '^[0-9]{1,5}$') {
        throw "Invalid proxy port: use a number from 1 to 65535."
    }
    if ($uri.Port -lt 1 -or $uri.Port -gt 65535) {
        throw "Invalid proxy port: use a number from 1 to 65535."
    }
    return @{
        Url = $proxyUrl
        HostName = $uri.DnsSafeHost.Trim([char[]]"[]")
        Port = $uri.Port
    }
}

function Test-LauncherProxy($ProxySettings) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connection = $client.ConnectAsync($ProxySettings.HostName, $ProxySettings.Port)
        if (-not $connection.Wait(3000)) {
            return $false
        }
        $connection.GetAwaiter().GetResult()
        return $true
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

function Get-RunningDesktopApp([string]$Executable) {
    $processName = [IO.Path]::GetFileNameWithoutExtension($Executable)
    Get-Process -Name $processName -ErrorAction SilentlyContinue | Where-Object {
        try {
            [string]::Equals($_.Path, [IO.Path]::GetFullPath($Executable), [StringComparison]::OrdinalIgnoreCase)
        } catch {
            $false
        }
    }
}

function Start-ProxiedApp([string]$Executable, $ProxySettings, [string]$NoProxy) {
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $Executable
    $startInfo.UseShellExecute = $false
    foreach ($key in @("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy")) {
        $startInfo.EnvironmentVariables[$key] = $ProxySettings.Url
    }
    $startInfo.EnvironmentVariables["NO_PROXY"] = $NoProxy
    $startInfo.EnvironmentVariables["no_proxy"] = $NoProxy
    $process = [Diagnostics.Process]::Start($startInfo)
    $process.Dispose()
}
