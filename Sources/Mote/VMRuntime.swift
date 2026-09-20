import Foundation

struct VMRuntime: Codable, Equatable, Sendable {
    let pid: Int32
    let startedAt: Date
}
