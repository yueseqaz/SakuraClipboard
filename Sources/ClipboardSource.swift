import Cocoa

struct ClipboardSource: Codable, Equatable {
    let bundleIdentifier: String?
    let name: String?

    private static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    private static let originalSourceType = NSPasteboard.PasteboardType("com.sakura.clipboard.original-source")

    private struct OriginalSource: Codable {
        let source: ClipboardSource?
    }

    init?(bundleIdentifier: String?, name: String?) {
        let bundleIdentifier = bundleIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.bundleIdentifier = bundleIdentifier?.isEmpty == false ? bundleIdentifier : nil
        self.name = name?.isEmpty == false ? name : nil
        if self.bundleIdentifier == nil && self.name == nil { return nil }
    }

    static func capture(from pasteboard: NSPasteboard, fallback: ClipboardSource?) -> ClipboardSource? {
        // Restoring a history item must preserve its original source, even when unknown.
        if let data = pasteboard.data(forType: originalSourceType),
           let original = try? JSONDecoder().decode(OriginalSource.self, from: data) {
            return original.source
        }
        if let bundleID = pasteboard.string(forType: sourceType)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !bundleID.isEmpty {
            if fallback?.bundleIdentifier == bundleID { return fallback }
            let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            let bundle = url.flatMap { Bundle(url: $0) }
            let name = (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String)
            return ClipboardSource(bundleIdentifier: bundleID, name: name)
        }
        return fallback
    }

    static func writeOriginal(_ source: ClipboardSource?, to pasteboard: NSPasteboard) {
        if let data = try? JSONEncoder().encode(OriginalSource(source: source)) {
            pasteboard.setData(data, forType: originalSourceType)
        }
    }
}

final class ClipboardSourceIconProvider {
    private let cache = NSCache<NSString, NSImage>()
    private lazy var unknownIcon: NSImage = {
        let image = NSImage(systemSymbolName: "app", accessibilityDescription: nil)
            ?? StatusBarIcon.makeFallbackImage()
        image.size = NSSize(width: 16, height: 16)
        image.isTemplate = true
        return image
    }()

    init() {
        cache.countLimit = 64
    }

    func icon(for source: ClipboardSource?) -> NSImage {
        guard let bundleID = source?.bundleIdentifier else { return unknownIcon }
        if let cached = cache.object(forKey: bundleID as NSString) { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID),
           let appIcon = NSWorkspace.shared.icon(forFile: url.path).copy() as? NSImage {
            appIcon.size = NSSize(width: 16, height: 16)
            appIcon.isTemplate = false
            image = appIcon
        } else {
            image = unknownIcon
        }
        cache.setObject(image, forKey: bundleID as NSString)
        return image
    }
}
