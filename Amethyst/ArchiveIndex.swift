import Foundation

// Read the ZIP directory by offset so multi-gigabyte firmware images stay on disk.
private extension Data {
    func uint(_ offset: Int, _ width: Int) throws -> UInt64 {
        guard offset >= 0, offset <= count - width else { throw AnalysisFailure("Truncated archive field.") }
        return (0..<width).reduce(UInt64(0)) { $0 | UInt64(self[startIndex + offset + $1]) << (8 * $1) }
    }
}

enum ArchiveIndex {
    static func zip(_ file: FileHandle, length: UInt64) throws -> FileAnalysis {
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            guard offset <= length, count >= 0, UInt64(count) <= length - offset else { throw AnalysisFailure("ZIP offset exceeds file size.") }
            try file.seek(toOffset: offset)
            let data = try file.read(upToCount: count) ?? Data()
            guard data.count == count else { throw AnalysisFailure("Incomplete ZIP record.") }
            return data
        }
        let tailSize = Int(min(length, 65557))
        let tailOffset = length - UInt64(tailSize)
        let tail = try read(tailOffset, tailSize)
        guard let end = tail.range(of: Data([0x50,0x4b,5,6]), options: .backwards)?.lowerBound,
              try end + 22 + Int(tail.uint(end + 20, 2)) == tail.count else { throw AnalysisFailure("Missing ZIP directory end.") }
        var count = try tail.uint(end + 10, 2)
        var offset = try tail.uint(end + 16, 4)
        if offset == UInt32.max || count == UInt16.max {
            guard tailOffset + UInt64(end) >= 20 else { throw AnalysisFailure("Missing ZIP64 locator.") }
            let locator = try read(tailOffset + UInt64(end) - 20, 20)
            guard try locator.uint(0, 4) == 0x07064b50 else { throw AnalysisFailure("Invalid ZIP64 locator.") }
            let record = try read(locator.uint(8, 8), 56)
            guard try record.uint(0, 4) == 0x06064b50 else { throw AnalysisFailure("Invalid ZIP64 directory.") }
            count = try record.uint(32, 8)
            offset = try record.uint(48, 8)
        }
        var rows = ["Archive entries · \(count)"]
        var firmware = false
        for _ in 0..<min(count, 4096) {
            let header = try read(offset, 46)
            guard try header.uint(0, 4) == 0x02014b50 else { throw AnalysisFailure("Invalid ZIP directory entry.") }
            let nameSize = Int(try header.uint(28, 2))
            let name = String(decoding: try read(offset + 46, nameSize), as: UTF8.self)
            let extraSize = Int(try header.uint(30, 2))
            if ["Restore.plist", "BuildManifest.plist"].contains(name) {
                var local = try header.uint(42, 4)
                if local == UInt32.max {
                    let extra = try read(offset + 46 + UInt64(nameSize), extraSize)
                    var i = 0
                    while i + 4 <= extra.count {
                        let size = Int(try extra.uint(i + 2, 2))
                        if try extra.uint(i, 2) == 1 {
                            var field = i + 4
                            for slot in [24,20] where try header.uint(slot, 4) == UInt32.max { field += 8 }
                            guard field + 8 <= i + 4 + size else { throw AnalysisFailure("Incomplete ZIP64 offset.") }
                            local = try extra.uint(field, 8)
                            break
                        }
                        i += 4 + size
                    }
                }
                let packed = Int(try header.uint(20, 4))
                let size = Int(try header.uint(24, 4))
                if packed > 0, size > 0, packed <= Analyzer.limit, size <= Analyzer.limit {
                    let record = try read(local, 30)
                    guard try record.uint(0, 4) == 0x04034b50 else { throw AnalysisFailure("Invalid plist member.") }
                    let start = try local + 30 + record.uint(26, 2) + record.uint(28, 2)
                    let data = try read(start, packed)
                    let mode = try header.uint(10, 2)
                    var plain = Data()
                    if mode == 0 { plain = data }
                    if mode == 8 {
                        plain = Data(count: size)
                        let ok = plain.withUnsafeMutableBytes { dst in data.withUnsafeBytes { src in
                            am_inflate(src.bindMemory(to: UInt8.self).baseAddress, UInt32(packed),
                                       dst.bindMemory(to: UInt8.self).baseAddress, UInt32(size))
                        } }
                        if ok == 0 { throw AnalysisFailure("Invalid deflated firmware metadata.") }
                    }
                    if plain.count == size {
                        let checksum = plain.withUnsafeBytes { crc32(0, $0.bindMemory(to: UInt8.self).baseAddress, UInt32(size)) }
                        guard checksum == (try header.uint(16, 4)) else { throw AnalysisFailure("Firmware metadata checksum failed.") }
                        if let dict = try PropertyListSerialization.propertyList(from: plain, format: nil) as? [String: Any] {
                            let fields = Analyzer.firmwareRows(dict)
                            firmware = firmware || !fields.isEmpty
                            rows += fields
                        }
                    }
                }
            }
            if rows.count < 100 { rows.append(String(name.prefix(300))) }
            offset += UInt64(46 + nameSize + extraSize) + (try header.uint(32, 2))
        }
        if count > 4096 { rows.append("Partial directory · 4096 entries inspected") }
        return FileAnalysis(kind: firmware ? "IPSW metadata" : "ZIP inventory", rows: rows)
    }

    static func tarGzip(_ url: URL) throws -> FileAnalysis {
        guard let stream = gzopen(url.path, "rb") else { throw AnalysisFailure("Cannot open gzip stream.") }
        defer { gzclose(stream) }
        var rows = [String]()
        var consumed = 0
        let budget = 16 * 1024 * 1024
        var header = [UInt8](repeating: 0, count: 512)
        var scratch = [UInt8](repeating: 0, count: 32768)
        while consumed + 512 <= budget, rows.count < 200 {
            guard gzread(stream, &header, 512) == 512 else { throw AnalysisFailure("Incomplete tar header.") }
            consumed += 512
            if header.allSatisfy({ $0 == 0 }) { break }
            func field(_ range: Range<Int>) -> String {
                String(decoding: header[range].prefix(while: { $0 != 0 }), as: UTF8.self).trimmingCharacters(in: .whitespaces)
            }
            let sum = header.enumerated().reduce(0) { $0 + (148..<156 ~= $1.offset ? 32 : Int($1.element)) }
            guard Int(field(148..<156), radix: 8) == sum,
                  let size = Int(field(124..<136), radix: 8), size >= 0 else { throw AnalysisFailure("Invalid tar header or size.") }
            rows.append("\(field(0..<100)) · \(size) B")
            if size > budget - consumed { rows.append("Preview byte limit reached"); break }
            var remaining = (size + 511) / 512 * 512
            consumed += remaining
            while remaining > 0 {
                let amount = min(remaining, scratch.count)
                guard gzread(stream, &scratch, UInt32(amount)) == Int32(amount) else { throw AnalysisFailure("Incomplete tar member.") }
                remaining -= amount
            }
        }
        return FileAnalysis(kind: "Tar/gzip inventory", rows: ["Preview · up to 200 members or 16 MiB of archive data"] + rows)
    }
}
