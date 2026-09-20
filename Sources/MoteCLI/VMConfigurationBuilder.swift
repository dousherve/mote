import Foundation
import Virtualization

struct VMConfigurationBuilder {
    enum ConfigurationError: LocalizedError {
        case virtualizationUnsupported
        case invalidDiskSize(UInt64)

        var errorDescription: String? {
            switch self {
            case .virtualizationUnsupported:
                return "Virtualization is not supported on this Mac."
            case .invalidDiskSize(let size):
                return "Disk size \(size) must be a multiple of 512 bytes."
            }
        }
    }

    func build(
        for bundle: VMBundle,
        consoleInput: FileHandle,
        consoleOutput: FileHandle
    ) throws -> VZVirtualMachineConfiguration {
        guard VZVirtualMachine.isSupported else {
            throw ConfigurationError.virtualizationUnsupported
        }
        try Self.validateDiskSize(bundle.record.diskSize)

        let configuration = VZVirtualMachineConfiguration()
        configuration.cpuCount = bundle.record.cpuCount
        configuration.memorySize = bundle.record.memorySize

        let bootLoader = VZEFIBootLoader()
        bootLoader.variableStore = VZEFIVariableStore(url: bundle.variableStoreURL)
        configuration.bootLoader = bootLoader
        configuration.platform = VZGenericPlatformConfiguration()

        let diskAttachment = try VZDiskImageStorageDeviceAttachment(
            url: bundle.diskURL,
            readOnly: false,
            cachingMode: .automatic,
            synchronizationMode: .full
        )
        let blockDevice = VZVirtioBlockDeviceConfiguration(attachment: diskAttachment)
        blockDevice.blockDeviceIdentifier = String(bundle.record.id.uuidString.prefix(20))
        configuration.storageDevices = [blockDevice]

        let network = VZVirtioNetworkDeviceConfiguration()
        network.attachment = VZNATNetworkDeviceAttachment()
        network.macAddress = VZMACAddress(string: Self.macAddressString(for: bundle.record.id))!
        configuration.networkDevices = [network]

        configuration.entropyDevices = [VZVirtioEntropyDeviceConfiguration()]
        configuration.memoryBalloonDevices = [VZVirtioTraditionalMemoryBalloonDeviceConfiguration()]

        let serialPort = VZVirtioConsoleDeviceSerialPortConfiguration()
        serialPort.attachment = VZFileHandleSerialPortAttachment(
            fileHandleForReading: consoleInput,
            fileHandleForWriting: consoleOutput
        )
        configuration.serialPorts = [serialPort]

        try configuration.validate()
        return configuration
    }

    static func validateDiskSize(_ size: UInt64) throws {
        guard size > 0, size.isMultiple(of: 512) else {
            throw ConfigurationError.invalidDiskSize(size)
        }
    }

    static func macAddressString(for id: UUID) -> String {
        var uuid = id.uuid
        let bytes = withUnsafeBytes(of: &uuid) { Array($0) }
        return ([UInt8(0x02)] + bytes.prefix(5)).map { String(format: "%02x", $0) }.joined(separator: ":")
    }
}
