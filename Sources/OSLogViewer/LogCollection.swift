//
//  LogCollection.swift
//  OSLogViewer
//
//  https://github.com/0xWDG/OSLogViewer
//  MIT LICENCE

import Foundation

#if canImport(OSLog)
import OSLog
#endif

/// Upper bounds for how much log history is kept in memory.
///
/// Collection keeps the newest entries that fit both limits and counts the
/// older entries it dropped, so a burst of logging cannot exhaust memory.
public struct OSLogCollectionLimits: Equatable, Sendable {
    /// Maximum number of entries kept.
    public var maxEntries: Int

    /// Approximate maximum number of message bytes kept.
    public var maxBytes: Int

    /// Create collection limits.
    /// - Parameters:
    ///   - maxEntries: maximum number of entries kept (standard 20,000)
    ///   - maxBytes: approximate maximum number of message bytes kept (standard 8 MB)
    public init(maxEntries: Int = 20_000, maxBytes: Int = 8 * 1024 * 1024) {
        self.maxEntries = max(1, maxEntries)
        self.maxBytes = max(1, maxBytes)
    }

    /// The standard limits.
    public static let standard = OSLogCollectionLimits()
}

/// Keeps the newest appended elements within `OSLogCollectionLimits`.
struct LogTail<Element> {
    let limits: OSLogCollectionLimits

    private var storage: [(element: Element, cost: Int)] = []
    private var start = 0
    private var bytes = 0
    private(set) var omittedCount = 0

    init(limits: OSLogCollectionLimits) {
        self.limits = limits
    }

    var count: Int { storage.count - start }

    var elements: [Element] { storage[start...].map(\.element) }

    mutating func append(_ element: Element, cost: Int) {
        storage.append((element, cost))
        bytes += cost
        while count > limits.maxEntries || (bytes > limits.maxBytes && count > 1) {
            bytes -= storage[start].cost
            start += 1
            omittedCount += 1
        }
        if start > 4096, start * 2 > storage.count {
            storage.removeFirst(start)
            start = 0
        }
    }
}

#if canImport(OSLog)
/// The newest log entries since a date, plus how many older ones were dropped.
struct OSLogCollection {
    let entries: [OSLogEntryLog]
    let omittedCount: Int

    static let empty = OSLogCollection(entries: [], omittedCount: 0)

    static func cost(of entry: OSLogEntryLog) -> Int {
        entry.composedMessage.utf8.count + entry.subsystem.utf8.count + entry.category.utf8.count + 64
    }

    /// Stream the current process' log store into a bounded tail.
    ///
    /// Returns `.empty` when the surrounding task is cancelled, so callers never
    /// mistake a partial (oldest-only) read for the full window.
    static func collect(
        since: Date,
        matching predicate: NSPredicate,
        limits: OSLogCollectionLimits
    ) throws -> OSLogCollection {
        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        let entries = try logStore.getEntries(at: logStore.position(date: since), matching: predicate)
        var iterator = entries.makeIterator()
        var tail = LogTail<OSLogEntryLog>(limits: limits)
        var hasMore = true

        while hasMore {
            if Task.isCancelled { return .empty }
            withAutoreleasePool {
                guard let next = iterator.next() else {
                    hasMore = false
                    return
                }
                guard let log = next as? OSLogEntryLog else { return }
                tail.append(log, cost: cost(of: log))
            }
        }

        return OSLogCollection(entries: tail.elements, omittedCount: tail.omittedCount)
    }

    private static func withAutoreleasePool(_ body: () -> Void) {
#if canImport(ObjectiveC)
        autoreleasepool(invoking: body)
#else
        body()
#endif
    }
}
#endif
