import Foundation
import Virtualization

struct CLI {
    enum CLIError: LocalizedError {
        case usage(String)

        var errorDescription: String? {
            switch self {
            case .usage(let message): return message
            }
        }
    }

    let store: VMStore

    init(store: VMStore = VMStore()) {
        self.store = store
    }

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

    private func startVM(arguments: [String]) throws -> String {
        guard arguments.count == 1, let name = arguments.first else {
            throw CLIError.usage("Usage: mote start <name>")
        }

        let bundle = try store.load(named: name)
        let terminal = TerminalSession()
        let configuration = try VMConfigurationBuilder().build(
            for: bundle,
            consoleInput: terminal.guestInput,
            consoleOutput: .standardOutput
        )
        let runner = VMRunner(configuration: configuration, terminal: terminal)
        try runner.run()
        return ""
    }

    static let help = """
    Mote — tiny virtual machines on macOS

    USAGE
      mote <command>

    COMMANDS
      create <name> [--cpus N] [--memory 8G] [--disk 64G]
                          Create an empty ARM64 Linux VM bundle
      start <name>        Start a VM in the foreground
      list, ls            List virtual machines
      host                Show host virtualization limits
      version             Show the Mote version
      help                Show this help

    ENVIRONMENT
      MOTE_HOME           Override the virtual machine store
    """
}
