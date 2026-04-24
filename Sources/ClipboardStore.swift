import Cocoa
import SQLite3

// MARK: - Store
class ClipboardStore {
    enum FilterType: Int {
        case all = -1
        case text = 0
        case image = 1
    }

    struct Query {
        let keyword: String
        let filterType: FilterType
        let favoritesOnly: Bool
        let favoriteFolder: String?
    }

    static let shared = ClipboardStore()
    private static let textPreviewFetchLimit = 600
    private(set) var items: [ClipboardItem] = []
    private let defaultMaxItems = 200
    private let minMaxItems = 10
    private let hardMaxItems = 5000
    private let maxItemsKey = "clipboard.maxItems"
    private let retentionDaysKey = "clipboard.retentionDays"
    static let retentionDayOptions: [Int?] = [1, 3, 5, 7, 15, 30, nil]
    private let fileManager = FileManager.default
    private let dbLock = NSRecursiveLock()
    private var db: OpaquePointer?

    private func notifyClipboardUpdated() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .clipboardUpdated, object: nil)
        }
    }

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

    var retentionDays: Int? {
        let raw = UserDefaults.standard.integer(forKey: retentionDaysKey)
        if raw <= 0 { return nil }
        return Self.retentionDayOptions.contains(raw) ? raw : nil
    }

    private init() {
        openDatabase()
        createTablesIfNeeded()
        applyRetentionPolicyLocked()
        loadAll()
    }

    func addText(_ text: String) {
        dbLock.lock()
        defer { dbLock.unlock() }
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        removeExistingText(cleaned)
        let item = ClipboardItem(text: cleaned)
        insert(item)
        finalizeChanges()
    }

    func addImage(_ image: NSImage) {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let imageData = ClipboardItem.makeImageData(from: image) else { return }
        addImageDataLocked(imageData)
    }

    func addImageData(_ imageData: Data) {
        dbLock.lock()
        defer { dbLock.unlock() }
        addImageDataLocked(imageData)
    }

    private func addImageDataLocked(_ imageData: Data) {
        removeExistingImageData(imageData)
        let item = ClipboardItem(imageData: imageData)
        insert(item)
        finalizeChanges()
    }

    func updateFavorite(id: String, isFavorite: Bool, folderName: String? = nil) {
        dbLock.lock()
        defer { dbLock.unlock() }

        let cleanedFolder = folderName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = (isFavorite && !(cleanedFolder ?? "").isEmpty) ? cleanedFolder : nil

        execute(
            "UPDATE clipboard_items SET is_favorite = ?, favorite_folder = ? WHERE id = ?;",
            bind: { stmt in
                sqlite3_bind_int(stmt, 1, isFavorite ? 1 : 0)
                if let folder {
                    sqlite3_bind_text(stmt, 2, folder, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 2)
                }
                sqlite3_bind_text(stmt, 3, id, -1, SQLITE_TRANSIENT)
            }
        )
        loadAll()
        notifyClipboardUpdated()
    }

    func toggleFavorite(id: String) {
        dbLock.lock()
        defer { dbLock.unlock() }
        let target = items.first(where: { $0.id == id })
        updateFavorite(
            id: id,
            isFavorite: !(target?.isFavorite ?? false),
            folderName: target?.favoriteFolder
        )
    }

    func clear() {
        dbLock.lock()
        defer { dbLock.unlock() }
        execute("DELETE FROM clipboard_items WHERE is_favorite = 0;")
        loadAll()
        notifyClipboardUpdated()
    }

    func setMaxItems(_ newValue: Int) {
        dbLock.lock()
        defer { dbLock.unlock() }
        let clamped = max(minMaxItems, min(newValue, hardMaxItems))
        UserDefaults.standard.set(clamped, forKey: maxItemsKey)
        trim()
        applyRetentionPolicyLocked()
        loadAll()
        notifyClipboardUpdated()
    }

    func setRetentionDays(_ days: Int?) {
        dbLock.lock()
        defer { dbLock.unlock() }
        if let days, Self.retentionDayOptions.contains(days) {
            UserDefaults.standard.set(days, forKey: retentionDaysKey)
        } else {
            UserDefaults.standard.removeObject(forKey: retentionDaysKey)
        }
        applyRetentionPolicyLocked()
        trim()
        loadAll()
        notifyClipboardUpdated()
    }

    func allFavoriteFolders() -> [String] {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return [] }

        var stmt: OpaquePointer?
        let sql = "SELECT DISTINCT favorite_folder FROM clipboard_items WHERE is_favorite = 1 AND favorite_folder IS NOT NULL AND length(trim(favorite_folder)) > 0 ORDER BY favorite_folder COLLATE NOCASE ASC;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(stmt) }

        var folders: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cText = sqlite3_column_text(stmt, 0) else { continue }
            folders.append(String(cString: cText))
        }
        return folders
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
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let attrs = try? fileManager.attributesOfItem(atPath: storeURL.path),
              let bytes = attrs[.size] as? Int64 else {
            return "0 B"
        }
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    func fullText(for id: String) -> String? {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return nil }
        var stmt: OpaquePointer?
        let sql = "SELECT text FROM clipboard_items WHERE id = ? AND type = 0 LIMIT 1;"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_bind_text(stmt, 1, id, -1, SQLITE_TRANSIENT)
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        guard let cText = sqlite3_column_text(stmt, 0) else { return nil }
        return String(cString: cText)
    }

    func image(for id: String) -> NSImage? {
        dbLock.lock()
        defer { dbLock.unlock() }
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
        dbLock.lock()
        defer { dbLock.unlock() }
        let built = buildQuerySQL(query: query)
        return fetch(sql: built.sql + " ORDER BY created_at DESC;", binders: built.binders)
    }

    func filteredItems(query: Query, limit: Int, offset: Int) -> [ClipboardItem] {
        dbLock.lock()
        defer { dbLock.unlock() }
        let safeLimit = max(1, limit)
        let safeOffset = max(0, offset)
        var built = buildQuerySQL(query: query)
        built.sql += " ORDER BY created_at DESC LIMIT ? OFFSET ?;"
        built.binders.append { stmt, i in sqlite3_bind_int(stmt, i, Int32(safeLimit)) }
        built.binders.append { stmt, i in sqlite3_bind_int(stmt, i, Int32(safeOffset)) }
        return fetch(sql: built.sql, binders: built.binders)
    }

    func filteredCount(query: Query) -> Int {
        dbLock.lock()
        defer { dbLock.unlock() }
        guard let db else { return 0 }
        let built = buildQuerySQL(query: query, selectClause: "SELECT COUNT(1)")
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, built.sql + ";", -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(stmt) }
        for (idx, binder) in built.binders.enumerated() {
            binder(stmt, Int32(idx + 1))
        }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(stmt, 0))
    }

    private func buildQuerySQL(
        query: Query,
        selectClause: String? = nil
    ) -> (sql: String, binders: [(OpaquePointer?, Int32) -> Void]) {
        let selectText = "substr(text, 1, \(Self.textPreviewFetchLimit)) AS text"
        var sql = selectClause ?? """
        SELECT id, type, \(selectText), NULL AS image_data, created_at, is_favorite, length(text), favorite_folder
        """
        sql += " FROM clipboard_items WHERE 1 = 1"
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

        if query.favoritesOnly {
            sql += " AND is_favorite = 1"
            if let folder = query.favoriteFolder {
                sql += " AND favorite_folder = ?"
                bindings.append { stmt, i in sqlite3_bind_text(stmt, i, folder, -1, SQLITE_TRANSIENT) }
            }
        }
        return (sql, bindings)
    }

    private func finalizeChanges() {
        applyRetentionPolicyLocked()
        trim()
        loadAll()
        notifyClipboardUpdated()
    }

    private func applyRetentionPolicyLocked() {
        guard let days = retentionDays else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400).timeIntervalSince1970
        execute(
            """
            DELETE FROM clipboard_items
            WHERE is_favorite = 0
              AND created_at < ?;
            """,
            bind: { stmt in
                sqlite3_bind_double(stmt, 1, cutoff)
            }
        )
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
                is_favorite INTEGER NOT NULL DEFAULT 0,
                favorite_folder TEXT
            );
            """
        )
        ensureFavoriteFolderColumn()
        execute("CREATE INDEX IF NOT EXISTS idx_clipboard_created_at ON clipboard_items(created_at DESC);")
        execute("CREATE INDEX IF NOT EXISTS idx_clipboard_type ON clipboard_items(type);")
        execute("CREATE INDEX IF NOT EXISTS idx_clipboard_favorite_created ON clipboard_items(is_favorite DESC, created_at DESC);")
    }

    private func ensureFavoriteFolderColumn() {
        guard !columnExists(table: "clipboard_items", column: "favorite_folder") else { return }
        execute("ALTER TABLE clipboard_items ADD COLUMN favorite_folder TEXT;")
    }

    private func columnExists(table: String, column: String) -> Bool {
        guard let db else { return false }
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let cName = sqlite3_column_text(stmt, 1) else { continue }
            if String(cString: cName) == column {
                return true
            }
        }
        return false
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
            INSERT INTO clipboard_items (id, type, text, image_data, created_at, is_favorite, favorite_folder)
            VALUES (?, ?, ?, ?, ?, ?, ?);
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
                if let folder = item.favoriteFolder {
                    sqlite3_bind_text(stmt, 7, folder, -1, SQLITE_TRANSIENT)
                } else {
                    sqlite3_bind_null(stmt, 7)
                }
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
                ORDER BY created_at DESC
                LIMIT -1 OFFSET ?
            );
            """,
            bind: { stmt in
                sqlite3_bind_int(stmt, 1, Int32(self.maxItems))
            }
        )
    }

    private func loadAll() {
        let selectText = "substr(text, 1, \(Self.textPreviewFetchLimit)) AS text"
        items = fetch(
            sql: """
            SELECT id, type, \(selectText), NULL AS image_data, created_at, is_favorite, length(text), favorite_folder
            FROM clipboard_items
            ORDER BY created_at DESC;
            """
        )
    }

    private func fetch(
        sql: String,
        binders: [(OpaquePointer?, Int32) -> Void] = []
    ) -> [ClipboardItem] {
        guard let db else { return [] }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
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
            let favoriteFolder = sqlite3_column_text(stmt, 7).map { String(cString: $0) }

            if typeRaw == ClipboardItem.Kind.text.rawValue, let text {
                result.append(
                    ClipboardItem(
                        id: id,
                        text: text,
                        date: Date(timeIntervalSince1970: createdAt),
                        isFavorite: isFavorite,
                        favoriteFolder: favoriteFolder,
                        textLength: textLength,
                        hasMoreText: textLength > text.count
                    )
                )
            } else if typeRaw == ClipboardItem.Kind.image.rawValue {
                if let imageData {
                    result.append(
                        ClipboardItem(
                            id: id,
                            imageData: imageData,
                            date: Date(timeIntervalSince1970: createdAt),
                            isFavorite: isFavorite,
                            favoriteFolder: favoriteFolder
                        )
                    )
                } else {
                    result.append(
                        ClipboardItem(
                            id: id,
                            imageDate: Date(timeIntervalSince1970: createdAt),
                            isFavorite: isFavorite,
                            favoriteFolder: favoriteFolder
                        )
                    )
                }
            }
        }
        sqlite3_finalize(stmt)
        return result
    }
}

extension Notification.Name {
    static let clipboardUpdated = Notification.Name("clipboardUpdated")
}
