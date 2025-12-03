import Foundation

class FileScanner {
    private let videoExtensions = ["mp4", "mkv", "avi", "webm", "mov", "wmv", "flv", "m4v", "mpg", "mpeg", "3gp"]
    
    func scanFolder(path: String, maxDepth: Int) async -> [Video] {
        var videos: [Video] = []
        let fileManager = FileManager.default
        let baseURL = URL(fileURLWithPath: path)
        
        print("📂 Scanning folder: \(path)")
        print("   Max depth: \(maxDepth)")
        
        // 폴더 접근 가능한지 확인
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
        
        if !exists {
            print("❌ Folder does not exist: \(path)")
            return []
        }
        
        if !isDirectory.boolValue {
            print("❌ Path is not a directory: \(path)")
            return []
        }
        
        // 읽기 권한 확인
        if !fileManager.isReadableFile(atPath: path) {
            print("❌ Cannot read folder (permission denied): \(path)")
            return []
        }
        
        await scanDirectory(baseURL, currentDepth: 0, maxDepth: maxDepth, videos: &videos, fileManager: fileManager)
        
        print("✅ Scan complete. Found \(videos.count) videos")
        return videos
    }
    
    private func scanDirectory(_ url: URL, currentDepth: Int, maxDepth: Int, videos: inout [Video], fileManager: FileManager) async {
        guard currentDepth <= maxDepth else { 
            print("   ⏭️ Skipping (depth \(currentDepth) > maxDepth \(maxDepth)): \(url.path)")
            return 
        }
        
        do {
            let contents = try fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey], options: [.skipsHiddenFiles])
            
            print("   📁 Depth \(currentDepth): \(url.lastPathComponent) (\(contents.count) items)")
            
            for item in contents {
                do {
                    let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .creationDateKey])
                    
                    if resourceValues.isDirectory == true {
                        // Skip common system folders
                        let name = item.lastPathComponent
                        if ["node_modules", ".git", "Library", ".Trash", "__MACOSX", ".Spotlight-V100", ".fseventsd"].contains(name) {
                            continue
                        }
                        
                        // Recursively scan subdirectories
                        await scanDirectory(item, currentDepth: currentDepth + 1, maxDepth: maxDepth, videos: &videos, fileManager: fileManager)
                    } else {
                        // Check if it's a video file
                        let ext = item.pathExtension.lowercased()
                        if videoExtensions.contains(ext) {
                            let video = Video(
                                path: item.path,
                                filename: item.lastPathComponent,
                                folderPath: item.deletingLastPathComponent().path,
                                size: Int64(resourceValues.fileSize ?? 0),
                                createdAt: resourceValues.creationDate ?? Date(),
                                thumbnailPath: findThumbnail(for: item)
                            )
                            videos.append(video)
                            print("      🎬 Found video: \(video.filename)")
                        }
                    }
                } catch {
                    print("   ⚠️ Error reading item \(item.lastPathComponent): \(error.localizedDescription)")
                }
            }
        } catch {
            print("   ❌ Error scanning directory \(url.path): \(error.localizedDescription)")
        }
    }
    
    private func findThumbnail(for videoURL: URL) -> String? {
        let filename = videoURL.deletingPathExtension().lastPathComponent
        let folder = videoURL.deletingLastPathComponent()
        
        let imageExtensions = ["jpg", "jpeg", "png", "webp"]
        
        for ext in imageExtensions {
            let thumbnailURL = folder.appendingPathComponent("\(filename).\(ext)")
            if FileManager.default.fileExists(atPath: thumbnailURL.path) {
                return thumbnailURL.path
            }
        }
        
        return nil
    }
}
