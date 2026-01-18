import Foundation
import os.log

enum LogLevel {
    case debug
    case info
    case warning
    case error
}

struct Logger {
    private static let subsystem = "com.meetingprompter.ios"
    
    static func log(_ message: String, level: LogLevel = .info, category: String = "default") {
        let logger = OSLog(subsystem: subsystem, category: category)
        
        switch level {
        case .debug:
            os_log("%{public}@", log: logger, type: .debug, message)
        case .info:
            os_log("%{public}@", log: logger, type: .info, message)
        case .warning:
            os_log("%{public}@", log: logger, type: .default, "⚠️ \(message)")
        case .error:
            os_log("%{public}@", log: logger, type: .error, "❌ \(message)")
        }
    }
}