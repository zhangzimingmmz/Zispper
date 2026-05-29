import Foundation

final class Logger {
    static let shared = Logger(logPath: Configuration.logPath)

    private let logPath: String
    private let queue = DispatchQueue(label: "zispper.Logger")
    private let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    init(logPath: String) {
        self.logPath = logPath
    }

    func log(_ message: String, sessionID: Int? = nil) {
        queue.async {
            self.ensureFileExists()

            let timestamp = self.formatter.string(from: Date())
            let sessionPrefix = sessionID.map { "[session:\($0)] " } ?? ""
            let logMessage = "\(timestamp): \(sessionPrefix)\(message)\n"

            guard let handle = FileHandle(forWritingAtPath: self.logPath) else {
                return
            }

            defer {
                try? handle.close()
            }

            do {
                try handle.seekToEnd()
                if let data = logMessage.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } catch {
                fputs("Logger write failed: \(error)\n", stderr)
            }
        }
    }

    private func ensureFileExists() {
        if !FileManager.default.fileExists(atPath: logPath) {
            FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
        }
    }
}

func logToFile(_ message: String, sessionID: Int? = nil) {
    Logger.shared.log(message, sessionID: sessionID)
}
