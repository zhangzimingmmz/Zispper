import Foundation

enum ASRProviderKind: String {
    case local = "本地 ASR"
    case remote = "豆包远程"
}

enum LocalASRHealthState {
    case unknown
    case healthy
    case unhealthy
}

protocol ASRClientDelegate: AnyObject {
    func didReceiveResult(text: String, isFinal: Bool, sessionID: Int)
    func didError(error: Error, sessionID: Int)
    func didSessionEnd(sessionID: Int)
    func didSelectProvider(_ provider: ASRProviderKind, sessionID: Int)
    func didUpdatePreferredProvider(_ provider: ASRProviderKind)
}

final class ASRClient {
    weak var delegate: ASRClientDelegate?

    private let sampleRate = Int(Configuration.audioSampleRate)
    private let channels = Int(Configuration.audioChannels)
    private let bitsPerSample = 16
    private let stateQueue = DispatchQueue(label: "zispper.ASRClient.state")

    private var audioBuffer = Data()
    private var currentSessionID = 0
    private var currentTask: URLSessionTask?
    private var healthTimer: DispatchSourceTimer?
    private var localHealthState: LocalASRHealthState = .unknown
    private var lastLocalFailureAt: Date?
    private var healthProbeFailureCount = 0
    private var didLogImplicitHealthProbeAmbiguity = false

    private lazy var urlSession: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = Configuration.requestTimeout
        configuration.timeoutIntervalForResource = Configuration.requestTimeout
        return URLSession(configuration: configuration)
    }()

    func connect() {
        logToFile("ASR client configured with local-first routing and remote fallback=\(Configuration.doubaoFallbackEnabled)")
        startHealthMonitor()
        probeLocalHealth(reason: "startup")
    }

    func disconnect() {
        cancelPendingRequest(reason: "disconnect")
        healthTimer?.cancel()
        healthTimer = nil
    }

    @discardableResult
    func startNewSession() -> Int {
        stateQueue.sync {
            currentSessionID += 1
            audioBuffer.removeAll(keepingCapacity: true)
            currentTask?.cancel()
            currentTask = nil
            logToFile("Started new ASR session", sessionID: currentSessionID)
            return currentSessionID
        }
    }

    func sendAudio(data: Data, isLast: Bool = false, sessionID: Int) {
        stateQueue.async {
            guard sessionID == self.currentSessionID else {
                logToFile("Ignoring audio for stale session", sessionID: sessionID)
                return
            }

            if !data.isEmpty {
                self.audioBuffer.append(data)
            }

            if isLast {
                self.finishSession(sessionID: sessionID)
            }
        }
    }

    func cancelPendingRequest(reason: String, sessionID: Int? = nil) {
        stateQueue.async {
            let effectiveSessionID = sessionID ?? self.currentSessionID
            guard effectiveSessionID == self.currentSessionID else {
                return
            }

            guard let task = self.currentTask else { return }
            logToFile("Cancelling in-flight upload (\(reason))", sessionID: effectiveSessionID)
            task.cancel()
            self.currentTask = nil
        }
    }

    func discardSession(sessionID: Int, reason: String) {
        stateQueue.async {
            guard sessionID == self.currentSessionID else {
                return
            }

            self.currentTask?.cancel()
            self.currentTask = nil
            self.audioBuffer.removeAll(keepingCapacity: true)
            logToFile("Discarded ASR session (\(reason))", sessionID: sessionID)
        }
    }

    private func finishSession(sessionID: Int) {
        guard !audioBuffer.isEmpty else {
            logToFile("No audio data to send", sessionID: sessionID)
            DispatchQueue.main.async {
                self.delegate?.didSessionEnd(sessionID: sessionID)
            }
            return
        }

        let pcmData = audioBuffer
        audioBuffer.removeAll(keepingCapacity: true)

        let wavData = createWAVFile(pcmData: pcmData)
        logToFile("Finishing session with \(pcmData.count) bytes of PCM", sessionID: sessionID)
        transcribe(wavData: wavData, sessionID: sessionID)
    }

    private func transcribe(wavData: Data, sessionID: Int) {
        if shouldTryLocalProvider() {
            uploadToLocalASR(wavData: wavData, sessionID: sessionID, allowFallback: Configuration.doubaoFallbackEnabled)
        } else if Configuration.doubaoFallbackEnabled {
            uploadToDoubaoFlash(wavData: wavData, sessionID: sessionID)
        } else {
            uploadToLocalASR(wavData: wavData, sessionID: sessionID, allowFallback: false)
        }
    }

    private func shouldTryLocalProvider() -> Bool {
        switch localHealthState {
        case .healthy, .unknown:
            return true
        case .unhealthy:
            guard Configuration.doubaoFallbackEnabled else {
                return true
            }

            guard let lastLocalFailureAt else {
                return false
            }

            if Date().timeIntervalSince(lastLocalFailureAt) >= Configuration.localHealthRetryCooldown {
                markLocalHealth(.unknown, reason: "retry cooldown elapsed")
                return true
            }

            return false
        }
    }

    private func uploadToLocalASR(wavData: Data, sessionID: Int, allowFallback: Bool) {
        notifyProviderSelection(.local, sessionID: sessionID)

        var request = URLRequest(url: Configuration.asrEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = allowFallback ? min(Configuration.requestTimeout, Configuration.localFallbackTimeout) : Configuration.requestTimeout

        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = createLocalMultipartBody(wavData: wavData, boundary: boundary)

        logToFile("Uploading \(wavData.count) bytes to local ASR \(Configuration.asrEndpoint.absoluteString)", sessionID: sessionID)

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            self.stateQueue.async {
                guard sessionID == self.currentSessionID else {
                    logToFile("Ignoring stale local ASR callback", sessionID: sessionID)
                    return
                }

                self.currentTask = nil

                if let error = error as NSError? {
                    if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                        DispatchQueue.main.async {
                            self.delegate?.didSessionEnd(sessionID: sessionID)
                        }
                        return
                    }

                    logToFile("Local ASR upload error: \(error.localizedDescription)", sessionID: sessionID)
                    self.markLocalHealth(.unhealthy, reason: "local request failed")
                    if allowFallback {
                        self.uploadToDoubaoFlash(wavData: wavData, sessionID: sessionID)
                    } else {
                        DispatchQueue.main.async {
                            self.delegate?.didError(error: error, sessionID: sessionID)
                            self.delegate?.didSessionEnd(sessionID: sessionID)
                        }
                    }
                    return
                }

                if let httpResponse = response as? HTTPURLResponse,
                   !(200...299).contains(httpResponse.statusCode) {
                    let error = NSError(
                        domain: "LocalASRClient",
                        code: httpResponse.statusCode,
                        userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                    )
                    logToFile("Local ASR returned HTTP \(httpResponse.statusCode)", sessionID: sessionID)
                    self.markLocalHealth(.unhealthy, reason: "local HTTP \(httpResponse.statusCode)")
                    if allowFallback {
                        self.uploadToDoubaoFlash(wavData: wavData, sessionID: sessionID)
                    } else {
                        DispatchQueue.main.async {
                            self.delegate?.didError(error: error, sessionID: sessionID)
                            self.delegate?.didSessionEnd(sessionID: sessionID)
                        }
                    }
                    return
                }

                guard let data else {
                    let error = NSError(domain: "LocalASRClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data"])
                    self.markLocalHealth(.unhealthy, reason: "local returned no data")
                    if allowFallback {
                        self.uploadToDoubaoFlash(wavData: wavData, sessionID: sessionID)
                    } else {
                        DispatchQueue.main.async {
                            self.delegate?.didError(error: error, sessionID: sessionID)
                            self.delegate?.didSessionEnd(sessionID: sessionID)
                        }
                    }
                    return
                }

                do {
                    let response = try JSONDecoder().decode(LocalASRResponse.self, from: data)
                    self.markLocalHealth(.healthy, reason: "local request succeeded")

                    DispatchQueue.main.async {
                        if let text = response.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            self.delegate?.didReceiveResult(text: text, isFinal: true, sessionID: sessionID)
                        }
                        self.delegate?.didSessionEnd(sessionID: sessionID)
                    }
                } catch {
                    logToFile("Local ASR JSON parse error: \(error)", sessionID: sessionID)
                    self.markLocalHealth(.unhealthy, reason: "local parse failed")
                    if allowFallback {
                        self.uploadToDoubaoFlash(wavData: wavData, sessionID: sessionID)
                    } else {
                        DispatchQueue.main.async {
                            self.delegate?.didError(error: error, sessionID: sessionID)
                            self.delegate?.didSessionEnd(sessionID: sessionID)
                        }
                    }
                }
            }
        }

        stateQueue.async {
            guard sessionID == self.currentSessionID else { return }
            self.currentTask = task
            task.resume()
        }
    }

    private func uploadToDoubaoFlash(wavData: Data, sessionID: Int) {
        guard Configuration.doubaoFallbackEnabled else {
            let error = NSError(domain: "DoubaoASRClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Doubao fallback is not configured"])
            DispatchQueue.main.async {
                self.delegate?.didError(error: error, sessionID: sessionID)
                self.delegate?.didSessionEnd(sessionID: sessionID)
            }
            return
        }

        let appID = Configuration.doubaoAppID
        let accessToken = Configuration.doubaoAccessToken

        notifyProviderSelection(.remote, sessionID: sessionID)

        var request = URLRequest(url: Configuration.doubaoFlashEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = Configuration.requestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(appID, forHTTPHeaderField: "X-Api-App-Key")
        request.setValue(accessToken, forHTTPHeaderField: "X-Api-Access-Key")
        request.setValue(Configuration.doubaoResourceID, forHTTPHeaderField: "X-Api-Resource-Id")
        request.setValue(UUID().uuidString.lowercased(), forHTTPHeaderField: "X-Api-Request-Id")
        request.setValue("-1", forHTTPHeaderField: "X-Api-Sequence")

        let body = DoubaoFlashRequest(
            user: .init(uid: appID),
            audio: .init(data: wavData.base64EncodedString(), format: "wav", language: Configuration.asrLanguage, codec: "raw", rate: sampleRate, bits: bitsPerSample, channel: channels),
            request: .init(modelName: Configuration.doubaoModelName, enableItn: true, enablePunc: true)
        )

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            DispatchQueue.main.async {
                self.delegate?.didError(error: error, sessionID: sessionID)
                self.delegate?.didSessionEnd(sessionID: sessionID)
            }
            return
        }

        logToFile("Uploading \(wavData.count) bytes to Doubao flash fallback", sessionID: sessionID)

        let task = urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }

            self.stateQueue.async {
                guard sessionID == self.currentSessionID else {
                    logToFile("Ignoring stale Doubao callback", sessionID: sessionID)
                    return
                }

                self.currentTask = nil

                DispatchQueue.main.async {
                    if let error = error as NSError? {
                        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
                            self.delegate?.didSessionEnd(sessionID: sessionID)
                            return
                        }

                        self.delegate?.didError(error: error, sessionID: sessionID)
                        self.delegate?.didSessionEnd(sessionID: sessionID)
                        return
                    }

                    if let httpResponse = response as? HTTPURLResponse,
                       !(200...299).contains(httpResponse.statusCode) {
                        let error = NSError(
                            domain: "DoubaoASRClient",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode)"]
                        )
                        self.delegate?.didError(error: error, sessionID: sessionID)
                        self.delegate?.didSessionEnd(sessionID: sessionID)
                        return
                    }

                    guard let data else {
                        let error = NSError(domain: "DoubaoASRClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "No response data"])
                        self.delegate?.didError(error: error, sessionID: sessionID)
                        self.delegate?.didSessionEnd(sessionID: sessionID)
                        return
                    }

                    do {
                        let response = try JSONDecoder().decode(DoubaoFlashResponse.self, from: data)
                        if let text = response.result?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                            self.delegate?.didReceiveResult(text: text, isFinal: true, sessionID: sessionID)
                        } else {
                            logToFile("Doubao flash returned no text", sessionID: sessionID)
                        }
                        self.delegate?.didSessionEnd(sessionID: sessionID)
                    } catch {
                        self.delegate?.didError(error: error, sessionID: sessionID)
                        self.delegate?.didSessionEnd(sessionID: sessionID)
                    }
                }
            }
        }

        stateQueue.async {
            guard sessionID == self.currentSessionID else { return }
            self.currentTask = task
            task.resume()
        }
    }

    private func createLocalMultipartBody(wavData: Data, boundary: String) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(wavData)
        body.append("\r\n".data(using: .utf8)!)

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(Configuration.asrLanguage)\r\n".data(using: .utf8)!)

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    private func notifyProviderSelection(_ provider: ASRProviderKind, sessionID: Int) {
        DispatchQueue.main.async {
            self.delegate?.didSelectProvider(provider, sessionID: sessionID)
        }
    }

    private func startHealthMonitor() {
        guard healthTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(deadline: .now() + Configuration.localHealthCheckInterval, repeating: Configuration.localHealthCheckInterval)
        timer.setEventHandler { [weak self] in
            self?.probeLocalHealth(reason: "periodic")
        }
        timer.resume()
        healthTimer = timer
    }

    private func probeLocalHealth(reason: String) {
        var request = URLRequest(url: Configuration.localASRHealthURL)
        request.httpMethod = Configuration.hasExplicitLocalASRHealthURL ? "GET" : "HEAD"
        request.timeoutInterval = Configuration.localHealthProbeTimeout

        let task = urlSession.dataTask(with: request) { [weak self] _, response, error in
            guard let self = self else { return }

            self.stateQueue.async {
                if let error = error {
                    self.noteHealthProbeFailure("Local ASR health probe failed (\(reason)): \(error.localizedDescription)")
                    self.markLocalHealth(.unhealthy, reason: "health probe failed")
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse else {
                    self.markLocalHealth(.unhealthy, reason: "health probe missing response")
                    return
                }

                if (200...399).contains(httpResponse.statusCode) {
                    self.markLocalHealth(.healthy, reason: "health probe succeeded")
                    return
                }

                if !Configuration.hasExplicitLocalASRHealthURL,
                   [404, 405, 501].contains(httpResponse.statusCode) {
                    if !self.didLogImplicitHealthProbeAmbiguity {
                        logToFile("Local ASR health probe is inconclusive with HTTP \(httpResponse.statusCode); using request outcomes")
                        self.didLogImplicitHealthProbeAmbiguity = true
                    }
                    return
                }

                self.markLocalHealth(.unhealthy, reason: "health probe HTTP \(httpResponse.statusCode)")
            }
        }
        task.resume()
    }

    private func noteHealthProbeFailure(_ message: String) {
        healthProbeFailureCount += 1
        if localHealthState != .unhealthy || healthProbeFailureCount == 1 || healthProbeFailureCount % 10 == 0 {
            logToFile(message)
        }
    }

    private func markLocalHealth(_ newState: LocalASRHealthState, reason: String) {
        guard localHealthState != newState else { return }

        localHealthState = newState
        switch newState {
        case .healthy:
            lastLocalFailureAt = nil
            healthProbeFailureCount = 0
        case .unhealthy:
            lastLocalFailureAt = Date()
        case .unknown:
            break
        }
        logToFile("Local ASR health -> \(String(describing: newState)) (\(reason))")

        let preferredProvider: ASRProviderKind
        switch newState {
        case .healthy, .unknown:
            preferredProvider = .local
        case .unhealthy:
            preferredProvider = Configuration.doubaoFallbackEnabled ? .remote : .local
        }

        DispatchQueue.main.async {
            self.delegate?.didUpdatePreferredProvider(preferredProvider)
        }
    }

    private func createWAVFile(pcmData: Data) -> Data {
        var wavData = Data()

        let audioDataSize = UInt32(pcmData.count)
        let fileSize = audioDataSize + 36
        let byteRate = UInt32(sampleRate * channels * bitsPerSample / 8)
        let blockAlign = UInt16(channels * bitsPerSample / 8)

        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(fileSize.littleEndianData)
        wavData.append("WAVE".data(using: .ascii)!)

        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(UInt32(16).littleEndianData)
        wavData.append(UInt16(1).littleEndianData)
        wavData.append(UInt16(channels).littleEndianData)
        wavData.append(UInt32(sampleRate).littleEndianData)
        wavData.append(byteRate.littleEndianData)
        wavData.append(blockAlign.littleEndianData)
        wavData.append(UInt16(bitsPerSample).littleEndianData)

        wavData.append("data".data(using: .ascii)!)
        wavData.append(audioDataSize.littleEndianData)
        wavData.append(pcmData)

        logToFile("Created WAV payload of \(wavData.count) bytes", sessionID: currentSessionID)
        return wavData
    }
}

private struct LocalASRResponse: Decodable {
    let text: String?
}

private struct DoubaoFlashRequest: Encodable {
    struct User: Encodable {
        let uid: String
    }

    struct Audio: Encodable {
        let data: String
        let format: String
        let language: String
        let codec: String
        let rate: Int
        let bits: Int
        let channel: Int
    }

    struct Request: Encodable {
        let modelName: String
        let enableItn: Bool
        let enablePunc: Bool

        enum CodingKeys: String, CodingKey {
            case modelName = "model_name"
            case enableItn = "enable_itn"
            case enablePunc = "enable_punc"
        }
    }

    let user: User
    let audio: Audio
    let request: Request
}

private struct DoubaoFlashResponse: Decodable {
    struct Result: Decodable {
        let text: String?
    }

    let result: Result?
}

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
