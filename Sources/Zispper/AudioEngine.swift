import Foundation
import AVFoundation

protocol AudioEngineDelegate: AnyObject {
    func didCaptureAudio(data: Data)
}

class AudioEngine {
    private let engine = AVAudioEngine()
    weak var delegate: AudioEngineDelegate?
    
    // Volcengine requires 16k, 16bit, mono
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    
    private var audioBuffer = Data()
    private let bufferLimit = 3200 // ~0.1s at 16k 16bit mono (actually 0.1 * 16000 * 2 = 3200 bytes)

    func start() throws {
        // logToFile("AudioEngine: Starting...")
        audioBuffer.removeAll()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        
        logToFile("AudioEngine: Input format - sampleRate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount)")
        
        // Check if input format is valid
        guard inputFormat.sampleRate > 0 else {
            logToFile("AudioEngine: ERROR - Invalid input format (sampleRate is 0). Microphone permission may be denied.")
            return
        }
        
        // Install tap on input node
        // We need to convert whatever the input is (usually 44.1k/48k flt) to 16k Int16
        // Creating a converter format
        
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)!
        
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer, time) in
            guard let self = self else { return }
            
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }
            
            // Output buffer
            // Calculate capacity: (time * rate) roughly
            let frames = Int(Double(buffer.frameLength) / inputFormat.sampleRate * 16000)
            guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: self.targetFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }
            
            var error: NSError?
            converter.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
            
            if let channelData = pcmBuffer.int16ChannelData {
                let channelDataPointer = channelData.pointee
                let byteCount = Int(pcmBuffer.frameLength) * 2
                let data = Data(bytes: channelDataPointer, count: byteCount)
                
                self.audioBuffer.append(data)
                
                // If buffer is large enough, send it
                if self.audioBuffer.count >= self.bufferLimit {
                    let chunk = self.audioBuffer
                    self.audioBuffer = Data() // Reset
                    // logToFile("AudioEngine: Sending chunk size \(chunk.count)")
                    self.delegate?.didCaptureAudio(data: chunk)
                }
            }
        }
        
        try engine.start()
        logToFile("AudioEngine: Started successfully")
    }
    
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        
        // Flush remaining buffer
        if !audioBuffer.isEmpty {
            delegate?.didCaptureAudio(data: audioBuffer)
            audioBuffer.removeAll()
        }
    }
}
