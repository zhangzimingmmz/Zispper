import Cocoa

typealias KeyHandler = (Bool) -> Void

final class InputManager {
    static let shared = InputManager()

    private var handler: KeyHandler?
    private var authorizationChanged: ((Bool) -> Void)?
    private var isFnPressed = false
    private var isMonitoring = false
    private var permissionCheckTimer: Timer?
    private var hasShownPermissionPrompt = false
    private var eventTap: CFMachPort?
    private var authorizationState: Bool?

    private let callback: CGEventTapCallBack = { _, type, event, _ in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            let manager = InputManager.shared
            if let eventTap = manager.eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                logToFile("Event tap re-enabled after \(type)")
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let manager = InputManager.shared
        let isFn = event.flags.contains(.maskSecondaryFn)

        if isFn && !manager.isFnPressed {
            manager.isFnPressed = true
            logToFile("Fn key down detected")
            manager.handler?(true)
        } else if !isFn && manager.isFnPressed {
            manager.isFnPressed = false
            logToFile("Fn key up detected")
            manager.handler?(false)
        }

        return Unmanaged.passUnretained(event)
    }

    private init() {}

    func startMonitoring(handler: @escaping KeyHandler, authorizationChanged: ((Bool) -> Void)? = nil) {
        self.handler = handler
        self.authorizationChanged = authorizationChanged
        trySetupEventTap()
    }

    func hasAccessibilityPermission() -> Bool {
        AXIsProcessTrusted()
    }

    private func trySetupEventTap() {
        guard !isMonitoring else {
            notifyAuthorizationIfNeeded(true)
            return
        }

        let trusted: Bool
        if hasShownPermissionPrompt {
            trusted = AXIsProcessTrusted()
        } else {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            trusted = AXIsProcessTrustedWithOptions(options as CFDictionary)
            hasShownPermissionPrompt = true
        }

        notifyAuthorizationIfNeeded(trusted)

        if !trusted {
            logToFile("Accessibility permission missing; retrying silently")
            startPermissionPolling()
            return
        }

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
            logToFile("Failed to create event tap; retrying")
            startPermissionPolling()
            return
        }

        eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isMonitoring = true
        logToFile("Event tap created successfully")
    }

    private func notifyAuthorizationIfNeeded(_ isAuthorized: Bool) {
        guard authorizationState != isAuthorized else {
            return
        }

        authorizationState = isAuthorized
        DispatchQueue.main.async {
            self.authorizationChanged?(isAuthorized)
        }
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
}
