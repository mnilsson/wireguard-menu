import WireGuardCore
import XCTest
import Darwin
@testable import WireGuardMenu

final class TunnelTests: XCTestCase {
    func testRunningRequiresMatchingSocketAndLiveInterface() throws {
        let directory = URL(fileURLWithPath: "/tmp/wgm-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { close(descriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = directory.appendingPathComponent("utun42.sock").path
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: Array(path.utf8) + [0])
        }
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        try "utun42\n".write(to: directory.appendingPathComponent("office.name"), atomically: true, encoding: .utf8)
        let tunnel = Tunnel(path: "/tmp/office.conf")
        XCTAssertEqual(tunnel.status(runtimeDirectory: directory.path, interfaceExists: { $0 == "utun42" }), .running("utun42"))
        XCTAssertEqual(tunnel.status(runtimeDirectory: directory.path, interfaceExists: { _ in false }), .stopped)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1)],
                                             ofItemAtPath: directory.appendingPathComponent("office.name").path)
        XCTAssertEqual(tunnel.status(runtimeDirectory: directory.path, interfaceExists: { _ in true }), .stopped)
    }

    func testConfigurationNames() {
        XCTAssertTrue(Tunnel(path: "/a folder/office.conf").validName)
        XCTAssertFalse(Tunnel(path: "/tmp/office prod.conf").validName)
        XCTAssertFalse(Tunnel(path: "/tmp/abcdefghijklmnop.conf").validName)
        XCTAssertFalse(Tunnel(path: "/tmp/office.zip").validName)
    }

    func testCommandArgumentsPreservePathLiterally() {
        let path = "/tmp/it's $(echo wrong) `echo wrong`\nfile.conf"
        let result = runCommand("/usr/bin/printf", arguments: ["%s", path])
        XCTAssertEqual(result.code, 0)
        XCTAssertEqual(result.output, path)
    }

    func testMissingAndMalformedRuntimeState() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tunnel = Tunnel(path: "/tmp/office.conf")
        XCTAssertEqual(tunnel.status(runtimeDirectory: directory.path), .stopped)
        try "../../something".write(to: directory.appendingPathComponent("office.name"), atomically: true, encoding: .utf8)
        XCTAssertEqual(tunnel.status(runtimeDirectory: directory.path), .unknown)
        try "utun42".write(to: directory.appendingPathComponent("office.name"), atomically: true, encoding: .utf8)
        XCTAssertEqual(tunnel.status(runtimeDirectory: directory.path), .stopped)
    }
}
