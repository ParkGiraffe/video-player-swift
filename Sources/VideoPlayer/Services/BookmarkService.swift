import Foundation

class BookmarkService {
    static let shared = BookmarkService()
    
    private let bookmarksKey = "FolderBookmarks"
    private var accessedURLs: [String: URL] = [:]
    
    private init() {}
    
    // Security-Scoped Bookmark 저장
    func saveBookmark(for url: URL) -> Bool {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            
            var bookmarks = getBookmarks()
            bookmarks[url.path] = bookmarkData
            
            UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
            print("✅ Bookmark saved for: \(url.path)")
            return true
        } catch {
            print("❌ Failed to save bookmark: \(error)")
            return false
        }
    }
    
    // Security-Scoped Bookmark 복원 및 접근 시작
    func startAccessingFolder(path: String) -> Bool {
        let bookmarks = getBookmarks()
        
        guard let bookmarkData = bookmarks[path] else {
            print("⚠️ No bookmark found for: \(path)")
            return false
        }
        
        do {
            var isStale = false
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                print("⚠️ Bookmark is stale, re-saving: \(path)")
                _ = saveBookmark(for: url)
            }
            
            if url.startAccessingSecurityScopedResource() {
                accessedURLs[path] = url
                print("✅ Started accessing: \(path)")
                return true
            } else {
                print("❌ Failed to start accessing: \(path)")
                return false
            }
        } catch {
            print("❌ Failed to resolve bookmark: \(error)")
            return false
        }
    }
    
    // 접근 종료
    func stopAccessingFolder(path: String) {
        if let url = accessedURLs[path] {
            url.stopAccessingSecurityScopedResource()
            accessedURLs.removeValue(forKey: path)
            print("🛑 Stopped accessing: \(path)")
        }
    }
    
    // Bookmark 삭제
    func removeBookmark(for path: String) {
        var bookmarks = getBookmarks()
        bookmarks.removeValue(forKey: path)
        UserDefaults.standard.set(bookmarks, forKey: bookmarksKey)
        stopAccessingFolder(path: path)
        print("🗑️ Bookmark removed for: \(path)")
    }
    
    // 모든 저장된 Bookmark 복원
    func restoreAllBookmarks() {
        let bookmarks = getBookmarks()
        print("🔄 Restoring \(bookmarks.count) bookmarks...")
        
        for (path, _) in bookmarks {
            _ = startAccessingFolder(path: path)
        }
    }
    
    // 모든 접근 종료
    func stopAllAccess() {
        for (path, _) in accessedURLs {
            stopAccessingFolder(path: path)
        }
    }
    
    private func getBookmarks() -> [String: Data] {
        return UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
    }
}

