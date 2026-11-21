import Foundation
import SwiftUI

/// A row in either the local or the remote file list.
struct FileItem: Identifiable, Hashable {
    var id: String { path }
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: UInt64?
    let modified: Date?
    let permissions: String
    /// The synthetic ".." row that goes to the parent folder.
    var isParent: Bool = false
    var owner: String = ""
    var group: String = ""

    /// Permission bits (e.g. 0o755) read from the "rwxr-xr-x" string.
    var mode: UInt32? { FileItem.mode(from: permissions) }

    static func mode(from s: String) -> UInt32? {
        let chars = Array(s.suffix(9))
        guard chars.count == 9 else { return nil }
        var m: UInt32 = 0
        for (i, c) in chars.enumerated() {
            let bit = UInt32(1) << UInt32(8 - i)
            switch c {
            case "r", "w", "x": m |= bit
            case "s": m |= bit; m |= (i == 2 ? 0o4000 : 0o2000)
            case "S": m |= (i == 2 ? 0o4000 : 0o2000)
            case "t": m |= bit; m |= 0o1000
            case "T": m |= 0o1000
            default: break
            }
        }
        return m
    }

    var kindDescription: String {
        if isDirectory { return "Folder" }
        if isSymlink { return "Symbolic link" }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty ? "File" : "\(ext.uppercased()) file"
    }

    static func parentRow(of path: String, parent: String) -> FileItem {
        FileItem(name: "..", path: "\u{0}parent:" + parent, isDirectory: true, isSymlink: false,
                 size: nil, modified: nil, permissions: "", isParent: true)
    }

    var parentTarget: String { String(path.dropFirst("\u{0}parent:".count)) }

    var sizeText: String {
        guard !isDirectory, let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    var modifiedText: String {
        guard let modified else { return "" }
        return FileItem.dateFormatter.string(from: modified)
    }

    var icon: String { FileKind.of(self).symbol }
    var iconColor: Color { FileKind.of(self).color }

    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    /// Directories first, then case-insensitive by name.
    static func sort(_ items: [FileItem]) -> [FileItem] {
        items.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func permissionString(_ mode: UInt32?) -> String {
        guard let mode else { return "" }
        let type: Character
        switch mode & 0o170000 {
        case 0o040000: type = "d"
        case 0o120000: type = "l"
        default: type = "-"
        }
        let chars: [Character] = ["r", "w", "x"]
        var out = String(type)
        for i in (0..<9).reversed() {
            out.append(mode & (1 << UInt32(i)) != 0 ? chars[(8 - i) % 3] : "-")
        }
        return out
    }
}

enum RemotePath {
    static func join(_ dir: String, _ name: String) -> String {
        dir.hasSuffix("/") ? dir + name : dir + "/" + name
    }

    static func parent(_ path: String) -> String {
        guard path != "/" else { return "/" }
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let idx = trimmed.lastIndex(of: "/") else { return "/" }
        let p = String(trimmed[..<idx])
        return p.isEmpty ? "/" : p
    }
}

/// File categories for colorful icons.
enum FileKind {
    case parent, folder, hiddenFolder, symlink, image, video, audio, archive, code, script, config, text,
         pdf, key, log, database, document, spreadsheet, executable, web, generic

    static func of(_ item: FileItem) -> FileKind {
        if item.isParent { return .parent }
        if item.isDirectory { return item.name.hasPrefix(".") ? .hiddenFolder : .folder }
        if item.isSymlink { return .symlink }
        let lower = item.name.lowercased()
        let ext = (lower as NSString).pathExtension
        if ["id_rsa", "id_ed25519", "id_ecdsa", "authorized_keys", "known_hosts"].contains(lower) { return .key }
        if ["dockerfile", "makefile", ".bashrc", ".zshrc", ".profile", ".bash_profile", ".env", ".gitignore"].contains(lower) { return .config }
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "svg", "ico", "heic": return .image
        case "mp4", "mkv", "mov", "avi", "webm", "m4v": return .video
        case "mp3", "wav", "flac", "aac", "ogg", "m4a": return .audio
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "zst", "deb", "rpm", "dmg", "iso": return .archive
        case "swift", "c", "h", "cpp", "hpp", "m", "go", "rs", "java", "kt", "py", "rb", "php", "js", "ts",
             "jsx", "tsx", "cs", "scala", "lua", "pl", "r", "dart", "vue": return .code
        case "sh", "bash", "zsh", "fish", "ps1", "bat", "cmd", "command": return .script
        case "conf", "cfg", "ini", "yaml", "yml", "toml", "json", "xml", "plist", "properties", "env", "service": return .config
        case "html", "htm", "css", "scss", "less": return .web
        case "txt", "md", "rst", "readme", "csv", "tsv": return .text
        case "pdf": return .pdf
        case "pem", "key", "crt", "cer", "pub", "p12", "pfx", "gpg", "asc": return .key
        case "log", "out", "err": return .log
        case "sql", "db", "sqlite", "sqlite3", "dump", "bak": return .database
        case "doc", "docx", "odt", "rtf", "pages", "ppt", "pptx", "key_": return .document
        case "xls", "xlsx", "ods", "numbers": return .spreadsheet
        case "exe", "bin", "run", "appimage", "so", "dylib", "o", "a", "jar", "app": return .executable
        default:
            if item.permissions.count == 10, item.permissions.dropFirst(3).first == "x" { return .executable }
            return .generic
        }
    }

    var symbol: String {
        switch self {
        case .parent: return "arrowshape.turn.up.left.fill"
        case .folder: return "folder.fill"
        case .hiddenFolder: return "folder"
        case .symlink: return "link.circle.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "doc.zipper"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .script: return "terminal.fill"
        case .config: return "gearshape.fill"
        case .text: return "doc.text.fill"
        case .pdf: return "doc.richtext.fill"
        case .key: return "key.fill"
        case .log: return "list.bullet.rectangle.fill"
        case .database: return "cylinder.split.1x2.fill"
        case .document: return "doc.fill"
        case .spreadsheet: return "tablecells.fill"
        case .executable: return "gearshape.2.fill"
        case .web: return "globe"
        case .generic: return "doc"
        }
    }

    /// Two-color gradient used by the Vivid icon style.
    var vividColors: (Color, Color) {
        func h(_ a: String, _ b: String) -> (Color, Color) { (Color(hex: a), Color(hex: b)) }
        switch self {
        case .parent: return h("8E9EAB", "5D6D7E")
        case .folder: return h("4FACFE", "6A5CFF")
        case .hiddenFolder: return h("8EA6C8", "5B6B8C")
        case .symlink: return h("00C9FF", "2BD99F")
        case .image: return h("C471ED", "4568DC")
        case .video: return h("FF5F6D", "FFAA5A")
        case .audio: return h("F857A6", "FF5858")
        case .archive: return h("F7971E", "F5C400")
        case .code: return h("11998E", "38D96D")
        case .script: return h("00B09B", "86C93D")
        case .config: return h("6E7F96", "9AA9BC")
        case .text: return h("7B8AA0", "A3B1C4")
        case .pdf: return h("ED213A", "B3304A")
        case .key: return h("F7B733", "FC4A1A")
        case .log: return h("B48A78", "8C6555")
        case .database: return h("4776E6", "8E54E9")
        case .document: return h("2193B0", "56C5E0")
        case .spreadsheet: return h("1D976C", "5BD68F")
        case .executable: return h("00B4DB", "0083B0")
        case .web: return h("43CEA2", "185A9D")
        case .generic: return h("8E9EAB", "65758A")
        }
    }

    var color: Color {
        guard MainActor.assumeIsolated({ AppSettings.shared.colorfulIcons }) else {
            switch self {
            case .folder, .hiddenFolder, .parent: return .accentColor
            default: return .secondary
            }
        }
        switch self {
        case .parent: return .secondary
        case .folder: return Color(hex: "4A9EFF")
        case .hiddenFolder: return Color(hex: "7FA8D6")
        case .symlink: return .cyan
        case .image: return .purple
        case .video: return .pink
        case .audio: return .red
        case .archive: return .orange
        case .code: return .green
        case .script: return Color(hex: "2FBF71")
        case .config: return Color(hex: "8E9AAF")
        case .text: return Color(hex: "A0A7B4")
        case .pdf: return .red
        case .key: return .yellow
        case .log: return .brown
        case .database: return .indigo
        case .document: return .blue
        case .spreadsheet: return Color(hex: "1E9E5A")
        case .executable: return .mint
        case .web: return .teal
        case .generic: return .secondary
        }
    }
}

/// Draws a file's icon in the current icon style.
struct FileIconView: View {
    let item: FileItem
    var size: CGFloat = 18
    var styleOverride: IconStyle? = nil
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        let kind = FileKind.of(item)
        let style = styleOverride ?? settings.iconStyle
        switch style {
        case .vivid:
            let (a, b) = kind.vividColors
            Image(systemName: kind.symbol)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(LinearGradient(colors: [a, b], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: size * 0.28))
                .shadow(color: b.opacity(0.35), radius: 1, y: 0.5)
        case .colorful:
            Image(systemName: kind.symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(kind.color)
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        case .mono:
            Image(systemName: kind.symbol)
                .foregroundStyle(item.isDirectory ? Color.accentColor : .secondary)
                .font(.system(size: size * 0.8))
                .frame(width: size, height: size)
        }
    }
}
