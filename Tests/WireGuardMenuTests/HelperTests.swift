import Foundation
import XCTest
import WireGuardCore
@testable import WireGuardHelper

final class HelperTests: XCTestCase {
    func testOnlyConfigurationPathsWithinClientHomeAreAccepted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let escape = directory.appendingPathComponent("outside")
        try FileManager.default.createSymbolicLink(at: escape, withDestinationURL: URL(fileURLWithPath: "/etc"))

        XCTAssertTrue(validateConfigurationPath(directory.appendingPathComponent("office.conf").path, home: directory))
        XCTAssertFalse(validateConfigurationPath(escape.appendingPathComponent("office.conf").path, home: directory))
        XCTAssertFalse(validateConfigurationPath(directory.path + "/../office.conf", home: directory))
        XCTAssertFalse(validateConfigurationPath(directory.path + "-other/office.conf", home: directory))
        XCTAssertFalse(validateConfigurationPath(directory.path + "/office.txt", home: directory))
    }

    func testHelperRejectsUnsupportedCommandsAndOutsidePaths() async {
        let helper = HelperSession(home: URL(fileURLWithPath: "/Users/example"), commands: DispatchQueue(label: "test"))
        for (path, action) in [("/Users/example/office.conf", "up; id"), ("/etc/office.conf", "up")] {
            let code = await withCheckedContinuation { continuation in
                helper.change(path, action: action) { code, _ in continuation.resume(returning: code) }
            }
            XCTAssertEqual(code, -1)
        }
    }

    func testHelperReturnsStatusForEachRequestedPath() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let path = home.appendingPathComponent("missing.conf").path
        let helper = HelperSession(home: home, commands: DispatchQueue(label: "test"))
        let data = await withCheckedContinuation { continuation in
            helper.statuses([path, path, "/etc/outside.conf"]) { continuation.resume(returning: $0) }
        }
        let result = try JSONDecoder().decode([String: TunnelStatus].self, from: data)
        XCTAssertEqual(result[path], .stopped)
        XCTAssertEqual(result["/etc/outside.conf"], .unknown)
    }

    func testXPCRejectsClientsWithWrongSignature() async {
        let delegate = HelperDelegate(clientRequirement: "identifier \"not.this.app\"")
        let listener = NSXPCListener.anonymous()
        listener.delegate = delegate
        listener.resume()
        defer { listener.invalidate() }
        let connection = NSXPCConnection(listenerEndpoint: listener.endpoint)
        connection.remoteObjectInterface = NSXPCInterface(with: WireGuardHelperProtocol.self)
        connection.resume()
        defer { connection.invalidate() }
        let rejected = expectation(description: "Wrong client signature is rejected")
        let proxy = connection.remoteObjectProxyWithErrorHandler { _ in rejected.fulfill() } as! WireGuardHelperProtocol
        proxy.statuses([]) { _ in XCTFail("Unauthenticated request reached helper") }
        await fulfillment(of: [rejected], timeout: 5)
        withExtendedLifetime(delegate) {}
    }
}
