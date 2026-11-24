import SwiftUI
import Darwin

struct Monitor: View {
    @Environment(\.scenePhase) var phase
    @State private var memory: [Double] = []
    @State private var cpu: [Double] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            trace("Resident memory", values: memory, unit: "MiB", color: violet)
            trace("CPU · one core = 100%", values: cpu, unit: "%", color: .teal)
        }
        .padding(.vertical, 6)
        .task(id: phase) {
            guard phase == .active else { return }
            var last: (wall: Double, cpu: Double)?
            memory = []
            cpu = []
            while !Task.isCancelled {
                if let bytes = Inspection.resident() { memory = Array((memory + [Double(bytes) / 1048576]).suffix(30)) }
                else { memory = [] }
                var usage = rusage()
                if getrusage(RUSAGE_SELF, &usage) == 0 {
                    func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1e6 }
                    let now = ProcessInfo.processInfo.systemUptime
                    let used = seconds(usage.ru_utime) + seconds(usage.ru_stime)
                    if let last, now > last.wall {
                        cpu = Array((cpu + [max(0, (used - last.cpu) * 100 / (now - last.wall))]).suffix(30))
                    }
                    last = (now, used)
                } else { cpu = []; last = nil }
                do { try await Task.sleep(nanoseconds: 2_000_000_000) } catch { return }
            }
        }
    }

    private func trace(_ title: String, values: [Double], unit: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption)
                Spacer()
                Text(values.last.map { String(format: "%.1f %@", $0, unit) } ?? "—").monospacedDigit()
            }
            Canvas { context, size in
                var path = Path()
                let peak = max(values.max() ?? 1, 1)
                for (i, value) in values.enumerated() {
                    let point = CGPoint(x: size.width * CGFloat(i) / 29, y: (size.height - 2) * (1 - value / peak) + 1)
                    if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                context.stroke(path, with: .color(color), lineWidth: 2)
            }.frame(height: 28).accessibilityHidden(true)
        }
    }
}

struct Arrival: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expanded = false
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                Image(systemName: "diamond.fill").font(.largeTitle).foregroundColor(violet)
                    .shadow(color: violet.opacity(0.45), radius: 8)
                    .scaleEffect(expanded || reduceMotion ? 1 : 0.72)
                Text("Amethyst").font(.title2.weight(.semibold))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
        .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) { expanded = true } }
    }
}
