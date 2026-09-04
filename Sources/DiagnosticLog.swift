import Foundation

final class DiagnosticLog {
    static let shared = DiagnosticLog()

    private let fileURL: URL?
    private let previousFileURL: URL?
    private let formatter = ISO8601DateFormatter()

    private init() {
        let manager = FileManager.default
        guard let library = manager.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            fileURL = nil
            previousFileURL = nil
            return
        }
        let directory = library.appendingPathComponent("Logs/Gravtail", isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("Gravtail.log")
        previousFileURL = directory.appendingPathComponent("Gravtail.previous.log")
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

        rotateIfNeeded(incomingBytes: data.count)

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

    private func rotateIfNeeded(incomingBytes: Int) {
        guard let fileURL, let previousFileURL else { return }
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        let currentBytes = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        guard MaintenancePolicy.shouldRotateLog(
            currentBytes: currentBytes,
            incomingBytes: incomingBytes
        ) else { return }

        let manager = FileManager.default
        try? manager.removeItem(at: previousFileURL)
        do {
            try manager.moveItem(at: fileURL, to: previousFileURL)
        } catch {
            // Rotation must never affect cursor behavior. If the old log is
            // locked or unavailable, leave it alone and drop this rotation.
        }
    }
}
