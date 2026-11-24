import SwiftUI

private let violet = Color(red: 0.74, green: 0.59, blue: 1)

@main
struct AmethystApp: App {
    @StateObject private var session = Session()

    var body: some Scene {
        WindowGroup {
            TabView {
                NavigationView { Dashboard() }
                    .tabItem { Label("Overview", systemImage: "diamond") }
                NavigationView { Browser(projects: false) }
                    .tabItem { Label("Advisories", systemImage: "books.vertical") }
                NavigationView { Browser(projects: true) }
                    .tabItem { Label("Projects", systemImage: "square.stack.3d.up") }
                NavigationView { Diagnostics() }
                    .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }
                NavigationView { Console() }
                    .tabItem { Label("Console", systemImage: "terminal") }
            }
            .navigationViewStyle(.stack).environmentObject(session)
            .preferredColorScheme(.dark).tint(violet)
        }
    }
}

private struct Dashboard: View {
    @EnvironmentObject var session: Session
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "iphone").font(.largeTitle).foregroundColor(violet)
                    Text(session.snapshot.model).font(.title2.bold())
                    Text("iOS " + session.snapshot.firmware).font(.system(.subheadline, design: .monospaced))
                }.padding(.vertical, 10)
            }.listRowBackground(Color(red: 0.15, green: 0.10, blue: 0.23))
            Section("Device inspector") {
                ForEach(session.snapshot.fields) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.title).font(.caption).foregroundColor(.secondary)
                        Text(row.value ?? "Unavailable").textSelection(.enabled)
                    }
                }
            }
            Button("Refresh readings") { session.refresh() }
        }.navigationTitle("Amethyst")
        .toolbar { NavigationLink(destination: Settings()) { Label("Settings", systemImage: "gearshape") } }
    }
}

private struct Browser: View {
    @EnvironmentObject var session: Session
    let projects: Bool
    @State private var query = ""
    var body: some View {
        let entries = projects ? session.catalog?.projects : session.catalog?.vulnerabilities
        let visible = (entries ?? []).filter { query.isEmpty || ($0.id + " " + $0.category).localizedCaseInsensitiveContains(query) }
        List {
            if let error = session.catalogError { Text("Catalog unavailable: " + error) }
            else if visible.isEmpty { Text("No matching entries.") }
            ForEach(visible) { entry in
                let assessment = entry.assess(device: session.snapshot.device, firmware: session.snapshot.firmware, build: session.snapshot.build)
                NavigationLink {
                    List {
                        Section("Assessment for this device") {
                            Text(assessment.rawValue).foregroundColor(violet)
                            Text(entry.scope)
                        }
                        Section(entry.category) { Text(entry.summary) }
                        Section("References") {
                            ForEach(entry.references, id: \.self) { url in
                                Link(url.host ?? url.absoluteString, destination: url)
                            }
                        }
                    }.navigationTitle(entry.id)
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.category).font(.caption).foregroundColor(.secondary)
                        Text(entry.id).font(.headline)
                        Text(assessment.rawValue).font(.subheadline).foregroundColor(violet)
                    }.padding(.vertical, 4)
                }
            }
        }.navigationTitle(projects ? "Compatibility" : "Advisories").searchable(text: $query)
    }
}

private struct EventRow: View {
    let event: Event
    var color: Color {
        switch event.level {
        case .info: return violet
        case .warning: return .orange
        case .error: return .red
        case .success: return .green
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(event.level.rawValue).foregroundColor(color)
                Text(event.time, style: .time).foregroundColor(.secondary)
            }.font(.system(.caption, design: .monospaced))
            Text(event.message).textSelection(.enabled)
        }
    }
}

private struct Diagnostics: View {
    @EnvironmentObject var session: Session
    var body: some View {
        List {
            Button { session.diagnose() } label: { Label("Run diagnostics", systemImage: "play.circle") }
            if !session.diagnostics.isEmpty {
                Section("Latest run") { ForEach(session.diagnostics) { EventRow(event: $0) } }
            }
            Section("Visibility") {
                Text("Readings describe the current app process. System-wide free RAM, kernel memory contents and other apps’ entitlements are unavailable through these APIs. A container host can change the results.")
            }
        }.navigationTitle("Diagnostics")
    }
}

private struct Console: View {
    @EnvironmentObject var session: Session
    @AppStorage("includeSnapshot") private var includeSnapshot = true
    @State private var exporting = false
    @State private var document = Report(text: "")
    var body: some View {
        List {
            Button {
                document = session.report(includeDevice: includeSnapshot)
                exporting = true
            } label: { Label("Export text report", systemImage: "square.and.arrow.up") }
            ForEach(session.events.reversed()) { EventRow(event: $0) }
        }.navigationTitle("Research console")
        .fileExporter(isPresented: $exporting, document: document, contentType: .plainText, defaultFilename: "Amethyst-report") { result in
            switch result {
            case .success: session.log(.success, "Report exported.")
            case .failure(let error): session.log(.error, "Export: " + error.localizedDescription)
            }
        }
    }
}

private struct Settings: View {
    @AppStorage("includeSnapshot") private var includeSnapshot = true
    var body: some View {
        Form {
            Section {
                Toggle("Include device overview", isOn: $includeSnapshot)
            } header: { Text("Report export") } footer: {
                Text("Console messages include readings from each diagnostic run. The latest 250 messages stay in memory until the app closes.")
            }
            Section("Project Amethyst") {
                Text("Version 0.1 · Pre-Alpha")
                Link("Source code", destination: URL(string: "https://github.com/angie689/project-amethyst")!)
            }
        }.navigationTitle("Settings")
    }
}
