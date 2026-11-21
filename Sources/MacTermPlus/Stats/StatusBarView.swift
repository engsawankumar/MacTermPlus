import SwiftUI

/// Strip of server info under an SSH tab.
struct ServerStatusBar: View {
    @ObservedObject var stats: ServerStats
    @ObservedObject var settings = AppSettings.shared

    private func on(_ item: StatusItem) -> Bool { settings.statusItems.contains(item) }

    var body: some View {
        HStack(spacing: 0) {
            if !stats.hasData {
                Segment(icon: "hourglass", color: .secondary) { Text("Collecting server info…") }
            } else {
                if on(.host), !stats.host.isEmpty {
                    Segment(icon: "server.rack", color: .teal) { Text(stats.host) }
                }
                if on(.os), !stats.os.isEmpty {
                    let distro = Distro.named(stats.osID)
                    HStack(spacing: 5) {
                        DistroBadge(osID: stats.osID.isEmpty ? "linux" : stats.osID, size: 16)
                        Text(stats.os).lineLimit(1)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: distro?.colors.0 ?? "F5C518").opacity(0.14), in: RoundedRectangle(cornerRadius: 5))
                    .padding(.horizontal, 2)
                }
                if on(.cpu), let cpu = stats.cpuPercent {
                    Segment(icon: "cpu", color: cpuColor(cpu)) {
                        HStack(spacing: 6) {
                            Text(String(format: "%.0f%%", cpu)).monospacedDigit().frame(minWidth: 30, alignment: .trailing)
                            Sparkline(values: stats.cpuHistory, color: cpuColor(cpu)).frame(width: 60, height: 14)
                        }
                    }
                }
                if on(.memory), let used = stats.memUsed, let total = stats.memTotal, total > 0 {
                    Segment(icon: "memorychip", color: .green) {
                        HStack(spacing: 6) {
                            Text("\(ServerStats.bytes(used)) / \(ServerStats.bytes(total))").monospacedDigit()
                            UsageBar(fraction: Double(used) / Double(total)).frame(width: 36, height: 6)
                        }
                    }
                }
                if on(.network), let rx = stats.rxRate, let tx = stats.txRate {
                    Segment(icon: "arrow.up.arrow.down", color: .blue) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down").foregroundStyle(.green)
                            Text(ServerStats.rate(rx)).monospacedDigit()
                            Image(systemName: "arrow.up").foregroundStyle(.orange)
                            Text(ServerStats.rate(tx)).monospacedDigit()
                        }
                    }
                }
                if on(.user), !stats.user.isEmpty {
                    Segment(icon: stats.user == "root" ? "person.badge.key.fill" : "person.fill",
                            color: stats.user == "root" ? .red : .purple) { Text(stats.user) }
                }
                if on(.disk), let used = stats.diskUsed, let total = stats.diskTotal, total > 0 {
                    let pct = Double(used) / Double(total) * 100
                    Segment(icon: "internaldrive", color: pct > 90 ? .red : (pct > 75 ? .orange : .indigo)) {
                        Text(String(format: "/: %.0f%%", pct))
                            .monospacedDigit()
                            .foregroundStyle(pct > 90 ? .red : .primary)
                            .help("\(ServerStats.bytes(used)) used of \(ServerStats.bytes(total))")
                    }
                }
                if on(.diskTotal), let total = stats.diskTotal, total > 0 {
                    Segment(icon: "externaldrive.fill", color: .teal) {
                        Text("Total \(ServerStats.bytes(total))").monospacedDigit()
                    }
                }
                if on(.diskFree), let free = stats.diskFree, let total = stats.diskTotal, total > 0 {
                    let freePct = Double(free) / Double(total) * 100
                    Segment(icon: "externaldrive.badge.checkmark", color: freePct < 10 ? .red : .green) {
                        Text("Free \(ServerStats.bytes(free))")
                            .monospacedDigit()
                            .foregroundStyle(freePct < 10 ? .red : .primary)
                            .help(String(format: "%.0f%% free", freePct))
                    }
                }
                if on(.uptime), let up = stats.uptime {
                    Segment(icon: "clock", color: .mint) { Text("up \(ServerStats.duration(up))") }
                }
                if on(.load), !stats.load.isEmpty {
                    Segment(icon: "gauge.with.dots.needle.33percent", color: .pink) { Text(stats.load).monospacedDigit() }
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(.bar)
    }

    private var osIcon: String {
        let o = stats.os.lowercased()
        if o.contains("mac") || o.contains("darwin") { return "apple.logo" }
        if o.contains("windows") { return "pc" }
        return "shippingbox.fill"
    }

    private func cpuColor(_ v: Double) -> Color {
        v > 85 ? .red : (v > 60 ? .orange : .green)
    }
}

private struct Segment<Content: View>: View {
    let icon: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(color)
            content()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
        .padding(.horizontal, 2)
    }
}

struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = values.suffix(30)
            let w = geo.size.width, h = geo.size.height
            let step = pts.count > 1 ? w / CGFloat(pts.count - 1) : w
            let path = Path { p in
                for (i, v) in pts.enumerated() {
                    let pt = CGPoint(x: CGFloat(i) * step, y: h - CGFloat(v / 100) * h)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
            }
            ZStack {
                path.stroke(color, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
                Path { p in
                    p.addPath(path)
                    p.addLine(to: CGPoint(x: CGFloat(max(pts.count - 1, 0)) * step, y: h))
                    p.addLine(to: CGPoint(x: 0, y: h))
                }
                .fill(color.opacity(0.18))
            }
        }
    }
}

private struct UsageBar: View {
    let fraction: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.25))
                Capsule().fill(fraction > 0.9 ? Color.red : (fraction > 0.75 ? .orange : .green))
                    .frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
    }
}
