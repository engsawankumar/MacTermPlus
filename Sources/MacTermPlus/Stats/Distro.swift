import SwiftUI

/// Operating systems recognized from /etc/os-release, drawn as original badges in each
/// project's signature colors (not the projects' trademarked logos).
struct Distro {
    let id: String
    let name: String
    let colors: (String, String)
    /// Either an SF Symbol ("sf:…") or a short text mark.
    let mark: String

    static let all: [Distro] = [
        Distro(id: "ubuntu", name: "Ubuntu", colors: ("E95420", "C34113"), mark: "U"),
        Distro(id: "debian", name: "Debian", colors: ("D70A53", "A80030"), mark: "D"),
        Distro(id: "raspbian", name: "Raspberry Pi OS", colors: ("D6264F", "A1173A"), mark: "π"),
        Distro(id: "fedora", name: "Fedora", colors: ("51A2DA", "294172"), mark: "f"),
        Distro(id: "centos", name: "CentOS", colors: ("A14F8C", "932279"), mark: "C"),
        Distro(id: "rhel", name: "Red Hat Enterprise Linux", colors: ("EE0000", "A30000"), mark: "RH"),
        Distro(id: "rocky", name: "Rocky Linux", colors: ("10B981", "0B7A55"), mark: "R"),
        Distro(id: "almalinux", name: "AlmaLinux", colors: ("1E73BE", "0F4266"), mark: "α"),
        Distro(id: "ol", name: "Oracle Linux", colors: ("E3523E", "C74634"), mark: "O"),
        Distro(id: "amzn", name: "Amazon Linux", colors: ("FFB547", "FF9900"), mark: "a"),
        Distro(id: "arch", name: "Arch Linux", colors: ("1793D1", "0F6A99"), mark: "sf:triangle.fill"),
        Distro(id: "manjaro", name: "Manjaro", colors: ("35BF5C", "228B3F"), mark: "M"),
        Distro(id: "endeavouros", name: "EndeavourOS", colors: ("7F3FBF", "C33FB3"), mark: "E"),
        Distro(id: "alpine", name: "Alpine Linux", colors: ("1A8CC1", "0D597F"), mark: "sf:mountain.2.fill"),
        Distro(id: "opensuse", name: "openSUSE", colors: ("73BA25", "4F8A10"), mark: "S"),
        Distro(id: "sles", name: "SUSE Linux Enterprise", colors: ("30BA78", "0C322C"), mark: "S"),
        Distro(id: "linuxmint", name: "Linux Mint", colors: ("87CF3E", "5E9B23"), mark: "m"),
        Distro(id: "pop", name: "Pop!_OS", colors: ("48B9C7", "2D8C99"), mark: "P"),
        Distro(id: "elementary", name: "elementary OS", colors: ("64BAFF", "3689E6"), mark: "e"),
        Distro(id: "kali", name: "Kali Linux", colors: ("367BF0", "1F4E9E"), mark: "K"),
        Distro(id: "gentoo", name: "Gentoo", colors: ("7A6FB0", "54487A"), mark: "G"),
        Distro(id: "nixos", name: "NixOS", colors: ("7EBAE4", "5277C3"), mark: "sf:snowflake"),
        Distro(id: "void", name: "Void Linux", colors: ("5A9E7C", "295340"), mark: "V"),
        Distro(id: "slackware", name: "Slackware", colors: ("6B6BB5", "3B3B7A"), mark: "S"),
        Distro(id: "clear-linux-os", name: "Clear Linux", colors: ("56C1F0", "0071C5"), mark: "C"),
        Distro(id: "photon", name: "Photon OS", colors: ("8BC34A", "607D3B"), mark: "P"),
        Distro(id: "proxmox", name: "Proxmox VE", colors: ("F28C38", "E57000"), mark: "PX"),
        Distro(id: "truenas", name: "TrueNAS", colors: ("0095D5", "005F8A"), mark: "T"),
        Distro(id: "openwrt", name: "OpenWrt", colors: ("00B5E2", "00668A"), mark: "sf:wifi.router.fill"),
        Distro(id: "freebsd", name: "FreeBSD", colors: ("D03B37", "AB2B28"), mark: "BSD"),
        Distro(id: "openbsd", name: "OpenBSD", colors: ("F2CA30", "B8961B"), mark: "oB"),
        Distro(id: "darwin", name: "macOS", colors: ("8E8E93", "3A3A3C"), mark: "sf:apple.logo"),
        Distro(id: "windows", name: "Windows", colors: ("2F8BE6", "0067B8"), mark: "sf:squareshape.split.2x2"),
        Distro(id: "linux", name: "Linux", colors: ("F5C518", "B8860B"), mark: "sf:terminal.fill"),
    ]

    static func named(_ id: String) -> Distro? { all.first { $0.id == id } }

    /// Picks a known ID from os-release ID / ID_LIKE / PRETTY_NAME.
    static func resolve(id: String, like: String, pretty: String) -> String {
        let aliases = ["raspberrypi": "raspbian", "centos-stream": "centos", "redhat": "rhel", "opensuse-leap": "opensuse",
                       "opensuse-tumbleweed": "opensuse", "sled": "sles", "mint": "linuxmint", "pop-os": "pop",
                       "almalinux-": "almalinux", "macos": "darwin", "mac os x": "darwin", "debian-": "debian"]
        let cleaned = id.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        let p = pretty.lowercased()
        // Newer Raspberry Pi OS reports ID=debian; its name gives it away.
        if p.contains("raspbian") || p.contains("raspberry") { return "raspbian" }
        if named(cleaned) != nil { return cleaned }
        if let a = aliases[cleaned] { return a }
        for d in all where d.id != "linux" && p.contains(d.name.lowercased()) { return d.id }
        for l in like.lowercased().split(separator: " ").map(String.init) where named(l) != nil { return l }
        if cleaned.hasPrefix("opensuse") { return "opensuse" }
        if p.contains("darwin") || p.contains("macos") { return "darwin" }
        return cleaned.isEmpty ? "" : "linux"
    }
}

/// Original OS badge: gradient tile in the distro's colors with a simple mark.
struct DistroBadge: View {
    let osID: String
    var size: CGFloat = 18

    var body: some View {
        let d = Distro.named(osID) ?? Distro.named("linux")!
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28)
                .fill(LinearGradient(colors: [Color(hex: d.colors.0), Color(hex: d.colors.1)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if d.mark.hasPrefix("sf:") {
                Image(systemName: String(d.mark.dropFirst(3)))
                    .font(.system(size: size * 0.5, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text(d.mark)
                    .font(.system(size: size * (d.mark.count > 2 ? 0.34 : (d.mark.count == 2 ? 0.42 : 0.6)), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
        .help(d.name)
    }
}
