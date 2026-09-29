import Foundation
import os.log

// Public logging helper that makes strings visible in Console.app
struct LogHelper {
    private static let log = OSLog(subsystem: "com.iayxify.iayxify", category: "Iayxify")
    
    static func log(_ message: String) {
        os_log("%{public}@", log: log, type: .default, "[Iayxify] \(message)")
    }
    
    static func logError(_ message: String) {
        os_log("%{public}@", log: log, type: .error, "[Iayxify] ERROR: \(message)")
    }
    
    static func logDebug(_ message: String) {
        os_log("%{public}@", log: log, type: .debug, "[Iayxify] \(message)")
    }
}
