import Foundation

struct VMRecord: Codable, Sendable {
    static let manifestName = "config.json"
    static let diskName = "disk.img"
    static let variableStoreName = "efi-variable-store"

    let schemaVersion: Int
    let id: UUID
    let name: String
    let createdAt: Date
    let cpuCount: Int
    let memorySize: UInt64
    let diskSize: UInt64

    init(name: String, cpuCount: Int, memorySize: UInt64, diskSize: UInt64) {
        self.schemaVersion = 1
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.cpuCount = cpuCount
        self.memorySize = memorySize
        self.diskSize = diskSize
    }
}
