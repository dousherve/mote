import Darwin
import Dispatch
import Foundation

final class TerminalSession: @unchecked Sendable {
    enum TerminalError: LocalizedError {
        case cannotReadAttributes(Int32)
        case cannotSetAttributes(Int32)

        var errorDescription: String? {
            switch self {
            case .cannotReadAttributes(let code):
                return "Unable to read terminal attributes: \(String(cString: strerror(code)))."
            case .cannotSetAttributes(let code):
                return "Unable to configure the terminal: \(String(cString: strerror(code)))."
            }
        }
    }

    let guestInput: FileHandle

    private let inputPipe: Pipe
    private var inputSource: DispatchSourceRead?
    private var originalAttributes = termios()
    private var terminalWasConfigured = false
    private var escapeHandler: (@Sendable () -> Void)?

    init() {
        let pipe = Pipe()
        self.inputPipe = pipe
        self.guestInput = pipe.fileHandleForReading
    }

    func start(onEscape: @escaping @Sendable () -> Void) throws {
        escapeHandler = onEscape

        if isatty(STDIN_FILENO) == 1 {
            guard tcgetattr(STDIN_FILENO, &originalAttributes) == 0 else {
                throw TerminalError.cannotReadAttributes(errno)
            }
            var rawAttributes = originalAttributes
            cfmakeraw(&rawAttributes)
            guard tcsetattr(STDIN_FILENO, TCSANOW, &rawAttributes) == 0 else {
                throw TerminalError.cannotSetAttributes(errno)
            }
            terminalWasConfigured = true
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: STDIN_FILENO, queue: .main)
        source.setEventHandler { [weak self] in
            self?.forwardAvailableInput()
        }
        inputSource = source
        source.resume()
    }

    func stop() {
        inputSource?.cancel()
        inputSource = nil
        escapeHandler = nil

        if terminalWasConfigured {
            var attributes = originalAttributes
            _ = tcsetattr(STDIN_FILENO, TCSANOW, &attributes)
            terminalWasConfigured = false
        }
    }

    private func forwardAvailableInput() {
        guard let source = inputSource else { return }
        let requestedCount = max(1, min(Int(source.data), 4096))
        var buffer = [UInt8](repeating: 0, count: requestedCount)
        let bytesRead = buffer.withUnsafeMutableBytes {
            Darwin.read(STDIN_FILENO, $0.baseAddress, $0.count)
        }

        guard bytesRead > 0 else {
            if bytesRead == 0 { inputSource?.cancel() }
            return
        }

        var guestBytes = [UInt8]()
        guestBytes.reserveCapacity(bytesRead)
        for byte in buffer.prefix(bytesRead) {
            if byte == 0x1d { // Ctrl-]
                escapeHandler?()
            } else {
                guestBytes.append(byte)
            }
        }

        if !guestBytes.isEmpty {
            try? inputPipe.fileHandleForWriting.write(contentsOf: Data(guestBytes))
        }
    }

    deinit {
        stop()
    }
}
