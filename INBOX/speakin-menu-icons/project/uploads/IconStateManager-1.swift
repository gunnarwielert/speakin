import AppKit
import Combine

@MainActor
final class IconStateManager {
    private var animationTimer: DispatchSourceTimer?
    private var dotCount = 1
    private weak var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem

        AppState.shared.$iconState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.updateForState(state)
            }
            .store(in: &cancellables)
    }

    private func updateForState(_ state: AppIconState) {
        stopAnimation()

        switch state {
        case .idle:
            setIcon(opacity: 0.5, content: nil)
        case .listening:
            setIcon(opacity: 1.0, content: nil)
        case .processing:
            startProcessingAnimation()
        case .success:
            setIcon(opacity: 1.0, content: "✓")
        case .error:
            setIcon(opacity: 1.0, content: "!")
        }
    }

    private func startProcessingAnimation() {
        dotCount = 1
        updateProcessingIcon()

        // Create timer on dedicated background queue to avoid competing with audio I/O
        let timerQueue = DispatchQueue(label: "com.speakin.icon.timer", qos: .utility)
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)

        timer.schedule(deadline: .now(), repeating: 0.2)
        timer.setEventHandler { [weak self] in
            // Update icon on main thread
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.dotCount = (self.dotCount % 3) + 1
                self.updateProcessingIcon()
            }
        }

        timer.resume()
        animationTimer = timer
    }

    private func updateProcessingIcon() {
        let dots = String(repeating: "●", count: dotCount)
        setIcon(opacity: 1.0, content: dots)
    }

    private func stopAnimation() {
        animationTimer?.cancel()
        animationTimer = nil
    }

    private func setIcon(opacity: CGFloat, content: String?) {
        guard let button = statusItem?.button else { return }

        let icon = generateIcon(opacity: opacity, content: content)
        button.image = icon
    }

    private func generateIcon(opacity: CGFloat, content: String?) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSGraphicsContext.current?.cgContext.setAlpha(opacity)

            self.drawSpeechBubble(in: rect)

            if let content = content {
                self.drawContent(content, in: rect)
            }

            return true
        }

        image.isTemplate = true
        return image
    }

    private func drawSpeechBubble(in rect: NSRect) {
        let bubbleRect = NSRect(x: 2, y: 4, width: 14, height: 11)
        let bubblePath = NSBezierPath(roundedRect: bubbleRect, xRadius: 3, yRadius: 3)

        let tailPath = NSBezierPath()
        tailPath.move(to: NSPoint(x: 4, y: 4))
        tailPath.line(to: NSPoint(x: 2, y: 1))
        tailPath.line(to: NSPoint(x: 7, y: 4))
        tailPath.close()

        NSColor.black.setFill()
        bubblePath.fill()
        tailPath.fill()
    }

    private func drawContent(_ content: String, in rect: NSRect) {
        let fontSize: CGFloat
        if content.count > 2 {
            fontSize = 6
        } else if content.count > 1 {
            fontSize = 8
        } else {
            fontSize = 10
        }

        let font = NSFont.systemFont(ofSize: fontSize, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.white
        ]

        let attributedString = NSAttributedString(string: content, attributes: attributes)
        let stringSize = attributedString.size()

        let bubbleCenter = NSPoint(x: 9, y: 9.5)
        let drawPoint = NSPoint(
            x: bubbleCenter.x - stringSize.width / 2,
            y: bubbleCenter.y - stringSize.height / 2
        )

        attributedString.draw(at: drawPoint)
    }

    deinit {
        animationTimer?.cancel()
    }
}
