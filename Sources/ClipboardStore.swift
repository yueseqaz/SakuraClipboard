import Cocoa
import SQLite3

// MARK: - Store
class ClipboardStore {
    enum FilterType: Int {
        case all = -1
        case text = 0
        case image = 1
    }

    enum TimeFilter: Int {
        case all
        case lastHour
        case today
        case last7Days
        case last30Days
    }

    struct Query {
        let keyword: String
        let filterType: FilterType
        let timeFilter: TimeFilter
    }

    static let shared = ClipboardStore()
    private static let textPreviewFetchLimit = 600
    private(set) var items: [ClipboardItem] = []
    private let defaultMaxItems = 50
    private let minMaxItems = 10
    private let hardMaxItems = 500
    private let maxItemsKey = "clipboard.maxItems"
    private let fileManager = FileManager.default
    private var db: OpaquePointer?

    private var storeURL: URL = {
        let fallback = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SakuraClipboard-history.sqlite")
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fallback
        }
        return base
            .appendingPathComponent("SakuraClipboard", isDirectory: true)
            .appendingPathComponent("history.sqlite")
    }()

    var maxItems: Int {
        let raw = UserDefaults.standard.integer(forKey: maxItemsKey)
        if raw == 0 { return defaultMaxItems }
        return max(minMaxItems, min(raw, hardMaxItems))
    }

    private init() {
        openDatabase()
        createTablesIfNeeded()
        loadAll()
    }

    func addText(_ text: String) {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        removeExistingText(cleaned)
        let item = ClipboardItem(text: cleaned)
        insert(item)
        finalizeChanges()
    }

    func addImage(_ image: NSImage) {
        guard let imageData = ClipboardItem.makeImageData(from: image) else { return }
        removeExistingImageData(imageData)
        let item = ClipboardItem(imageData: imageData)
        insert(item)
        finalizeChanges()
    }

    func updateFavorite(id: String, isFavorite: Bool) {
        execute(
            "UPDATE clipboard_items SET is_favorite = ? WHERE id = ?;",
            bind: { stmt in
                sqlite3_bind_int(stmt, 1, isFavorite ? 1 : 0)
                sqlite3_bind_text(stmt, 2, id, -1, SQLITE_TRANSIENT)
            }
        )
        loadAll()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func toggleFavorite(id: String) {
        let target = items.first(where: { $0.id == id })
        updateFavorite(id: id, isFavorite: !(target?.isFavorite ?? false))
    }

    func clear() {
        execute("DELETE FROM clipboard_items;")
        items.removeAll()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func clearStorage() {
        closeDatabase()
        try? fileManager.removeItem(at: storeURL)
        openDatabase()
        createTablesIfNeeded()
        items.removeAll()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func setMaxItems(_ newValue: Int) {
        let clamped = max(minMaxItems, min(newValue, hardMaxItems))
        UserDefaults.standard.set(clamped, forKey: maxItemsKey)
        trim()
        loadAll()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    func storageLocationDescription() -> String {
        storeURL.path
    }

    func revealInFinder() {
        let directory = storeURL.deletingLastPathComponent()
        let target = fileManager.fileExists(atPath: storeURL.path) ? storeURL : directory
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func storageUsageDescription() -> String {
        guard let attrs = try? fileManager.attributesOfItem(atPath: storeURL.path),
              let bytes = attrs[.size] as? Int64 else {
            return "0 B"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func fullText(for id: String) -> String? {
        let rows = fetch(
            sql: "SELECT id, type, text, image_data, created_at, is_favorite, length(text) FROM clipboard_items WHERE id = ? LIMIT 1;",
            binders: [{ stmt, i in sqlite3_bind_text(stmt, i, id, -1, SQLITE_TRANSIENT) }],
            truncateText: false,
            includeImageData: false
        )
        return rows.first?.text
    }

    func image(for id: String) -> NSImage? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT image_data FROM clipboard_items WHERE id = ? AND type = 1 LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let blob = sqlite3_column_blob(stmt, 0) else { return nil }
        let size = Int(sqlite3_column_bytes(stmt, 0))
        let data = Data(bytes: blob, count: size)
        return NSImage(data: data)
    }

    func filteredItems(query: Query) -> [ClipboardItem] {
        var sql = """
        SELECT id, type, text, image_data, created_at, is_favorite, length(text)
        FROM clipboard_items
        WHERE 1 = 1
        """
        var bindings: [(OpaquePointer?, Int32) -> Void] = []

        let keyword = query.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            sql += " AND text LIKE ?"
            let value = "%\(keyword)%"
            bindings.append { stmt, i in sqlite3_bind_text(stmt, i, value, -1, SQLITE_TRANSIENT) }
        }

        if query.filterType != .all {
            sql += " AND type = ?"
            let typeRaw = query.filterType.rawValue
            bindings.append { stmt, i in sqlite3_bind_int(stmt, i, Int32(typeRaw)) }
        }

        if let threshold = thresholdDate(for: query.timeFilter) {
            sql += " AND created_at >= ?"
            let ts = threshold.timeIntervalSince1970
            bindings.append { stmt, i in sqlite3_bind_double(stmt, i, ts) }
        }

        sql += " ORDER BY is_favorite DESC, created_at DESC;"

        return fetch(sql: sql, binders: bindings, includeImageData: false)
    }

    private func finalizeChanges() {
        trim()
        loadAll()
        NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
    }

    private func thresholdDate(for filter: TimeFilter) -> Date? {
        let now = Date()
        let calendar = Calendar.current
        switch filter {
        case .all:
            return nil
        case .lastHour:
            return now.addingTimeInterval(-3600)
        case .today:
            return calendar.startOfDay(for: now)
        case .last7Days:
            return now.addingTimeInterval(-7 * 24 * 3600)
        case .last30Days:
            return now.addingTimeInterval(-30 * 24 * 3600)
        }
    }

    private func openDatabase() {
        do {
            try fileManager.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            print("Create db directory failed: \(error)")
        }
        if sqlite3_open(storeURL.path, &db) != SQLITE_OK {
            print("Open sqlite failed")
            db = nil
        }
    }

    private func closeDatabase() {
        if db != nil {
            sqlite3_close(db)
            db = nil
        }
    }

    deinit {
        closeDatabase()
    }

    private func createTablesIfNeeded() {
        execute(
            """
            CREATE TABLE IF NOT EXISTS clipboard_items (
                id TEXT PRIMARY KEY,
                type INTEGER NOT NULL,
                text TEXT,
                image_data BLOB,
                created_at REAL NOT NULL,
                is_favorite INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        execute("CREATE INDEX IF NOT EXISTS idx_clipboard_created_at ON clipboard_items(created_at DESC);")
        execute("CREATE INDEX IF NOT EXISTS idx_clipboard_type ON clipboard_items(type);")
        execute("CREATE INDEX IF NOT EXISTS idx_clipboard_favorite_created ON clipboard_items(is_favorite DESC, created_at DESC);")
    }

    private func execute(_ sql: String, bind: ((OpaquePointer?) -> Void)? = nil) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            if let msg = sqlite3_errmsg(db) {
                print("SQLite prepare failed: \(String(cString: msg))")
            }
            return
        }
        bind?(stmt)
        if sqlite3_step(stmt) != SQLITE_DONE {
            if let msg = sqlite3_errmsg(db) {
                print("SQLite step failed: \(String(cString: msg))")
            }
        }
        sqlite3_finalize(stmt)
    }

    private func insert(_ item: ClipboardItem) {
        execute(
            """
            INSERT INTO clipboard_items (id, type, text, image_data, created_at, is_favorite)
            VALUES (?, ?, ?, ?, ?, ?);
            """,
            bind: { stmt in
                sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT)
                sqlite3_bind_int(stmt, 2, Int32(item.kind.rawValue))
                if let text = item.text {
                    sqlite3_bind_text(stmt, 3, text, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 3)
                }
                if let imageData = item.imageData {
                    imageData.withUnsafeBytes { ptr in
                        _ = sqlite3_bind_blob(stmt, 4, ptr.baseAddress, Int32(imageData.count), SQLITE_TRANSIENT)
                    }
                } else {
                    sqlite3_bind_null(stmt, 4)
                }
                sqlite3_bind_double(stmt, 5, item.date.timeIntervalSince1970)
                sqlite3_bind_int(stmt, 6, item.isFavorite ? 1 : 0)
            }
        )
    }

    private func removeExistingText(_ text: String) {
        execute(
            "DELETE FROM clipboard_items WHERE id IN (SELECT id FROM clipboard_items WHERE type = 0 AND text = ? LIMIT 1);",
            bind: { stmt in sqlite3_bind_text(stmt, 1, text, -1, SQLITE_TRANSIENT) }
        )
    }

    private func removeExistingImageData(_ imageData: Data) {
        execute(
            "DELETE FROM clipboard_items WHERE id IN (SELECT id FROM clipboard_items WHERE type = 1 AND image_data = ? LIMIT 1);",
            bind: { stmt in
                imageData.withUnsafeBytes { ptr in
                    _ = sqlite3_bind_blob(stmt, 1, ptr.baseAddress, Int32(imageData.count), SQLITE_TRANSIENT)
                }
            }
        )
    }

    private func trim() {
        execute(
            """
            DELETE FROM clipboard_items
            WHERE id IN (
                SELECT id
                FROM clipboard_items
                ORDER BY is_favorite DESC, created_at DESC
                LIMIT -1 OFFSET ?
            );
            """,
            bind: { stmt in
                sqlite3_bind_int(stmt, 1, Int32(self.maxItems))
            }
        )
    }

    private func loadAll() {
        items = fetch(
            sql: """
            SELECT id, type, text, image_data, created_at, is_favorite, length(text)
            FROM clipboard_items
            ORDER BY is_favorite DESC, created_at DESC;
            """,
            includeImageData: false
        )
    }

    private func fetch(
        sql: String,
        binders: [(OpaquePointer?, Int32) -> Void] = [],
        truncateText: Bool = true,
        includeImageData: Bool = true
    ) -> [ClipboardItem] {
        guard let db else { return [] }
        var effectiveSQL = sql
        if truncateText {
            effectiveSQL = effectiveSQL
                .replacingOccurrences(of: "SELECT id, type, text, image_data, created_at, is_favorite, length(text)", with: "SELECT id, type, substr(text, 1, \(Self.textPreviewFetchLimit)) AS text, image_data, created_at, is_favorite, length(text)")
                .replacingOccurrences(of: "SELECT id, type, text, image_data, created_at, is_favorite", with: "SELECT id, type, substr(text, 1, \(Self.textPreviewFetchLimit)) AS text, image_data, created_at, is_favorite")
        }
        if !includeImageData {
            effectiveSQL = effectiveSQL.replacingOccurrences(of: "image_data", with: "NULL AS image_data")
        }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, effectiveSQL, -1, &stmt, nil) == SQLITE_OK else {
            if let msg = sqlite3_errmsg(db) {
                print("SQLite query prepare failed: \(String(cString: msg))")
            }
            return []
        }
        for (idx, binder) in binders.enumerated() {
            binder(stmt, Int32(idx + 1))
        }
        var result: [ClipboardItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cId = sqlite3_column_text(stmt, 0) else { continue }
            let id = String(cString: cId)
            let typeRaw = sqlite3_column_int(stmt, 1)
            let text = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
            var imageData: Data?
            if let blob = sqlite3_column_blob(stmt, 3) {
                let size = Int(sqlite3_column_bytes(stmt, 3))
                imageData = Data(bytes: blob, count: size)
            }
            let createdAt = sqlite3_column_double(stmt, 4)
            let isFavorite = sqlite3_column_int(stmt, 5) == 1
            let textLength = Int(sqlite3_column_int(stmt, 6))

            if typeRaw == ClipboardItem.Kind.text.rawValue, let text {
                result.append(
                    ClipboardItem(
                        id: id,
                        text: text,
                        date: Date(timeIntervalSince1970: createdAt),
                        isFavorite: isFavorite,
                        textLength: textLength,
                        hasMoreText: textLength > text.count
                    )
                )
            } else if typeRaw == ClipboardItem.Kind.image.rawValue, let imageData {
                result.append(ClipboardItem(id: id, imageData: imageData, date: Date(timeIntervalSince1970: createdAt), isFavorite: isFavorite))
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
}

extension Notification.Name {
    static let clipboardUpdated = Notification.Name("clipboardUpdated")
}
