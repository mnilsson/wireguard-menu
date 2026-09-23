import WireGuardCore
import AppKit
import XCTest
@testable import WireGuardMenu

final class TunnelControlsTests: XCTestCase {
    @MainActor
    func testDisconnectRemainsAvailableWithoutReadableRuntimeState() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let mapping = directory.appendingPathComponent("office.name")
        try "utun42\n".write(to: mapping, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: mapping.path)
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: mapping.path)
        let tunnel = Tunnel(path: "/tmp/office.conf")
        let status = tunnel.status(runtimeDirectory: directory.path)
        XCTAssertEqual(status, .unknown)

        let controls = AppDelegate().connectionMenuItems(for: tunnel, status: status)
        let disconnect = try XCTUnwrap(controls.first { $0.title == "Disconnect" })
        XCTAssertTrue(disconnect.isEnabled)
        XCTAssertEqual(disconnect.action, NSSelectorFromString("disconnectTunnel:"))
        XCTAssertEqual(disconnect.representedObject as? String, tunnel.path)
    }
}
