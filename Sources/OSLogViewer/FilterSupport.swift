import Foundation

protocol LogEntryFilterable {
    var subsystem: String { get }
    var category: String { get }
}

struct FilterSupport {
    static func normalizedCategories(from categories: [String]) -> [String] {
        var unique = Set<String>()
        var includesEmpty = false

        for category in categories {
            if category.isEmpty {
                includesEmpty = true
            } else {
                unique.insert(category)
            }
        }

        var sorted = unique.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        if includesEmpty {
            sorted.insert("", at: 0)
        }

        return sorted
    }

    static func sanitizeCategorySelections(
        currentSelections: [String: Set<String>],
        availableCategories: [String: [String]]
    ) -> [String: Set<String>] {
        currentSelections.reduce(into: [:]) { partialResult, element in
            let (subsystem, categories) = element
            guard !categories.isEmpty else { return }

            let available = Set(availableCategories[subsystem] ?? [])
            if available.isEmpty {
                partialResult[subsystem] = categories
            } else {
                let intersection = categories.intersection(available)
                if !intersection.isEmpty {
                    partialResult[subsystem] = intersection
                }
            }
        }
    }

    static func displayString(for items: [String]) -> String {
        guard !items.isEmpty else { return "" }

        if let formatted = ListFormatter().string(from: items) {
            return formatted
        }

        return items.joined(separator: ", ")
    }

    static func categoryDisplayName(for category: String) -> String {
        category.isEmpty ? "Uncategorized" : category
    }

    static func filterEntries<Entry: LogEntryFilterable>(
        _ entries: [Entry],
        subsystemFilters: Set<String>,
        categoryFilters: [String: Set<String>]
    ) -> [Entry] {
        entries.filter { entry in
            let matchesSubsystem = subsystemFilters.isEmpty || subsystemFilters.contains(entry.subsystem)
            guard matchesSubsystem else { return false }

            let categories = categoryFilters[entry.subsystem] ?? Set<String>()
            guard !categories.isEmpty else { return true }

            return categories.contains(entry.category)
        }
    }
}

#if canImport(OSLog)
import OSLog

extension OSLogEntryLog: LogEntryFilterable {}
#endif
