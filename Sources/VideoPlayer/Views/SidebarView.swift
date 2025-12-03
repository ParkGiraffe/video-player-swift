import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var showFolderPicker = false
    @State private var showFolderSettings: MountedFolder?
    @State private var newTagName = ""
    @State private var newTagColor = Color(red: 0.39, green: 0.4, blue: 0.95)
    @State private var newLanguageCode = ""
    @State private var newLanguageName = ""
    
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
                    HStack {
                        Button {
                            appState.filterByFolder(folder)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(appState.selectedFolder?.id == folder.id ? .accentColor : .primary)
                        
                        Spacer()
                        
                        if appState.isScanningFolder == folder.path {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Menu {
                                Button {
                                    showFolderSettings = folder
                                } label: {
                                    Label("설정", systemImage: "gearshape")
                                }
                                
                                Button {
                                    Task {
                                        await appState.scanFolder(folder)
                                    }
                                } label: {
                                    Label("재스캔", systemImage: "arrow.clockwise")
                                }
                                
                                Divider()
                                
                                Button(role: .destructive) {
                                    appState.removeMountedFolder(folder)
                                } label: {
                                    Label("제거", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
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
}

// Folder Settings Sheet
struct FolderSettingsSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let folder: MountedFolder
    @State private var scanDepthText: String
    
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
                
                Spacer()
                
                Button("저장 후 재스캔") {
                    let depth = Int(scanDepthText) ?? folder.scanDepth
                    appState.updateFolderScanDepth(folder, depth: depth)
                    Task {
                        await appState.scanFolder(folder)
                    }
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
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
