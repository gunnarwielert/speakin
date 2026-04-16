import AppKit

struct UninstallManager {
    static func showUninstallConfirmation() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Speakin?"
        alert.informativeText = "This will delete all Speakin data including the downloaded transcription model. The app will quit after cleanup. You'll need to manually move Speakin.app to Trash."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            performUninstall()
        }
    }

    private static func performUninstall() {
        do {
            try StorageManager.shared.deleteAllData()

            UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier ?? "com.speakin.app")
            UserDefaults.standard.synchronize()

            NSApp.terminate(nil)
        } catch {
            let errorAlert = NSAlert()
            errorAlert.messageText = "Uninstall Failed"
            errorAlert.informativeText = "Could not delete all data: \(error.localizedDescription)"
            errorAlert.alertStyle = .critical
            errorAlert.addButton(withTitle: "OK")
            errorAlert.runModal()
        }
    }
}
