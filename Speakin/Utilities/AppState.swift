import Foundation
import Combine

enum AppIconState {
    case idle
    case listening
    case processing
    case success
    case error
}

enum AppReadyState {
    case checkingPermissions
    case requestingPermissions
    case downloadingModel(progress: Double)
    case ready
    case permissionDenied(PermissionType)
}

enum PermissionType {
    case accessibility
    case microphone
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var iconState: AppIconState = .idle
    @Published var readyState: AppReadyState = .checkingPermissions
    @Published var isFirstLaunch: Bool = false

    private var ephemeralStateTask: Task<Void, Never>?

    private init() {
        isFirstLaunch = !UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if isFirstLaunch {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
    }

    func transitionToListening() {
        ephemeralStateTask?.cancel()
        iconState = .listening
    }

    func transitionToProcessing() {
        ephemeralStateTask?.cancel()
        iconState = .processing
    }

    func transitionToSuccess() {
        transitionToEphemeralState(.success)
    }

    func transitionToError() {
        transitionToEphemeralState(.error)
    }

    func transitionToIdle() {
        ephemeralStateTask?.cancel()
        iconState = .idle
    }

    private func transitionToEphemeralState(_ state: AppIconState) {
        ephemeralStateTask?.cancel()
        iconState = state

        ephemeralStateTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled {
                iconState = .idle
            }
        }
    }
}
