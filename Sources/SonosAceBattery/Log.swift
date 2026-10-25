import Foundation
import os

/// Lightweight logging: unified log (Console.app, subsystem com.buens.SonosAceBattery),
/// stderr, and ~/Library/Logs/SonosAceBattery.log for easy troubleshooting.
enum Log {
    private static let logger = Logger(subsystem: "com.buens.SonosAceBattery", category: "battery")
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()
    private static let fileHandle: FileHandle? = {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs")
        let url = dir.appendingPathComponent("SonosAceBattery.log")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? UInt64, size > 512 * 1024 {
            try? FileManager.default.removeItem(at: url)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let h = try? FileHandle(forWritingTo: url)
        h?.seekToEndOfFile()
        return h
    }()

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
        let data = "[\(stamp.string(from: Date()))] \(message)\n".data(using: .utf8)!
        FileHandle.standardError.write(data)
        fileHandle?.write(data)
    }
}
