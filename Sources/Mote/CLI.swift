import Foundation
import Virtualization

struct CLI {
    enum CLIError: LocalizedError {
        case usage(String)
        case installationAlreadyAttempted(String)
        case alreadyRunning(String)
        case notRunning(String)
        case deletionRequiresForce(String)
        case cannotDeleteRunning(String)
        case stopTimedOut(name: String, forced: Bool)

        var errorDescription: String? {
            switch self {
            case .usage(let message): return message
            case .installationAlreadyAttempted(let name):
                return "Installation has already been attempted for '\(name)'. Use --force to run it again."
            case .alreadyRunning(let name):
                return "The VM '\(name)' is already running."
            case .notRunning(let name):
                return "The VM '\(name)' is not running."
            case .deletionRequiresForce(let name):
                return "Deleting '\(name)' permanently removes its bundle. Re-run with --force to confirm."
            case .cannotDeleteRunning(let name):
                return "The VM '\(name)' is running. Stop it before deleting it."
            case .stopTimedOut(let name, let forced):
                if forced {
                    return "Timed out while force-stopping '\(name)'. Check its runner log."
                }
                return "Timed out waiting for '\(name)' to shut down. Re-run with --force to stop it immediately."
            }
        }
    }

    let store: VMStore

    init(store: VMStore = VMStore()) {
        self.store = store
    }

    @MainActor
    func run(arguments: [String]) throws -> String {
        guard let command = arguments.first else { return Self.help }
        switch command {
        case "help", "-h", "--help":
            return Self.help
        case "version", "--version":
            return "mote 0.1.0"
        case "host":
            return try hostInformation(arguments: Array(arguments.dropFirst()))
        case "list", "ls":
            return try listVMs(arguments: Array(arguments.dropFirst()))
        case "show":
            return try showVM(arguments: Array(arguments.dropFirst()))
        case "create":
            return try createVM(arguments: Array(arguments.dropFirst()))
        case "start":
            return try startVM(arguments: Array(arguments.dropFirst()))
        case "stop":
            return try stopVM(arguments: Array(arguments.dropFirst()))
        case "restart":
            return try restartVM(arguments: Array(arguments.dropFirst()))
        case "delete":
            return try deleteVM(arguments: Array(arguments.dropFirst()))
        case "attach":
            return try attachVM(arguments: Array(arguments.dropFirst()))
        case "display":
            return try displayVM(arguments: Array(arguments.dropFirst()))
        case "install":
            return try installVM(arguments: Array(arguments.dropFirst()))
        case "_run":
            return try runSupervisor(arguments: Array(arguments.dropFirst()))
        default:
            throw CLIError.usage("Unknown command '\(command)'. Run 'mote help' for usage.")
        }
    }

    private func hostInformation(arguments: [String]) throws -> String {
        let json = try parseJSONOption(arguments, usage: "Usage: mote host [--json]")
        let process = ProcessInfo.processInfo
        let report = CLIOutput.Host(
            architecture: "arm64",
            logicalCPUCount: process.processorCount,
            memoryBytes: process.physicalMemory,
            minimumVMCPUCount: VZVirtualMachineConfiguration.minimumAllowedCPUCount,
            maximumVMCPUCount: VZVirtualMachineConfiguration.maximumAllowedCPUCount,
            minimumVMMemoryBytes: VZVirtualMachineConfiguration.minimumAllowedMemorySize,
            maximumVMMemoryBytes: VZVirtualMachineConfiguration.maximumAllowedMemorySize,
            storePath: store.root.path
        )
        if json { return try CLIOutput.json(report) }
        return """
        Architecture: \(report.architecture)
        Logical CPUs: \(report.logicalCPUCount)
        Memory: \(ByteSize.format(report.memoryBytes))
        VM CPU range: \(VZVirtualMachineConfiguration.minimumAllowedCPUCount)-\(VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        VM memory range: \(ByteSize.format(VZVirtualMachineConfiguration.minimumAllowedMemorySize))-\(ByteSize.format(VZVirtualMachineConfiguration.maximumAllowedMemorySize))
        Store: \(store.root.path)
        """
    }

    private func listVMs(arguments: [String]) throws -> String {
        let json = try parseJSONOption(arguments, usage: "Usage: mote list [--json]")
        let records = try store.list()
        let reports = records.map { record in
            let bundle = VMBundle(
                record: record,
                url: store.root.appending(path: "\(record.name).motevm", directoryHint: .isDirectory)
            )
            return CLIOutput.VMListItem(
                name: record.name,
                cpuCount: record.cpuCount,
                memoryBytes: record.memorySize,
                diskBytes: record.diskSize,
                state: store.runtimeStatus(for: bundle).name
            )
        }
        if json { return try CLIOutput.json(reports) }
        guard !records.isEmpty else { return "No virtual machines." }
        let rows = reports.map {
            "\($0.name)\t\($0.state)\t\($0.cpuCount) CPU\t\(ByteSize.format($0.memoryBytes))\t\(ByteSize.format($0.diskBytes))"
        }
        return (["NAME\tSTATE\tCPU\tMEMORY\tDISK"] + rows).joined(separator: "\n")
    }

    private func showVM(arguments: [String]) throws -> String {
        guard let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage("Usage: mote show <name> [--json]")
        }
        let json = try parseJSONOption(
            Array(arguments.dropFirst()),
            usage: "Usage: mote show <name> [--json]"
        )
        let bundle = try store.load(named: name)
        let diskUsage = try store.diskUsage(for: bundle)
        let runtimeStatus = store.runtimeStatus(for: bundle)
        let runtime = runtimeStatus.runtime
        let installation = bundle.record.installation.map {
            CLIOutput.Installation(
                state: $0.state.rawValue,
                mediaName: $0.mediaName,
                startedAt: $0.startedAt,
                guestStoppedAt: $0.guestStoppedAt
            )
        }
        let report = CLIOutput.VMDetails(
            name: bundle.record.name,
            id: bundle.record.id.uuidString,
            schemaVersion: bundle.record.schemaVersion,
            createdAt: bundle.record.createdAt,
            cpuCount: bundle.record.cpuCount,
            memoryBytes: bundle.record.memorySize,
            disk: .init(
                configuredBytes: bundle.record.diskSize,
                logicalBytes: diskUsage.logical,
                allocatedBytes: diskUsage.allocated
            ),
            bundlePath: bundle.url.path,
            installation: installation,
            runtime: .init(
                state: runtimeStatus.name,
                pid: runtime?.pid,
                startedAt: runtime?.startedAt
            )
        )
        if json { return try CLIOutput.json(report) }

        let installationDescription: String
        if let installation {
            installationDescription = "\(installation.state) from \(installation.mediaName) at \(Self.formatDate(installation.startedAt))"
        } else {
            installationDescription = "not attempted"
        }
        var runtimeDescription = report.runtime.state
        if let pid = report.runtime.pid, let startedAt = report.runtime.startedAt {
            runtimeDescription += " (PID \(pid), since \(Self.formatDate(startedAt)))"
        }
        return """
        Name: \(report.name)
        ID: \(report.id)
        Schema: \(report.schemaVersion)
        Created: \(Self.formatDate(report.createdAt))
        CPUs: \(report.cpuCount)
        Memory: \(ByteSize.format(report.memoryBytes))
        Disk: \(ByteSize.format(report.disk.logicalBytes)) logical, \(ByteSize.format(report.disk.allocatedBytes)) allocated (\(ByteSize.format(report.disk.configuredBytes)) configured)
        Installation: \(installationDescription)
        Runtime: \(runtimeDescription)
        Bundle: \(report.bundlePath)
        """
    }

    private func createVM(arguments: [String]) throws -> String {
        guard let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage("Usage: mote create <name> [--cpus N] [--memory 8G] [--disk 64G]")
        }

        var cpuCount = min(4, ProcessInfo.processInfo.processorCount)
        var memorySize: UInt64 = 8 << 30
        var diskSize: UInt64 = 64 << 30
        var index = 1

        while index < arguments.count {
            let option = arguments[index]
            guard index + 1 < arguments.count else {
                throw CLIError.usage("Missing value for '\(option)'.")
            }
            let value = arguments[index + 1]
            switch option {
            case "--cpus":
                guard let parsed = Int(value), parsed > 0 else {
                    throw CLIError.usage("Invalid CPU count '\(value)'.")
                }
                cpuCount = parsed
            case "--memory":
                memorySize = try ByteSize.parse(value)
            case "--disk":
                diskSize = try ByteSize.parse(value)
            default:
                throw CLIError.usage("Unknown option '\(option)'.")
            }
            index += 2
        }

        guard (VZVirtualMachineConfiguration.minimumAllowedCPUCount...VZVirtualMachineConfiguration.maximumAllowedCPUCount).contains(cpuCount) else {
            throw CLIError.usage("CPU count must be supported by this host.")
        }
        guard (VZVirtualMachineConfiguration.minimumAllowedMemorySize...VZVirtualMachineConfiguration.maximumAllowedMemorySize).contains(memorySize) else {
            throw CLIError.usage("Memory size must be supported by this host.")
        }
        try VMConfigurationBuilder.validateDiskSize(diskSize)

        let record = VMRecord(name: name, cpuCount: cpuCount, memorySize: memorySize, diskSize: diskSize)
        let url = try store.create(record)
        return "Created '\(name)' at \(url.path)"
    }

    @MainActor
    private func startVM(arguments: [String]) throws -> String {
        guard let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage("Usage: mote start <name> [--display] [--console]")
        }
        var display = false
        var console = false
        for option in arguments.dropFirst() {
            switch option {
            case "--display" where !display:
                display = true
            case "--console" where !console:
                console = true
            default:
                throw CLIError.usage("Unknown option '\(option)'.")
            }
        }

        let bundle = try store.load(named: name)
        guard store.activeRuntime(for: bundle) == nil else {
            throw CLIError.alreadyRunning(name)
        }

        let runtime = try VMProcessLauncher(store: store).launch(bundle: bundle)
        if display {
            try VMControlChannel.send("display", to: bundle)
        }
        if console {
            let attachment = SerialAttachment(bundle: bundle)
            try attachment.run()
            return "Detached from '\(name)'; the VM is still running."
        }
        return "Started '\(name)' (PID \(runtime.pid))."
    }

    private func stopVM(arguments: [String]) throws -> String {
        let (name, force) = try parseForceOption(
            arguments,
            usage: "Usage: mote stop <name> [--force]"
        )
        let bundle = try store.load(named: name)
        try stop(bundle: bundle, force: force)
        return "Stopped '\(name)'."
    }

    private func restartVM(arguments: [String]) throws -> String {
        let (name, force) = try parseForceOption(
            arguments,
            usage: "Usage: mote restart <name> [--force]"
        )
        let bundle = try store.load(named: name)
        try stop(bundle: bundle, force: force)
        let runtime = try VMProcessLauncher(store: store).launch(bundle: bundle)
        return "Restarted '\(name)' (PID \(runtime.pid))."
    }

    private func deleteVM(arguments: [String]) throws -> String {
        let (name, force) = try parseForceOption(
            arguments,
            usage: "Usage: mote delete <name> --force"
        )
        let bundle = try store.load(named: name)
        guard force else { throw CLIError.deletionRequiresForce(name) }
        guard store.activeRuntime(for: bundle) == nil else {
            throw CLIError.cannotDeleteRunning(name)
        }

        let lock: VMLock
        do {
            lock = try VMLock(bundle: bundle)
        } catch VMLock.LockError.unavailable {
            throw CLIError.cannotDeleteRunning(name)
        }
        guard store.activeRuntime(for: bundle) == nil else {
            throw CLIError.cannotDeleteRunning(name)
        }
        try withExtendedLifetime(lock) {
            try store.delete(bundle)
        }
        return "Deleted '\(name)'."
    }

    private func stop(bundle: VMBundle, force: Bool) throws {
        guard store.activeRuntime(for: bundle) != nil else {
            throw CLIError.notRunning(bundle.record.name)
        }
        try VMControlChannel.send(force ? "force-stop" : "stop", to: bundle)

        let timeout: TimeInterval = force ? 10 : 30
        let deadline = Date(timeIntervalSinceNow: timeout)
        repeat {
            if store.activeRuntime(for: bundle) == nil,
               canAcquireLock(for: bundle) {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline

        throw CLIError.stopTimedOut(name: bundle.record.name, forced: force)
    }

    private func canAcquireLock(for bundle: VMBundle) -> Bool {
        do {
            let lock = try VMLock(bundle: bundle)
            withExtendedLifetime(lock) {}
            return true
        } catch {
            return false
        }
    }

    @MainActor
    private func attachVM(arguments: [String]) throws -> String {
        guard arguments.count == 1, let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage("Usage: mote attach <name>")
        }
        let bundle = try store.load(named: name)
        guard store.activeRuntime(for: bundle) != nil else {
            throw CLIError.notRunning(name)
        }
        let attachment = SerialAttachment(bundle: bundle)
        try attachment.run()
        return "Detached from '\(name)'; the VM is still running."
    }

    private func displayVM(arguments: [String]) throws -> String {
        guard arguments.count == 1, let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage("Usage: mote display <name>")
        }
        let bundle = try store.load(named: name)
        guard store.activeRuntime(for: bundle) != nil else {
            throw CLIError.notRunning(name)
        }
        try VMControlChannel.send("display", to: bundle)
        return "Opened the display for '\(name)'."
    }

    @MainActor
    private func runSupervisor(arguments: [String]) throws -> String {
        guard arguments.count == 1, let name = arguments.first else {
            throw CLIError.usage("Invalid internal supervisor invocation.")
        }
        try VMBackgroundSupervisor(store: store).run(name: name)
        return ""
    }

    @MainActor
    private func installVM(arguments: [String]) throws -> String {
        guard let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage("Usage: mote install <name> --iso <path> [--force]")
        }

        var isoPath: String?
        var force = false
        var index = 1
        while index < arguments.count {
            switch arguments[index] {
            case "--iso":
                guard index + 1 < arguments.count else {
                    throw CLIError.usage("Missing value for '--iso'.")
                }
                isoPath = arguments[index + 1]
                index += 2
            case "--force":
                force = true
                index += 1
            default:
                throw CLIError.usage("Unknown option '\(arguments[index])'.")
            }
        }

        guard let isoPath else {
            throw CLIError.usage("Usage: mote install <name> --iso <path> [--force]")
        }

        var bundle = try store.load(named: name)
        if bundle.record.installation != nil, !force {
            throw CLIError.installationAlreadyAttempted(name)
        }
        let lock = try VMLock(bundle: bundle)

        let media = try InstallationMedia(path: isoPath)
        let terminal = TerminalSession()
        let configuration = try VMConfigurationBuilder().build(
            for: bundle,
            consoleInput: terminal.guestInput,
            consoleOutput: .standardOutput,
            options: .init(installationMedia: media.url, graphicalDisplay: true)
        )

        let installation = VMInstallation.started(mediaName: media.url.lastPathComponent)
        bundle = try store.recordInstallation(installation, for: bundle)

        let runner = VMRunner(configuration: configuration, terminal: terminal)
        let reason = try withExtendedLifetime(lock) {
            try runner.run(displayTitle: "Install \(name)")
        }
        switch reason {
        case .guestStopped:
            _ = try store.recordInstallation(installation.recordingGuestStop(), for: bundle)
            return "Installation session ended for '\(name)'. Run 'mote start \(name)' to boot without the ISO."
        case .forced:
            return "Installation session for '\(name)' was force-stopped; its disk may be incomplete."
        }
    }

    private func parseJSONOption(_ arguments: [String], usage: String) throws -> Bool {
        switch arguments {
        case []: return false
        case ["--json"]: return true
        default: throw CLIError.usage(usage)
        }
    }

    private func parseForceOption(_ arguments: [String], usage: String) throws -> (String, Bool) {
        guard let name = arguments.first, !name.hasPrefix("-") else {
            throw CLIError.usage(usage)
        }
        switch Array(arguments.dropFirst()) {
        case []: return (name, false)
        case ["--force"]: return (name, true)
        default: throw CLIError.usage(usage)
        }
    }

    private static func formatDate(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    static let help = """
    Mote — tiny virtual machines on macOS

    USAGE
      mote <command>

    COMMANDS
      create <name> [--cpus N] [--memory 8G] [--disk 64G]
                          Create an empty ARM64 Linux VM bundle
      start <name> [--display] [--console]
                          Start a VM in the background
      stop <name> [--force]
                          Request shutdown, or stop immediately with --force
      restart <name> [--force]
                          Stop and start a running VM
      attach <name>       Attach to a running VM's serial console
      display <name>      Open the display of a running VM
      install <name> --iso <path> [--force]
                          Boot an ARM64 installer in a graphical window
      show <name> [--json]
                          Show VM configuration, storage, and runtime state
      delete <name> --force
                          Permanently delete a stopped VM
      list, ls [--json]   List virtual machines
      host [--json]       Show host virtualization limits
      version             Show the Mote version
      help                Show this help

    ENVIRONMENT
      MOTE_HOME           Override the virtual machine store
    """
}
