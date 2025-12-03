import SwiftUI

struct VideoGridView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var selectedVideoForDetail: Video?
    
    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 16)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(appState.videos.count)개 영상")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("검색", text: Binding(
                        get: { appState.searchQuery },
                        set: { appState.search($0) }
                    ))
                    .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.white.opacity(0.1))
                .cornerRadius(8)
                .frame(maxWidth: 300)
                
                // View mode toggle
                Picker("", selection: $appState.viewMode) {
                    Image(systemName: "square.grid.2x2").tag(AppState.ViewMode.grid)
                    Image(systemName: "list.bullet").tag(AppState.ViewMode.list)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 80)
            }
            .padding()
            .background(Color.black.opacity(0.3))
            
            // Content
            if appState.isLoading {
                Spacer()
                ProgressView()
                    .scaleEffect(1.5)
                Spacer()
            } else if appState.videos.isEmpty {
                Spacer()
                VStack(spacing: 16) {
                    Image(systemName: "film")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("영상이 없습니다")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("사이드바에서 폴더를 추가하세요")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    if appState.viewMode == .grid {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(appState.videos) { video in
                                VideoCard(video: video, onPlay: {
                                    openPlayer(video)
                                }, onShowDetail: {
                                    selectedVideoForDetail = video
                                })
                            }
                        }
                        .padding()
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(appState.videos) { video in
                                VideoRow(video: video, onPlay: {
                                    openPlayer(video)
                                }, onShowDetail: {
                                    selectedVideoForDetail = video
                                })
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
        .sheet(item: $selectedVideoForDetail) { video in
            VideoDetailSheet(video: video)
                .environmentObject(appState)
        }
    }
    
    private func openPlayer(_ video: Video) {
        appState.openPlayer(video: video)
        openWindow(id: "player", value: video.id)
    }
}

struct VideoCard: View {
    @EnvironmentObject var appState: AppState
    
    let video: Video
    let onPlay: () -> Void
    let onShowDetail: () -> Void
    
    @State private var isHovered = false
    
    // Get assigned tags for this video
    private var assignedTags: [Tag] {
        appState.tags.filter { tag in
            appState.isTagAssignedToVideo(tag: tag, video: video)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Thumbnail
            ZStack {
                if let thumbnailPath = video.thumbnailPath,
                   let image = NSImage(contentsOfFile: thumbnailPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(LinearGradient(
                            colors: [Color.purple.opacity(0.3), Color.blue.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundColor(.white.opacity(0.5))
                }
                
                // Play overlay
                if isHovered {
                    Color.black.opacity(0.4)
                    
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.white)
                }
                
                // Info button (top right)
                VStack {
                    HStack {
                        Spacer()
                        if isHovered {
                            Button {
                                onShowDetail()
                            } label: {
                                Image(systemName: "info.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(8)
                        }
                    }
                    Spacer()
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .clipped()
            
            // Info - 높이 고정
            VStack(alignment: .leading, spacing: 4) {
                Text(video.filename)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
                
                HStack {
                    Text(video.formattedSize)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // Show assigned tags
                    if !assignedTags.isEmpty {
                        HStack(spacing: 4) {
                            ForEach(assignedTags.prefix(3)) { tag in
                                Circle()
                                    .fill(Color(hex: tag.color) ?? .blue)
                                    .frame(width: 8, height: 8)
                            }
                            if assignedTags.count > 3 {
                                Text("+\(assignedTags.count - 3)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 55)
            .background(Color.black.opacity(0.3))
        }
        .background(Color.white.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor : Color.clear, lineWidth: 2)
        )
        .onHover { isHovered = $0 }
        .onTapGesture {
            onPlay()
        }
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("재생", systemImage: "play.fill")
            }
            
            Button {
                onShowDetail()
            } label: {
                Label("태그/참가자 편집", systemImage: "tag.fill")
            }
            
            Divider()
            
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: video.path)])
            } label: {
                Label("Finder에서 보기", systemImage: "folder")
            }
        }
    }
}

struct VideoRow: View {
    @EnvironmentObject var appState: AppState
    
    let video: Video
    let onPlay: () -> Void
    let onShowDetail: () -> Void
    
    @State private var isHovered = false
    
    // Get assigned tags for this video
    private var assignedTags: [Tag] {
        appState.tags.filter { tag in
            appState.isTagAssignedToVideo(tag: tag, video: video)
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            ZStack {
                if let thumbnailPath = video.thumbnailPath,
                   let image = NSImage(contentsOfFile: thumbnailPath) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    
                    Image(systemName: "film")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 68)
            .cornerRadius(6)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.filename)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                
                HStack {
                    Text(video.formattedSize)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    
                    // Show assigned tags
                    if !assignedTags.isEmpty {
                        ForEach(assignedTags.prefix(3)) { tag in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color(hex: tag.color) ?? .blue)
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                        }
                    }
                }
            }
            
            Spacer()
            
            // Actions
            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        onShowDetail()
                    } label: {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    
                    Button {
                        onPlay()
                    } label: {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Color.accentColor)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isHovered ? Color.white.opacity(0.05) : Color.clear)
        .onHover { isHovered = $0 }
        .onTapGesture {
            onPlay()
        }
        .contextMenu {
            Button {
                onPlay()
            } label: {
                Label("재생", systemImage: "play.fill")
            }
            
            Button {
                onShowDetail()
            } label: {
                Label("태그/참가자 편집", systemImage: "tag.fill")
            }
            
            Divider()
            
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: video.path)])
            } label: {
                Label("Finder에서 보기", systemImage: "folder")
            }
        }
    }
}

#Preview {
    VideoGridView()
        .environmentObject(AppState())
}
