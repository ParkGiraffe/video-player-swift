import SwiftUI
import Combine

@MainActor
class AppState: ObservableObject {
    // Data
    @Published var videos: [Video] = []
    @Published var mountedFolders: [MountedFolder] = []
    @Published var tags: [Tag] = []
    @Published var participants: [Participant] = []
    @Published var languages: [Language] = []
    
    // Video mappings (cached)
    @Published private var videoTags: [String: Set<String>] = [:]
    @Published private var videoParticipants: [String: Set<String>] = [:]
    @Published private var videoLanguages: [String: Set<String>] = [:]
    
    // UI State
    @Published var selectedVideo: Video?
    @Published var selectedFolder: MountedFolder?
    @Published var selectedTag: Tag?
    @Published var selectedParticipant: Participant?
    @Published var selectedLanguage: Language?
    @Published var searchQuery: String = ""
    @Published var viewMode: ViewMode = .grid
    @Published var isLoading: Bool = false
    @Published var isScanningFolder: String?
    
    // Player State
    @Published var isPlayerOpen: Bool = false
    @Published var currentPlayingVideo: Video?
    @Published var currentVideoIndex: Int = 0
    
    // Services
    private let database = DatabaseService.shared
    private let scanner = FileScanner()
    
    enum ViewMode: String, CaseIterable {
        case grid = "Grid"
        case list = "List"
    }
    
    init() {
        loadData()
    }
    
    func loadData() {
        Task {
            await loadMountedFolders()
            await loadVideos()
            await loadTags()
            await loadParticipants()
            await loadLanguages()
            await loadVideoMappings()
        }
    }
    
    // MARK: - Folders
    
    func loadMountedFolders() async {
        mountedFolders = database.getMountedFolders()
    }
    
    func addMountedFolder(path: String) async {
        let name = (path as NSString).lastPathComponent
        let folder = MountedFolder(path: path, name: name)
        database.addMountedFolder(folder)
        await loadMountedFolders()
        await scanFolder(folder)
    }
    
    func removeMountedFolder(_ folder: MountedFolder) {
        database.removeMountedFolder(folder.id)
        database.deleteVideosInFolder(folder.path)
        
        // 북마크도 삭제
        BookmarkService.shared.removeBookmark(for: folder.path)
        
        Task {
            await loadMountedFolders()
            await loadVideos()
        }
    }
    
    func updateFolderScanDepth(_ folder: MountedFolder, depth: Int) {
        database.updateMountedFolderScanDepth(folderId: folder.id, depth: depth)
        Task {
            await loadMountedFolders()
        }
    }
    
    func scanFolder(_ folder: MountedFolder) async {
        isScanningFolder = folder.path
        
        // 북마크로 접근 권한 확보 시도
        _ = BookmarkService.shared.startAccessingFolder(path: folder.path)
        
        database.deleteVideosInFolder(folder.path)
        
        let scannedVideos = await scanner.scanFolder(path: folder.path, maxDepth: folder.scanDepth)
        
        print("📊 Saving \(scannedVideos.count) videos to database...")
        
        for video in scannedVideos {
            database.addVideo(video)
        }
        
        await loadVideos()
        isScanningFolder = nil
        
        print("📊 Total videos in database after scan: \(videos.count)")
    }
    
    // MARK: - Videos
    
    func loadVideos() async {
        isLoading = true
        
        print("🔍 Loading videos...")
        print("   Filter - Folder: \(selectedFolder?.path ?? "none")")
        print("   Filter - Tag: \(selectedTag?.name ?? "none")")
        print("   Filter - Participant: \(selectedParticipant?.name ?? "none")")
        print("   Filter - Language: \(selectedLanguage?.name ?? "none")")
        print("   Filter - Search: \(searchQuery.isEmpty ? "none" : searchQuery)")
        
        // 기본적으로 모든 비디오 로드
        var allVideos = database.getVideos(
            folderPath: selectedFolder?.path,
            searchQuery: searchQuery.isEmpty ? nil : searchQuery
        )
        
        print("   📊 Videos from DB: \(allVideos.count)")
        
        // 태그 필터링
        if let tag = selectedTag {
            let tagVideoIds = videoTags.filter { $0.value.contains(tag.id) }.map { $0.key }
            allVideos = allVideos.filter { tagVideoIds.contains($0.id) }
            print("   📊 After tag filter: \(allVideos.count)")
        }
        
        // 참가자 필터링
        if let participant = selectedParticipant {
            let participantVideoIds = videoParticipants.filter { $0.value.contains(participant.id) }.map { $0.key }
            allVideos = allVideos.filter { participantVideoIds.contains($0.id) }
            print("   📊 After participant filter: \(allVideos.count)")
        }
        
        // 언어 필터링
        if let language = selectedLanguage {
            let languageVideoIds = videoLanguages.filter { $0.value.contains(language.id) }.map { $0.key }
            allVideos = allVideos.filter { languageVideoIds.contains($0.id) }
            print("   📊 After language filter: \(allVideos.count)")
        }
        
        videos = allVideos
        isLoading = false
        
        print("✅ Loaded \(videos.count) videos")
    }
    
    func selectVideo(_ video: Video?) {
        selectedVideo = video
    }
    
    func playVideo(_ video: Video) {
        currentPlayingVideo = video
        currentVideoIndex = videos.firstIndex(where: { $0.id == video.id }) ?? 0
        isPlayerOpen = true
    }
    
    func openPlayer(video: Video) {
        playVideo(video)
    }
    
    func closePlayer() {
        isPlayerOpen = false
        currentPlayingVideo = nil
    }
    
    func playNextVideo() {
        guard currentVideoIndex < videos.count - 1 else { return }
        currentVideoIndex += 1
        currentPlayingVideo = videos[currentVideoIndex]
    }
    
    func playPreviousVideo() {
        guard currentVideoIndex > 0 else { return }
        currentVideoIndex -= 1
        currentPlayingVideo = videos[currentVideoIndex]
    }
    
    // MARK: - Tags
    
    func loadTags() async {
        tags = database.getTags()
    }
    
    func createTag(name: String, color: String) {
        let tag = Tag(name: name, color: color)
        database.addTag(tag)
        Task { await loadTags() }
    }
    
    func deleteTag(_ tag: Tag) {
        database.deleteTag(tag.id)
        for (videoId, tagIds) in videoTags {
            if tagIds.contains(tag.id) {
                videoTags[videoId]?.remove(tag.id)
            }
        }
        if selectedTag?.id == tag.id {
            selectedTag = nil
        }
        Task { await loadTags() }
    }
    
    func isTagAssignedToVideo(tag: Tag, video: Video) -> Bool {
        return videoTags[video.id]?.contains(tag.id) ?? false
    }
    
    func assignTagToVideo(tag: Tag, video: Video) {
        database.assignTagToVideo(tagId: tag.id, videoId: video.id)
        if videoTags[video.id] == nil {
            videoTags[video.id] = []
        }
        videoTags[video.id]?.insert(tag.id)
    }
    
    func removeTagFromVideo(tag: Tag, video: Video) {
        database.removeTagFromVideo(tagId: tag.id, videoId: video.id)
        videoTags[video.id]?.remove(tag.id)
    }
    
    func getVideoCountForTag(_ tag: Tag) -> Int {
        return videoTags.filter { $0.value.contains(tag.id) }.count
    }
    
    // MARK: - Participants
    
    func loadParticipants() async {
        participants = database.getParticipants()
    }
    
    func createParticipant(name: String) {
        let participant = Participant(name: name)
        database.addParticipant(participant)
        Task { await loadParticipants() }
    }
    
    func createParticipantAndAssign(name: String, video: Video) {
        let participant = Participant(name: name)
        database.addParticipant(participant)
        database.assignParticipantToVideo(participantId: participant.id, videoId: video.id)
        
        if videoParticipants[video.id] == nil {
            videoParticipants[video.id] = []
        }
        videoParticipants[video.id]?.insert(participant.id)
        
        Task { await loadParticipants() }
    }
    
    func deleteParticipant(_ participant: Participant) {
        database.deleteParticipant(participant.id)
        for (videoId, participantIds) in videoParticipants {
            if participantIds.contains(participant.id) {
                videoParticipants[videoId]?.remove(participant.id)
            }
        }
        if selectedParticipant?.id == participant.id {
            selectedParticipant = nil
        }
        Task { await loadParticipants() }
    }
    
    func isParticipantAssignedToVideo(participant: Participant, video: Video) -> Bool {
        return videoParticipants[video.id]?.contains(participant.id) ?? false
    }
    
    func assignParticipantToVideo(participant: Participant, video: Video) {
        database.assignParticipantToVideo(participantId: participant.id, videoId: video.id)
        if videoParticipants[video.id] == nil {
            videoParticipants[video.id] = []
        }
        videoParticipants[video.id]?.insert(participant.id)
    }
    
    func removeParticipantFromVideo(participant: Participant, video: Video) {
        database.removeParticipantFromVideo(participantId: participant.id, videoId: video.id)
        videoParticipants[video.id]?.remove(participant.id)
    }
    
    func getVideoCountForParticipant(_ participant: Participant) -> Int {
        return videoParticipants.filter { $0.value.contains(participant.id) }.count
    }
    
    // MARK: - Languages
    
    func loadLanguages() async {
        languages = database.getLanguages()
    }
    
    func createLanguage(code: String, name: String) {
        let language = Language(code: code, name: name)
        database.addLanguage(language)
        Task { await loadLanguages() }
    }
    
    func deleteLanguage(_ language: Language) {
        database.deleteLanguage(language.id)
        for (videoId, languageIds) in videoLanguages {
            if languageIds.contains(language.id) {
                videoLanguages[videoId]?.remove(language.id)
            }
        }
        if selectedLanguage?.id == language.id {
            selectedLanguage = nil
        }
        Task { await loadLanguages() }
    }
    
    func isLanguageAssignedToVideo(language: Language, video: Video) -> Bool {
        return videoLanguages[video.id]?.contains(language.id) ?? false
    }
    
    func assignLanguageToVideo(language: Language, video: Video) {
        database.assignLanguageToVideo(languageId: language.id, videoId: video.id)
        if videoLanguages[video.id] == nil {
            videoLanguages[video.id] = []
        }
        videoLanguages[video.id]?.insert(language.id)
    }
    
    func removeLanguageFromVideo(language: Language, video: Video) {
        database.removeLanguageFromVideo(languageId: language.id, videoId: video.id)
        videoLanguages[video.id]?.remove(language.id)
    }
    
    func getVideoCountForLanguage(_ language: Language) -> Int {
        return videoLanguages.filter { $0.value.contains(language.id) }.count
    }
    
    // MARK: - Video Mappings
    
    func loadVideoMappings() async {
        videoTags = database.getAllVideoTags()
        videoParticipants = database.getAllVideoParticipants()
        videoLanguages = database.getAllVideoLanguages()
    }
    
    // MARK: - Filtering
    
    func clearFilters() {
        selectedFolder = nil
        selectedTag = nil
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByFolder(_ folder: MountedFolder?) {
        selectedFolder = folder
        selectedTag = nil
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByTag(_ tag: Tag) {
        selectedTag = tag
        selectedFolder = nil
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByParticipant(_ participant: Participant) {
        selectedParticipant = participant
        selectedFolder = nil
        selectedTag = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByLanguage(_ language: Language) {
        selectedLanguage = language
        selectedFolder = nil
        selectedTag = nil
        selectedParticipant = nil
        Task { await loadVideos() }
    }
    
    func search(_ query: String) {
        searchQuery = query
        Task { await loadVideos() }
    }
}
