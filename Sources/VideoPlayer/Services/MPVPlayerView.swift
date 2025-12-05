import Foundation
import AppKit
import OpenGL.GL
import OpenGL.GL3
import Clibmpv

// MARK: - MPV OpenGL View
class MPVPlayerView: NSOpenGLView {
    private var mpv: OpaquePointer?
    private var mpvGL: OpaquePointer?
    private var displayLink: CVDisplayLink?
    
    // Callbacks need to be static/global
    private static var updateCallback: ((UnsafeMutableRawPointer?) -> Void)?
    
    var onTimeUpdate: ((Double) -> Void)?
    var onDurationUpdate: ((Double) -> Void)?
    var onPlaybackStateChange: ((Bool) -> Void)?
    var onLoadStateChange: ((Bool) -> Void)?
    var onError: ((String) -> Void)?
    var onEndOfFile: (() -> Void)?
    
    override init?(frame frameRect: NSRect, pixelFormat format: NSOpenGLPixelFormat?) {
        // Create pixel format with required attributes
        let attrs: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            UInt32(NSOpenGLPFAColorSize), 24,
            UInt32(NSOpenGLPFAAlphaSize), 8,
            UInt32(NSOpenGLPFADepthSize), 24,
            0
        ]
        
        guard let pixelFormat = NSOpenGLPixelFormat(attributes: attrs) else {
            print("❌ Failed to create OpenGL pixel format")
            return nil
        }
        
        super.init(frame: frameRect, pixelFormat: pixelFormat)
        
        wantsBestResolutionOpenGLSurface = true
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        shutdown()
    }
    
    // MARK: - MPV Setup
    
    func initializeMPV() -> Bool {
        guard mpv == nil else { return true }
        
        mpv = mpv_create()
        guard mpv != nil else {
            print("❌ Failed to create mpv context")
            return false
        }
        
        // Set options before initialization
        checkError(mpv_set_option_string(mpv, "vo", "libmpv"))
        checkError(mpv_set_option_string(mpv, "hwdec", "auto"))
        checkError(mpv_set_option_string(mpv, "keep-open", "yes"))
        checkError(mpv_set_option_string(mpv, "idle", "yes"))
        
        // Initialize mpv
        guard mpv_initialize(mpv) == 0 else {
            print("❌ Failed to initialize mpv")
            mpv_destroy(mpv)
            mpv = nil
            return false
        }
        
        // Request property updates
        mpv_observe_property(mpv, 0, "time-pos", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 1, "duration", MPV_FORMAT_DOUBLE)
        mpv_observe_property(mpv, 2, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 3, "eof-reached", MPV_FORMAT_FLAG)
        
        // Setup OpenGL
        return setupOpenGL()
    }
    
    private func setupOpenGL() -> Bool {
        guard let context = openGLContext else {
            print("❌ No OpenGL context")
            return false
        }
        
        context.makeCurrentContext()
        
        // Get OpenGL proc address function
        let getProcAddress: @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? = { _, name in
            guard let name = name else { return nil }
            let symbol = String(cString: name)
            
            let symbolName = CFStringCreateWithCString(kCFAllocatorDefault, symbol, kCFStringEncodingASCII)
            guard let bundleURL = CFURLCreateWithFileSystemPath(
                kCFAllocatorDefault,
                "/System/Library/Frameworks/OpenGL.framework" as CFString,
                CFURLPathStyle.cfurlposixPathStyle,
                true
            ) else { return nil }
            
            guard let bundle = CFBundleCreate(kCFAllocatorDefault, bundleURL) else { return nil }
            
            return CFBundleGetFunctionPointerForName(bundle, symbolName)
        }
        
        var openglInitParams = mpv_opengl_init_params(
            get_proc_address: getProcAddress,
            get_proc_address_ctx: nil
        )
        
        // mpv_render_param 배열 구성
        var renderContext: OpaquePointer?
        
        // API 타입
        var apiTypeStr = Array(MPV_RENDER_API_TYPE_OPENGL.utf8CString)
        
        let result = apiTypeStr.withUnsafeMutableBufferPointer { apiBuffer -> Int32 in
            withUnsafeMutablePointer(to: &openglInitParams) { initPtr -> Int32 in
                var params: [mpv_render_param] = [
                    mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiBuffer.baseAddress),
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil)
                ]
                
                return params.withUnsafeMutableBufferPointer { paramsBuffer in
                    mpv_render_context_create(&renderContext, mpv, paramsBuffer.baseAddress)
                }
            }
        }
        
        guard result == 0, let ctx = renderContext else {
            print("❌ Failed to create mpv render context: \(result)")
            return false
        }
        
        mpvGL = ctx
        
        // Setup render update callback
        let view = Unmanaged.passUnretained(self).toOpaque()
        mpv_render_context_set_update_callback(mpvGL, { ctx in
            guard let ctx = ctx else { return }
            let view = Unmanaged<MPVPlayerView>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                view.needsDisplay = true
            }
        }, view)
        
        // Start display link
        startDisplayLink()
        
        print("✅ MPV OpenGL initialized successfully")
        return true
    }
    
    // MARK: - Display Link
    
    private func startDisplayLink() {
        CVDisplayLinkCreateWithActiveCGDisplays(&displayLink)
        
        guard let displayLink = displayLink else { return }
        
        let view = Unmanaged.passUnretained(self).toOpaque()
        
        CVDisplayLinkSetOutputCallback(displayLink, { displayLink, inNow, inOutputTime, flagsIn, flagsOut, displayLinkContext -> CVReturn in
            guard let context = displayLinkContext else { return kCVReturnSuccess }
            let view = Unmanaged<MPVPlayerView>.fromOpaque(context).takeUnretainedValue()
            
            DispatchQueue.main.async {
                view.processEvents()
                if view.mpvGL != nil {
                    view.needsDisplay = true
                }
            }
            
            return kCVReturnSuccess
        }, view)
        
        CVDisplayLinkStart(displayLink)
    }
    
    // MARK: - Event Processing
    
    private func processEvents() {
        guard let mpv = mpv else { return }
        
        while true {
            let event = mpv_wait_event(mpv, 0)
            guard let eventPtr = event else { break }
            
            if eventPtr.pointee.event_id == MPV_EVENT_NONE { break }
            
            switch eventPtr.pointee.event_id {
            case MPV_EVENT_PROPERTY_CHANGE:
                handlePropertyChange(event: eventPtr)
                
            case MPV_EVENT_END_FILE:
                onEndOfFile?()
                
            case MPV_EVENT_FILE_LOADED:
                onLoadStateChange?(true)
                
            case MPV_EVENT_LOG_MESSAGE:
                if let data = eventPtr.pointee.data {
                    let msg = data.assumingMemoryBound(to: mpv_event_log_message.self).pointee
                    if let text = msg.text {
                        print("MPV: \(String(cString: text))")
                    }
                }
                
            default:
                break
            }
        }
    }
    
    private func handlePropertyChange(event: UnsafePointer<mpv_event>) {
        guard let data = event.pointee.data else { return }
        let prop = data.assumingMemoryBound(to: mpv_event_property.self).pointee
        
        guard let name = prop.name else { return }
        let propName = String(cString: name)
        
        switch propName {
        case "time-pos":
            if prop.format == MPV_FORMAT_DOUBLE, let dataPtr = prop.data {
                let time = dataPtr.assumingMemoryBound(to: Double.self).pointee
                onTimeUpdate?(time)
            }
            
        case "duration":
            if prop.format == MPV_FORMAT_DOUBLE, let dataPtr = prop.data {
                let duration = dataPtr.assumingMemoryBound(to: Double.self).pointee
                onDurationUpdate?(duration)
            }
            
        case "pause":
            if prop.format == MPV_FORMAT_FLAG, let dataPtr = prop.data {
                let paused = dataPtr.assumingMemoryBound(to: Int32.self).pointee != 0
                onPlaybackStateChange?(!paused)
            }
            
        case "eof-reached":
            if prop.format == MPV_FORMAT_FLAG, let dataPtr = prop.data {
                let eof = dataPtr.assumingMemoryBound(to: Int32.self).pointee != 0
                if eof {
                    onEndOfFile?()
                }
            }
            
        default:
            break
        }
    }
    
    // MARK: - Rendering
    
    override func draw(_ dirtyRect: NSRect) {
        guard let mpvGL = mpvGL, let context = openGLContext else {
            super.draw(dirtyRect)
            return
        }
        
        context.makeCurrentContext()
        
        let scale = window?.backingScaleFactor ?? 1.0
        let width = Int32(bounds.width * scale)
        let height = Int32(bounds.height * scale)
        
        var fbo = mpv_opengl_fbo(
            fbo: 0,
            w: width,
            h: height,
            internal_format: 0
        )
        
        var flipY: Int32 = 1
        
        var params: [mpv_render_param] = []
        
        withUnsafeMutablePointer(to: &fbo) { fboPtr in
            params.append(mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: fboPtr))
        }
        
        withUnsafeMutablePointer(to: &flipY) { flipPtr in
            params.append(mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr))
        }
        
        params.append(mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil))
        
        mpv_render_context_render(mpvGL, &params)
        
        context.flushBuffer()
    }
    
    override func reshape() {
        super.reshape()
        needsDisplay = true
    }
    
    // MARK: - Playback Controls
    
    func loadFile(_ path: String) {
        if mpv == nil {
            if !initializeMPV() { return }
        }
        
        guard let mpv = self.mpv else { return }
        
        // loadfile 명령어 실행
        path.withCString { pathPtr in
            "replace".withCString { modePtr in
                var args: [UnsafePointer<CChar>?] = []
                "loadfile".withCString { cmd in
                    args = [cmd, pathPtr, modePtr, nil]
                    args.withUnsafeMutableBufferPointer { buffer in
                        mpv_command(mpv, buffer.baseAddress)
                    }
                }
            }
        }
    }
    
    func play() {
        command("set", "pause", "no")
    }
    
    func pause() {
        command("set", "pause", "yes")
    }
    
    func togglePause() {
        command("cycle", "pause")
    }
    
    func seek(to position: Double) {
        command("seek", String(position), "absolute")
    }
    
    func seekRelative(_ seconds: Double) {
        command("seek", String(seconds), "relative")
    }
    
    func setVolume(_ volume: Double) {
        command("set", "volume", String(volume))
    }
    
    func setMuted(_ muted: Bool) {
        command("set", "mute", muted ? "yes" : "no")
    }
    
    func setSpeed(_ speed: Double) {
        command("set", "speed", String(speed))
    }
    
    func stop() {
        command("stop")
    }
    
    private func command(_ args: String...) {
        guard let mpv = mpv else { return }
        
        // strdup으로 C 문자열 배열 생성
        var cStrings = args.map { strdup($0) }
        cStrings.append(nil)
        
        defer {
            for ptr in cStrings {
                if let ptr = ptr { free(ptr) }
            }
        }
        
        // UnsafePointer로 변환
        cStrings.withUnsafeMutableBufferPointer { buffer in
            // UnsafeMutablePointer<CChar>? 를 UnsafePointer<CChar>? 로 변환
            var pointers: [UnsafePointer<CChar>?] = buffer.map { ptr in
                ptr.map { UnsafePointer($0) }
            }
            pointers.withUnsafeMutableBufferPointer { ptrBuffer in
                mpv_command(mpv, ptrBuffer.baseAddress)
            }
        }
    }
    
    func shutdown() {
        if let displayLink = displayLink {
            CVDisplayLinkStop(displayLink)
            self.displayLink = nil
        }
        
        if let mpvGL = mpvGL {
            mpv_render_context_free(mpvGL)
            self.mpvGL = nil
        }
        
        if let mpv = mpv {
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }
    }
    
    // MARK: - Helpers
    
    private func checkError(_ status: Int32) {
        if status < 0 {
            let error = String(cString: mpv_error_string(status))
            print("⚠️ MPV Error: \(error)")
        }
    }
    
    // MARK: - Properties
    
    var currentTime: Double {
        guard let mpv = mpv else { return 0 }
        var time: Double = 0
        mpv_get_property(mpv, "time-pos", MPV_FORMAT_DOUBLE, &time)
        return time
    }
    
    var duration: Double {
        guard let mpv = mpv else { return 0 }
        var dur: Double = 0
        mpv_get_property(mpv, "duration", MPV_FORMAT_DOUBLE, &dur)
        return dur
    }
    
    var volume: Double {
        guard let mpv = mpv else { return 100 }
        var vol: Double = 100
        mpv_get_property(mpv, "volume", MPV_FORMAT_DOUBLE, &vol)
        return vol
    }
    
    var isPaused: Bool {
        guard let mpv = mpv else { return true }
        var paused: Int32 = 0
        mpv_get_property(mpv, "pause", MPV_FORMAT_FLAG, &paused)
        return paused != 0
    }
}

