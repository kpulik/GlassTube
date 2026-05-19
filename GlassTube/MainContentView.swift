//
//  MainContentView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI

private let standardVideoGridColumns: [GridItem] = [
    GridItem(.adaptive(minimum: 300, maximum: 300), spacing: 20, alignment: .top)
]

struct MainContentView: View {
    let destination: NavigationDestination
    var libraryDestination: LibraryDestination?
    @Binding var searchText: String
    @Binding var isShowingSearch: Bool

    var body: some View {
        Group {
            if isShowingSearch {
                SearchResultsView(query: searchText)
            } else if let libraryDestination {
                switch libraryDestination {
                case .downloads:
                    DownloadsView()
                default:
                    AuthenticatedLibraryDestinationView(destination: libraryDestination)
                }
            } else {
                switch destination {
                case .home:
                    HomeView()
                case .subscriptions:
                    SubscriptionsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct AuthenticatedLibraryDestinationView: View {
    let destination: LibraryDestination
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    @State private var videos: [Video] = []
    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var fetchLimit = 50
    @State private var loadErrorMessage: String?
    @State private var selectedPlaylist: Playlist?

    @State private var glasstubeWatchLaterVideos: [Video] = []
    @State private var isLoadingGlassTubeWatchLater = false
    @State private var glasstubeWatchLaterError: String?
    @State private var glasstubeWatchLaterPlaylistID: String?
    @State private var isInfoExpanded = false

    var body: some View {
        Group {
            if !authManager.isSignedIn {
                signedOutView
            } else if destination == .playlists {
                playlistsView
            } else if destination == .watchLater {
                glasstubeWatchLaterView
            } else {
                videosView
            }
        }
        .navigationTitle(destination.rawValue)
        .task(id: "\(destination.rawValue)-\(authManager.isSignedIn)") {
            fetchLimit = 50
            hasReachedEnd = false
            await loadDestinationContent(forceReload: true)
        }
        .sheet(item: $selectedPlaylist) { playlist in
            PlaylistDetailView(playlist: playlist)
                .environmentObject(appNavigationModel)
                .environmentObject(authManager)
                .environmentObject(youtubeService)
        }
    }

    private var glasstubeWatchLaterView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Collapsible Info Banner
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isInfoExpanded.toggle()
                        }
                    } label: {
                        HStack {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            Text("About GlassTube Watch Later")
                                .font(.headline)
                            Spacer()
                            Image(systemName: isInfoExpanded ? "chevron.up" : "chevron.down")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                    
                    if isInfoExpanded {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Why is this not my real Watch Later?")
                                .font(.subheadline.weight(.semibold))
                            Text("Due to YouTube API restrictions, GlassTube cannot read your official Watch Later playlist. Instead, videos you save are added to a private playlist called 'GlassTube Watch Later' in your account.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Divider()
                            
                            Text("Where do my saves go?")
                                .font(.subheadline.weight(.semibold))
                            Text("Check Settings → Content → Watch Later Destination to choose between:\n• GlassTube Playlist (default) — viewable here\n• YouTube Watch Later — syncs with YouTube but can't be viewed in the app")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding()
                .background(.ultraThinMaterial)
                .cornerRadius(12)

                if isLoadingGlassTubeWatchLater {
                    ProgressView("Loading GlassTube Watch Later...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let glasstubeWatchLaterError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(glasstubeWatchLaterError)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadGlassTubeWatchLater() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if glasstubeWatchLaterVideos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No videos in GlassTube Watch Later")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 10) {
                            ForEach(glasstubeWatchLaterVideos) { video in
                                PlaylistVideoRow(
                                    video: video,
                                    onTap: {
                                        appNavigationModel.open(video: video)
                                    },
                                    onDelete: {
                                        Task { await deleteVideoFromGlassTubeWatchLater(video) }
                                    }
                                )
                            }
                            .onMove { source, destination in
                                glasstubeWatchLaterVideos.move(fromOffsets: source, toOffset: destination)
                                Task { await reorderGlassTubeWatchLater() }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
            .padding(.horizontal, 20)
        }
        .onAppear {
            Task { await loadGlassTubeWatchLater() }
        }
    }

    private func loadGlassTubeWatchLater() async {
        isLoadingGlassTubeWatchLater = true
        glasstubeWatchLaterError = nil
        defer { isLoadingGlassTubeWatchLater = false }
        guard let accessToken = await authManager.getValidToken() else {
            glasstubeWatchLaterError = "Sign in to view your GlassTube Watch Later playlist."
            return
        }
        do {
            let playlists = try await youtubeService.fetchMyPlaylists(accessToken: accessToken)
            if let gtPlaylist = playlists.first(where: { $0.title == "GlassTube Watch Later" }) {
                glasstubeWatchLaterPlaylistID = gtPlaylist.id
                let videos = try await youtubeService.fetchVideosInPlaylist(playlistID: gtPlaylist.id, accessToken: accessToken)
                glasstubeWatchLaterVideos = videos
            } else {
                glasstubeWatchLaterPlaylistID = nil
                glasstubeWatchLaterVideos = []
            }
        } catch {
            glasstubeWatchLaterError = error.localizedDescription
        }
    }

    private func deleteVideoFromGlassTubeWatchLater(_ video: Video) async {
        guard let playlistID = glasstubeWatchLaterPlaylistID,
              let accessToken = await authManager.getValidToken() else {
            return
        }

        glasstubeWatchLaterVideos.removeAll { $0.id == video.id }

        do {
            try await youtubeService.removeVideoFromPlaylist(
                videoId: video.id,
                playlistId: playlistID,
                accessToken: accessToken
            )
        } catch {
            await loadGlassTubeWatchLater()
        }
    }

    private func reorderGlassTubeWatchLater() async {
        // The local array has already been reordered by the .onMove modifier.
        // In a production app, you'd call an API to persist the new order.
        // YouTube's Data API doesn't have a simple reorder endpoint, so this
        // would require deleting all items and re-adding them in the new order,
        // which is expensive. For now, we just maintain local order during the session.
    }

    private var signedOutView: some View {
        VStack(spacing: 16) {
            Image(systemName: destination.icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(destination.rawValue)
                .font(.title)
                .fontWeight(.bold)
            Text("Sign in to access your \(destination.rawValue.lowercased())")
                .foregroundStyle(.secondary)
            Text("Use the account button in the toolbar to sign in.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var playlistsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && playlists.isEmpty {
                    ProgressView("Loading playlists...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let loadErrorMessage, playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(loadErrorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadDestinationContent(forceReload: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No playlists found")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        LazyVStack(spacing: 10) {
                            ForEach(playlists) { playlist in
                                playlistRow(playlist)
                            }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 16)
                                Spacer()
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("library-playlists-load-more-\(playlists.count)-\(fetchLimit)")
                            .onAppear {
                                Task { await loadMoreDestinationContentIfNeeded() }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private var videosView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isLoading && videos.isEmpty {
                    ProgressView("Loading \(destination.rawValue.lowercased())...")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else if let loadErrorMessage, videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(loadErrorMessage)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadDestinationContent(forceReload: true) }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: destination.icon)
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No \(destination.rawValue.lowercased()) found")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    VStack(spacing: 0) {
                        LazyVGrid(
                            columns: standardVideoGridColumns,
                            spacing: 28
                        ) {
                            ForEach(videos) { video in
                                VideoCardView(video: video) {
                                    appNavigationModel.open(video: video)
                                }
                            }
                        }

                        if isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .padding(.vertical, 16)
                                Spacer()
                            }
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("library-videos-load-more-\(destination.rawValue)-\(videos.count)-\(fetchLimit)")
                            .onAppear {
                                Task { await loadMoreDestinationContentIfNeeded() }
                            }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
        }
    }

    private func playlistRow(_ playlist: Playlist) -> some View {
        Button {
            selectedPlaylist = playlist
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if let thumbnailURL = playlist.thumbnailURL,
                   let url = URL(string: thumbnailURL),
                   !thumbnailURL.isEmpty {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.08))
                            .overlay { ProgressView() }
                    }
                    .frame(width: 180, height: 102)
                    .cornerRadius(8)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.08))
                        .frame(width: 180, height: 102)
                        .overlay {
                            Image(systemName: "music.note.list")
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(playlist.title)
                        .font(.headline)
                        .lineLimit(2)

                    Text("\(playlist.videoCount) videos")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !playlist.channelName.isEmpty {
                        Text(playlist.channelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func loadDestinationContent(forceReload: Bool = false, limitOverride: Int? = nil) async {
        let requestedLimit = limitOverride ?? fetchLimit

        if !forceReload && limitOverride == nil {
            switch destination {
            case .playlists where !playlists.isEmpty:
                return
            case .yourVideos where !videos.isEmpty,
                 .watchLater where !videos.isEmpty,
                 .likedVideos where !videos.isEmpty:
                return
            default:
                break
            }
        }

        guard authManager.isSignedIn else {
            videos = []
            playlists = []
            loadErrorMessage = nil
            return
        }

        guard let token = await authManager.getValidToken() else {
            videos = []
            playlists = []
            loadErrorMessage = "Your session expired. Please sign in again."
            return
        }

        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            switch destination {
            case .playlists:
                playlists = try await youtubeService.fetchMyPlaylists(accessToken: token, maxResults: requestedLimit)
                videos = []
            case .yourVideos:
                videos = try await youtubeService.fetchMyUploads(accessToken: token, maxResults: requestedLimit)
                playlists = []
            case .watchLater:
                var mergedVideos: [Video] = []
                if let innertubeWatchLater = try? await youtubeService.api.getWatchLaterFeed(accessToken: token),
                   !innertubeWatchLater.isEmpty {
                    mergedVideos.append(contentsOf: innertubeWatchLater)
                }

                if mergedVideos.count < requestedLimit,
                   let personalWatchLater = try? await youtubeService.fetchVideosFromPersonalPlaylist(
                    kind: .watchLater,
                    accessToken: token,
                    maxResults: requestedLimit
                   ),
                   !personalWatchLater.isEmpty {
                    mergedVideos.append(contentsOf: personalWatchLater)
                }

                videos = deduplicateVideosByID(mergedVideos, limit: requestedLimit)
                playlists = []
            case .likedVideos:
                var mergedVideos: [Video] = []
                if let innertubeLikedVideos = try? await youtubeService.api.getLikedVideosFeed(accessToken: token),
                   !innertubeLikedVideos.isEmpty {
                    mergedVideos.append(contentsOf: innertubeLikedVideos)
                }

                if mergedVideos.count < requestedLimit,
                   let likedVideos = try? await youtubeService.fetchVideosFromPersonalPlaylist(
                    kind: .likedVideos,
                    accessToken: token,
                    maxResults: requestedLimit
                   ),
                   !likedVideos.isEmpty {
                    mergedVideos.append(contentsOf: likedVideos)
                }

                videos = deduplicateVideosByID(mergedVideos, limit: requestedLimit)
                playlists = []
            case .downloads:
                break
            }
        } catch {
            videos = []
            playlists = []
            if youtubeService.isQuotaExceededError(error) {
                loadErrorMessage = youtubeService.quotaExceededMessage(for: destination.rawValue)
            } else {
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreDestinationContentIfNeeded() async {
        guard authManager.isSignedIn else { return }
        guard destination != .downloads else { return }
        guard !isLoading else { return }
        guard !isLoadingMore else { return }
        guard !hasReachedEnd else { return }

        let previousCount: Int
        switch destination {
        case .playlists:
            guard !playlists.isEmpty else { return }
            previousCount = playlists.count
        case .yourVideos, .watchLater, .likedVideos:
            guard !videos.isEmpty else { return }
            previousCount = videos.count
        case .downloads:
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextLimit = fetchLimit + 50
        await loadDestinationContent(forceReload: true, limitOverride: nextLimit)

        let newCount: Int
        switch destination {
        case .playlists:
            newCount = playlists.count
        case .yourVideos, .watchLater, .likedVideos:
            newCount = videos.count
        case .downloads:
            return
        }

        if newCount <= previousCount {
            hasReachedEnd = true
        } else {
            fetchLimit = nextLimit
        }
    }

    private func deduplicateVideosByID(_ videos: [Video], limit: Int) -> [Video] {
        var seenIDs = Set<String>()
        var unique: [Video] = []

        for video in videos where seenIDs.insert(video.id).inserted {
            unique.append(video)
            if unique.count >= limit {
                break
            }
        }

        return unique
    }
}

// MARK: - Playlist Video Row (for drag and delete)

struct PlaylistVideoRow: View {
    let video: Video
    let onTap: () -> Void
    let onDelete: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                CachedAsyncImage(url: URL(string: video.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.1))
                        .overlay { ProgressView() }
                }
                .frame(width: 180, height: 102)
                .cornerRadius(8)
                
                if !video.isLive {
                    Text(video.formattedDuration)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background { Capsule().fill(.black.opacity(0.8)) }
                        .padding(6)
                }
            }
            
            // Metadata
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)
                
                Text(video.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                HStack(spacing: 4) {
                    Text(video.formattedViews)
                    Text("•")
                    Text(video.relativeTime)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Delete button (visible on hover)
            if isHovered {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                        .padding(8)
                }
                .buttonStyle(.plain)
                .help("Remove from playlist")
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    @Environment(\.dismiss) private var dismiss
    @State private var videos: [Video] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var fetchLimit = 50
    @State private var loadErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && videos.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading playlist videos...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadErrorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text(loadErrorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadVideos() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                } else if videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("No videos found in this playlist")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            LazyVStack(spacing: 10) {
                                ForEach(videos) { video in
                                    PlaylistVideoRow(
                                        video: video,
                                        onTap: {
                                            appNavigationModel.open(video: video)
                                        },
                                        onDelete: {
                                            Task { await deleteVideo(video) }
                                        }
                                    )
                                }
                                .onMove { source, destination in
                                    videos.move(fromOffsets: source, toOffset: destination)
                                    Task { await reorderVideos() }
                                }
                            }
                            .padding(.horizontal, 20)

                            if isLoadingMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .padding(.bottom, 24)
                                    Spacer()
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("playlist-load-more-\(playlist.id)-\(videos.count)-\(fetchLimit)")
                                .onAppear {
                                    Task { await loadMoreVideosIfNeeded() }
                                }
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle(playlist.title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: playlist.id) {
            fetchLimit = 50
            hasReachedEnd = false
            await loadVideos()
        }
    }

    private func loadVideos() async {
        guard authManager.isSignedIn else {
            loadErrorMessage = "Please sign in again to load playlist videos."
            return
        }

        guard let token = await authManager.getValidToken() else {
            loadErrorMessage = "Could not get a valid Google token. Please sign in again."
            return
        }

        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            videos = try await youtubeService.fetchVideosInPlaylist(
                playlistID: playlist.id,
                accessToken: token,
                maxResults: fetchLimit
            )
        } catch {
            videos = []
            if youtubeService.isQuotaExceededError(error) {
                loadErrorMessage = youtubeService.quotaExceededMessage(for: "Playlist videos")
            } else {
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    private func loadMoreVideosIfNeeded() async {
        guard !isLoading else { return }
        guard !isLoadingMore else { return }
        guard !hasReachedEnd else { return }
        guard !videos.isEmpty else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        let previousCount = videos.count
        fetchLimit += 50
        await loadVideos()

        if videos.count <= previousCount {
            hasReachedEnd = true
        }
    }

    private func deleteVideo(_ video: Video) async {
        guard let accessToken = await authManager.getValidToken() else {
            return
        }

        videos.removeAll { $0.id == video.id }

        do {
            try await youtubeService.removeVideoFromPlaylist(
                videoId: video.id,
                playlistId: playlist.id,
                accessToken: accessToken
            )
        } catch {
            await loadVideos()
        }
    }

    private func reorderVideos() async {
        // The local array has already been reordered by the .onMove modifier.
        // YouTube's Data API doesn't have a simple reorder endpoint, so this
        // would require deleting all items and re-adding them in the new order,
        // which is expensive. For now, we maintain local order during the session.
    }
}

struct PlaceholderLibraryView: View {
    let destination: LibraryDestination

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: destination.icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(destination.rawValue)
                .font(.title)
                .fontWeight(.bold)
            Text("Sign in to access your \(destination.rawValue.lowercased())")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(destination.rawValue)
    }
}

// MARK: - Home View

struct HomeView: View {
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Loading state
                if youtubeService.isLoading && youtubeService.homeVideos.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Loading videos...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if youtubeService.homeVideos.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)

                        Text("Could not load your home feed")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(youtubeService.homeFeedLoadFailureMessage(isSignedIn: authManager.isSignedIn))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)

                        Button("Retry") {
                            Task {
                                await loadHomeFeedForCurrentAuthState()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                }

                if !youtubeService.homeVideos.isEmpty {
                    // Video grid
                    LazyVGrid(
                        columns: standardVideoGridColumns,
                        spacing: 28
                    ) {
                        ForEach(Array(youtubeService.homeVideos.enumerated()), id: \.element.id) { index, video in
                            VideoCardView(video: video) {
                                appNavigationModel.open(video: video)
                            }
                            .onAppear {
                                triggerHomeLoadMoreIfNeeded(index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    if youtubeService.isLoadingMoreHome {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.bottom, 24)
                            Spacer()
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("home-load-more-\(youtubeService.homeVideos.count)")
                        .onAppear {
                            guard !youtubeService.homeVideos.isEmpty else { return }
                            Task {
                                await youtubeService.loadMoreHomeFeed()
                            }
                        }
                }
            }
        }
        .navigationTitle("Home")
        .task(id: authManager.isSignedIn) {
            await loadHomeFeedForCurrentAuthState()
        }
    }

    private func triggerHomeLoadMoreIfNeeded(index: Int) {
        let thresholdIndex = max(0, youtubeService.homeVideos.count - 8)
        guard index >= thresholdIndex else { return }
        Task {
            await youtubeService.loadMoreHomeFeed()
        }
    }

    private func loadHomeFeedForCurrentAuthState() async {
        if authManager.isSignedIn,
           let token = await authManager.getValidToken() {
            await youtubeService.loadHomeFeed(accessToken: token)
            return
        }

        if youtubeService.homeVideos.isEmpty || !authManager.isSignedIn {
            await youtubeService.loadHomeFeed()
        }
    }
}

// MARK: - Video Card View (using real Video model)

struct VideoCardView: View {
    let video: Video
    let onTap: () -> Void

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var downloadManager: DownloadManager
    
    @AppStorage("watchLaterDestination") private var watchLaterDestination = "glasstube"
    
    @State private var isHovered = false
    @State private var showingPlaylistPicker = false
    @State private var showingDownloadPicker = false
    @State private var availableFormats: [DownloadFormatOption] = []
    @State private var isLoadingFormats = false
    @State private var showingActionAlert = false
    @State private var actionMessage = ""
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack(alignment: .bottomTrailing) {
                // Load real thumbnail
                CachedAsyncImage(url: URL(string: video.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.1))
                        .aspectRatio(16/9, contentMode: .fit)
                        .overlay {
                            ProgressView()
                        }
                }
                .cornerRadius(12)
                .overlay(alignment: .topLeading) {
                    // LIVE badge overlay
                    if video.isLive {
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.red))
                            .padding(8)
                    }
                }

                // Duration badge (not for live videos)
                if !video.isLive {
                    Text(video.formattedDuration)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background {
                            Capsule()
                                .fill(.black.opacity(0.8))
                        }
                        .padding(8)
                }
            }
            .frame(height: 169)
            .overlay {
                if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }

            // Metadata
            HStack(alignment: .top, spacing: 10) {
                // Channel avatar
                if let avatarURL = video.channelAvatar, let url = URL(string: avatarURL) {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.primary.opacity(0.15))
                    }
                    .frame(width: 36, height: 36)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.15))
                        .frame(width: 36, height: 36)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .frame(height: 42, alignment: .topLeading)
                        .foregroundStyle(.primary)

                    Text(video.channelName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 4) {
                        Text(video.formattedViews)
                        Text("•")
                        Text(video.relativeTime)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                // Keep this independent from the card tap target.
                Menu {
                    Button("Play") { onTap() }
                    Button("Download Video") {
                        startDownload()
                    }
                    Button("Add to Watch Later") {
                        Task {
                            await addToWatchLater()
                        }
                    }
                    Button("Save to Playlist") {
                        showingPlaylistPicker = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(.secondary)
                        .padding(4)
                }
                .menuStyle(.borderlessButton)
                .opacity(isHovered ? 1 : 0.65)
            }
        }
        .frame(width: 300, height: 304, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .alert("Video Action", isPresented: $showingActionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage)
        }
        .sheet(isPresented: $showingPlaylistPicker) {
            PlaylistPickerSheet(video: video)
                .environmentObject(authManager)
                .environmentObject(youtubeService)
        }
        .sheet(isPresented: $showingDownloadPicker) {
            DownloadPickerSheet(
                videoId: video.id,
                videoTitle: video.title,
                channelName: video.channelName,
                thumbnailURL: video.thumbnailURL,
                isLoading: isLoadingFormats,
                formats: availableFormats,
                onDownloadWithFormat: { format in
                    downloadManager.downloadWithFormat(
                        videoId: video.id,
                        title: video.title,
                        channelName: video.channelName,
                        thumbnailURL: video.thumbnailURL,
                        formatOption: format
                    )
                    showingDownloadPicker = false
                }
            )
        }
    }

    private var isPlaceholderVideo: Bool {
        video.id.hasPrefix("mock_") || video.id.hasPrefix("sample_")
    }

    private func startDownload() {
        guard !isPlaceholderVideo else {
            presentMessage("This item cannot be downloaded.")
            return
        }

        showingDownloadPicker = true
        isLoadingFormats = true
        Task {
            let formats = await downloadManager.fetchAvailableQualities(videoId: video.id)
            availableFormats = formats
            isLoadingFormats = false
        }
    }

    private func addToWatchLater() async {
        guard !isPlaceholderVideo else {
            presentMessage("This item cannot be saved.")
            return
        }

        guard authManager.isSignedIn else {
            presentMessage("Sign in first to use Watch Later.")
            return
        }

        guard let token = await authManager.getValidToken() else {
            presentMessage("Could not get a valid token. Please sign in again.")
            return
        }

        do {
            if watchLaterDestination == "youtube" {
                // Add to YouTube's official Watch Later (write-only, can't be viewed in app)
                try await youtubeService.addVideoToWatchLater(videoId: video.id, accessToken: token)
                presentMessage("Added to YouTube Watch Later.")
            } else {
                // Add to GlassTube-managed playlist (readable in Library tab)
                try await youtubeService.addVideoToGlassTubeWatchLater(videoId: video.id, accessToken: token)
                presentMessage("Added to GlassTube Watch Later.")
            }
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                presentMessage(youtubeService.quotaExceededMessage(for: "Watch Later"))
            } else if youtubeService.isInsufficientScopeError(error) {
                presentMessage(youtubeService.insufficientScopeMessage(for: "Watch Later saves"))
            } else {
                presentMessage("Could not add to Watch Later: \(error.localizedDescription)")
            }
        }
    }

    private func presentMessage(_ message: String) {
        actionMessage = message
        showingActionAlert = true
    }
}

struct PlaylistPickerSheet: View {
    let video: Video

    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var youtubeService: YouTubeService
    @Environment(\.dismiss) private var dismiss

    @State private var playlists: [Playlist] = []
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var loadErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if !authManager.isSignedIn {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 40))
                            .foregroundStyle(.secondary)
                        Text("Sign in to save videos to playlists.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Loading playlists...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let loadErrorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text(loadErrorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task { await loadPlaylists() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if playlists.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("No playlists found")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(playlists) { playlist in
                        Button {
                            Task { await save(video: video, to: playlist) }
                        } label: {
                            HStack(spacing: 12) {
                                Group {
                                    if let thumbnailURL = playlist.thumbnailURL,
                                       let url = URL(string: thumbnailURL),
                                       !thumbnailURL.isEmpty {
                                        CachedAsyncImage(url: url) { image in
                                            image
                                                .resizable()
                                                .aspectRatio(16/9, contentMode: .fill)
                                                .clipped()
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color.primary.opacity(0.08))
                                                .overlay { ProgressView() }
                                        }
                                    } else {
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(Color.primary.opacity(0.08))
                                            .overlay {
                                                Image(systemName: "music.note.list")
                                                    .foregroundStyle(.secondary)
                                            }
                                    }
                                }
                                .frame(width: 124, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(playlist.title)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)

                                    Text("\(playlist.videoCount) videos")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isSaving)
                    }
                    .listStyle(.inset)
                }
            }
            .navigationTitle("Save to Playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 620)
        .task {
            await loadPlaylists()
        }
    }

    private func loadPlaylists() async {
        guard authManager.isSignedIn else {
            playlists = []
            loadErrorMessage = nil
            return
        }

        guard let token = await authManager.getValidToken() else {
            playlists = []
            loadErrorMessage = "Could not get a valid token. Please sign in again."
            return
        }

        isLoading = true
        loadErrorMessage = nil
        defer { isLoading = false }

        do {
            playlists = try await youtubeService.fetchMyPlaylists(accessToken: token)
        } catch {
            playlists = []
            if youtubeService.isQuotaExceededError(error) {
                loadErrorMessage = youtubeService.quotaExceededMessage(for: "Playlists")
            } else if youtubeService.isInsufficientScopeError(error) {
                loadErrorMessage = youtubeService.insufficientScopeMessage(for: "playlist access")
            } else {
                loadErrorMessage = error.localizedDescription
            }
        }
    }

    private func save(video: Video, to playlist: Playlist) async {
        guard let token = await authManager.getValidToken() else {
            loadErrorMessage = "Could not get a valid token. Please sign in again."
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await youtubeService.addVideo(videoId: video.id, toPlaylistID: playlist.id, accessToken: token)
            dismiss()
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                loadErrorMessage = youtubeService.quotaExceededMessage(for: "Save to playlist")
            } else if youtubeService.isInsufficientScopeError(error) {
                loadErrorMessage = youtubeService.insufficientScopeMessage(for: "playlist saves")
            } else {
                loadErrorMessage = "Could not save to playlist: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Placeholder Views

struct SubscriptionsView: View {
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    @State private var subscriptionVideos: [Video] = []
    @State private var isLoading = false
    @State private var isLoadingMore = false
    @State private var hasReachedEnd = false
    @State private var topUpPass = 0
    @State private var loadErrorMessage: String?

    var body: some View {
        Group {
            if authManager.isSignedIn {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isLoading && subscriptionVideos.isEmpty {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                Text("Loading subscriptions...")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else if let loadErrorMessage, subscriptionVideos.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.secondary)
                                Text(loadErrorMessage)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                Button("Retry") {
                                    Task { await loadSubscriptionFeed() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else if subscriptionVideos.isEmpty {
                            VStack(spacing: 16) {
                                Image(systemName: "play.rectangle.on.rectangle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("No subscription videos yet")
                                    .font(.title3)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            LazyVGrid(
                                columns: standardVideoGridColumns,
                                spacing: 28
                            ) {
                                ForEach(Array(subscriptionVideos.enumerated()), id: \.element.id) { index, video in
                                    VideoCardView(video: video) {
                                        appNavigationModel.open(video: video)
                                    }
                                    .onAppear {
                                        triggerSubscriptionLoadMoreIfNeeded(index: index)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                            if isLoadingMore {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .padding(.bottom, 24)
                                    Spacer()
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("subscriptions-load-more-\(subscriptionVideos.count)-\(topUpPass)")
                                .onAppear {
                                    Task {
                                        await loadMoreSubscriptions()
                                    }
                                }
                        }
                    }
                }
                .task(id: authManager.isSignedIn) {
                    if authManager.isSignedIn {
                        await loadSubscriptionFeed()
                    } else {
                        subscriptionVideos = []
                        loadErrorMessage = nil
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "play.rectangle.on.rectangle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Subscriptions")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Sign in to see updates from your favorite channels")
                        .foregroundStyle(.secondary)
                    Text("Use the account button in the toolbar to sign in.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("Subscriptions")
    }

    private func loadSubscriptionFeed() async {
        isLoading = true
        loadErrorMessage = nil
        hasReachedEnd = false
        topUpPass = 0
        defer { isLoading = false }

        guard let token = await authManager.getValidToken() else {
            loadErrorMessage = "Could not get a valid Google token. Try signing out and signing in again."
            return
        }

        var mergedVideos: [Video] = []
        var encounteredErrors: [Error] = []

        do {
            let innertubeSubscriptions = try await youtubeService.api.getSubscriptionFeed(accessToken: token)
            mergedVideos.append(contentsOf: innertubeSubscriptions)
        } catch {
            encounteredErrors.append(error)
        }

        if mergedVideos.count < 30 {
            do {
                let recentUploads = try await youtubeService.fetchRecentVideosFromSubscribedChannels(
                    accessToken: token,
                    maxChannels: 30,
                    videosPerChannel: 2,
                    shuffleChannels: true
                )
                mergedVideos.append(contentsOf: recentUploads)
            } catch {
                encounteredErrors.append(error)
            }
        }

        subscriptionVideos = deduplicateByID(mergedVideos)

        if !subscriptionVideos.isEmpty {
            loadErrorMessage = nil
            if subscriptionVideos.count < 24 {
                await loadMoreSubscriptions()
            }
            return
        }

        if encounteredErrors.contains(where: { youtubeService.isQuotaExceededError($0) }) {
            loadErrorMessage = youtubeService.quotaExceededMessage(for: "Subscriptions")
        } else if let firstError = encounteredErrors.first {
            loadErrorMessage = "Couldn't load subscriptions: \(firstError.localizedDescription)"
        } else {
            loadErrorMessage = "No subscription uploads found for this account yet."
        }
    }

    private func loadMoreSubscriptions() async {
        guard authManager.isSignedIn else { return }
        guard !isLoadingMore else { return }
        guard !hasReachedEnd else { return }

        guard let token = await authManager.getValidToken() else {
            hasReachedEnd = true
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        topUpPass += 1
        let previousCount = subscriptionVideos.count
        let maxChannels = min(120, 30 + (topUpPass * 20))
        let videosPerChannel = topUpPass >= 3 ? 3 : 2

        do {
            let additionalVideos = try await youtubeService.fetchRecentVideosFromSubscribedChannels(
                accessToken: token,
                maxChannels: maxChannels,
                videosPerChannel: videosPerChannel,
                shuffleChannels: true
            )
            if !additionalVideos.isEmpty {
                subscriptionVideos = deduplicateByID(subscriptionVideos + additionalVideos)
            }
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                loadErrorMessage = youtubeService.quotaExceededMessage(for: "Subscriptions")
            }
        }

        if subscriptionVideos.count == previousCount {
            hasReachedEnd = true
        } else {
            loadErrorMessage = nil
        }
    }

    private func triggerSubscriptionLoadMoreIfNeeded(index: Int) {
        let thresholdIndex = max(0, subscriptionVideos.count - 8)
        guard index >= thresholdIndex else { return }
        Task {
            await loadMoreSubscriptions()
        }
    }

    private func deduplicateByID(_ videos: [Video]) -> [Video] {
        var seenIDs = Set<String>()
        var unique: [Video] = []

        for video in videos where seenIDs.insert(video.id).inserted {
            unique.append(video)
        }

        return unique.sorted { $0.publishedAt > $1.publishedAt }
    }
}

struct LibraryView: View {
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var authManager: AuthManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Library")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                // Downloads section
                if !downloadManager.downloads.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.down.circle.fill")
                                .foregroundStyle(Color.accentColor)
                            Text("Downloads")
                                .font(.headline)
                            Spacer()
                            Text("\(downloadManager.downloads.filter { $0.isCompleted }.count) videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 20)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(downloadManager.downloads.filter { $0.isCompleted }.prefix(6)) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        CachedAsyncImage(url: URL(string: item.thumbnailURL)) { image in
                                            image.resizable().aspectRatio(16/9, contentMode: .fill).clipped()
                                        } placeholder: {
                                            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.1))
                                        }
                                        .frame(width: 200, height: 112)
                                        .cornerRadius(8)

                                        Text(item.title)
                                            .font(.caption)
                                            .lineLimit(2)
                                            .frame(width: 200, alignment: .leading)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                    }
                }

                if !authManager.isSignedIn {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle")
                            .font(.system(size: 36))
                            .foregroundStyle(.secondary)
                        Text("Sign in for more")
                            .font(.headline)
                        Text("Sign in to access your playlists, watch later, and liked videos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
                }
            }
        }
        .navigationTitle("Library")
    }
}

// MARK: - Search Results View

struct SearchResultsView: View {
    let query: String
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var appNavigationModel: AppNavigationModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if youtubeService.isLoading && youtubeService.searchResults.isEmpty {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Searching...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else if youtubeService.searchResults.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No results for \"\(query)\"")
                            .font(.title3)
                            .fontWeight(.medium)
                        Text("Try different keywords or check your spelling")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Text("Results for \"\(query)\"")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // Search results as a list (YouTube-style)
                    LazyVStack(spacing: 16) {
                        ForEach(Array(youtubeService.searchResults.enumerated()), id: \.element.id) { index, video in
                            SearchResultRow(video: video) {
                                appNavigationModel.open(video: video)
                            }
                            .onAppear {
                                triggerSearchLoadMoreIfNeeded(index: index)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                    if youtubeService.isLoadingMoreSearch {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.bottom, 24)
                            Spacer()
                        }
                    }

                    Color.clear
                        .frame(height: 1)
                        .id("search-load-more-\(youtubeService.searchResults.count)")
                        .onAppear {
                            guard !youtubeService.searchResults.isEmpty else { return }
                            Task {
                                await youtubeService.loadMoreSearchResults(query: query)
                            }
                        }
                }
            }
        }
        .navigationTitle("Search")
    }

    private func triggerSearchLoadMoreIfNeeded(index: Int) {
        let thresholdIndex = max(0, youtubeService.searchResults.count - 8)
        guard index >= thresholdIndex else { return }
        Task {
            await youtubeService.loadMoreSearchResults(query: query)
        }
    }
}

// MARK: - Search Result Row (horizontal layout like YouTube search)

struct SearchResultRow: View {
    let video: Video
    let onTap: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 16) {
                // Thumbnail
                ZStack(alignment: .bottomTrailing) {
                    CachedAsyncImage(url: URL(string: video.thumbnailURL)) { image in
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .clipped()
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.1))
                            .aspectRatio(16/9, contentMode: .fit)
                            .overlay { ProgressView() }
                    }
                    .frame(width: 360, height: 202)
                    .cornerRadius(12)

                    if !video.isLive {
                        Text(video.formattedDuration)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background { Capsule().fill(.black.opacity(0.8)) }
                            .padding(8)
                    }
                }

                // Metadata
                VStack(alignment: .leading, spacing: 8) {
                    Text(video.title)
                        .font(.title3)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    HStack(spacing: 4) {
                        Text(video.formattedViews)
                        Text("•")
                        Text(video.relativeTime)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color.primary.opacity(0.15))
                            .frame(width: 24, height: 24)
                            .overlay {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                        Text(video.channelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Text(video.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(8)
        .background {
            if isHovered {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(0.05))
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Video Loading Watch View (fetches real stream URL)

struct VideoLoadingWatchView: View {
    let video: Video
    let onSelectVideo: ((Video) -> Void)?
    @EnvironmentObject private var youtubeService: YouTubeService
    @State private var resolvedVideo: Video
    @State private var streamURL: URL?
    @State private var qualityOptions: [StreamQualityOption] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    init(video: Video, onSelectVideo: ((Video) -> Void)? = nil) {
        self.video = video
        self.onSelectVideo = onSelectVideo
        _resolvedVideo = State(initialValue: video)
    }

    var body: some View {
        content
            .task(id: video.id) {
                await resetAndLoadStream()
            }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Loading video...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessageText = errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text(errorMessageText)
                    .foregroundStyle(.secondary)
                Button("Retry") {
                    Task {
                        await resetAndLoadStream()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let streamURL {
            WatchView(
                videoURL: streamURL,
                videoId: resolvedVideo.id,
                videoTitle: resolvedVideo.title,
                videoDescription: resolvedVideo.description,
                channelId: resolvedVideo.channelId,
                channelName: resolvedVideo.channelName,
                channelAvatar: resolvedVideo.channelAvatar ?? "",
                thumbnailURL: resolvedVideo.thumbnailURL,
                subscribers: "",
                views: resolvedVideo.formattedViews,
                uploadDate: resolvedVideo.relativeTime,
                initialLikeCount: resolvedVideo.likeCount,
                qualityOptions: qualityOptions,
                onSelectVideo: onSelectVideo
            )
        } else {
            VStack(spacing: 16) {
                Image(systemName: "video.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Couldn't resolve a playable stream for this video.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadStream() async {
        guard !video.id.hasPrefix("mock_"), !video.id.hasPrefix("sample_") else {
            streamURL = nil
            errorMessage = "This placeholder item does not have a real YouTube stream URL."
            isLoading = false
            return
        }

        do {
            async let streamTask = youtubeService.getStreamManifest(videoId: video.id)
            async let detailsTask = youtubeService.getVideo(id: video.id)

            let manifest = try await streamTask
            guard !Task.isCancelled else { return }
            streamURL = manifest.defaultURL
            qualityOptions = manifest.qualityOptions

            if let detail = try? await detailsTask {
                guard !Task.isCancelled else { return }
                resolvedVideo = mergeVideo(base: video, detail: detail)
            } else {
                resolvedVideo = video
            }
        } catch {
            guard !Task.isCancelled else { return }
            streamURL = nil
            qualityOptions = []
            errorMessage = "Couldn't load stream: \(error.localizedDescription)"
        }
        isLoading = false
    }

    private func resetAndLoadStream() async {
        resolvedVideo = video
        streamURL = nil
        qualityOptions = []
        errorMessage = nil
        isLoading = true
        await loadStream()
    }

    private func mergeVideo(base: Video, detail: Video) -> Video {
        Video(
            id: base.id,
            title: detail.title.isEmpty ? base.title : detail.title,
            description: detail.description.isEmpty ? base.description : detail.description,
            channelId: detail.channelId.isEmpty ? base.channelId : detail.channelId,
            channelName: detail.channelName.isEmpty ? base.channelName : detail.channelName,
            channelAvatar: detail.channelAvatar ?? base.channelAvatar,
            thumbnailURL: detail.thumbnailURL.isEmpty ? base.thumbnailURL : detail.thumbnailURL,
            duration: detail.duration > 0 ? detail.duration : base.duration,
            viewCount: detail.viewCount > 0 ? detail.viewCount : base.viewCount,
            likeCount: detail.likeCount ?? base.likeCount,
            publishedAt: detail.publishedAt,
            isLive: detail.isLive,
            isUpcoming: detail.isUpcoming
        )
    }
}

#Preview {
    MainContentView(destination: .home, searchText: .constant(""), isShowingSearch: .constant(false))
    .environmentObject(AppNavigationModel())
        .environmentObject(YouTubeService())
        .environmentObject(DownloadManager())
    .environmentObject(AuthManager())
}
