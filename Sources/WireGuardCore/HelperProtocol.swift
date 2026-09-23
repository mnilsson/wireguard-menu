import Foundation
import Security

public enum HelperService {
    public static let name = "se.mnilsson.wireguard-menu.helper"
    public static let appIdentifier = "se.mnilsson.wireguard-menu"
    public static let plistName = name + ".plist"

    public static func peerRequirement(identifier: String) throws -> String {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
              let information = information as? [String: Any],
              let team = information[kSecCodeInfoTeamIdentifier as String] as? String,
              team.range(of: "^[A-Z0-9]+$", options: .regularExpression) != nil else {
            throw NSError(domain: name, code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Build the app and helper with an Apple code-signing identity before enabling the helper."])
        }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\""
    }
}

@objc public protocol WireGuardHelperProtocol {
    func statuses(_ paths: [String], withReply reply: @escaping @Sendable (Data) -> Void)
    func change(_ path: String, action: String, withReply reply: @escaping @Sendable (Int32, String) -> Void)
}

public enum TunnelAction: String, Sendable {
    case up, down
}

public func validateConfigurationPath(_ path: String, home: URL) -> Bool {
    let original = URL(fileURLWithPath: path).standardizedFileURL
    let url = original.deletingLastPathComponent().resolvingSymlinksInPath()
        .appendingPathComponent(original.lastPathComponent).resolvingSymlinksInPath()
    let root = home.resolvingSymlinksInPath().path + "/"
    return path.hasPrefix("/") && url.path.hasPrefix(root) && Tunnel(path: url.path).validName
}
