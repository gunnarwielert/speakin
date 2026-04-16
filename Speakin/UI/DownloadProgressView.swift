import SwiftUI

@MainActor
final class DownloadProgressModel: ObservableObject {
    @Published var progress: Double = 0
    @Published var statusText: String = "Preparing..."
}

struct DownloadProgressView: View {
    @ObservedObject var model: DownloadProgressModel

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Speakin")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Downloading transcription model...")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: model.progress)
                .progressViewStyle(.linear)
                .frame(width: 200)

            Text(model.statusText)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(32)
        .frame(width: 300, height: 200)
    }
}

struct DownloadProgressWindow {
    private var window: NSWindow?

    @MainActor
    mutating func show(model: DownloadProgressModel) {
        let hostingView = NSHostingView(rootView: DownloadProgressView(model: model))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )

        window.title = "Speakin Setup"
        window.contentView = hostingView
        window.center()
        window.isReleasedWhenClosed = false
        window.level = .floating

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = window
    }

    @MainActor
    mutating func close() {
        window?.close()
        window = nil
    }
}
