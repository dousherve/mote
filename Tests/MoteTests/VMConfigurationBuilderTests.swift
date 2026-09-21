import Foundation
import Testing
@testable import Mote

@Test func derivesStableLocallyAdministeredMACAddress() {
    let id = UUID(uuidString: "12345678-9abc-def0-1234-56789abcdef0")!

    let first = VMConfigurationBuilder.macAddressString(for: id)
    let second = VMConfigurationBuilder.macAddressString(for: id)

    #expect(first == "02:12:34:56:78:9a")
    #expect(second == first)
}

@Test func validatesRawDiskAlignment() throws {
    try VMConfigurationBuilder.validateDiskSize(512)
    try VMConfigurationBuilder.validateDiskSize(64 << 30)
    #expect(throws: VMConfigurationBuilder.ConfigurationError.self) {
        try VMConfigurationBuilder.validateDiskSize(513)
    }
    #expect(throws: VMConfigurationBuilder.ConfigurationError.self) {
        try VMConfigurationBuilder.validateDiskSize(0)
    }
}

@Test @MainActor func startRequiresExactlyOneName() {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let cli = CLI(store: VMStore(root: root))

    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["start"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["start", "one", "two"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["start", "one", "--console", "--console"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["attach"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["display", "one", "two"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["mount", "one"]) }
    #expect(throws: CLI.CLIError.self) { try cli.run(arguments: ["unmount"]) }
}
