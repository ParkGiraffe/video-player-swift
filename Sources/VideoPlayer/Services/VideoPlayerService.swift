import Foundation
import AVFoundation
import AVKit
import Combine

// 플레이어 타입
enum PlayerType {
    case avPlayer
    case mpv
}

class VideoPlayerService: ObservableObject {
    static let shared = VideoPlayerService()
    
    // AVPlayer (mp4, mov 등)
    let player = AVPlayer()
    
    // MPV Player View (mkv, avi 등)
    var mpvPlayerView: MPVPlayerView?
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Float = 1.0
    @Published var isMuted: Bool = false
    @Published var playbackSpeed: Float = 1.0
    @Published var isLoaded: Bool = false
    @Published var error: String?
    @Published var currentPlayerType: PlayerType = .avPlayer
    
    // 영상 종료 이벤트
    let videoEndedSubject = PassthroughSubject<Void, Never>()
    
    // MKV 등 AVPlayer에서 지원하지 않는 포맷
    private let mpvOnlyFormats = ["mkv", "avi", "wmv", "flv", "webm"]
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe playback status
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard self?.currentPlayerType == .avPlayer else { return }
                self?.isPlaying = status == .playing
            }
            .store(in: &cancellables)
        
        // Observe volume
        player.publisher(for: \.volume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vol in
                guard self?.currentPlayerType == .avPlayer else { return }
                self?.volume = vol
            }
            .store(in: &cancellables)
        
        // Observe mute
        player.publisher(for: \.isMuted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                guard self?.currentPlayerType == .avPlayer else { return }
                self?.isMuted = muted
            }
            .store(in: &cancellables)
        
        // Observe rate
        player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                guard self?.currentPlayerType == .avPlayer else { return }
                if rate != 0 {
                    self?.playbackSpeed = rate
                }
            }
            .store(in: &cancellables)
        
        // Playback finished notification
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.currentPlayerType == .avPlayer else { return }
                self?.isPlaying = false
                self?.videoEndedSubject.send()
            }
            .store(in: &cancellables)
    }
    
    // 포맷에 따라 사용할 플레이어 결정
    func getPlayerType(for path: String) -> PlayerType {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return mpvOnlyFormats.contains(ext) ? .mpv : .avPlayer
    }
    
    func loadFile(_ path: String) {
        error = nil
        isLoaded = false
        
        let playerType = getPlayerType(for: path)
        currentPlayerType = playerType
        
        if playerType == .mpv {
            loadWithMPV(path)
        } else {
            loadWithAVPlayer(path)
        }
    }
    
    private func loadWithAVPlayer(_ path: String) {
        // MPV 정리
        mpvPlayerView?.stop()
        
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)
        
        // Setup time observer
        removeTimeObserver()
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }
        
        // Get duration when ready
        playerItem.publisher(for: \.status)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                if status == .readyToPlay {
                    self?.duration = playerItem.duration.seconds
                    self?.isLoaded = true
                    self?.play()
                } else if status == .failed {
                    self?.error = playerItem.error?.localizedDescription ?? "재생할 수 없습니다"
                    self?.isLoaded = false
                }
            }
            .store(in: &cancellables)
    }
    
    private func loadWithMPV(_ path: String) {
        // AVPlayer 정리
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeTimeObserver()
        
        // MPV 플레이어 뷰가 없으면 생성
        if mpvPlayerView == nil {
            mpvPlayerView = MPVPlayerView(frame: NSRect(x: 0, y: 0, width: 800, height: 450), pixelFormat: nil)
        }
        
        guard let mpvView = mpvPlayerView else {
            error = "MPV 플레이어를 초기화할 수 없습니다."
            return
        }
        
        // MPV 콜백 설정
        mpvView.onTimeUpdate = { [weak self] time in
            DispatchQueue.main.async {
                self?.currentTime = time
            }
        }
        
        mpvView.onDurationUpdate = { [weak self] dur in
            DispatchQueue.main.async {
                self?.duration = dur
            }
        }
        
        mpvView.onPlaybackStateChange = { [weak self] playing in
            DispatchQueue.main.async {
                self?.isPlaying = playing
            }
        }
        
        mpvView.onLoadStateChange = { [weak self] loaded in
            DispatchQueue.main.async {
                self?.isLoaded = loaded
            }
        }
        
        mpvView.onError = { [weak self] errorMsg in
            DispatchQueue.main.async {
                self?.error = errorMsg
            }
        }
        
        mpvView.onEndOfFile = { [weak self] in
            DispatchQueue.main.async {
                self?.isPlaying = false
                self?.videoEndedSubject.send()
            }
        }
        
        // 파일 로드
        if !mpvView.initializeMPV() {
            error = "MPV를 초기화할 수 없습니다. brew install mpv를 실행하세요."
            return
        }
        
        mpvView.loadFile(path)
        isLoaded = true
        isPlaying = true
    }
    
    func play() {
        if currentPlayerType == .mpv {
            mpvPlayerView?.play()
        } else {
            player.play()
            if playbackSpeed != 1.0 {
                player.rate = playbackSpeed
            }
        }
    }
    
    func pause() {
        if currentPlayerType == .mpv {
            mpvPlayerView?.pause()
        } else {
            player.pause()
        }
    }
    
    func togglePause() {
        if currentPlayerType == .mpv {
            mpvPlayerView?.togglePause()
            isPlaying = !(mpvPlayerView?.isPaused ?? true)
        } else {
            if isPlaying {
                pause()
            } else {
                play()
            }
        }
    }
    
    func seek(to seconds: Double) {
        if currentPlayerType == .mpv {
            mpvPlayerView?.seek(to: seconds)
        } else {
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }
    
    func seekRelative(_ seconds: Double) {
        if currentPlayerType == .mpv {
            mpvPlayerView?.seekRelative(seconds)
        } else {
            let newTime = max(0, min(duration, currentTime + seconds))
            seek(to: newTime)
        }
    }
    
    func setVolume(_ vol: Float) {
        if currentPlayerType == .mpv {
            mpvPlayerView?.setVolume(Double(vol) * 100)  // mpv uses 0-100
            volume = vol
        } else {
            player.volume = max(0, min(1, vol))
        }
    }
    
    func toggleMute() {
        if currentPlayerType == .mpv {
            isMuted.toggle()
            mpvPlayerView?.setMuted(isMuted)
        } else {
            player.isMuted.toggle()
        }
    }
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if currentPlayerType == .mpv {
            mpvPlayerView?.setSpeed(Double(speed))
        } else {
            if isPlaying {
                player.rate = speed
            }
        }
    }
    
    func stop() {
        if currentPlayerType == .mpv {
            mpvPlayerView?.stop()
        } else {
            player.pause()
            player.replaceCurrentItem(with: nil)
            removeTimeObserver()
        }
        isLoaded = false
        currentTime = 0
        duration = 0
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    deinit {
        removeTimeObserver()
        mpvPlayerView?.shutdown()
    }
}

