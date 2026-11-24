import Darwin
import Foundation
import MachO
import Metal

enum Access: String, Codable {
    case accessible = "Accessible", restricted = "Restricted", denied = "Denied"
    case unavailable = "Unavailable", untested = "Untested"
}

struct Observation: Codable, Identifiable {
    var id: Probe { probe }
    let probe: Probe
    let time: Date
    let state: Access
    let detail: String
    let code: Int32?
    let domain: String?
}

enum Probe: String, CaseIterable, Codable, Identifiable {
    case kernel = "Kernel release", hardware = "Hardware model", memory = "Task virtual memory"
    case threads = "Task threads", network = "Network interfaces", images = "Loaded images"
    case disk = "Container volume", limits = "Open file limit", gpu = "Metal device"
    case sandbox = "System directory access", io = "IOKit registry"
    var id: Self { self }

    func run() -> Observation {
        func result(_ state: Access, _ message: String, _ code: Int32? = nil, _ domain: String? = nil) -> Observation {
            Observation(probe: self, time: Date(), state: state, detail: message, code: code, domain: domain)
        }
        func posix(_ code: Int32) -> Observation {
            let state: Access = code == EACCES ? .denied : (code == EPERM ? .restricted : .unavailable)
            return result(state, String(cString: strerror(code)), code, "POSIX")
        }
        func mach(_ code: Int32) -> Observation {
            result(code == KERN_PROTECTION_FAILURE ? .denied : .unavailable,
                   String(cString: mach_error_string(code)), code, "Mach")
        }
        switch self {
        case .kernel, .hardware:
            let key = self == .kernel ? "kern.osrelease" : "hw.machine"
            var buffer = [CChar](repeating: 0, count: 256)
            var size = buffer.count
            guard sysctlbyname(key, &buffer, &size, nil, 0) == 0 else { return posix(errno) }
            return result(.accessible, "\(key) = " + String(cString: buffer), 0, "POSIX")
        case .memory:
            var resident: UInt64 = 0, virtualSize: UInt64 = 0, footprint: UInt64 = 0
            let code = am_task_memory(&resident, &virtualSize, &footprint)
            guard code == 0 else { return mach(code) }
            return result(.accessible, "Resident \(resident) B · Footprint \(footprint) B · Virtual \(virtualSize) B", code, "Mach")
        case .threads:
            var count: UInt32 = 0
            let code = am_thread_count(&count)
            return code == 0 ? result(.accessible, "\(count) threads in this task", code, "Mach") : mach(code)
        case .network:
            var start: UnsafeMutablePointer<ifaddrs>?
            guard getifaddrs(&start) == 0 else { return posix(errno) }
            defer { if let start { freeifaddrs(start) } }
            var names = Set<String>()
            var node = start
            while let entry = node?.pointee {
                names.insert(String(cString: entry.ifa_name))
                node = entry.ifa_next
            }
            return result(.accessible, "\(names.count) interfaces: " + names.sorted().joined(separator: ", "), 0, "POSIX")
        case .images:
            let count = _dyld_image_count()
            let names = (0..<min(count, 64)).compactMap { index in
                _dyld_get_image_name(index).map { URL(fileURLWithPath: String(cString: $0)).lastPathComponent }
            }
            return result(.accessible, "\(count) images · first \(names.count) names\n" + names.joined(separator: "\n"))
        case .disk:
            var total: UInt64 = 0, available: UInt64 = 0
            let code = am_volume(NSHomeDirectory(), &total, &available)
            return code == 0 ? result(.accessible, "\(available) B available of \(total) B", code, "POSIX") : posix(code)
        case .limits:
            var limit = rlimit()
            guard getrlimit(RLIMIT_NOFILE, &limit) == 0 else { return posix(errno) }
            return result(.accessible, "File descriptors · soft \(limit.rlim_cur) · hard \(limit.rlim_max)", 0, "POSIX")
        case .gpu:
            guard let gpu = MTLCreateSystemDefaultDevice() else { return result(.unavailable, "Metal returned no default device.") }
            return result(.accessible, "\(gpu.name) · max buffer \(gpu.maxBufferLength) B · Apple GPU family 6: \(gpu.supportsFamily(.apple6))")
        case .sandbox:
            guard let directory = opendir("/private/var/mobile/Library") else { return posix(errno) }
            closedir(directory)
            return result(.accessible, "Opened the system Library directory read-only.", 0, "POSIX")
        case .io:
            return result(.untested, "The public iPhone SDK does not provide a general IOKit registry inspection interface.")
        }
    }
}
