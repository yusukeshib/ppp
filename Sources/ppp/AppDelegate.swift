import AppKit
import ApplicationServices

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var accessibilityItem: NSMenuItem!
    private var monitor: AccessibilityTextMonitor!
    private var coordinator: ReviewCoordinator!
    private var settingsWindow: SettingsWindowController!
    private let settings = AppSettings.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        let suggestionPanel = SuggestionPanel()
        let triggerPanel = SelectionTriggerPanel()
        coordinator = ReviewCoordinator(
            settings: settings,
            panel: suggestionPanel,
            triggerPanel: triggerPanel
        )

        monitor = AccessibilityTextMonitor()
        monitor.onCapture = { [weak self] capture in
            self?.coordinator.receive(capture)
        }
        monitor.onSelectionCleared = { [weak self] in
            self?.coordinator.selectionCleared()
        }
        monitor.onUnavailable = { [weak self] in
            self?.coordinator.temporarilyUnavailable()
        }
        monitor.start()

        settingsWindow = SettingsWindowController(settings: settings)
        settingsWindow.onSave = { [weak self] in
            self?.coordinator.reset()
            self?.monitor.refresh()
            self?.rebuildStatusMenu()
        }

        setupMainMenu()
        setupStatusItem()
        requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor.stop()
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()
        let editMenuItem = NSMenuItem(title: L10n.string("Edit"), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: L10n.string("Edit"))

        editMenu.addItem(
            NSMenuItem(title: L10n.string("Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        )
        editMenu.addItem(
            NSMenuItem(title: L10n.string("Redo"), action: Selector(("redo:")), keyEquivalent: "Z")
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(title: L10n.string("Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        )
        editMenu.addItem(
            NSMenuItem(title: L10n.string("Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        )
        editMenu.addItem(
            NSMenuItem(title: L10n.string("Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        )
        editMenu.addItem(.separator())
        editMenu.addItem(
            NSMenuItem(title: L10n.string("Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        )

        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusBarIcon.make(accessibilityDescription: "ppp")
            button.toolTip = "ppp"
        }

        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.delegate = self

        let settingsItem = NSMenuItem(title: L10n.string("Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        for profile in settings.promptProfiles {
            let item = NSMenuItem(title: profile.name, action: #selector(selectPrompt(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = profile.id.uuidString
            item.state = profile.id == settings.selectedPromptID ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())

        accessibilityItem = NSMenuItem(
            title: L10n.string("Accessibility Access"),
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L10n.string("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items where item.representedObject != nil {
            guard let value = item.representedObject as? String,
                  let id = UUID(uuidString: value)
            else { continue }
            item.state = id == settings.selectedPromptID ? .on : .off
        }
        if AccessibilityTextMonitor.isTrusted {
            accessibilityItem.title = L10n.string("Accessibility Access: Granted")
            accessibilityItem.state = .on
            monitor.refresh()
        } else {
            accessibilityItem.title = L10n.string("Grant Accessibility Access…")
            accessibilityItem.state = .off
        }
    }

    private func requestAccessibilityIfNeeded() {
        guard !AccessibilityTextMonitor.isTrusted else { return }
        AccessibilityTextMonitor.requestAccess()
    }

    @objc private func showSettings() {
        coordinator.dismiss()
        settingsWindow.present()
    }

    @objc private func selectPrompt(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let id = UUID(uuidString: value)
        else { return }
        settings.selectedPromptID = id
        coordinator.reset()
        guard let menu = sender.menu else { return }
        for item in menu.items where item.representedObject != nil {
            item.state = item === sender ? NSControl.StateValue.on : .off
        }
    }

    @objc private func openAccessibilitySettings() {
        if !AccessibilityTextMonitor.isTrusted {
            AccessibilityTextMonitor.requestAccess()
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
