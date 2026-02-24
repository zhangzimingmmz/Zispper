import Foundation

protocol ASRClientDelegate: AnyObject {
    func didReceiveResult(text: String, isFinal: Bool)
    func didError(error: Error)
    func didSessionEnd()
}

class ASRClient {
    weak var delegate: ASRClientDelegate?
    private var audioBuffer = Data()
    private let sampleRate: Int = 16000
    private let channels: Int = 1
    private let bitsPerSample: Int = 16
    
    func connect() {
        // No-op for HTTP client
        logToFile("ASRClient: HTTP mode, no persistent connection needed")
    }
    
    func disconnect() {
        // No-op for HTTP client
    }
    
    func startNewSession() {
        audioBuffer = Data()
        logToFile("ASRClient: Started new session, cleared buffer")
    }
    
    func sendAudio(data: Data, isLast: Bool = false) {
        if !data.isEmpty {
            audioBuffer.append(data)
            // logToFile("ASRClient: Buffered \(data.count) bytes, total: \(audioBuffer.count)")
        }
        
        if isLast {
            finishSession()
        }
    }
    
    private func finishSession() {
        guard !audioBuffer.isEmpty else {
            logToFile("ASRClient: No audio data to send")
            delegate?.didSessionEnd()
            return
        }
        
        logToFile("ASRClient: Finishing session with \(audioBuffer.count) bytes of audio")
        
        // Convert PCM to WAV
        let wavData = createWAVFile(pcmData: audioBuffer)
        
        // Upload to SenseVoice
        uploadToSenseVoice(wavData: wavData)
    }
    
    private func uploadToSenseVoice(wavData: Data) {
        let urlString = "http://100.64.0.6:30766/v1/audio/transcriptions"
        guard let url = URL(string: urlString) else {
            logToFile("ASRClient: Invalid URL")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Add language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("zh\r\n".data(using: .utf8)!)
        
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        logToFile("ASRClient: Uploading \(wavData.count) bytes WAV to \(urlString)")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    logToFile("ASRClient: Upload error: \(error.localizedDescription)")
                    self?.delegate?.didError(error: error)
                    self?.delegate?.didSessionEnd()
                    return
                }
                
                guard let data = data else {
                    logToFile("ASRClient: No response data")
                    self?.delegate?.didSessionEnd()
                    return
                }
                
                logToFile("ASRClient: Received response: \(data.count) bytes")
                
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        logToFile("ASRClient: Response JSON: \(json)")
                        
                        if let text = json["text"] as? String {
                            logToFile("ASRClient: Recognized text: \(text)")
                            self?.delegate?.didReceiveResult(text: text, isFinal: true)
                        } else {
                            logToFile("ASRClient: No 'text' field in response")
                        }
                    }
                } catch {
                    logToFile("ASRClient: JSON parse error: \(error)")
                }
                
                self?.delegate?.didSessionEnd()
            }
        }
        
        task.resume()
    }
    
    private func createWAVFile(pcmData: Data) -> Data {
        var wavData = Data()
        
        let audioDataSize = UInt32(pcmData.count)
        let fileSize = audioDataSize + 36
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(fileSize.littleEndianData)
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianData) // Subchunk1Size (16 for PCM)
        wavData.append(UInt16(1).littleEndianData)  // AudioFormat (1 = PCM)
        wavData.append(UInt16(channels).littleEndianData)
        wavData.append(UInt32(sampleRate).littleEndianData)
        wavData.append(byteRate.littleEndianData)
        wavData.append(blockAlign.littleEndianData)
        wavData.append(UInt16(bitsPerSample).littleEndianData)
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(audioDataSize.littleEndianData)
        wavData.append(pcmData)
        
        logToFile("ASRClient: Created WAV file: \(wavData.count) bytes")
        return wavData
    }
}

// Helper extension for little-endian data
extension UInt32 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt32>.size)
    }
}

extension UInt16 {
    var littleEndianData: Data {
        var value = self.littleEndian
        return Data(bytes: &value, count: MemoryLayout<UInt16>.size)
    }
}
