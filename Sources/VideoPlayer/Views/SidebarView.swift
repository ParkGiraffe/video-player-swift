import SwiftUI

// 폴더 트리 노드 구조체
struct FolderNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let depth: Int
    var children: [FolderNode]
    var videoCount: Int
    
    init(name: String, path: String, depth: Int = 0, children: [FolderNode] = [], videoCount: Int = 0) {
        self.id = path
        self.name = name
        self.path = path
        self.depth = depth
        self.children = children
        self.videoCount = videoCount
    }
}

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFolderPicker = false
    @State private var showFolderSettings: MountedFolder?
    @State private var newTagName = ""
    @State private var newTagColor = Color(red: 0.39, green: 0.4, blue: 0.95)
    @State private var newLanguageCode = ""
    @State private var newLanguageName = ""
    @State private var expandedFolders: Set<String> = []
    
    var body: some View {
        List {
            // All Videos
            Section {
                Button {
                    appState.clearFilters()
                } label: {
                    Label("모든 영상", systemImage: "film")
                }
                .buttonStyle(.plain)
                .foregroundColor(appState.selectedFolder == nil && appState.selectedTag == nil && appState.selectedParticipant == nil && appState.selectedLanguage == nil ? .accentColor : .primary)
            }
            
            // Mounted Folders
            Section("마운트된 폴더") {
                ForEach(appState.mountedFolders) { folder in
                    FolderTreeView(
                        folder: folder,
                        folderTree: buildFolderTree(for: folder),
                        expandedFolders: $expandedFolders,
                        selectedSubfolderPath: appState.selectedSubfolderPath,
                        showFolderSettings: $showFolderSettings,
                        onSelectFolder: { path, rootOnly in
                            appState.filterBySubfolder(folder, subfolderPath: path, rootOnly: rootOnly)
                        },
                        onRescan: {
                            Task {
                                await appState.scanFolder(folder)
                            }
                        },
                        onRemove: {
                            appState.removeMountedFolder(folder)
                        }
                    )
                    .environmentObject(appState)
                }
                
                Button {
                    showFolderPicker = true
                } label: {
                    Label("폴더 추가", systemImage: "plus.circle")
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
            
            // Tags - 클릭하면 해당 태그의 영상 모아보기
            Section("태그") {
                ForEach(appState.tags) { tag in
                    HStack {
                        Button {
                            appState.filterByTag(tag)
                        } label: {
                            HStack {
                                Circle()
                                    .fill(Color(hex: tag.color) ?? .blue)
                                    .frame(width: 10, height: 10)
                                Text(tag.name)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(appState.selectedTag?.id == tag.id ? .accentColor : .primary)
                        
                        Spacer()
                        
                        // 해당 태그의 영상 개수
                        Text("\(appState.getVideoCountForTag(tag))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            appState.deleteTag(tag)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("태그 이름", text: $newTagName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onSubmit {
                            addNewTag()
                        }
                    
                    ColorPicker("", selection: $newTagColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 30, height: 30)
                    
                    Button {
                        addNewTag()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(newTagName.isEmpty ? .secondary : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newTagName.isEmpty)
                }
                .padding(.vertical, 4)
            }
            
            // Languages - 클릭하면 해당 언어의 영상 모아보기
            Section("언어") {
                ForEach(appState.languages) { language in
                    HStack {
                        Button {
                            appState.filterByLanguage(language)
                        } label: {
                            HStack {
                                Text(language.code)
                                    .font(.caption)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.2))
                                    .cornerRadius(4)
                                Text(language.name)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(appState.selectedLanguage?.id == language.id ? .accentColor : .primary)
                        
                        Spacer()
                        
                        // 해당 언어의 영상 개수
                        Text("\(appState.getVideoCountForLanguage(language))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            appState.deleteLanguage(language)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
                
                HStack(spacing: 8) {
                    TextField("코드", text: $newLanguageCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                    
                    TextField("언어 이름", text: $newLanguageName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onSubmit {
                            addNewLanguage()
                        }
                    
                    Button {
                        addNewLanguage()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor((newLanguageCode.isEmpty || newLanguageName.isEmpty) ? .secondary : .accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(newLanguageCode.isEmpty || newLanguageName.isEmpty)
                }
                .padding(.vertical, 4)
            }
            
            // Participants - 클릭하면 해당 참가자의 영상 모아보기
            Section("참가자") {
                ForEach(appState.participants) { participant in
                    HStack {
                        Button {
                            appState.filterByParticipant(participant)
                        } label: {
                            HStack {
                                Image(systemName: "person.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(participant.name)
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(appState.selectedParticipant?.id == participant.id ? .accentColor : .primary)
                        
                        Spacer()
                        
                        // 해당 참가자의 영상 개수
                        Text("\(appState.getVideoCountForParticipant(participant))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Button {
                            appState.deleteParticipant(participant)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)
                    }
                }
                
                if appState.participants.isEmpty {
                    Text("영상 정보에서 참가자를 추가하세요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .fileImporter(
            isPresented: $showFolderPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // Security-scoped resource 접근 시작
                    if url.startAccessingSecurityScopedResource() {
                        // 북마크 저장 (앱 재시작 후에도 접근 가능하도록)
                        _ = BookmarkService.shared.saveBookmark(for: url)
                        
                        Task {
                            await appState.addMountedFolder(path: url.path)
                        }
                    } else {
                        print("❌ Failed to access folder: \(url.path)")
                    }
                }
            case .failure(let error):
                print("Folder picker error: \(error)")
            }
        }
        .sheet(item: $showFolderSettings) { folder in
            FolderSettingsSheet(folder: folder)
                .environmentObject(appState)
        }
    }
    
    private func addNewTag() {
        guard !newTagName.isEmpty else { return }
        let hexColor = colorToHex(newTagColor)
        appState.createTag(name: newTagName, color: hexColor)
        newTagName = ""
        newTagColor = Color(red: 0.39, green: 0.4, blue: 0.95)
    }
    
    private func addNewLanguage() {
        guard !newLanguageCode.isEmpty && !newLanguageName.isEmpty else { return }
        appState.createLanguage(code: newLanguageCode.uppercased(), name: newLanguageName)
        newLanguageCode = ""
        newLanguageName = ""
    }
    
    private func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else {
            return "#6366f1"
        }
        
        let r = Int(rgbColor.redComponent * 255)
        let g = Int(rgbColor.greenComponent * 255)
        let b = Int(rgbColor.blueComponent * 255)
        
        return String(format: "#%02X%02X%02X", r, g, b)
    }
    
    /// 마운트된 폴더의 하위 폴더 트리 구조 생성 (재귀적)
    private func buildFolderTree(for mountedFolder: MountedFolder) -> FolderNode {
        // 해당 마운트 폴더에 속한 모든 비디오의 폴더 경로 수집
        let allVideos = appState.allVideosInFolder(mountedFolder)
        let folderPaths = Set(allVideos.map { $0.folderPath })
        
        // 비디오 개수 계산을 위한 맵
        var videoCountMap: [String: Int] = [:]
        for video in allVideos {
            videoCountMap[video.folderPath, default: 0] += 1
        }
        
        let basePath = mountedFolder.path
        
        // 재귀적으로 트리 구축
        func buildNode(path: String, name: String, depth: Int) -> FolderNode {
            // 중간 폴더도 포함 (비디오가 없더라도)
            var allChildFolderNames = Set<String>()
            for folderPath in folderPaths {
                guard folderPath.hasPrefix(path + "/") else { continue }
                let relativePath = String(folderPath.dropFirst(path.count + 1))
                if let firstComponent = relativePath.split(separator: "/").first {
                    allChildFolderNames.insert(String(firstComponent))
                }
            }
            
            // 자식 노드들 생성 (재귀)
            let children = allChildFolderNames
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
                .map { childName -> FolderNode in
                    let childPath = path + "/" + childName
                    return buildNode(path: childPath, name: childName, depth: depth + 1)
                }
            
            return FolderNode(
                name: name,
                path: path,
                depth: depth,
                children: children,
                videoCount: videoCountMap[path] ?? 0
            )
        }
        
        return buildNode(path: basePath, name: mountedFolder.name, depth: 0)
    }
}

// 폴더 트리 뷰 컴포넌트
struct FolderTreeView: View {
    @EnvironmentObject var appState: AppState
    
    let folder: MountedFolder
    let folderTree: FolderNode
    @Binding var expandedFolders: Set<String>
    let selectedSubfolderPath: String?
    @Binding var showFolderSettings: MountedFolder?
    let onSelectFolder: (String?, Bool) -> Void  // (path, rootOnly)
    let onRescan: () -> Void
    let onRemove: () -> Void
    
    @State private var isHovered = false
    
    private var isSelected: Bool {
        selectedSubfolderPath == nil && appState.selectedFolder?.id == folder.id && !appState.selectedRootOnly
    }
    
    private var isRootSelected: Bool {
        selectedSubfolderPath == nil && appState.selectedFolder?.id == folder.id && appState.selectedRootOnly
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            // 루트 폴더 (마운트된 폴더)
            HStack(spacing: 2) {
                // 확장/축소 버튼 - 넓은 터치 영역
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleExpanded(folderTree.path)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(expandedFolders.contains(folderTree.path) ? 90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(folderTree.children.isEmpty ? 0 : 1)
                .disabled(folderTree.children.isEmpty)
                
                // 폴더 아이콘
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : Color(nsColor: .systemBlue))
                
                // 폴더 이름
                Text(folder.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                // 메뉴 버튼 (호버 시에만 표시)
                if isHovered || appState.isScanningFolder == folder.path {
                    if appState.isScanningFolder == folder.path {
                        ProgressView()
                            .scaleEffect(0.6)
                            .frame(width: 20, height: 20)
                    } else {
                        Menu {
                            Button {
                                showFolderSettings = folder
                            } label: {
                                Label("설정", systemImage: "gearshape")
                            }
                            
                            Button {
                                onRescan()
                            } label: {
                                Label("재스캔", systemImage: "arrow.clockwise")
                            }
                            
                            Divider()
                            
                            Button(role: .destructive) {
                                onRemove()
                            } label: {
                                Label("제거", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .menuStyle(.borderlessButton)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onSelectFolder(nil, false)
            }
            .onHover { hovering in
                isHovered = hovering
            }
            
            // 하위 폴더들 (펼쳐진 경우)
            if expandedFolders.contains(folderTree.path) {
                VStack(alignment: .leading, spacing: 1) {
                    // <Root> 노드 - 하위 폴더가 있고 해당 폴더에 직접 영상이 있을 때만 표시
                    if !folderTree.children.isEmpty && folderTree.videoCount > 0 {
                        RootOnlyRow(
                            path: folderTree.path,
                            videoCount: folderTree.videoCount,
                            isSelected: isRootSelected,
                            onSelect: { onSelectFolder(nil, true) }
                        )
                    }
                    
                    ForEach(folderTree.children) { child in
                        SubfolderRow(
                            node: child,
                            expandedFolders: $expandedFolders,
                            selectedSubfolderPath: selectedSubfolderPath,
                            selectedRootOnly: appState.selectedRootOnly,
                            onSelect: onSelectFolder
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
    
    private func toggleExpanded(_ path: String) {
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
        }
    }
}

// <Root> 전용 행 컴포넌트
struct RootOnlyRow: View {
    let path: String
    let videoCount: Int
    let isSelected: Bool
    let onSelect: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(spacing: 2) {
            // 화살표 자리 (없음)
            Spacer().frame(width: 22)
            
            // 아이콘
            Image(systemName: "folder.badge.minus")
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .white : .orange)
            
            // 이름
            Text("<Root>")
                .font(.system(size: 13))
                .foregroundColor(isSelected ? .white : .primary)
            
            Spacer()
            
            // 비디오 개수
            if videoCount > 0 {
                Text("\(videoCount)")
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// 하위 폴더 행 컴포넌트 - Finder 스타일
struct SubfolderRow: View {
    let node: FolderNode
    @Binding var expandedFolders: Set<String>
    let selectedSubfolderPath: String?
    let selectedRootOnly: Bool
    let onSelect: (String?, Bool) -> Void  // (path, rootOnly)
    
    @State private var isHovered = false
    
    private var isSelected: Bool {
        selectedSubfolderPath == node.path && !selectedRootOnly
    }
    
    private var isRootSelected: Bool {
        selectedSubfolderPath == node.path && selectedRootOnly
    }
    
    private var isExpanded: Bool {
        expandedFolders.contains(node.path)
    }
    
    // 해당 폴더의 전체 비디오 수 (하위 포함)
    private var totalVideoCount: Int {
        func countVideos(_ node: FolderNode) -> Int {
            node.videoCount + node.children.reduce(0) { $0 + countVideos($1) }
        }
        return countVideos(node)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 2) {
                // 확장/축소 화살표 - 넓은 터치 영역
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        toggleExpanded(node.path)
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(node.children.isEmpty ? 0 : 1)
                .disabled(node.children.isEmpty)
                
                // 폴더 아이콘 - Finder 스타일
                Image(systemName: "folder.fill")
                    .font(.system(size: 14))
                    .foregroundColor(isSelected ? .white : Color(nsColor: .systemBlue))
                
                // 폴더 이름
                Text(node.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Spacer()
                
                // 비디오 개수 (전체)
                if totalVideoCount > 0 {
                    Text("\(totalVideoCount)")
                        .font(.system(size: 11))
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor : (isHovered ? Color.primary.opacity(0.08) : Color.clear))
            )
            .contentShape(Rectangle())  // 전체 영역 클릭 가능
            .onTapGesture {
                onSelect(node.path, false)
            }
            .onHover { hovering in
                isHovered = hovering
            }
            
            // 하위 폴더 재귀적으로 표시
            if isExpanded {
                VStack(alignment: .leading, spacing: 1) {
                    // <Root> 노드 - 하위 폴더가 있고 해당 폴더에 직접 영상이 있을 때만
                    if !node.children.isEmpty && node.videoCount > 0 {
                        RootOnlyRow(
                            path: node.path,
                            videoCount: node.videoCount,
                            isSelected: isRootSelected,
                            onSelect: { onSelect(node.path, true) }
                        )
                    }
                    
                    ForEach(node.children) { child in
                        SubfolderRow(
                            node: child,
                            expandedFolders: $expandedFolders,
                            selectedSubfolderPath: selectedSubfolderPath,
                            selectedRootOnly: selectedRootOnly,
                            onSelect: onSelect
                        )
                    }
                }
                .padding(.leading, 12)
            }
        }
    }
    
    private func toggleExpanded(_ path: String) {
        if expandedFolders.contains(path) {
            expandedFolders.remove(path)
        } else {
            expandedFolders.insert(path)
        }
    }
}

// Folder Settings Sheet
struct FolderSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let folder: MountedFolder
    @State private var scanDepthText: String
    @State private var isScanning = false
    
    init(folder: MountedFolder) {
        self.folder = folder
        self._scanDepthText = State(initialValue: String(folder.scanDepth))
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text("폴더 설정")
                .font(.headline)
            
            Text(folder.name)
                .foregroundColor(.secondary)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("스캔 깊이")
                    .font(.subheadline)
                
                HStack {
                    TextField("깊이", text: $scanDepthText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                        .disabled(isScanning)
                        .onChange(of: scanDepthText) { _, newValue in
                            let filtered = newValue.filter { $0.isNumber }
                            if let num = Int(filtered) {
                                scanDepthText = String(min(25, max(0, num)))
                            } else if filtered.isEmpty {
                                scanDepthText = ""
                            }
                        }
                    
                    Text("(0 = 루트만, 최대 25)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Text("깊이가 높을수록 더 많은 하위 폴더를 스캔합니다.\n0을 입력하면 해당 폴더만 스캔합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Spacer()
            
            HStack {
                Button("취소") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                .disabled(isScanning)
                
                Spacer()
                
                Button {
                    isScanning = true
                    let depth = Int(scanDepthText) ?? folder.scanDepth
                    appState.updateFolderScanDepth(folder, depth: depth)
                    Task {
                        await appState.scanFolder(folder)
                        await MainActor.run {
                            isScanning = false
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 16, height: 16)
                            Text("스캔 중...")
                        } else {
                            Text("저장 후 재스캔")
                        }
                    }
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(isScanning)
            }
        }
        .padding()
        .frame(width: 350, height: 280)
    }
}

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }
        
        self.init(
            red: Double((rgb & 0xFF0000) >> 16) / 255.0,
            green: Double((rgb & 0x00FF00) >> 8) / 255.0,
            blue: Double(rgb & 0x0000FF) / 255.0
        )
    }
}

#Preview {
    SidebarView()
        .environmentObject(AppState())
}
