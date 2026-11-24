import SwiftUI
import UniformTypeIdentifiers

struct ImportView: View {
    @State private var picking = false
    @State private var busy = false
    @State private var report: FileAnalysis?
    @State private var name = ""
    @State private var query = ""
    @State private var problem: String?
    var body: some View {
        List {
            Button { picking = true } label: { Label("Choose diagnostic file", systemImage: "doc.badge.plus") }
                .disabled(busy)
            if busy { ProgressView("Reading file…") }
            if let problem { Text(problem).foregroundColor(.orange) }
            if let report {
                Section(report.kind) {
                    Text(name).font(.headline)
                    let visible = report.rows.enumerated().filter { query.isEmpty || $0.element.localizedCaseInsensitiveContains(query) }
                    if visible.isEmpty { Text("No matching lines.") }
                    ForEach(visible, id: \.offset) { item in
                        Text(item.element).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                    }
                }
            }
        }.navigationTitle("File analyzer").searchable(text: $query)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item]) { result in
            do {
                let url = try result.get()
                busy = true; problem = nil; report = nil; query = ""; name = url.lastPathComponent
                Task {
                    do {
                        report = try await Task.detached(priority: .utility) {
                            let scoped = url.startAccessingSecurityScopedResource()
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            return try Analyzer.inspect(url)
                        }.value
                    } catch { problem = error.localizedDescription }
                    busy = false
                }
            } catch { if (error as NSError).code != NSUserCancelledError { problem = error.localizedDescription } }
        }
    }
}
