import SwiftUI
import UniformTypeIdentifiers

enum Severity: String, Codable, CaseIterable { case info = "INFO", success = "SUCCESS", warning = "WARNING", error = "ERROR" }

struct Event: Identifiable, Encodable {
    let id = UUID()
    let time = Date()
    let level: Severity
    let message: String
    var line: String { "\(time.ISO8601Format()) [\(level.rawValue)] \(message)" }
}

struct Report: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText, .json] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents, let value = String(data: data, encoding: .utf8)
        else { throw CocoaError(.fileReadCorruptFile) }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

struct Scan: Codable, Identifiable {
    let id: UUID
    let time: Date
    let device: String
    let firmware: String
    let build: String?
    let results: [Observation]
    let advisories: [String: Verdict]
}

@MainActor final class Session: ObservableObject {
    @Published var snapshot = Inspection()
    @Published private(set) var events: [Event] = []
    @Published private(set) var history: [Scan] = []
    @Published private(set) var current: [Observation] = []
    @Published private(set) var total = 0
    var running: Bool { total > 0 }
    private let historyKey = "completedScans.v2"
    private(set) var catalog: Catalog?
    private(set) var catalogError: String?

    init() {
        do {
            if let data = UserDefaults.standard.data(forKey: historyKey) {
                do { history = try JSONDecoder().decode([Scan].self, from: data) }
                catch { log(.warning, "Previous assessments could not be read.") }
            }
            guard let url = Bundle.main.url(forResource: "catalog", withExtension: "json")
            else { throw CocoaError(.fileNoSuchFile) }
            catalog = try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: url))
            log(.info, "Local catalog loaded.")
        } catch {
            catalogError = error.localizedDescription
            log(.error, "Catalog unavailable: \(error.localizedDescription)")
        }
    }

    func log(_ level: Severity, _ message: String) {
        events.append(Event(level: level, message: message))
        if events.count > 250 { events.removeFirst(events.count - 250) }
    }

    func refresh() {
        snapshot = Inspection()
        log(.info, "Device readings refreshed.")
    }

    func run(_ probes: [Probe]) async {
        guard !running, !probes.isEmpty else { return }
        total = probes.count
        current = []
        refresh()
        let device = snapshot
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        for probe in probes {
            let observation = await Task.detached(priority: .utility) { probe.run() }.value
            current.append(observation)
            let severity: Severity = observation.state == .accessible ? .success : (observation.state == .untested ? .info : .warning)
            log(severity, "\(probe.rawValue) · \(observation.state.rawValue) · \(observation.detail)")
        }
        let assessments = Dictionary(uniqueKeysWithValues: (catalog?.vulnerabilities ?? []).map {
            ($0.id, $0.assess(device: device.device, firmware: device.firmware, build: device.build, arch: device.arch))
        })
        let scan = Scan(id: UUID(), time: Date(), device: device.device, firmware: device.firmware,
                        build: device.build, results: current, advisories: assessments)
        history = Array(([scan] + history).prefix(5))
        do { UserDefaults.standard.set(try JSONEncoder().encode(history), forKey: historyKey) }
        catch { log(.error, "Assessment history could not be saved: " + error.localizedDescription) }
        total = 0
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func structuredReport(includeDevice: Bool) throws -> Report {
        struct Export: Encodable {
            let schema: Int
            let generated: Date
            let overview: [String: String]?
            let assessments: [Scan]
            let console: [Event]
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let overview = Dictionary(uniqueKeysWithValues: snapshot.fields.map { ($0.title, $0.value ?? "Unavailable") })
        let export = Export(schema: 1, generated: Date(), overview: includeDevice ? overview : nil, assessments: history, console: events)
        return Report(text: String(decoding: try encoder.encode(export), as: UTF8.self))
    }

    func report(includeDevice: Bool) -> Report {
        var lines = ["Project Amethyst 0.2", Date().ISO8601Format()]
        if includeDevice {
            lines += [snapshot.model, "Sampled " + snapshot.sampled.ISO8601Format()]
            lines += snapshot.fields.map { "\($0.title): \($0.value ?? "Unavailable")" }
        }
        lines += ["Console"] + events.map(\.line)
        return Report(text: lines.joined(separator: "\n") + "\n")
    }
}
