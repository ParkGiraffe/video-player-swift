import SwiftUI
import AppKit

@main
struct VideoPlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1200, minHeight: 800)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
        
        // Player window
        WindowGroup("Player", id: "player", for: Video.ID.self) { $videoId in
            if let videoId = videoId,
               let video = appState.videos.first(where: { $0.id == videoId }) {
                PlayerWindow(video: video)
                    .environmentObject(appState)
            }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 앱을 regular app으로 설정 (Dock에 표시, 키보드 포커스 받음)
        NSApp.setActivationPolicy(.regular)
        
        // 앱을 최전면으로 활성화
        NSApp.activate(ignoringOtherApps: true)
        
        // 저장된 폴더 북마크 복원
        BookmarkService.shared.restoreAllBookmarks()
        
        // 메인 윈도우를 key window로 만듦
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        VideoPlayerService.shared.stop()
        BookmarkService.shared.stopAllAccess()
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
    
    func applicationDidBecomeActive(_ notification: Notification) {
        // 앱이 활성화될 때마다 모든 윈도우를 앞으로
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock 아이콘 클릭 시 윈도우를 앞으로
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }
}
