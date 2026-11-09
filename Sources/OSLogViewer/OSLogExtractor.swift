//
//  OSLogExtractor.swift
//  OSLogViewer
//
//  Created by Wesley de Groot on 19/11/2024.
//
//  https://github.com/0xWDG/OSLogViewer
//  MIT LICENCE

import Foundation

#if canImport(OSLog)
import OSLog
#endif

/// OSLogExtractor is made to extract your apps OS_Log history,
public class OSLogExtractor {
    /// Identifier
    public let id = UUID()

    /// Subsystem to read logs from
    public var subsystem: String

    /// From which date preriod
    public var since: Date

    /// How much history is kept; older entries beyond these limits are omitted
    public var limits: OSLogCollectionLimits

    /// OSLogExtractor is made to extract your apps OS_Log history,
    ///
    /// - Parameters:
    ///   - subsystem: which subsystem should be read
    ///   - since: from which time (standard 1hr)
    ///   - limits: how much history is kept (standard 20,000 entries / 8 MB)
    public init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "",
        since: Date = Date().addingTimeInterval(-3600),
        limits: OSLogCollectionLimits = .standard
    ) {
        self.subsystem = subsystem
        self.since = since
        self.limits = limits
    }

    /// Export OSLog as string.
    ///
    /// Contains the newest entries within `limits`; the header states how many
    /// older entries were omitted.
    public func export() async -> String {
#if canImport(OSLog)
        let collection = collect()

        let appName: String = {
            if let displayName: String = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String {
                return displayName
            } else if let name: String = Bundle.main.infoDictionary?["CFBundleName"] as? String {
                return name
            }
            return "this application"
        }()

        var output = "This is the OSLog archive for \(appName).\r\n"
        output += "Generated on \(Date().formatted())\r\n"
        output += "Generator https://github.com/0xWDG/OSLogViewer\r\n"
        if collection.omittedCount > 0 {
            output += "Omitted \(collection.omittedCount) older entries "
            output += "(limit \(limits.maxEntries) entries / \(limits.maxBytes / 1024) KB)\r\n"
        }
        output += "\r\n"
        output.reserveCapacity(output.utf8.count + collection.entries.reduce(0) { $0 + OSLogCollection.cost(of: $1) })

        for (index, entry) in collection.entries.enumerated() {
            if index > 0 { output += "\r\n\r\n" }
            output += entry.composedMessage
            output += "\r\n"
            output += getLogLevelEmoji(level: entry.level)
            output += " \(entry.date.formatted()) 🏛️ \(entry.sender) ⚙️ \(entry.subsystem) 🌐 \(entry.category)"
        }
        return output
#else
        return ""
#endif
    }

#if canImport(OSLog)
    /// Generate an emoji for the current log level
    /// - Parameter level: log level
    /// - Returns: Emoji
    func getLogLevelEmoji(level: OSLogEntryLog.Level) -> String {
        switch level {
        case .undefined, .notice:
            "🔔"
        case .debug:
            "🩺"
        case .info:
            "ℹ️"
        case .error:
            "❗"
        case .fault:
            "‼️"
        default:
            "🔔"
        }
    }

    /// Get the logs
    ///
    /// Returns the newest entries within `limits`, oldest first.
    public func getLog() async -> [OSLogEntryLog] {
        collect().entries
    }

    private func collect() -> OSLogCollection {
        do {
            return try OSLogCollection.collect(
                since: since,
                matching: NSPredicate(format: "subsystem BEGINSWITH %@", subsystem),
                limits: limits
            )
        } catch {
            // We fail to get the results, add this to the log.
            os_log(.fault, "Something went wrong %@", error as NSError)

            return .empty
        }
    }
#endif
}
