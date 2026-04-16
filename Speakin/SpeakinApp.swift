import SwiftUI
import Combine
import ServiceManagement

@main
struct SpeakinApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()
    private var currentRecordingURL: URL?
    private var downloadModel: DownloadProgressModel?
    private var downloadWindow: DownloadProgressWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarController = MenuBarController()
        menuBarController?.setup()

        Task {
            await initializeApp()
        }
    }

    private func initializeApp() async {
        AppState.shared.readyState = .checkingPermissions

        let permissionsGranted = await PermissionManager.shared.checkAndRequestPermissions()

        if !permissionsGranted {
            PermissionManager.shared.pollForAccessibilityPermission { [weak self] granted in
                if granted {
                    Task { @MainActor in
                        await self?.continueInitialization()
                    }
                }
            }
            return
        }

        await continueInitialization()
    }

    private func continueInitialization() async {
        let needsDownload = !StorageManager.shared.modelExists()

        if needsDownload {
            let model = DownloadProgressModel()
            downloadModel = model
            downloadWindow = DownloadProgressWindow()
            downloadWindow?.show(model: model)
            AppState.shared.readyState = .downloadingModel(progress: 0)
        }

        do {
            try await TranscriptionEngine.shared.initialize { [weak self] progress, status in
                guard let self = self else { return }
                self.downloadModel?.progress = progress
                self.downloadModel?.statusText = status
                AppState.shared.readyState = .downloadingModel(progress: progress)
            }

            downloadWindow?.close()
            downloadWindow = nil
            downloadModel = nil

            AppState.shared.readyState = .ready
            startHotkeyMonitoring()

            if AppState.shared.isFirstLaunch {
                promptForLoginItem()
            }

        } catch {
            downloadWindow?.close()
            downloadWindow = nil
            downloadModel = nil

            showInitializationError(error)
        }
    }

    private func promptForLoginItem() {
        let alert = NSAlert()
        alert.messageText = "Start Speakin at Login?"
        alert.informativeText = "Would you like Speakin to start automatically when you log in?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Yes")
        alert.addButton(withTitle: "No")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to register login item: \(error)")
            }
        }
    }

    private func startHotkeyMonitoring() {
        let started = HotkeyMonitor.shared.start()

        if !started {
            PermissionAlert.showAccessibilityPermissionAlert()
            return
        }

        HotkeyMonitor.shared.keyDownPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleKeyDown()
            }
            .store(in: &cancellables)

        HotkeyMonitor.shared.keyUpPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.handleKeyUp()
            }
            .store(in: &cancellables)
    }

    private func handleKeyDown() {
        guard case .ready = AppState.shared.readyState else { return }

        AppState.shared.transitionToListening()

        do {
            currentRecordingURL = try AudioRecorder.shared.startRecording()
        } catch {
            print("Failed to start recording: \(error)")
            AppState.shared.transitionToError()
        }
    }

    private func handleKeyUp() {
        guard case .ready = AppState.shared.readyState else { return }

        AppState.shared.transitionToProcessing()

        AudioRecorder.shared.stopRecording { [weak self] recordingURL in
            guard let self = self, let recordingURL = recordingURL else {
                AppState.shared.transitionToIdle()
                return
            }

            Task {
                await self.processRecording(at: recordingURL)
            }
        }
    }

    private func processRecording(at url: URL) async {
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        do {
            let transcribedText = try await TranscriptionEngine.shared.transcribe(audioURL: url)

            if transcribedText.isEmpty {
                AppState.shared.transitionToSuccess()
                return
            }

            let inserted = TextInserter.insertTextWithFallback(transcribedText)

            if inserted {
                AppState.shared.transitionToSuccess()
            } else {
                AppState.shared.transitionToError()
            }
        } catch {
            print("Transcription error: \(error)")
            AppState.shared.transitionToError()
        }
    }

    private func showInitializationError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Initialization Failed"
        alert.informativeText = "Failed to initialize the transcription engine: \(error.localizedDescription)\n\nThe app will now quit."
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotkeyMonitor.shared.stop()
        AudioRecorder.shared.cancelRecording { [weak self] in
            self?.cleanupOnTermination()
        }
    }

    private func cleanupOnTermination() {
        StorageManager.shared.cleanupTemporaryFiles()
    }
}
