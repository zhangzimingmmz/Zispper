import Cocoa

typealias KeyHandler = (Bool) -> Void // True=Down, False=Up

class InputManager {
    static let shared = InputManager()
    private var handler: KeyHandler?
    private var isFnPressed = false
    private var isMonitoring = false
    private var permissionCheckTimer: Timer?
    private var hasShownPermissionPrompt = false
    
    // CGEvent Callback
    private let callback: CGEventTapCallBack = { (proxy, type, event, refcon) in
        if type == .flagsChanged {
             // Fn key modifier code is usually 0x00800000 or similar mask change.
             // But simpler to check modifier flags
             let flags = event.flags
             let isFn = flags.contains(.maskSecondaryFn) // "Fn" key
             
             // logToFile("FlagsChanged event. isFn: \(isFn), flags: \(flags.rawValue)")
             
             // Logic to detect UP/DOWN of specific key is tricky with flagsChanged.
             // If we rely on the specific `hasFn` state change:
             let manager = InputManager.shared
             if isFn && !manager.isFnPressed {
                 manager.isFnPressed = true
                 logToFile("Fn Key DOWN detected")
                 manager.handler?(true)
             } else if !isFn && manager.isFnPressed {
                 manager.isFnPressed = false
                 logToFile("Fn Key UP detected")
                 manager.handler?(false)
             }
        }
        return Unmanaged.passRetained(event)
    }
    
    func startMonitoring(handler: @escaping KeyHandler) {
        self.handler = handler
        
        trySetupEventTap()
    }
    
    private func trySetupEventTap() {
        guard !isMonitoring else { return }
        
        // First time: show system prompt. After that: check silently
        let options: [String: Bool]
        if hasShownPermissionPrompt {
            options = [:] // Silent check, no prompt
        } else {
            options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            hasShownPermissionPrompt = true
        }
        
        let trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
        if !trusted {
            logToFile("AXIsProcessTrusted returned false. Will retry silently...")
            startPermissionPolling()
            return
        }
        
        // logToFile("AXIsProcessTrusted returned true.") // Commented out as per instruction
        stopPermissionPolling()
        
        let eventMask = (1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: nil
        ) else {
            logToFile("Failed to create event tap. Will retry...")
            startPermissionPolling()
            return
        }
        
        // Create run loop source
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isMonitoring = true
        logToFile("Event tap created successfully!")
    }
    
    private func startPermissionPolling() {
        guard permissionCheckTimer == nil else { return }
        
        permissionCheckTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.trySetupEventTap()
        }
    }
    
    private func stopPermissionPolling() {
        permissionCheckTimer?.invalidate()
        permissionCheckTimer = nil
    }
    
    func typeText(_ text: String) {
        // Use AppleScript or CGEvent to type.
        // CGEvent is faster but requires mapping Char to KeyCode.
        // Simple way: Clipboard + Paste (Cmd+V) is often most compatible, but "typing" preserves clipboard.
        // Let's use Source: CGEventKeyboardSetUnicodeString which is deprecated but works, 
        // OR better: use Accessibility API or simple key simulation for English.
        // For Unicode (Chinese), Copy+Paste is standard for such tools.
        
        // Save original clipboard content as string
        let pasteboard = NSPasteboard.general
        let originalString = pasteboard.string(forType: .string)
        
        // Set new text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Press Command + V to paste
        let src = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        
        cmdDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        cmdUp?.post(tap: .cghidEventTap)
        
        // Restore original clipboard content after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            pasteboard.clearContents()
            if let original = originalString {
                pasteboard.setString(original, forType: .string)
            }
        }
    }
}
