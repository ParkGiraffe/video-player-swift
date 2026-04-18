import Foundation
import AVFoundation
import CoreMedia

enum CodecDetector {
    // AVFoundation이 안정적으로 디코딩하는 비디오 코덱 FourCharCode
    // VP9('vp09'), AV1('av01') 같은 오픈 코덱은 여기 없으므로 MPV로 폴백됨
    private static let avPlayerCompatibleCodecs: Set<FourCharCode> = [
        kCMVideoCodecType_H264,           // 'avc1'
        kCMVideoCodecType_HEVC,           // 'hvc1'
        0x68657631,                        // 'hev1' (HEVC 변종)
        kCMVideoCodecType_MPEG4Video,      // 'mp4v'
        kCMVideoCodecType_AppleProRes422,
        kCMVideoCodecType_AppleProRes4444,
    ]

    // mp4/mov 컨테이너 내부가 VP9/AV1일 수 있어 코덱 확인이 필요한 확장자들
    static let ambiguousContainerExtensions: Set<String> = [
        "mp4", "mov", "m4v", "3gp", "mpg", "mpeg"
    ]

    /// 주어진 파일의 비디오 트랙이 AVFoundation으로 디코딩 가능한지 확인
    static func isAVPlayerCompatible(path: String) async -> Bool {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else {
                // 비디오 트랙이 없으면 오디오 전용일 수 있으므로 AVPlayer에 맡김
                return true
            }
            let descriptions = try await track.load(.formatDescriptions)
            guard let desc = descriptions.first else { return false }
            let codecType = CMFormatDescriptionGetMediaSubType(desc)
            return avPlayerCompatibleCodecs.contains(codecType)
        } catch {
            return false
        }
    }
}
