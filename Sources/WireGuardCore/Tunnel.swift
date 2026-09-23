import Foundation
import Darwin

public struct Tunnel: Sendable {
    public init(path: String) { self.path = path }
    public let path: String
    public var name: String { URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent }

    public var validName: Bool {
        URL(fileURLWithPath: path).pathExtension == "conf" &&
        name.range(of: #"^[a-zA-Z0-9_=+.-]{1,15}$"#, options: .regularExpression) != nil
    }

    public func status(runtimeDirectory: String = "/var/run/wireguard",
                interfaceExists: (String) -> Bool = { if_nametoindex($0) != 0 }) -> TunnelStatus {
        let fileManager = FileManager.default
        let mapping = runtimeDirectory + "/" + name + ".name"
        do {
            let interface = try String(contentsOfFile: mapping, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard interface.range(of: #"^utun[0-9]+$"#, options: .regularExpression) != nil else {
                return .unknown
            }
            let socket = runtimeDirectory + "/" + interface + ".sock"
            let socketAttributes = try fileManager.attributesOfItem(atPath: socket)
            let mappingAttributes = try fileManager.attributesOfItem(atPath: mapping)
            guard socketAttributes[.type] as? FileAttributeType == .typeSocket,
                  let socketDate = socketAttributes[.modificationDate] as? Date,
                  let mappingDate = mappingAttributes[.modificationDate] as? Date,
                  abs(socketDate.timeIntervalSince(mappingDate)) < 2,
                  interfaceExists(interface) else { return .stopped }
            return .running(interface)
        } catch {
            let error = error as NSError
            if error.domain == NSCocoaErrorDomain &&
                [NSFileReadNoSuchFileError, NSFileNoSuchFileError].contains(error.code) {
                return .stopped
            }
            return .unknown
        }
    }
}

public enum TunnelStatus: Equatable, Codable, Sendable {
    case stopped, running(String), unknown
    public var isRunning: Bool { if case .running = self { return true }; return false }
    public var label: String {
        switch self {
        case .stopped: "Stopped"
        case .running(let interface): "Running · \(interface)"
        case .unknown: "Status unavailable"
        }
    }
}

public struct CommandResult: Sendable {
    public init(code: Int32, output: String) { self.code = code; self.output = output }
    public let code: Int32
    public let output: String
}

public func runCommand(_ executable: String, arguments: [String]) -> CommandResult {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do {
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
    } catch {
        return CommandResult(code: -1, output: error.localizedDescription)
    }
}
