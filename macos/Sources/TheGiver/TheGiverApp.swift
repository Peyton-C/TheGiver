import AppKit
import SwiftUI

/// The Giver runs as an agent, without a Dock icon, for as long as a picker
/// is open, and takes one only while the settings window is showing.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var pickers: [PickerPanel] = []
    private var settingsWindow: NSWindow?
    private let defaults = Defaults()
    private var openedAtLaunch = false

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = Self.mainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files and links arrive around launch; show the settings only when
        // The Giver was started on its own.
        DispatchQueue.main.async {
            if !self.openedAtLaunch && self.pickers.isEmpty {
                self.showSettings()
            }
        }
    }

    /// Receives links as well as files, as AppKit routes the URL schemes in
    /// Info.plist here too.
    func application(_ application: NSApplication, open urls: [URL]) {
        openedAtLaunch = true
        // Files opened together share a picker. Links each get their own, as
        // one application rarely suits a mixed handful.
        let files = urls.filter(\.isFileURL)
        if !files.isEmpty { showPicker(for: files) }
        urls.filter { !$0.isFileURL }.forEach { showPicker(for: [$0]) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showSettings() }
        return false
    }

    private func showPicker(for targets: [URL]) {
        let panel = PickerPanel(targets: targets)
        panel.delegate = self
        panel.onShowSettings = { [weak self] in self?.showSettings() }
        pickers.append(panel)
        // The plain activate() only asks, and Finder, having just opened the
        // file, doesn't give way to an agent.
        NSApp.activate(ignoringOtherApps: true)
        panel.present()
    }

    @objc func showSettings() {
        NSApp.setActivationPolicy(.regular)
        defaults.refresh()
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            let host = NSHostingController(rootView: SettingsView(defaults: defaults))
            window.contentViewController = host
            window.title = "The Giver"
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        // The default may have been changed in System Settings meanwhile.
        if notification.object as? NSWindow === settingsWindow { defaults.refresh() }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        pickers.removeAll { $0 === window }
        if window === settingsWindow {
            settingsWindow = nil
            NSApp.setActivationPolicy(.accessory)
        }
        // Nothing is left to do once the last window goes. Panels don't count
        // towards applicationShouldTerminateAfterLastWindowClosed.
        if pickers.isEmpty && settingsWindow == nil {
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    /// An agent shows no menu bar, but the key equivalents still come from
    /// it: without an Edit menu the path field can't copy or paste.
    private static func mainMenu() -> NSMenu {
        let main = NSMenu()

        let app = NSMenu()
        app.addItem(withTitle: "About The Giver", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit The Giver", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        main.addItem(withTitle: "The Giver", action: nil, keyEquivalent: "").submenu = app

        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "").submenu = edit

        let window = NSMenu(title: "Window")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(withTitle: "Window", action: nil, keyEquivalent: "").submenu = window
        return main
    }
}
