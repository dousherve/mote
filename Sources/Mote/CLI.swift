import Foundation
import Virtualization

struct CLI {
    enum CLIError: LocalizedError {
        case usage(String)
        case installationAlreadyAttempted(String)
        case alreadyRunning(String)
        case notRunning(String)

        var errorDescription: String? {
            switch self {
            case .usage(let message): return message
            case .installationAlreadyAttempted(let name):
                return "Installation has already been attempted for '\(name)'. Use --force to run it again."
            case .alreadyRunning(let name):
                return "The VM '\(name)' is already running."
            case .notRunning(let name):
                return "The VM '\(name)' is not running."
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
            return hostInformation()
        case "list", "ls":
            return try listVMs()
        case "create":
            return try createVM(arguments: Array(arguments.dropFirst()))
        case "start":
            return try startVM(arguments: Array(arguments.dropFirst()))
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

    private func hostInformation() -> String {
        let process = ProcessInfo.processInfo
        return """
        Architecture: arm64
        Logical CPUs: \(process.processorCount)
        Memory: \(ByteSize.format(process.physicalMemory))
        VM CPU range: \(VZVirtualMachineConfiguration.minimumAllowedCPUCount)-\(VZVirtualMachineConfiguration.maximumAllowedCPUCount)
        VM memory range: \(ByteSize.format(VZVirtualMachineConfiguration.minimumAllowedMemorySize))-\(ByteSize.format(VZVirtualMachineConfiguration.maximumAllowedMemorySize))
        Store: \(store.root.path)
        """
    }

    private func listVMs() throws -> String {
        let records = try store.list()
        guard !records.isEmpty else { return "No virtual machines." }
        let rows = records.map {
            "\($0.name)\t\($0.cpuCount) CPU\t\(ByteSize.format($0.memorySize))\t\(ByteSize.format($0.diskSize))"
        }
        return (["NAME\tCPU\tMEMORY\tDISK"] + rows).joined(separator: "\n")
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

    static let help = """
    Mote — tiny virtual machines on macOS

    USAGE
      mote <command>

    COMMANDS
      create <name> [--cpus N] [--memory 8G] [--disk 64G]
                          Create an empty ARM64 Linux VM bundle
      start <name> [--display] [--console]
                          Start a VM in the background
      attach <name>       Attach to a running VM's serial console
      display <name>      Open the display of a running VM
      install <name> --iso <path> [--force]
                          Boot an ARM64 installer in a graphical window
      list, ls            List virtual machines
      host                Show host virtualization limits
      version             Show the Mote version
      help                Show this help

    ENVIRONMENT
      MOTE_HOME           Override the virtual machine store
    """
}
