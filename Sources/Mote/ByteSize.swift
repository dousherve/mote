import Foundation

struct ByteSize {
    enum ParseError: LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let value):
                return "Invalid size '\(value)'. Use a whole number followed by K, M, G, or T."
            }
        }
    }

    static func parse(_ value: String) throws -> UInt64 {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let suffix = normalized.last else { throw ParseError.invalid(value) }

        let multiplier: UInt64
        let digits: Substring
        switch suffix {
        case "K":
            multiplier = 1 << 10
            digits = normalized.dropLast()
        case "M":
            multiplier = 1 << 20
            digits = normalized.dropLast()
        case "G":
            multiplier = 1 << 30
            digits = normalized.dropLast()
        case "T":
            multiplier = 1 << 40
            digits = normalized.dropLast()
        default:
            multiplier = 1
            digits = Substring(normalized)
        }

        guard let count = UInt64(digits), count > 0,
              count <= UInt64.max / multiplier else {
            throw ParseError.invalid(value)
        }
        return count * multiplier
    }

    static func format(_ bytes: UInt64) -> String {
        let units: [(UInt64, String)] = [
            (1 << 40, "TiB"), (1 << 30, "GiB"), (1 << 20, "MiB"), (1 << 10, "KiB")
        ]
        for (unit, label) in units where bytes >= unit && bytes.isMultiple(of: unit) {
            return "\(bytes / unit) \(label)"
        }
        return "\(bytes) bytes"
    }
}
