import Foundation

final class DiagnosticLog {
    static let shared = DiagnosticLog()

    private let fileURL: URL?
    private let formatter = ISO8601DateFormatter()

    private init() {
        let manager = FileManager.default
        guard let library = manager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            fileURL = nil
            return
        }
        let directory = library.appendingPathComponent("Logs/Gravtail", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("Gravtail.log")
    }

    func record(_ event: String, fields: [String: String] = [:]) {
        guard let fileURL else { return }
        let details = fields.keys.sorted().map { key in
            "\(key)=\(fields[key] ?? "")"
        }.joined(separator: " ")
        let suffix = details.isEmpty ? "" : " \(details)"
        guard let data = "\(formatter.string(from: Date())) event=\(event)\(suffix)\n".data(using: .utf8) else {
            return
        }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } catch {
            try? handle.close()
        }
    }
}
