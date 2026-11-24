import Foundation

func expect(_ condition: Bool, _ message: String) {
    guard condition else { fatalError(message) }
}
let data = try Data(contentsOf: URL(fileURLWithPath: "Amethyst/catalog.json"))
let catalog = try JSONDecoder().decode(Catalog.self, from: data)
let entries = catalog.projects + catalog.vulnerabilities
expect(Set(entries.map(\.id)).count == entries.count, "Duplicate catalog ID")
for entry in entries {
    expect(!entry.rules.isEmpty && !entry.references.isEmpty, entry.id)
    expect(entry.references.allSatisfy { $0.scheme == "https" && $0.host != nil }, entry.id)
    for rule in entry.rules {
        for bound in [rule.minimum, rule.maximum].compactMap({ $0 }) {
            expect(Version(bound) != nil, bound)
        }
    }
}
let phone = "iPhone12,5"
let historical = catalog.projects.first { $0.id == "Dopamine 2.1.7" }!
func verdict(_ entry: Entry, _ os: String, _ hw: String = phone, _ build: String? = "20G81") -> Verdict {
    entry.assess(device: hw, firmware: os, build: build)
}
expect(verdict(historical, "16.5.1") == .supported, "Upper inclusive")
expect(verdict(historical, "16.5.2") == .unsupported, "Past upper bound")
expect(verdict(historical, "27.0.1") == .unsupported, "Historical release")
expect(verdict(historical, "16.5", "unknown") == .unknown, "Unmapped model")
expect(verdict(historical, "16.5", phone, nil) == .unknown, "Missing build")
expect(verdict(historical, "16.5", phone, "20F5000a") == .unknown, "Beta build")
expect(verdict(historical, "16..5") == .unknown, "Malformed firmware")
for cve in catalog.vulnerabilities {
    expect(verdict(cve, "16.6") == .affected, "Before fix")
    expect(verdict(cve, "16.6.1") == .patched, "Patched")
    expect(verdict(cve, "27.0.1") == .unknown, "Unassessed branch")
}
print("Catalog and assessment checks passed.")
