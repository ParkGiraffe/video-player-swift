import Foundation
import AppKit

class MPVPlayer: ObservableObject {
    static let shared = MPVPlayer()
    
    private var mpvProcess: Process?
    private var ipcPath: String?
    private var updateTimer: Timer?
    
    // Published state
    @Published var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var volume: Double = 100
    @Published var isMuted: Bool = false
    @Published var playbackSpeed: Double = 1.0
    @Published var isLoaded: Bool = false
    
    private init() {}
    
    func initialize() {
        // Check if mpv is available
        let mpvPath = findMpvPath()
        print("MPV path: \(mpvPath ?? "not found")")
    }
    
    private func findMpvPath() -> String? {
        let paths = [
            "/opt/homebrew/bin/mpv",
            "/usr/local/bin/mpv",
            "/usr/bin/mpv"
        ]
        
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    func loadFile(_ path: String, in view: NSView? = nil) {
        // Stop any existing playback
        stop()
        
        guard let mpvPath = findMpvPath() else {
            print("mpv not found")
            return
        }
        
        // Generate IPC socket path
        let timestamp = Date().timeIntervalSince1970
        ipcPath = "/tmp/mpv-ipc-\(Int(timestamp))"
        
        // Build mpv arguments
        var args = [
            "--input-ipc-server=\(ipcPath!)",
            "--osc=yes",
            "--keep-open=yes",
            "--idle=no",
            "--hwdec=auto",
            "--title=Video Player"
        ]
        
        // If we have a view, embed mpv in it
        if let view = view, let window = view.window {
            // Get the window ID
            let windowNumber = window.windowNumber
            args.append("--wid=\(windowNumber)")
        }
        
        args.append("--")
        args.append(path)
        
        // Start mpv process
        mpvProcess = Process()
        mpvProcess?.executableURL = URL(fileURLWithPath: mpvPath)
        mpvProcess?.arguments = args
        
        do {
            try mpvProcess?.run()
            print("mpv started with args: \(args)")
            
            DispatchQueue.main.async {
                self.isLoaded = true
                self.isPlaying = true
            }
            
            // Start polling for state updates
            startUpdateTimer()
            
        } catch {
            print("Failed to start mpv: \(error)")
        }
    }
    
    private func startUpdateTimer() {
        updateTimer?.invalidate()
        
        // Wait for IPC socket to be created
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.updateTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.pollState()
            }
        }
    }
    
    private func pollState() {
        guard let ipcPath = ipcPath else { return }
        
        // Get time-pos
        if let response = sendCommand(["get_property", "time-pos"]) {
            if let data = response["data"] as? Double {
                DispatchQueue.main.async {
                    self.currentTime = data
                }
            }
        }
        
        // Get duration
        if let response = sendCommand(["get_property", "duration"]) {
            if let data = response["data"] as? Double {
                DispatchQueue.main.async {
                    self.duration = data
                }
            }
        }
        
        // Get pause state
        if let response = sendCommand(["get_property", "pause"]) {
            if let data = response["data"] as? Bool {
                DispatchQueue.main.async {
                    self.isPlaying = !data
                }
            }
        }
        
        // Get volume
        if let response = sendCommand(["get_property", "volume"]) {
            if let data = response["data"] as? Double {
                DispatchQueue.main.async {
                    self.volume = data
                }
            }
        }
        
        // Get mute
        if let response = sendCommand(["get_property", "mute"]) {
            if let data = response["data"] as? Bool {
                DispatchQueue.main.async {
                    self.isMuted = data
                }
            }
        }
        
        // Get speed
        if let response = sendCommand(["get_property", "speed"]) {
            if let data = response["data"] as? Double {
                DispatchQueue.main.async {
                    self.playbackSpeed = data
                }
            }
        }
    }
    
    private func sendCommand(_ command: [Any]) -> [String: Any]? {
        guard let ipcPath = ipcPath else { return nil }
        
        // Create JSON command
        let commandDict: [String: Any] = ["command": command]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: commandDict),
              var jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        jsonString += "\n"
        
        // Connect to Unix socket
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socket >= 0 else { return nil }
        defer { close(socket) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ipcPath.withCString { cString in
                _ = strcpy(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self), cString)
            }
        }
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(socket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else { return nil }
        
        // Send command
        jsonString.withCString { cString in
            _ = send(socket, cString, strlen(cString), 0)
        }
        
        // Read response
        var buffer = [CChar](repeating: 0, count: 4096)
        let bytesRead = recv(socket, &buffer, buffer.count - 1, 0)
        
        guard bytesRead > 0 else { return nil }
        
        let responseString = String(cString: buffer)
        guard let responseData = responseString.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return nil
        }
        
        return response
    }
    
    // MARK: - Playback Controls
    
    func play() {
        _ = sendCommand(["set_property", "pause", false])
        DispatchQueue.main.async {
            self.isPlaying = true
        }
    }
    
    func pause() {
        _ = sendCommand(["set_property", "pause", true])
        DispatchQueue.main.async {
            self.isPlaying = false
        }
    }
    
    func togglePause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to position: Double) {
        _ = sendCommand(["seek", position, "absolute"])
    }
    
    func seekRelative(_ seconds: Double) {
        _ = sendCommand(["seek", seconds, "relative"])
    }
    
    func setVolume(_ volume: Double) {
        _ = sendCommand(["set_property", "volume", volume])
        DispatchQueue.main.async {
            self.volume = volume
        }
    }
    
    func toggleMute() {
        let newMuted = !isMuted
        _ = sendCommand(["set_property", "mute", newMuted])
        DispatchQueue.main.async {
            self.isMuted = newMuted
        }
    }
    
    func setSpeed(_ speed: Double) {
        _ = sendCommand(["set_property", "speed", speed])
        DispatchQueue.main.async {
            self.playbackSpeed = speed
        }
    }
    
    func stop() {
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Send quit command
        _ = sendCommand(["quit"])
        
        // Terminate process
        mpvProcess?.terminate()
        mpvProcess = nil
        
        // Clean up IPC socket
        if let ipcPath = ipcPath {
            try? FileManager.default.removeItem(atPath: ipcPath)
        }
        ipcPath = nil
        
        DispatchQueue.main.async {
            self.isLoaded = false
            self.isPlaying = false
            self.currentTime = 0
            self.duration = 0
        }
    }
    
    func shutdown() {
        stop()
    }
}
