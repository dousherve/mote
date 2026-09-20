import Foundation

struct VMInstallation: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case started
        case guestStopped
    }

    let state: State
    let mediaName: String
    let startedAt: Date
    let guestStoppedAt: Date?

    static func started(mediaName: String, at date: Date = Date()) -> Self {
        Self(state: .started, mediaName: mediaName, startedAt: date, guestStoppedAt: nil)
    }

    func recordingGuestStop(at date: Date = Date()) -> Self {
        Self(state: .guestStopped, mediaName: mediaName, startedAt: startedAt, guestStoppedAt: date)
    }
}

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
    let installation: VMInstallation?

    init(
        name: String,
        cpuCount: Int,
        memorySize: UInt64,
        diskSize: UInt64,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        installation: VMInstallation? = nil
    ) {
        self.schemaVersion = 2
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.cpuCount = cpuCount
        self.memorySize = memorySize
        self.diskSize = diskSize
        self.installation = installation
    }

    func recordingInstallation(_ installation: VMInstallation) -> Self {
        Self(
            name: name,
            cpuCount: cpuCount,
            memorySize: memorySize,
            diskSize: diskSize,
            id: id,
            createdAt: createdAt,
            installation: installation
        )
    }
}
