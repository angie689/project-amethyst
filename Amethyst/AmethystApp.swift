import SwiftUI

let violet = Color(red: 0.74, green: 0.59, blue: 1)

@main
struct AmethystApp: App {
    @StateObject private var session = Session()

    @State private var arriving = true
    @State private var tab = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                NavigationView { Dashboard() }
                    .tabItem { Label("Overview", systemImage: "diamond") }.tag(0)
                NavigationView { Browser(projects: false) }
                    .tabItem { Label("Advisories", systemImage: "books.vertical") }.tag(1)
                NavigationView { Browser(projects: true) }
                    .tabItem { Label("Projects", systemImage: "square.stack.3d.up") }.tag(2)
                NavigationView { Diagnostics() }
                    .tabItem { Label("Diagnostics", systemImage: "waveform.path.ecg") }.tag(3)
                NavigationView { Console() }
                    .tabItem { Label("Console", systemImage: "terminal") }.tag(4)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: tab)
            .overlay { if arriving { Arrival().transition(.opacity) } }
            .task {
                if !reduceMotion { try? await Task.sleep(nanoseconds: 320_000_000) }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { arriving = false }
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
            Section("Process activity") { Monitor() }
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
                let assessment = entry.assess(device: session.snapshot.device, firmware: session.snapshot.firmware, build: session.snapshot.build, arch: session.snapshot.arch)
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
            Section {
                Button { Task { await session.run(Probe.allCases) } } label: { Label("Scan capabilities", systemImage: "waveform.path.ecg") }
                    .disabled(session.running)
                if session.running {
                    ProgressView(value: Double(session.current.count), total: Double(session.total))
                        .accessibilityLabel("Scan progress")
                }
                NavigationLink(destination: ImportView()) { Label("Analyze a file", systemImage: "doc.text.magnifyingglass") }
                NavigationLink(destination: Comparison()) { Label("Compare assessments", systemImage: "clock.arrow.circlepath") }
            }
            Section("Capabilities") {
                ForEach(Probe.allCases) { probe in
                    let observations = session.running ? session.current : session.history.first?.results ?? []
                    let observation = observations.first { $0.probe == probe }
                    NavigationLink {
                        List {
                            Text(observation?.state.rawValue ?? "Untested").foregroundColor(violet)
                            if let observation {
                                Text(observation.detail).textSelection(.enabled)
                                Text(observation.time.ISO8601Format())
                                if let code = observation.code { Text("\(observation.domain ?? "API") · \(code)") }
                            }
                            Button("Run this test") { Task { await session.run([probe]) } }.disabled(session.running)
                        }.navigationTitle(probe.rawValue)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(probe.rawValue)
                            Text(observation?.state.rawValue ?? "Untested").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
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
    @State private var level: Severity?
    @State private var query = ""
    @State private var json = false
    @State private var exporting = false
    @State private var document = Report(text: "")
    var body: some View {
        List {
            Menu {
                ForEach(Probe.allCases) { probe in
                    Button(probe.rawValue) { Task { await session.run([probe]) } }
                }
            } label: { Label("Run a test", systemImage: "play.circle") }.disabled(session.running)
            NavigationLink("Compare assessments", destination: Comparison())
            Picker("Severity", selection: $level) {
                Text("All").tag(nil as Severity?)
                ForEach(Severity.allCases, id: \.self) { Text($0.rawValue).tag(Optional($0)) }
            }
            Picker("Export format", selection: $json) {
                Text("Plain text").tag(false)
                Text("JSON").tag(true)
            }
            Button {
                do {
                    document = json ? try session.structuredReport(includeDevice: includeSnapshot) : session.report(includeDevice: includeSnapshot)
                    exporting = true
                } catch { session.log(.error, error.localizedDescription) }
            } label: { Label("Export report", systemImage: "square.and.arrow.up") }
            ForEach(session.events.reversed().filter { (level == nil || $0.level == level) && (query.isEmpty || $0.message.localizedCaseInsensitiveContains(query)) }) { EventRow(event: $0) }
        }.navigationTitle("Research console").searchable(text: $query)
        .fileExporter(isPresented: $exporting, document: document, contentType: json ? .json : .plainText, defaultFilename: "Amethyst-report") { result in
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
                Text("Version 0.2 · Pre-Alpha")
                Link("Source code", destination: URL(string: "https://github.com/angie689/project-amethyst")!)
            }
        }.navigationTitle("Settings")
    }
}
