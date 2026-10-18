import AppKit
import Foundation
import UniformTypeIdentifiers

private func text(_ chinese: String, _ english: String) -> String {
    Locale.preferredLanguages.first?.hasPrefix("zh") == true ? chinese : english
}

final class SettingsDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private let host = NSTextField(string: "127.0.0.1")
    private let port = NSTextField(string: "10808")
    private let scheme = NSPopUpButton()
    private let desktop = NSTextField(string: "")
    private let launcher = NSTextField(string: "")
    private let appearance = NSPopUpButton()
    private let status = NSTextField(wrappingLabelWithString: "")
    private var iconButtons: [NSButton] = []
    private var iconPreviews: [NSButton] = []
    private var commands: [NSButton] = []
    private var selectedStyle = "chatgpt"
    private var saved: [String: String] = [:]
    private let settingsURL: URL

    init(settingsURL: URL? = nil) {
        self.settingsURL = settingsURL ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/codex-local-proxy-launcher/settings.json")
        super.init()
    }

    func selfTest(in directory: URL) throws {
        let target = directory.appendingPathComponent("Codex Launcher.app")
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Codex Launcher.app")
        try FileManager.default.copyItem(at: sibling, to: target)
        scheme.addItems(withTitles: ["HTTP", "HTTPS"])
        scheme.selectItem(at: 0)
        appearance.addItems(withTitles: ["Auto", "Light", "Dark"])
        appearance.selectItem(at: 0)
        host.stringValue = "::1"
        port.stringValue = "7890"
        launcher.stringValue = target.path
        try persist()
        let stored = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: settingsURL))
        guard stored["CODEX_PROXY_URL"] == "http://[::1]:7890" else { throw CocoaError(.fileReadCorruptFile) }
        port.stringValue = "65536"
        do { try persist(); throw CocoaError(.validationMissingMandatoryProperty) }
        catch let error as NSError where error.domain == "Launcher" {}
        let reloaded = SettingsDelegate(settingsURL: settingsURL)
        reloaded.load()
        guard reloaded.host.stringValue == "::1", reloaded.port.stringValue == "7890" else {
            throw CocoaError(.fileReadCorruptFile)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        load()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 500),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = text("Codex Launcher 设置", "Codex Launcher Settings")
        window.isReleasedWhenClosed = false
        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 24)
        ])
        let title = NSTextField(labelWithString: text("代理设置", "Proxy Settings"))
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        root.addArrangedSubview(title)
        scheme.addItems(withTitles: ["HTTP", "HTTPS"])
        scheme.selectItem(withTitle: (saved["CODEX_PROXY_SCHEME"] ?? "http").uppercased())
        let proxyRow = NSStackView(views: [host, NSTextField(labelWithString: text("端口", "Port")), port, scheme])
        proxyRow.spacing = 10
        host.widthAnchor.constraint(equalToConstant: 210).isActive = true
        port.widthAnchor.constraint(equalToConstant: 80).isActive = true
        root.addArrangedSubview(row(text("代理地址", "Proxy Host"), proxyRow))
        desktop.placeholderString = text("自动查找 ChatGPT / Codex", "Find ChatGPT / Codex automatically")
        desktop.target = self
        desktop.action = #selector(refreshIcons)
        root.addArrangedSubview(row(text("桌面应用", "Desktop App"), desktop, action: #selector(browseDesktop)))
        root.addArrangedSubview(row(text("启动器", "Launcher"), launcher, action: #selector(browseLauncher)))
        root.addArrangedSubview(NSBox.separator())
        let iconTitle = NSTextField(labelWithString: text("启动器图标", "Launcher Icon"))
        iconTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        root.addArrangedSubview(iconTitle)
        let icons = NSStackView()
        icons.distribution = .fillEqually
        icons.spacing = 12
        for (index, name) in ["ChatGPT", "Codex", "Space"].enumerated() {
            let preview = NSButton(title: "", target: self, action: #selector(selectIcon(_:)))
            preview.isBordered = false
            preview.imageScaling = .scaleProportionallyDown
            preview.tag = index
            preview.toolTip = name
            preview.widthAnchor.constraint(equalToConstant: 64).isActive = true
            preview.heightAnchor.constraint(equalToConstant: 64).isActive = true
            iconPreviews.append(preview)
            let button = NSButton(radioButtonWithTitle: name, target: self, action: #selector(selectIcon(_:)))
            button.tag = index
            button.toolTip = name
            iconButtons.append(button)
            let choice = NSStackView(views: [preview, button])
            choice.orientation = .vertical
            choice.alignment = .centerX
            choice.spacing = 8
            choice.widthAnchor.constraint(equalToConstant: 175).isActive = true
            choice.heightAnchor.constraint(equalToConstant: 96).isActive = true
            icons.addArrangedSubview(choice)
        }
        root.addArrangedSubview(icons)
        appearance.addItems(withTitles: [text("当前系统外观", "Current System Appearance"), text("浅色", "Light"), text("深色", "Dark")])
        let appearanceIndex = ["auto", "light", "dark"].firstIndex(of: saved["CODEX_ICON_APPEARANCE"] ?? "auto") ?? 0
        appearance.selectItem(at: appearanceIndex)
        appearance.target = self
        appearance.action = #selector(refreshIcons)
        let change = button(text("应用图标", "Apply Icon"), "paintbrush", #selector(changeIcon))
        let iconRow = NSStackView(views: [appearance, change])
        iconRow.spacing = 12
        root.addArrangedSubview(iconRow)
        root.addArrangedSubview(NSBox.separator())
        let save = button(text("保存设置", "Save Settings"), "checkmark", #selector(saveSettings))
        let launch = button(text("启动 Codex", "Launch Codex"), "play.fill", #selector(launchApp))
        let buttons = NSStackView(views: [save, launch])
        buttons.spacing = 12
        root.addArrangedSubview(buttons)
        status.font = .systemFont(ofSize: 12)
        status.textColor = .secondaryLabelColor
        status.maximumNumberOfLines = 3
        status.widthAnchor.constraint(equalToConstant: 600).isActive = true
        root.addArrangedSubview(status)
        refreshIcons()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func row(_ label: String, _ control: NSView, action: Selector? = nil) -> NSStackView {
        let name = NSTextField(labelWithString: label)
        name.widthAnchor.constraint(equalToConstant: 92).isActive = true
        let stack = NSStackView(views: [name, control])
        stack.spacing = 10
        if let action = action {
            let browse = NSButton(title: text("选择…", "Browse…"), target: self, action: action)
            stack.addArrangedSubview(browse)
            control.widthAnchor.constraint(equalToConstant: 390).isActive = true
        }
        return stack
    }

    private func button(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
        let control = NSButton(title: title, target: self, action: action)
        control.bezelStyle = .rounded
        control.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        control.imagePosition = .imageLeading
        commands.append(control)
        return control
    }

    private func load() {
        if let data = try? Data(contentsOf: settingsURL),
           let values = try? JSONDecoder().decode([String: String].self, from: data) { saved = values }
        host.stringValue = saved["CODEX_PROXY_HOST"] ?? "127.0.0.1"
        port.stringValue = saved["CODEX_PROXY_PORT"] ?? "10808"
        desktop.stringValue = saved["CODEX_APP_PATH"] ?? ""
        let installed = "/Applications/Codex Launcher.app"
        let sibling = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Codex Launcher.app").path
        launcher.stringValue = saved["launcherAppPath"] ?? (FileManager.default.fileExists(atPath: installed) ? installed : sibling)
        selectedStyle = saved["CODEX_ICON_STYLE"] ?? "chatgpt"
    }

    private func values() throws -> [String: String] {
        let hostname = host.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let number = Int(port.stringValue), (1...65535).contains(number),
              !hostname.isEmpty, hostname.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !hostname.contains("/"), !hostname.contains("@") else {
            throw NSError(domain: "Launcher", code: 1, userInfo: [NSLocalizedDescriptionKey: text("请填写有效的代理地址和 1–65535 之间的端口。", "Enter a valid proxy host and a port between 1 and 65535.")])
        }
        let plainHost = hostname.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let urlHost = plainHost.contains(":") ? "[\(plainHost)]" : plainHost
        let protocolName = scheme.titleOfSelectedItem!.lowercased()
        let url = "\(protocolName)://\(urlHost):\(number)"
        guard !plainHost.hasPrefix("-"), let parsed = URLComponents(string: url), parsed.url != nil,
              parsed.host != nil, parsed.port == number, parsed.path.isEmpty, parsed.query == nil, parsed.fragment == nil else {
            throw NSError(domain: "Launcher", code: 1, userInfo: [NSLocalizedDescriptionKey: text("代理地址格式不正确。", "Invalid proxy address.")])
        }
        var result = saved
        result["CODEX_PROXY_HOST"] = plainHost
        result["CODEX_PROXY_PORT"] = String(number)
        result["CODEX_PROXY_SCHEME"] = protocolName
        result["CODEX_PROXY_URL"] = url
        result["CODEX_APP_PATH"] = desktop.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        result["launcherAppPath"] = launcher.stringValue
        result["CODEX_ICON_STYLE"] = selectedStyle
        result["CODEX_ICON_APPEARANCE"] = ["auto", "light", "dark"][appearance.indexOfSelectedItem]
        return result
    }

    private func persist() throws {
        let next = try values()
        try validateLauncher()
        try writePreferences(next)
    }

    private func validateLauncher() throws {
        guard Bundle(path: launcher.stringValue)?.bundleIdentifier == "io.github.codex-proxy-launcher" else {
            throw NSError(domain: "Launcher", code: 1, userInfo: [NSLocalizedDescriptionKey: text("请选择有效的 Codex Launcher.app。", "Select a valid Codex Launcher.app.")])
        }
    }

    private func writePreferences(_ next: [String: String]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: next, options: [.prettyPrinted, .sortedKeys]).write(to: settingsURL, options: .atomic)
        saved = next
    }

    @objc private func saveSettings() {
        do { try persist(); status.stringValue = text("已保存。下次从原启动器打开时生效。", "Saved. Applies next time you open the original launcher.") }
        catch { show(error) }
    }

    @objc private func launchApp() {
        do {
            try persist()
            let executable = URL(fileURLWithPath: launcher.stringValue).appendingPathComponent("Contents/MacOS/Codex Launcher")
            let process = Process()
            process.executableURL = executable
            process.environment = environment()
            try process.run()
            status.stringValue = text("已打开启动器。", "Launcher opened.")
        } catch { show(error) }
    }

    private func environment() -> [String: String] {
        var result = ProcessInfo.processInfo.environment
        for (key, value) in saved where key.hasPrefix("CODEX_") {
            result[key] = value.isEmpty ? nil : value
        }
        return result
    }

    @objc private func changeIcon() {
        do {
            try validateLauncher()
            var next = saved
            next["CODEX_ICON_STYLE"] = selectedStyle
            next["CODEX_ICON_APPEARANCE"] = ["auto", "light", "dark"][appearance.indexOfSelectedItem]
            next["launcherAppPath"] = launcher.stringValue
            try writePreferences(next)
            let script = Bundle.main.resourceURL!.appendingPathComponent("launcher-icon.zsh")
            let process = Process()
            let output = Pipe()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path, "--app", launcher.stringValue, "--style", selectedStyle,
                                 "--appearance", saved["CODEX_ICON_APPEARANCE"]!, "--no-dialog"]
            var iconEnvironment = environment()
            iconEnvironment["CODEX_APP_PATH"] = desktop.stringValue.isEmpty ? nil : desktop.stringValue
            process.environment = iconEnvironment
            process.standardOutput = output
            process.standardError = output
            commands.forEach { $0.isEnabled = false }
            status.stringValue = text("正在更换图标…", "Changing icon…")
            process.terminationHandler = { [weak self] finished in
                let detail = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    self.commands.forEach { $0.isEnabled = true }
                    if finished.terminationStatus == 0 {
                        self.status.stringValue = text("图标已更换，Dock 缓存可能稍后刷新。", "Icon changed. The Dock cache may refresh shortly.")
                    } else {
                        self.status.stringValue = text("更换失败，原启动器已保留。", "Change failed; the original launcher was retained.")
                        let alert = NSAlert()
                        alert.messageText = self.status.stringValue
                        alert.informativeText = String(detail.suffix(1600))
                        alert.runModal()
                    }
                }
            }
            try process.run()
        } catch {
            commands.forEach { $0.isEnabled = true }
            show(error)
        }
    }

    @objc private func selectIcon(_ sender: NSButton) {
        selectedStyle = ["chatgpt", "codex", "space"][sender.tag]
        refreshIcons()
    }

    private func sourceResources() -> URL? {
        let candidates = desktop.stringValue.isEmpty
            ? ["/Applications/ChatGPT.app", NSHomeDirectory() + "/Applications/ChatGPT.app", "/Applications/Codex.app"]
            : [desktop.stringValue]
        for path in candidates {
            let url = URL(fileURLWithPath: path)
            let resources = path.hasSuffix(".app") ? url.appendingPathComponent("Contents/Resources")
                : url.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Resources")
            if FileManager.default.fileExists(atPath: resources.path) { return resources }
        }
        return nil
    }

    @objc private func refreshIcons() {
        let dark = appearance.indexOfSelectedItem == 2 || (appearance.indexOfSelectedItem == 0 &&
            NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        let names = ["icon-chatgpt.png", dark ? "icon-codex-dark-color.png" : "icon-codex-light.png", dark ? "icon-space-dark.png" : "icon-space-light.png"]
        for (index, button) in iconButtons.enumerated() {
            let url = sourceResources()?.appendingPathComponent(names[index])
            let image = url.flatMap { NSImage(contentsOf: $0) }
            image?.size = NSSize(width: 64, height: 64)
            iconPreviews[index].image = image ?? NSImage(systemSymbolName: "questionmark.square.dashed", accessibilityDescription: text("本机缺少此图标", "Icon unavailable locally"))
            button.state = selectedStyle == ["chatgpt", "codex", "space"][index] ? .on : .off
        }
    }

    @objc private func browseDesktop() { browse(into: desktop) }
    @objc private func browseLauncher() { browse(into: launcher) }
    private func browse(into field: NSTextField) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { field.stringValue = panel.url!.path; refreshIcons() }
    }

    private func show(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

private extension NSBox {
    static func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; box.widthAnchor.constraint(equalToConstant: 600).isActive = true; return box }
}

let app = NSApplication.shared
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--self-test" {
    let directory = URL(fileURLWithPath: CommandLine.arguments[2])
    do {
        try SettingsDelegate(settingsURL: directory.appendingPathComponent("settings.json")).selfTest(in: directory)
        print("macOS settings validation and persistence checks passed.")
        exit(0)
    } catch {
        fputs("Settings test failed: \(error)\n", stderr)
        exit(1)
    }
}
let delegate = SettingsDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
let menu = NSMenu()
let applicationMenu = NSMenu()
let applicationItem = NSMenuItem()
applicationItem.submenu = applicationMenu
applicationMenu.addItem(withTitle: text("退出设置", "Quit Settings"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
menu.addItem(applicationItem)
let editMenu = NSMenu(title: text("编辑", "Edit"))
let editItem = NSMenuItem(title: editMenu.title, action: nil, keyEquivalent: "")
editItem.submenu = editMenu
for (title, selector, key) in [(text("剪切", "Cut"), "cut:", "x"), (text("复制", "Copy"), "copy:", "c"),
                              (text("粘贴", "Paste"), "paste:", "v"), (text("全选", "Select All"), "selectAll:", "a")] {
    editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
}
menu.addItem(editItem)
app.mainMenu = menu
app.run()
