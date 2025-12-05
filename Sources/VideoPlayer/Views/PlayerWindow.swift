import SwiftUI
import AVKit
import AVFoundation

struct PlayerWindow: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var playerService = VideoPlayerService.shared
    @Environment(\.dismiss) private var dismiss
    
    let video: Video
    
    @State private var showControls = true
    @State private var hideControlsTask: Task<Void, Never>?
    @State private var isHovering = false
    
    var body: some View {
        ZStack {
            // Video Player View - AVPlayer embedded
            VideoPlayerView(player: playerService.player)
                .background(Color.black)
                .onAppear {
                    loadVideo()
                    // 창을 최전면으로
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .onDisappear {
                    savePosition()
                    playerService.stop()
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
                PlayerControlsOverlay(video: video) {
                    closePlayer()
                }
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
        
        // Left/Right arrows - 10초 이동
        if press.key == .leftArrow {
            playerService.seekRelative(-10)
            showControlsTemporarily()
            return .handled
        }
        if press.key == .rightArrow {
            playerService.seekRelative(10)
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
        if appState.currentVideoIndex < appState.videos.count - 1 {
            savePosition()
            appState.playNextVideo()
            if let nextVideo = appState.currentPlayingVideo {
                loadVideoFor(nextVideo)
            }
        }
    }
    
    private func playPrevious() {
        if appState.currentVideoIndex > 0 {
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

struct PlayerControlsOverlay: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var playerService = VideoPlayerService.shared
    
    let video: Video
    let onClose: () -> Void
    
    @State private var showSpeedMenu = false
    @State private var showSettingsMenu = false
    
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
                            if appState.currentVideoIndex > 0 {
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
                        .foregroundColor(appState.currentVideoIndex > 0 ? .white : .white.opacity(0.3))
                        .disabled(appState.currentVideoIndex <= 0)
                        
                        // -10s
                        Button {
                            playerService.seekRelative(-10)
                        } label: {
                            Image(systemName: "gobackward.10")
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
                        
                        // +10s
                        Button {
                            playerService.seekRelative(10)
                        } label: {
                            Image(systemName: "goforward.10")
                                .font(.system(size: 26))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.white)
                        
                        // Next
                        Button {
                            if appState.currentVideoIndex < appState.videos.count - 1 {
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
                        .foregroundColor(appState.currentVideoIndex < appState.videos.count - 1 ? .white : .white.opacity(0.3))
                        .disabled(appState.currentVideoIndex >= appState.videos.count - 1)
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
                                
                                Toggle(isOn: $appState.shuffleEnabled) {
                                    HStack {
                                        Image(systemName: "shuffle")
                                            .foregroundColor(appState.shuffleEnabled ? .accentColor : .secondary)
                                        Text("다음 영상 랜덤 재생")
                                    }
                                }
                                .toggleStyle(.switch)
                                .onChange(of: appState.shuffleEnabled) { _, newValue in
                                    if !newValue {
                                        appState.resetShuffleHistory()
                                    }
                                }
                            }
                            .padding()
                            .frame(width: 220)
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
