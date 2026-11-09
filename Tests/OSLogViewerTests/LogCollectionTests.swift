import XCTest
@testable import OSLogViewer

#if canImport(OSLog)
import OSLog
#endif

final class LogCollectionTests: XCTestCase {
    func testTailKeepsTheNewestEntriesWithinTheEntryLimit() {
        var tail = LogTail<String>(limits: OSLogCollectionLimits(maxEntries: 3, maxBytes: .max))
        for index in 0..<10 {
            tail.append("m\(index)", cost: 1)
        }

        XCTAssertEqual(tail.elements, ["m7", "m8", "m9"])
        XCTAssertEqual(tail.omittedCount, 7)
    }

    func testTailKeepsTheNewestEntriesWithinTheByteLimit() {
        var tail = LogTail<String>(limits: OSLogCollectionLimits(maxEntries: .max, maxBytes: 25))
        for index in 0..<10 {
            tail.append("m\(index)", cost: 10)
        }

        XCTAssertEqual(tail.elements, ["m8", "m9"])
        XCTAssertEqual(tail.omittedCount, 8)
    }

    func testTailKeepsASingleEntryLargerThanTheByteLimit() {
        var tail = LogTail<String>(limits: OSLogCollectionLimits(maxEntries: 10, maxBytes: 5))
        tail.append("huge", cost: 100)

        XCTAssertEqual(tail.elements, ["huge"])
        XCTAssertEqual(tail.omittedCount, 0)
    }

#if canImport(OSLog)
    func testExtractorExportsOnlyTheNewestEntriesAndReportsTheRest() async throws {
        let subsystem = "nl.wesleydegroot.oslogviewer.tests.\(UUID().uuidString)"
        let logger = Logger(subsystem: subsystem, category: "bounded")
        let since = Date().addingTimeInterval(-1)
        for index in 0..<50 {
            logger.notice("bounded-entry-\(index, privacy: .public)")
        }

        let extractor = OSLogExtractor(
            subsystem: subsystem,
            since: since,
            limits: OSLogCollectionLimits(maxEntries: 5)
        )
        let entries = await extractor.getLog()
        let export = await extractor.export()

        XCTAssertEqual(entries.map(\.composedMessage), (45..<50).map { "bounded-entry-\($0)" })
        XCTAssertTrue(export.contains("Omitted 45 older entries"))
        XCTAssertTrue(export.contains("bounded-entry-49"))
        XCTAssertFalse(export.contains("bounded-entry-44"))
    }
#endif
}
