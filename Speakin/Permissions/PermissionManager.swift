import AVFoundation
import AppKit

@MainActor
final class PermissionManager {
    static let shared = PermissionManager()

    private init() {}

    var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    var hasMicrophonePermission: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    var hasAllPermissions: Bool {
        hasAccessibilityPermission && hasMicrophonePermission
    }

    func checkAndRequestPermissions() async -> Bool {
        let accessibilityGranted = await checkAccessibilityPermission()

        if !accessibilityGranted {
            AppState.shared.readyState = .permissionDenied(.accessibility)
            return false
        }

        let microphoneGranted = await requestMicrophonePermission()

        if !microphoneGranted {
            AppState.shared.readyState = .permissionDenied(.microphone)
            return false
        }

        return true
    }

    private func checkAccessibilityPermission() async -> Bool {
        if AXIsProcessTrusted() {
            return true
        }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)

        if !trusted {
            PermissionAlert.showAccessibilityPermissionAlert()
        }

        return trusted
    }

    private func requestMicrophonePermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            PermissionAlert.showMicrophonePermissionAlert()
            return false
        @unknown default:
            return false
        }
    }

    func pollForAccessibilityPermission(completion: @escaping (Bool) -> Void) {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if AXIsProcessTrusted() {
                timer.invalidate()
                completion(true)
            }
        }
    }
}
