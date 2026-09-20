import Darwin
import Foundation

final class BackgroundConsole: @unchecked Sendable {
    enum ConsoleError: LocalizedError {
        case system(String)

        var errorDescription: String? {
            switch self {
            case .system(let message):
                return "Unable to create the VM console: \(message)."
            }
        }
    }

    let guestInput: FileHandle
    let guestOutput: FileHandle

    private let inputURL: URL

    init(bundle: VMBundle) throws {
        inputURL = bundle.consoleInputURL
        _ = Darwin.unlink(inputURL.path)
        guard Darwin.mkfifo(inputURL.path, S_IRUSR | S_IWUSR) == 0 else {
            throw ConsoleError.system(String(cString: strerror(errno)))
        }

        let inputDescriptor = Darwin.open(inputURL.path, O_RDWR)
        guard inputDescriptor >= 0 else {
            let code = errno
            _ = Darwin.unlink(inputURL.path)
            throw ConsoleError.system(String(cString: strerror(code)))
        }
        guestInput = FileHandle(fileDescriptor: inputDescriptor, closeOnDealloc: true)

        do {
            guard FileManager.default.createFile(atPath: bundle.consoleLogURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: bundle.consoleLogURL.path
            )
            guestOutput = try FileHandle(forWritingTo: bundle.consoleLogURL)
            try guestOutput.truncate(atOffset: 0)
        } catch {
            try? guestInput.close()
            _ = Darwin.unlink(inputURL.path)
            throw error
        }
    }

    func stop() {
        try? guestInput.close()
        try? guestOutput.close()
        _ = Darwin.unlink(inputURL.path)
    }

    deinit {
        _ = Darwin.unlink(inputURL.path)
    }
}
