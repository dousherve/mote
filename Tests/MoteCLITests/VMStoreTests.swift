import Foundation
import Testing
@testable import MoteCLI

@Test func validatesNames() {
    #expect(VMStore.isValidName("ubuntu-dev_1"))
    #expect(!VMStore.isValidName("../escape"))
    #expect(!VMStore.isValidName("two words"))
    #expect(!VMStore.isValidName(""))
}

@Test func emptyStoreListsNoVMs() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    let store = VMStore(root: root)
    #expect(try store.list().isEmpty)
}

@Test func loadsCompleteBundle() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "test", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)

    let bundle = try VMStore(root: root).load(named: "test")

    #expect(bundle.record.id == record.id)
    #expect(bundle.diskURL.lastPathComponent == VMRecord.diskName)
    #expect(bundle.variableStoreURL.lastPathComponent == VMRecord.variableStoreName)
}

@Test func rejectsBundleWithMissingDisk() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "broken", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: false, includeVariableStore: true)

    #expect(throws: VMStore.StoreError.self) {
        try VMStore(root: root).load(named: "broken")
    }
}

private func writeBundle(
    _ record: VMRecord,
    at root: URL,
    includeDisk: Bool,
    includeVariableStore: Bool
) throws {
    let bundle = root.appending(path: "\(record.name).motevm", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode(record).write(to: bundle.appending(path: VMRecord.manifestName))
    if includeDisk {
        try Data().write(to: bundle.appending(path: VMRecord.diskName))
    }
    if includeVariableStore {
        try Data().write(to: bundle.appending(path: VMRecord.variableStoreName))
    }
}
