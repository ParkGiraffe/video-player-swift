import Foundation
import SQLite

class DatabaseService {
    static let shared = DatabaseService()
    
    private var db: Connection?
    
    // Tables
    private let videos = Table("videos")
    private let mountedFolders = Table("mounted_folders")
    private let tags = Table("tags")
    private let participants = Table("participants")
    private let languages = Table("languages")
    private let videoTags = Table("video_tags")
    private let videoParticipants = Table("video_participants")
    private let videoLanguages = Table("video_languages")
    private let playbackPositions = Table("playback_positions")
    
    // Columns
    private let id = Expression<String>("id")
    private let path = Expression<String>("path")
    private let filename = Expression<String>("filename")
    private let folderPath = Expression<String>("folder_path")
    private let size = Expression<Int64>("size")
    private let createdAt = Expression<String>("created_at")
    private let thumbnailPath = Expression<String?>("thumbnail_path")
    private let name = Expression<String>("name")
    private let color = Expression<String>("color")
    private let code = Expression<String>("code")
    private let scanDepth = Expression<Int>("scan_depth")
    private let videoId = Expression<String>("video_id")
    private let tagId = Expression<String>("tag_id")
    private let participantId = Expression<String>("participant_id")
    private let languageId = Expression<String>("language_id")
    private let position = Expression<Double>("position")
    
    private init() {
        setupDatabase()
    }
    
    private func setupDatabase() {
        do {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let appFolder = appSupport.appendingPathComponent("VideoPlayer")
            
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            
            let dbPath = appFolder.appendingPathComponent("database.sqlite")
            db = try Connection(dbPath.path)
            
            createTables()
            
            print("Database initialized at: \(dbPath.path)")
        } catch {
            print("Database error: \(error)")
        }
    }
    
    private func createTables() {
        guard let db = db else { return }
        
        do {
            // Videos table
            try db.run(videos.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(path, unique: true)
                t.column(filename)
                t.column(folderPath)
                t.column(size)
                t.column(createdAt)
                t.column(thumbnailPath)
            })
            
            // Mounted folders table
            try db.run(mountedFolders.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(path, unique: true)
                t.column(name)
                t.column(createdAt)
                t.column(scanDepth, defaultValue: 2)
            })
            
            // Tags table
            try db.run(tags.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(name)
                t.column(color)
            })
            
            // Participants table
            try db.run(participants.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(name)
            })
            
            // Languages table
            try db.run(languages.create(ifNotExists: true) { t in
                t.column(id, primaryKey: true)
                t.column(code)
                t.column(name)
            })
            
            // Junction tables
            try db.run(videoTags.create(ifNotExists: true) { t in
                t.column(videoId)
                t.column(tagId)
                t.primaryKey(videoId, tagId)
            })
            
            try db.run(videoParticipants.create(ifNotExists: true) { t in
                t.column(videoId)
                t.column(participantId)
                t.primaryKey(videoId, participantId)
            })
            
            try db.run(videoLanguages.create(ifNotExists: true) { t in
                t.column(videoId)
                t.column(languageId)
                t.primaryKey(videoId, languageId)
            })
            
            // Playback positions
            try db.run(playbackPositions.create(ifNotExists: true) { t in
                t.column(videoId, primaryKey: true)
                t.column(position)
            })
            
        } catch {
            print("Failed to create tables: \(error)")
        }
    }
    
    // MARK: - Videos
    
    private let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()
    
    func addVideo(_ video: Video) {
        guard let db = db else { return }
        
        do {
            try db.run(videos.insert(or: .replace,
                id <- video.id,
                path <- video.path,
                filename <- video.filename,
                folderPath <- video.folderPath,
                size <- video.size,
                createdAt <- dateFormatter.string(from: video.createdAt),
                thumbnailPath <- video.thumbnailPath
            ))
        } catch {
            print("Failed to add video: \(error)")
        }
    }
    
    func getVideos(folderPath filterPath: String? = nil, searchQuery: String? = nil) -> [Video] {
        guard let db = db else { 
            print("❌ Database connection is nil!")
            return [] 
        }
        
        var query = videos
        
        if let path = filterPath {
            // folderPath 또는 path가 해당 경로로 시작하는 비디오를 찾음
            query = query.filter(self.path.like("\(path)%") || self.folderPath.like("\(path)%"))
            print("   🔎 DB filter by path: \(path)%")
        }
        
        if let search = searchQuery {
            query = query.filter(filename.like("%\(search)%"))
            print("   🔎 DB filter by search: %\(search)%")
        }
        
        query = query.order(filename.asc)
        
        do {
            let results = try db.prepare(query).map { row in
                Video(
                    id: row[id],
                    path: row[self.path],
                    filename: row[filename],
                    folderPath: row[self.folderPath],
                    size: row[size],
                    createdAt: dateFormatter.date(from: row[createdAt]) ?? Date(),
                    thumbnailPath: row[thumbnailPath]
                )
            }
            print("   📊 DB returned \(results.count) videos")
            return results
        } catch {
            print("❌ Failed to get videos: \(error)")
            return []
        }
    }
    
    // 전체 비디오 수 확인용 (디버그)
    func getTotalVideoCount() -> Int {
        guard let db = db else { return 0 }
        
        do {
            return try db.scalar(videos.count)
        } catch {
            print("❌ Failed to count videos: \(error)")
            return 0
        }
    }
    
    func deleteVideo(_ videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videos.filter(id == videoId).delete())
            // Also delete related mappings
            try db.run(videoTags.filter(self.videoId == videoId).delete())
            try db.run(videoParticipants.filter(self.videoId == videoId).delete())
            try db.run(videoLanguages.filter(self.videoId == videoId).delete())
        } catch {
            print("Failed to delete video: \(error)")
        }
    }
    
    func deleteVideosInFolder(_ folderPath: String) {
        guard let db = db else { return }
        
        do {
            // Get video IDs first
            let videosToDelete = videos.filter(self.folderPath.like("\(folderPath)%"))
            let videoIds = try db.prepare(videosToDelete.select(id)).map { $0[id] }
            
            // Delete related mappings
            for vid in videoIds {
                try db.run(videoTags.filter(self.videoId == vid).delete())
                try db.run(videoParticipants.filter(self.videoId == vid).delete())
                try db.run(videoLanguages.filter(self.videoId == vid).delete())
            }
            
            // Delete videos
            try db.run(videosToDelete.delete())
        } catch {
            print("Failed to delete videos in folder: \(error)")
        }
    }
    
    // MARK: - Mounted Folders
    
    func addMountedFolder(_ folder: MountedFolder) {
        guard let db = db else { return }
        
        do {
            try db.run(mountedFolders.insert(or: .replace,
                id <- folder.id,
                path <- folder.path,
                name <- folder.name,
                createdAt <- dateFormatter.string(from: folder.createdAt),
                scanDepth <- folder.scanDepth
            ))
        } catch {
            print("Failed to add mounted folder: \(error)")
        }
    }
    
    func getMountedFolders() -> [MountedFolder] {
        guard let db = db else { return [] }
        
        do {
            return try db.prepare(mountedFolders).map { row in
                MountedFolder(
                    id: row[id],
                    path: row[path],
                    name: row[name],
                    createdAt: dateFormatter.date(from: row[createdAt]) ?? Date(),
                    scanDepth: row[scanDepth]
                )
            }
        } catch {
            print("Failed to get mounted folders: \(error)")
            return []
        }
    }
    
    func removeMountedFolder(_ folderId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(mountedFolders.filter(id == folderId).delete())
        } catch {
            print("Failed to remove mounted folder: \(error)")
        }
    }
    
    func updateMountedFolderScanDepth(folderId: String, depth: Int) {
        guard let db = db else { return }
        
        do {
            try db.run(mountedFolders.filter(id == folderId).update(scanDepth <- depth))
        } catch {
            print("Failed to update scan depth: \(error)")
        }
    }
    
    // MARK: - Tags
    
    func addTag(_ tag: Tag) {
        guard let db = db else { return }
        
        do {
            try db.run(tags.insert(or: .replace,
                id <- tag.id,
                name <- tag.name,
                color <- tag.color
            ))
        } catch {
            print("Failed to add tag: \(error)")
        }
    }
    
    func getTags() -> [Tag] {
        guard let db = db else { return [] }
        
        do {
            return try db.prepare(tags).map { row in
                Tag(
                    id: row[id],
                    name: row[name],
                    color: row[color]
                )
            }
        } catch {
            print("Failed to get tags: \(error)")
            return []
        }
    }
    
    func deleteTag(_ tagId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(tags.filter(id == tagId).delete())
            try db.run(videoTags.filter(self.tagId == tagId).delete())
        } catch {
            print("Failed to delete tag: \(error)")
        }
    }
    
    // MARK: - Tag Assignment
    
    func assignTagToVideo(tagId: String, videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videoTags.insert(or: .replace,
                self.videoId <- videoId,
                self.tagId <- tagId
            ))
        } catch {
            print("Failed to assign tag to video: \(error)")
        }
    }
    
    func removeTagFromVideo(tagId: String, videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videoTags.filter(self.videoId == videoId && self.tagId == tagId).delete())
        } catch {
            print("Failed to remove tag from video: \(error)")
        }
    }
    
    func getTagsForVideo(videoId: String) -> [String] {
        guard let db = db else { return [] }
        
        do {
            return try db.prepare(videoTags.filter(self.videoId == videoId)).map { row in
                row[tagId]
            }
        } catch {
            print("Failed to get tags for video: \(error)")
            return []
        }
    }
    
    func getAllVideoTags() -> [String: Set<String>] {
        guard let db = db else { return [:] }
        
        var result: [String: Set<String>] = [:]
        
        do {
            for row in try db.prepare(videoTags) {
                let vid = row[videoId]
                let tid = row[tagId]
                if result[vid] == nil {
                    result[vid] = []
                }
                result[vid]?.insert(tid)
            }
        } catch {
            print("Failed to get all video tags: \(error)")
        }
        
        return result
    }
    
    // MARK: - Participants
    
    func addParticipant(_ participant: Participant) {
        guard let db = db else { return }
        
        do {
            try db.run(participants.insert(or: .replace,
                id <- participant.id,
                name <- participant.name
            ))
        } catch {
            print("Failed to add participant: \(error)")
        }
    }
    
    func getParticipants() -> [Participant] {
        guard let db = db else { return [] }
        
        do {
            return try db.prepare(participants).map { row in
                Participant(
                    id: row[id],
                    name: row[name]
                )
            }
        } catch {
            print("Failed to get participants: \(error)")
            return []
        }
    }
    
    func deleteParticipant(_ participantId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(participants.filter(id == participantId).delete())
            try db.run(videoParticipants.filter(self.participantId == participantId).delete())
        } catch {
            print("Failed to delete participant: \(error)")
        }
    }
    
    // MARK: - Participant Assignment
    
    func assignParticipantToVideo(participantId: String, videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videoParticipants.insert(or: .replace,
                self.videoId <- videoId,
                self.participantId <- participantId
            ))
        } catch {
            print("Failed to assign participant to video: \(error)")
        }
    }
    
    func removeParticipantFromVideo(participantId: String, videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videoParticipants.filter(self.videoId == videoId && self.participantId == participantId).delete())
        } catch {
            print("Failed to remove participant from video: \(error)")
        }
    }
    
    func getParticipantsForVideo(videoId: String) -> [String] {
        guard let db = db else { return [] }
        
        do {
            return try db.prepare(videoParticipants.filter(self.videoId == videoId)).map { row in
                row[participantId]
            }
        } catch {
            print("Failed to get participants for video: \(error)")
            return []
        }
    }
    
    func getAllVideoParticipants() -> [String: Set<String>] {
        guard let db = db else { return [:] }
        
        var result: [String: Set<String>] = [:]
        
        do {
            for row in try db.prepare(videoParticipants) {
                let vid = row[videoId]
                let pid = row[participantId]
                if result[vid] == nil {
                    result[vid] = []
                }
                result[vid]?.insert(pid)
            }
        } catch {
            print("Failed to get all video participants: \(error)")
        }
        
        return result
    }
    
    // MARK: - Languages
    
    func addLanguage(_ language: Language) {
        guard let db = db else { return }
        
        do {
            try db.run(languages.insert(or: .replace,
                id <- language.id,
                code <- language.code,
                name <- language.name
            ))
        } catch {
            print("Failed to add language: \(error)")
        }
    }
    
    func getLanguages() -> [Language] {
        guard let db = db else { return [] }
        
        do {
            return try db.prepare(languages).map { row in
                Language(
                    id: row[id],
                    code: row[code],
                    name: row[name]
                )
            }
        } catch {
            print("Failed to get languages: \(error)")
            return []
        }
    }
    
    func deleteLanguage(_ languageId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(languages.filter(id == languageId).delete())
            try db.run(videoLanguages.filter(self.languageId == languageId).delete())
        } catch {
            print("Failed to delete language: \(error)")
        }
    }
    
    // MARK: - Language Assignment
    
    func assignLanguageToVideo(languageId: String, videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videoLanguages.insert(or: .replace,
                self.videoId <- videoId,
                self.languageId <- languageId
            ))
        } catch {
            print("Failed to assign language to video: \(error)")
        }
    }
    
    func removeLanguageFromVideo(languageId: String, videoId: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videoLanguages.filter(self.videoId == videoId && self.languageId == languageId).delete())
        } catch {
            print("Failed to remove language from video: \(error)")
        }
    }
    
    func getAllVideoLanguages() -> [String: Set<String>] {
        guard let db = db else { return [:] }
        
        var result: [String: Set<String>] = [:]
        
        do {
            for row in try db.prepare(videoLanguages) {
                let vid = row[videoId]
                let lid = row[languageId]
                if result[vid] == nil {
                    result[vid] = []
                }
                result[vid]?.insert(lid)
            }
        } catch {
            print("Failed to get all video languages: \(error)")
        }
        
        return result
    }
    
    // MARK: - Playback Position
    
    func savePlaybackPosition(videoId: String, position: Double) {
        guard let db = db else { return }
        
        do {
            try db.run(playbackPositions.insert(or: .replace,
                self.videoId <- videoId,
                self.position <- position
            ))
        } catch {
            print("Failed to save playback position: \(error)")
        }
    }
    
    func getPlaybackPosition(videoId: String) -> Double? {
        guard let db = db else { return nil }
        
        do {
            if let row = try db.pluck(playbackPositions.filter(self.videoId == videoId)) {
                return row[position]
            }
        } catch {
            print("Failed to get playback position: \(error)")
        }
        return nil
    }
    
    // MARK: - Thumbnail
    
    func updateVideoThumbnail(videoId: String, thumbnailPath: String) {
        guard let db = db else { return }
        
        do {
            try db.run(videos.filter(id == videoId).update(self.thumbnailPath <- thumbnailPath))
        } catch {
            print("Failed to update thumbnail path: \(error)")
        }
    }
    
    func getVideosWithoutThumbnails() -> [(id: String, path: String)] {
        guard let db = db else { return [] }
        
        do {
            let query = videos.filter(thumbnailPath == nil || thumbnailPath == "")
            return try db.prepare(query).map { row in
                (id: row[id], path: row[self.path])
            }
        } catch {
            print("Failed to get videos without thumbnails: \(error)")
            return []
        }
    }
}
