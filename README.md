# codex-local-proxy-launcher

<p>
  <a href="#中文">中文</a> |
  <a href="#english">English</a>
</p>

<a id="中文"></a>

一个适用于 Codex Desktop 的跨平台代理启动器。它会在启动 Codex 前注入本地代理环境变量，并且只影响这一次启动出来的 Codex 进程；不会修改系统代理、TUN 路由、注册表，也不会改动 Codex 自己的配置文件。

适合这种情况：Codex 桌面端连不上、反复 `Reconnecting`、WebSocket 失败，但你又不想为了它打开系统级代理或全局 TUN。

启动器会给 Codex 注入这些环境变量：

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
```

支持 macOS 和 Windows。默认代理地址是 `http://127.0.0.1:10808`，也就是很多 v2rayN 配置里的 HTTP/mixed 端口。Clash 类客户端常见端口是 `7890`，可以按下面的用法传进去。

## 使用前

- 先安装 Codex Desktop。
- 先启动你的代理客户端。
- 使用 HTTP 或 mixed 端口，不要填纯 SOCKS 端口。
- 启动前完全退出 Codex。已经运行的 Codex 进程不会继承新的环境变量。

## macOS

默认端口 `10808`，直接双击：

```text
macos/Codex Launcher.app
```

也可以从终端运行：

```bash
./macos/Launch\ Codex\ With\ Proxy.command
```

如果你的代理端口不是 `10808`，把端口作为参数传进去：

```bash
./macos/Launch\ Codex\ With\ Proxy.command 7890
```

或者临时用环境变量：

```bash
CODEX_PROXY_PORT=7890 ./macos/Launch\ Codex\ With\ Proxy.command
```

如果 macOS 下载后拦截应用，右键 `Codex Launcher.app`，选择 **打开**。本地开发时也可以去掉 quarantine 标记：

```bash
xattr -dr com.apple.quarantine ./macos/Codex\ Launcher.app
```

仓库不会内置 Codex 官方图标。macOS 版默认用一个本机 symlink 指向 `/Applications/Codex.app` 里的图标；如果 Codex 装在别的位置，或者 Finder 还显示默认应用图标，可以手动刷新一次：

```bash
./macos/Install\ Codex\ Icon.command
```

## Windows

默认端口 `10808`，直接双击：

```text
windows\Launch Codex With Proxy.cmd
```

也可以从 PowerShell 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Launch-Codex-With-Proxy.ps1
```

如果你的代理端口不是 `10808`，把端口作为参数传进去：

```bat
windows\Launch Codex With Proxy.cmd 7890
```

或者用 PowerShell 参数：

```powershell
.\windows\Launch-Codex-With-Proxy.ps1 -ProxyPort 7890
```

也可以临时用环境变量：

```powershell
$env:CODEX_PROXY_PORT = "7890"
.\windows\Launch-Codex-With-Proxy.ps1
```

生成桌面快捷方式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Create-Codex-Launcher-Shortcut.ps1
```

如果快捷方式也要固定端口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Create-Codex-Launcher-Shortcut.ps1 -ProxyPort 7890
```

Windows 版支持 Microsoft Store 安装的 Codex，会自动查找 `OpenAI.Codex` AppX 包，以及类似下面的路径：

```text
C:\Program Files\WindowsApps\OpenAI.Codex_*\app\Codex.exe
```

## 配置文件

如果不想每次传端口，可以用配置文件。双击 macOS `.app` 时尤其推荐这种方式。

复制仓库里的示例配置：

```bash
cp codex-proxy-launcher.env.example codex-proxy-launcher.env
nano codex-proxy-launcher.env
```

或者直接创建用户级配置文件，放到这里后，launcher 放在哪都能读取：

```bash
nano ~/.codex-proxy-launcher.env
```

写入常用配置：

```env
CODEX_PROXY_PORT=10808
CODEX_PROXY_HOST=127.0.0.1
CODEX_PROXY_SCHEME=http
```

Windows 用户也可以创建用户级配置：

```powershell
notepad "$env:USERPROFILE\.codex-proxy-launcher.env"
```

启动器会读取这些位置：

- 仓库根目录的 `codex-proxy-launcher.env`
- `macos/` 或 `windows/` 目录里的 `codex-proxy-launcher.env`
- macOS 的 `~/.codex-proxy-launcher.env`
- Windows 的 `%USERPROFILE%\.codex-proxy-launcher.env`
- `CODEX_PROXY_CONFIG` 指定的自定义配置文件

更少见的情况可以直接覆盖完整代理地址或 Codex 路径：

```env
CODEX_PROXY_URL=http://127.0.0.1:10808
CODEX_NO_PROXY=localhost,127.0.0.1,::1
CODEX_APP_PATH=/Applications/Codex.app/Contents/MacOS/Codex
CODEX_EXE=C:\Path\To\Codex.exe
```

## 常见问题

### proxy is not listening

代理客户端没开，或者端口填错了。确认你填的是 HTTP/mixed 端口。如果端口不是 `10808`，用参数、环境变量或配置文件改掉。

### Codex is already running

先把 Codex 完全退出，包括菜单栏或托盘里的后台进程。环境变量只会传给启动器新打开的 Codex。

### Windows 找不到 Codex.exe

如果是 Microsoft Store 安装，先更新或重装 Codex，再运行启动器。如果安装路径很特殊，在配置文件里设置 `CODEX_EXE`。

### 纯 SOCKS 端口不工作

请使用代理客户端的 HTTP 或 mixed 端口。这个工具走的是 HTTP 代理环境变量，不是 SOCKS 转发器。

## 为什么不直接改系统代理

很多人会频繁开关代理客户端。如果把系统代理固定成 `127.0.0.1:10808`，代理客户端一关，系统网络就可能跟着坏掉。

这个启动器只影响它启动出来的 Codex。代理客户端关了，系统其他应用不受影响。

## 免责声明

这是非官方工具，不隶属于 OpenAI。Codex 和 OpenAI 是其各自所有者的商标或产品名。

## License

MIT

---

<a id="english"></a>

A cross-platform proxy launcher for Codex Desktop. It injects local proxy environment variables before starting Codex, and the change only applies to the Codex process started by this launcher. It does not touch system proxy settings, TUN routes, registry keys, or Codex configuration files.

Use it when Codex Desktop cannot connect, keeps reconnecting, or fails WebSocket connections, and you do not want to enable a system-wide proxy or global TUN just for Codex.

The launcher injects these variables into Codex:

```text
HTTP_PROXY
HTTPS_PROXY
ALL_PROXY
NO_PROXY
```

macOS and Windows are supported. The default proxy address is `http://127.0.0.1:10808`, which is a common HTTP/mixed proxy port for v2rayN. Clash-like clients often use `7890`; pass that port with the commands below if needed.

## Before you start

- Install Codex Desktop first.
- Start your proxy client first.
- Use an HTTP or mixed proxy port, not a SOCKS-only port.
- Quit Codex completely before launching it through this tool. Existing Codex processes cannot inherit new environment variables.

## macOS

Default port `10808`, open:

```text
macos/Codex Launcher.app
```

Or run from Terminal:

```bash
./macos/Launch\ Codex\ With\ Proxy.command
```

If your proxy uses another port, pass it as an argument:

```bash
./macos/Launch\ Codex\ With\ Proxy.command 7890
```

Or set it temporarily with an environment variable:

```bash
CODEX_PROXY_PORT=7890 ./macos/Launch\ Codex\ With\ Proxy.command
```

If macOS blocks the app after download, right-click `Codex Launcher.app` and choose **Open**. For local development, you can also remove the quarantine flag:

```bash
xattr -dr com.apple.quarantine ./macos/Codex\ Launcher.app
```

The repository does not bundle the official Codex icon. The macOS app uses a local symlink to the icon inside `/Applications/Codex.app` by default. If Codex is installed somewhere else, or Finder still shows the default app icon, refresh it manually:

```bash
./macos/Install\ Codex\ Icon.command
```

## Windows

Default port `10808`, double-click:

```text
windows\Launch Codex With Proxy.cmd
```

Or run from PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Launch-Codex-With-Proxy.ps1
```

If your proxy uses another port, pass it as an argument:

```bat
windows\Launch Codex With Proxy.cmd 7890
```

Or use the PowerShell parameter:

```powershell
.\windows\Launch-Codex-With-Proxy.ps1 -ProxyPort 7890
```

Or set it temporarily with an environment variable:

```powershell
$env:CODEX_PROXY_PORT = "7890"
.\windows\Launch-Codex-With-Proxy.ps1
```

Create a desktop shortcut:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Create-Codex-Launcher-Shortcut.ps1
```

Create a shortcut pinned to another port:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\windows\Create-Codex-Launcher-Shortcut.ps1 -ProxyPort 7890
```

Microsoft Store installs are supported. The Windows launcher checks the `OpenAI.Codex` AppX package and paths like:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_*\app\Codex.exe
```

## Config file

To avoid passing the port every time, use a config file. This is especially useful when opening the macOS `.app` directly.

Copy the example config:

```bash
cp codex-proxy-launcher.env.example codex-proxy-launcher.env
nano codex-proxy-launcher.env
```

Or create a user-level config file directly, which works no matter where the launcher is located:

```bash
nano ~/.codex-proxy-launcher.env
```

Common settings:

```env
CODEX_PROXY_PORT=10808
CODEX_PROXY_HOST=127.0.0.1
CODEX_PROXY_SCHEME=http
```

Windows users can also create a user-level config file:

```powershell
notepad "$env:USERPROFILE\.codex-proxy-launcher.env"
```

The launcher reads config from:

- `codex-proxy-launcher.env` in the repository root
- `codex-proxy-launcher.env` inside `macos/` or `windows/`
- `~/.codex-proxy-launcher.env` on macOS
- `%USERPROFILE%\.codex-proxy-launcher.env` on Windows
- a custom file specified by `CODEX_PROXY_CONFIG`

Advanced overrides:

```env
CODEX_PROXY_URL=http://127.0.0.1:10808
CODEX_NO_PROXY=localhost,127.0.0.1,::1
CODEX_APP_PATH=/Applications/Codex.app/Contents/MacOS/Codex
CODEX_EXE=C:\Path\To\Codex.exe
```

## Troubleshooting

### proxy is not listening

Your proxy client is not running, or the port is wrong. Make sure you are using the HTTP/mixed proxy port. If the port is not `10808`, set it with an argument, environment variable, or config file.

### Codex is already running

Quit Codex completely, including any menu-bar or tray process. Environment variables only apply to the Codex process started by this launcher.

### Windows cannot find Codex.exe

If Codex is installed from Microsoft Store, update or reinstall it, then run the launcher again. If your install path is unusual, set `CODEX_EXE` in the config file.

### SOCKS-only proxy does not work

Use your proxy client's HTTP or mixed proxy port. This tool uses HTTP proxy environment variables; it is not a SOCKS forwarder.

## Why not use system proxy?

Many users turn proxy clients on and off frequently. If the system proxy is fixed to `127.0.0.1:10808`, network access can break when the proxy client is off.

This launcher only affects the Codex process it starts. Other apps are not affected when your proxy client is off.

## Disclaimer

This is an unofficial tool and is not affiliated with OpenAI. Codex and OpenAI are trademarks or product names of their respective owners.

## License

MIT
