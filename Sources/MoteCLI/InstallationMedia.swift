import Foundation

struct InstallationMedia: Sendable {
    enum MediaError: LocalizedError {
        case notFound(String)
        case notISO(String)
        case unsupportedArchitecture(String)
        case unrecognizedArchitecture(String)

        var errorDescription: String? {
            switch self {
            case .notFound(let path):
                return "Installation media not found: \(path)"
            case .notISO(let path):
                return "Installation media must be an ISO file: \(path)"
            case .unsupportedArchitecture(let name):
                return "Installation media '\(name)' targets x86_64; Mote requires ARM64."
            case .unrecognizedArchitecture(let name):
                return "Cannot confirm that '\(name)' is ARM64; its filename must contain 'aarch64' or 'arm64'."
            }
        }
    }

    let url: URL

    init(path: String, fileManager: FileManager = .default) throws {
        let expanded = NSString(string: path).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw MediaError.notFound(url.path)
        }
        guard url.pathExtension.lowercased() == "iso" else {
            throw MediaError.notISO(url.path)
        }

        let name = url.lastPathComponent.lowercased()
        if name.contains("x86_64") || name.contains("amd64") {
            throw MediaError.unsupportedArchitecture(url.lastPathComponent)
        }
        guard name.contains("aarch64") || name.contains("arm64") else {
            throw MediaError.unrecognizedArchitecture(url.lastPathComponent)
        }
        self.url = url
    }
}
