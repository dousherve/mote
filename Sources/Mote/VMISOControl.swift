import Foundation

enum VMISOControl {
    enum Request: Equatable, Sendable {
        case mount(id: UUID, path: String)
        case unmount(id: UUID)

        var id: UUID {
            switch self {
            case .mount(let id, _), .unmount(let id): id
            }
        }

        var command: String {
            switch self {
            case .mount(let id, let path):
                return "mount-iso \(id.uuidString) \(Data(path.utf8).base64EncodedString())"
            case .unmount(let id):
                return "unmount-iso \(id.uuidString)"
            }
        }

        init?(command: String) {
            let components = command.split(separator: " ", omittingEmptySubsequences: false)
            guard components.count >= 2, let id = UUID(uuidString: String(components[1])) else {
                return nil
            }
            switch components[0] {
            case "mount-iso" where components.count == 3:
                guard let data = Data(base64Encoded: String(components[2])),
                      let path = String(data: data, encoding: .utf8),
                      !path.isEmpty else { return nil }
                self = .mount(id: id, path: path)
            case "unmount-iso" where components.count == 2:
                self = .unmount(id: id)
            default:
                return nil
            }
        }
    }

    enum RequestError: LocalizedError {
        case unsupportedHost
        case failed(String)
        case timedOut(String)
        case supervisorStopped(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedHost:
                return "Hot-mounted ISOs require macOS 15 or newer."
            case .failed(let message):
                return message
            case .timedOut(let name):
                return "Timed out waiting for ISO media operation on '\(name)'. Check its runner log; restart a VM launched by an older Mote build."
            case .supervisorStopped(let name):
                return "The supervisor for '\(name)' stopped before the ISO media operation completed."
            }
        }
    }

    private struct Response: Codable {
        let success: Bool
        let message: String?
    }

    static func request(_ request: Request, to bundle: VMBundle) throws {
        let responseURL = responseURL(for: request.id, bundle: bundle)
        defer { try? FileManager.default.removeItem(at: responseURL) }
        try VMControlChannel.send(request.command, to: bundle)

        let deadline = Date(timeIntervalSinceNow: 30)
        repeat {
            if let data = try? Data(contentsOf: responseURL),
               let response = try? JSONDecoder().decode(Response.self, from: data) {
                if response.success { return }
                throw RequestError.failed(response.message ?? "ISO media operation failed.")
            }
            if !VMControlChannel.isAvailable(for: bundle) {
                throw RequestError.supervisorStopped(bundle.record.name)
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        throw RequestError.timedOut(bundle.record.name)
    }

    static func respond(to request: Request, bundle: VMBundle, error: Error?) throws {
        let response = Response(success: error == nil, message: error?.localizedDescription)
        let data = try JSONEncoder().encode(response)
        let url = responseURL(for: request.id, bundle: bundle)
        let temporaryURL = url.appendingPathExtension("partial")
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        guard FileManager.default.createFile(
            atPath: temporaryURL.path,
            contents: data,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }

    private static func responseURL(for id: UUID, bundle: VMBundle) -> URL {
        bundle.url.appending(path: ".iso-response-\(id.uuidString)")
    }
}
