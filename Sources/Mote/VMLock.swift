import Darwin
import Foundation

final class VMLock: @unchecked Sendable {
    enum LockError: LocalizedError {
        case unavailable(String)
        case system(vm: String, message: String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let name):
                return "The VM '\(name)' is already in use."
            case .system(let name, let message):
                return "Unable to lock VM '\(name)': \(message)."
            }
        }
    }

    private let descriptor: Int32

    init(bundle: VMBundle) throws {
        let descriptor = Darwin.open(bundle.lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else {
            throw LockError.system(
                vm: bundle.record.name,
                message: String(cString: strerror(errno))
            )
        }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            Darwin.close(descriptor)
            if code == EWOULDBLOCK {
                throw LockError.unavailable(bundle.record.name)
            }
            throw LockError.system(
                vm: bundle.record.name,
                message: String(cString: strerror(code))
            )
        }
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
