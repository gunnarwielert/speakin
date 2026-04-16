import Foundation

struct StorageManager {
    static let shared = StorageManager()

    private init() {}

    var applicationSupportDirectory: URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let speakinDir = appSupport.appendingPathComponent("Speakin", isDirectory: true)

        if !fileManager.fileExists(atPath: speakinDir.path) {
            try? fileManager.createDirectory(at: speakinDir, withIntermediateDirectories: true)
        }

        return speakinDir
    }

    var modelsDirectory: URL {
        let modelsDir = applicationSupportDirectory.appendingPathComponent("models", isDirectory: true)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: modelsDir.path) {
            try? fileManager.createDirectory(at: modelsDir, withIntermediateDirectories: true)
        }

        return modelsDir
    }

    var temporaryAudioDirectory: URL {
        let tempDir = applicationSupportDirectory.appendingPathComponent("temp", isDirectory: true)
        let fileManager = FileManager.default

        if !fileManager.fileExists(atPath: tempDir.path) {
            try? fileManager.createDirectory(at: tempDir, withIntermediateDirectories: true)
        }

        return tempDir
    }

    func temporaryAudioFileURL() -> URL {
        temporaryAudioDirectory.appendingPathComponent("recording_\(UUID().uuidString).wav")
    }

    func cleanupTemporaryFiles() {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: temporaryAudioDirectory, includingPropertiesForKeys: nil) else {
            return
        }

        for file in contents {
            try? fileManager.removeItem(at: file)
        }
    }

    func modelExists() -> Bool {
        let fileManager = FileManager.default

        // Check for the specific model folder structure
        // WhisperKit downloads to: models/openai_whisper-small/
        let modelPath = modelsDirectory.appendingPathComponent("openai_whisper-small")

        guard fileManager.fileExists(atPath: modelPath.path) else {
            return false
        }

        // Verify essential .mlmodelc files exist
        let requiredModels = ["MelSpectrogram.mlmodelc", "AudioEncoder.mlmodelc", "TextDecoder.mlmodelc"]

        for modelName in requiredModels {
            let modelFile = modelPath.appendingPathComponent(modelName)
            if !fileManager.fileExists(atPath: modelFile.path) {
                return false
            }
        }

        return true
    }

    func deleteAllData() throws {
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: applicationSupportDirectory.path) {
            try fileManager.removeItem(at: applicationSupportDirectory)
        }

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            let prefsPath = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Preferences")
                .appendingPathComponent("\(bundleIdentifier).plist")

            if fileManager.fileExists(atPath: prefsPath.path) {
                try fileManager.removeItem(at: prefsPath)
            }
        }
    }
}
