import Cocoa
import SwiftUI
import AVFoundation

// AppDelegate
class AppDelegate: NSObject, NSApplicationDelegate, ASRClientDelegate, AudioEngineDelegate {
    
    var statusBarItem: NSStatusItem!
    var audioEngine = AudioEngine()
    var asrClient = ASRClient()
    var isRecording = false
    var currentTextText = ""
    var lastCommittedText = ""  // Track what we've already typed
    var hasCommittedResult = false  // Prevent multiple final commits
    var waitingForFinalResult = false  // Wait for final result after stop
    private var fallbackTimeoutWorkItem: DispatchWorkItem? // Track the timeout to prevent leaks

    func applicationDidFinishLaunching(_ notification: Notification) {
        logToFile("App Did Finish Launching")
        
        // Request microphone permission early
        requestMicrophonePermission()
        
        // Setup Status Bar

        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusBarItem.button {
            button.title = "🎤"
        }
        logToFile("Status Bar Item Created")

        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Zispper ASR", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Toggle Recording", action: #selector(toggleRecordingManual), keyEquivalent: "r")) // Manual Trigger
        menu.addItem(NSMenuItem(title: "View Logs", action: #selector(viewLogs), keyEquivalent: "l"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusBarItem.menu = menu
        
        // Setup Delegates
        audioEngine.delegate = self
        asrClient.delegate = self
        
        // Setup Input Monitoring
        logToFile("Starting Input Monitoring...")

        InputManager.shared.startMonitoring { [weak self] isDown in
            DispatchQueue.main.async {
                if isDown {
                    self?.startSession()
                } else {
                    self?.stopSession()
                }
            }
        }
        
        // Connect Client early? Or on demand?
        // Connecting takes time (SSL handshake). Better keep persistent connection or connect on app launch.
        asrClient.connect()
        logToFile("ASR Client Connect called")
    }
    
    private func requestMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            logToFile("Microphone permission already granted")
        case .notDetermined:
            logToFile("Requesting microphone permission...")
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                logToFile("Microphone permission \(granted ? "granted" : "denied")")
                // Permission granted, ready to use immediately
            }
        case .denied, .restricted:
            logToFile("Microphone permission denied or restricted")
        @unknown default:
            break
        }
    }
    @objc func toggleRecordingManual() {
        if isRecording {
            stopSession()
        } else {
            startSession()
        }
    }
    
    @objc func viewLogs() {
        let script = """
        tell application "iTerm"
            create window with default profile
            tell current session of current window
                write text "tail -f /tmp/ZispperDebug.log"
            end tell
        end tell
        """
        
        if let appleScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            appleScript.executeAndReturnError(&error)
            if let error = error {
                print("iTerm AppleScript Error: \(error)")
            }
        }
    }
    
    func startSession() {
        guard !isRecording else { return }
        
        // Ensure correct session state (Handshake + Seq=1)
        asrClient.startNewSession()
        
        // Cancel any lingering timeout from a previous session
        fallbackTimeoutWorkItem?.cancel()
        fallbackTimeoutWorkItem = nil
        
        isRecording = true
        print("Fn Down - Start Recording")
        logToFile("Fn Down - Start Recording")

        
        if let button = statusBarItem.button {
            button.title = "🔴"
        }
        
        currentTextText = ""
        lastCommittedText = ""  // Reset for new session
        hasCommittedResult = false  // Reset for new session
        waitingForFinalResult = false
        do {
            try audioEngine.start()
        } catch {
            print("Audio Engine Error: \(error)")
        }
    }
    
    func stopSession() {
        guard isRecording else { return }
        
        // Add 0.1s delay to capture speech tail
        DispatchQueue.main.asyncAfter(deadline: .now() ) { [weak self] in
            guard let self = self, self.isRecording else { return }
            
            self.isRecording = false
            self.waitingForFinalResult = true  // Start waiting for final result
            
            self.audioEngine.stop()
            
            // Send last frame to signal end of audio
            self.asrClient.sendAudio(data: Data(), isLast: true)
            
            if let button = self.statusBarItem.button {
                button.title = "⏳"
            }
            
            // Cancel any existing timeout
            self.fallbackTimeoutWorkItem?.cancel()
            
            // Fallback timeout in case HTTP request hangs (increased to 10s just in case)
            let workItem = DispatchWorkItem { [weak self] in
                self?.commitFinalResult()
            }
            self.fallbackTimeoutWorkItem = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0, execute: workItem)
        }
    }
    
    private func commitFinalResult() {
        // Cancel timeout since we are now committing
        fallbackTimeoutWorkItem?.cancel()
        fallbackTimeoutWorkItem = nil
        
        guard waitingForFinalResult && !hasCommittedResult else { return }
        
        hasCommittedResult = true
        waitingForFinalResult = false
        
        if !currentTextText.isEmpty {
            logToFile("Committing final result (timeout): \(currentTextText)")
            InputManager.shared.typeText(currentTextText)
        }
        
        DispatchQueue.main.async {
            if let button = self.statusBarItem.button {
                button.title = "🎤"
            }
        }
    }
    
    // AudioEngine Delegate
    func didCaptureAudio(data: Data) {
        // Send to ASR
        asrClient.sendAudio(data: data, isLast: false)
    }
    
    // ASR Delegate
    func didReceiveResult(text: String, isFinal: Bool) {
        print("ASR Result: \(text)")
        
        // Always update current text with latest result
        if !text.isEmpty {
            self.currentTextText = text
            // For HTTP mode, the result is always final and complete. Commit immediately!
            if self.waitingForFinalResult && !self.hasCommittedResult {
                self.commitFinalResult()
            }
        }
    }
    
    func didError(error: Error) {
        print("ASR Error: \(error)")
        logToFile("ASR Error: \(error)")

        DispatchQueue.main.async {
            // Reset state so user can try again
            self.isRecording = false
            self.waitingForFinalResult = false
            self.audioEngine.stop()
            
            if let button = self.statusBarItem.button {
                button.title = "🎤"
            }
        }
    }
    
    // Called when WebSocket closes - server finished processing
    func didSessionEnd() {
        logToFile("Session ended, committing result")
        DispatchQueue.main.async {
            self.commitFinalResult()
        }
    }
}

// Entry Point
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
