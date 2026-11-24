import SwiftUI
import UniformTypeIdentifiers

enum Severity: String { case info = "INFO", success = "SUCCESS", warning = "WARNING", error = "ERROR" }

struct Event: Identifiable {
    let id = UUID()
    let time = Date()
    let level: Severity
    let message: String
    var line: String { "\(time.ISO8601Format()) [\(level.rawValue)] \(message)" }
}

struct Report: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
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

final class Session: ObservableObject {
    @Published var snapshot = Inspection()
    @Published private(set) var events: [Event] = []
    @Published private(set) var diagnostics: [Event] = []
    private(set) var catalog: Catalog?
    private(set) var catalogError: String?

    init() {
        do {
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

    func diagnose() {
        refresh()
        diagnostics = []
        func record(_ level: Severity, _ message: String) {
            log(level, message)
            if let last = events.last { diagnostics.append(last) }
        }
        for field in snapshot.fields {
            record(field.value == nil || field.value == "Unavailable" ? .warning : .success,
                   "\(field.title): \(field.value ?? "Unavailable")")
        }
        // Read-only probes. Discard directory contents and retain only the outcome.
        for (label, path) in [("App home", NSHomeDirectory()), ("System data directory", "/private/var/mobile/Library")] {
            do {
                _ = try FileManager.default.contentsOfDirectory(atPath: path)
                record(.info, "\(label): directory listing permitted in this process.")
            } catch {
                let error = error as NSError
                record(.warning, "\(label): listing unavailable (\(error.domain) \(error.code)).")
            }
        }
        record(.info, "Protected app data currently \(UIApplication.shared.isProtectedDataAvailable ? "available" : "unavailable").")
    }

    func report(includeDevice: Bool) -> Report {
        var lines = ["Project Amethyst 0.1", Date().ISO8601Format()]
        if includeDevice {
            lines += [snapshot.model, "Sampled " + snapshot.sampled.ISO8601Format()]
            lines += snapshot.fields.map { "\($0.title): \($0.value ?? "Unavailable")" }
        }
        lines += ["Console"] + events.map(\.line)
        return Report(text: lines.joined(separator: "\n") + "\n")
    }
}
