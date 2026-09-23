import Foundation

struct ConfigurationStore {
    var directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("WireGuard Menu/Configurations", isDirectory: true)

    func importConfiguration(from source: URL) throws -> URL {
        let fileManager = FileManager.default
        // Separate imports preserve filenames without overwriting previously removed configurations.
        let folder = directory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(source.lastPathComponent)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            try fileManager.copyItem(at: source, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: folder)
            throw error
        }
    }
}
