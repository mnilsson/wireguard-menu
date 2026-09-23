import WireGuardCore
import AppKit
import ServiceManagement
import UniformTypeIdentifiers

@main
struct WireGuardMenu {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var item: NSStatusItem!
    private var timer: Timer?
    private var busyPath: String?
    private let helper = HelperClient()
    private var statuses: [String: TunnelStatus] = [:]
    private var refreshing = false
    private var paths = UserDefaults.standard.stringArray(forKey: "tunnelPaths") ?? []
    private var tunnels: [Tunnel] { paths.map { Tunnel(path: $0) } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "network", accessibilityDescription: "WireGuard tunnels")
        rebuildMenu()
        refreshStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshStatus() }
        }
    }

    func menuWillOpen(_ menu: NSMenu) { rebuildMenu(); refreshStatus() }

    private func refreshStatus() {
        guard !refreshing else { return }
        guard helper.isEnabled else {
            statuses = [:]
            rebuildMenu()
            return
        }
        refreshing = true
        let requestedPaths = paths
        Task {
            defer { refreshing = false }
            statuses = (try? await helper.statuses(paths: requestedPaths)) ?? [:]
            rebuildMenu()
        }
    }

    private func entry(_ title: String, action: Selector? = nil, path: String? = nil) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.representedObject = path
        return entry
    }

    private func rebuildMenu() {
        let menu = item.menu ?? NSMenu()
        menu.removeAllItems()
        menu.autoenablesItems = false
        menu.delegate = self
        var running = 0
        for tunnel in tunnels {
            let status = statuses[tunnel.path] ?? .unknown
            if status.isRunning { running += 1 }
            let working = busyPath == tunnel.path
            let row = entry("\(tunnel.name) — \(working ? "Working…" : status.label)")
            row.image = NSImage(systemSymbolName: status.isRunning ? "circle.fill" : "circle",
                                accessibilityDescription: status.label)
            let submenu = NSMenu()
            submenu.autoenablesItems = false
            for control in connectionMenuItems(for: tunnel, status: status) {
                submenu.addItem(control)
            }
            submenu.addItem(entry("Show configuration in Finder", action: #selector(reveal(_:)), path: tunnel.path))
            let remove = entry("Remove from menu", action: #selector(removeTunnel(_:)), path: tunnel.path)
            remove.isEnabled = busyPath == nil && status == .stopped
            submenu.addItem(remove)
            row.submenu = submenu
            menu.addItem(row)
        }
        if paths.isEmpty {
            let hint = entry("Add your office and production .conf files")
            hint.isEnabled = false
            menu.addItem(hint)
        }
        menu.addItem(.separator())
        if !helper.isEnabled {
            menu.addItem(entry("Enable password-free control…", action: #selector(enableHelper)))
        }
        menu.addItem(entry("Helper settings…", action: #selector(helperSettings)))
        let hint = entry("Running indicates an interface, not reachability")
        hint.isEnabled = false
        menu.addItem(hint)
        let add = entry("Add tunnel…", action: #selector(addTunnel))
        add.isEnabled = busyPath == nil
        menu.addItem(add)
        menu.addItem(.separator())
        let quit = entry("Quit (leave tunnels running)", action: #selector(quitApp))
        quit.isEnabled = busyPath == nil
        menu.addItem(quit)
        item.button?.title = " \(running)/\(paths.count)"
        item.button?.toolTip = "WireGuard: \(running) of \(paths.count) tunnels running"
        item.menu = menu
    }

    @objc private func addTunnel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose WireGuard configurations"
        panel.message = "Selected .conf files are copied into the app’s Application Support folder. You can then delete the originals."
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .data]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let tunnel = Tunnel(path: url.path)
            guard tunnel.validName else {
                showError("Invalid configuration name", "Use a .conf filename with 1–15 letters, digits, or _ = + . - characters.")
                continue
            }
            if paths.contains(tunnel.path) { continue }
            guard !tunnels.contains(where: { $0.name == tunnel.name }) else {
                showError("Duplicate tunnel name", "Each configuration needs a unique filename, even when stored in different folders.")
                continue
            }
            do {
                let imported = try ConfigurationStore().importConfiguration(from: url)
                paths.append(imported.path)
            } catch {
                showError("Could not import \(tunnel.name)", error.localizedDescription)
            }
        }
        save()
    }

    @objc private func enableHelper() {
        do {
            try helper.enable()
            refreshStatus()
        } catch {
            showError("Could not enable helper", error.localizedDescription)
        }
    }

    @objc private func helperSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    func connectionMenuItems(for tunnel: Tunnel, status: TunnelStatus) -> [NSMenuItem] {
        let connect = entry("Connect", action: #selector(connectTunnel(_:)), path: tunnel.path)
        connect.isEnabled = busyPath == nil && !status.isRunning
        let disconnect = entry("Disconnect", action: #selector(disconnectTunnel(_:)), path: tunnel.path)
        // Keep recovery available even if a status request failed.
        disconnect.isEnabled = busyPath == nil
        return [connect, disconnect]
    }

    @objc private func removeTunnel(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String,
              busyPath == nil, statuses[path] == .stopped else { return }
        paths.removeAll { $0 == path }
        save()
    }

    @objc private func reveal(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func connectTunnel(_ sender: NSMenuItem) {
        changeTunnel(sender, action: "up")
    }

    @objc private func disconnectTunnel(_ sender: NSMenuItem) {
        changeTunnel(sender, action: "down")
    }

    private func changeTunnel(_ sender: NSMenuItem, action: String) {
        guard busyPath == nil, let path = sender.representedObject as? String else { return }
        let tunnel = Tunnel(path: path)
        guard tunnel.validName else { return }
        if !helper.isEnabled {
            enableHelper()
            guard helper.isEnabled else { return }
        }
        busyPath = path
        rebuildMenu()
        Task {
            let result: CommandResult
            do {
                result = try await helper.change(path: path, action: action)
            } catch {
                result = CommandResult(code: -1, output: error.localizedDescription)
            }
            busyPath = nil
            statuses[path] = nil
            rebuildMenu()
            refreshStatus()
            if result.code != 0 {
                showError("Could not \(action == "up" ? "connect" : "disconnect") \(tunnel.name)", result.output)
            }
        }
    }

    private func save() {
        UserDefaults.standard.set(paths, forKey: "tunnelPaths")
        rebuildMenu()
        refreshStatus()
    }

    private func showError(_ title: String, _ message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}
