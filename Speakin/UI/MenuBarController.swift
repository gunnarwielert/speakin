import AppKit
import Combine

@MainActor
final class MenuBarController {
    private var statusItem: NSStatusItem?
    private var iconStateManager: IconStateManager?
    private var cancellables = Set<AnyCancellable>()

    func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let statusItem = statusItem else { return }

        iconStateManager = IconStateManager(statusItem: statusItem)

        setupMenu()
    }

    private func setupMenu() {
        let menu = NSMenu()

        let aboutItem = NSMenuItem(title: "About Speakin", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(NSMenuItem.separator())

        let uninstallItem = NSMenuItem(title: "Uninstall...", action: #selector(uninstall), keyEquivalent: "")
        uninstallItem.target = self
        menu.addItem(uninstallItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Speakin", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Speakin"
        alert.informativeText = "Push-to-talk voice transcription.\n\nHold Right Option to record, release to transcribe.\n\nVersion 1.0"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func uninstall() {
        UninstallManager.showUninstallConfirmation()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}
