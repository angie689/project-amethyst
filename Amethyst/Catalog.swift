import Foundation

struct Version: Comparable {
    let parts: [Int]

    init?(_ value: String) {
        let fields = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(fields.count) else { return nil }
        let numbers = fields.compactMap { field -> Int? in
            guard !field.isEmpty, field.allSatisfy({ $0 >= "0" && $0 <= "9" }) else { return nil }
            return Int(field)
        }
        guard numbers.count == fields.count else { return nil }
        parts = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.parts.lexicographicallyPrecedes(rhs.parts)
    }
}

enum Verdict: String, Codable {
    case supported = "Supported", experimental = "Experimental", unsupported = "Unsupported"
    case unknown = "Unknown", affected = "Potentially affected", patched = "Documented fix"
}

struct Rule: Decodable {
    let devices: [String]
    let minimum: String?
    let maximum: String?
    let verdict: Verdict

    func matches(_ device: String, _ version: Version) -> Bool {
        guard devices.contains(device) else { return false }
        if let minimum {
            guard let lower = Version(minimum), version >= lower else { return false }
        }
        if let maximum {
            guard let upper = Version(maximum), version <= upper else { return false }
        }
        return true
    }
}

struct Entry: Identifiable, Decodable {
    let id: String
    let category: String
    let summary: String
    let scope: String
    let references: [URL]
    let rules: [Rule]

    func assess(device: String, firmware: String, build: String?) -> Verdict {
        guard let version = Version(firmware), let build,
              build.range(of: #"^[0-9]+[A-Z][0-9]+$"#, options: .regularExpression) != nil else { return .unknown }
        return rules.first { $0.matches(device, version) }?.verdict ?? .unknown
    }
}

struct Catalog: Decodable {
    let vulnerabilities: [Entry]
    let projects: [Entry]
}
