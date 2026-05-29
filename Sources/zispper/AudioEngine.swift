import Foundation
import AVFoundation

protocol AudioEngineDelegate: AnyObject {
    func didCaptureAudio(data: Data)
}

enum AudioEngineError: LocalizedError {
    case microphoneUnavailable
    case invalidInputFormat

    var errorDescription: String? {
        switch self {
        case .microphoneUnavailable:
            return "Microphone permission has not been granted."
        case .invalidInputFormat:
            return "The microphone input format is invalid."
        }
    }
}

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: Configuration.audioSampleRate,
        channels: Configuration.audioChannels,
        interleaved: true
    )!

    weak var delegate: AudioEngineDelegate?
    private var audioBuffer = Data()
    private var isRunning = false

    func start() throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw AudioEngineError.microphoneUnavailable
        }

        audioBuffer.removeAll()

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        logToFile("AudioEngine input format sampleRate=\(inputFormat.sampleRate) channels=\(inputFormat.channelCount)")

        guard inputFormat.sampleRate > 0 else {
            throw AudioEngineError.invalidInputFormat
        }

        if isRunning {
            inputNode.removeTap(onBus: 0)
            engine.stop()
            isRunning = false
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioEngineError.invalidInputFormat
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }

            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            let frames = max(1, Int(Double(buffer.frameLength) / inputFormat.sampleRate * Configuration.audioSampleRate))
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: AVAudioFrameCount(frames)) else {
                return
            }

            var error: NSError?
            converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)

            if let error {
                logToFile("Audio conversion error: \(error.localizedDescription)")
                return
            }

            guard let channelData = pcmBuffer.int16ChannelData else {
                return
            }

            let byteCount = Int(pcmBuffer.frameLength) * MemoryLayout<Int16>.size
            let data = Data(bytes: channelData.pointee, count: byteCount)
            self.audioBuffer.append(data)

            if self.audioBuffer.count >= Configuration.audioBufferLimit {
                let chunk = self.audioBuffer
                self.audioBuffer.removeAll(keepingCapacity: true)
                self.delegate?.didCaptureAudio(data: chunk)
            }
        }

        engine.prepare()
        try engine.start()
        isRunning = true
        logToFile("AudioEngine started successfully")
    }

    func stop() {
        guard isRunning else {
            flushBuffer()
            return
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        flushBuffer()
    }

    private func flushBuffer() {
        if !audioBuffer.isEmpty {
            delegate?.didCaptureAudio(data: audioBuffer)
            audioBuffer.removeAll(keepingCapacity: true)
        }
    }
}
