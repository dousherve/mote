import Darwin
import Foundation

@MainActor
final class VMControlChannel {
    enum ControlError: LocalizedError {
        case unavailable(String)
        case system(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let name):
                return "The VM '\(name)' is not running."
            case .system(let message):
                return "Unable to communicate with the VM supervisor: \(message)."
            }
        }
    }

    private let url: URL
    private var descriptor: Int32 = -1
    private var pending = Data()

    init(url: URL) throws {
        self.url = url
        _ = Darwin.unlink(url.path)
        guard Darwin.mkfifo(url.path, S_IRUSR | S_IWUSR) == 0 else {
            throw ControlError.system(String(cString: strerror(errno)))
        }

        descriptor = Darwin.open(url.path, O_RDWR | O_NONBLOCK)
        guard descriptor >= 0 else {
            let code = errno
            _ = Darwin.unlink(url.path)
            throw ControlError.system(String(cString: strerror(code)))
        }
    }

    func stop() {
        if descriptor >= 0 {
            Darwin.close(descriptor)
            descriptor = -1
        }
        _ = Darwin.unlink(url.path)
    }

    nonisolated static func isAvailable(for bundle: VMBundle) -> Bool {
        let descriptor = Darwin.open(bundle.controlURL.path, O_WRONLY | O_NONBLOCK)
        guard descriptor >= 0 else { return false }
        Darwin.close(descriptor)
        return true
    }

    nonisolated static func send(_ command: String, to bundle: VMBundle) throws {
        let descriptor = Darwin.open(bundle.controlURL.path, O_WRONLY | O_NONBLOCK)
        guard descriptor >= 0 else {
            throw ControlError.unavailable(bundle.record.name)
        }
        defer { Darwin.close(descriptor) }

        let payload = Data("\(command)\n".utf8)
        let written = payload.withUnsafeBytes {
            Darwin.write(descriptor, $0.baseAddress, $0.count)
        }
        guard written == payload.count else {
            throw ControlError.system(String(cString: strerror(errno)))
        }
    }

    func poll(handler: (String) -> Void) {
        var bytes = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = bytes.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if count > 0 {
                pending.append(contentsOf: bytes.prefix(count))
                continue
            }
            if count < 0, errno != EAGAIN, errno != EWOULDBLOCK {
                stop()
            }
            break
        }

        while let newline = pending.firstIndex(of: 0x0a) {
            let line = pending[..<newline]
            pending.removeSubrange(...newline)
            if let command = String(data: line, encoding: .utf8), !command.isEmpty {
                handler(command)
            }
        }
    }

    deinit {
        if descriptor >= 0 {
            Darwin.close(descriptor)
        }
        _ = Darwin.unlink(url.path)
    }
}
