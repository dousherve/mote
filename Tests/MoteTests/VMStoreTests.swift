import Foundation
import Testing
@testable import Mote

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

@Test func decodesLegacyManifestWithoutInstallationState() throws {
    let json = """
    {
      "schemaVersion": 1,
      "id": "12345678-9ABC-DEF0-1234-56789ABCDEF0",
      "name": "legacy",
      "createdAt": "2026-09-20T12:00:00Z",
      "cpuCount": 2,
      "memorySize": 1073741824,
      "diskSize": 1073741824
    }
    """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    let record = try decoder.decode(VMRecord.self, from: Data(json.utf8))

    #expect(record.schemaVersion == 1)
    #expect(record.installation == nil)
}

@Test func recordsInstallationStateAtomically() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "installing", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)
    let store = VMStore(root: root)
    let bundle = try store.load(named: "installing")
    let startedAt = Date(timeIntervalSince1970: 1_800_000_000)
    let installation = VMInstallation.started(mediaName: "Fedora-aarch64.iso", at: startedAt)

    _ = try store.recordInstallation(installation, for: bundle)
    let updated = try store.load(named: "installing")

    #expect(updated.record.schemaVersion == 2)
    #expect(updated.record.installation == installation)
}

@Test func ignoresInterruptedManifestTemporaryFile() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "recoverable", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)
    let temporaryManifest = root
        .appending(path: "recoverable.motevm")
        .appending(path: ".config.json.interrupted")
    try Data("{\"incomplete\":" .utf8).write(to: temporaryManifest)

    let loaded = try VMStore(root: root).load(named: "recoverable")

    #expect(loaded.record.id == record.id)
}

@Test func reportsDiskAllocationAndDeletesBundle() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "disposable", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 20)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)
    let store = VMStore(root: root)
    let bundle = try store.load(named: "disposable")
    let disk = try FileHandle(forWritingTo: bundle.diskURL)
    try disk.truncate(atOffset: record.diskSize)
    try disk.close()

    let usage = try store.diskUsage(for: bundle)
    #expect(usage.logical == record.diskSize)
    #expect(usage.allocated <= usage.logical)

    try store.delete(bundle)
    #expect(!FileManager.default.fileExists(atPath: bundle.url.path))
}

@Test @MainActor func structuredCLIOutputIsValidJSON() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "json-vm", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)
    let cli = CLI(store: VMStore(root: root))

    let listData = Data(try cli.run(arguments: ["list", "--json"]).utf8)
    let list = try #require(JSONSerialization.jsonObject(with: listData) as? [[String: Any]])
    #expect(list.first?["name"] as? String == "json-vm")
    #expect(list.first?["state"] as? String == "stopped")

    let showData = Data(try cli.run(arguments: ["show", "json-vm", "--json"]).utf8)
    let details = try #require(JSONSerialization.jsonObject(with: showData) as? [String: Any])
    #expect(details["name"] as? String == "json-vm")
    #expect((details["runtime"] as? [String: Any])?["state"] as? String == "stopped")
}

@Test @MainActor func deleteRequiresForceAndRemovesStoppedVM() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "delete-me", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)
    let cli = CLI(store: VMStore(root: root))

    #expect(throws: CLI.CLIError.self) {
        try cli.run(arguments: ["delete", "delete-me"])
    }
    #expect(try cli.run(arguments: ["delete", "delete-me", "--force"]) == "Deleted 'delete-me'.")
    #expect(!FileManager.default.fileExists(atPath: root.appending(path: "delete-me.motevm").path))
}

@Test @MainActor func deleteRefusesActiveVM() throws {
    let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let record = VMRecord(name: "keep-running", cpuCount: 2, memorySize: 1 << 30, diskSize: 1 << 30)
    try writeBundle(record, at: root, includeDisk: true, includeVariableStore: true)
    let store = VMStore(root: root)
    let bundle = try store.load(named: "keep-running")
    try store.writeRuntime(VMRuntime(pid: 42, startedAt: Date()), for: bundle)
    let channel = try VMControlChannel(url: bundle.controlURL)
    defer { channel.stop() }

    #expect(throws: CLI.CLIError.self) {
        try CLI(store: store).run(arguments: ["delete", "keep-running", "--force"])
    }
    #expect(FileManager.default.fileExists(atPath: bundle.url.path))
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
