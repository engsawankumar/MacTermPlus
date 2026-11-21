import AppKit
import SwiftTerm
import SwiftUI

/// A terminal color scheme: background, foreground, cursor, selection, and the 16 ANSI colors.
struct TerminalTheme: Identifiable, Hashable {
    let id: String
    let name: String
    let isDark: Bool
    let background: String
    let foreground: String
    let cursor: String
    let selection: String
    /// black, red, green, yellow, blue, magenta, cyan, white, then the 8 bright variants.
    let ansi: [String]

    var nsBackground: NSColor { NSColor(hex: background) }
    var nsForeground: NSColor { NSColor(hex: foreground) }
    var nsCursor: NSColor { NSColor(hex: cursor) }
    var nsSelection: NSColor { NSColor(hex: selection) }

    var swiftTermColors: [SwiftTerm.Color] {
        ansi.map { hex in
            let (r, g, b) = NSColor.rgb(hex)
            return SwiftTerm.Color(red: UInt16(r) * 257, green: UInt16(g) * 257, blue: UInt16(b) * 257)
        }
    }

    static func named(_ id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }

    static let all: [TerminalTheme] = [
        TerminalTheme(id: "macterm-night", name: "MacTerm Night", isDark: true,
                      background: "171A21", foreground: "DCE0E8", cursor: "3FE0CC", selection: "2E4A5C",
                      ansi: ["1E2129", "F0626E", "7FD88F", "F5C66E", "5FA8F5", "C58AF0", "3FE0CC", "C9CED8",
                             "4B5263", "FF7A85", "98E6A6", "FFD98A", "7DBBFF", "D7A6FF", "6FF0DF", "FFFFFF"]),
        TerminalTheme(id: "midnight", name: "Midnight Blue", isDark: true,
                      background: "0B1426", foreground: "C8D3F5", cursor: "82AAFF", selection: "203461",
                      ansi: ["15203A", "FF5874", "21C7A8", "ECC48D", "82AAFF", "C792EA", "7FDBCA", "C8D3F5",
                             "4B5B83", "FF6E8A", "3EE0C0", "FFD9A1", "9DBCFF", "D7A7F5", "9CEADC", "FFFFFF"]),
        TerminalTheme(id: "dracula", name: "Dracula", isDark: true,
                      background: "282A36", foreground: "F8F8F2", cursor: "F8F8F2", selection: "44475A",
                      ansi: ["21222C", "FF5555", "50FA7B", "F1FA8C", "BD93F9", "FF79C6", "8BE9FD", "F8F8F2",
                             "6272A4", "FF6E6E", "69FF94", "FFFFA5", "D6ACFF", "FF92DF", "A4FFFF", "FFFFFF"]),
        TerminalTheme(id: "nord", name: "Nord", isDark: true,
                      background: "2E3440", foreground: "D8DEE9", cursor: "88C0D0", selection: "434C5E",
                      ansi: ["3B4252", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "88C0D0", "E5E9F0",
                             "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "ECEFF4"]),
        TerminalTheme(id: "tokyo-night", name: "Tokyo Night", isDark: true,
                      background: "1A1B26", foreground: "C0CAF5", cursor: "C0CAF5", selection: "33467C",
                      ansi: ["15161E", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "A9B1D6",
                             "414868", "F7768E", "9ECE6A", "E0AF68", "7AA2F7", "BB9AF7", "7DCFFF", "C0CAF5"]),
        TerminalTheme(id: "one-dark", name: "One Dark", isDark: true,
                      background: "282C34", foreground: "ABB2BF", cursor: "528BFF", selection: "3E4451",
                      ansi: ["282C34", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
                             "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF"]),
        TerminalTheme(id: "gruvbox-dark", name: "Gruvbox Dark", isDark: true,
                      background: "282828", foreground: "EBDBB2", cursor: "EBDBB2", selection: "504945",
                      ansi: ["282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984",
                             "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2"]),
        TerminalTheme(id: "catppuccin", name: "Catppuccin Mocha", isDark: true,
                      background: "1E1E2E", foreground: "CDD6F4", cursor: "F5E0DC", selection: "45475A",
                      ansi: ["45475A", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "BAC2DE",
                             "585B70", "F38BA8", "A6E3A1", "F9E2AF", "89B4FA", "F5C2E7", "94E2D5", "A6ADC8"]),
        TerminalTheme(id: "monokai", name: "Monokai", isDark: true,
                      background: "272822", foreground: "F8F8F2", cursor: "F8F8F0", selection: "49483E",
                      ansi: ["272822", "F92672", "A6E22E", "F4BF75", "66D9EF", "AE81FF", "A1EFE4", "F8F8F2",
                             "75715E", "F92672", "A6E22E", "F4BF75", "66D9EF", "AE81FF", "A1EFE4", "F9F8F5"]),
        TerminalTheme(id: "solarized-dark", name: "Solarized Dark", isDark: true,
                      background: "002B36", foreground: "93A1A1", cursor: "93A1A1", selection: "073642",
                      ansi: ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
                             "586E75", "CB4B16", "93A1A1", "839496", "657B83", "6C71C4", "93A1A1", "FDF6E3"]),
        TerminalTheme(id: "moba-classic", name: "Classic Black", isDark: true,
                      background: "000000", foreground: "E6E6E6", cursor: "FFFFFF", selection: "3A3A3A",
                      ansi: ["000000", "CD3131", "0DBC79", "E5E510", "2472C8", "BC3FBC", "11A8CD", "E5E5E5",
                             "666666", "F14C4C", "23D18B", "F5F543", "3B8EEA", "D670D6", "29B8DB", "FFFFFF"]),
        TerminalTheme(id: "matrix", name: "Matrix", isDark: true,
                      background: "000A00", foreground: "33FF66", cursor: "66FF99", selection: "0F3D1A",
                      ansi: ["001400", "2BAA4B", "33FF66", "99FF66", "1F9E57", "3DCC7A", "66FFB2", "B3FFC6",
                             "0B4D1F", "4DD96F", "66FF8C", "CCFF99", "33CC77", "66E699", "99FFCC", "E6FFEC"]),
        TerminalTheme(id: "amber", name: "Retro Amber", isDark: true,
                      background: "140C00", foreground: "FFB000", cursor: "FFCC4D", selection: "4D3300",
                      ansi: ["1F1400", "CC7A00", "E69900", "FFB000", "B37700", "D98C00", "FFC233", "FFD480",
                             "4D3300", "FF9900", "FFAD33", "FFC94D", "CC8800", "F2A100", "FFD266", "FFE6B3"]),
        TerminalTheme(id: "ocean", name: "Deep Ocean", isDark: true,
                      background: "0F1E2E", foreground: "D6E9F8", cursor: "4FD6BE", selection: "1E3A55",
                      ansi: ["14283D", "EF6B73", "6CD8A0", "F3D27A", "4AA8FF", "B48CF2", "4FD6BE", "D6E9F8",
                             "3D5A78", "FF8A91", "8CEBB8", "FFE39C", "7AC0FF", "CBA9FF", "7FE8D6", "FFFFFF"]),
        TerminalTheme(id: "solarized-light", name: "Solarized Light", isDark: false,
                      background: "FDF6E3", foreground: "586E75", cursor: "586E75", selection: "EEE8D5",
                      ansi: ["073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
                             "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3"]),
        TerminalTheme(id: "paper", name: "Paper Light", isDark: false,
                      background: "FFFFFF", foreground: "24292F", cursor: "0969DA", selection: "CCE3FF",
                      ansi: ["24292F", "CF222E", "116329", "9A6700", "0969DA", "8250DF", "1B7C83", "6E7781",
                             "57606A", "A40E26", "1A7F37", "BF8700", "218BFF", "A475F9", "3192AA", "8C959F"]),
        TerminalTheme(id: "rose-light", name: "Rosé Light", isDark: false,
                      background: "FAF4ED", foreground: "575279", cursor: "9893A5", selection: "DFDAD9",
                      ansi: ["F2E9E1", "B4637A", "286983", "EA9D34", "56949F", "907AA9", "D7827E", "575279",
                             "9893A5", "B4637A", "286983", "EA9D34", "56949F", "907AA9", "D7827E", "575279"]),
    ]
}

extension NSColor {
    static func rgb(_ hex: String) -> (UInt8, UInt8, UInt8) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let v = UInt32(s, radix: 16) ?? 0
        return (UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF))
    }

    convenience init(hex: String) {
        let (r, g, b) = NSColor.rgb(hex)
        self.init(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

extension SwiftUI.Color {
    init(hex: String) { self.init(nsColor: NSColor(hex: hex)) }
}

/// Small color strip image for menus (menus can't show custom SwiftUI views).
enum ThemeSwatch {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func image(_ t: TerminalTheme) -> NSImage {
        if let img = cache[t.id] { return img }
        let img = NSImage(size: NSSize(width: 34, height: 14), flipped: false) { r in
            NSBezierPath(roundedRect: r, xRadius: 3, yRadius: 3).addClip()
            t.nsBackground.setFill(); r.fill()
            for (i, hex) in [t.ansi[1], t.ansi[2], t.ansi[3], t.ansi[4], t.ansi[5]].enumerated() {
                NSColor(hex: hex).setFill()
                NSRect(x: 4 + CGFloat(i) * 6, y: 4, width: 5, height: 6).fill()
            }
            return true
        }
        cache[t.id] = img
        return img
    }
}
