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
        let asset = AVAsset(url: videoURL)
        
        // 지원되지 않는 포맷 체크
        let ext = videoURL.pathExtension.lowercased()
        let unsupportedFormats = ["mkv", "avi", "wmv", "flv"]
        if unsupportedFormats.contains(ext) {
            print("⚠️ Thumbnail generation not supported for \(ext): \(videoPath)")
            return nil
        }
        
        do {
            // 비디오 길이 확인
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            
            guard durationSeconds > 0 else {
                print("⚠️ Video has no duration: \(videoPath)")
                return nil
            }
            
            // 썸네일 추출할 시간 계산 (10% 지점, 최소 1초)
            let timeSeconds = max(1.0, durationSeconds * timePercent)
            let time = CMTime(seconds: timeSeconds, preferredTimescale: 600)
            
            // 이미지 생성기 설정
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 480, height: 270) // 16:9 기준 최대 크기
            generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
            generator.requestedTimeToleranceAfter = CMTime(seconds: 2, preferredTimescale: 600)
            
            // 썸네일 추출
            let cgImage = try await generator.image(at: time).image
            
            // NSImage로 변환
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            
            // JPEG 데이터로 변환
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmapRep.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                print("❌ Failed to convert thumbnail to JPEG: \(videoPath)")
                return nil
            }
            
            // 파일로 저장
            try jpegData.write(to: thumbnailPath)
            
            thumbnailCache[videoId] = thumbnailPath.path
            print("✅ Generated thumbnail: \(thumbnailPath.lastPathComponent)")
            
            return thumbnailPath.path
            
        } catch {
            print("❌ Failed to generate thumbnail for \(videoPath): \(error.localizedDescription)")
            return nil
        }
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


