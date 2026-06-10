# codex-local-proxy-launcher

<p align="right">
  <a href="#中文"><kbd>中文</kbd></a>
  <a href="#english"><kbd>English</kbd></a>
</p>

<a id="中文"></a>

## 中文

一个给 Codex Desktop 用的双端代理启动器。它只给 Codex 进程注入代理环境变量，不改系统代理、不改 TUN 路由、不改注册表、不改 Codex 配置。

适合这种情况：VS Code 里的 Codex 能联网，因为 VS Code 自己配了代理；但 Codex 桌面端不走代理，打开会断网、重连、WebSocket 失败。

启动器会给 Codex 设置这些环境变量：

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
```

## 平台支持

- macOS：提供 `.app` 启动器和 `.command` 脚本
- Windows：提供 PowerShell 启动器、`.cmd` 双击入口和桌面快捷方式生成脚本

## 使用前提

- 已安装 Codex Desktop。
- 代理客户端已经启动。
- 使用 HTTP 或 mixed 代理端口，不要填纯 SOCKS 端口。
  - v2rayN 常见端口是 `10808`。
  - Clash 类客户端常见端口是 `7890`。
- 启动前要先完全退出 Codex。已经运行的 Codex 进程不会继承新的代理环境变量。

## macOS 用法

双击：

```text
macos/Codex Launcher.app
```

或者运行：

```bash
./macos/Launch\ Codex\ With\ Proxy.command
```

如果 macOS 下载后拦截应用，右键 `Codex Launcher.app`，点一次 **打开**。本地开发时也可以执行：

```bash
xattr -dr com.apple.quarantine ./macos/Codex\ Launcher.app
```

## Windows 用法

双击：

```text
windows\Launch Codex With Proxy.cmd
```

或者运行 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Launch-Codex-With-Proxy.ps1
```

生成桌面快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Create-Codex-Launcher-Shortcut.ps1
```

Windows 版支持 Microsoft Store 安装的 Codex，会自动查找 `OpenAI.Codex` AppX 包，以及类似下面的路径：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_*\app\Codex.exe
```

## 自定义代理端口

默认端口是 `10808`。

有三种改法，优先级从高到低是：命令参数、环境变量、配置文件。

### 1. 命令参数

macOS：

```bash
./macos/Launch\ Codex\ With\ Proxy.command 7890
```

Windows PowerShell：

```powershell
.\windows\Launch-Codex-With-Proxy.ps1 -ProxyPort 7890
```

Windows cmd：

```bat
windows\Launch Codex With Proxy.cmd 7890
```

### 2. 环境变量

macOS：

```bash
CODEX_PROXY_PORT=7890 ./macos/Launch\ Codex\ With\ Proxy.command
```

Windows PowerShell：

```powershell
$env:CODEX_PROXY_PORT = "7890"
.\windows\Launch-Codex-With-Proxy.ps1
```

### 3. 配置文件

复制示例配置：

```bash
cp codex-proxy-launcher.env.example codex-proxy-launcher.env
```

然后改端口：

```env
CODEX_PROXY_PORT=10808
CODEX_PROXY_HOST=127.0.0.1
CODEX_PROXY_SCHEME=http
```

启动器会读取这些位置：

- 仓库根目录的 `codex-proxy-launcher.env`
- `macos/` 或 `windows/` 目录里的 `codex-proxy-launcher.env`
- macOS 的 `~/.codex-proxy-launcher.env`
- Windows 的 `%USERPROFILE%\.codex-proxy-launcher.env`
- `CODEX_PROXY_CONFIG` 指定的自定义配置文件

高级配置：

```env
CODEX_PROXY_URL=http://127.0.0.1:10808
CODEX_NO_PROXY=localhost,127.0.0.1,::1
CODEX_APP_PATH=/Applications/Codex.app/Contents/MacOS/Codex
CODEX_EXE=C:\Path\To\Codex.exe
```

## 常见问题

### 提示 proxy is not listening

先启动代理客户端。确认你填的是 HTTP/mixed 端口。如果端口不是 `10808`，设置 `CODEX_PROXY_PORT`。

### 提示 Codex is already running

完全退出 Codex，包括菜单栏或托盘里的后台进程，然后重新用这个启动器打开。

### Windows 找不到 Codex.exe

如果是 Microsoft Store 安装，先更新或重装 Codex，再运行启动器。如果安装路径很特殊，在配置文件里设置 `CODEX_EXE`。

### 纯 SOCKS 端口不工作

请使用代理客户端的 HTTP 或 mixed 端口。本工具的目标是给 Codex 设置 HTTP 代理环境变量。

## 为什么不直接改系统代理

很多人代理客户端会一会开一会关。如果把系统代理固定成 `127.0.0.1:10808`，代理客户端关闭时，整个系统网络都可能坏掉。

这个启动器只影响它启动出来的 Codex 进程。代理客户端关了，系统其他应用不受影响。

## 项目名建议

推荐用 `codex-local-proxy-launcher`。它比 `codex_networkfix` 更地道，也比 `codex-proxy-launcher` 更不容易和已有项目撞名。

## 免责声明

这是非官方工具，不隶属于 OpenAI。Codex 和 OpenAI 是其各自所有者的商标或产品名。

## License

MIT

---

<a id="english"></a>

## English

<p align="right">
  <a href="#中文"><kbd>中文</kbd></a>
  <a href="#english"><kbd>English</kbd></a>
</p>

A cross-platform proxy launcher for Codex Desktop. It injects proxy environment variables only into the Codex process. It does not modify system proxy settings, TUN routes, registry keys, or Codex configuration files.

This is useful when Codex works inside VS Code because VS Code has its own proxy settings, but Codex Desktop cannot connect directly and keeps reconnecting or failing WebSocket connections.

The launcher sets these variables for Codex:

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
```

## Supported platforms

- macOS: `.app` launcher and `.command` wrapper
- Windows: PowerShell launcher, `.cmd` wrapper, and desktop shortcut generator

## Requirements

- Codex Desktop is already installed.
- Your proxy client is already running.
- Use an HTTP or mixed proxy port, not a SOCKS-only port.
  - v2rayN commonly uses `10808`.
  - Clash-like clients commonly use `7890`.
- Quit Codex completely before launching it through this tool. Existing Codex processes cannot inherit new environment variables.

## macOS usage

Open:

```text
macos/Codex Launcher.app
```

Or run:

```bash
./macos/Launch\ Codex\ With\ Proxy.command
```

If macOS blocks the app after download, right-click `Codex Launcher.app` and choose **Open** once. For local development, you can also run:

```bash
xattr -dr com.apple.quarantine ./macos/Codex\ Launcher.app
```

## Windows usage

Double-click:

```text
windows\Launch Codex With Proxy.cmd
```

Or run PowerShell directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Launch-Codex-With-Proxy.ps1
```

Create a desktop shortcut:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Create-Codex-Launcher-Shortcut.ps1
```

Microsoft Store installs are supported. The Windows launcher checks the `OpenAI.Codex` AppX package and paths like:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_*\app\Codex.exe
```

## Custom proxy port

The default port is `10808`.

You can override it in three ways. Priority order: command argument, environment variable, config file.

### 1. Command argument

macOS:

```bash
./macos/Launch\ Codex\ With\ Proxy.command 7890
```

Windows PowerShell:

```powershell
.\windows\Launch-Codex-With-Proxy.ps1 -ProxyPort 7890
```

Windows cmd:

```bat
windows\Launch Codex With Proxy.cmd 7890
```

### 2. Environment variable

macOS:

```bash
CODEX_PROXY_PORT=7890 ./macos/Launch\ Codex\ With\ Proxy.command
```

Windows PowerShell:

```powershell
$env:CODEX_PROXY_PORT = "7890"
.\windows\Launch-Codex-With-Proxy.ps1
```

### 3. Config file

Copy the example config:

```bash
cp codex-proxy-launcher.env.example codex-proxy-launcher.env
```

Then edit the port:

```env
CODEX_PROXY_PORT=10808
CODEX_PROXY_HOST=127.0.0.1
CODEX_PROXY_SCHEME=http
```

The launcher reads config from:

- `codex-proxy-launcher.env` in the repository root
- `codex-proxy-launcher.env` inside `macos/` or `windows/`
- `~/.codex-proxy-launcher.env` on macOS
- `%USERPROFILE%\.codex-proxy-launcher.env` on Windows
- a custom path from `CODEX_PROXY_CONFIG`

Advanced overrides:

```env
CODEX_PROXY_URL=http://127.0.0.1:10808
CODEX_NO_PROXY=localhost,127.0.0.1,::1
CODEX_APP_PATH=/Applications/Codex.app/Contents/MacOS/Codex
CODEX_EXE=C:\Path\To\Codex.exe
```

## Troubleshooting

### proxy is not listening

Start your proxy client first. Make sure you are using its HTTP or mixed proxy port. If your port is not `10808`, set `CODEX_PROXY_PORT`.

### Codex is already running

Quit Codex completely, including any menu-bar or tray process, then launch it again through this tool.

### Windows cannot find Codex.exe

If Codex is installed from Microsoft Store, update or reinstall it, then run the launcher again. If your install path is unusual, set `CODEX_EXE`.

### SOCKS-only proxy does not work

Use your proxy client's HTTP or mixed proxy port. This tool is designed around HTTP proxy environment variables.

## Why not use system proxy?

Many users turn their proxy clients on and off frequently. If the system proxy is fixed to `127.0.0.1:10808`, network access can break when the proxy client is off.

This launcher only affects the Codex process it starts. Other apps are not affected when your proxy client is off.

## Naming

Recommended repository name: `codex-local-proxy-launcher`. It is more idiomatic than `codex_networkfix` and less likely to collide with existing `codex-proxy-launcher` repositories.

## Disclaimer

This is an unofficial tool and is not affiliated with OpenAI. Codex and OpenAI are trademarks or product names of their respective owners.

## License

MIT
