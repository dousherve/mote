import Foundation

struct VMProcessLauncher {
    enum LaunchError: LocalizedError {
        case executableUnavailable
        case failed(vm: String, log: String)
        case timedOut(vm: String, log: String)

        var errorDescription: String? {
            switch self {
            case .executableUnavailable:
                return "Unable to locate the Mote executable."
            case .failed(let name, let log):
                return "The supervisor for '\(name)' exited before the VM started. See \(log)."
            case .timedOut(let name, let log):
                return "Timed out while starting '\(name)'. See \(log)."
            }
        }
    }

    let store: VMStore

    func launch(bundle: VMBundle) throws -> VMRuntime {
        guard let executable = Bundle.main.executableURL else {
            throw LaunchError.executableUnavailable
        }

        store.clearRuntime(for: bundle)
        if !FileManager.default.fileExists(atPath: bundle.runnerLogURL.path) {
            guard FileManager.default.createFile(atPath: bundle.runnerLogURL.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: bundle.runnerLogURL.path
        )
        let log = try FileHandle(forWritingTo: bundle.runnerLogURL)
        try log.truncate(atOffset: 0)

        let process = Process()
        process.executableURL = executable
        process.arguments = ["_run", bundle.record.name]
        var environment = ProcessInfo.processInfo.environment
        environment["MOTE_HOME"] = store.root.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = log
        process.standardError = log
        try process.run()
        try log.close()

        let deadline = Date(timeIntervalSinceNow: 10)
        repeat {
            if let runtime = store.activeRuntime(for: bundle),
               runtime.pid == process.processIdentifier {
                return runtime
            }
            if !process.isRunning {
                throw LaunchError.failed(vm: bundle.record.name, log: bundle.runnerLogURL.path)
            }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline

        process.terminate()
        throw LaunchError.timedOut(vm: bundle.record.name, log: bundle.runnerLogURL.path)
    }
}
