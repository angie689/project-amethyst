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
    entry.assess(device: hw, firmware: os, build: build, arch: "ARM64")
}
expect(verdict(historical, "16.5.1") == .supported, "Upper inclusive")
expect(verdict(historical, "16.5.2") == .unsupported, "Past upper bound")
expect(verdict(historical, "27.0.1") == .unsupported, "Historical release")
expect(verdict(historical, "16.5", "unknown") == .unknown, "Unmapped model")
expect(verdict(historical, "16.5", phone, nil) == .unknown, "Missing build")
expect(verdict(historical, "16.5", phone, "20F5000a") == .unknown, "Beta build")
expect(verdict(historical, "16..5") == .unknown, "Malformed firmware")
for cve in catalog.vulnerabilities {
    expect(verdict(cve, "16.6", phone, "20G75") == .affected, "Before fix")
    expect(verdict(cve, "16.6") == .unknown, "Inconsistent build")
    expect(cve.assess(device: phone, firmware: "16.6", build: "20G75", arch: "x86_64") == .unknown, "Wrong architecture")
    expect(verdict(cve, "16.6.1") == .patched, "Patched")
    expect(verdict(cve, "27.0.1") == .unknown, "Unassessed branch")
}
print("Catalog and assessment checks passed.")
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
for (name, kind, field) in [
    ("crash", "Application crash", "procName · Demo"), ("panic", "Kernel panic", "panicString · Sample panic"),
    ("jetsam", "Jetsam event", "Processes recorded · 1"), ("analytics", "Analytics report", "message · Sample event"),
    ("sysdiagnose.tar.gz", "Tar/gzip inventory", "logs/summary.txt · 5 B"), ("sample.ipsw", "IPSW metadata", "ProductBuildVersion · 20G75")
] {
    let report = try Analyzer.inspect(folder.appendingPathComponent(name))
    expect(report.kind == kind && report.rows.contains(field), name)
}
expect((try? Analyzer.inspect(folder.appendingPathComponent("broken.zip"))) == nil, "Broken archive")
for probe in [Probe.kernel, .memory, .threads, .network, .disk, .limits, .images] {
    let reading = probe.run()
    expect(reading.state == .accessible && !reading.detail.isEmpty, "Runner probe: " + probe.rawValue)
}
print("File import fixtures and native host probes passed.")
