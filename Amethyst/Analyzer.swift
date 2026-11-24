import Foundation

struct AnalysisFailure: LocalizedError {
    var errorDescription: String? { reason }
    let reason: String
    init(_ reason: String) { self.reason = reason }
}

struct FileAnalysis {
    let kind: String
    let rows: [String]
}

enum Analyzer {
    static let limit = 4 * 1024 * 1024

    static func inspect(_ url: URL) throws -> FileAnalysis {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let length = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let prefix = try handle.read(upToCount: 4) ?? Data()
        if prefix.starts(with: [0x50, 0x4b, 3, 4]) {
            return try ArchiveIndex.zip(handle, length: length)
        }
        if prefix.starts(with: [0x1f, 0x8b]) { return try ArchiveIndex.tarGzip(url) }
        try handle.seek(toOffset: 0)
        let data = try handle.read(upToCount: limit) ?? Data()
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           plist["ProductBuildVersion"] != nil {
            return FileAnalysis(kind: "Firmware metadata", rows: firmwareRows(plist))
        }
        guard !data.isEmpty, !data.prefix(512).contains(0) else { throw AnalysisFailure("Unsupported or empty diagnostic file.") }
        let text = String(decoding: data, as: UTF8.self)
        var rows = [String]()
        var kind = "Diagnostic text"
        let lines = text.split(separator: "\n", maxSplits: 2000)
        func collect(_ value: [String: Any]) {
            switch value["bug_type"] as? String {
            case "210": kind = "Kernel panic"
            case "298": kind = "Jetsam event"
            case "309": kind = "Application crash"
            case "211": kind = "Analytics report"
            default: break
            }
            for key in ["bug_type", "timestamp", "app_name", "procName", "name", "os_version", "osVersion",
                        "build", "modelCode", "panicString", "exception", "termination", "largestProcess", "memoryStatus", "message"] {
                if let item = value[key] {
                    rows.append("\(key) · " + display(item))
                }
            }
            if let processes = value["processes"] as? [[String: Any]] {
                rows.append("Processes recorded · \(processes.count)")
                for process in processes.prefix(50) {
                    if let name = process["name"] as? String {
                        rows.append("\(name) · pages \(process["rpages"].map(display) ?? "unknown") · reason \(process["reason"].map(display) ?? "unspecified")")
                    }
                }
            }
        }
        func parse(_ data: Data) -> Bool {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
            collect(object)
            return true
        }
        if !parse(data) {
            if let first = lines.first { _ = parse(Data(first.utf8)) }
            if let split = text.firstIndex(of: "\n"), !parse(Data(text[text.index(after: split)...].utf8)) {
                for line in lines.dropFirst().prefix(128) where line.utf8.count < 65536 {
                    if rows.count >= 200 { break }
                    _ = parse(Data(line.utf8))
                }
            }
        }
        for line in lines.prefix(150) where rows.count < 250 {
            let preview = String(line.prefix(400))
            if preview.hasPrefix("PanicString:") || preview.hasPrefix("panic(cpu") { kind = "Kernel panic" }
            if preview.hasPrefix("Exception Type:") { kind = "Application crash" }
            rows.append(preview)
        }
        if length > UInt64(limit) { rows.insert("Partial preview · first 4 MiB", at: 0) }
        return FileAnalysis(kind: kind, rows: rows)
    }

    static func display(_ item: Any) -> String {
        if let dict = item as? [String: Any] {
            return dict.keys.sorted().prefix(12).compactMap { key in
                guard let value = dict[key], value is String || value is NSNumber else { return nil }
                return "\(key)=\(String(describing: value).prefix(180))"
            }.joined(separator: ", ")
        }
        if let list = item as? [Any] {
            return list.prefix(24).compactMap { ($0 as? String).map { String($0.prefix(120)) } }.joined(separator: ", ")
        }
        return String(String(describing: item).prefix(1200))
    }

    static func firmwareRows(_ dict: [String: Any]) -> [String] {
        ["ProductVersion", "ProductBuildVersion", "ProductType", "SupportedProductTypes", "BuildIdentities"].compactMap { key in
            guard let value = dict[key] else { return nil }
            if key == "BuildIdentities", let items = value as? [Any] { return "Build identities · \(items.count)" }
            return "\(key) · " + display(value)
        }
    }
}
