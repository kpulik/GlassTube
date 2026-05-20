//
//  WatchView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AppKit

struct WatchView: View {
    let videoURL: URL
    let videoId: String
    let videoTitle: String
    let videoDescription: String
    let channelId: String
    let channelName: String
    let channelAvatar: String
    let thumbnailURL: String
    let subscribers: String
    let views: String
    let uploadDate: String
    let initialLikeCount: Int?
    let qualityOptions: [StreamQualityOption]
    let onSelectVideo: ((Video) -> Void)?

    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var authManager: AuthManager
    @EnvironmentObject private var downloadManager: DownloadManager
    @EnvironmentObject private var extensionsManager: ExtensionsManager
    @State private var displayedLikeCount = 0
    @State private var isLiked = false
    @State private var isDisliked = false
    @State private var isSubscribed = false
    @State private var isSubscribing = false
    @State private var subscriptionResourceId: String?
    @State private var showingDescription = false
    @State private var relatedVideos: [Video] = []
    @State private var isLoadingRelatedVideos = false
    @State private var comments: [Comment] = []
    @State private var isLoadingComments = false
    @State private var commentsErrorMessage: String?
    @State private var draftCommentText = ""
    @State private var isPostingComment = false
    @State private var chapters: [Chapter] = []
    @State private var showingActionAlert = false
    @State private var actionMessage = ""
    @State private var showingChannelSheet = false
    @State private var resolvedChannel: Channel?
    @State private var showingDownloadPicker = false
    @State private var availableFormats: [DownloadFormatOption] = []
    @State private var isLoadingFormats = false
    @State private var showingSavePicker = false
    @State private var userPlaylists: [Playlist] = []
    @State private var isLoadingUserPlaylists = false
    @State private var savePickerErrorMessage: String?
    @State private var isSavingToPlaylist = false

    init(
        videoURL: URL,
        videoId: String,
        videoTitle: String,
        videoDescription: String,
        channelId: String,
        channelName: String,
        channelAvatar: String,
        thumbnailURL: String,
        subscribers: String,
        views: String,
        uploadDate: String,
        initialLikeCount: Int? = nil,
        qualityOptions: [StreamQualityOption] = [],
        onSelectVideo: ((Video) -> Void)? = nil
    ) {
        self.videoURL = videoURL
        self.videoId = videoId
        self.videoTitle = videoTitle
        self.videoDescription = videoDescription
        self.channelId = channelId
        self.channelName = channelName
        self.channelAvatar = channelAvatar
        self.thumbnailURL = thumbnailURL
        self.subscribers = subscribers
        self.views = views
        self.uploadDate = uploadDate
        self.initialLikeCount = initialLikeCount
        self.qualityOptions = qualityOptions
        self.onSelectVideo = onSelectVideo
    }
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                // Main content area
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Video player
                        VideoPlayerView(
                            videoURL: videoURL,
                            videoTitle: extensionsManager.deArrowTitle ?? videoTitle,
                            channelName: resolvedChannelName,
                            thumbnailURL: thumbnailURL,
                            sponsorSegments: extensionsManager.sponsorSegments,
                            chapters: chapters,
                            availableQualities: qualityOptions
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: appNavigationModel.isVideoFullscreen ? geometry.size.height : nil)
                        
                        if !appNavigationModel.isVideoFullscreen {
                            // Video metadata
                            VStack(alignment: .leading, spacing: 12) {
                                // Title (DeArrow replaces clickbait if available)
                                Text(extensionsManager.deArrowTitle ?? videoTitle)
                                    .font(.title2)
                                    .fontWeight(.semibold)

                                // Show original title button if DeArrow replaced it
                                if extensionsManager.deArrowTitle != nil {
                                    Button("Show original title") {
                                        extensionsManager.deArrowTitle = nil
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }

                                // Channel info and engagement
                                HStack(spacing: 12) {
                                    // Channel info
                                    Button {
                                        showingChannelSheet = true
                                    } label: {
                                        HStack(spacing: 12) {
                                            if let avatar = resolvedChannelAvatarURL,
                                               let url = URL(string: avatar),
                                               !avatar.isEmpty {
                                                CachedAsyncImage(url: url) { image in
                                                    image
                                                        .resizable()
                                                        .aspectRatio(contentMode: .fill)
                                                        .clipShape(Circle())
                                                } placeholder: {
                                                    Circle()
                                                        .fill(Color.primary.opacity(0.15))
                                                        .overlay {
                                                            ProgressView()
                                                                .scaleEffect(0.6)
                                                        }
                                                }
                                                .frame(width: 40, height: 40)
                                            } else {
                                                Circle()
                                                    .fill(Color.primary.opacity(0.15))
                                                    .frame(width: 40, height: 40)
                                                    .overlay {
                                                        Image(systemName: "person.fill")
                                                            .foregroundStyle(.secondary)
                                                    }
                                            }

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(resolvedChannelName)
                                                    .font(.body)
                                                    .fontWeight(.medium)

                                                Text(resolvedSubscriberText)
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    GlassButton(
                                        title: subscribeButtonTitle,
                                        icon: isSubscribed ? "checkmark" : "plus",
                                        isPrimary: !isSubscribed
                                    ) {
                                        Task { await toggleSubscription() }
                                    }

                                    Spacer()
                                }

                                // Engagement buttons row
                                HStack(spacing: 8) {
                                    // Like/Dislike
                                    GlassButton(
                                        title: likeButtonTitle,
                                        icon: isLiked ? "hand.thumbsup.fill" : "hand.thumbsup",
                                        isPrimary: false
                                    ) {
                                        Task { await toggleLike() }
                                    }

                                    GlassButton(
                                        title: extensionsManager.dislikeCount.map { formatCount($0) },
                                        icon: isDisliked ? "hand.thumbsdown.fill" : "hand.thumbsdown",
                                        isPrimary: false
                                    ) {
                                        Task { await toggleDislike() }
                                    }

                                    Divider()
                                        .frame(height: 24)

                                    // Share
                                    GlassButton(title: "Share", icon: "square.and.arrow.up", isPrimary: false) {
                                        copyVideoURLToPasteboard()
                                        showAction("Video link copied.")
                                    }

                                    // Download via yt-dlp
                                    GlassButton(
                                        title: downloadButtonTitle,
                                        icon: downloadButtonIcon,
                                        isPrimary: false
                                    ) {
                                        guard !videoId.hasPrefix("mock_") else { return }
                                        if let activeItem = downloadManager.downloads.first(where: { $0.videoId == videoId }),
                                           case .downloading = activeItem.status {
                                            downloadManager.cancelDownload(videoId: videoId)
                                            showAction("Stopped download.")
                                        } else {
                                            showingDownloadPicker = true
                                            isLoadingFormats = true
                                            Task {
                                                let formats = await downloadManager.fetchAvailableQualities(videoId: videoId)
                                                availableFormats = formats
                                                isLoadingFormats = false
                                            }
                                        }
                                    }

                                    // Save
                                    GlassButton(title: "Save", icon: "plus", isPrimary: false) {
                                        openSavePicker()
                                    }

                                    GlassButton(title: "YouTube", icon: "safari", isPrimary: false) {
                                        openVideoInBrowser()
                                    }
                                }

                                // Description box
                                DescriptionBox(
                                    views: views,
                                    uploadDate: uploadDate,
                                    description: resolvedDescription,
                                    isExpanded: $showingDescription
                                )

                                // SponsorBlock segments
                                if !extensionsManager.sponsorSegments.isEmpty {
                                    SponsorBlockInfo(segments: extensionsManager.sponsorSegments)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                            CommentsSection(
                                comments: comments,
                                isLoading: isLoadingComments,
                                errorMessage: commentsErrorMessage,
                                videoId: videoId,
                                isSignedIn: authManager.isSignedIn,
                                draftText: $draftCommentText,
                                isPostingComment: isPostingComment,
                                onSubmitComment: {
                                    Task { await submitComment() }
                                }
                            )
                            .padding(.horizontal, 20)
                        }
                    }
                }
                .scrollDisabled(appNavigationModel.isVideoFullscreen)
                
                // Suggested videos sidebar
                if !appNavigationModel.isVideoFullscreen && !appNavigationModel.isTheaterMode {
                    SuggestedVideosSidebar(
                        videos: relatedVideos,
                        isLoading: isLoadingRelatedVideos,
                        onSelectVideo: { video in
                            selectVideo(video)
                        }
                    )
                    .frame(width: min(402, geometry.size.width * 0.35))
                }
            }
            .background(appNavigationModel.isVideoFullscreen ? Color.black : Color.clear)
        }
        .navigationTitle("")
        .task(id: videoId) {
            guard !videoId.hasPrefix("mock_"), !videoId.hasPrefix("sample_") else {
                relatedVideos = []
                comments = []
                return
            }

            displayedLikeCount = initialLikeCount ?? 0
            isLiked = false
            isDisliked = false

            extensionsManager.loadExtensions(for: videoId)
            async let relatedTask: () = loadRelatedVideos()
            async let chaptersTask: () = loadChapters()
            async let commentsTask: () = loadComments()
            async let channelTask: () = loadChannelMetadata()
            async let subscriptionTask: () = loadSubscriptionState()
            _ = await (relatedTask, chaptersTask, commentsTask, channelTask, subscriptionTask)
        }
        .onChange(of: extensionsManager.likeCount) { _, newValue in
            guard let newValue else { return }
            displayedLikeCount = newValue
        }
        .onDisappear {
            appNavigationModel.isVideoFullscreen = false
            appNavigationModel.isTheaterMode = false
            extensionsManager.stopRefreshing()
        }
        .alert("Action", isPresented: $showingActionAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionMessage)
        }
        .sheet(isPresented: $showingChannelSheet) {
            ChannelView(
                channelId: channelId,
                initialChannelName: resolvedChannelName,
                initialChannelAvatarURL: resolvedChannelAvatarURL
            ) { selectedVideo in
                selectVideo(selectedVideo)
            }
            .environmentObject(youtubeService)
            .environmentObject(authManager)
            .environmentObject(downloadManager)
        }
        .sheet(isPresented: $showingSavePicker) {
            WatchPlaylistPickerSheet(
                videoTitle: videoTitle,
                playlists: userPlaylists,
                isLoading: isLoadingUserPlaylists,
                isSaving: isSavingToPlaylist,
                errorMessage: savePickerErrorMessage,
                onSaveToExisting: { playlist in
                    Task { await saveVideo(toPlaylistID: playlist.id, playlistTitle: playlist.title) }
                },
                onSaveToWatchLater: {
                    Task { await saveVideo(toPlaylistID: "WL", playlistTitle: "Watch Later") }
                },
                onCreateAndSave: { name, privacy in
                    Task { await createPlaylistAndSave(name: name, privacy: privacy) }
                }
            )
        }
        .sheet(isPresented: $showingDownloadPicker) {
            DownloadPickerSheet(
                videoId: videoId,
                videoTitle: videoTitle,
                channelName: channelName,
                thumbnailURL: thumbnailURL,
                isLoading: isLoadingFormats,
                formats: availableFormats,
                onDownloadWithFormat: { format in
                    downloadManager.downloadWithFormat(
                        videoId: videoId,
                        title: videoTitle,
                        channelName: channelName,
                        thumbnailURL: thumbnailURL,
                        formatOption: format
                    )
                    showingDownloadPicker = false
                }
            )
        }
    }
    
    private var downloadButtonTitle: String {
        guard let item = downloadManager.downloads.first(where: { $0.videoId == videoId }) else {
            return "Download"
        }
        switch item.status {
        case .downloading(let progress): return "\(Int(progress * 100))%"
        case .completed: return "Downloaded"
        case .failed: return "Retry"
        case .missingFile: return "Missing File"
        }
    }

    private var downloadButtonIcon: String {
        guard let item = downloadManager.downloads.first(where: { $0.videoId == videoId }) else {
            return "arrow.down.circle"
        }
        switch item.status {
        case .downloading: return "xmark.circle"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.circle"
        case .missingFile: return "questionmark.folder"
        }
    }

    private var likeButtonTitle: String? {
        guard displayedLikeCount > 0 else { return nil }
        return formatCount(displayedLikeCount)
    }

    private var resolvedDescription: String {
        let trimmed = videoDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return "No description available for this video."
    }

    private var resolvedChannelName: String {
        let name = resolvedChannel?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return name
        }
        return channelName
    }

    private var resolvedSubscriberText: String {
        if let resolvedChannel,
           let subscriberCount = resolvedChannel.subscriberCount,
           subscriberCount > 0 {
            return "\(resolvedChannel.formattedSubscribers) subscribers"
        }

        let trimmedSubscribers = subscribers.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSubscribers.isEmpty {
            return "Subscribers unavailable"
        }

        if trimmedSubscribers.lowercased().contains("subscriber") {
            return trimmedSubscribers
        }

        return "\(trimmedSubscribers) subscribers"
    }

    private var resolvedChannelAvatarURL: String? {
        if let resolved = resolvedChannel?.avatarURL,
           !resolved.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return resolved
        }

        let trimmed = channelAvatar.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func copyVideoURLToPasteboard() {
        let watchURL = "https://www.youtube.com/watch?v=\(videoId)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(watchURL, forType: .string)
    }

    private func openVideoInBrowser() {
        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else { return }
        NSWorkspace.shared.open(url)
    }

    private func openChannelInBrowser() {
        if !channelId.isEmpty,
           let url = URL(string: "https://www.youtube.com/channel/\(channelId)?sub_confirmation=1") {
            NSWorkspace.shared.open(url)
            return
        }

        let encodedName = channelName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? channelName
        guard let fallback = URL(string: "https://www.youtube.com/results?search_query=\(encodedName)") else { return }
        NSWorkspace.shared.open(fallback)
    }

    private var subscribeButtonTitle: String {
        if isSubscribing { return isSubscribed ? "Unsubscribing..." : "Subscribing..." }
        return isSubscribed ? "Subscribed" : "Subscribe"
    }

    private func loadSubscriptionState() async {
        guard !channelId.isEmpty, authManager.isSignedIn,
              let token = await authManager.getValidToken() else {
            subscriptionResourceId = nil
            isSubscribed = false
            return
        }

        do {
            let resolvedId = try await youtubeService.checkSubscription(channelId: channelId, accessToken: token)
            subscriptionResourceId = resolvedId
            isSubscribed = resolvedId != nil
        } catch {
            // Non-fatal: keep the button usable even if the state check fails
            // (e.g. quota exceeded). Tapping will still surface a clear error.
            subscriptionResourceId = nil
            isSubscribed = false
        }
    }

    private func toggleSubscription() async {
        guard !channelId.isEmpty else {
            openChannelInBrowser()
            showAction("Opened channel in browser.")
            return
        }

        guard authManager.isSignedIn else {
            showAction("Sign in first to subscribe.")
            return
        }

        guard let token = await authManager.getValidToken() else {
            showAction("Could not get a valid token. Please sign in again.")
            return
        }

        guard !isSubscribing else { return }
        isSubscribing = true
        defer { isSubscribing = false }

        if isSubscribed, let resourceId = subscriptionResourceId {
            do {
                try await youtubeService.unsubscribeFromChannel(subscriptionId: resourceId, accessToken: token)
                subscriptionResourceId = nil
                isSubscribed = false
                showAction("Unsubscribed from \(channelName).")
            } catch {
                if youtubeService.isQuotaExceededError(error) {
                    showAction(youtubeService.quotaExceededMessage(for: "Channel subscriptions"))
                } else if youtubeService.isInsufficientScopeError(error) {
                    showAction(youtubeService.insufficientScopeMessage(for: "channel subscriptions"))
                } else {
                    showAction("Could not unsubscribe: \(error.localizedDescription)")
                }
            }
            return
        }

        do {
            let newResourceId = try await youtubeService.subscribeToChannel(channelId: channelId, accessToken: token)
            subscriptionResourceId = newResourceId.isEmpty ? nil : newResourceId
            isSubscribed = true
            showAction("Subscribed to \(channelName).")
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                showAction(youtubeService.quotaExceededMessage(for: "Channel subscriptions"))
            } else if youtubeService.isInsufficientScopeError(error) {
                showAction(youtubeService.insufficientScopeMessage(for: "channel subscriptions"))
            } else {
                showAction("Could not subscribe: \(error.localizedDescription)")
            }
        }
    }

    private func openSavePicker() {
        guard authManager.isSignedIn else {
            showAction("Sign in first to save to a playlist.")
            return
        }
        savePickerErrorMessage = nil
        showingSavePicker = true
        Task { await loadUserPlaylists() }
    }

    private func loadUserPlaylists() async {
        guard let token = await authManager.getValidToken() else {
            savePickerErrorMessage = "Could not get a valid token. Please sign in again."
            return
        }
        isLoadingUserPlaylists = true
        defer { isLoadingUserPlaylists = false }
        do {
            let playlists = try await youtubeService.fetchMyPlaylists(accessToken: token)
            userPlaylists = playlists
        } catch {
            userPlaylists = []
            savePickerErrorMessage = "Could not load your playlists: \(error.localizedDescription)"
        }
    }

    private func saveVideo(toPlaylistID playlistID: String, playlistTitle: String) async {
        guard let token = await authManager.getValidToken() else {
            savePickerErrorMessage = "Could not get a valid token. Please sign in again."
            return
        }
        isSavingToPlaylist = true
        savePickerErrorMessage = nil
        defer { isSavingToPlaylist = false }

        do {
            try await youtubeService.addVideo(videoId: videoId, toPlaylistID: playlistID, accessToken: token)
            showingSavePicker = false
            showAction("Added to \(playlistTitle).")
        } catch {
            // Watch Later is the one place we still open YouTube as a last resort —
            // the Data API literally doesn't allow writes there, so Innertube is
            // the only path and worth surfacing a browser fallback for.
            if playlistID == "WL" {
                openVideoOnYouTubeForManualSave()
                showingSavePicker = false
                showAction("Couldn't add to Watch Later in-app (\(error.localizedDescription)). Opened on YouTube so you can save it there.")
            } else {
                savePickerErrorMessage = "Couldn't add to \(playlistTitle): \(error.localizedDescription)"
            }
        }
    }

    private func createPlaylistAndSave(name: String, privacy: String) async {
        guard let token = await authManager.getValidToken() else {
            savePickerErrorMessage = "Could not get a valid token. Please sign in again."
            return
        }
        isSavingToPlaylist = true
        savePickerErrorMessage = nil
        defer { isSavingToPlaylist = false }

        do {
            let playlist = try await youtubeService.createPlaylist(
                title: name,
                privacyStatus: privacy,
                accessToken: token
            )
            try await youtubeService.addVideo(
                videoId: videoId,
                toPlaylistID: playlist.id,
                accessToken: token
            )
            userPlaylists.insert(playlist, at: 0)
            showingSavePicker = false
            showAction("Created \"\(playlist.title)\" and saved video.")
        } catch {
            savePickerErrorMessage = "Couldn't create playlist: \(error.localizedDescription)"
        }
    }

    private func openVideoOnYouTubeForManualSave() {
        if let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func showAction(_ message: String) {
        actionMessage = message
        showingActionAlert = true
    }

    private func selectVideo(_ video: Video) {
        if let onSelectVideo {
            onSelectVideo(video)
        } else {
            guard let url = URL(string: "https://www.youtube.com/watch?v=\(video.id)") else { return }
            NSWorkspace.shared.open(url)
        }
    }

    private func toggleLike() async {
        if !authManager.isSignedIn {
            withAnimation {
                if isLiked {
                    isLiked = false
                    displayedLikeCount = max(0, displayedLikeCount - 1)
                } else {
                    isLiked = true
                    if isDisliked {
                        isDisliked = false
                    }
                    displayedLikeCount += 1
                }
            }
            return
        }

        guard let token = await authManager.getValidToken() else {
            showAction("Could not get a valid token. Please sign in again.")
            return
        }

        let targetRating = isLiked ? "none" : "like"
        do {
            try await youtubeService.rateVideo(videoId: videoId, rating: targetRating, accessToken: token)
            withAnimation {
                if isLiked {
                    isLiked = false
                    displayedLikeCount = max(0, displayedLikeCount - 1)
                } else {
                    isLiked = true
                    if isDisliked {
                        isDisliked = false
                    }
                    displayedLikeCount += 1
                }
            }
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                showAction(youtubeService.quotaExceededMessage(for: "Likes"))
            } else if youtubeService.isInsufficientScopeError(error) {
                showAction(youtubeService.insufficientScopeMessage(for: "likes/dislikes"))
            } else {
                showAction("Could not update like: \(error.localizedDescription)")
            }
        }
    }

    private func toggleDislike() async {
        if !authManager.isSignedIn {
            withAnimation {
                if isDisliked {
                    isDisliked = false
                } else {
                    isDisliked = true
                    if isLiked {
                        isLiked = false
                        displayedLikeCount = max(0, displayedLikeCount - 1)
                    }
                }
            }
            return
        }

        guard let token = await authManager.getValidToken() else {
            showAction("Could not get a valid token. Please sign in again.")
            return
        }

        let targetRating = isDisliked ? "none" : "dislike"
        do {
            try await youtubeService.rateVideo(videoId: videoId, rating: targetRating, accessToken: token)
            withAnimation {
                if isDisliked {
                    isDisliked = false
                } else {
                    isDisliked = true
                    if isLiked {
                        isLiked = false
                        displayedLikeCount = max(0, displayedLikeCount - 1)
                    }
                }
            }
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                showAction(youtubeService.quotaExceededMessage(for: "Dislikes"))
            } else if youtubeService.isInsufficientScopeError(error) {
                showAction(youtubeService.insufficientScopeMessage(for: "likes/dislikes"))
            } else {
                showAction("Could not update dislike: \(error.localizedDescription)")
            }
        }
    }

    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }

    private func loadChapters() async {
        do {
            chapters = try await youtubeService.api.getChapters(videoId: videoId)
        } catch {
            chapters = []
        }
    }

    private func loadComments() async {
        isLoadingComments = true
        commentsErrorMessage = nil
        defer { isLoadingComments = false }

        // Comments via Innertube `next`/continuation are public — no auth
        // required. Always try the anonymous path first so users see comments
        // whether they're signed in or not.
        do {
            let anonymous = try await youtubeService.fetchComments(videoId: videoId, accessToken: nil)
            if !anonymous.isEmpty || !authManager.isSignedIn {
                comments = anonymous
                return
            }
        } catch {
            // Fall through to the signed-in attempt below; if that also fails
            // we'll surface this anonymous-path error.
            if !authManager.isSignedIn {
                comments = []
                if youtubeService.isQuotaExceededError(error) {
                    commentsErrorMessage = youtubeService.quotaExceededMessage(for: "Comments")
                } else {
                    commentsErrorMessage = "Couldn't load comments: \(error.localizedDescription)"
                }
                return
            }
        }

        // Signed-in retry: a few videos limit anonymous access. Try with a
        // bearer token if we have one.
        guard let token = await authManager.getValidToken() else {
            comments = []
            return
        }

        do {
            comments = try await youtubeService.fetchComments(videoId: videoId, accessToken: token)
        } catch {
            comments = []
            if youtubeService.isQuotaExceededError(error) {
                commentsErrorMessage = youtubeService.quotaExceededMessage(for: "Comments")
            } else if youtubeService.isInsufficientScopeError(error) {
                commentsErrorMessage = youtubeService.insufficientScopeMessage(for: "comments")
            } else {
                commentsErrorMessage = error.localizedDescription
            }
        }
    }

    private func submitComment() async {
        guard authManager.isSignedIn else {
            showAction("Sign in first to post comments.")
            return
        }

        let trimmed = draftCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showAction("Enter a comment before posting.")
            return
        }

        guard let token = await authManager.getValidToken() else {
            showAction("Could not get a valid token. Please sign in again.")
            return
        }

        guard !isPostingComment else { return }
        isPostingComment = true
        defer { isPostingComment = false }

        do {
            try await youtubeService.postComment(videoId: videoId, text: trimmed, accessToken: token)
            draftCommentText = ""
            await loadComments()
            showAction("Comment posted.")
        } catch {
            if youtubeService.isQuotaExceededError(error) {
                showAction(youtubeService.quotaExceededMessage(for: "Comments"))
            } else if youtubeService.isInsufficientScopeError(error) {
                showAction(youtubeService.insufficientScopeMessage(for: "comment posting"))
            } else {
                showAction("Could not post comment: \(error.localizedDescription)")
            }
        }
    }

    private func loadRelatedVideos() async {
        isLoadingRelatedVideos = true
        defer { isLoadingRelatedVideos = false }

        var merged: [Video] = []

        if let directRelated = try? await youtubeService.api.getRelatedVideos(videoId: videoId), !directRelated.isEmpty {
            merged.append(contentsOf: directRelated)
        }

        if merged.count < 20,
           authManager.isSignedIn,
           let token = await authManager.getValidToken(),
           let subscriptionFeed = try? await youtubeService.api.getSubscriptionFeed(accessToken: token),
           !subscriptionFeed.isEmpty {
            merged.append(contentsOf: subscriptionFeed)
        }

        if merged.count < 20 {
            var homeFeedCandidates = youtubeService.homeVideos

            if homeFeedCandidates.isEmpty {
                if authManager.isSignedIn,
                   let token = await authManager.getValidToken() {
                    await youtubeService.loadHomeFeed(accessToken: token)
                } else {
                    await youtubeService.loadHomeFeed()
                }
                homeFeedCandidates = youtubeService.homeVideos
            }

            if !homeFeedCandidates.isEmpty {
                merged.append(contentsOf: homeFeedCandidates)
            }
        }

        let deduplicated = deduplicateVideos(merged)
        relatedVideos = Array(deduplicated.filter { $0.id != videoId }.prefix(36))
    }

    private func loadChannelMetadata() async {
        guard !channelId.isEmpty else { return }

        // Don't pass auth token — Innertube browse doesn't need it for public channels
        // and sending one can trigger Data API quota limits / HTTP 400 errors.
        if let fetchedChannel = try? await youtubeService.fetchChannel(channelId: channelId) {
            resolvedChannel = fetchedChannel
        }
    }

    private func deduplicateVideos(_ videos: [Video]) -> [Video] {
        var seen = Set<String>()
        var unique: [Video] = []
        for video in videos where seen.insert(video.id).inserted {
            unique.append(video)
        }
        return unique
    }
}

// MARK: - Glass Button

struct GlassButton: View {
    let title: String?
    let icon: String?
    let isPrimary: Bool
    let action: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                }
                if let title {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                }
            }
            .foregroundStyle(isPrimary ? .white : .primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .background {
            GlassEffectContainer(spacing: 10) {
                Capsule()
                    .fill(isPrimary ? Color.red : Color.primary.opacity(0.08))
                    .glassEffect(
                        .regular.interactive(isHovered),
                        in: .capsule
                    )
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Description Box

struct DescriptionBox: View {
    let views: String
    let uploadDate: String
    let description: String
    @Binding var isExpanded: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(views)
                    .fontWeight(.medium)
                Text("•")
                Text(uploadDate)
            }
            .font(.body)
            
            Text(description)
                .font(.body)
                .lineLimit(isExpanded ? nil : 2)
            
            Button(isExpanded ? "Show less" : "...more") {
                withAnimation {
                    isExpanded.toggle()
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.05))
        }
    }
}

// MARK: - Comments Section

struct CommentsSection: View {
    let comments: [Comment]
    let isLoading: Bool
    let errorMessage: String?
    let videoId: String
    let isSignedIn: Bool
    @Binding var draftText: String
    let isPostingComment: Bool
    let onSubmitComment: () -> Void


    // Disable comment posting: always view-only
    private var canShowComposer: Bool { false }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.title3)
                .fontWeight(.semibold)

            // Comment composer is disabled (view-only)
            // No sign-in prompt either

            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading comments...")
                        .foregroundStyle(.secondary)
                }
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Button("Open Comments on YouTube") {
                        guard let url = URL(string: "https://www.youtube.com/watch?v=\(videoId)") else { return }
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }
            } else if comments.isEmpty {
                Text("No comments available for this video.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(comments.prefix(25)) { comment in
                        CommentRow(comment: comment)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.04))
        }
    }
}

struct CommentRow: View {
    let comment: Comment

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 34, height: 34)
                .overlay {
                    Text(String(comment.authorName.prefix(1)).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorName)
                        .font(.caption.weight(.semibold))
                    Text(comment.relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(comment.text)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    Label("\(comment.likeCount)", systemImage: "hand.thumbsup")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if comment.replyCount > 0 {
                        Text("\(comment.replyCount) repl\(comment.replyCount == 1 ? "y" : "ies")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Suggested Videos Sidebar

struct SuggestedVideosSidebar: View {
    let videos: [Video]
    let isLoading: Bool
    let onSelectVideo: (Video) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Related videos")
                    .font(.body)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading related videos...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
                } else if videos.isEmpty {
                    Text("No related videos available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 20)
                } else {
                    ForEach(videos) { video in
                        SuggestedVideoRow(video: video) {
                            onSelectVideo(video)
                        }
                    }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
    }
}

struct SuggestedVideoRow: View {
    let video: Video
    let onTap: () -> Void
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: onTap) {
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
                .frame(width: 160, height: 90)
                .cornerRadius(8)
                
                // Duration
                if !video.isLive && video.duration > 0 {
                    Text(video.formattedDuration)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background {
                            Capsule()
                                .fill(.black.opacity(0.8))
                        }
                        .padding(4)
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
        }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - SponsorBlock Segment Info

struct SponsorBlockInfo: View {
    let segments: [SponsorSegment]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "shield.checkered")
                    .foregroundStyle(.green)
                Text("SponsorBlock")
                    .fontWeight(.medium)
                Text("\(segments.count) segment\(segments.count == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            FlowLayout(spacing: 6) {
                ForEach(segments) { segment in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(segment.categoryColor)
                            .frame(width: 8, height: 8)
                        Text(segment.categoryLabel)
                    }
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background {
                        Capsule().fill(Color.primary.opacity(0.06))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        }
    }
}

/// Simple flow layout for tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}

// MARK: - Download Picker Sheet

struct DownloadPickerSheet: View {
    let videoId: String
    let videoTitle: String
    let channelName: String
    let thumbnailURL: String
    let isLoading: Bool
    let formats: [DownloadFormatOption]
    let onDownloadWithFormat: (DownloadFormatOption) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Download Video")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Text(videoTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Fetching available qualities...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else if !formats.isEmpty {
                Text("Available Qualities")
                    .font(.subheadline.weight(.semibold))

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(formats) { format in
                            Button {
                                onDownloadWithFormat(format)
                            } label: {
                                HStack {
                                    Text(format.label)
                                        .font(.body.weight(.medium))
                                    Spacer()
                                    if let fileSize = format.fileSize {
                                        Text(fileSize)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    if !format.hasAudio {
                                        Text("+ audio")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.orange.opacity(0.15))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                    Image(systemName: "arrow.down.circle")
                                        .foregroundStyle(Color.accentColor)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(.secondary.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 240)
            }

            if !isLoading && formats.isEmpty {
                Text("No formats found. Make sure yt-dlp is installed (brew install yt-dlp).")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - Playlist Picker Sheet

struct WatchPlaylistPickerSheet: View {
    let videoTitle: String
    let playlists: [Playlist]
    let isLoading: Bool
    let isSaving: Bool
    let errorMessage: String?
    let onSaveToExisting: (Playlist) -> Void
    let onSaveToWatchLater: () -> Void
    let onCreateAndSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isCreatingNew = false
    @State private var newPlaylistName = ""
    @State private var newPlaylistPrivacy = "private"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Save Video")
                    .font(.headline)
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }

            Text(videoTitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            if isCreatingNew {
                newPlaylistForm
            } else {
                existingPlaylistList
            }

            if let errorMessage, !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 460)
        .disabled(isSaving)
    }

    private var existingPlaylistList: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Watch Later always first.
            pickerRow(
                title: "Watch Later",
                subtitle: "Save for later on YouTube",
                icon: "clock"
            ) {
                onSaveToWatchLater()
            }

            // Existing playlists.
            if isLoading {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Loading your playlists...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 6)
            } else if !playlists.isEmpty {
                Text("Your Playlists")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(playlists) { playlist in
                            pickerRow(
                                title: playlist.title,
                                subtitle: "\(playlist.videoCount) videos",
                                icon: "music.note.list"
                            ) {
                                onSaveToExisting(playlist)
                            }
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            Divider().padding(.vertical, 4)

            Button {
                isCreatingNew = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Color.accentColor)
                    Text("New playlist...")
                        .font(.body.weight(.medium))
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            if isSaving {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Saving...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
            }
        }
    }

    private var newPlaylistForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Playlist")
                .font(.subheadline.weight(.semibold))

            TextField("Playlist name", text: $newPlaylistName)
                .textFieldStyle(.roundedBorder)

            Picker("Privacy", selection: $newPlaylistPrivacy) {
                Text("Private").tag("private")
                Text("Unlisted").tag("unlisted")
                Text("Public").tag("public")
            }
            .pickerStyle(.segmented)

            HStack {
                Button("Back") {
                    isCreatingNew = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Spacer()

                Button {
                    let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onCreateAndSave(trimmed, newPlaylistPrivacy)
                } label: {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Create & Save")
                            .fontWeight(.semibold)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isSaving)
            }
        }
    }

    private func pickerRow(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    WatchView(
        videoURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!,
        videoId: "sample_preview",
        videoTitle: "Sample Video Title - This is a longer title that demonstrates text wrapping",
        videoDescription: "Sample description text.",
        channelId: "UC_x5XG1OV2P6uZZ5FSM9Ttw",
        channelName: "Sample Channel",
        channelAvatar: "person.fill",
        thumbnailURL: "https://i.ytimg.com/vi/jNQXAC9IVRw/maxresdefault.jpg",
        subscribers: "12.5M",
        views: "1.2M views",
        uploadDate: "3 days ago"
    )
    .environmentObject(YouTubeService())
    .environmentObject(AuthManager())
    .environmentObject(DownloadManager())
    .environmentObject(ExtensionsManager())
}
