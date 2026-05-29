import Cocoa
import AVFoundation

private enum AppSessionState: Equatable {
    case idle(status: String?)
    case recording(sessionID: Int)
    case finishing(sessionID: Int)
    case committing(sessionID: Int)
    case failed(message: String)

    var menuBarTitle: String {
        switch self {
        case .idle(let status):
            let label = status ?? "就绪"
            return "🎤 \(label)"
        case .recording:
            return "🔴 录音中"
        case .finishing:
            return "⏳ 识别中"
        case .committing:
            return "✍️ 输入中"
        case .failed(let message):
            return "⚠️ \(message)"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, ASRClientDelegate, AudioEngineDelegate {
    private var statusBarItem: NSStatusItem!
    private let audioEngine = AudioEngine()
    private let asrClient = ASRClient()
    private let textInjector = TextInjector.shared

    private var state: AppSessionState = .idle(status: "启动中")
    private var activeSessionID: Int?
    private var currentText = ""
    private var fallbackTimeoutWorkItem: DispatchWorkItem?
    private var statusResetWorkItem: DispatchWorkItem?
    private var recordingStartedAt: Date?
    private weak var statusMenuItem: NSMenuItem?
    private var preferredProvider: ASRProviderKind = .local
    private var activeProvider: ASRProviderKind?

    func applicationDidFinishLaunching(_ notification: Notification) {
        logToFile("Application did finish launching")

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureMenu()
        updateState(.idle(status: "就绪"))

        audioEngine.delegate = self
        asrClient.delegate = self

        requestMicrophonePermission()

        InputManager.shared.startMonitoring(handler: { [weak self] isDown in
            DispatchQueue.main.async {
                if isDown {
                    self?.startSession()
                } else {
                    self?.stopSession()
                }
            }
        }, authorizationChanged: { [weak self] authorized in
            self?.handleAccessibilityAuthorizationChange(isAuthorized: authorized)
        })

        asrClient.connect()
    }

    private func configureMenu() {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "\(Configuration.appName) 语音输入", action: nil, keyEquivalent: ""))
        let statusItem = NSMenuItem(title: "状态：启动中", action: nil, keyEquivalent: "")
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem(title: "使用：按住 Fn 说话，松开后自动输入", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "开始/停止录音", action: #selector(toggleRecordingManual), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "查看日志", action: #selector(viewLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusMenuItem = statusItem
        statusBarItem.menu = menu
    }

    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            logToFile("Microphone permission already granted")
        case .notDetermined:
            logToFile("Requesting microphone permission")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logToFile("Microphone permission \(granted ? "granted" : "denied")")
                if !granted {
                    DispatchQueue.main.async {
                        self.updateState(.failed(message: "需要开启麦克风权限"))
                    }
                }
            }
        case .denied, .restricted:
            logToFile("Microphone permission denied or restricted")
            updateState(.failed(message: "需要开启麦克风权限"))
        @unknown default:
            logToFile("Unknown microphone authorization status")
        }
    }

    private func handleAccessibilityAuthorizationChange(isAuthorized: Bool) {
        if isAuthorized {
            logToFile("Accessibility permission granted")
            if case .failed(let message) = state, message == "需要开启辅助功能权限" {
                updateState(.idle(status: "就绪"))
            }
        } else {
            logToFile("Accessibility permission missing")
            if activeSessionID == nil {
                updateState(.failed(message: "需要开启辅助功能权限"))
            }
        }
    }

    @objc private func toggleRecordingManual() {
        switch state {
        case .recording:
            stopSession()
        default:
            startSession()
        }
    }

    @objc private func viewLogs() {
        let script = """
        tell application "iTerm"
            create window with default profile
            tell current session of current window
                write text "tail -f \(Configuration.logPath)"
            end tell
        end tell
        """

        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error {
                logToFile("iTerm AppleScript error: \(error)")
            }
        }
    }

    private func statusText(for state: AppSessionState) -> String {
        let provider = (activeProvider ?? preferredProvider).rawValue

        switch state {
        case .idle(let status):
            return "\(status ?? "就绪")｜通道：\(provider)"
        case .recording:
            return "正在录音｜松开 Fn 后开始识别"
        case .finishing:
            return "正在识别｜通道：\(provider)"
        case .committing:
            return "正在输入识别结果｜通道：\(provider)"
        case .failed(let message):
            return "\(message)｜通道：\(provider)"
        }
    }

    private func updateState(_ newState: AppSessionState) {
        state = newState
        statusBarItem.button?.title = newState.menuBarTitle
        statusMenuItem?.title = "状态：\(statusText(for: newState))"
    }

    private func refreshStatusText() {
        statusMenuItem?.title = "状态：\(statusText(for: state))"
    }

    private func startSession() {
        guard activeSessionID == nil else { return }

        statusResetWorkItem?.cancel()
        statusResetWorkItem = nil

        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            updateState(.failed(message: "需要开启麦克风权限"))
            return
        }

        guard InputManager.shared.hasAccessibilityPermission() else {
            updateState(.failed(message: "需要开启辅助功能权限"))
            return
        }

        fallbackTimeoutWorkItem?.cancel()
        fallbackTimeoutWorkItem = nil

        let sessionID = asrClient.startNewSession()
        activeSessionID = sessionID
        activeProvider = nil
        recordingStartedAt = Date()
        currentText = ""
        updateState(.recording(sessionID: sessionID))
        logToFile("Starting session", sessionID: sessionID)

        do {
            try audioEngine.start()
        } catch {
            logToFile("Audio engine failed to start: \(error.localizedDescription)", sessionID: sessionID)
            activeSessionID = nil
            recordingStartedAt = nil
            updateState(.failed(message: "录音启动失败，请检查麦克风"))
        }
    }

    private func stopSession() {
        guard case .recording(let sessionID) = state else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + Configuration.recordingTailDelay) { [weak self] in
            guard let self,
                  case .recording(let activeID) = self.state,
                  activeID == sessionID else {
                return
            }

            self.audioEngine.stop()
            let recordingDuration = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            self.recordingStartedAt = nil

            if recordingDuration < Configuration.minimumRecordingDuration {
                self.asrClient.discardSession(sessionID: sessionID, reason: "recording too short")
                self.activeSessionID = nil
                self.activeProvider = nil
                self.currentText = ""
                self.showIdleStatus("录音太短", resettingAfter: 1.5)
                logToFile("Ignored very short recording (\(String(format: "%.2f", recordingDuration))s)", sessionID: sessionID)
                return
            }

            self.updateState(.finishing(sessionID: sessionID))
            self.asrClient.sendAudio(data: Data(), isLast: true, sessionID: sessionID)
            self.scheduleFinalizationTimeout(for: sessionID)
            logToFile("Stopped recording; waiting for final result", sessionID: sessionID)
        }
    }

    private func scheduleFinalizationTimeout(for sessionID: Int) {
        fallbackTimeoutWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.asrClient.cancelPendingRequest(reason: "final result timeout", sessionID: sessionID)
            self.completeSession(sessionID: sessionID, committedText: self.currentText, completionReason: "timeout")
        }

        fallbackTimeoutWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Configuration.finalResultTimeout, execute: workItem)
    }

    private func completeSession(sessionID: Int, committedText: String, completionReason: String) {
        guard activeSessionID == sessionID else { return }

        fallbackTimeoutWorkItem?.cancel()
        fallbackTimeoutWorkItem = nil

        if committedText.isEmpty {
            logToFile("Completing session without text (\(completionReason))", sessionID: sessionID)
            activeSessionID = nil
            activeProvider = nil
            recordingStartedAt = nil
            currentText = ""
            showIdleStatus("未识别到语音", resettingAfter: 2)
            return
        }

        updateState(.committing(sessionID: sessionID))
        logToFile("Injecting recognized text (\(completionReason))", sessionID: sessionID)

        textInjector.inject(committedText) { [weak self] result in
            guard let self, self.activeSessionID == sessionID else { return }

            if result.succeeded {
                logToFile("Text injection succeeded", sessionID: sessionID)
                self.activeSessionID = nil
                self.activeProvider = nil
                self.recordingStartedAt = nil
                self.currentText = ""
                self.showIdleStatus("已输入", resettingAfter: 1.2)
            } else {
                let reason = result.reason ?? "Text injection failed"
                logToFile("Text injection failed: \(reason)", sessionID: sessionID)
                self.activeSessionID = nil
                self.activeProvider = nil
                self.recordingStartedAt = nil
                self.currentText = ""
                self.updateState(.failed(message: "粘贴失败，请先点到输入框"))
            }
        }
    }

    func didCaptureAudio(data: Data) {
        guard let sessionID = activeSessionID else { return }
        asrClient.sendAudio(data: data, sessionID: sessionID)
    }

    func didReceiveResult(text: String, isFinal: Bool, sessionID: Int) {
        guard activeSessionID == sessionID else { return }
        currentText = text

        if isFinal, case .finishing = state {
            completeSession(sessionID: sessionID, committedText: text, completionReason: "server result")
        }
    }

    func didError(error: Error, sessionID: Int) {
        guard activeSessionID == sessionID else { return }

        logToFile("ASR error: \(error.localizedDescription)", sessionID: sessionID)
        audioEngine.stop()
        fallbackTimeoutWorkItem?.cancel()
        fallbackTimeoutWorkItem = nil
        activeSessionID = nil
        activeProvider = nil
        recordingStartedAt = nil
        currentText = ""
        updateState(.failed(message: "识别失败，请检查网络或服务"))
    }

    func didSessionEnd(sessionID: Int) {
        guard activeSessionID == sessionID else { return }

        if case .finishing = state {
            completeSession(sessionID: sessionID, committedText: currentText, completionReason: "session end")
        }
    }

    func didSelectProvider(_ provider: ASRProviderKind, sessionID: Int) {
        guard activeSessionID == sessionID else { return }
        activeProvider = provider
        refreshStatusText()
    }

    func didUpdatePreferredProvider(_ provider: ASRProviderKind) {
        preferredProvider = provider
        if activeSessionID == nil {
            refreshStatusText()
        }
    }

    private func showIdleStatus(_ status: String, resettingAfter delay: TimeInterval) {
        updateState(.idle(status: status))

        statusResetWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.activeSessionID == nil else { return }
            self.updateState(.idle(status: "就绪"))
        }

        statusResetWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
