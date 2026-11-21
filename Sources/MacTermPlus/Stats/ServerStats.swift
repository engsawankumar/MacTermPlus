import Citadel
import Foundation
import NIOCore

/// Polls basic health numbers from the server over the tab's existing SSH connection.
@MainActor
final class ServerStats: ObservableObject {
    @Published private(set) var host = ""
    @Published private(set) var os = ""
    @Published private(set) var user = ""
    @Published private(set) var cpuPercent: Double?
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var memUsed: UInt64?
    @Published private(set) var memTotal: UInt64?
    @Published private(set) var rxRate: Double?
    @Published private(set) var txRate: Double?
    @Published private(set) var diskUsed: UInt64?
    @Published private(set) var diskTotal: UInt64?
    @Published private(set) var diskFree: UInt64?
    /// os-release ID (e.g. "ubuntu", "debian"), or "darwin" / "freebsd".
    @Published private(set) var osID = ""
    /// Called once when the OS is first identified (used to remember it on the session).
    var onOSDetected: ((String) -> Void)?
    @Published private(set) var uptime: TimeInterval?
    @Published private(set) var load = ""
    @Published private(set) var hasData = false

    private var task: Task<Void, Never>?
    private var lastCPU: (busy: Double, total: Double)?
    private var lastNet: (rx: Double, tx: Double, at: Date)?

    /// POSIX sh, silent on errors, always exits 0 (Citadel treats stderr / non-zero as failure).
    static let script = #"""
    { echo "H=$(hostname)"; echo "U=$(whoami)"
      if [ -r /etc/os-release ]; then . /etc/os-release; echo "O=$PRETTY_NAME"; echo "I=$ID"; echo "J=$ID_LIKE"; else echo "O=$(uname -sr)"; echo "I=$(uname -s | tr 'A-Z' 'a-z')"; fi
      if [ -r /proc/stat ]; then echo "C=$(head -n1 /proc/stat)"
      else echo "P=$(ps -A -o %cpu= | awk '{s+=$1} END{print s}') $(sysctl -n hw.ncpu 2>/dev/null || nproc)"; fi
      if [ -r /proc/meminfo ]; then awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{print "M=" t " " a}' /proc/meminfo; fi
      if [ -r /proc/net/dev ]; then awk -F: 'NR>2 { gsub(/^ +/,"",$1); if ($1!="lo") { split($2,f," "); rx+=f[1]; tx+=f[9] } } END{print "N=" rx " " tx}' /proc/net/dev; fi
      df -Pk / | awk 'NR==2{print "D=" $2 " " $3 " " $4}'
      if [ -r /proc/uptime ]; then echo "T=$(cut -d' ' -f1 /proc/uptime)"; fi
      if [ -r /proc/loadavg ]; then echo "L=$(cut -d' ' -f1-3 /proc/loadavg)"; else echo "L=$(uptime | sed 's/.*load average[s]*: //')"; fi
    } 2>/dev/null; true
    """#

    func start(connection: SSHConnection) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                let settings = AppSettings.shared
                if settings.showStatusBar, connection.state == .connected,
                   let client = try? await connection.connectedClient() {
                    if let out = try? await client.executeCommand(Self.script, maxResponseSize: 64 * 1024) {
                        self?.parse(String(buffer: out))
                    }
                }
                let interval = max(1, settings.statusInterval)
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func parse(_ text: String) {
        var values: [String: String] = [:]
        for line in text.split(separator: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            values[String(line[..<eq])] = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
        }
        if let v = values["H"], !v.isEmpty { host = v }
        if let v = values["U"], !v.isEmpty { user = v }
        if let v = values["O"], !v.isEmpty { os = v.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
        if let v = values["I"]?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased(), !v.isEmpty {
            let resolved = Distro.resolve(id: v, like: values["J"] ?? "", pretty: os)
            if resolved != osID {
                osID = resolved
                onOSDetected?(resolved)
            }
        }

        if let c = values["C"] {
            // cpu user nice system idle iowait irq softirq steal ...
            let nums = c.split(separator: " ").dropFirst().compactMap { Double($0) }
            if nums.count >= 4 {
                let idle = nums[3] + (nums.count > 4 ? nums[4] : 0)
                let total = nums.prefix(8).reduce(0, +)
                if let last = lastCPU, total > last.total {
                    let busy = (total - idle) - last.busy
                    pushCPU(max(0, min(100, busy / (total - last.total) * 100)))
                }
                lastCPU = (total - idle, total)
            }
        } else if let p = values["P"] {
            let parts = p.split(separator: " ").compactMap { Double($0) }
            if parts.count == 2, parts[1] > 0 { pushCPU(min(100, parts[0] / parts[1])) }
        }

        if let m = values["M"] {
            let parts = m.split(separator: " ").compactMap { UInt64($0) }
            if parts.count == 2 {
                memTotal = parts[0] * 1024
                memUsed = (parts[0] - min(parts[0], parts[1])) * 1024
            }
        }
        if let n = values["N"] {
            let parts = n.split(separator: " ").compactMap { Double($0) }
            if parts.count == 2 {
                let now = Date()
                if let last = lastNet {
                    let dt = now.timeIntervalSince(last.at)
                    if dt > 0 {
                        rxRate = max(0, (parts[0] - last.rx) / dt)
                        txRate = max(0, (parts[1] - last.tx) / dt)
                    }
                }
                lastNet = (parts[0], parts[1], now)
            }
        }
        if let d = values["D"] {
            let parts = d.split(separator: " ").compactMap { UInt64($0) }
            if parts.count >= 2 { diskTotal = parts[0] * 1024; diskUsed = parts[1] * 1024 }
            if parts.count >= 3 { diskFree = parts[2] * 1024 }
        }
        if let t = values["T"], let secs = Double(t) { uptime = secs }
        if let l = values["L"] { load = l }
        hasData = true
    }

    private func pushCPU(_ value: Double) {
        cpuPercent = value
        cpuHistory.append(value)
        if cpuHistory.count > 40 { cpuHistory.removeFirst(cpuHistory.count - 40) }
    }

    // MARK: Formatting

    static func bytes(_ v: UInt64) -> String {
        let gb = Double(v) / 1_073_741_824
        return gb >= 1 ? String(format: "%.2f GB", gb) : String(format: "%.0f MB", Double(v) / 1_048_576)
    }

    static func rate(_ v: Double) -> String {
        if v >= 1_048_576 { return String(format: "%.1f MB/s", v / 1_048_576) }
        if v >= 1024 { return String(format: "%.0f KB/s", v / 1024) }
        return String(format: "%.0f B/s", v)
    }

    static func duration(_ secs: TimeInterval) -> String {
        let s = Int(secs)
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
