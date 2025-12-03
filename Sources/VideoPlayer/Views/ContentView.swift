import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        NavigationSplitView {
            SidebarView()
                .frame(minWidth: 240)
        } detail: {
            VideoGridView()
        }
        .background(Color.black.opacity(0.95))
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}

