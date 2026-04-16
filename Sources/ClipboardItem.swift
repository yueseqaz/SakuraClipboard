import Cocoa
import SQLite3

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - Model
class ClipboardItem {
    enum Kind: Int {
        case text = 0
        case image = 1
    }

    let id: String
    let kind: Kind
    let text: String?
    let imageData: Data?
    let date: Date
    let isFavorite: Bool
    let favoriteFolder: String?
    let textLength: Int
    let hasMoreText: Bool
    private var cachedImage: NSImage?

    init(
        id: String = UUID().uuidString,
        text: String,
        date: Date = Date(),
        isFavorite: Bool = false,
        favoriteFolder: String? = nil,
        textLength: Int? = nil,
        hasMoreText: Bool? = nil
    ) {
        self.id = id
        self.kind = .text
        self.text = text
        self.imageData = nil
        self.date = date
        self.isFavorite = isFavorite
        self.favoriteFolder = favoriteFolder?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let length = textLength ?? text.count
        self.textLength = length
        self.hasMoreText = hasMoreText ?? (length > text.count)
    }

    init(
        id: String = UUID().uuidString,
        imageData: Data,
        date: Date = Date(),
        isFavorite: Bool = false,
        favoriteFolder: String? = nil
    ) {
        self.id = id
        self.kind = .image
        self.text = nil
        self.imageData = imageData
        self.date = date
        self.isFavorite = isFavorite
        self.favoriteFolder = favoriteFolder?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.textLength = 0
        self.hasMoreText = false
    }

    init(id: String, imageDate: Date, isFavorite: Bool, favoriteFolder: String? = nil) {
        self.id = id
        self.kind = .image
        self.text = nil
        self.imageData = nil
        self.date = imageDate
        self.isFavorite = isFavorite
        self.favoriteFolder = favoriteFolder?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.textLength = 0
        self.hasMoreText = false
    }

    convenience init?(
        id: String = UUID().uuidString,
        image: NSImage,
        date: Date = Date(),
        isFavorite: Bool = false,
        favoriteFolder: String? = nil
    ) {
        guard let data = Self.makeImageData(from: image) else { return nil }
        self.init(id: id, imageData: data, date: date, isFavorite: isFavorite, favoriteFolder: favoriteFolder)
    }

    var image: NSImage? {
        if let cachedImage { return cachedImage }
        guard let imageData else { return nil }
        let img = NSImage(data: imageData)
        cachedImage = img
        return img
    }

    static func makeImageData(from image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }
        return png
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
