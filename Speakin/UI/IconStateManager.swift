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
            setIcon(opacity: 1.0, content: "listening")  // Empty cutout, no symbols
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
        setIcon(opacity: 1.0, content: "dots")
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
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            // Flip coordinate system to match SVG (top-left origin)
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1.0, y: -1.0)

            ctx.setAlpha(opacity)

            if content == nil {
                // Idle state: standalone speech bubble
                self.drawIdleBubble(in: ctx)
            } else {
                // Active states: rounded rect with bubble cutout
                self.drawActiveBackground(in: ctx)

                // Draw content symbols
                if content == "dots" {
                    self.drawProcessingDots(in: ctx)
                } else if content == "✓" {
                    self.drawCheckmark(in: ctx)
                } else if content == "!" {
                    self.drawExclamation(in: ctx)
                }
            }

            return true
        }

        image.isTemplate = true
        return image
    }

    // MARK: - Icon Drawing (Based on Claude Design spec)

    /// Idle state: Standalone speech bubble with tail
    /// SVG path from design: 18×18 canvas, generous corner radii (r≈3.8)
    private func drawIdleBubble(in ctx: CGContext) {
        let path = CGMutablePath()

        // Main bubble body with rounded corners
        path.move(to: CGPoint(x: 4.8, y: 1.2))
        path.addLine(to: CGPoint(x: 13.2, y: 1.2))
        path.addArc(tangent1End: CGPoint(x: 17, y: 1.2),
                   tangent2End: CGPoint(x: 17, y: 5),
                   radius: 3.8)
        path.addLine(to: CGPoint(x: 17, y: 11.5))
        path.addArc(tangent1End: CGPoint(x: 17, y: 15.3),
                   tangent2End: CGPoint(x: 13.2, y: 15.3),
                   radius: 3.8)
        path.addLine(to: CGPoint(x: 8.3, y: 15.3))

        // Tail curve (sweeps from bottom-left toward bottom-center)
        path.addCurve(to: CGPoint(x: 3.7, y: 17.4),
                     control1: CGPoint(x: 7.2, y: 16.2),
                     control2: CGPoint(x: 5.4, y: 17.1))
        path.addCurve(to: CGPoint(x: 4.55, y: 15.3),
                     control1: CGPoint(x: 4.4, y: 16.2),
                     control2: CGPoint(x: 4.6, y: 15.2))
        path.addLine(to: CGPoint(x: 4.8, y: 15.3))
        path.addArc(tangent1End: CGPoint(x: 1, y: 15.3),
                   tangent2End: CGPoint(x: 1, y: 11.5),
                   radius: 3.8)
        path.addLine(to: CGPoint(x: 1, y: 5))
        path.addArc(tangent1End: CGPoint(x: 1, y: 1.2),
                   tangent2End: CGPoint(x: 4.8, y: 1.2),
                   radius: 3.8)
        path.closeSubpath()

        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
    }

    /// Active states: Rounded rectangle with speech bubble cut out (evenodd fill)
    private func drawActiveBackground(in ctx: CGContext) {
        let combinedPath = CGMutablePath()

        // Outer rounded rectangle
        let outerRect = CGRect(x: 0.5, y: 0.5, width: 17, height: 17)
        let outerPath = CGPath(roundedRect: outerRect, cornerWidth: 3.5, cornerHeight: 3.5, transform: nil)
        combinedPath.addPath(outerPath)

        // Inner bubble cutout (slightly inset version of idle bubble)
        let innerPath = CGMutablePath()
        innerPath.move(to: CGPoint(x: 5.4, y: 2.8))
        innerPath.addLine(to: CGPoint(x: 12.6, y: 2.8))
        innerPath.addArc(tangent1End: CGPoint(x: 15.4, y: 2.8),
                        tangent2End: CGPoint(x: 15.4, y: 5.6),
                        radius: 2.8)
        innerPath.addLine(to: CGPoint(x: 15.4, y: 10.8))
        innerPath.addArc(tangent1End: CGPoint(x: 15.4, y: 13.6),
                        tangent2End: CGPoint(x: 12.6, y: 13.6),
                        radius: 2.8)
        innerPath.addLine(to: CGPoint(x: 8.1, y: 13.6))

        // Tail cutout
        innerPath.addCurve(to: CGPoint(x: 4.3, y: 15.4),
                          control1: CGPoint(x: 7.2, y: 14.4),
                          control2: CGPoint(x: 5.7, y: 15.1))
        innerPath.addCurve(to: CGPoint(x: 5.0, y: 13.6),
                          control1: CGPoint(x: 4.9, y: 14.4),
                          control2: CGPoint(x: 5.05, y: 13.7))
        innerPath.addLine(to: CGPoint(x: 5.4, y: 13.6))
        innerPath.addArc(tangent1End: CGPoint(x: 2.6, y: 13.6),
                        tangent2End: CGPoint(x: 2.6, y: 10.8),
                        radius: 2.8)
        innerPath.addLine(to: CGPoint(x: 2.6, y: 5.6))
        innerPath.addArc(tangent1End: CGPoint(x: 2.6, y: 2.8),
                        tangent2End: CGPoint(x: 5.4, y: 2.8),
                        radius: 2.8)
        innerPath.closeSubpath()

        combinedPath.addPath(innerPath)

        // Fill with even-odd rule to create cutout effect
        ctx.setFillColor(NSColor.black.cgColor)
        ctx.addPath(combinedPath)
        ctx.fillPath(using: .evenOdd)
    }

    /// Processing state: Three animated dots inside bubble cutout
    private func drawProcessingDots(in ctx: CGContext) {
        ctx.setFillColor(NSColor.white.cgColor)

        let cx: CGFloat = 9
        let cy: CGFloat = 8.2
        let radius: CGFloat = 0.85
        let spacing: CGFloat = 2.5

        // Draw dots based on animation frame
        let positions: [(CGFloat, CGFloat)] = [
            (cx - spacing, cy),
            (cx, cy),
            (cx + spacing, cy)
        ]

        for i in 0..<dotCount {
            let pos = positions[i]
            ctx.addEllipse(in: CGRect(x: pos.0 - radius, y: pos.1 - radius,
                                     width: radius * 2, height: radius * 2))
        }

        ctx.fillPath()
    }

    /// Success state: Checkmark symbol
    private func drawCheckmark(in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.4)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        let path = CGMutablePath()
        path.move(to: CGPoint(x: 5.8, y: 8.5))
        path.addLine(to: CGPoint(x: 8, y: 10.8))
        path.addLine(to: CGPoint(x: 12.4, y: 5.8))

        ctx.addPath(path)
        ctx.strokePath()
    }

    /// Error state: Exclamation mark (line + dot)
    private func drawExclamation(in ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineCap(.round)

        // Exclamation line
        let linePath = CGMutablePath()
        linePath.move(to: CGPoint(x: 9, y: 5.2))
        linePath.addLine(to: CGPoint(x: 9, y: 9.5))
        ctx.addPath(linePath)
        ctx.strokePath()

        // Exclamation dot
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.addEllipse(in: CGRect(x: 8.2, y: 10.6, width: 1.6, height: 1.6))
        ctx.fillPath()
    }

    deinit {
        animationTimer?.cancel()
    }
}
