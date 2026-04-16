@preconcurrency import AVFoundation
import Foundation

@MainActor
final class AudioRecorder: NSObject {
    static let shared = AudioRecorder()

    private var audioEngine: AVAudioEngine?
    nonisolated(unsafe) private var audioFile: AVAudioFile?
    private var currentRecordingURL: URL?
    private var isRecording = false

    /// Serial queue for buffer conversion and accumulation.
    /// The Core Audio render thread ONLY dispatches buffer references here — it does zero work itself.
    private let processingQueue = DispatchQueue(
        label: "com.speakin.audiorecorder.processing",
        qos: .userInitiated
    )

    /// Separate serial queue for disk I/O, completely decoupled from audio processing.
    /// processingQueue dispatches extracted batches here and returns immediately.
    private let writeQueue = DispatchQueue(
        label: "com.speakin.audiorecorder.write",
        qos: .utility
    )

    /// Buffer accumulator for batching writes (reduces I/O operations by 90%)
    nonisolated(unsafe) private let bufferAccumulator = AudioBufferAccumulator(batchSize: 10)

    private override init() {
        super.init()
    }

    func startRecording() throws -> URL {
        guard !isRecording else {
            throw AudioRecorderError.alreadyRecording
        }

        let audioEngine = AVAudioEngine()
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw AudioRecorderError.invalidFormat
        }

        let outputURL = StorageManager.shared.temporaryAudioFileURL()

        // Write 16-bit PCM on disk (compact), but AVAudioFile.processingFormat is ALWAYS
        // Float32 non-interleaved regardless of the on-disk format. We must convert to and
        // write in processingFormat, not the raw 16-bit format, to avoid -10877.
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let audioFile = try AVAudioFile(forWriting: outputURL, settings: fileSettings)

        // This is Float32, non-interleaved, 16 kHz, 1 ch — the only format AVAudioFile.write accepts.
        let processingFormat = audioFile.processingFormat

        guard let converter = AVAudioConverter(from: recordingFormat, to: processingFormat) else {
            throw AudioRecorderError.converterCreationFailed
        }

        // CRITICAL: Do NO work on the Core Audio render thread.
        // Capture the buffer reference (ARC retains it) and dispatch immediately.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            self.processingQueue.async {
                self.processAndAccumulate(
                    buffer,
                    converter: converter,
                    audioFile: audioFile,
                    processingFormat: processingFormat
                )
            }
        }

        try audioEngine.start()

        self.audioEngine = audioEngine
        self.audioFile = audioFile
        self.currentRecordingURL = outputURL
        self.isRecording = true

        return outputURL
    }

    /// Runs on processingQueue. Converts to Float32, accumulates, and dispatches a batch to
    /// writeQueue when full. Returns immediately — does not wait for disk I/O.
    nonisolated private func processAndAccumulate(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        audioFile: AVAudioFile,
        processingFormat: AVAudioFormat
    ) {
        let targetFrameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * processingFormat.sampleRate / buffer.format.sampleRate
        )

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: processingFormat,
            frameCapacity: targetFrameCount
        ) else { return }

        var conversionError: NSError?
        converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        guard conversionError == nil, convertedBuffer.frameLength > 0 else { return }

        // processingFormat is Float32 non-interleaved; floatChannelData[0] is channel 0 (mono).
        guard let floatData = convertedBuffer.floatChannelData?[0] else { return }

        let frameLength = Int(convertedBuffer.frameLength)
        let audioData = Data(bytes: floatData, count: frameLength * MemoryLayout<Float>.stride)

        if bufferAccumulator.append(audioData, frameLength: frameLength) {
            // Extract the full batch here on processingQueue, then hand off to writeQueue.
            // processingQueue returns immediately; writeQueue writes at its own pace.
            let batch = bufferAccumulator.extractBatch()
            writeQueue.async { [weak self] in
                self?.writeBatch(batch, to: audioFile, format: processingFormat)
            }
        }
    }

    /// Runs on writeQueue. Merges a pre-extracted batch into one buffer and performs a single write.
    nonisolated private func writeBatch(
        _ batch: [(data: Data, frameLength: Int)],
        to audioFile: AVAudioFile,
        format: AVAudioFormat
    ) {
        guard !batch.isEmpty else { return }

        let totalFrames = batch.reduce(0) { $0 + $1.frameLength }

        guard
            let largeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)),
            let channelData = largeBuffer.floatChannelData?[0]
        else {
            print("AudioRecorder: failed to allocate write buffer (\(totalFrames) frames)")
            return
        }

        var offset = 0
        for (data, frameLength) in batch {
            data.withUnsafeBytes { ptr in
                guard let base = ptr.baseAddress else { return }
                channelData
                    .advanced(by: offset)
                    .update(from: base.assumingMemoryBound(to: Float.self), count: frameLength)
                offset += frameLength
            }
        }

        largeBuffer.frameLength = AVAudioFrameCount(totalFrames)

        do {
            try audioFile.write(from: largeBuffer)
        } catch {
            print("AudioRecorder: write error — \(error)")
        }
    }

    func stopRecording(completion: ((URL?) -> Void)? = nil) {
        guard isRecording else {
            completion?(nil)
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false

        let recordingURL = currentRecordingURL
        currentRecordingURL = nil

        // Capture and clear the main-actor reference; captured local keeps the file alive.
        let audioFile = self.audioFile
        self.audioFile = nil

        // processingQueue is serial: this block runs after every in-flight processAndAccumulate task.
        processingQueue.async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion?(recordingURL) }
                return
            }

            // Flush any buffers that didn't fill a full batch
            if let audioFile {
                let remaining = self.bufferAccumulator.extractBatch()
                if !remaining.isEmpty {
                    let format = audioFile.processingFormat
                    self.writeQueue.async {
                        self.writeBatch(remaining, to: audioFile, format: format)
                    }
                }
            }

            // Block processingQueue until writeQueue drains (no deadlock: different queues).
            self.writeQueue.sync {}
            DispatchQueue.main.async { completion?(recordingURL) }
        }
    }

    func cancelRecording(completion: (() -> Void)? = nil) {
        guard isRecording else {
            completion?()
            return
        }

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRecording = false
        self.audioFile = nil

        let recordingURL = currentRecordingURL
        currentRecordingURL = nil

        // Drain in-flight processing tasks first (serial queue), then discard everything.
        processingQueue.async { [weak self] in
            // Clear any pending un-dispatched buffers.
            self?.bufferAccumulator.clear()
            // Wait for any writes already dispatched to writeQueue to finish before deleting the file.
            self?.writeQueue.sync {}
            if let url = recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
            DispatchQueue.main.async { completion?() }
        }
    }
}

enum AudioRecorderError: Error, LocalizedError {
    case alreadyRecording
    case invalidFormat
    case converterCreationFailed
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:    return "Already recording"
        case .invalidFormat:       return "Invalid audio format"
        case .converterCreationFailed: return "Failed to create audio converter"
        case .recordingFailed:     return "Recording failed"
        }
    }
}
