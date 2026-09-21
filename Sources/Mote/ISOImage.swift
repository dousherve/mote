import Foundation

struct ISOImage: Sendable {
    enum ISOError: LocalizedError {
        case notFound(String)
        case notISO(String)
        case notRegularFile(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let path):
                return "ISO image not found: \(path)"
            case .notISO(let path):
                return "Expected a .iso file: \(path)"
            case .notRegularFile(let path):
                return "ISO image must be a regular file: \(path)"
            }
        }
    }

    let url: URL

    init(path: String, fileManager: FileManager = .default) throws {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        guard url.pathExtension.lowercased() == "iso" else {
            throw ISOError.notISO(url.path)
        }
        guard fileManager.fileExists(atPath: url.path) else {
            throw ISOError.notFound(url.path)
        }
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw ISOError.notRegularFile(url.path)
        }
        self.url = url.resolvingSymlinksInPath()
    }
}
