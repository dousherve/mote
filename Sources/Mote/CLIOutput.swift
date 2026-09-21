import Foundation

enum CLIOutput {
    struct Host: Codable {
        let architecture: String
        let logicalCPUCount: Int
        let memoryBytes: UInt64
        let minimumVMCPUCount: Int
        let maximumVMCPUCount: Int
        let minimumVMMemoryBytes: UInt64
        let maximumVMMemoryBytes: UInt64
        let storePath: String
    }

    struct VMListItem: Codable {
        let name: String
        let cpuCount: Int
        let memoryBytes: UInt64
        let diskBytes: UInt64
        let state: String
    }

    struct Disk: Codable {
        let configuredBytes: UInt64
        let logicalBytes: UInt64
        let allocatedBytes: UInt64
    }

    struct Installation: Codable {
        let state: String
        let mediaName: String
        let startedAt: Date
        let guestStoppedAt: Date?
    }

    struct Runtime: Codable {
        let state: String
        let pid: Int32?
        let startedAt: Date?
    }

    struct VMDetails: Codable {
        let name: String
        let id: String
        let schemaVersion: Int
        let createdAt: Date
        let cpuCount: Int
        let memoryBytes: UInt64
        let disk: Disk
        let bundlePath: String
        let installation: Installation?
        let runtime: Runtime
    }

    static func json<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
}
