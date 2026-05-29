import Foundation
import AVFoundation

enum Configuration {
    static let appName = "zispper"
    static let bundleIdentifier = "com.zhangziming.zispper"
    static let logPath = "/tmp/zispper.log"

    static let asrEndpoint = URL(string: environmentValue("ZISPPER_ASR_URL", legacyKey: "DOUBAOVOICE_ASR_URL") ?? "http://127.0.0.1:8766/v1/audio/transcriptions")!
    private static let localASRHealthURLOverride = environmentValue("ZISPPER_LOCAL_ASR_HEALTH_URL", legacyKey: "DOUBAOVOICE_LOCAL_ASR_HEALTH_URL")
    static let localASRHealthURL = URL(string: localASRHealthURLOverride ?? "http://127.0.0.1:8766/health")!
    static let hasExplicitLocalASRHealthURL = localASRHealthURLOverride != nil
    static let asrLanguage = environmentValue("ZISPPER_ASR_LANGUAGE", legacyKey: "DOUBAOVOICE_ASR_LANGUAGE") ?? "zh"

    static let requestTimeout: TimeInterval = doubleValue(for: "ZISPPER_REQUEST_TIMEOUT", legacyKey: "DOUBAOVOICE_REQUEST_TIMEOUT", fallback: 30)
    static let localFallbackTimeout: TimeInterval = doubleValue(for: "ZISPPER_LOCAL_FALLBACK_TIMEOUT", legacyKey: "DOUBAOVOICE_LOCAL_FALLBACK_TIMEOUT", fallback: 2)
    static let localHealthProbeTimeout: TimeInterval = doubleValue(for: "ZISPPER_LOCAL_HEALTH_PROBE_TIMEOUT", legacyKey: "DOUBAOVOICE_LOCAL_HEALTH_PROBE_TIMEOUT", fallback: 1)
    static let localHealthCheckInterval: TimeInterval = doubleValue(for: "ZISPPER_LOCAL_HEALTH_CHECK_INTERVAL", legacyKey: "DOUBAOVOICE_LOCAL_HEALTH_CHECK_INTERVAL", fallback: 60)
    static let localHealthRetryCooldown: TimeInterval = doubleValue(for: "ZISPPER_LOCAL_HEALTH_RETRY_COOLDOWN", legacyKey: "DOUBAOVOICE_LOCAL_HEALTH_RETRY_COOLDOWN", fallback: 20)
    static let recordingTailDelay: TimeInterval = doubleValue(for: "ZISPPER_RECORDING_TAIL_DELAY", legacyKey: "DOUBAOVOICE_RECORDING_TAIL_DELAY", fallback: 0.1)
    static let minimumRecordingDuration: TimeInterval = doubleValue(for: "ZISPPER_MIN_RECORDING_DURATION", legacyKey: "DOUBAOVOICE_MIN_RECORDING_DURATION", fallback: 0.25)
    static let finalResultTimeout: TimeInterval = doubleValue(for: "ZISPPER_FINAL_RESULT_TIMEOUT", legacyKey: "DOUBAOVOICE_FINAL_RESULT_TIMEOUT", fallback: 10)
    static let textInjectionPasteDelay: TimeInterval = doubleValue(for: "ZISPPER_PASTEBOARD_PASTE_DELAY", legacyKey: "DOUBAOVOICE_PASTEBOARD_PASTE_DELAY", fallback: 0.03)
    static let textInjectionRestoreDelay: TimeInterval = doubleValue(for: "ZISPPER_PASTEBOARD_RESTORE_DELAY", legacyKey: "DOUBAOVOICE_PASTEBOARD_RESTORE_DELAY", fallback: 0.2)

    static let doubaoFlashEndpoint = URL(string: environmentValue("ZISPPER_DOUBAO_FLASH_URL", legacyKey: "DOUBAOVOICE_DOUBAO_FLASH_URL") ?? "https://openspeech.bytedance.com/api/v3/auc/bigmodel/recognize/flash")!
    static let doubaoAppID = environmentValue("ZISPPER_DOUBAO_APP_ID", legacyKey: "DOUBAOVOICE_DOUBAO_APP_ID") ?? ""
    static let doubaoAccessToken = environmentValue("ZISPPER_DOUBAO_ACCESS_TOKEN", legacyKey: "DOUBAOVOICE_DOUBAO_ACCESS_TOKEN") ?? ""
    static let doubaoResourceID = environmentValue("ZISPPER_DOUBAO_RESOURCE_ID", legacyKey: "DOUBAOVOICE_DOUBAO_RESOURCE_ID") ?? "volc.bigasr.auc_turbo"
    static let doubaoModelName = environmentValue("ZISPPER_DOUBAO_MODEL", legacyKey: "DOUBAOVOICE_DOUBAO_MODEL") ?? "bigmodel"

    static var doubaoFallbackEnabled: Bool {
        guard !doubaoAppID.isEmpty, !doubaoAccessToken.isEmpty else {
            return false
        }
        return true
    }

    static let audioSampleRate = 16000.0
    static let audioChannels: AVAudioChannelCount = 1
    static let audioBufferLimit = 3200

    private static func environmentValue(_ key: String, legacyKey: String? = nil) -> String? {
        if let value = ProcessInfo.processInfo.environment[key], !value.isEmpty {
            return value
        }

        if let legacyKey, let value = ProcessInfo.processInfo.environment[legacyKey], !value.isEmpty {
            return value
        }

        return nil
    }

    private static func doubleValue(for key: String, legacyKey: String, fallback: TimeInterval) -> TimeInterval {
        guard let rawValue = environmentValue(key, legacyKey: legacyKey), let value = Double(rawValue) else {
            return fallback
        }
        return value
    }
}
