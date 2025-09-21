import XCTest
@testable import OSLogViewer

final class FilterSupportTests: XCTestCase {
    private struct DummyEntry: LogEntryFilterable {
        let subsystem: String
        let category: String
    }

    func testFilterEntriesHonorsSubsystemAndCategorySelections() {
        let entries: [DummyEntry] = [
            .init(subsystem: "com.example.app", category: "network"),
            .init(subsystem: "com.example.app", category: "ui"),
            .init(subsystem: "com.example.app", category: ""),
            .init(subsystem: "com.example.analytics", category: "tracking")
        ]

        let filtered = FilterSupport.filterEntries(
            entries,
            subsystemFilters: ["com.example.app"],
            categoryFilters: ["com.example.app": ["network", ""]]
        )

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.category == "network" })
        XCTAssertTrue(filtered.contains { $0.category.isEmpty })
        XCTAssertFalse(filtered.contains { $0.category == "ui" })
        XCTAssertFalse(filtered.contains { $0.subsystem == "com.example.analytics" })
    }

    func testFilterEntriesFallsBackToAllCategoriesWhenUnset() {
        let entries: [DummyEntry] = [
            .init(subsystem: "com.example.app", category: "network"),
            .init(subsystem: "com.example.app", category: "ui")
        ]

        let filtered = FilterSupport.filterEntries(
            entries,
            subsystemFilters: ["com.example.app"],
            categoryFilters: [:]
        )

        XCTAssertEqual(filtered.count, entries.count)
    }

    func testNormalizedCategoriesSortsAndPromotesEmptyCategory() {
        let categories = ["ui", "Network", "", "database", "network"]
        let normalized = FilterSupport.normalizedCategories(from: categories)

        XCTAssertEqual(normalized.first, "")
        XCTAssertEqual(
            Set(normalized.dropFirst()),
            Set(["database", "Network", "network", "ui"])
        )
    }

    func testSanitizeCategorySelectionsRemovesEmptySets() {
        let selections: [String: Set<String>] = [
            "com.example.app": ["network"],
            "com.example.analytics": []
        ]

        let available = [
            "com.example.app": ["network"],
            "com.example.analytics": []
        ]

        let sanitized = FilterSupport.sanitizeCategorySelections(
            currentSelections: selections,
            availableCategories: available
        )

        XCTAssertEqual(sanitized.keys.sorted(), ["com.example.app"])
        XCTAssertEqual(sanitized["com.example.app"], ["network"])
    }
}
