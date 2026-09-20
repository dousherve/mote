import Darwin
import Dispatch
import Foundation

@MainActor
final class SerialAttachment {
    enum AttachmentError: LocalizedError {
        case unavailable(String)
        case cannotReadAttributes(Int32)
        case cannotSetAttributes(Int32)

        var errorDescription: String? {
            switch self {
            case .unavailable(let name):
                return "The serial console for '\(name)' is unavailable."
            case .cannotReadAttributes(let code):
                return "Unable to read terminal attributes: \(String(cString: strerror(code)))."
            case .cannotSetAttributes(let code):
                return "Unable to configure the terminal: \(String(cString: strerror(code)))."
            }
        }
    }

    private let bundle: VMBundle
    private var inputDescriptor: Int32 = -1
    private var logHandle: FileHandle?
    private var inputSource: DispatchSourceRead?
    private var originalAttributes = termios()
    private var terminalWasConfigured = false
    private var finished = false

    init(bundle: VMBundle) {
        self.bundle = bundle
    }

    func run() throws {
        inputDescriptor = Darwin.open(bundle.consoleInputURL.path, O_WRONLY | O_NONBLOCK)
        guard inputDescriptor >= 0 else {
            throw AttachmentError.unavailable(bundle.record.name)
        }
        logHandle = try FileHandle(forReadingFrom: bundle.consoleLogURL)
        try showRecentOutput()
        try configureTerminal()
        Darwin.signal(SIGPIPE, SIG_IGN)
        installInputSource()

        FileHandle.standardError.write(
            Data("\nmote: Attached to '\(bundle.record.name)'. Press Ctrl-] to detach.\n".utf8)
        )
        defer { stop() }

        while !finished {
            copyNewOutput()
            if !VMControlChannel.isAvailable(for: bundle) {
                finished = true
                continue
            }
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        copyNewOutput()
    }

    private func showRecentOutput() throws {
        guard let logHandle else { return }
        let end = try logHandle.seekToEnd()
        try logHandle.seek(toOffset: end > 65_536 ? end - 65_536 : 0)
        copyNewOutput()
    }

    private func configureTerminal() throws {
        guard isatty(STDIN_FILENO) == 1 else { return }
        guard tcgetattr(STDIN_FILENO, &originalAttributes) == 0 else {
            throw AttachmentError.cannotReadAttributes(errno)
        }
        var rawAttributes = originalAttributes
        cfmakeraw(&rawAttributes)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &rawAttributes) == 0 else {
            throw AttachmentError.cannotSetAttributes(errno)
        }
        terminalWasConfigured = true
    }

    private func installInputSource() {
        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler { [weak self] in
            self?.forwardAvailableInput()
        }
        inputSource = source
        source.resume()
    }

    private func forwardAvailableInput() {
        guard let source = inputSource else { return }
        let requestedCount = max(1, min(Int(source.data), 4096))
        var bytes = [UInt8](repeating: 0, count: requestedCount)
        let count = bytes.withUnsafeMutableBytes {
            Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
        }
        guard count > 0 else {
            if count == 0 { finished = true }
            return
        }

        var forwarded = [UInt8]()
        for byte in bytes.prefix(count) {
            if byte == 0x1d {
                finished = true
            } else if !finished {
                forwarded.append(byte)
            }
        }
        guard !forwarded.isEmpty else { return }
        _ = forwarded.withUnsafeBytes {
            Darwin.write(inputDescriptor, $0.baseAddress, $0.count)
        }
    }

    private func copyNewOutput() {
        guard let logHandle else { return }
        do {
            while let data = try logHandle.read(upToCount: 16_384), !data.isEmpty {
                try FileHandle.standardOutput.write(contentsOf: data)
            }
        } catch {
            finished = true
        }
    }

    private func stop() {
        inputSource?.cancel()
        inputSource = nil
        if inputDescriptor >= 0 {
            Darwin.close(inputDescriptor)
            inputDescriptor = -1
        }
        Darwin.signal(SIGPIPE, SIG_DFL)
        try? logHandle?.close()
        logHandle = nil
        if terminalWasConfigured {
            var attributes = originalAttributes
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &attributes)
            terminalWasConfigured = false
        }
    }

    deinit {
        if inputDescriptor >= 0 {
            Darwin.close(inputDescriptor)
        }
    }
}
