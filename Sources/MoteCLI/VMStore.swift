import Foundation
import Virtualization

struct VMStore {
    enum StoreError: LocalizedError {
        case invalidName(String)
        case alreadyExists(String)
        case corruptBundle(String)

        var errorDescription: String? {
            switch self {
            case .invalidName(let name):
                return "Invalid VM name '\(name)'. Use letters, numbers, dots, underscores, or hyphens."
            case .alreadyExists(let name):
                return "A VM named '\(name)' already exists."
            case .corruptBundle(let name):
                return "The VM bundle '\(name)' has an unreadable manifest."
            }
        }
    }

    let root: URL
    private let fileManager: FileManager

    init(root: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        if let root {
            self.root = root
        } else if let override = ProcessInfo.processInfo.environment["MOTE_HOME"], !override.isEmpty {
            self.root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            self.root = fileManager.homeDirectoryForCurrentUser
                .appending(path: "Library/Application Support/Mote/Virtual Machines", directoryHint: .isDirectory)
        }
    }

    func list() throws -> [VMRecord] {
        guard fileManager.fileExists(atPath: root.path) else { return [] }
        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return try entries
            .filter { $0.pathExtension == "motevm" }
            .map { bundle in
                let manifest = bundle.appending(path: VMRecord.manifestName)
                guard let data = try? Data(contentsOf: manifest),
                      let record = try? Self.decoder.decode(VMRecord.self, from: data) else {
                    throw StoreError.corruptBundle(bundle.lastPathComponent)
                }
                return record
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func create(_ record: VMRecord) throws -> URL {
        guard Self.isValidName(record.name) else { throw StoreError.invalidName(record.name) }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let bundle = root.appending(path: "\(record.name).motevm", directoryHint: .isDirectory)
        guard !fileManager.fileExists(atPath: bundle.path) else {
            throw StoreError.alreadyExists(record.name)
        }

        do {
            try fileManager.createDirectory(at: bundle, withIntermediateDirectories: false)

            let disk = bundle.appending(path: VMRecord.diskName)
            guard fileManager.createFile(atPath: disk.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let handle = try FileHandle(forWritingTo: disk)
            try handle.truncate(atOffset: record.diskSize)
            try handle.close()

            let variables = bundle.appending(path: VMRecord.variableStoreName)
            _ = try VZEFIVariableStore(creatingVariableStoreAt: variables)

            let data = try Self.encoder.encode(record)
            try data.write(to: bundle.appending(path: VMRecord.manifestName), options: .atomic)
            return bundle
        } catch {
            try? fileManager.removeItem(at: bundle)
            throw error
        }
    }

    static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64, name != ".", name != ".." else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return name.unicodeScalars.allSatisfy(allowed.contains)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
