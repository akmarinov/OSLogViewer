import XCTest
@testable import OSLogViewer

final class ExportHeaderTests: XCTestCase {
    func testHeaderListsExtraLinesAfterTitle() {
        let extractor = OSLogExtractor(exportHeaderLines: ["App version: 3.3.0", "Build number: 832", "Environment: Dev"])

        let lines = extractor.header(omittedCount: 0).components(separatedBy: "\r\n")

        XCTAssertTrue(lines[0].hasPrefix("This is the OSLog archive for "))
        XCTAssertEqual(Array(lines[1...3]), ["App version: 3.3.0", "Build number: 832", "Environment: Dev"])
        XCTAssertTrue(lines[4].hasPrefix("Generated on "))
    }

    func testHeaderWithoutExtraLinesIsUnchanged() {
        let extractor = OSLogExtractor()

        let lines = extractor.header(omittedCount: 0).components(separatedBy: "\r\n")

        XCTAssertTrue(lines[0].hasPrefix("This is the OSLog archive for "))
        XCTAssertTrue(lines[1].hasPrefix("Generated on "))
        XCTAssertEqual(lines[2], "Generator https://github.com/0xWDG/OSLogViewer")
        XCTAssertEqual(Array(lines.suffix(2)), ["", ""])
    }

    func testHeaderReportsOmittedEntries() {
        let extractor = OSLogExtractor(limits: OSLogCollectionLimits(maxEntries: 10, maxBytes: 2048))

        let header = extractor.header(omittedCount: 5)

        XCTAssertTrue(header.contains("Omitted 5 older entries (limit 10 entries / 2 KB)\r\n"))
    }
}
