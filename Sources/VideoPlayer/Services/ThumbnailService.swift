import Foundation
import AVFoundation
import AppKit

actor ThumbnailService {
    static let shared = ThumbnailService()

    private let thumbnailDirectory: URL
    private let fileManager = FileManager.default

    // 썸네일 캐시 (메모리)
    private var thumbnailCache: [String: String] = [:]

    private init() {
        // 앱 지원 디렉토리에 썸네일 폴더 생성
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        thumbnailDirectory = appSupport.appendingPathComponent("VideoPlayer/Thumbnails")

        try? FileManager.default.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
    }

    /// 비디오에서 썸네일 생성
    /// - Parameters:
    ///   - videoPath: 비디오 파일 경로
    ///   - videoId: 비디오 ID (저장 시 파일명으로 사용)
    ///   - timePercent: 썸네일을 추출할 시간 위치 (0.0 ~ 1.0, 기본값 0.1 = 10% 지점)
    /// - Returns: 생성된 썸네일 파일 경로
    func generateThumbnail(for videoPath: String, videoId: String, timePercent: Double = 0.1) async -> String? {
        // 이미 캐시에 있으면 바로 반환
        if let cached = thumbnailCache[videoId] {
            if fileManager.fileExists(atPath: cached) {
                return cached
            }
        }

        // 이미 생성된 썸네일이 있는지 확인
        let thumbnailPath = thumbnailDirectory.appendingPathComponent("\(videoId).jpg")
        if fileManager.fileExists(atPath: thumbnailPath.path) {
            thumbnailCache[videoId] = thumbnailPath.path
            return thumbnailPath.path
        }

        // 비디오에서 썸네일 추출
        let videoURL = URL(fileURLWithPath: videoPath)
        let ext = videoURL.pathExtension.lowercased()

        // AVFoundation이 처리 못하는 컨테이너/코덱은 바로 mpv로
        let mpvOnlyFormats = ["mkv", "avi", "wmv", "flv", "webm"]
        if mpvOnlyFormats.contains(ext) {
            return await generateWithMPV(videoPath: videoPath, outputPath: thumbnailPath.path, videoId: videoId)
        }

        // mp4/mov 등: AVFoundation 시도, 실패 시 mpv 폴백
        if let result = await generateWithAVFoundation(
            videoURL: videoURL,
            outputPath: thumbnailPath,
            timePercent: timePercent
        ) {
            thumbnailCache[videoId] = result
            print("✅ Generated thumbnail: \(thumbnailPath.lastPathComponent)")
            return result
        }

        // AVFoundation 실패 — mpv CLI로 폴백 (mp4 안에 VP9/AV1이 들어있는 경우 등)
        print("↪️ AVFoundation failed, falling back to mpv for: \(videoPath)")
        return await generateWithMPV(videoPath: videoPath, outputPath: thumbnailPath.path, videoId: videoId)
    }

    private func generateWithAVFoundation(
        videoURL: URL,
        outputPath: URL,
        timePercent: Double
    ) async -> String? {
        let asset = AVAsset(url: videoURL)

        do {
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)

            guard durationSeconds > 0 else {
                print("⚠️ Video has no duration: \(videoURL.path)")
                return nil
            }

            let timeSeconds = max(1.0, durationSeconds * timePercent)
            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)

            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270)
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)

            let cgImage = try await generator.image(at: time).image
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))

            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                print("❌ Failed to convert thumbnail to JPEG: \(videoURL.path)")
                return nil
            }

            try jpegData.write(to: outputPath)
            return outputPath.path

        } catch {
            print("⚠️ AVFoundation thumbnail failed for \(videoURL.path): \(error.localizedDescription)")
            return nil
        }
    }

    private func generateWithMPV(videoPath: String, outputPath: String, videoId: String) async -> String? {
        guard let mpvPath = findMPVBinary() else {
            print("❌ mpv binary not found; cannot generate thumbnail for: \(videoPath)")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: mpvPath)
        process.arguments = [
            "--no-config",
            "--no-audio",
            "--no-sub",
            "--frames=1",
            "--start=10%",
            "--vf=scale=480:-2",
            "--ovc=mjpeg",
            "--ovcopts=strict=unofficial",
            "--o=\(outputPath)",
            videoPath
        ]
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("❌ Failed to launch mpv for thumbnail: \(error.localizedDescription)")
            return nil
        }

        guard process.terminationStatus == 0, fileManager.fileExists(atPath: outputPath) else {
            let errStr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("❌ mpv thumbnail generation failed (status \(process.terminationStatus)) for \(videoPath): \(errStr.suffix(400))")
            return nil
        }

        thumbnailCache[videoId] = outputPath
        print("✅ Generated thumbnail via mpv: \((outputPath as NSString).lastPathComponent)")
        return outputPath
    }

    private func findMPVBinary() -> String? {
        let paths = ["/opt/homebrew/bin/mpv", "/usr/local/bin/mpv", "/usr/bin/mpv"]
        return paths.first { fileManager.fileExists(atPath: $0) }
    }

    /// 여러 비디오의 썸네일을 일괄 생성
    func generateThumbnails(for videos: [(path: String, id: String)]) async -> [String: String] {
        var results: [String: String] = [:]

        for video in videos {
            if let thumbnailPath = await generateThumbnail(for: video.path, videoId: video.id) {
                results[video.id] = thumbnailPath
            }
        }

        return results
    }

    /// 썸네일 삭제
    func deleteThumbnail(videoId: String) {
        let thumbnailPath = thumbnailDirectory.appendingPathComponent("\(videoId).jpg")
        try? fileManager.removeItem(at: thumbnailPath)
        thumbnailCache.removeValue(forKey: videoId)
    }

    /// 모든 캐시 삭제
    func clearAllThumbnails() {
        try? fileManager.removeItem(at: thumbnailDirectory)
        try? fileManager.createDirectory(at: thumbnailDirectory, withIntermediateDirectories: true)
        thumbnailCache.removeAll()
    }

    /// 캐시에서 썸네일 경로 가져오기
    func getCachedThumbnail(videoId: String) -> String? {
        return thumbnailCache[videoId]
    }
}



