import SwiftUI

struct VideoDetailSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let video: Video
    @State private var newParticipantName = ""
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("영상 정보")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Video Info
                    VStack(alignment: .leading, spacing: 8) {
                        Text(video.filename)
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text(formatFileSize(video.size))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    // Tags
                    VStack(alignment: .leading, spacing: 12) {
                        Text("태그")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if appState.tags.isEmpty {
                            Text("태그가 없습니다. 사이드바에서 태그를 추가하세요.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    let isAssigned = appState.isTagAssignedToVideo(tag: tag, video: video)
                                    
                                    Button {
                                        if isAssigned {
                                            appState.removeTagFromVideo(tag: tag, video: video)
                                        } else {
                                            appState.assignTagToVideo(tag: tag, video: video)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Circle()
                                                .fill(Color(hex: tag.color) ?? .blue)
                                                .frame(width: 8, height: 8)
                                            Text(tag.name)
                                                .font(.caption)
                                            
                                            if isAssigned {
                                                Image(systemName: "checkmark")
                                                    .font(.caption2)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isAssigned ? (Color(hex: tag.color) ?? .blue).opacity(0.2) : Color.secondary.opacity(0.1))
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    // Participants - 텍스트 입력으로 추가
                    VStack(alignment: .leading, spacing: 12) {
                        Text("참가자")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        // 새 참가자 입력
                        HStack {
                            TextField("참가자 이름 입력 후 Enter", text: $newParticipantName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    addParticipant()
                                }
                            
                            Button {
                                addParticipant()
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(newParticipantName.isEmpty ? .secondary : .accentColor)
                            }
                            .buttonStyle(.plain)
                            .disabled(newParticipantName.isEmpty)
                        }
                        
                        // 할당된 참가자 목록
                        let assignedParticipants = appState.participants.filter { 
                            appState.isParticipantAssignedToVideo(participant: $0, video: video) 
                        }
                        
                        if !assignedParticipants.isEmpty {
                            FlowLayout(spacing: 8) {
                                ForEach(assignedParticipants) { participant in
                                    HStack(spacing: 4) {
                                        Image(systemName: "person.fill")
                                            .font(.caption2)
                                        Text(participant.name)
                                            .font(.caption)
                                        
                                        Button {
                                            appState.removeParticipantFromVideo(participant: participant, video: video)
                                        } label: {
                                            Image(systemName: "xmark")
                                                .font(.system(size: 8, weight: .bold))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color.accentColor.opacity(0.2))
                                    .cornerRadius(16)
                                }
                            }
                        }
                        
                        // 기존 참가자 목록에서 선택
                        let unassignedParticipants = appState.participants.filter { 
                            !appState.isParticipantAssignedToVideo(participant: $0, video: video) 
                        }
                        
                        if !unassignedParticipants.isEmpty {
                            Text("기존 참가자에서 선택:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            FlowLayout(spacing: 8) {
                                ForEach(unassignedParticipants) { participant in
                                    Button {
                                        appState.assignParticipantToVideo(participant: participant, video: video)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "person")
                                                .font(.caption2)
                                            Text(participant.name)
                                                .font(.caption)
                                            Image(systemName: "plus")
                                                .font(.caption2)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.secondary.opacity(0.1))
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    Divider()
                    
                    // Languages
                    VStack(alignment: .leading, spacing: 12) {
                        Text("언어")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        if appState.languages.isEmpty {
                            Text("언어가 없습니다. 사이드바에서 언어를 추가하세요.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            FlowLayout(spacing: 8) {
                                ForEach(appState.languages) { language in
                                    let isAssigned = appState.isLanguageAssignedToVideo(language: language, video: video)
                                    
                                    Button {
                                        if isAssigned {
                                            appState.removeLanguageFromVideo(language: language, video: video)
                                        } else {
                                            appState.assignLanguageToVideo(language: language, video: video)
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(language.code)
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                            Text(language.name)
                                                .font(.caption)
                                            
                                            if isAssigned {
                                                Image(systemName: "checkmark")
                                                    .font(.caption2)
                                            }
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(isAssigned ? Color.green.opacity(0.2) : Color.secondary.opacity(0.1))
                                        .cornerRadius(16)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 4)
            }
            
            Spacer()
            
            // Action buttons
            HStack {
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Label("저장", systemImage: "checkmark")
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 480, height: 600)
    }
    
    private func addParticipant() {
        guard !newParticipantName.isEmpty else { return }
        
        // 기존에 같은 이름의 참가자가 있는지 확인
        if let existing = appState.participants.first(where: { $0.name.lowercased() == newParticipantName.lowercased() }) {
            // 이미 있으면 그걸 할당
            if !appState.isParticipantAssignedToVideo(participant: existing, video: video) {
                appState.assignParticipantToVideo(participant: existing, video: video)
            }
        } else {
            // 없으면 새로 만들고 할당
            appState.createParticipantAndAssign(name: newParticipantName, video: video)
        }
        
        newParticipantName = ""
    }
    
    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// FlowLayout for tags/participants
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                      y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                
                lineHeight = max(lineHeight, size.height)
                currentX += size.width + spacing
                
                self.size.width = max(self.size.width, currentX)
            }
            
            self.size.height = currentY + lineHeight
        }
    }
}

#Preview {
    VideoDetailSheet(video: Video(
        path: "/test/video.mp4",
        filename: "test_video.mp4",
        folderPath: "/test",
        size: 1024 * 1024 * 100
    ))
    .environmentObject(AppState())
}
