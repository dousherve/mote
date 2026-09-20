import Darwin
import Dispatch
import Foundation
import Virtualization

final class VMRunner: NSObject, VZVirtualMachineDelegate, @unchecked Sendable {
    typealias Logger = @Sendable (String) -> Void

    enum StopReason: Sendable {
        case guestStopped
        case forced
    }

    private let virtualMachine: VZVirtualMachine
    private let terminal: TerminalSession
    private let logger: Logger
    private var signalSources: [DispatchSourceSignal] = []
    private var finished = false
    private var failure: Error?
    private var stopReason: StopReason?
    private var stopRequestCount = 0
    private var display: VMDisplay?

    init(
        configuration: VZVirtualMachineConfiguration,
        terminal: TerminalSession,
        logger: @escaping Logger = VMRunner.standardErrorLogger
    ) {
        self.virtualMachine = VZVirtualMachine(configuration: configuration)
        self.terminal = terminal
        self.logger = logger
        super.init()
        self.virtualMachine.delegate = self
    }

    @MainActor
    func run(displayTitle: String? = nil) throws -> StopReason {
        precondition(Thread.isMainThread, "VMRunner must run on the main thread")

        if let displayTitle {
            display = VMDisplay(virtualMachine: virtualMachine, title: displayTitle)
            display?.show()
        }
        try terminal.start { [weak self] in
            self?.requestStop(source: "console escape")
        }
        installSignalHandlers()
        defer {
            removeSignalHandlers()
            terminal.stop()
            display?.close()
            display = nil
        }

        logger("Starting virtual machine…")
        virtualMachine.start { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.logger("Virtual machine is running. Press Ctrl-] to request shutdown.")
            case .failure(let error):
                self.failure = error
                self.finished = true
            }
        }

        while !finished {
            let limit = Date(timeIntervalSinceNow: 0.25)
            if let display {
                display.processEvents(until: limit)
            } else {
                RunLoop.main.run(mode: .default, before: limit)
            }
        }

        if let failure { throw failure }
        return stopReason ?? .forced
    }

    func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        logger("Guest shut down.")
        stopReason = .guestStopped
        finished = true
    }

    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        failure = error
        finished = true
    }

    func virtualMachine(
        _ virtualMachine: VZVirtualMachine,
        networkDevice: VZNetworkDevice,
        attachmentWasDisconnectedWithError error: Error
    ) {
        logger("Network attachment disconnected: \(error.localizedDescription)")
    }

    private func installSignalHandlers() {
        installSignalHandler(SIGINT)
        installSignalHandler(SIGTERM)
    }

    private func installSignalHandler(_ signalNumber: Int32) {
        Darwin.signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { [weak self] in
            self?.requestStop(source: "signal")
        }
        signalSources.append(source)
        source.resume()
    }

    private func removeSignalHandlers() {
        signalSources.forEach { $0.cancel() }
        signalSources.removeAll()
        Darwin.signal(SIGINT, SIG_DFL)
        Darwin.signal(SIGTERM, SIG_DFL)
    }

    private func requestStop(source: String) {
        guard !finished else { return }
        stopRequestCount += 1

        if stopRequestCount == 1, virtualMachine.canRequestStop {
            do {
                try virtualMachine.requestStop()
                logger("Requested a graceful guest shutdown from \(source). Press Ctrl-] again to force stop.")
                return
            } catch {
                logger("Graceful shutdown request failed: \(error.localizedDescription)")
            }
        }

        guard virtualMachine.canStop else {
            logger("The virtual machine cannot be stopped in its current state.")
            return
        }

        logger("Forcing the virtual machine to stop…")
        virtualMachine.stop { [weak self] error in
            guard let self else { return }
            if let error {
                self.failure = error
            }
            self.stopReason = .forced
            self.finished = true
        }
    }

    private static let standardErrorLogger: Logger = { message in
        FileHandle.standardError.write(Data("mote: \(message)\n".utf8))
    }
}
