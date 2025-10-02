import XCTest
@testable import ScanOrganizerCore

final class ScanOrganizerTests: XCTestCase {

    func testDocumentInitialization() {
        let url = URL(fileURLWithPath: "/test/document.pdf")
        let document = Document(originalPath: url)

        XCTAssertEqual(document.originalPath, url)
        XCTAssertEqual(document.documentType, .unknown)
        XCTAssertEqual(document.confidence, 0.0)
        XCTAssertTrue(document.extractedText.isEmpty)
        XCTAssertNil(document.processedPath)
    }

    func testDocumentTypeDisplayNames() {
        XCTAssertEqual(DocumentType.invoice.displayName, "Rechnung")
        XCTAssertEqual(DocumentType.receipt.displayName, "Quittung")
        XCTAssertEqual(DocumentType.contract.displayName, "Vertrag")
        XCTAssertEqual(DocumentType.letter.displayName, "Brief")
        XCTAssertEqual(DocumentType.report.displayName, "Bericht")
        XCTAssertEqual(DocumentType.statement.displayName, "Kontoauszug")
        XCTAssertEqual(DocumentType.unknown.displayName, "Unbekannt")
    }

    func testProcessingResult() {
        let document = Document(originalPath: URL(fileURLWithPath: "/test.pdf"))
        let result = ProcessingResult(success: true, document: document, processingTime: 1.5)

        XCTAssertTrue(result.success)
        XCTAssertNotNil(result.document)
        XCTAssertNil(result.error)
        XCTAssertEqual(result.processingTime, 1.5)
    }

    func testQueueItemStatus() {
        XCTAssertEqual(QueueItemStatus.pending.displayName, "Wartend")
        XCTAssertEqual(QueueItemStatus.processing.displayName, "In Bearbeitung")
        XCTAssertEqual(QueueItemStatus.completed.displayName, "Abgeschlossen")
        XCTAssertFalse(QueueItemStatus.pending.isFinished)
        XCTAssertFalse(QueueItemStatus.processing.isFinished)
        XCTAssertTrue(QueueItemStatus.completed.isFinished)
    }

    func testQueueItemInitialization() {
        let url = URL(fileURLWithPath: "/test/sample.pdf")
        let item = QueueItem(fileURL: url)

        XCTAssertEqual(item.fileURL, url)
        XCTAssertEqual(item.fileName, "sample.pdf")
        XCTAssertEqual(item.status, .pending)
        XCTAssertEqual(item.progress, 0.0)
        XCTAssertTrue(item.currentStep.isEmpty)
        XCTAssertNil(item.result)
    }

    func testFileOrganizerFolderNames() {
        let organizer = FileOrganizer()
        let year = Calendar.current.component(.year, from: Date())

        // Test internal folder name generation through file organization
        let testURL = URL(fileURLWithPath: "/tmp/test.pdf")

        // Create test file
        FileManager.default.createFile(atPath: testURL.path, contents: nil)

        // Test that the organizer creates proper directory structure
        do {
            _ = try organizer.file(document: testURL, as: "test.pdf", type: .invoice)
            // Cleanup
            try? FileManager.default.removeItem(at: testURL)
        } catch {
            XCTFail("File organization failed: \(error)")
        }
    }

    func testStorageStatisticsFormatting() {
        let stats = StorageStatistics(
            totalFiles: 10,
            totalSize: 1048576, // 1 MB
            filesByType: [.invoice: 5, .receipt: 3, .unknown: 2],
            baseDirectory: URL(fileURLWithPath: "/test")
        )

        XCTAssertEqual(stats.totalFiles, 10)
        XCTAssertEqual(stats.totalSize, 1048576)
        XCTAssertEqual(stats.filesByType[.invoice], 5)
        XCTAssertFalse(stats.formattedSize.isEmpty)
    }

    func testClassificationStructure() {
        let classification = Classification(
            type: .invoice,
            confidence: 0.85,
            vendor: "Test Company",
            amount: Decimal(123.45),
            date: Date(),
            details: "Test details"
        )

        XCTAssertEqual(classification.type, .invoice)
        XCTAssertEqual(classification.confidence, 0.85)
        XCTAssertEqual(classification.vendor, "Test Company")
        XCTAssertEqual(classification.amount, Decimal(123.45))
        XCTAssertNotNil(classification.date)
        XCTAssertEqual(classification.details, "Test details")
    }
}