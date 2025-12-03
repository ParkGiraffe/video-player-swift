import Foundation

struct Video: Identifiable, Hashable, Codable {
    let id: String
    let path: String
    let filename: String
    let folderPath: String
    let size: Int64
    let createdAt: Date
    var thumbnailPath: String?
    
    init(id: String = UUID().uuidString, path: String, filename: String, folderPath: String, size: Int64, createdAt: Date = Date(), thumbnailPath: String? = nil) {
        self.id = id
        self.path = path
        self.filename = filename
        self.folderPath = folderPath
        self.size = size
        self.createdAt = createdAt
        self.thumbnailPath = thumbnailPath
    }
    
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}

struct MountedFolder: Identifiable, Hashable, Codable {
    let id: String
    let path: String
    let name: String
    let createdAt: Date
    var scanDepth: Int
    
    init(id: String = UUID().uuidString, path: String, name: String, createdAt: Date = Date(), scanDepth: Int = 2) {
        self.id = id
        self.path = path
        self.name = name
        self.createdAt = createdAt
        self.scanDepth = scanDepth
    }
}

struct Tag: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var color: String
    
    init(id: String = UUID().uuidString, name: String, color: String = "#6366f1") {
        self.id = id
        self.name = name
        self.color = color
    }
}

struct Participant: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    
    init(id: String = UUID().uuidString, name: String) {
        self.id = id
        self.name = name
    }
}

struct Language: Identifiable, Hashable, Codable {
    let id: String
    var code: String
    var name: String
    
    init(id: String = UUID().uuidString, code: String, name: String) {
        self.id = id
        self.code = code
        self.name = name
    }
}

