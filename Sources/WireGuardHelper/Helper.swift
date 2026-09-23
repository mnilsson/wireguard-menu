import Foundation
import WireGuardCore

final class HelperSession: NSObject, WireGuardHelperProtocol {
    let home: URL
    let commands: DispatchQueue

    init(home: URL, commands: DispatchQueue) {
        self.home = home
        self.commands = commands
    }

    func statuses(_ paths: [String], withReply reply: @escaping @Sendable (Data) -> Void) {
        let statuses = Dictionary(paths.map { path in
            (path, validateConfigurationPath(path, home: home) ? Tunnel(path: path).status() : .unknown)
        }, uniquingKeysWith: { first, _ in first })
        reply((try? JSONEncoder().encode(statuses)) ?? Data())
    }

    func change(_ path: String, action: String, withReply reply: @escaping @Sendable (Int32, String) -> Void) {
        guard let action = TunnelAction(rawValue: action), validateConfigurationPath(path, home: home) else {
            reply(-1, "Select a .conf file inside your home folder and use Connect or Disconnect.")
            return
        }
        commands.async {
            guard let executable = ["/opt/homebrew/bin/wg-quick", "/usr/local/bin/wg-quick"]
                .first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                reply(-1, "Install wireguard-tools and wireguard-go with Homebrew.")
                return
            }
            let result = runCommand("/usr/bin/env", arguments: [
                "-i", "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "HOME=/var/root", executable, action.rawValue, path
            ])
            reply(result.code, result.output)
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    let clientRequirement: String
    let commands = DispatchQueue(label: "se.mnilsson.wireguard-menu.commands")

    init(clientRequirement: String) { self.clientRequirement = clientRequirement }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard let user = getpwuid(connection.effectiveUserIdentifier),
              connection.effectiveUserIdentifier != 0 else { return false }
        let home = URL(fileURLWithPath: String(cString: user.pointee.pw_dir), isDirectory: true)
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: WireGuardHelperProtocol.self)
        connection.exportedObject = HelperSession(home: home, commands: commands)
        connection.resume()
        return true
    }
}

@main
struct WireGuardHelper {
    static func main() throws {
        guard geteuid() == 0 else { exit(1) }
        let delegate = HelperDelegate(clientRequirement: try HelperService.peerRequirement(identifier: HelperService.appIdentifier))
        let listener = NSXPCListener(machServiceName: HelperService.name)
        listener.delegate = delegate
        listener.resume()
        withExtendedLifetime(delegate) { RunLoop.current.run() }
    }
}
