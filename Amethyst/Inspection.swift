import Foundation
import UIKit
import Darwin
import os

func systemString(_ key: String) -> String? {
    var size = 0
    guard sysctlbyname(key, nil, &size, nil, 0) == 0, size > 0, size < 65536 else { return nil }
    var bytes = [CChar](repeating: 0, count: size)
    guard sysctlbyname(key, &bytes, &size, nil, 0) == 0, bytes.contains(0) else { return nil }
    return String(validatingUTF8: bytes)
}

struct Reading: Identifiable {
    let title: String
    let value: String?
    var id: String { title }
    init(_ title: String, _ value: String?) { self.title = title; self.value = value }
}

struct Inspection {
    let device = systemString("hw.machine") ?? "Unavailable"
    let firmware = UIDevice.current.systemVersion
    let build = systemString("kern.osversion")
    let sampled = Date()
    let fields: [Reading]
    let model: String

    init() {
        let models = ["iPhone12,5": "iPhone 11 Pro Max", "iPhone12,3": "iPhone 11 Pro",
                      "iPhone12,1": "iPhone 11", "iPhone10,3": "iPhone X", "iPhone10,6": "iPhone X"]
        model = models[device] ?? UIDevice.current.model
        let chip = models[device].map { $0 == "iPhone X" ? "A11 Bionic" : "A13 Bionic" }
        #if arch(arm64)
        let architecture = "ARM64"
        #elseif arch(x86_64)
        let architecture = "x86_64"
        #else
        let architecture = "Other"
        #endif
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let disk = try? home.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityKey])
        let pressure = os_proc_available_memory()
        fields = [Reading("Hardware identifier", device), Reading("Chipset", chip),
                  Reading("Process architecture", architecture), Reading("iOS", firmware), Reading("Build", build),
                  Reading("Physical memory", Self.bytes(Int64(ProcessInfo.processInfo.physicalMemory))),
                  Reading("Available to app", pressure > 0 ? Self.bytes(Int64(pressure)) : nil),
                  Reading("Resident memory", Self.resident().map(Self.bytes)),
                  Reading("Volume capacity", disk?.volumeTotalCapacity.map { Self.bytes(Int64($0)) }),
                  Reading("Volume available", disk?.volumeAvailableCapacity.map { Self.bytes(Int64($0)) }),
                  Reading("Kernel version", systemString("kern.version"))]
    }

    static func bytes(_ amount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: amount, countStyle: .binary)
    }

    static func resident() -> Int64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout.size(ofValue: info) / MemoryLayout<integer_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: capacity) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.resident_size) : nil
    }
}
