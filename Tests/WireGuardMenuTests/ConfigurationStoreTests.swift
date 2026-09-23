import XCTest
@testable import WireGuardMenu

final class ConfigurationStoreTests: XCTestCase {
    func testImportSurvivesDeletingOriginalAndPreservesEarlierCopies() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: directory) }
        let source = directory.appendingPathComponent("office.conf")
        let store = ConfigurationStore(directory: directory.appendingPathComponent("Application Support/Configurations"))
        try "original configuration".write(to: source, atomically: true, encoding: .utf8)
        let first = try store.importConfiguration(from: source)
        try "replacement configuration".write(to: source, atomically: true, encoding: .utf8)
        let second = try store.importConfiguration(from: source)
        try fileManager.removeItem(at: source)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "office.conf")
        XCTAssertEqual(first.deletingLastPathComponent().deletingLastPathComponent().path, store.directory.path)
        XCTAssertEqual(try String(contentsOf: first, encoding: .utf8), "original configuration")
        XCTAssertEqual(try String(contentsOf: second, encoding: .utf8), "replacement configuration")
    }

    func testFailedImportLeavesNoPartialEntry() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fileManager.removeItem(at: directory) }
        let store = ConfigurationStore(directory: directory)

        XCTAssertThrowsError(try store.importConfiguration(from: directory.appendingPathComponent("missing.conf")))
        XCTAssertEqual(try fileManager.contentsOfDirectory(atPath: directory.path), [])
    }
}
