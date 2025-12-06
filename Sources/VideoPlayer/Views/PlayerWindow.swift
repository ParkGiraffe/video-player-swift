import SwiftUI
import AVKit
import AVFoundation

import Combine

struct PlayerWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var playerService = VideoPlayerService.shared
    @Environment(\.dismiss) private var dismiss
    
    let video: Video
    
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isHovering = false
    @State private var videoEndedCancellable: AnyCancellable?
    @State private var showDeleteConfirmation = false
    
    var body: some View {
        ZStack {
            // 플레이어 타입에 따라 다른 뷰 사용
            if playerService.currentPlayerType == .mpv {
                // MPV Player View (MKV, AVI 등)
                MPVPlayerViewWrapper()
                    .background(Color.black)
            } else {
                // AVPlayer View (MP4, MOV 등)
                VideoPlayerView(player: playerService.player)
                    .background(Color.black)
            }
            
            // onAppear/onDisappear는 ZStack 레벨에서 처리
            Color.clear
                .frame(width: 0, height: 0)
                .onAppear {
                    loadVideo()
                    setupVideoEndedObserver()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .onDisappear {
                    savePosition()
                    playerService.stop()
                    videoEndedCancellable?.cancel()
                }
            
            // 전체 화면 탭 영역 (컨트롤 제외)
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    playerService.togglePause()
                }
            
            // Error message
            if let error = playerService.error {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.yellow)
                    
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                }
                .padding()
                .background(Color.black.opacity(0.8))
                .cornerRadius(12)
            }
            
            // Controls overlay
            if showControls && playerService.error == nil {
                PlayerControlsOverlay(
                    video: video,
                    onClose: { closePlayer() },
                    onDelete: { deleteCurrentVideo() },
                    showDeleteConfirmation: $showDeleteConfirmation
                )
                .transition(.opacity)
            }
            
            // Center play button when paused
            if !playerService.isPlaying && playerService.isLoaded && playerService.error == nil {
                Button {
                    playerService.play()
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .padding(35)
                        .background(Color.black.opacity(0.5))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.black)
        .focusable()
        .onHover { hovering in
            isHovering = hovering
            if hovering {
                showControlsTemporarily()
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                showControlsTemporarily()
            case .ended:
                break
            }
        }
        .onKeyPress { press in
            handleKeyPress(press)
        }
    }
    
    private func loadVideo() {
        let position = DatabaseService.shared.getPlaybackPosition(videoId: video.id)
        playerService.loadFile(video.path)
        
        if let pos = position, pos > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playerService.seek(to: pos)
            }
        }
    }
    
    private func setupVideoEndedObserver() {
        videoEndedCancellable = playerService.videoEndedSubject
            .receive(on: DispatchQueue.main)
            .sink { [self] in
                handleVideoEnded()
            }
    }
    
    private func handleVideoEnded() {
        // 자동 재생이 활성화된 경우에만 다음 영상 재생
        guard appState.autoPlayNextEnabled else { return }
        
        // 셔플 모드인 경우 랜덤 재생
        if appState.shuffleEnabled {
            savePosition()
            appState.playRandomVideo()
            if let nextVideo = appState.currentPlayingVideo {
                loadVideoFor(nextVideo)
            }
        } else {
            // 다음 영상이 있는 경우에만 재생
            if appState.currentVideoIndex < appState.videos.count - 1 {
                savePosition()
                appState.playNextVideo()
                if let nextVideo = appState.currentPlayingVideo {
                    loadVideoFor(nextVideo)
                }
            }
        }
    }
    
    private func savePosition() {
        if playerService.currentTime > 0 {
            DatabaseService.shared.savePlaybackPosition(videoId: video.id, position: playerService.currentTime)
        }
    }
    
    private func showControlsTemporarily() {
        showControls = true
        hideControlsTask?.cancel()
        
        if playerService.isPlaying {
            hideControlsTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if !Task.isCancelled {
                    await MainActor.run {
                        withAnimation {
                            showControls = false
                        }
                    }
                }
            }
        }
    }
    
    private func handleKeyPress(_ press: KeyPress) -> KeyPress.Result {
        // Space bar - 재생/정지
        if press.key == .space {
            playerService.togglePause()
            return .handled
        }
        
        // Cmd + Backspace - 영상 삭제
        if press.modifiers.contains(.command) && press.key == .delete {
            showDeleteConfirmation = true
            return .handled
        }
        
        // Cmd + Left/Right - 이전/다음 영상
        if press.modifiers.contains(.command) {
            if press.key == .leftArrow {
                playPrevious()
                return .handled
            } else if press.key == .rightArrow {
                playNext()
                return .handled
            }
        }
        
        // Left/Right arrows - n초 이동 (설정된 초 단위)
        if press.key == .leftArrow {
            playerService.seekRelative(-appState.seekSeconds)
            showControlsTemporarily()
            return .handled
        }
        if press.key == .rightArrow {
            playerService.seekRelative(appState.seekSeconds)
            showControlsTemporarily()
            return .handled
        }
        
        // Up/Down arrows - 볼륨
        if press.key == .upArrow {
            playerService.setVolume(min(1, playerService.volume + 0.1))
            return .handled
        }
        if press.key == .downArrow {
            playerService.setVolume(max(0, playerService.volume - 0.1))
            return .handled
        }
        
        // M - 음소거
        if press.key == .init("m") {
            playerService.toggleMute()
            return .handled
        }
        
        // Escape - 닫기
        if press.key == .escape {
            closePlayer()
            return .handled
        }
        
        return .ignored
    }
    
    private func playNext() {
        let canPlay = appState.shuffleEnabled 
            ? appState.videos.count > 1 
            : appState.currentVideoIndex < appState.videos.count - 1
        
        if canPlay {
            savePosition()
            appState.playNextVideo()
            if let nextVideo = appState.currentPlayingVideo {
                loadVideoFor(nextVideo)
            }
        }
    }
    
    private func playPrevious() {
        let canPlay = appState.shuffleEnabled 
            ? appState.canPlayPreviousInShuffle 
            : appState.currentVideoIndex > 0
        
        if canPlay {
            savePosition()
            appState.playPreviousVideo()
            if let prevVideo = appState.currentPlayingVideo {
                loadVideoFor(prevVideo)
            }
        }
    }
    
    private func loadVideoFor(_ video: Video) {
        let position = DatabaseService.shared.getPlaybackPosition(videoId: video.id)
        playerService.loadFile(video.path)
        
        if let pos = position, pos > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playerService.seek(to: pos)
            }
        }
    }
    
    private func closePlayer() {
        savePosition()
        appState.closePlayer()
        dismiss()
    }
    
    private func deleteCurrentVideo() {
        guard let currentVideo = appState.currentPlayingVideo else { return }
        
        let fileManager = FileManager.default
        let videoURL = URL(fileURLWithPath: currentVideo.path)
        let videoName = videoURL.deletingPathExtension().lastPathComponent
        let videoFolder = videoURL.deletingLastPathComponent()
        
        // 🔥 삭제 전에 다음 영상을 미리 결정
        let nextVideo = determineNextVideoAfterDelete(currentVideo: currentVideo)
        
        // 1. 커스텀 썸네일 삭제 (영상과 같은 폴더에 같은 이름의 이미지 파일)
        let thumbnailExtensions = ["jpg", "jpeg", "png", "webp"]
        for ext in thumbnailExtensions {
            let thumbnailPath = videoFolder.appendingPathComponent("\(videoName).\(ext)")
            if fileManager.fileExists(atPath: thumbnailPath.path) {
                do {
                    try fileManager.removeItem(at: thumbnailPath)
                    print("✅ 커스텀 썸네일 삭제 완료: \(thumbnailPath.lastPathComponent)")
                } catch {
                    print("⚠️ 커스텀 썸네일 삭제 실패: \(error.localizedDescription)")
                }
            }
        }
        
        // 2. 앱에서 생성한 썸네일 삭제 (Application Support 폴더)
        Task {
            await ThumbnailService.shared.deleteThumbnail(videoId: currentVideo.id)
        }
        
        // 3. 영상 파일 삭제
        do {
            try fileManager.removeItem(atPath: currentVideo.path)
            print("✅ 영상 파일 삭제 완료: \(currentVideo.path)")
        } catch {
            print("❌ 영상 파일 삭제 실패: \(error.localizedDescription)")
            // 파일 삭제 실패해도 DB에서는 삭제 진행
        }
        
        // 앱 상태에서 삭제 (히스토리 처리 포함)
        appState.deleteVideoAndUpdateHistory(currentVideo)
        
        // 다음 영상 재생 또는 플레이어 닫기
        if let next = nextVideo {
            appState.currentPlayingVideo = next
            appState.currentVideoIndex = appState.videos.firstIndex(where: { $0.id == next.id }) ?? 0
            playerService.loadFile(next.path)
            
            // 셔플 모드에서 히스토리에 추가
            if appState.shuffleEnabled {
                appState.addToPlaybackHistory(videoId: next.id)
            }
        } else {
            // 재생할 영상이 없으면 플레이어 닫기
            closePlayer()
        }
    }
    
    /// 삭제 후 재생할 다음 영상 결정 (삭제 전에 호출)
    private func determineNextVideoAfterDelete(currentVideo: Video) -> Video? {
        let videos = appState.videos
        guard videos.count > 1 else { return nil }  // 삭제하면 0개가 됨
        
        if appState.shuffleEnabled {
            // 셔플 모드: 현재 영상 제외하고 랜덤 선택
            let candidates = videos.filter { $0.id != currentVideo.id }
            return candidates.randomElement()
        } else {
            // 순차 모드: 다음 영상 또는 이전 영상
            guard let currentIndex = videos.firstIndex(where: { $0.id == currentVideo.id }) else {
                return videos.first { $0.id != currentVideo.id }
            }
            
            if currentIndex < videos.count - 1 {
                // 다음 영상이 있으면 다음 영상
                return videos[currentIndex + 1]
            } else if currentIndex > 0 {
                // 마지막이면 이전 영상
                return videos[currentIndex - 1]
            }
            return nil
        }
    }
}

// AVPlayer를 SwiftUI에 임베딩하는 NSViewRepresentable
struct VideoPlayerView: NSViewRepresentable {
    let player: AVPlayer
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = player
        playerView.controlsStyle = .none
        playerView.showsFullScreenToggleButton = false
        playerView.allowsPictureInPicturePlayback = true
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

// MPV Player를 SwiftUI에 임베딩하는 NSViewRepresentable
struct MPVPlayerViewWrapper: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        // VideoPlayerService에서 MPV 뷰를 가져오거나 생성
        let playerService = VideoPlayerService.shared
        
        if let mpvView = playerService.mpvPlayerView {
            return mpvView
        } else {
            // 폴백: 빈 뷰 반환
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.black.cgColor
            return view
        }
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // MPV 뷰 업데이트
    }
}

struct PlayerControlsOverlay: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var playerService = VideoPlayerService.shared
    
    let video: Video
    let onClose: () -> Void
    let onDelete: () -> Void
    @Binding var showDeleteConfirmation: Bool
    
    @State private var showSpeedMenu = false
    @State private var showSettingsMenu = false
    
    // 셔플 모드에서는 히스토리 기반으로, 일반 모드에서는 인덱스 기반으로 판단
    private var canPlayPrevious: Bool {
        if appState.shuffleEnabled {
            return appState.canPlayPreviousInShuffle
        } else {
            return appState.currentVideoIndex > 0
        }
    }
    
    private var canPlayNext: Bool {
        if appState.shuffleEnabled {
            return appState.videos.count > 1  // 셔플 모드에서는 영상이 2개 이상이면 항상 가능
        } else {
            return appState.currentVideoIndex < appState.videos.count - 1
        }
    }
    
    // 건너뛰기 아이콘 (설정된 초에 따라)
    private var seekBackwardIcon: String {
        switch Int(appState.seekSeconds) {
        case 5: return "gobackward.5"
        case 10: return "gobackward.10"
        case 15: return "gobackward.15"
        case 30: return "gobackward.30"
        case 60: return "gobackward.60"
        default: return "gobackward.10"
        }
    }
    
    private var seekForwardIcon: String {
        switch Int(appState.seekSeconds) {
        case 5: return "goforward.5"
        case 10: return "goforward.10"
        case 15: return "goforward.15"
        case 30: return "goforward.30"
        case 60: return "goforward.60"
        default: return "goforward.10"
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(appState.currentPlayingVideo?.filename ?? video.filename)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text("\(appState.currentVideoIndex + 1) / \(appState.videos.count)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                        
                        if appState.shuffleEnabled {
                            HStack(spacing: 4) {
                                Image(systemName: "shuffle")
                                    .font(.system(size: 10))
                                Text("셔플")
                                    .font(.caption2)
                            }
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.2))
                            .cornerRadius(4)
                        }
                    }
                }
                
                Spacer()
                
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.7), Color.clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onTapGesture { } // 탭 이벤트 소비
            
            Spacer()
            
            // Bottom controls
            VStack(spacing: 16) {
                // Progress bar - 터치 영역 확대
                ProgressSlider(
                    value: Binding(
                        get: { playerService.currentTime },
                        set: { playerService.seek(to: $0) }
                    ),
                    total: playerService.duration
                )
                .frame(height: 30) // 터치 영역
                
                HStack(spacing: 20) {
                    // Left: Playback controls
                    HStack(spacing: 16) {
                        // Previous
                        Button {
                            if canPlayPrevious {
                                appState.playPreviousVideo()
                                if let video = appState.currentPlayingVideo {
                                    playerService.loadFile(video.path)
                                }
                            }
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(canPlayPrevious ? .white : .white.opacity(0.3))
                        .disabled(!canPlayPrevious)
                        
                        // -Ns (설정된 초만큼)
                        Button {
                            playerService.seekRelative(-appState.seekSeconds)
                        } label: {
                            Image(systemName: seekBackwardIcon)
                                .font(.system(size: 26))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        
                        // Play/Pause
                        Button {
                            playerService.togglePause()
                        } label: {
                            Image(systemName: playerService.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 32))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        
                        // +Ns (설정된 초만큼)
                        Button {
                            playerService.seekRelative(appState.seekSeconds)
                        } label: {
                            Image(systemName: seekForwardIcon)
                                .font(.system(size: 26))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        
                        // Next
                        Button {
                            if canPlayNext {
                                appState.playNextVideo()
                                if let video = appState.currentPlayingVideo {
                                    playerService.loadFile(video.path)
                                }
                            }
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.system(size: 22))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(canPlayNext ? .white : .white.opacity(0.3))
                        .disabled(!canPlayNext)
                    }
                    
                    // Time display
                    Text("\(formatTime(playerService.currentTime)) / \(formatTime(playerService.duration))")
                        .font(.system(size: 14, design: .monospaced))
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    // Right: Volume & Speed
                    HStack(spacing: 16) {
                        // Volume
                        HStack(spacing: 6) {
                            Button {
                                playerService.toggleMute()
                            } label: {
                                Image(systemName: playerService.isMuted ? "speaker.slash.fill" : volumeIcon)
                                    .font(.system(size: 20))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.white)
                            
                            // 볼륨 슬라이더 - 터치 영역 확대
                            VolumeSlider(
                                value: Binding(
                                    get: { Double(playerService.isMuted ? 0 : playerService.volume) },
                                    set: { playerService.setVolume(Float($0)) }
                                )
                            )
                            .frame(width: 80, height: 30)
                        }
                        
                        // Speed 버튼
                        Button {
                            showSpeedMenu.toggle()
                        } label: {
                            Text("\(Double(playerService.playbackSpeed), specifier: "%.2g")x")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSpeedMenu, arrowEdge: .top) {
                            VStack(spacing: 0) {
                                ForEach([0.5, 0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { speed in
                                    Button {
                                        playerService.setSpeed(Float(speed))
                                        showSpeedMenu = false
                                    } label: {
                                        HStack {
                                            if Double(playerService.playbackSpeed) == speed {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                            } else {
                                                Spacer().frame(width: 14)
                                            }
                                            Text("\(speed, specifier: "%.2g")x")
                                                .font(.system(size: 13))
                                            Spacer()
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Double(playerService.playbackSpeed) == speed ? Color.accentColor.opacity(0.2) : Color.clear)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .frame(width: 100)
                            .padding(.vertical, 4)
                        }
                        
                        // 설정 버튼
                        Button {
                            showSettingsMenu.toggle()
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18))
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .popover(isPresented: $showSettingsMenu, arrowEdge: .top) {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("재생 설정")
                                    .font(.headline)
                                    .padding(.bottom, 4)
                                
                                // 다음 영상 자동 재생
                                HStack {
                                    Image(systemName: "play.circle")
                                        .foregroundColor(appState.autoPlayNextEnabled ? .accentColor : .secondary)
                                        .frame(width: 20)
                                    Text("다음 영상 자동 재생")
                                    Spacer()
                                    Toggle("", isOn: $appState.autoPlayNextEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                }
                                
                                // 다음 영상 랜덤 재생
                                HStack {
                                    Image(systemName: "shuffle")
                                        .foregroundColor(appState.shuffleEnabled ? .accentColor : .secondary)
                                        .frame(width: 20)
                                    Text("다음 영상 랜덤 재생")
                                    Spacer()
                                    Toggle("", isOn: $appState.shuffleEnabled)
                                        .toggleStyle(.switch)
                                        .labelsHidden()
                                        .onChange(of: appState.shuffleEnabled) { _, newValue in
                                            if !newValue {
                                                appState.resetShuffleHistory()
                                            }
                                        }
                                }
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // 건너뛰기 초 설정
                                HStack {
                                    Image(systemName: "forward")
                                        .foregroundColor(.secondary)
                                        .frame(width: 20)
                                    Text("건너뛰기")
                                    Spacer()
                                    Picker("", selection: $appState.seekSeconds) {
                                        Text("5초").tag(5.0)
                                        Text("10초").tag(10.0)
                                        Text("15초").tag(15.0)
                                        Text("30초").tag(30.0)
                                        Text("60초").tag(60.0)
                                    }
                                    .pickerStyle(.menu)
                                    .labelsHidden()
                                    .frame(width: 80)
                                }
                                
                                Divider()
                                    .padding(.vertical, 4)
                                
                                // 영상 삭제 버튼 - 전체 너비 터치 영역
                                Button(role: .destructive) {
                                    showSettingsMenu = false
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        showDeleteConfirmation = true
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: "trash")
                                            .foregroundColor(.red)
                                            .frame(width: 20)
                                        Text("영상 삭제")
                                            .foregroundColor(.red)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                            .padding()
                            .frame(width: 250)
                        }
                        .alert("영상 삭제", isPresented: $showDeleteConfirmation) {
                            Button("취소", role: .cancel) { }
                            Button("삭제", role: .destructive) {
                                onDelete()
                            }
                            .keyboardShortcut(.defaultAction)
                        } message: {
                            Text("'\(appState.currentPlayingVideo?.filename ?? video.filename)' 파일을 삭제하시겠습니까?\n\n이 작업은 되돌릴 수 없습니다.")
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
            .background(
                LinearGradient(
                    colors: [Color.clear, Color.black.opacity(0.8)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .onTapGesture { } // 탭 이벤트 소비
        }
    }
    
    private var volumeIcon: String {
        if playerService.volume == 0 {
            return "speaker.fill"
        } else if playerService.volume < 0.5 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.2.fill"
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
    
}

// 프로그레스 슬라이더 - 큰 터치 영역
struct ProgressSlider: View {
    @Binding var value: Double
    let total: Double
    
    @State private var isDragging = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 큰 터치 영역 (투명)
                Rectangle()
                    .fill(Color.clear)
                
                // 보이는 슬라이더 (가운데 정렬)
                VStack {
                    Spacer()
                    ZStack(alignment: .leading) {
                        // Background
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: isDragging ? 8 : 5)
                        
                        // Progress
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: total > 0 ? geometry.size.width * (value / total) : 0, height: isDragging ? 8 : 5)
                    }
                    .cornerRadius(2.5)
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let percent = max(0, min(1, gesture.location.x / geometry.size.width))
                        value = percent * total
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
        }
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// 볼륨 슬라이더 - 큰 터치 영역
struct VolumeSlider: View {
    @Binding var value: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // 큰 터치 영역
                Rectangle()
                    .fill(Color.clear)
                
                // 보이는 슬라이더
                VStack {
                    Spacer()
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.3))
                            .frame(height: 4)
                        
                        Rectangle()
                            .fill(Color.accentColor)
                            .frame(width: geometry.size.width * value, height: 4)
                        
                        // 동그란 핸들
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                            .offset(x: geometry.size.width * value - 6)
                    }
                    Spacer()
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let percent = max(0, min(1, gesture.location.x / geometry.size.width))
                        value = percent
                    }
            )
        }
    }
}

#Preview {
    PlayerWindow(video: Video(
        path: "/test/video.mp4",
        filename: "test_video.mp4",
        folderPath: "/test",
        size: 1024 * 1024 * 100
    ))
    .environmentObject(AppState())
}
