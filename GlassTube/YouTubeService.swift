//
//  YouTubeService.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import Foundation
import SwiftUI
import Combine

struct StreamQualityOption: Identifiable, Equatable {
    let id: String
    let label: String
    let url: URL
    let height: Int
}

struct StreamManifest {
    let defaultURL: URL
    let qualityOptions: [StreamQualityOption]
}

/// High-level service for fetching YouTube data
@MainActor
class YouTubeService: ObservableObject {

    enum PersonalPlaylistKind {
        case likedVideos
        case watchLater
        case watchHistory

        var relatedPlaylistsKey: String {
            switch self {
            case .likedVideos:
                return "likes"
            case .watchLater:
                return "watchLater"
            case .watchHistory:
                return "watchHistory"
            }
        }

        var displayName: String {
            switch self {
            case .likedVideos:
                return "Liked Videos"
            case .watchLater:
                return "Watch Later"
            case .watchHistory:
                return "History"
            }
        }
    }
    
    // MARK: - Published State
    
    @Published var homeVideos: [Video] = []
    @Published var searchResults: [Video] = []
    @Published var isLoading = false
    @Published var isLoadingMoreHome = false
    @Published var isLoadingMoreSearch = false
    @Published var error: Error?
    
    // MARK: - Dependencies
    
    let api = InnertubeAPI()
    
    // MARK: - Cache
    
    private var videoCache: [String: Video] = [:]
    private var channelCache: [String: Channel] = [:]
    private var seenHomeVideoIDs = Set<String>()
    private var homeQueryCursor = 0
    private var currentHomeAccessToken: String?
    private var homePaginationExhausted = false
    private var seenSearchVideoIDs = Set<String>()
    private var searchQueryCursor = 0
    private var currentSearchQuery = ""

    private let homeDiscoveryQueries = [
        "trending now",
        "popular music",
        "gaming",
        "technology",
        "news",
        "new uploads",
        "movies trailers",
        "podcasts"
    ]

    private let searchExpansionSuffixes = [
        "",
        "official",
        "live",
        "new",
        "2026",
        "highlights",
        "full video"
    ]
    
    // MARK: - Home Feed
    
    func loadHomeFeed(accessToken: String? = nil) async {
        isLoading = true
        defer { isLoading = false }
        homeQueryCursor = Int.random(in: 0..<homeDiscoveryQueries.count)
        homePaginationExhausted = false
        seenHomeVideoIDs = []
        currentHomeAccessToken = accessToken

        var resolvedVideos: [Video] = []
        var lastHomeLoadError: Error?

        if let accessToken,
           let subscriptionFeed = try? await api.getSubscriptionFeed(accessToken: accessToken),
           !subscriptionFeed.isEmpty {
            resolvedVideos = deduplicate(subscriptionFeed, seen: &seenHomeVideoIDs)
        }

        do {
            let videos = try await api.getHomeFeed(accessToken: accessToken)
            if !videos.isEmpty {
                if resolvedVideos.isEmpty {
                    resolvedVideos = deduplicate(videos, seen: &seenHomeVideoIDs)
                } else {
                    resolvedVideos.append(contentsOf: deduplicate(videos, seen: &seenHomeVideoIDs))
                }
            }
        } catch {
            lastHomeLoadError = error
            self.error = error
        }

        if let accessToken,
           resolvedVideos.count < 48,
           let subscriptionFeed = try? await api.getSubscriptionFeed(accessToken: accessToken),
           !subscriptionFeed.isEmpty {
            resolvedVideos.append(contentsOf: deduplicate(subscriptionFeed, seen: &seenHomeVideoIDs))
        }

        if let accessToken,
           resolvedVideos.count < 48,
           let homeActivities = try? await fetchHomeActivityVideos(accessToken: accessToken),
           !homeActivities.isEmpty {
            resolvedVideos.append(contentsOf: deduplicate(homeActivities, seen: &seenHomeVideoIDs))
        }

        if let accessToken,
           resolvedVideos.count < 48,
           let recentSubscriptionUploads = try? await fetchRecentVideosFromSubscribedChannels(
            accessToken: accessToken,
            maxChannels: 80,
            videosPerChannel: 2,
            shuffleChannels: true
           ),
           !recentSubscriptionUploads.isEmpty {
            resolvedVideos.append(contentsOf: deduplicate(recentSubscriptionUploads, seen: &seenHomeVideoIDs))
        }

        if resolvedVideos.isEmpty {
            if let accessToken,
               let subscriptions = try? await api.getSubscriptionFeed(accessToken: accessToken),
               !subscriptions.isEmpty {
                resolvedVideos = deduplicate(subscriptions, seen: &seenHomeVideoIDs)
            } else {
                let discoveryFallback = await buildDiscoveryFallbackFeed(accessToken: accessToken)
                if !discoveryFallback.isEmpty {
                    resolvedVideos = deduplicate(discoveryFallback, seen: &seenHomeVideoIDs)
                } else if accessToken != nil {
                    // Signed-in paths can fail when token scopes/session are invalid.
                    // Fall back to anonymous discovery so Home still renders videos.
                    let anonymousFallback = await buildDiscoveryFallbackFeed()
                    if !anonymousFallback.isEmpty {
                        resolvedVideos = deduplicate(anonymousFallback, seen: &seenHomeVideoIDs)
                    }
                }
            }
        }

        if let accessToken, !resolvedVideos.isEmpty {
            resolvedVideos = await enrichVideosWithMetadata(resolvedVideos, accessToken: accessToken)
        }

        homeVideos = resolvedVideos
        if resolvedVideos.isEmpty {
            if let lastHomeLoadError {
                error = lastHomeLoadError
            } else {
                error = NSError(domain: "YouTubeService", code: 41, userInfo: [
                    NSLocalizedDescriptionKey: "Home feed returned no videos. Verify sign-in and network access."
                ])
            }
        } else {
            error = nil
        }

        if homeVideos.count < 48 {
            await loadMoreHomeFeed(minimumTargetCount: 48, accessToken: accessToken)
        }
    }

    // MARK: - Search

    func search(query: String) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            searchResults = []
            seenSearchVideoIDs = []
            currentSearchQuery = ""
            return
        }

        currentSearchQuery = normalizedQuery
        seenSearchVideoIDs = []
        searchQueryCursor = 0
        searchResults = []

        isLoading = true
        defer { isLoading = false }

        await loadMoreSearchResults(query: normalizedQuery, minimumTargetCount: 20)

        if searchResults.isEmpty {
            do {
                let fallback = try await api.search(query: normalizedQuery)
                searchResults = deduplicate(fallback, seen: &seenSearchVideoIDs)
            } catch {
                self.error = error
            }
        }
    }

    func loadMoreSearchResults(query: String) async {
        await loadMoreSearchResults(query: query, minimumTargetCount: searchResults.count + 18)
    }

    private func loadMoreSearchResults(query: String, minimumTargetCount: Int) async {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else { return }
        guard normalizedQuery == currentSearchQuery else { return }
        guard !isLoadingMoreSearch else { return }

        isLoadingMoreSearch = true
        defer { isLoadingMoreSearch = false }

        var attempts = 0
        while attempts < searchExpansionSuffixes.count,
              searchResults.count < minimumTargetCount {
            let suffix = searchExpansionSuffixes[searchQueryCursor % searchExpansionSuffixes.count]
            searchQueryCursor += 1
            let requestQuery = suffix.isEmpty ? normalizedQuery : "\(normalizedQuery) \(suffix)"

            do {
                let fetched = try await api.search(query: requestQuery)
                let unique = deduplicate(fetched, seen: &seenSearchVideoIDs)
                if !unique.isEmpty {
                    searchResults.append(contentsOf: unique)
                }
            } catch {
                self.error = error
            }

            attempts += 1
        }
    }

    func loadMoreHomeFeed() async {
        await loadMoreHomeFeed(minimumTargetCount: homeVideos.count + 20, accessToken: currentHomeAccessToken)
    }

    private func loadMoreHomeFeed(minimumTargetCount: Int, accessToken: String?) async {
        guard !isLoadingMoreHome else { return }
        guard !homePaginationExhausted else { return }

        isLoadingMoreHome = true
        defer { isLoadingMoreHome = false }

        let initialCount = homeVideos.count

        if let accessToken,
           homeVideos.count < minimumTargetCount,
           let subscriptions = try? await api.getSubscriptionFeed(accessToken: accessToken),
           !subscriptions.isEmpty {
            homeVideos.append(contentsOf: deduplicate(subscriptions, seen: &seenHomeVideoIDs))
        }

        if let accessToken, homeVideos.count < minimumTargetCount,
           let homeActivities = try? await fetchHomeActivityVideos(accessToken: accessToken, maxResults: 30),
           !homeActivities.isEmpty {
            homeVideos.append(contentsOf: deduplicate(homeActivities, seen: &seenHomeVideoIDs))
        }

        if let accessToken,
           homeVideos.count < minimumTargetCount,
           let subscriptionUploads = try? await fetchRecentVideosFromSubscribedChannels(
            accessToken: accessToken,
            maxChannels: 80,
            videosPerChannel: 3,
            shuffleChannels: true
           ),
           !subscriptionUploads.isEmpty {
            homeVideos.append(contentsOf: deduplicate(subscriptionUploads, seen: &seenHomeVideoIDs))
        }

        var attempts = 0
        while attempts < homeDiscoveryQueries.count,
              homeVideos.count < minimumTargetCount {
            let query = homeDiscoveryQueries[homeQueryCursor % homeDiscoveryQueries.count]
            homeQueryCursor += 1

            do {
                let fetched = try await api.search(query: query, accessToken: accessToken)
                let unique = deduplicate(fetched, seen: &seenHomeVideoIDs)
                if !unique.isEmpty {
                    homeVideos.append(contentsOf: unique)
                }
            } catch {
                self.error = error
            }

            attempts += 1
        }

        if homeVideos.count == initialCount {
            homePaginationExhausted = true
        }
    }

    // MARK: - Authenticated Library Data

    func fetchMyPlaylists(accessToken: String, maxResults: Int = 50) async throws -> [Playlist] {
        let targetCount = max(1, min(maxResults, 250))
        var aggregatedItems: [[String: Any]] = []
        var nextPageToken: String?

        while aggregatedItems.count < targetCount {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlists")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "mine", value: "true"),
                URLQueryItem(name: "maxResults", value: String(min(50, targetCount - aggregatedItems.count)))
            ]

            if let nextPageToken, !nextPageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }

            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw NSError(domain: "YouTubeService", code: 20, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build playlists request URL."
                ])
            }

            let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
            let pageItems = json["items"] as? [[String: Any]] ?? []
            aggregatedItems.append(contentsOf: pageItems)

            nextPageToken = json["nextPageToken"] as? String
            if nextPageToken == nil || pageItems.isEmpty {
                break
            }
        }

        let items = Array(aggregatedItems.prefix(targetCount))

        return items.compactMap { item in
            guard let id = item["id"] as? String,
                  let snippet = item["snippet"] as? [String: Any] else {
                return nil
            }

            let contentDetails = item["contentDetails"] as? [String: Any]
            let title = snippet["title"] as? String ?? "Untitled Playlist"
            let description = snippet["description"] as? String ?? ""
            let channelID = snippet["channelId"] as? String ?? ""
            let channelName = snippet["channelTitle"] as? String ?? ""
            let thumbnailURL = extractThumbnailURL(fromSnippet: snippet, fallbackVideoID: nil)
            let videoCount = contentDetails?["itemCount"] as? Int ?? 0

            return Playlist(
                id: id,
                title: title,
                description: description,
                channelId: channelID,
                channelName: channelName,
                thumbnailURL: thumbnailURL.isEmpty ? nil : thumbnailURL,
                videoCount: videoCount,
                videos: []
            )
        }
    }

    func fetchMyUploads(accessToken: String, maxResults: Int = 50) async throws -> [Video] {
        let targetCount = max(1, min(maxResults, 250))
        var aggregatedItems: [[String: Any]] = []
        var nextPageToken: String?

        while aggregatedItems.count < targetCount {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "forMine", value: "true"),
                URLQueryItem(name: "type", value: "video"),
                URLQueryItem(name: "order", value: "date"),
                URLQueryItem(name: "maxResults", value: String(min(50, targetCount - aggregatedItems.count)))
            ]

            if let nextPageToken, !nextPageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }

            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw NSError(domain: "YouTubeService", code: 21, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build uploads request URL."
                ])
            }

            let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
            let pageItems = json["items"] as? [[String: Any]] ?? []
            aggregatedItems.append(contentsOf: pageItems)

            nextPageToken = json["nextPageToken"] as? String
            if nextPageToken == nil || pageItems.isEmpty {
                break
            }
        }

        let items = Array(aggregatedItems.prefix(targetCount))
        let videos = deduplicatedVideos(items.compactMap(parseSearchItemToVideo))
        return await enrichVideosWithMetadata(videos, accessToken: accessToken)
    }

    func fetchVideosFromPersonalPlaylist(
        kind: PersonalPlaylistKind,
        accessToken: String,
        maxResults: Int = 50
    ) async throws -> [Video] {
        let playlistID = try await fetchRelatedPlaylistID(kind: kind, accessToken: accessToken)

        let targetCount = max(1, min(maxResults, 250))
        var aggregatedItems: [[String: Any]] = []
        var nextPageToken: String?

        while aggregatedItems.count < targetCount {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "playlistId", value: playlistID),
                URLQueryItem(name: "maxResults", value: String(min(50, targetCount - aggregatedItems.count)))
            ]

            if let nextPageToken, !nextPageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }

            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw NSError(domain: "YouTubeService", code: 22, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build playlist items request URL."
                ])
            }

            let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
            let pageItems = json["items"] as? [[String: Any]] ?? []
            aggregatedItems.append(contentsOf: pageItems)

            nextPageToken = json["nextPageToken"] as? String
            if nextPageToken == nil || pageItems.isEmpty {
                break
            }
        }

        let items = Array(aggregatedItems.prefix(targetCount))
        let videos = deduplicatedVideos(items.compactMap(parsePlaylistItemToVideo))
        return await enrichVideosWithMetadata(videos, accessToken: accessToken)
    }

    func fetchVideosInPlaylist(
        playlistID: String,
        accessToken: String,
        maxResults: Int = 50
    ) async throws -> [Video] {
        let targetCount = max(1, min(maxResults, 250))
        var aggregatedItems: [[String: Any]] = []
        var nextPageToken: String?

        while aggregatedItems.count < targetCount {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "playlistId", value: playlistID),
                URLQueryItem(name: "maxResults", value: String(min(50, targetCount - aggregatedItems.count)))
            ]

            if let nextPageToken, !nextPageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }

            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw NSError(domain: "YouTubeService", code: 27, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build playlist items request URL."
                ])
            }

            let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
            let pageItems = json["items"] as? [[String: Any]] ?? []
            aggregatedItems.append(contentsOf: pageItems)

            nextPageToken = json["nextPageToken"] as? String
            if nextPageToken == nil || pageItems.isEmpty {
                break
            }
        }

        let items = Array(aggregatedItems.prefix(targetCount))
        let videos = deduplicatedVideos(items.compactMap(parsePlaylistItemToVideo))
        return await enrichVideosWithMetadata(videos, accessToken: accessToken)
    }

    func fetchHomeActivityVideos(accessToken: String, maxResults: Int = 30) async throws -> [Video] {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/activities")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,contentDetails"),
            URLQueryItem(name: "home", value: "true"),
            URLQueryItem(name: "maxResults", value: String(max(1, min(maxResults, 50))))
        ]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 28, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build activities request URL."
            ])
        }

        let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
        let items = json["items"] as? [[String: Any]] ?? []
        let videos = deduplicatedVideos(items.compactMap(parseActivityItemToVideo))
        return await enrichVideosWithMetadata(videos, accessToken: accessToken)
    }

    /// Adds a video to Watch Later. The Data API has blocked
    /// playlistItems.insert against the `WL` playlist since 2016, so this
    /// routes through Innertube's `browse/edit_playlist` endpoint (same path
    /// YouTube's own web app uses when clicking "Save to Watch Later").
    func addVideoToWatchLater(videoId: String, accessToken: String) async throws {
        do {
            try await api.addToWatchLater(videoId: videoId, accessToken: accessToken)
        } catch {
            throw NSError(domain: "YouTubeService", code: 33, userInfo: [
                NSLocalizedDescriptionKey: "Watch Later failed via Innertube: \(error.localizedDescription)"
            ])
        }
    }

    /// Fetches or creates a GlassTube-managed "Watch Later" playlist.
    /// YouTube's native Watch Later (`WL`) cannot be read via any API, so this
    /// provides a user-accessible alternative that GlassTube fully controls.
    func fetchOrCreateGlassTubeWatchLaterPlaylist(accessToken: String) async throws -> Playlist {
        let glassTubePlaylistTitle = "GlassTube Watch Later"
        
        // Check if it already exists
        let existingPlaylists = try await fetchMyPlaylists(accessToken: accessToken, maxResults: 200)
        if let existing = existingPlaylists.first(where: { $0.title == glassTubePlaylistTitle }) {
            return existing
        }
        
        // Create it if not found
        return try await createPlaylist(
            title: glassTubePlaylistTitle,
            privacyStatus: "private",
            accessToken: accessToken
        )
    }

    /// Adds a video to the GlassTube-managed Watch Later playlist (creating it if needed).
    func addVideoToGlassTubeWatchLater(videoId: String, accessToken: String) async throws {
        let playlist = try await fetchOrCreateGlassTubeWatchLaterPlaylist(accessToken: accessToken)
        try await addVideo(videoId: videoId, toPlaylistID: playlist.id, accessToken: accessToken)
    }

    func addVideo(videoId: String, toPlaylistID playlistID: String, accessToken: String) async throws {
        // Watch Later specifically has been blocked on the Data API since 2016;
        // skip the Data API attempt and go straight to Innertube.
        if playlistID == "WL" {
            try await api.addToWatchLater(videoId: videoId, accessToken: accessToken)
            return
        }

        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet") else {
            throw NSError(domain: "YouTubeService", code: 29, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build playlist insert request URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "snippet": [
                "playlistId": playlistID,
                "resourceId": [
                    "kind": "youtube#video",
                    "videoId": videoId
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 30, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            // Data API rejected the write (commonly because force-ssl isn't in
            // our scope set). Fall back to Innertube, which works under the
            // `youtube` scope our device-flow OAuth actually grants.
            do {
                try await api.addVideoToPlaylist(
                    videoId: videoId,
                    playlistId: playlistID,
                    accessToken: accessToken
                )
                return
            } catch {
                let message = parseYouTubeDataErrorMessage(from: data)
                    ?? "Failed to save video to playlist (HTTP \(httpResponse.statusCode))."
                throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: message
                ])
            }
        }
    }

    /// Removes a video from a playlist by finding and deleting the playlist item.
    func removeVideoFromPlaylist(videoId: String, playlistId: String, accessToken: String) async throws {
        // First, we need to find the playlistItem ID for this video in this playlist.
        // YouTube's API requires the playlistItem ID (not just videoId) to delete.
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "id,snippet"),
            URLQueryItem(name: "playlistId", value: playlistId),
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "maxResults", value: "1")
        ]

        guard let searchURL = components?.url else {
            throw NSError(domain: "YouTubeService", code: 63, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build playlist item search URL."
            ])
        }

        let searchJSON = try await fetchYouTubeDataJSON(url: searchURL, accessToken: accessToken)
        guard let items = searchJSON["items"] as? [[String: Any]],
              let firstItem = items.first,
              let playlistItemId = firstItem["id"] as? String else {
            throw NSError(domain: "YouTubeService", code: 64, userInfo: [
                NSLocalizedDescriptionKey: "Could not find this video in the playlist."
            ])
        }

        // Now delete the playlist item
        var deleteComponents = URLComponents(string: "https://www.googleapis.com/youtube/v3/playlistItems")
        deleteComponents?.queryItems = [URLQueryItem(name: "id", value: playlistItemId)]

        guard let deleteURL = deleteComponents?.url else {
            throw NSError(domain: "YouTubeService", code: 65, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build delete URL."
            ])
        }

        var request = URLRequest(url: deleteURL)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 66, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseYouTubeDataErrorMessage(from: data)
                ?? "Failed to remove video from playlist (HTTP \(httpResponse.statusCode))."
            throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    /// Creates a new playlist owned by the signed-in user. Tries the Data API
    /// first (`playlists.insert`) and falls back to Innertube `playlist/create`
    /// if the Data API rejects the write for this scope.
    func createPlaylist(
        title: String,
        privacyStatus: String = "private",
        accessToken: String
    ) async throws -> Playlist {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else {
            throw NSError(domain: "YouTubeService", code: 62, userInfo: [
                NSLocalizedDescriptionKey: "Playlist name cannot be empty."
            ])
        }

        let normalizedPrivacy: String = {
            switch privacyStatus.lowercased() {
            case "public", "unlisted", "private": return privacyStatus.lowercased()
            default: return "private"
            }
        }()

        if let url = URL(string: "https://www.googleapis.com/youtube/v3/playlists?part=snippet,status") {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let body: [String: Any] = [
                "snippet": [
                    "title": trimmedTitle
                ],
                "status": [
                    "privacyStatus": normalizedPrivacy
                ]
            ]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)

            if let (data, response) = try? await URLSession.shared.data(for: request),
               let httpResponse = response as? HTTPURLResponse,
               (200...299).contains(httpResponse.statusCode),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let id = json["id"] as? String,
               !id.isEmpty {
                return Playlist(
                    id: id,
                    title: trimmedTitle,
                    description: "",
                    channelId: "",
                    channelName: "",
                    thumbnailURL: nil,
                    videoCount: 0,
                    videos: []
                )
            }
        }

        // Data API rejected it (or returned an unexpected shape). Fall back to
        // Innertube, which plays nicer with our device-flow OAuth scope set.
        let id = try await api.createPlaylist(
            title: trimmedTitle,
            privacyStatus: normalizedPrivacy,
            accessToken: accessToken
        )
        return Playlist(
            id: id,
            title: trimmedTitle,
            description: "",
            channelId: "",
            channelName: "",
            thumbnailURL: nil,
            videoCount: 0,
            videos: []
        )
    }

    func rateVideo(videoId: String, rating: String, accessToken: String) async throws {
        let normalizedRating = rating.lowercased()
        guard ["like", "dislike", "none"].contains(normalizedRating) else {
            throw NSError(domain: "YouTubeService", code: 35, userInfo: [
                NSLocalizedDescriptionKey: "Invalid rating value: \(rating)."
            ])
        }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos/rate")
        components?.queryItems = [
            URLQueryItem(name: "id", value: videoId),
            URLQueryItem(name: "rating", value: normalizedRating)
        ]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 36, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build video rating request URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 37, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseYouTubeDataErrorMessage(from: data)
                ?? "Failed to rate video (HTTP \(httpResponse.statusCode))."
            throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    func fetchComments(videoId: String, accessToken: String? = nil, maxResults: Int = 25) async throws -> [Comment] {
        // Try Innertube first — it's the same source YouTube's web client uses
        // and doesn't burn Data API quota. Any failure (comments disabled,
        // unexpected shape) falls through to the Data API path below.
        if let innertubeComments = try? await api.getComments(videoId: videoId, accessToken: accessToken),
           !innertubeComments.isEmpty {
            let capped = Array(innertubeComments.prefix(max(1, min(maxResults, 100))))
            return capped
        }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/commentThreads")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "snippet,replies"),
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "textFormat", value: "plainText"),
            URLQueryItem(name: "order", value: "relevance"),
            URLQueryItem(name: "maxResults", value: String(max(1, min(maxResults, 100))))
        ]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 38, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build comments request URL."
            ])
        }

        let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
        let items = json["items"] as? [[String: Any]] ?? []
        return items.compactMap { parseCommentThread($0, videoId: videoId) }
    }

    func postComment(videoId: String, text: String, accessToken: String) async throws {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            throw NSError(domain: "YouTubeService", code: 43, userInfo: [
                NSLocalizedDescriptionKey: "Comment text cannot be empty."
            ])
        }

        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/commentThreads?part=snippet") else {
            throw NSError(domain: "YouTubeService", code: 44, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build comment creation request URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "snippet": [
                "videoId": videoId,
                "topLevelComment": [
                    "snippet": [
                        "textOriginal": trimmedText
                    ]
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 45, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseYouTubeDataErrorMessage(from: data)
                ?? "Failed to post comment (HTTP \(httpResponse.statusCode))."
            throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    func subscribeToChannel(channelId: String, accessToken: String) async throws -> String {
        guard let url = URL(string: "https://www.googleapis.com/youtube/v3/subscriptions?part=snippet") else {
            throw NSError(domain: "YouTubeService", code: 39, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build subscription request URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "snippet": [
                "resourceId": [
                    "kind": "youtube#channel",
                    "channelId": channelId
                ]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 40, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseYouTubeDataErrorMessage(from: data)
                ?? "Failed to subscribe to channel (HTTP \(httpResponse.statusCode))."
            throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let subscriptionId = json["id"] as? String, !subscriptionId.isEmpty {
            return subscriptionId
        }
        return ""
    }

    /// Checks whether the signed-in user is subscribed to `channelId`. Returns
    /// the subscription resource id when subscribed (needed for unsubscribe),
    /// or nil when not subscribed.
    func checkSubscription(channelId: String, accessToken: String) async throws -> String? {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/subscriptions")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "id"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "forChannelId", value: channelId),
            URLQueryItem(name: "maxResults", value: "1")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 46, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build subscription check URL."
            ])
        }

        let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
        let items = json["items"] as? [[String: Any]] ?? []
        return items.first?["id"] as? String
    }

    func unsubscribeFromChannel(subscriptionId: String, accessToken: String) async throws {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/subscriptions")
        components?.queryItems = [URLQueryItem(name: "id", value: subscriptionId)]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 47, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build unsubscribe request URL."
            ])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 48, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseYouTubeDataErrorMessage(from: data)
                ?? "Failed to unsubscribe (HTTP \(httpResponse.statusCode))."
            throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }

    func fetchChannel(channelId: String, accessToken: String? = nil) async throws -> Channel {
        if let cached = channelCache[channelId] {
            return cached
        }

        let channel = try await api.getChannel(channelId: channelId, accessToken: accessToken)
        channelCache[channelId] = channel
        return channel
    }

    func fetchChannelVideos(
        channelId: String,
        accessToken: String? = nil,
        maxResults: Int = 50
    ) async throws -> [Video] {
        let rawVideos = try await api.getChannelVideos(
            channelId: channelId,
            accessToken: accessToken,
            maxResults: maxResults
        )

        guard let accessToken, !rawVideos.isEmpty else {
            return rawVideos
        }

        return await enrichVideosWithMetadata(rawVideos, accessToken: accessToken)
    }

    func fetchRecentVideosFromSubscribedChannels(
        accessToken: String,
        maxChannels: Int = 20,
        videosPerChannel: Int = 2,
        shuffleChannels: Bool = false
    ) async throws -> [Video] {
        guard maxChannels > 0 else { return [] }

        var channelIDs: [String] = []
        var seenChannelIDs = Set<String>()
        var nextPageToken: String?

        while channelIDs.count < maxChannels {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/subscriptions")
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "part", value: "snippet"),
                URLQueryItem(name: "mine", value: "true"),
                URLQueryItem(name: "maxResults", value: "50")
            ]

            if let nextPageToken, !nextPageToken.isEmpty {
                queryItems.append(URLQueryItem(name: "pageToken", value: nextPageToken))
            }

            components?.queryItems = queryItems

            guard let url = components?.url else {
                throw NSError(domain: "YouTubeService", code: 31, userInfo: [
                    NSLocalizedDescriptionKey: "Failed to build subscriptions request URL."
                ])
            }

            let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
            let items = json["items"] as? [[String: Any]] ?? []

            for item in items {
                guard let snippet = item["snippet"] as? [String: Any],
                      let resourceID = snippet["resourceId"] as? [String: Any],
                      let channelID = resourceID["channelId"] as? String,
                      !channelID.isEmpty,
                      seenChannelIDs.insert(channelID).inserted else {
                    continue
                }

                channelIDs.append(channelID)
                if channelIDs.count >= maxChannels {
                    break
                }
            }

            if channelIDs.count >= maxChannels {
                break
            }

            nextPageToken = json["nextPageToken"] as? String
            if nextPageToken == nil {
                break
            }
        }

        if channelIDs.isEmpty {
            return []
        }

        if shuffleChannels {
            channelIDs.shuffle()
        }

        var collectedVideos: [Video] = []
        let perChannelLimit = max(1, min(videosPerChannel, 10))

        for channelID in channelIDs {
            var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/activities")
            components?.queryItems = [
                URLQueryItem(name: "part", value: "snippet,contentDetails"),
                URLQueryItem(name: "channelId", value: channelID),
                URLQueryItem(name: "maxResults", value: String(perChannelLimit))
            ]

            guard let url = components?.url else { continue }

            do {
                let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
                let items = json["items"] as? [[String: Any]] ?? []
                collectedVideos.append(contentsOf: items.compactMap(parseActivityItemToVideo))
            } catch {
                continue
            }
        }

        let videos = deduplicatedVideos(collectedVideos).sorted { $0.publishedAt > $1.publishedAt }
        return await enrichVideosWithMetadata(videos, accessToken: accessToken)
    }

    private func fetchRelatedPlaylistID(kind: PersonalPlaylistKind, accessToken: String) async throws -> String {
        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/channels")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails"),
            URLQueryItem(name: "mine", value: "true"),
            URLQueryItem(name: "maxResults", value: "1")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 23, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build channels request URL."
            ])
        }

        let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
        if let items = json["items"] as? [[String: Any]],
           let first = items.first,
           let contentDetails = first["contentDetails"] as? [String: Any],
           let relatedPlaylists = contentDetails["relatedPlaylists"] as? [String: Any],
           let playlistID = relatedPlaylists[kind.relatedPlaylistsKey] as? String,
           !playlistID.isEmpty {
            return playlistID
        }

        switch kind {
        case .watchLater:
            return "WL"
        case .likedVideos:
            return "LL"
        case .watchHistory:
            return "HL"
        }
    }

    private func fetchYouTubeDataJSON(url: URL, accessToken: String?) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "YouTubeService", code: 25, userInfo: [
                NSLocalizedDescriptionKey: "Invalid response from YouTube Data API."
            ])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseYouTubeDataErrorMessage(from: data) ?? "YouTube Data API request failed with HTTP \(httpResponse.statusCode)."
            throw NSError(domain: "YouTubeService", code: httpResponse.statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "YouTubeService", code: 26, userInfo: [
                NSLocalizedDescriptionKey: "Invalid JSON payload from YouTube Data API."
            ])
        }

        return json
    }

    func isQuotaExceededError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("quota") || message.contains("daily limit")
    }

    func isInsufficientScopeError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("insufficient authentication scopes")
            || message.contains("insufficientpermissions")
            || message.contains("insufficient permissions")
    }

    func quotaExceededMessage(for feature: String) -> String {
        "Google API quota was exceeded while loading \(feature). Quota resets daily at midnight Pacific Time. To fix immediately, use a different Google Cloud project/OAuth client with YouTube Data API enabled, or wait for the daily reset."
    }

    func insufficientScopeMessage(for feature: String) -> String {
        "Google reported insufficient OAuth scopes for \(feature). Google's TV/Limited-Input device flow (the only flow GlassTube uses) doesn't grant youtube.force-ssl, so Data API write actions like comment posting, video ratings, and subscribe/unsubscribe are not supported via this sign-in. Use YouTube in a browser for those actions, or open the video on YouTube from the share menu."
    }

    func homeFeedLoadFailureMessage(isSignedIn: Bool) -> String {
        guard let error else {
            return isSignedIn
                ? "Home feed returned no videos for this account. Retry, then check your OAuth setup and quotas in Settings."
                : "Home feed returned no videos for this session. Retry or sign in to load personalized videos."
        }

        if isQuotaExceededError(error) {
            return quotaExceededMessage(for: "Home feed")
        }

        let message = error.localizedDescription
        let lower = message.lowercased()

        if lower.contains("http 401") || lower.contains("unauthorized") || lower.contains("invalid credentials") {
            return "Your sign-in token is no longer valid. Re-authenticate in Settings > Authentication, then retry Home."
        }

        if lower.contains("invalid argument") || lower.contains("badrequest") {
            return "YouTube rejected one of the Home feed requests. Retry now; GlassTube will continue using search-based discovery fallback."
        }

        return message
    }

    private func parseYouTubeDataErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else {
            return nil
        }

        if let message = error["message"] as? String, !message.isEmpty {
            return message
        }

        if let details = error["errors"] as? [[String: Any]],
           let first = details.first,
           let reason = first["reason"] as? String,
           !reason.isEmpty {
            return reason
        }

        return nil
    }

    private func parseSearchItemToVideo(_ item: [String: Any]) -> Video? {
        guard let id = item["id"] as? [String: Any],
              let videoID = id["videoId"] as? String,
              let snippet = item["snippet"] as? [String: Any] else {
            return nil
        }

        let title = snippet["title"] as? String ?? "Untitled"
        let description = snippet["description"] as? String ?? ""
        let channelID = snippet["channelId"] as? String ?? ""
        let channelName = snippet["channelTitle"] as? String ?? "Unknown"
        let thumbnailURL = extractThumbnailURL(fromSnippet: snippet, fallbackVideoID: videoID)

        return Video(
            id: videoID,
            title: title,
            description: description,
            channelId: channelID,
            channelName: channelName,
            channelAvatar: nil,
            thumbnailURL: thumbnailURL,
            duration: 0,
            viewCount: 0,
            likeCount: nil,
            publishedAt: parsePublishedDate(snippet["publishedAt"] as? String),
            isLive: false,
            isUpcoming: false
        )
    }

    private func parsePlaylistItemToVideo(_ item: [String: Any]) -> Video? {
        guard let snippet = item["snippet"] as? [String: Any] else {
            return nil
        }

        let contentDetails = item["contentDetails"] as? [String: Any]
        let resourceID = snippet["resourceId"] as? [String: Any]
        let videoID = (resourceID?["videoId"] as? String) ?? (contentDetails?["videoId"] as? String) ?? ""

        guard !videoID.isEmpty else { return nil }

        let title = snippet["title"] as? String ?? "Untitled"
        let description = snippet["description"] as? String ?? ""
        let channelID = snippet["channelId"] as? String ?? ""
        let channelName = snippet["videoOwnerChannelTitle"] as? String ?? (snippet["channelTitle"] as? String ?? "Unknown")
        let thumbnailURL = extractThumbnailURL(fromSnippet: snippet, fallbackVideoID: videoID)

        return Video(
            id: videoID,
            title: title,
            description: description,
            channelId: channelID,
            channelName: channelName,
            channelAvatar: nil,
            thumbnailURL: thumbnailURL,
            duration: 0,
            viewCount: 0,
            likeCount: nil,
            publishedAt: parsePublishedDate(snippet["publishedAt"] as? String),
            isLive: false,
            isUpcoming: false
        )
    }

    private func parseCommentThread(_ item: [String: Any], videoId: String) -> Comment? {
        guard let snippet = item["snippet"] as? [String: Any],
              let topLevelComment = snippet["topLevelComment"] as? [String: Any],
              let topLevelSnippet = topLevelComment["snippet"] as? [String: Any],
              let commentID = topLevelComment["id"] as? String else {
            return nil
        }

        let replies = ((item["replies"] as? [String: Any])?["comments"] as? [[String: Any]] ?? [])
            .compactMap { parseCommentReply($0, videoId: videoId) }

        let authorChannelID = (topLevelSnippet["authorChannelId"] as? [String: Any])?["value"] as? String ?? ""
        let textOriginal = topLevelSnippet["textOriginal"] as? String
        let textDisplay = topLevelSnippet["textDisplay"] as? String

        return Comment(
            id: commentID,
            videoId: videoId,
            authorName: topLevelSnippet["authorDisplayName"] as? String ?? "Unknown",
            authorAvatar: topLevelSnippet["authorProfileImageUrl"] as? String,
            authorChannelId: authorChannelID,
            text: textOriginal ?? textDisplay ?? "",
            likeCount: intValue(topLevelSnippet["likeCount"]),
            publishedAt: parsePublishedDate(topLevelSnippet["publishedAt"] as? String),
            isPinned: topLevelSnippet["viewerRating"] as? String == "like",
            isCreatorHeart: (topLevelSnippet["authorIsChannelOwner"] as? Bool) ?? false,
            replyCount: intValue(snippet["totalReplyCount"]),
            replies: replies.isEmpty ? nil : replies
        )
    }

    private func parseCommentReply(_ item: [String: Any], videoId: String) -> Comment? {
        guard let snippet = item["snippet"] as? [String: Any],
              let commentID = item["id"] as? String else {
            return nil
        }

        let authorChannelID = (snippet["authorChannelId"] as? [String: Any])?["value"] as? String ?? ""
        let textOriginal = snippet["textOriginal"] as? String
        let textDisplay = snippet["textDisplay"] as? String

        return Comment(
            id: commentID,
            videoId: videoId,
            authorName: snippet["authorDisplayName"] as? String ?? "Unknown",
            authorAvatar: snippet["authorProfileImageUrl"] as? String,
            authorChannelId: authorChannelID,
            text: textOriginal ?? textDisplay ?? "",
            likeCount: intValue(snippet["likeCount"]),
            publishedAt: parsePublishedDate(snippet["publishedAt"] as? String),
            isPinned: false,
            isCreatorHeart: (snippet["authorIsChannelOwner"] as? Bool) ?? false,
            replyCount: 0,
            replies: nil
        )
    }

    private func intValue(_ value: Any?) -> Int {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String, let intValue = Int(string) { return intValue }
        return 0
    }

    private func parseActivityItemToVideo(_ item: [String: Any]) -> Video? {
        guard let snippet = item["snippet"] as? [String: Any],
              let contentDetails = item["contentDetails"] as? [String: Any],
              let upload = contentDetails["upload"] as? [String: Any],
              let videoID = upload["videoId"] as? String,
              !videoID.isEmpty else {
            return nil
        }

        let title = snippet["title"] as? String ?? "Untitled"
        let description = snippet["description"] as? String ?? ""
        let channelID = snippet["channelId"] as? String ?? ""
        let channelName = snippet["channelTitle"] as? String ?? "Unknown"
        let thumbnailURL = extractThumbnailURL(fromSnippet: snippet, fallbackVideoID: videoID)

        return Video(
            id: videoID,
            title: title,
            description: description,
            channelId: channelID,
            channelName: channelName,
            channelAvatar: nil,
            thumbnailURL: thumbnailURL,
            duration: 0,
            viewCount: 0,
            likeCount: nil,
            publishedAt: parsePublishedDate(snippet["publishedAt"] as? String),
            isLive: false,
            isUpcoming: false
        )
    }

    private func extractThumbnailURL(fromSnippet snippet: [String: Any], fallbackVideoID: String?) -> String {
        if let thumbnails = snippet["thumbnails"] as? [String: Any] {
            let preferredKeys = ["maxres", "standard", "high", "medium", "default"]
            for key in preferredKeys {
                if let image = thumbnails[key] as? [String: Any],
                   let url = image["url"] as? String,
                   !url.isEmpty {
                    return url
                }
            }
        }

        if let fallbackVideoID, !fallbackVideoID.isEmpty {
            return "https://i.ytimg.com/vi/\(fallbackVideoID)/hqdefault.jpg"
        }

        return ""
    }

    private func parsePublishedDate(_ raw: String?) -> Date {
        guard let raw, !raw.isEmpty else { return Date() }

        let formatterWithFractionalSeconds = ISO8601DateFormatter()
        formatterWithFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatterWithFractionalSeconds.date(from: raw) {
            return date
        }

        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: raw) {
            return date
        }

        return Date()
    }

    private func deduplicatedVideos(_ videos: [Video]) -> [Video] {
        var seenIDs = Set<String>()
        var deduplicated: [Video] = []
        for video in videos where seenIDs.insert(video.id).inserted {
            deduplicated.append(video)
        }
        return deduplicated
    }

    func enrichVideosWithMetadata(_ videos: [Video], accessToken: String) async -> [Video] {
        guard !videos.isEmpty else { return videos }

        let uniqueIDs = Array(Set(videos.map(\.id)))
        guard !uniqueIDs.isEmpty else { return videos }

        var metadataByID: [String: (duration: TimeInterval, views: Int)] = [:]

        do {
            for chunk in stride(from: 0, to: uniqueIDs.count, by: 50) {
                let end = min(chunk + 50, uniqueIDs.count)
                let idChunk = Array(uniqueIDs[chunk..<end])
                let chunkMetadata = try await fetchVideoMetadata(for: idChunk, accessToken: accessToken)
                metadataByID.merge(chunkMetadata) { _, latest in latest }
            }
        } catch {
            return videos
        }

        return videos.map { video in
            guard let metadata = metadataByID[video.id] else { return video }

            let resolvedDuration = metadata.duration > 0 ? metadata.duration : video.duration
            let resolvedViews = metadata.views > 0 ? metadata.views : video.viewCount

            if resolvedDuration == video.duration && resolvedViews == video.viewCount {
                return video
            }

            return Video(
                id: video.id,
                title: video.title,
                description: video.description,
                channelId: video.channelId,
                channelName: video.channelName,
                channelAvatar: video.channelAvatar,
                thumbnailURL: video.thumbnailURL,
                duration: resolvedDuration,
                viewCount: resolvedViews,
                likeCount: video.likeCount,
                publishedAt: video.publishedAt,
                isLive: video.isLive,
                isUpcoming: video.isUpcoming
            )
        }
    }

    private func fetchVideoMetadata(for videoIDs: [String], accessToken: String) async throws -> [String: (duration: TimeInterval, views: Int)] {
        guard !videoIDs.isEmpty else { return [:] }

        var components = URLComponents(string: "https://www.googleapis.com/youtube/v3/videos")
        components?.queryItems = [
            URLQueryItem(name: "part", value: "contentDetails,statistics"),
            URLQueryItem(name: "id", value: videoIDs.joined(separator: ",")),
            URLQueryItem(name: "maxResults", value: "50")
        ]

        guard let url = components?.url else {
            throw NSError(domain: "YouTubeService", code: 34, userInfo: [
                NSLocalizedDescriptionKey: "Failed to build videos metadata request URL."
            ])
        }

        let json = try await fetchYouTubeDataJSON(url: url, accessToken: accessToken)
        let items = json["items"] as? [[String: Any]] ?? []

        var metadata: [String: (duration: TimeInterval, views: Int)] = [:]
        for item in items {
            guard let id = item["id"] as? String, !id.isEmpty else { continue }

            let contentDetails = item["contentDetails"] as? [String: Any]
            let statistics = item["statistics"] as? [String: Any]

            let durationString = contentDetails?["duration"] as? String ?? ""
            let parsedDuration = parseISO8601Duration(durationString)
            let views = Int(statistics?["viewCount"] as? String ?? "0") ?? 0

            metadata[id] = (duration: parsedDuration, views: views)
        }

        return metadata
    }

    private func parseISO8601Duration(_ value: String) -> TimeInterval {
        guard !value.isEmpty else { return 0 }

        let pattern = #"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return 0 }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, options: [], range: range) else { return 0 }

        func intValue(at index: Int) -> Int {
            let nsRange = match.range(at: index)
            guard nsRange.location != NSNotFound,
                  let swiftRange = Range(nsRange, in: value) else {
                return 0
            }
            return Int(value[swiftRange]) ?? 0
        }

        let hours = intValue(at: 1)
        let minutes = intValue(at: 2)
        let seconds = intValue(at: 3)

        return TimeInterval((hours * 3600) + (minutes * 60) + seconds)
    }
    
    // MARK: - Video Details
    
    func getVideo(id: String) async throws -> Video {
        // Check cache first
        if let cached = videoCache[id] {
            return cached
        }
        
        // Fetch from API
        let response = try await api.getVideoDetails(videoId: id)
        
        guard let details = response.videoDetails else {
            throw NSError(domain: "YouTubeService", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No video details found"
            ])
        }
        
        // Parse to Video model
        let video = Video(
            id: details.videoId,
            title: details.title,
            description: details.shortDescription,
            channelId: details.channelId,
            channelName: details.author,
            channelAvatar: nil,
            thumbnailURL: details.thumbnail.thumbnails.last?.url ?? "",
            duration: TimeInterval(details.lengthSeconds) ?? 0,
            viewCount: Int(details.viewCount ?? "0") ?? 0,
            likeCount: nil,
            publishedAt: Date(),
            isLive: false,
            isUpcoming: false
        )
        
        // Cache it
        videoCache[id] = video
        
        return video
    }
    
    // MARK: - Get Video Stream URL

    func getStreamManifest(videoId: String) async throws -> StreamManifest {
        if let iosManifest = try? await getStreamManifestFromIOSClient(videoId: videoId) {
            return iosManifest
        }

        if let androidManifest = try? await getStreamManifestFromAndroidClient(videoId: videoId) {
            return androidManifest
        }

        if let ytDlpURL = try? await Self.extractStreamURLWithYtDlp(videoId: videoId) {
            return StreamManifest(
                defaultURL: ytDlpURL,
                qualityOptions: [
                    StreamQualityOption(id: "auto", label: "Auto", url: ytDlpURL, height: Int.max)
                ]
            )
        }

        throw NSError(domain: "YouTubeService", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "No valid stream URL found for video \(videoId). Try installing yt-dlp (brew install yt-dlp) for better compatibility."
        ])
    }

    func getStreamURL(videoId: String) async throws -> URL {
        let manifest = try await getStreamManifest(videoId: videoId)
        return manifest.defaultURL
    }

    private func getStreamManifestFromAndroidClient(videoId: String) async throws -> StreamManifest {
        let json = try await api.getAndroidPlayerResponse(videoId: videoId)

        if let playability = json["playabilityStatus"] as? [String: Any],
           let status = playability["status"] as? String,
           status != "OK" {
            throw NSError(domain: "YouTubeService", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Video not playable: \(status)"
            ])
        }

        guard let streamingData = json["streamingData"] as? [String: Any] else {
            throw NSError(domain: "YouTubeService", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "No streaming data in ANDROID response"
            ])
        }

        if let hlsURLString = streamingData["hlsManifestUrl"] as? String,
           let defaultHLSURL = URL(string: hlsURLString) {
            var heights = availableHeights(
                combined: streamingData["formats"] as? [[String: Any]],
                adaptive: streamingData["adaptiveFormats"] as? [[String: Any]]
            )
            let m3u8Heights = await Self.fetchHLSVariantHeights(masterURL: defaultHLSURL)
            if !m3u8Heights.isEmpty { heights = m3u8Heights }
            let options = hlsHeightOptions(availableHeights: heights, hlsURL: defaultHLSURL)
            return manifest(defaultURL: defaultHLSURL, options: options)
        }

        // AVPlayer can't play YouTube's DASH video-only `adaptiveFormats` with
        // audio — it would play silent. Combined `formats` (≤720p) include an
        // audio track, so they are the only safe single-URL fallback.
        let combinedOptions = combinedOnlyQualityOptions(from: streamingData["formats"] as? [[String: Any]])
        if let combinedURL = bestURLFromRawFormats(streamingData["formats"] as? [[String: Any]], preferCombined: true) {
            return manifest(defaultURL: combinedURL, options: combinedOptions)
        }

        throw NSError(domain: "YouTubeService", code: 12, userInfo: [
            NSLocalizedDescriptionKey: "No combined (video+audio) URL in ANDROID response — try yt-dlp fallback."
        ])
    }

    /// Pick the best format URL from raw JSON format arrays.
    private func bestURLFromRawFormats(_ formats: [[String: Any]]?, preferCombined: Bool) -> URL? {
        guard let formats else { return nil }

        let candidates = formats.filter { format in
            guard let urlString = format["url"] as? String, !urlString.isEmpty else { return false }
            let mimeType = format["mimeType"] as? String ?? ""
            if preferCombined {
                // Combined formats contain both video and audio tracks
                return mimeType.contains("video") && (mimeType.contains("mp4a") || mimeType.contains("opus"))
            } else {
                return mimeType.contains("video")
            }
        }

        // Sort by height descending, pick the highest available quality
        let sorted = candidates.sorted { a, b in
            let ha = a["height"] as? Int ?? 0
            let hb = b["height"] as? Int ?? 0
            return ha > hb
        }

        if let urlString = sorted.first?["url"] as? String, let url = URL(string: urlString) {
            return url
        }
        return nil
    }

    private func getStreamManifestFromIOSClient(videoId: String) async throws -> StreamManifest {
        let response = try await api.getPlaybackDetails(videoId: videoId)
        let streamingData = response.streamingData

        if let hlsManifestURLString = streamingData?.hlsManifestUrl,
           let hlsURL = URL(string: hlsManifestURLString) {
            let allFormats = (streamingData?.formats ?? []) + (streamingData?.adaptiveFormats ?? [])
            var heights = availableHeights(formats: allFormats)
            let m3u8Heights = await Self.fetchHLSVariantHeights(masterURL: hlsURL)
            if !m3u8Heights.isEmpty { heights = m3u8Heights }
            let options = hlsHeightOptions(availableHeights: heights, hlsURL: hlsURL)
            return manifest(defaultURL: hlsURL, options: options)
        }

        let combinedOptions = combinedOnlyIOSQualityOptions(from: streamingData)
        if let directURL = bestDirectFormatURL(from: streamingData) {
            return manifest(defaultURL: directURL, options: combinedOptions)
        }

        throw NSError(domain: "YouTubeService", code: 13, userInfo: [
            NSLocalizedDescriptionKey: "No direct URLs in iOS response"
        ])
    }

    private func bestDirectFormatURL(from streamingData: PlayerResponse.StreamingData?) -> URL? {
        guard let streamingData else { return nil }

        // Only pick combined (video+audio) formats as a default URL. Adaptive
        // formats are DASH video-only or audio-only; AVPlayer would play them
        // silent, which looks like a 720p cap but is really a "no audio" bug.
        let combinedFormats = (streamingData.formats ?? [])
            .filter {
                guard let url = $0.url, !url.isEmpty else { return false }
                return $0.mimeType.contains("video") && ($0.mimeType.contains("mp4a") || $0.mimeType.contains("opus"))
            }

        if let bestCombined = combinedFormats.max(by: { ($0.height ?? 0) < ($1.height ?? 0) }),
           let urlString = bestCombined.url,
           let url = URL(string: urlString) {
            return url
        }

        return nil
    }

    // The quality picker has two modes:
    //
    // 1. HLS mode (default): all quality rows share the HLS manifest URL.
    //    Selecting a row applies `preferredMaximumResolution` on the current
    //    AVPlayerItem so HLS's built-in ABR picks the matching bitrate — no
    //    URL swap, no black screen. Heights come from the union of combined
    //    + adaptive formats, so the picker reflects what YouTube actually
    //    offers for this video (144p through 4K/8K).
    //
    // 2. Combined-only mode: used when no HLS manifest is available (rare).
    //    Each row has its own direct URL. Caps at 720p because combined
    //    formats only go up to 720p — AVPlayer can't demux single DASH
    //    adaptive URLs without external muxing.

    /// Parse `#EXT-X-STREAM-INF ... RESOLUTION=WIDTHxHEIGHT` lines from an HLS
    /// master manifest and return the unique heights.
    ///
    /// This is the authoritative source for what resolutions YouTube is
    /// actually serving for a given video. The Innertube `formats` and
    /// `adaptiveFormats` arrays are advisory — the iOS-client response in
    /// particular frequently returns them empty or without `height` fields
    /// even when the HLS manifest exposes 144p..4320p variants. Falling back
    /// to manifest parsing keeps the quality picker honest regardless of
    /// what's in the JSON.
    private nonisolated static func fetchHLSVariantHeights(masterURL: URL) async -> Set<Int> {
        var request = URLRequest(url: masterURL)
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }

            var heights = Set<Int>()
            for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("#EXT-X-STREAM-INF") else { continue }
                guard let resRange = line.range(of: "RESOLUTION=") else { continue }
                let after = line[resRange.upperBound...]
                // RESOLUTION attribute is unquoted: ends at the next comma or EOL.
                let endIndex = after.firstIndex(where: { $0 == "," }) ?? after.endIndex
                let resValue = after[after.startIndex..<endIndex]
                let dims = resValue.split(separator: "x")
                guard dims.count == 2, let h = Int(dims[1]), h > 0 else { continue }
                heights.insert(h)
            }
            return heights
        } catch {
            return []
        }
    }

    private func hlsHeightOptions(availableHeights: Set<Int>, hlsURL: URL) -> [StreamQualityOption] {
        availableHeights
            .filter { $0 > 0 }
            .sorted(by: >)
            .map { height in
                StreamQualityOption(
                    id: "hls-\(height)",
                    label: "\(height)p",
                    url: hlsURL,
                    height: height
                )
            }
    }

    private func availableHeights(combined: [[String: Any]]?, adaptive: [[String: Any]]?) -> Set<Int> {
        var heights = Set<Int>()
        for list in [combined, adaptive] {
            guard let list else { continue }
            for format in list {
                let mimeType = (format["mimeType"] as? String ?? "").lowercased()
                guard mimeType.contains("video") else { continue }
                if let height = format["height"] as? Int, height > 0 {
                    heights.insert(height)
                }
            }
        }
        return heights
    }

    private func availableHeights(formats: [PlayerResponse.StreamingData.Format]) -> Set<Int> {
        var heights = Set<Int>()
        for format in formats {
            let mimeType = format.mimeType.lowercased()
            guard mimeType.contains("video") else { continue }
            if let height = format.height, height > 0 {
                heights.insert(height)
            }
        }
        return heights
    }

    private func combinedOnlyQualityOptions(from formats: [[String: Any]]?) -> [StreamQualityOption] {
        guard let formats else { return [] }

        return formats.compactMap { format in
            guard let urlString = format["url"] as? String,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                return nil
            }

            let mimeType = (format["mimeType"] as? String ?? "").lowercased()
            guard mimeType.contains("video"),
                  mimeType.contains("mp4a") || mimeType.contains("opus") else {
                return nil
            }

            let height = format["height"] as? Int ?? 0
            let qualityLabel = streamQualityLabel(raw: format["qualityLabel"] as? String, height: height)
            let idPart = (format["itag"] as? Int).map(String.init) ?? qualityLabel
            return StreamQualityOption(id: "android-\(idPart)", label: qualityLabel, url: url, height: height)
        }
    }

    private func combinedOnlyIOSQualityOptions(from streamingData: PlayerResponse.StreamingData?) -> [StreamQualityOption] {
        guard let streamingData else { return [] }

        return (streamingData.formats ?? []).compactMap { format in
            guard let urlString = format.url,
                  !urlString.isEmpty,
                  let url = URL(string: urlString) else {
                return nil
            }

            let mimeType = format.mimeType.lowercased()
            guard mimeType.contains("video"),
                  mimeType.contains("mp4a") || mimeType.contains("opus") else {
                return nil
            }

            let height = format.height ?? 0
            let qualityLabel = streamQualityLabel(raw: format.qualityLabel, height: height)
            return StreamQualityOption(id: "ios-\(format.itag)", label: qualityLabel, url: url, height: height)
        }
    }

    private func deduplicatedQualityOptions(_ options: [StreamQualityOption]) -> [StreamQualityOption] {
        guard !options.isEmpty else { return [] }

        var byLabel: [String: StreamQualityOption] = [:]
        for option in options {
            if let existing = byLabel[option.label] {
                if option.height > existing.height {
                    byLabel[option.label] = option
                }
            } else {
                byLabel[option.label] = option
            }
        }

        return byLabel.values.sorted { lhs, rhs in
            lhs.height > rhs.height
        }
    }

    private func streamQualityLabel(raw: String?, height: Int) -> String {
        if let raw, !raw.isEmpty {
            return raw
        }

        if height > 0 {
            return "\(height)p"
        }

        return "Auto"
    }

    private func manifest(defaultURL: URL, options: [StreamQualityOption]) -> StreamManifest {
        // HLS-mode options share `defaultURL` (one manifest, many resolution
        // rungs the player picks via `preferredMaximumResolution`). The old
        // filter dropped same-URL options and reduced the picker to just
        // "Auto". Dedup by id+label instead so HLS heights survive.
        let autoOption = StreamQualityOption(id: "auto", label: "Auto", url: defaultURL, height: Int.max)
        var resolvedOptions: [StreamQualityOption] = [autoOption]
        var seenIDs: Set<String> = [autoOption.id]
        var seenLabels: Set<String> = [autoOption.label]

        for option in options where !seenIDs.contains(option.id) && !seenLabels.contains(option.label) {
            seenIDs.insert(option.id)
            seenLabels.insert(option.label)
            resolvedOptions.append(option)
        }

        return StreamManifest(defaultURL: defaultURL, qualityOptions: resolvedOptions)
    }

    private func buildDiscoveryFallbackFeed(accessToken: String? = nil) async -> [Video] {
        let queries = homeDiscoveryQueries
        var seenIDs = Set<String>()
        var collected: [Video] = []

        for query in queries {
            guard collected.count < 48 else { break }
            do {
                let results = try await api.search(query: query, accessToken: accessToken)
                for video in results where seenIDs.insert(video.id).inserted {
                    collected.append(video)
                    if collected.count >= 48 { break }
                }
            } catch {
                continue
            }
        }

        return collected
    }

    private func deduplicate(_ videos: [Video], seen: inout Set<String>) -> [Video] {
        var unique: [Video] = []
        for video in videos where seen.insert(video.id).inserted {
            unique.append(video)
        }
        return unique
    }

    private nonisolated static func ytDlpPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    private nonisolated static func extractStreamURLWithYtDlp(videoId: String) async throws -> URL {
        try await Task.detached(priority: .utility) {
            guard let ytDlpPath = ytDlpPath() else {
                throw NSError(domain: "YouTubeService", code: 4, userInfo: [
                    NSLocalizedDescriptionKey: "yt-dlp not found"
                ])
            }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytDlpPath)
            process.arguments = [
                "https://www.youtube.com/watch?v=\(videoId)",
                "--no-playlist",
                "--format", "best[ext=mp4]/best",
                "--get-url"
            ]

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NSError(domain: "YouTubeService", code: 5, userInfo: [
                    NSLocalizedDescriptionKey: "yt-dlp failed to extract stream URL"
                ])
            }

            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8) ?? ""

            guard let firstURLLine = output
                .split(whereSeparator: \.isNewline)
                .map(String.init)
                .first(where: { $0.hasPrefix("http") }),
                  let url = URL(string: firstURLLine) else {
                throw NSError(domain: "YouTubeService", code: 6, userInfo: [
                    NSLocalizedDescriptionKey: "yt-dlp returned no URL"
                ])
            }

            return url
        }.value
    }
    
}
