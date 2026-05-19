//
//  GlassTubeApp.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AppKit

extension Notification.Name {
    static let glassTubeToggleSidebar = Notification.Name("GlassTubeToggleSidebar")
    static let glassTubePlaybackToggle = Notification.Name("GlassTubePlaybackToggle")
    static let glassTubeSeekForward = Notification.Name("GlassTubeSeekForward")
    static let glassTubeSeekBackward = Notification.Name("GlassTubeSeekBackward")
    static let glassTubeVolumeUp = Notification.Name("GlassTubeVolumeUp")
    static let glassTubeVolumeDown = Notification.Name("GlassTubeVolumeDown")
    static let glassTubeToggleVideoFullscreen = Notification.Name("GlassTubeToggleVideoFullscreen")
    static let glassTubeToggleTheaterMode = Notification.Name("GlassTubeToggleTheaterMode")
    static let glassTubeStopPlayback = Notification.Name("GlassTubeStopPlayback")
}

@main
struct GlassTubeApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var appNavigationModel = AppNavigationModel()
    @StateObject private var youtubeService = YouTubeService()
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var extensionsManager = ExtensionsManager()
    @StateObject private var authManager = AuthManager()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = true
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appNavigationModel)
                .environmentObject(youtubeService)
                .environmentObject(downloadManager)
                .environmentObject(extensionsManager)
                .environmentObject(authManager)
                .frame(minWidth: 960, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // Debug menu
            CommandMenu("Debug") {
                Button("Test YouTube API") {
                    openWindow(id: "test")
                }
            }
            
            // Playback menu
            CommandMenu("Playback") {
                Button("Play/Pause") {
                    NotificationCenter.default.post(name: .glassTubePlaybackToggle, object: nil)
                }
                
                Divider()
                
                Button("Forward 5s") {
                    NotificationCenter.default.post(name: .glassTubeSeekForward, object: nil)
                }
                
                Button("Backward 5s") {
                    NotificationCenter.default.post(name: .glassTubeSeekBackward, object: nil)
                }
                
                Divider()
                
                Button("Increase Volume") {
                    NotificationCenter.default.post(name: .glassTubeVolumeUp, object: nil)
                }
                
                Button("Decrease Volume") {
                    NotificationCenter.default.post(name: .glassTubeVolumeDown, object: nil)
                }
            }
            
            // View menu additions
            CommandGroup(after: .sidebar) {
                Button("Toggle Sidebar") {
                    NotificationCenter.default.post(name: .glassTubeToggleSidebar, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                
                Divider()
                
                Button("Theater Mode") {
                    NotificationCenter.default.post(name: .glassTubeToggleTheaterMode, object: nil)
                }
                .keyboardShortcut("t", modifiers: [])
                
                Button("Full Screen") {
                    NotificationCenter.default.post(name: .glassTubeToggleVideoFullscreen, object: nil)
                }
                .keyboardShortcut("f", modifiers: [])
            }
        }

        // Test window
        Window("YouTube API Test", id: "test") {
            TestVideoView()
                .environmentObject(appNavigationModel)
                .environmentObject(youtubeService)
                .environmentObject(downloadManager)
                .environmentObject(authManager)
                .environmentObject(extensionsManager)
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])
    }
}
