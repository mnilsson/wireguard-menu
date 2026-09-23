import Foundation
import ServiceManagement
import WireGuardCore

@MainActor
final class HelperClient {
    let service = SMAppService.daemon(plistName: HelperService.plistName)
    var isEnabled: Bool { service.status == .enabled }

    func enable() throws {
        _ = try HelperService.peerRequirement(identifier: HelperService.name)
        if service.status == .notRegistered || service.status == .notFound {
            try service.register()
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    func statuses(paths: [String]) async throws -> [String: TunnelStatus] {
        let data: Data = try await request { proxy, reply in
            proxy.statuses(paths) { reply(.success($0)) }
        }
        return try JSONDecoder().decode([String: TunnelStatus].self, from: data)
    }

    func change(path: String, action: String) async throws -> CommandResult {
        try await request { proxy, reply in
            proxy.change(path, action: action) { code, output in
                reply(.success(CommandResult(code: code, output: output)))
            }
        }
    }

    private func request<Value: Sendable>(
        _ send: (WireGuardHelperProtocol, @escaping @Sendable (Result<Value, Error>) -> Void) -> Void
    ) async throws -> Value {
        let requirement = try HelperService.peerRequirement(identifier: HelperService.name)
        return try await withCheckedThrowingContinuation { continuation in
            let connection = NSXPCConnection(machServiceName: HelperService.name, options: .privileged)
            connection.setCodeSigningRequirement(requirement)
            connection.remoteObjectInterface = NSXPCInterface(with: WireGuardHelperProtocol.self)
            let pending = HelperReply(continuation: continuation, connection: connection)
            let reply: @Sendable (Result<Value, Error>) -> Void = { result in
                Task { @MainActor in pending.finish(result) }
            }
            connection.invalidationHandler = {
                reply(.failure(NSError(domain: HelperService.name, code: 2, userInfo: [NSLocalizedDescriptionKey:
                    "The helper is unavailable. Enable it in System Settings → General → Login Items, then retry."])))
            }
            connection.interruptionHandler = connection.invalidationHandler
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ reply(.failure($0)) }) as? WireGuardHelperProtocol else {
                pending.finish(.failure(NSError(domain: HelperService.name, code: 3)))
                return
            }
            send(proxy, reply)
        }
    }
}

@MainActor
private final class HelperReply<Value: Sendable> {
    var continuation: CheckedContinuation<Value, Error>?
    let connection: NSXPCConnection

    init(continuation: CheckedContinuation<Value, Error>, connection: NSXPCConnection) {
        self.continuation = continuation
        self.connection = connection
    }

    func finish(_ result: Result<Value, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        connection.invalidationHandler = nil
        connection.interruptionHandler = nil
        connection.invalidate()
        continuation.resume(with: result)
    }
}
