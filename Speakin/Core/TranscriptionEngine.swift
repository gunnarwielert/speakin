import Foundation
import WhisperKit

@MainActor
final class TranscriptionEngine {
    static let shared = TranscriptionEngine()

    private var whisperKit: WhisperKit?
    private var isInitialized = false

    private init() {}

    var isReady: Bool {
        isInitialized && whisperKit != nil
    }

    func initialize(progressHandler: @escaping (Double, String) -> Void) async throws {
        let modelFolder = StorageManager.shared.modelsDirectory

        if StorageManager.shared.modelExists() {
            // Path A: Models exist - load them
            progressHandler(1.0, "Loading model...")

            let config = WhisperKitConfig(
                modelFolder: modelFolder.path,  // Only pass modelFolder when loading
                computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine),
                verbose: false,
                logLevel: .none
            )

            whisperKit = try await WhisperKit(config)
        } else {
            // Path B: Models don't exist - download them
            progressHandler(0.0, "Downloading model...")

            let config = WhisperKitConfig(
                model: "openai_whisper-small",
                downloadBase: modelFolder,  // Use downloadBase, NOT modelFolder
                // DO NOT set modelFolder here - let WhisperKit handle it
                computeOptions: ModelComputeOptions(audioEncoderCompute: .cpuAndNeuralEngine, textDecoderCompute: .cpuAndNeuralEngine),
                verbose: true,  // Enable verbose during download for debugging
                logLevel: .info,
                load: true,  // Load after download completes
                download: true  // Explicitly enable download
            )

            whisperKit = try await WhisperKit(config)
            progressHandler(1.0, "Model ready")
        }

        isInitialized = true
    }

    func transcribe(audioURL: URL) async throws -> String {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.notInitialized
        }

        let decodeOptions = DecodingOptions(
            task: .transcribe,
            language: nil,              // Keep nil for auto-detection
            usePrefillPrompt: true,     // Enable proper decoder init (WhisperKit default)
            usePrefillCache: false,     // Don't cache since language varies per recording
            detectLanguage: true,       // Explicitly enable language detection
            skipSpecialTokens: true,
            withoutTimestamps: true,
            suppressBlank: true
        )

        let result = try await whisperKit.transcribe(
            audioPath: audioURL.path,
            decodeOptions: decodeOptions
        )

        guard let transcription = result.first else {
            return ""
        }

        let text = transcription.text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)

        if text.isEmpty {
            return ""
        }

        return text + " "
    }
}

enum TranscriptionError: Error, LocalizedError {
    case notInitialized
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Transcription engine not initialized"
        case .transcriptionFailed:
            return "Transcription failed"
        }
    }
}
