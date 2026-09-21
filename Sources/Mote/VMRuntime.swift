import Foundation

struct VMRuntime: Codable, Equatable, Sendable {
    let pid: Int32
    let startedAt: Date
}

enum VMRuntimeStatus: Sendable {
    case stopped
    case running(VMRuntime)
    case stale(VMRuntime)
    case invalid

    var name: String {
        switch self {
        case .stopped: "stopped"
        case .running: "running"
        case .stale: "stale"
        case .invalid: "invalid"
        }
    }

    var runtime: VMRuntime? {
        switch self {
        case .running(let runtime), .stale(let runtime): runtime
        case .stopped, .invalid: nil
        }
    }
}
