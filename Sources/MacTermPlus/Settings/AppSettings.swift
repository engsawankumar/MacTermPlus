import AppKit
import SwiftTerm
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case teal, blue, purple, pink, orange, green, graphite
    var id: String { rawValue }
    var color: SwiftUI.Color {
        switch self {
        case .teal: return SwiftUI.Color(hex: "1FB5A6")
        case .blue: return .blue
        case .purple: return .purple
        case .pink: return .pink
        case .orange: return .orange
        case .green: return .green
        case .graphite: return .gray
        }
    }
}

enum IconStyle: String, CaseIterable, Identifiable {
    case mono, colorful, vivid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .mono: return "Monochrome"
        case .colorful: return "Colorful"
        case .vivid: return "Vivid (multi-color)"
        }
    }
}

enum CursorChoice: String, CaseIterable, Identifiable {
    case block, bar, underline
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    func style(blink: Bool) -> CursorStyle {
        switch self {
        case .block: return blink ? .blinkBlock : .steadyBlock
        case .bar: return blink ? .blinkBar : .steadyBar
        case .underline: return blink ? .blinkUnderline : .steadyUnderline
        }
    }
}

/// Items that can appear in the server status bar under an SSH terminal.
enum StatusItem: String, CaseIterable, Identifiable, Codable {
    case host, os, cpu, memory, network, user, disk, diskTotal, diskFree, uptime, load
    var id: String { rawValue }
    var label: String {
        switch self {
        case .host: return "Host name"
        case .os: return "Operating system"
        case .cpu: return "CPU usage + graph"
        case .memory: return "Memory"
        case .network: return "Network speed"
        case .user: return "User"
        case .disk: return "Disk usage % (/)"
        case .diskTotal: return "Total disk size"
        case .diskFree: return "Free disk space"
        case .uptime: return "Uptime"
        case .load: return "Load average"
        }
    }
}

/// All user preferences, persisted in UserDefaults. Views observe it; terminals are notified on change.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let changed = Notification.Name("MacTermPlus.settingsChanged")

    private let d = UserDefaults.standard

    // General
    @Published var appearance: AppAppearance { didSet { d.set(appearance.rawValue, forKey: "appearance") } }
    @Published var accent: AccentChoice { didSet { d.set(accent.rawValue, forKey: "accent") } }
    @Published var confirmCloseTab: Bool { didSet { d.set(confirmCloseTab, forKey: "confirmCloseTab") } }
    @Published var iconStyle: IconStyle { didSet { d.set(iconStyle.rawValue, forKey: "iconStyle") } }
    var colorfulIcons: Bool { iconStyle != .mono }
    @Published var compactSidebar: Bool { didSet { d.set(compactSidebar, forKey: "compactSidebar") } }
    @Published var coloredTabs: Bool { didSet { d.set(coloredTabs, forKey: "coloredTabs") } }
    @Published var showOSIcons: Bool { didSet { d.set(showOSIcons, forKey: "showOSIcons") } }
    @Published var confirmMultilinePaste: Bool { didSet { d.set(confirmMultilinePaste, forKey: "confirmMultilinePaste") } }

    // Terminal
    @Published var themeID: String { didSet { d.set(themeID, forKey: "themeID"); notify() } }
    @Published var fontName: String { didSet { d.set(fontName, forKey: "fontName"); notify() } }
    @Published var fontSize: Double { didSet { d.set(fontSize, forKey: "fontSize"); notify() } }
    @Published var cursor: CursorChoice { didSet { d.set(cursor.rawValue, forKey: "cursor"); notify() } }
    @Published var cursorBlink: Bool { didSet { d.set(cursorBlink, forKey: "cursorBlink"); notify() } }
    @Published var optionAsMeta: Bool { didSet { d.set(optionAsMeta, forKey: "optionAsMeta"); notify() } }
    @Published var copyOnSelect: Bool { didSet { d.set(copyOnSelect, forKey: "copyOnSelect") } }
    @Published var terminalPadding: Double { didSet { d.set(terminalPadding, forKey: "terminalPadding"); notify() } }

    // Files
    @Published var showHiddenFiles: Bool { didSet { d.set(showHiddenFiles, forKey: "showHiddenFiles") } }
    @Published var confirmDelete: Bool { didSet { d.set(confirmDelete, forKey: "confirmDelete") } }
    @Published var followTerminalFolder: Bool { didSet { d.set(followTerminalFolder, forKey: "followTerminalFolder") } }

    // Quick Commands
    @Published var showQuickCommands: Bool { didSet { d.set(showQuickCommands, forKey: "showQuickCommands") } }
    @Published var quickCommandsButton: Bool { didSet { d.set(quickCommandsButton, forKey: "quickCommandsButton") } }

    // Status bar
    @Published var showStatusBar: Bool { didSet { d.set(showStatusBar, forKey: "showStatusBar") } }
    @Published var statusItems: Set<StatusItem> {
        didSet { d.set(statusItems.map(\.rawValue), forKey: "statusItems") }
    }
    @Published var statusInterval: Double { didSet { d.set(statusInterval, forKey: "statusInterval") } }

    private init() {
        let ud = UserDefaults.standard
        func str(_ k: String, _ def: String) -> String { ud.string(forKey: k) ?? def }
        func bool(_ k: String, _ def: Bool) -> Bool { ud.object(forKey: k) as? Bool ?? def }
        func dbl(_ k: String, _ def: Double) -> Double { ud.object(forKey: k) as? Double ?? def }

        appearance = AppAppearance(rawValue: str("appearance", "system")) ?? .system
        accent = AccentChoice(rawValue: str("accent", "teal")) ?? .teal
        confirmCloseTab = bool("confirmCloseTab", true)
        iconStyle = IconStyle(rawValue: str("iconStyle", "")) ?? (bool("colorfulIcons", true) ? .colorful : .mono)
        compactSidebar = bool("compactSidebar", false)
        coloredTabs = bool("coloredTabs", true)
        showOSIcons = bool("showOSIcons", true)
        confirmMultilinePaste = bool("confirmMultilinePaste", true)

        themeID = str("themeID", "macterm-night")
        fontName = str("fontName", "SF Mono")
        fontSize = dbl("fontSize", 13)
        cursor = CursorChoice(rawValue: str("cursor", "block")) ?? .block
        cursorBlink = bool("cursorBlink", true)
        optionAsMeta = bool("optionAsMeta", true)
        copyOnSelect = bool("copyOnSelect", false)
        terminalPadding = dbl("terminalPadding", 12)

        showHiddenFiles = bool("showHiddenFiles", false)
        confirmDelete = bool("confirmDelete", true)
        followTerminalFolder = bool("followTerminalFolder", true)
        showQuickCommands = bool("showQuickCommands", false)
        quickCommandsButton = bool("quickCommandsButton", true)

        showStatusBar = bool("showStatusBar", true)
        if let saved = ud.array(forKey: "statusItems") as? [String] {
            var items = Set(saved.compactMap(StatusItem.init(rawValue:)))
            if ud.object(forKey: "statusItems.v2") == nil {   // show the new disk items once
                items.formUnion([.diskTotal, .diskFree])
                ud.set(true, forKey: "statusItems.v2")
            }
            statusItems = items
        } else {
            statusItems = Set(StatusItem.allCases)
        }
        statusInterval = dbl("statusInterval", 3)
    }

    var theme: TerminalTheme { TerminalTheme.named(themeID) }

    var terminalFont: NSFont {
        if fontName != "SF Mono", let f = NSFont(name: fontName, size: fontSize) { return f }
        return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    /// Installed fixed-width fonts, for the font picker.
    static let monospacedFonts: [String] = {
        let names = NSFontManager.shared.availableFontFamilies.filter { family in
            guard let font = NSFont(name: family, size: 12) else { return false }
            return font.isFixedPitch || NSFontManager.shared.traits(of: font).contains(.fixedPitchFontMask)
        }
        return ["SF Mono"] + names.filter { $0 != "SF Mono" }.sorted()
    }()

    /// Preferences that follow the user to other Macs (window state and per-Mac things are left out).
    static let syncKeys = ["appearance", "accent", "confirmCloseTab", "iconStyle", "compactSidebar", "coloredTabs",
                           "showOSIcons", "confirmMultilinePaste", "themeID", "fontName", "fontSize", "cursor", "cursorBlink",
                           "optionAsMeta", "copyOnSelect", "terminalPadding", "showHiddenFiles", "confirmDelete",
                           "followTerminalFolder", "quickCommandsButton", "showStatusBar", "statusItems", "statusInterval"]

    func resetToDefaults() {
        for key in Self.syncKeys + ["colorfulIcons"] { d.removeObject(forKey: key) }
        reload()
    }

    /// The synced preferences as a binary property list.
    func syncSnapshot() -> Data? {
        var dict: [String: Any] = [:]
        for k in Self.syncKeys { if let v = d.object(forKey: k) { dict[k] = v } }
        return try? PropertyListSerialization.data(fromPropertyList: dict, format: .binary, options: 0)
    }

    /// Applies preferences that came from another Mac.
    func applySynced(_ data: Data) {
        guard let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        for k in Self.syncKeys {
            if let v = dict[k] { d.set(v, forKey: k) } else { d.removeObject(forKey: k) }
        }
        reload()
    }

    /// Re-reads every preference from UserDefaults.
    private func reload() {
        let fresh = AppSettings()
        appearance = fresh.appearance; accent = fresh.accent; confirmCloseTab = fresh.confirmCloseTab
        iconStyle = fresh.iconStyle; compactSidebar = fresh.compactSidebar; coloredTabs = fresh.coloredTabs
        showOSIcons = fresh.showOSIcons; confirmMultilinePaste = fresh.confirmMultilinePaste; themeID = fresh.themeID
        fontName = fresh.fontName; fontSize = fresh.fontSize; cursor = fresh.cursor; cursorBlink = fresh.cursorBlink
        optionAsMeta = fresh.optionAsMeta; copyOnSelect = fresh.copyOnSelect; terminalPadding = fresh.terminalPadding
        showHiddenFiles = fresh.showHiddenFiles; confirmDelete = fresh.confirmDelete; followTerminalFolder = fresh.followTerminalFolder
        quickCommandsButton = fresh.quickCommandsButton; showStatusBar = fresh.showStatusBar; statusItems = fresh.statusItems
        statusInterval = fresh.statusInterval
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}

/// Applies the current settings to a terminal view.
enum Appearance {
    @MainActor
    static func apply(to view: TerminalView, themeID: String = "") {
        let s = AppSettings.shared
        let theme = themeID.isEmpty ? s.theme : TerminalTheme.named(themeID)
        view.font = s.terminalFont
        view.nativeBackgroundColor = theme.nsBackground
        view.nativeForegroundColor = theme.nsForeground
        view.caretColor = theme.nsCursor
        view.selectedTextBackgroundColor = theme.nsSelection
        view.installColors(theme.swiftTermColors)
        view.optionAsMetaKey = s.optionAsMeta
        view.setCursorStyle(s.cursor.style(blink: s.cursorBlink))
        // Also paint the backing layer so no other color shows around the text grid.
        view.wantsLayer = true
        view.layer?.backgroundColor = theme.nsBackground.cgColor
        view.needsDisplay = true
    }
}

enum AppInfo {
    static let developer = "Bairagi"
    static let credit = "Built by Bairagi"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
}
