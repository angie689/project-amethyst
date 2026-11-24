import SwiftUI

struct Comparison: View {
    @EnvironmentObject var session: Session
    @State private var selected: UUID?
    var body: some View {
        List {
            if let latest = session.history.first, let fallback = session.history.dropFirst().first {
                let previous = session.history.dropFirst().first { $0.id == selected } ?? fallback
                Section("Latest assessment") {
                    Text(latest.time.ISO8601Format())
                    Text("\(latest.device) · iOS \(latest.firmware) (\(latest.build ?? "unknown"))")
                }
                Picker("Compare with", selection: Binding(get: { previous.id }, set: { selected = $0 })) {
                    ForEach(Array(session.history.dropFirst())) { scan in
                        Text(scan.time.ISO8601Format()).tag(scan.id)
                    }
                }
                Section("Capability changes") {
                    ForEach(Probe.allCases) { probe in
                        let before = previous.results.first { $0.probe == probe }
                        let after = latest.results.first { $0.probe == probe }
                        if before != nil || after != nil {
                            DisclosureGroup {
                                sample("Previous", before)
                                sample("Latest", after)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(probe.rawValue)
                                    Text(change(before, after)).foregroundColor(.secondary).font(.caption)
                                }
                            }
                        }
                    }
                }
                Section("Advisory assessments") {
                    ForEach(Set(previous.advisories.keys).union(latest.advisories.keys).sorted(), id: \.self) { id in
                        Text("\(id)\n\(previous.advisories[id]?.rawValue ?? "Unassessed") → \(latest.advisories[id]?.rawValue ?? "Unassessed")")
                    }
                }
            } else { Text("Run two assessments to compare their readings. The latest five are saved on this device.") }
        }.navigationTitle("Compare")
    }

    private func change(_ before: Observation?, _ after: Observation?) -> String {
        guard let before, let after else { return before == nil ? "Only in latest run" : "Only in previous run" }
        if before.state != after.state { return before.state.rawValue + " → " + after.state.rawValue }
        return before.detail == after.detail && before.code == after.code ? "Unchanged" : "Reading changed"
    }

    private func sample(_ label: String, _ observation: Observation?) -> some View {
        VStack(alignment: .leading) {
            Text("\(label) · \(observation?.state.rawValue ?? "Untested")").font(.headline)
            if let observation { Text(observation.detail).font(.caption) }
        }
    }
}
