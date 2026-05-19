//
//  ContentView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var extensionsManager: ExtensionsManager
    @EnvironmentObject private var authManager: AuthManager
    @State private var selectedDestination: NavigationDestination = .home
    @State private var selectedLibrary: LibraryDestination?
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarVisibilityBeforeImmersiveMode: NavigationSplitViewVisibility = .all
    @State private var searchText = ""
    @State private var isShowingSearch = false
    @State private var showingSettings = false
    @State private var showingAccount = false
    @State private var accountOAuthClientIDDraft = ""
    @State private var accountOAuthClientSecretDraft = ""
    @State private var showFullscreenTabStrip = false
    @State private var isHoveringFullscreenTabStrip = false

    var body: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            // Left Sidebar
            SidebarView(
                selectedDestination: $selectedDestination,
                selectedLibrary: $selectedLibrary
            )
            .navigationSplitViewColumnWidth(
                min: 220,
                ideal: 240,
                max: 300
            )
        } detail: {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if appNavigationModel.hasWatchTabs && !appNavigationModel.isVideoFullscreen {
                        WatchTabStripView()
                            .environmentObject(appNavigationModel)
                    }

                    if let activeWatchVideo = appNavigationModel.activeWatchVideo {
                        VideoLoadingWatchView(video: activeWatchVideo) { nextVideo in
                            appNavigationModel.open(video: nextVideo)
                        }
                    } else {
                        MainContentView(
                            destination: selectedDestination,
                            libraryDestination: selectedLibrary,
                            searchText: $searchText,
                            isShowingSearch: $isShowingSearch
                        )
                    }
                }

                if appNavigationModel.isVideoFullscreen && appNavigationModel.hasWatchTabs {
                    VStack(spacing: 0) {
                        Color.clear
                            .frame(height: 56)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                if hovering {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showFullscreenTabStrip = true
                                    }
                                } else if !isHoveringFullscreenTabStrip {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showFullscreenTabStrip = false
                                    }
                                }
                            }
                        Spacer()
                    }

                    if showFullscreenTabStrip {
                        WatchTabStripView()
                            .environmentObject(appNavigationModel)
                            .onHover { hovering in
                                isHoveringFullscreenTabStrip = hovering
                                if !hovering {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        showFullscreenTabStrip = false
                                    }
                                }
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .background(appNavigationModel.isVideoFullscreen ? Color.black : Color.clear)
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                SearchBarView(text: $searchText) {
                    performSearch()
                }
            }

            ToolbarItemGroup(placement: .automatic) {
                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings")

                Button(action: {
                    if !authManager.hasOAuthConfiguration && !authManager.isSignedIn && !authManager.isPolling {
                        showingAccount = false
                        showingSettings = true
                    } else {
                        showingAccount.toggle()
                    }
                }) {
                    Image(systemName: "person.crop.circle")
                }
                .help("Account")
                .popover(isPresented: $showingAccount) {
                    AccountPopover(
                        authManager: authManager,
                        oauthClientID: $accountOAuthClientIDDraft,
                        oauthClientSecret: $accountOAuthClientSecretDraft
                    ) {
                        showingAccount = false
                        DispatchQueue.main.async {
                            showingSettings = true
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .environmentObject(authManager)
                .environmentObject(downloadManager)
                .environmentObject(extensionsManager)
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty {
                isShowingSearch = false
            }
        }
        .onChange(of: selectedDestination) { _, _ in
            appNavigationModel.showBrowse()
        }
        .onChange(of: selectedLibrary) { _, _ in
            appNavigationModel.showBrowse()
        }
        .onReceive(NotificationCenter.default.publisher(for: .glassTubeToggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.2)) {
                sidebarVisibility = (sidebarVisibility == .all) ? .detailOnly : .all
            }
        }
        .onChange(of: appNavigationModel.isVideoFullscreen) { _, isFullscreen in
            updateSidebarForImmersiveMode(isFullscreen || appNavigationModel.isTheaterMode)
            if !isFullscreen {
                showFullscreenTabStrip = false
                isHoveringFullscreenTabStrip = false
            }
        }
        .onChange(of: appNavigationModel.isTheaterMode) { _, isTheaterMode in
            updateSidebarForImmersiveMode(appNavigationModel.isVideoFullscreen || isTheaterMode)
        }
    }

    private func updateSidebarForImmersiveMode(_ isImmersive: Bool) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if isImmersive {
                sidebarVisibilityBeforeImmersiveMode = sidebarVisibility
                sidebarVisibility = .detailOnly
            } else {
                sidebarVisibility = sidebarVisibilityBeforeImmersiveMode
            }
        }
    }

    private func performSearch() {
        guard !searchText.isEmpty else { return }
        isShowingSearch = true
        Task {
            await youtubeService.search(query: searchText)
        }
    }
}

struct WatchTabStripView: View {
    @EnvironmentObject private var appNavigationModel: AppNavigationModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    appNavigationModel.showBrowse()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "square.grid.2x2")
                        Text("Browse")
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(tabBackground(isActive: appNavigationModel.activeWatchTabID == nil))
                }
                .buttonStyle(.plain)

                ForEach(appNavigationModel.watchTabs) { tab in
                    HStack(spacing: 6) {
                        Button {
                            appNavigationModel.activate(tabID: tab.id)
                        } label: {
                            Text(tab.video.title)
                                .lineLimit(1)
                                .font(.caption)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if appNavigationModel.activeWatchTabID == tab.id {
                                NotificationCenter.default.post(name: .glassTubeStopPlayback, object: nil)
                            }
                            appNavigationModel.close(tabID: tab.id)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .frame(width: 250)
                    .background(tabBackground(isActive: appNavigationModel.activeWatchTabID == tab.id))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func tabBackground(isActive: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isActive ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
    }
}

// MARK: - Navigation Destinations

enum NavigationDestination: String, CaseIterable, Identifiable {
    case home = "Home"
    case subscriptions = "Subscriptions"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .home: return "house.fill"
        case .subscriptions: return "play.rectangle.on.rectangle.fill"
        }
    }
}

enum LibraryDestination: String, CaseIterable, Identifiable {
    case playlists = "Playlists"
    case yourVideos = "Your videos"
    case watchLater = "Watch Later"
    case likedVideos = "Liked videos"
    case downloads = "Downloads"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .playlists: return "music.note.list"
        case .yourVideos: return "play.square.stack"
        case .watchLater: return "clock.badge.checkmark"
        case .likedVideos: return "hand.thumbsup.fill"
        case .downloads: return "arrow.down.circle.fill"
        }
    }
}

// MARK: - Account Popover

struct AccountPopover: View {
    @ObservedObject var authManager: AuthManager
    @Binding var oauthClientID: String
    @Binding var oauthClientSecret: String
    let onOpenAuthenticationSettings: () -> Void
    @State private var localSetupMessage: String?

    init(
        authManager: AuthManager,
        oauthClientID: Binding<String>,
        oauthClientSecret: Binding<String>,
        onOpenAuthenticationSettings: @escaping () -> Void = {}
    ) {
        self.authManager = authManager
        _oauthClientID = oauthClientID
        _oauthClientSecret = oauthClientSecret
        self.onOpenAuthenticationSettings = onOpenAuthenticationSettings
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if authManager.isSignedIn {
                // Signed in state
                HStack(spacing: 12) {
                    if !authManager.userAvatar.isEmpty, let url = URL(string: authManager.userAvatar) {
                        CachedAsyncImage(url: url) { image in
                            image.resizable().aspectRatio(contentMode: .fill).clipShape(Circle())
                        } placeholder: {
                            accountInitialCircle
                        }
                        .frame(width: 48, height: 48)
                    } else {
                        accountInitialCircle
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(authManager.userName)
                            .font(.body)
                            .fontWeight(.medium)
                        Text(authManager.userEmail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                Button(action: { authManager.signOut() }) {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                        Text("Sign Out")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .buttonStyle(.plain)
            } else if authManager.isPolling, let userCode = authManager.userCode {
                // Device code flow — waiting for user to authorize
                VStack(spacing: 16) {
                    Image(systemName: "link.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(Color.accentColor)

                    Text("Enter this code")
                        .font(.headline)

                    Text(userCode)
                        .font(.system(.title, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundStyle(Color.accentColor)
                        .textSelection(.enabled)

                    if let urlString = authManager.verificationURL,
                       let url = URL(string: urlString) {
                        Link(destination: url) {
                            HStack {
                                Image(systemName: "safari")
                                Text("Open Google Sign-In")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Waiting for authorization...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Cancel") {
                        authManager.cancelSignIn()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    if let errorMessage = authManager.authErrorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(20)
            } else {
                // Signed out state
                VStack(spacing: 14) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)

                    Text("Sign in to YouTube")
                        .font(.headline)

                    Text("Sign in to access subscriptions, liked videos, and personalized recommendations.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Before first login, open Settings > Authentication and complete the Audience > Test users step for your Google email.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                    if authManager.hasOAuthConfiguration {
                        Button(action: {
                            Task { await authManager.startDeviceCodeFlow() }
                        }) {
                            HStack {
                                Image(systemName: "person.badge.key")
                                Text("Sign In with Google")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            onOpenAuthenticationSettings()
                        } label: {
                            HStack {
                                Image(systemName: "list.bullet.clipboard")
                                Text("Open Setup Guide in Settings")
                            }
                        }
                        .buttonStyle(.bordered)
                        .font(.caption)

                        Link(
                            "Open OAuth Consent Screen (Audience tab)",
                            destination: URL(string: "https://console.cloud.google.com/apis/credentials/consent")!
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Quick setup (one time)")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)

                            TextField("Client ID", text: $oauthClientID)
                                .textFieldStyle(.roundedBorder)

                            SecureField("Client Secret", text: $oauthClientSecret)
                                .textFieldStyle(.roundedBorder)

                            Button(action: saveAndStartSignIn) {
                                HStack {
                                    Image(systemName: "checkmark.circle")
                                    Text("Save and Sign In")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!hasOAuthInput)

                            Button {
                                onOpenAuthenticationSettings()
                            } label: {
                                HStack {
                                    Image(systemName: "list.bullet.clipboard")
                                    Text("Open Authentication Setup Guide")
                                }
                            }
                            .buttonStyle(.bordered)
                            .font(.caption)

                            if let localSetupMessage {
                                Text(localSetupMessage)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if let errorMessage = authManager.authErrorMessage {
                        Text(errorMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Link(
                        "Official Google OAuth setup docs",
                        destination: URL(string: "https://developers.google.com/identity/protocols/oauth2/limited-input-device#creatingcred")!
                    )
                    .font(.caption)
                }
                .padding(20)
            }
        }
        .frame(width: 340)
        .onAppear {
            let hasDraftValues =
                !oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                !oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if !hasDraftValues {
                let oauth = authManager.oauthConfiguration()
                oauthClientID = oauth.clientID
                oauthClientSecret = oauth.clientSecret
            }

            localSetupMessage = nil
        }
    }

    private var hasOAuthInput: Bool {
        !oauthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !oauthClientSecret.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func saveAndStartSignIn() {
        authManager.saveOAuthConfiguration(
            clientID: oauthClientID,
            clientSecret: oauthClientSecret
        )
        localSetupMessage = "Credentials saved. Starting Google sign-in... If Google blocks access, complete OAuth consent screen > Audience > Test users in Settings and retry."

        Task {
            await authManager.startDeviceCodeFlow()
        }
    }

    private var accountInitialCircle: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.3))
            .frame(width: 48, height: 48)
            .overlay {
                Text(String(authManager.userName.prefix(1)).uppercased())
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }
    }
}

#Preview {
    ContentView()
    .environmentObject(AppNavigationModel())
        .environmentObject(YouTubeService())
        .environmentObject(DownloadManager())
        .environmentObject(ExtensionsManager())
        .environmentObject(AuthManager())
}
