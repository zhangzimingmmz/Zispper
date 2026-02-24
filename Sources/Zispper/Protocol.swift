import Foundation

// Shared logging utility
func logToFile(_ message: String) {
    let logPath = "/tmp/ZispperDebug.log"
    
    // Create file if not exists
    if !FileManager.default.fileExists(atPath: logPath) {
        FileManager.default.createFile(atPath: logPath, contents: nil, attributes: nil)
    }
    
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let timestamp = formatter.string(from: Date())
    
    let logMessage = "\(timestamp): \(message)\n"
    
    if let handle = FileHandle(forWritingAtPath: logPath) {
        handle.seekToEndOfFile()
        if let data = logMessage.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    }
}
