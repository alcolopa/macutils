import AppKit

/// One remembered clipboard entry: text, an image, or a set of copied files.
public struct ClipboardItem: Identifiable {
    public enum Content {
        case text(String)
        case image(Data, NSSize)
        case files([URL])
    }
    
    public let id = UUID()
    public let content: Content
    public let date: Date
    public let sourceBundleID: String?
    /// Identity used to collapse duplicates.
    public let key: String
    
    public init(content: Content, sourceBundleID: String?) {
        self.content = content
        self.date = Date()
        self.sourceBundleID = sourceBundleID
        switch content {
        case .text(let t): key = "t:" + t
        case .image(let d, _): key = "i:\(d.count):\(d.hashValue)"
        case .files(let urls): key = "f:" + urls.map(\.path).joined(separator: "\n")
        }
    }
    
    public var title: String {
        switch content {
        case .text(let t):
            let flat = t.trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: " ⏎ ")
                .replacingOccurrences(of: "\t", with: " ")
            return String(flat.prefix(200))
        case .image: return "Image"
        case .files(let urls):
            let first = urls.first?.lastPathComponent ?? "File"
            return urls.count > 1 ? "\(first) and \(urls.count - 1) more" : first
        }
    }
    
    public var subtitle: String {
        switch content {
        case .text(let t):
            let lines = t.split(whereSeparator: \.isNewline).count
            let chars = "\(t.count) character\(t.count == 1 ? "" : "s")"
            return lines > 1 ? "\(lines) lines · \(chars)" : chars
        case .image(_, let size): return "\(Int(size.width)) × \(Int(size.height)) px"
        case .files(let urls): return urls.count == 1 ? "File" : "\(urls.count) files"
        }
    }
    
    public var symbolName: String {
        switch content {
        case .text: return "text.alignleft"
        case .image: return "photo"
        case .files: return "doc"
        }
    }
    
    public var image: NSImage? {
        if case .image(let data, _) = content { return NSImage(data: data) }
        return nil
    }
}
