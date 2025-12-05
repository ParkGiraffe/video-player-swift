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
    @Published var selectedSubfolderPath: String?  // 선택된 하위 폴더 경로
    @Published var selectedRootOnly: Bool = false  // <Root> 선택 시 true - 해당 폴더의 직접 영상만 표시
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
    @Published var shuffleEnabled: Bool = false
    private var playedVideoIds: Set<String> = []  // 랜덤 재생 시 이미 재생한 비디오 추적
    
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
            
            // 백그라운드에서 누락된 썸네일 생성
            Task.detached(priority: .background) {
                await self.generateMissingThumbnails()
            }
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
        
        // 백그라운드에서 썸네일 생성
        Task.detached(priority: .background) {
            await self.generateMissingThumbnails()
        }
    }
    
    /// 썸네일이 없는 비디오에 대해 썸네일 생성
    func generateMissingThumbnails() async {
        let videosWithoutThumbnails = database.getVideosWithoutThumbnails()
        
        guard !videosWithoutThumbnails.isEmpty else {
            print("✅ All videos have thumbnails")
            return
        }
        
        print("🖼️ Generating thumbnails for \(videosWithoutThumbnails.count) videos...")
        
        for video in videosWithoutThumbnails {
            if let thumbnailPath = await ThumbnailService.shared.generateThumbnail(
                for: video.path,
                videoId: video.id
            ) {
                database.updateVideoThumbnail(videoId: video.id, thumbnailPath: thumbnailPath)
            }
        }
        
        // 썸네일 생성 후 비디오 목록 새로고침
        await loadVideos()
        print("✅ Thumbnail generation complete")
    }
    
    // MARK: - Videos
    
    func loadVideos() async {
        isLoading = true
        
        print("🔍 Loading videos...")
        print("   Filter - Folder: \(selectedFolder?.path ?? "none")")
        print("   Filter - Subfolder: \(selectedSubfolderPath ?? "none")")
        print("   Filter - RootOnly: \(selectedRootOnly)")
        print("   Filter - Tag: \(selectedTag?.name ?? "none")")
        print("   Filter - Participant: \(selectedParticipant?.name ?? "none")")
        print("   Filter - Language: \(selectedLanguage?.name ?? "none")")
        print("   Filter - Search: \(searchQuery.isEmpty ? "none" : searchQuery)")
        
        // 하위 폴더 경로 또는 마운트 폴더 경로로 필터링
        let filterPath = selectedSubfolderPath ?? selectedFolder?.path
        
        // 기본적으로 모든 비디오 로드
        var allVideos = database.getVideos(
            folderPath: filterPath,
            searchQuery: searchQuery.isEmpty ? nil : searchQuery
        )
        
        // <Root> 필터: 해당 폴더에 직접 있는 영상만 표시
        if selectedRootOnly, let path = filterPath {
            allVideos = allVideos.filter { $0.folderPath == path }
            print("   📊 After rootOnly filter: \(allVideos.count)")
        }
        
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
    
    func deleteVideo(_ video: Video) {
        // 데이터베이스에서 삭제
        database.deleteVideo(video.id)
        
        // 현재 목록에서 제거
        videos.removeAll { $0.id == video.id }
        
        // 선택 해제
        if selectedVideo?.id == video.id {
            selectedVideo = nil
        }
    }
    
    func updateVideoThumbnail(videoId: String, thumbnailPath: String) {
        database.updateVideoThumbnail(videoId: videoId, thumbnailPath: thumbnailPath)
        
        // 현재 목록에서 해당 비디오 업데이트
        if let index = videos.firstIndex(where: { $0.id == videoId }) {
            var updatedVideo = videos[index]
            updatedVideo.thumbnailPath = thumbnailPath
            videos[index] = updatedVideo
        }
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
        if shuffleEnabled {
            playRandomVideo()
        } else {
            guard currentVideoIndex < videos.count - 1 else { return }
            currentVideoIndex += 1
            currentPlayingVideo = videos[currentVideoIndex]
        }
    }
    
    func playPreviousVideo() {
        guard currentVideoIndex > 0 else { return }
        currentVideoIndex -= 1
        currentPlayingVideo = videos[currentVideoIndex]
    }
    
    func playRandomVideo() {
        guard videos.count > 1 else { return }
        
        // 현재 비디오를 재생 기록에 추가
        if let currentId = currentPlayingVideo?.id {
            playedVideoIds.insert(currentId)
        }
        
        // 아직 재생하지 않은 비디오 필터링
        let unplayedVideos = videos.filter { !playedVideoIds.contains($0.id) }
        
        // 모든 비디오를 재생했으면 기록 초기화
        let availableVideos = unplayedVideos.isEmpty ? videos : unplayedVideos
        if unplayedVideos.isEmpty {
            playedVideoIds.removeAll()
        }
        
        // 현재 비디오 제외하고 랜덤 선택
        let candidateVideos = availableVideos.filter { $0.id != currentPlayingVideo?.id }
        
        if let randomVideo = candidateVideos.randomElement() {
            currentVideoIndex = videos.firstIndex(where: { $0.id == randomVideo.id }) ?? 0
            currentPlayingVideo = randomVideo
        }
    }
    
    func resetShuffleHistory() {
        playedVideoIds.removeAll()
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
        selectedSubfolderPath = nil
        selectedRootOnly = false
        selectedTag = nil
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByFolder(_ folder: MountedFolder?) {
        selectedFolder = folder
        selectedSubfolderPath = nil
        selectedRootOnly = false
        selectedTag = nil
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterBySubfolder(_ folder: MountedFolder, subfolderPath: String?, rootOnly: Bool = false) {
        selectedFolder = folder
        selectedSubfolderPath = subfolderPath
        selectedRootOnly = rootOnly
        selectedTag = nil
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    /// 마운트된 폴더 내 모든 비디오 반환 (필터 없이)
    func allVideosInFolder(_ folder: MountedFolder) -> [Video] {
        return database.getVideos(folderPath: folder.path, searchQuery: nil)
    }
    
    func filterByTag(_ tag: Tag) {
        selectedTag = tag
        selectedFolder = nil
        selectedSubfolderPath = nil
        selectedRootOnly = false
        selectedParticipant = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByParticipant(_ participant: Participant) {
        selectedParticipant = participant
        selectedFolder = nil
        selectedSubfolderPath = nil
        selectedRootOnly = false
        selectedTag = nil
        selectedLanguage = nil
        Task { await loadVideos() }
    }
    
    func filterByLanguage(_ language: Language) {
        selectedLanguage = language
        selectedFolder = nil
        selectedSubfolderPath = nil
        selectedRootOnly = false
        selectedTag = nil
        selectedParticipant = nil
        Task { await loadVideos() }
    }
    
    func search(_ query: String) {
        searchQuery = query
        Task { await loadVideos() }
    }
}
