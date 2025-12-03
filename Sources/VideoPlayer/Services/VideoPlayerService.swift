import Foundation
import AVFoundation
import AVKit
import Combine

class VideoPlayerService: ObservableObject {
    static let shared = VideoPlayerService()
    
    let player = AVPlayer()
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
    
    private init() {
        setupObservers()
    }
    
    private func setupObservers() {
        // Observe playback status
        player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
            }
            .store(in: &cancellables)
        
        // Observe volume
        player.publisher(for: \.volume)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] vol in
                self?.volume = vol
            }
            .store(in: &cancellables)
        
        // Observe mute
        player.publisher(for: \.isMuted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] muted in
                self?.isMuted = muted
            }
            .store(in: &cancellables)
        
        // Observe rate
        player.publisher(for: \.rate)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] rate in
                if rate != 0 {
                    self?.playbackSpeed = rate
                }
            }
            .store(in: &cancellables)
        
        // Playback finished notification
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.isPlaying = false
            }
            .store(in: &cancellables)
    }
    
    func loadFile(_ path: String) {
        error = nil
        isLoaded = false
        
        let url = URL(fileURLWithPath: path)
        let asset = AVAsset(url: url)
        
        // Check if format is supported
        let ext = url.pathExtension.lowercased()
        let unsupportedFormats = ["mkv", "avi", "wmv", "flv"]
        
        if unsupportedFormats.contains(ext) {
            error = "이 포맷(\(ext.uppercased()))은 AVPlayer에서 지원하지 않습니다.\nmpv로 외부 재생합니다."
            openWithExternalPlayer(path)
            return
        }
        
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
    
    private func openWithExternalPlayer(_ path: String) {
        // mpv로 외부 재생
        let mpvPaths = [
            "/opt/homebrew/bin/mpv",
            "/usr/local/bin/mpv"
        ]
        
        var mpvPath: String?
        for p in mpvPaths {
            if FileManager.default.fileExists(atPath: p) {
                mpvPath = p
                break
            }
        }
        
        if let mpvPath = mpvPath {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: mpvPath)
            process.arguments = [path]
            
            do {
                try process.run()
            } catch {
                self.error = "mpv 실행 실패: \(error.localizedDescription)"
            }
        } else {
            self.error = "mpv가 설치되어 있지 않습니다. brew install mpv로 설치하세요."
        }
    }
    
    func play() {
        player.play()
        if playbackSpeed != 1.0 {
            player.rate = playbackSpeed
        }
    }
    
    func pause() {
        player.pause()
    }
    
    func togglePause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    func seekRelative(_ seconds: Double) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }
    
    func setVolume(_ vol: Float) {
        player.volume = max(0, min(1, vol))
    }
    
    func toggleMute() {
        player.isMuted.toggle()
    }
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        if isPlaying {
            player.rate = speed
        }
    }
    
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        removeTimeObserver()
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
    }
}

