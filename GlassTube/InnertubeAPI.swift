//
//  InnertubeAPI.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import Foundation
import Combine

/// YouTube's internal Innertube API client
/// This is the undocumented API that YouTube's web and mobile apps use
@MainActor
class InnertubeAPI: ObservableObject {
    
    // MARK: - API Configuration
    
    private let baseURL = "https://www.youtube.com/youtubei/v1"
    private let apiKey = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8" // Web client API key

    private let clientName = "WEB"
    private var clientVersion = "2.20260409.02.00"
    private let iosClientVersion = "20.10.4"

    /// Visitor data token fetched from YouTube for session continuity
    private var visitorData: String?
    
    // MARK: - Published State
    
    @Published var isLoading = false
    @Published var error: APIError?
    
    // MARK: - Errors
    
    enum APIError: Error, LocalizedError {
        case invalidURL
        case networkError(Error)
        case decodingError(Error)
        case invalidResponse
        case serverError(statusCode: Int, message: String?)
        case noData
        
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "Invalid URL"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            case .decodingError(let error): return "Decoding error: \(error.localizedDescription)"
            case .invalidResponse: return "Invalid response from server"
            case .serverError(let statusCode, let message):
                if let message, !message.isEmpty {
                    return "Server error (HTTP \(statusCode)): \(message)"
                }
                return "Server error (HTTP \(statusCode))"
            case .noData: return "No data received"
            }
        }
    }

    private func parseAPIErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? [String: Any] {
            if let message = error["message"] as? String, !message.isEmpty {
                return message
            }

            if let errors = error["errors"] as? [[String: Any]],
               let first = errors.first,
               let reason = first["reason"] as? String,
               !reason.isEmpty {
                return reason
            }

            if let status = error["status"] as? String, !status.isEmpty {
                return status
            }
        }

        return nil
    }
    
    // MARK: - Request Context
    
    private func createContext() -> [String: Any] {
        var client: [String: Any] = [
            "clientName": clientName,
            "clientVersion": clientVersion,
            "hl": "en",
            "gl": "US",
            "platform": "DESKTOP",
            "userAgent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
        ]
        if let visitorData {
            client["visitorData"] = visitorData
        }
        return ["client": client]
    }

    /// Fetch a visitor data token from YouTube's main page
    func fetchVisitorData() async {
        guard visitorData == nil else { return }
        do {
            guard let url = URL(string: "https://www.youtube.com/") else { return }
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            let (data, _) = try await URLSession.shared.data(for: request)
            if let html = String(data: data, encoding: .utf8) {
                if let range = html.range(of: "\"visitorData\":\"") {
                    let start = range.upperBound
                    if let end = html[start...].range(of: "\"")?.lowerBound {
                        visitorData = String(html[start..<end])
                    }
                }

                if let range = html.range(of: "\"INNERTUBE_CLIENT_VERSION\":\"") {
                    let start = range.upperBound
                    if let end = html[start...].range(of: "\"")?.lowerBound {
                        clientVersion = String(html[start..<end])
                    }
                }
            }
        } catch {
            // Non-fatal; continue without visitor data
        }
    }
    
    // MARK: - Generic Request
    
    private func makeRequest<T: Decodable>(
        endpoint: String,
        body: [String: Any]
    ) async throws -> T {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?key=\(apiKey)") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody = body
        requestBody["context"] = createContext()
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw APIError.serverError(
                    statusCode: statusCode,
                    message: parseAPIErrorMessage(from: data)
                )
            }
            
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            
            return try decoder.decode(T.self, from: data)
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Raw JSON Request (for complex responses)

    private func makeRawRequest(
        endpoint: String,
        body: [String: Any],
        accessToken: String? = nil
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?key=\(apiKey)&prettyPrint=false") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("1", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let accessToken, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        var requestBody = body
        requestBody["context"] = createContext()

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.serverError(
                statusCode: statusCode,
                message: parseAPIErrorMessage(from: data)
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.noData
        }

        return json
    }

    // MARK: - Browse (Home Feed)

    func getHomeFeed(accessToken: String? = nil) async throws -> [Video] {
        // Ensure we have visitor data for better results
        await fetchVisitorData()

        let body: [String: Any] = [
            "browseId": "FEwhat_to_watch"
        ]

        let json = try await makeRawRequest(endpoint: "browse", body: body, accessToken: accessToken)
        let videos = InnertubeParser.parseHomeFeed(json)

        // Trending browse IDs intermittently return INVALID_ARGUMENT for WEB clients.
        // Keep this fallback best-effort so Home can continue to downstream discovery search.
        if videos.isEmpty {
            let trendingBody: [String: Any] = ["browseId": "FEtrending"]
            if let trendingJson = try? await makeRawRequest(endpoint: "browse", body: trendingBody, accessToken: accessToken) {
                let trendingVideos = InnertubeParser.parseTrendingFeed(trendingJson)
                if !trendingVideos.isEmpty { return trendingVideos }
            }
        }

        return videos
    }

    // MARK: - Search

    func search(query: String, accessToken: String? = nil) async throws -> [Video] {
        let body: [String: Any] = [
            "query": query
        ]

        let json = try await makeRawRequest(endpoint: "search", body: body, accessToken: accessToken)
        return InnertubeParser.parseSearchResults(json)
    }
    
    // MARK: - Subscription Feed (authenticated)

    func getSubscriptionFeed(accessToken: String) async throws -> [Video] {
        let body: [String: Any] = ["browseId": "FEsubscriptions"]
        let json = try await makeRawRequest(endpoint: "browse", body: body, accessToken: accessToken)

        return InnertubeParser.parseHomeFeed(json)
    }

    func getWatchLaterFeed(accessToken: String) async throws -> [Video] {
        let body: [String: Any] = ["browseId": "VLWL"]
        let json = try await makeRawRequest(endpoint: "browse", body: body, accessToken: accessToken)
        return InnertubeParser.parseHomeFeed(json)
    }

    func getLikedVideosFeed(accessToken: String) async throws -> [Video] {
        let body: [String: Any] = ["browseId": "VLLL"]
        let json = try await makeRawRequest(endpoint: "browse", body: body, accessToken: accessToken)
        return InnertubeParser.parseHomeFeed(json)
    }

    func getHistoryFeed(accessToken: String) async throws -> [Video] {
        let body: [String: Any] = ["browseId": "FEhistory"]
        let json = try await makeRawRequest(endpoint: "browse", body: body, accessToken: accessToken)
        return InnertubeParser.parseHomeFeed(json)
    }

    /// Fetches the top-level comments for a video via Innertube. This consumes
    /// no YouTube Data API quota, unlike `commentThreads.list`. Works without
    /// authentication for public comments. Returns empty array if comments are
    /// disabled or the response layout is unexpected.
    func getComments(videoId: String, accessToken: String? = nil) async throws -> [Comment] {
        // Step 1: hit `next` with the videoId to discover the comments
        // continuation token (YouTube lazy-loads comments behind one).
        let nextBody: [String: Any] = ["videoId": videoId]
        let nextJson = try await makeRawRequest(
            endpoint: "next",
            body: nextBody,
            accessToken: accessToken
        )

        guard let continuationToken = InnertubeParser.findCommentsContinuationToken(in: nextJson) else {
            return []
        }

        // Step 2: resolve the continuation to get the actual comment threads.
        let continuationJson = try await makeRawRequest(
            endpoint: "next",
            body: ["continuation": continuationToken],
            accessToken: accessToken
        )

        return InnertubeParser.parseComments(continuationJson, videoId: videoId)
    }

    /// Adds a video to the signed-in user's Watch Later playlist via the
    /// Innertube `browse/edit_playlist` endpoint. The Data API has blocked
    /// playlistItems.insert against `WL` since 2016, so this is the only path
    /// that still works. Returns when the server accepts the action.
    ///
    /// The WEB client rejects Bearer-authed edit_playlist calls because the
    /// YouTube web front-end authenticates via SAPISIDHASH cookies. We retry
    /// across the ANDROID and TVHTML5 client contexts, which do accept OAuth
    /// Bearer tokens for playlist edits (Google issues our OAuth creds under
    /// the "TVs and Limited Input devices" client type, so TVHTML5 is the
    /// matching Innertube surface).
    func addToWatchLater(videoId: String, accessToken: String) async throws {
        try await editPlaylist(
            playlistId: "WL",
            action: "ACTION_ADD_VIDEO",
            addedVideoId: videoId,
            accessToken: accessToken
        )
    }

    /// Adds a video to an arbitrary playlist via Innertube. Used as a fallback
    /// for `playlistItems.insert` when the Data API route fails (which happens
    /// for some force-ssl scoped writes under our device-flow OAuth).
    func addVideoToPlaylist(
        videoId: String,
        playlistId: String,
        accessToken: String
    ) async throws {
        try await editPlaylist(
            playlistId: playlistId,
            action: "ACTION_ADD_VIDEO",
            addedVideoId: videoId,
            accessToken: accessToken
        )
    }

    /// Creates a new playlist via Innertube `playlist/create` and returns the
    /// resulting playlist id. Used as a fallback when Data API `playlists.insert`
    /// is refused for our OAuth scope set.
    func createPlaylist(
        title: String,
        privacyStatus: String,
        accessToken: String
    ) async throws -> String {
        let normalizedPrivacy: String = {
            switch privacyStatus.uppercased() {
            case "PUBLIC": return "PUBLIC"
            case "UNLISTED": return "UNLISTED"
            default: return "PRIVATE"
            }
        }()

        let body: [String: Any] = [
            "title": title,
            "privacyStatus": normalizedPrivacy
        ]

        // Try the OAuth-friendly clients in order.
        let contexts = innertubeEditContexts()
        var lastError: Error?
        for context in contexts {
            do {
                let json = try await makeEditRequest(
                    endpoint: "playlist/create",
                    body: body,
                    clientOverride: context,
                    accessToken: accessToken
                )
                if let id = json["playlistId"] as? String, !id.isEmpty {
                    return id
                }
                if let id = (json["playlistEditResults"] as? [[String: Any]])?
                    .first?["playlistId"] as? String, !id.isEmpty {
                    return id
                }
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? APIError.serverError(
            statusCode: 400,
            message: "Innertube playlist/create returned no id"
        )
    }

    /// Core edit_playlist helper: retries the call across compatible Innertube
    /// client contexts until one accepts the Bearer token.
    private func editPlaylist(
        playlistId: String,
        action: String,
        addedVideoId: String?,
        accessToken: String
    ) async throws {
        var actionDict: [String: Any] = ["action": action]
        if let addedVideoId { actionDict["addedVideoId"] = addedVideoId }
        let body: [String: Any] = [
            "playlistId": playlistId,
            "actions": [actionDict]
        ]

        let contexts = innertubeEditContexts()
        var lastError: Error?
        for context in contexts {
            do {
                let json = try await makeEditRequest(
                    endpoint: "browse/edit_playlist",
                    body: body,
                    clientOverride: context,
                    accessToken: accessToken
                )
                if let status = json["status"] as? String {
                    if status == "STATUS_SUCCEEDED" { return }
                    // Non-success but HTTP 200 — remember and try next client.
                    lastError = APIError.serverError(
                        statusCode: 200,
                        message: "edit_playlist returned \(status)"
                    )
                    continue
                }
                return
            } catch {
                lastError = error
                continue
            }
        }
        throw lastError ?? APIError.serverError(
            statusCode: 400,
            message: "edit_playlist failed across all clients"
        )
    }

    /// Ordered list of client contexts we try for edit_playlist / playlist/create
    /// when authenticating with an OAuth Bearer token.
    private func innertubeEditContexts() -> [[String: Any]] {
        return [
            // ANDROID — long-standing Innertube surface, accepts Bearer tokens
            // for playlist writes in the wild.
            [
                "clientName": "ANDROID",
                "clientVersion": "19.09.37",
                "androidSdkVersion": 30,
                "hl": "en",
                "gl": "US"
            ],
            // TVHTML5 — matches our OAuth client type (TVs and Limited Input
            // devices). Useful when Google routes our token through the TV path.
            [
                "clientName": "TVHTML5",
                "clientVersion": "7.20240724.13.00",
                "platform": "TV",
                "hl": "en",
                "gl": "US"
            ],
            // WEB — kept as a last resort; usually rejects Bearer-authed edits.
            [
                "clientName": clientName,
                "clientVersion": clientVersion,
                "platform": "DESKTOP",
                "hl": "en",
                "gl": "US"
            ]
        ]
    }

    /// Build a raw Innertube request with a client-context override so we can
    /// reissue the same write against multiple clients until one accepts the
    /// OAuth Bearer token.
    private func makeEditRequest(
        endpoint: String,
        body: [String: Any],
        clientOverride: [String: Any],
        accessToken: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/\(endpoint)?key=\(apiKey)&prettyPrint=false") else {
            throw APIError.invalidURL
        }

        let clientName = clientOverride["clientName"] as? String ?? self.clientName
        let clientVersion = clientOverride["clientVersion"] as? String ?? self.clientVersion
        let headerClientId: String = {
            switch clientName {
            case "ANDROID": return "3"
            case "IOS": return "5"
            case "TVHTML5": return "7"
            case "WEB_REMIX": return "67"
            default: return "1"
            }
        }()

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(headerClientId, forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(clientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        switch clientName {
        case "ANDROID":
            request.setValue(
                "com.google.android.youtube/\(clientVersion) (Linux; U; Android 11) gzip",
                forHTTPHeaderField: "User-Agent"
            )
        case "IOS":
            request.setValue(
                "com.google.ios.youtube/\(clientVersion) (iPhone14,3; U; CPU iOS 15_6 like Mac OS X)",
                forHTTPHeaderField: "User-Agent"
            )
        case "TVHTML5":
            request.setValue(
                "Mozilla/5.0 (SMART-TV; LINUX; Tizen 6.0) AppleWebKit/537.36 (KHTML, like Gecko) 85.0.4183.93/6.0 TV Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
        default:
            request.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
                forHTTPHeaderField: "User-Agent"
            )
        }

        var clientDict = clientOverride
        if let visitorData { clientDict["visitorData"] = visitorData }

        var requestBody = body
        requestBody["context"] = ["client": clientDict]

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.serverError(
                statusCode: statusCode,
                message: parseAPIErrorMessage(from: data)
            )
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.noData
        }
        return json
    }

    // MARK: - Video Details

    func getVideoDetails(videoId: String) async throws -> PlayerResponse {
        let body: [String: Any] = [
            "videoId": videoId
        ]

        return try await makeRequest(endpoint: "player", body: body)
    }

    /// Fetch player response using the ANDROID client, which returns direct stream URLs
    /// (no signature cipher) for most videos. Falls back to WEB client if needed.
    func getAndroidPlayerResponse(videoId: String) async throws -> [String: Any] {
        guard let url = URL(string: "\(baseURL)/player?key=AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w&prettyPrint=false") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.google.android.youtube/19.09.37 (Linux; U; Android 11) gzip", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "videoId": videoId,
            "context": [
                "client": [
                    "clientName": "ANDROID",
                    "clientVersion": "19.09.37",
                    "androidSdkVersion": 30,
                    "hl": "en",
                    "gl": "US"
                ]
            ],
            "playbackContext": [
                "contentPlaybackContext": [
                    "html5Preference": "HTML5_PREF_WANTS"
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.invalidResponse
        }

        return json
    }

    /// Fetch chapters for a video (from player response JSON)
    func getChapters(videoId: String) async throws -> [Chapter] {
        let body: [String: Any] = [
            "videoId": videoId
        ]
        let json = try await makeRawRequest(endpoint: "next", body: body)
        return InnertubeParser.parseChapters(json)
    }

    /// iOS client context returns HLS manifests and stream URLs more reliably than WEB.
    func getPlaybackDetails(videoId: String) async throws -> PlayerResponse {
        guard let url = URL(string: "\(baseURL)/player?key=\(apiKey)&prettyPrint=false") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://www.youtube.com", forHTTPHeaderField: "Origin")
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue("5", forHTTPHeaderField: "X-YouTube-Client-Name")
        request.setValue(iosClientVersion, forHTTPHeaderField: "X-YouTube-Client-Version")
        request.setValue("com.google.ios.youtube/\(iosClientVersion) (iPhone16,2; U; CPU iOS 18_2_1 like Mac OS X)", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "videoId": videoId,
            "contentCheckOk": true,
            "racyCheckOk": true,
            "context": [
                "client": [
                    "clientName": "IOS",
                    "clientVersion": iosClientVersion,
                    "deviceModel": "iPhone16,2",
                    "osName": "iPhone",
                    "osVersion": "18.2.1",
                    "hl": "en",
                    "gl": "US"
                ]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PlayerResponse.self, from: data)
    }
    
    // MARK: - Next (Recommended/Related Videos)

    func getRelatedVideos(videoId: String) async throws -> [Video] {
        let body: [String: Any] = [
            "videoId": videoId
        ]

        let json = try await makeRawRequest(endpoint: "next", body: body)
        return InnertubeParser.parseRelatedVideos(json)
    }

    // MARK: - Channel

    func getChannel(channelId: String, accessToken: String? = nil) async throws -> Channel {
        guard !channelId.isEmpty else {
            throw APIError.noData
        }

        let json = try await makeRawRequest(
            endpoint: "browse",
            body: ["browseId": channelId],
            accessToken: accessToken
        )

        guard let channel = InnertubeParser.parseChannelMetadata(json, fallbackChannelID: channelId) else {
            throw APIError.noData
        }

        return channel
    }

    func getChannelVideos(
        channelId: String,
        accessToken: String? = nil,
        maxResults: Int = 50
    ) async throws -> [Video] {
        guard !channelId.isEmpty else { return [] }

        var merged: [Video] = []

        let baseJSON = try await makeRawRequest(
            endpoint: "browse",
            body: ["browseId": channelId],
            accessToken: accessToken
        )
        merged.append(contentsOf: InnertubeParser.parseChannelVideos(baseJSON))

        // Try known params variants for the channel videos tab.
        let videoTabParams = ["EgZ2aWRlb3M%3D", "EgZ2aWRlb3M="]
        for params in videoTabParams where merged.count < maxResults {
            let body: [String: Any] = [
                "browseId": channelId,
                "params": params
            ]
            if let tabJSON = try? await makeRawRequest(endpoint: "browse", body: body, accessToken: accessToken) {
                merged.append(contentsOf: InnertubeParser.parseChannelVideos(tabJSON))
            }
        }

        return Array(deduplicateVideos(merged).prefix(maxResults))
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

// MARK: - Innertube JSON Parser

enum InnertubeParser {

    /// Parse home feed from browse response
    static func parseHomeFeed(_ json: [String: Any]) -> [Video] {
        var videos: [Video] = []

        guard let contents = json["contents"] as? [String: Any] else {
            return parseAnyVideoRenderers(in: json)
        }

        // Path A: twoColumnBrowseResultsRenderer (standard web)
        if let twoCol = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = twoCol["tabs"] as? [[String: Any]] {
            for tab in tabs {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let content = tabRenderer["content"] as? [String: Any] {
                    // richGridRenderer path
                    if let richGrid = content["richGridRenderer"] as? [String: Any],
                       let gridContents = richGrid["contents"] as? [[String: Any]] {
                        for item in gridContents {
                            if let richItem = item["richItemRenderer"] as? [String: Any],
                               let itemContent = richItem["content"] as? [String: Any],
                               let videoRenderer = itemContent["videoRenderer"] as? [String: Any],
                               let video = parseVideoRenderer(videoRenderer) {
                                videos.append(video)
                            }
                        }
                    }
                    // sectionListRenderer path (alternative)
                    if videos.isEmpty, let sectionList = content["sectionListRenderer"] as? [String: Any],
                       let sections = sectionList["contents"] as? [[String: Any]] {
                        videos.append(contentsOf: parseShelfSections(sections))
                    }
                }
            }
        }

        // Path B: singleColumnBrowseResultsRenderer (mobile-style)
        if videos.isEmpty,
           let singleCol = contents["singleColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = singleCol["tabs"] as? [[String: Any]] {
            for tab in tabs {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let content = tabRenderer["content"] as? [String: Any],
                   let sectionList = content["sectionListRenderer"] as? [String: Any],
                   let sections = sectionList["contents"] as? [[String: Any]] {
                    videos.append(contentsOf: parseShelfSections(sections))
                }
            }
        }

        mergeUnique(into: &videos, from: parseAnyVideoRenderers(in: json))

        return videos
    }

    /// Parse trending/explore feed
    static func parseTrendingFeed(_ json: [String: Any]) -> [Video] {
        var videos: [Video] = []

        guard let contents = json["contents"] as? [String: Any] else {
            return parseAnyVideoRenderers(in: json)
        }

        // Trending uses twoColumnBrowseResultsRenderer → sectionListRenderer → shelfRenderer/itemSectionRenderer
        if let twoCol = contents["twoColumnBrowseResultsRenderer"] as? [String: Any],
           let tabs = twoCol["tabs"] as? [[String: Any]] {
            for tab in tabs {
                if let tabRenderer = tab["tabRenderer"] as? [String: Any],
                   let content = tabRenderer["content"] as? [String: Any],
                   let sectionList = content["sectionListRenderer"] as? [String: Any],
                   let sections = sectionList["contents"] as? [[String: Any]] {
                    videos.append(contentsOf: parseShelfSections(sections))
                }
            }
        }

        mergeUnique(into: &videos, from: parseAnyVideoRenderers(in: json))

        return videos
    }

    /// Parse shelf/section items (used by trending and alternative home feed layouts)
    private static func parseShelfSections(_ sections: [[String: Any]]) -> [Video] {
        var videos: [Video] = []

        for section in sections {
            // itemSectionRenderer with videoRenderer items
            if let itemSection = section["itemSectionRenderer"] as? [String: Any],
               let sectionContents = itemSection["contents"] as? [[String: Any]] {
                for item in sectionContents {
                    if let videoRenderer = item["videoRenderer"] as? [String: Any],
                       let video = parseVideoRenderer(videoRenderer) {
                        videos.append(video)
                    }
                    // shelfRenderer containing expandedShelfContentsRenderer or horizontalListRenderer
                    if let shelf = item["shelfRenderer"] as? [String: Any],
                       let shelfContent = shelf["content"] as? [String: Any] {
                        if let expanded = shelfContent["expandedShelfContentsRenderer"] as? [String: Any],
                           let items = expanded["items"] as? [[String: Any]] {
                            for shelfItem in items {
                                if let vr = shelfItem["videoRenderer"] as? [String: Any],
                                   let video = parseVideoRenderer(vr) {
                                    videos.append(video)
                                }
                            }
                        }
                        if let horizontal = shelfContent["horizontalListRenderer"] as? [String: Any],
                           let items = horizontal["items"] as? [[String: Any]] {
                            for shelfItem in items {
                                if let vr = shelfItem["gridVideoRenderer"] as? [String: Any],
                                   let video = parseGridVideoRenderer(vr) {
                                    videos.append(video)
                                }
                            }
                        }
                    }
                }
            }
        }

        return videos
    }

    /// Parse gridVideoRenderer (used in shelves/grids)
    static func parseGridVideoRenderer(_ renderer: [String: Any]) -> Video? {
        guard let videoId = renderer["videoId"] as? String else { return nil }

        let title = extractText(renderer["title"]) ?? "Untitled"
        let channelName = extractText(renderer["shortBylineText"]) ?? "Unknown"

        let thumbnailURL = buildThumbnailURL(from: renderer["thumbnail"], videoId: videoId)

        let duration: TimeInterval
        if let overlay = (renderer["thumbnailOverlays"] as? [[String: Any]])?.first,
           let statusRenderer = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any],
           let text = extractText(statusRenderer["text"]) {
            duration = parseDuration(text)
        } else {
            duration = 0
        }

        let viewCount: Int
        if let viewCountText = renderer["viewCountText"] as? [String: Any],
           let simpleText = viewCountText["simpleText"] as? String {
            viewCount = parseViewCount(simpleText)
        } else {
            viewCount = 0
        }

        let publishedText = extractText(renderer["publishedTimeText"]) ?? ""

        return Video(
            id: videoId,
            title: title,
            description: "",
            channelId: "",
            channelName: channelName,
            channelAvatar: nil,
            thumbnailURL: thumbnailURL,
            duration: duration,
            viewCount: viewCount,
            likeCount: nil,
            publishedAt: parseRelativeDate(publishedText),
            isLive: false,
            isUpcoming: false
        )
    }

    /// Parse search results
    static func parseSearchResults(_ json: [String: Any]) -> [Video] {
        var videos: [Video] = []

        // Path: contents.twoColumnSearchResultsRenderer.primaryContents.sectionListRenderer.contents[0].itemSectionRenderer.contents
        if let contents = json["contents"] as? [String: Any],
           let twoCol = contents["twoColumnSearchResultsRenderer"] as? [String: Any],
           let primary = twoCol["primaryContents"] as? [String: Any],
           let sectionList = primary["sectionListRenderer"] as? [String: Any],
           let sections = sectionList["contents"] as? [[String: Any]] {
            for section in sections {
                if let itemSection = section["itemSectionRenderer"] as? [String: Any],
                   let sectionContents = itemSection["contents"] as? [[String: Any]] {
                    for item in sectionContents {
                        if let videoRenderer = item["videoRenderer"] as? [String: Any],
                           let video = parseVideoRenderer(videoRenderer) {
                            videos.append(video)
                        }

                        if let reelRenderer = item["reelItemRenderer"] as? [String: Any],
                           let short = parseReelItemRenderer(reelRenderer) {
                            videos.append(short)
                        }

                        if let reelShelf = item["reelShelfRenderer"] as? [String: Any],
                           let items = reelShelf["items"] as? [[String: Any]] {
                            for shelfItem in items {
                                if let reelRenderer = shelfItem["reelItemRenderer"] as? [String: Any],
                                   let short = parseReelItemRenderer(reelRenderer) {
                                    videos.append(short)
                                }
                            }
                        }
                    }
                }
            }
        }

        mergeUnique(into: &videos, from: parseAnyVideoRenderers(in: json))

        return videos
    }

    /// Parse related/recommended videos from next response
    static func parseRelatedVideos(_ json: [String: Any]) -> [Video] {
        var videos: [Video] = []

        // Path: contents.twoColumnWatchNextResults.secondaryResults.secondaryResults.results
        guard let contents = json["contents"] as? [String: Any],
              let twoCol = contents["twoColumnWatchNextResults"] as? [String: Any],
              let secondary = twoCol["secondaryResults"] as? [String: Any],
              let secondaryResults = secondary["secondaryResults"] as? [String: Any],
              let results = secondaryResults["results"] as? [[String: Any]]
        else { return videos }

        for item in results {
            if let renderer = item["compactVideoRenderer"] as? [String: Any],
               let video = parseCompactVideoRenderer(renderer) {
                videos.append(video)
            }
        }

        return videos
    }

    static func parseChannelVideos(_ json: [String: Any]) -> [Video] {
        parseAnyVideoRenderers(in: json)
    }

    static func parseChannelMetadata(_ json: [String: Any], fallbackChannelID: String) -> Channel? {
        let metadataRenderer = ((json["metadata"] as? [String: Any])?["channelMetadataRenderer"] as? [String: Any])
        let headerRenderer = ((json["header"] as? [String: Any])?["c4TabbedHeaderRenderer"] as? [String: Any])

        let title = metadataRenderer?["title"] as? String
            ?? extractText(headerRenderer?["title"])
            ?? "Channel"

        let description = metadataRenderer?["description"] as? String ?? ""
        let externalID = metadataRenderer?["externalId"] as? String ?? fallbackChannelID

        let vanityURL = metadataRenderer?["vanityChannelUrl"] as? String
        let handle = extractHandle(from: vanityURL) ?? ""

        let resolvedAvatar = extractThumbnailURL(from: metadataRenderer?["avatar"] ?? headerRenderer?["avatar"])
        let resolvedBanner = extractThumbnailURL(from: headerRenderer?["banner"])

        let subscriberText = extractText(headerRenderer?["subscriberCountText"])
        let videosText = extractText(headerRenderer?["videosCountText"])

        let subscriberCount: Int?
        if let subscriberText {
            subscriberCount = parseViewCount(subscriberText)
        } else {
            subscriberCount = nil
        }

        let videoCount: Int?
        if let videosText {
            videoCount = parseViewCount(videosText)
        } else {
            videoCount = nil
        }

        let isVerified: Bool = {
            guard let badges = headerRenderer?["badges"] as? [[String: Any]] else { return false }
            return badges.contains { badge in
                guard let renderer = badge["metadataBadgeRenderer"] as? [String: Any],
                      let style = renderer["style"] as? String else {
                    return false
                }
                return style.contains("VERIFIED")
            }
        }()

        return Channel(
            id: externalID,
            name: title,
            handle: handle,
            avatarURL: resolvedAvatar,
            bannerURL: resolvedBanner,
            subscriberCount: subscriberCount,
            videoCount: videoCount,
            description: description,
            isVerified: isVerified
        )
    }

    /// Parse compactVideoRenderer (used in related/recommended)
    static func parseCompactVideoRenderer(_ renderer: [String: Any]) -> Video? {
        guard let videoId = renderer["videoId"] as? String else { return nil }

        let title = extractText(renderer["title"]) ?? "Untitled"
        let channelName = extractText(renderer["longBylineText"] ?? renderer["shortBylineText"]) ?? "Unknown"

        let thumbnailURL = buildThumbnailURL(from: renderer["thumbnail"], videoId: videoId)

        let duration: TimeInterval
        if let lengthText = renderer["lengthText"] as? [String: Any],
           let simpleText = lengthText["simpleText"] as? String {
            duration = parseDuration(simpleText)
        } else {
            duration = 0
        }

        let viewCount: Int
        if let viewCountText = renderer["viewCountText"] as? [String: Any],
           let simpleText = viewCountText["simpleText"] as? String {
            viewCount = parseViewCount(simpleText)
        } else {
            viewCount = 0
        }

        let publishedText = extractText(renderer["publishedTimeText"]) ?? ""

        // Channel ID
        let channelId: String
        if let byline = renderer["longBylineText"] as? [String: Any],
           let runs = byline["runs"] as? [[String: Any]],
           let first = runs.first,
           let navEndpoint = first["navigationEndpoint"] as? [String: Any],
           let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
           let id = browseEndpoint["browseId"] as? String {
            channelId = id
        } else {
            channelId = ""
        }

        // Channel avatar
        let channelAvatar: String?
        if let channelThumbnail = renderer["channelThumbnail"] as? [String: Any],
           let thumbs = channelThumbnail["thumbnails"] as? [[String: Any]],
           let best = thumbs.last,
           let url = best["url"] as? String {
            channelAvatar = url.hasPrefix("//") ? "https:\(url)" : url
        } else {
            channelAvatar = nil
        }

        return Video(
            id: videoId,
            title: title,
            description: "",
            channelId: channelId,
            channelName: channelName,
            channelAvatar: channelAvatar,
            thumbnailURL: thumbnailURL,
            duration: duration,
            viewCount: viewCount,
            likeCount: nil,
            publishedAt: parseRelativeDate(publishedText),
            isLive: false,
            isUpcoming: false
        )
    }

    /// Parse a single videoRenderer into a Video model
    static func parseVideoRenderer(_ renderer: [String: Any]) -> Video? {
        guard let videoId = renderer["videoId"] as? String else { return nil }

        let title = extractText(renderer["title"])
        let channelName = extractText(renderer["ownerText"] ?? renderer["longBylineText"] ?? renderer["shortBylineText"])
        let description = extractText(renderer["detailedMetadataSnippets"] ?? renderer["descriptionSnippet"]) ?? ""

        // Thumbnail
        let thumbnailURL = buildThumbnailURL(from: renderer["thumbnail"], videoId: videoId)

        // Channel ID
        let channelId: String
        if let ownerText = renderer["ownerText"] as? [String: Any],
           let runs = ownerText["runs"] as? [[String: Any]],
           let first = runs.first,
           let navEndpoint = first["navigationEndpoint"] as? [String: Any],
           let browseEndpoint = navEndpoint["browseEndpoint"] as? [String: Any],
           let id = browseEndpoint["browseId"] as? String {
            channelId = id
        } else {
            channelId = ""
        }

        // Duration
        let duration: TimeInterval
        if let lengthText = renderer["lengthText"] as? [String: Any],
           let simpleText = lengthText["simpleText"] as? String {
            duration = parseDuration(simpleText)
        } else {
            duration = 0
        }

        // View count
        let viewCount: Int
        if let viewCountText = renderer["viewCountText"] as? [String: Any],
           let simpleText = viewCountText["simpleText"] as? String {
            viewCount = parseViewCount(simpleText)
        } else {
            viewCount = 0
        }

        // Published time
        let publishedText = extractText(renderer["publishedTimeText"]) ?? ""

        // Live badge
        let isLive: Bool
        if let badges = renderer["badges"] as? [[String: Any]] {
            isLive = badges.contains { badge in
                if let meta = badge["metadataBadgeRenderer"] as? [String: Any],
                   let style = meta["style"] as? String {
                    return style.contains("LIVE")
                }
                return false
            }
        } else if let overlays = renderer["thumbnailOverlays"] as? [[String: Any]] {
            isLive = overlays.contains { overlay in
                if let statusRenderer = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any],
                   let style = statusRenderer["style"] as? String {
                    return style == "LIVE"
                }
                return false
            }
        } else {
            isLive = false
        }

        // Channel avatar — try channelThumbnailSupportedRenderers first, then channelThumbnail directly
        let channelAvatar: String?
        if let channelThumbnail = renderer["channelThumbnailSupportedRenderers"] as? [String: Any],
           let channelThumbnailWithLink = channelThumbnail["channelThumbnailWithLinkRenderer"] as? [String: Any],
           let thumb = channelThumbnailWithLink["thumbnail"] as? [String: Any],
           let thumbs = thumb["thumbnails"] as? [[String: Any]],
           let first = thumbs.last,
           let url = first["url"] as? String {
            channelAvatar = url.hasPrefix("//") ? "https:\(url)" : url
        } else if let channelThumb = renderer["channelThumbnail"] as? [String: Any],
                  let thumbs = channelThumb["thumbnails"] as? [[String: Any]],
                  let first = thumbs.last,
                  let url = first["url"] as? String {
            channelAvatar = url.hasPrefix("//") ? "https:\(url)" : url
        } else {
            channelAvatar = nil
        }

        return Video(
            id: videoId,
            title: title ?? "Untitled",
            description: description,
            channelId: channelId,
            channelName: channelName ?? "Unknown",
            channelAvatar: channelAvatar,
            thumbnailURL: thumbnailURL,
            duration: duration,
            viewCount: viewCount,
            likeCount: nil,
            publishedAt: parseRelativeDate(publishedText),
            isLive: isLive,
            isUpcoming: false
        )
    }

    /// Parse reelItemRenderer (short-form results often returned in Shorts shelves).
    static func parseReelItemRenderer(_ renderer: [String: Any]) -> Video? {
        guard let videoId = renderer["videoId"] as? String else { return nil }

        let title = extractText(renderer["headline"] ?? renderer["title"]) ?? "Short"
        let channelName = extractText(renderer["shortBylineText"] ?? renderer["ownerText"] ?? renderer["bylineText"]) ?? "YouTube"
        let viewCountText = extractText(renderer["viewCountText"]) ?? ""
        let publishedText = extractText(renderer["publishedTimeText"]) ?? ""
        let thumbnailURL = buildThumbnailURL(from: renderer["thumbnail"], videoId: videoId)

        return Video(
            id: videoId,
            title: title,
            description: "",
            channelId: "",
            channelName: channelName,
            channelAvatar: nil,
            thumbnailURL: thumbnailURL,
            duration: 0,
            viewCount: parseViewCount(viewCountText),
            likeCount: nil,
            publishedAt: parseRelativeDate(publishedText),
            isLive: false,
            isUpcoming: false
        )
    }

    /// Parse playlistVideoRenderer items used by watch-later/history/liked playlist pages.
    static func parsePlaylistVideoRenderer(_ renderer: [String: Any]) -> Video? {
        guard let videoId = renderer["videoId"] as? String else { return nil }

        let title = extractText(renderer["title"]) ?? "Untitled"
        let channelName = extractText(renderer["shortBylineText"] ?? renderer["longBylineText"] ?? renderer["ownerText"]) ?? "Unknown"
        let thumbnailURL = buildThumbnailURL(from: renderer["thumbnail"], videoId: videoId)

        let duration: TimeInterval
        if let lengthText = renderer["lengthText"] as? [String: Any],
           let simpleText = lengthText["simpleText"] as? String {
            duration = parseDuration(simpleText)
        } else if let lengthSeconds = renderer["lengthSeconds"] as? String,
                  let seconds = Double(lengthSeconds) {
            duration = seconds
        } else if let lengthSeconds = renderer["lengthSeconds"] as? Int {
            duration = TimeInterval(lengthSeconds)
        } else {
            duration = 0
        }

        let viewCountText = extractText(renderer["viewCountText"] ?? renderer["shortViewCountText"] ?? renderer["videoInfo"]) ?? ""
        let publishedText = extractText(renderer["publishedTimeText"]) ?? ""

        let isLive: Bool
        if let overlays = renderer["thumbnailOverlays"] as? [[String: Any]] {
            isLive = overlays.contains { overlay in
                if let statusRenderer = overlay["thumbnailOverlayTimeStatusRenderer"] as? [String: Any],
                   let style = statusRenderer["style"] as? String {
                    return style == "LIVE"
                }
                return false
            }
        } else {
            isLive = false
        }

        return Video(
            id: videoId,
            title: title,
            description: "",
            channelId: "",
            channelName: channelName,
            channelAvatar: nil,
            thumbnailURL: thumbnailURL,
            duration: duration,
            viewCount: parseViewCount(viewCountText),
            likeCount: nil,
            publishedAt: parseRelativeDate(publishedText),
            isLive: isLive,
            isUpcoming: false
        )
    }

    private static func mergeUnique(into videos: inout [Video], from candidates: [Video]) {
        var seen = Set(videos.map(\.id))
        for video in candidates where seen.insert(video.id).inserted {
            videos.append(video)
        }
    }

    /// Walk any Innertube JSON layout and collect common video renderer types.
    private static func parseAnyVideoRenderers(in root: Any) -> [Video] {
        var videos: [Video] = []
        var seenIDs = Set<String>()

        func append(_ video: Video?) {
            guard let video, seenIDs.insert(video.id).inserted else { return }
            videos.append(video)
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let renderer = dict["videoRenderer"] as? [String: Any] {
                    append(parseVideoRenderer(renderer))
                }
                if let renderer = dict["compactVideoRenderer"] as? [String: Any] {
                    append(parseCompactVideoRenderer(renderer))
                }
                if let renderer = dict["gridVideoRenderer"] as? [String: Any] {
                    append(parseGridVideoRenderer(renderer))
                }
                if let renderer = dict["playlistVideoRenderer"] as? [String: Any] {
                    append(parsePlaylistVideoRenderer(renderer))
                }
                if let renderer = dict["reelItemRenderer"] as? [String: Any] {
                    append(parseReelItemRenderer(renderer))
                }

                for value in dict.values {
                    walk(value)
                }
                return
            }

            if let array = node as? [Any] {
                for element in array {
                    walk(element)
                }
            }
        }

        walk(root)
        return videos
    }

    // MARK: - Text Extraction

    /// Extracts text from various Innertube text formats (simpleText or runs)
    private static func extractText(_ value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }

        if let simpleText = dict["simpleText"] as? String {
            return simpleText
        }

        if let runs = dict["runs"] as? [[String: Any]] {
            return runs.compactMap { $0["text"] as? String }.joined()
        }

        return nil
    }

    private static func buildThumbnailURL(from value: Any?, videoId: String) -> String {
        if let thumbContainer = value as? [String: Any],
           let thumbs = thumbContainer["thumbnails"] as? [[String: Any]],
           let best = thumbs.last,
           let rawURL = best["url"] as? String {
            let resolvedURL = rawURL.hasPrefix("//") ? "https:\(rawURL)" : rawURL

            // Keep higher-quality variants when possible, but convert WebP paths to JPG equivalents
            // to avoid decoder issues on some macOS setups.
            if resolvedURL.contains("/vi_webp/") || resolvedURL.contains("/an_webp/") {
                return convertWebPThumbnailURL(resolvedURL) ?? resolvedURL
            }

            return resolvedURL
        }

        return "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg"
    }

    private static func convertWebPThumbnailURL(_ urlString: String) -> String? {
        guard var components = URLComponents(string: urlString) else { return nil }

        components.path = components.path
            .replacingOccurrences(of: "/vi_webp/", with: "/vi/")
            .replacingOccurrences(of: "/an_webp/", with: "/vi/")
            .replacingOccurrences(of: ".webp", with: ".jpg")

        return components.string
    }

    private static func extractThumbnailURL(from value: Any?) -> String? {
        guard let thumbContainer = value as? [String: Any],
              let thumbs = thumbContainer["thumbnails"] as? [[String: Any]],
              let best = thumbs.last,
              let rawURL = best["url"] as? String,
              !rawURL.isEmpty else {
            return nil
        }

        let resolvedURL = rawURL.hasPrefix("//") ? "https:\(rawURL)" : rawURL
        if resolvedURL.contains("/vi_webp/") || resolvedURL.contains("/an_webp/") {
            return convertWebPThumbnailURL(resolvedURL) ?? resolvedURL
        }
        return resolvedURL
    }

    private static func extractHandle(from vanityURL: String?) -> String? {
        guard let vanityURL,
              let url = URL(string: vanityURL) else {
            return nil
        }

        let pathComponent = url.pathComponents.last(where: { $0 != "/" })
        guard let pathComponent, !pathComponent.isEmpty else {
            return nil
        }

        if pathComponent.hasPrefix("@") {
            return pathComponent
        }

        return "@\(pathComponent)"
    }

    // MARK: - Chapter Parsing

    /// Parse chapters from the player response JSON
    static func parseChapters(_ json: [String: Any]) -> [Chapter] {
        var chapters: [Chapter] = []

        // Path: playerOverlays.playerOverlayRenderer.decoratedPlayerBarRenderer
        //   .decoratedPlayerBarRenderer.playerBar.multiMarkersPlayerBarRenderer.markersMap
        if let overlays = json["playerOverlays"] as? [String: Any],
           let overlay = overlays["playerOverlayRenderer"] as? [String: Any],
           let decorated = overlay["decoratedPlayerBarRenderer"] as? [String: Any],
           let inner = decorated["decoratedPlayerBarRenderer"] as? [String: Any],
           let playerBar = inner["playerBar"] as? [String: Any],
           let multi = playerBar["multiMarkersPlayerBarRenderer"] as? [String: Any],
           let markersMap = multi["markersMap"] as? [[String: Any]] {
            for marker in markersMap {
                if let markerValue = marker["value"] as? [String: Any],
                   let chaptersList = markerValue["chapters"] as? [[String: Any]] {
                    for chapter in chaptersList {
                        if let chapterRenderer = chapter["chapterRenderer"] as? [String: Any],
                           let title = extractText(chapterRenderer["title"]),
                           let timeMs = chapterRenderer["timeRangeStartMillis"] as? Int {
                            let thumbURL: String?
                            if let thumb = chapterRenderer["thumbnail"] as? [String: Any],
                               let thumbs = thumb["thumbnails"] as? [[String: Any]],
                               let best = thumbs.last,
                               let url = best["url"] as? String {
                                thumbURL = url.hasPrefix("//") ? "https:\(url)" : url
                            } else {
                                thumbURL = nil
                            }
                            chapters.append(Chapter(
                                title: title,
                                startTime: TimeInterval(timeMs) / 1000.0,
                                thumbnailURL: thumbURL
                            ))
                        }
                    }
                }
            }
        }

        // Fallback: parse chapters from description text (timestamps like "0:00 Intro")
        if chapters.isEmpty {
            if let videoDetails = json["videoDetails"] as? [String: Any],
               let description = videoDetails["shortDescription"] as? String {
                chapters = parseChaptersFromDescription(description)
            }
        }

        return chapters.sorted { $0.startTime < $1.startTime }
    }

    /// Parse timestamps from video description text
    /// Matches lines like "0:00 Intro" or "1:23:45 Main Content"
    static func parseChaptersFromDescription(_ description: String) -> [Chapter] {
        var chapters: [Chapter] = []
        let lines = description.components(separatedBy: .newlines)

        // Match timestamps at the start of a line: "0:00", "1:23", "1:23:45"
        let pattern = #"^(\d{1,2}:)?(\d{1,2}):(\d{2})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let range = NSRange(trimmed.startIndex..., in: trimmed)

            if let match = regex.firstMatch(in: trimmed, range: range) {
                var seconds: TimeInterval = 0
                let title: String

                // Extract hours (optional)
                if let hourRange = Range(match.range(at: 1), in: trimmed) {
                    let hourStr = trimmed[hourRange].replacingOccurrences(of: ":", with: "")
                    seconds += TimeInterval(Int(hourStr) ?? 0) * 3600
                }
                // Minutes
                if let minRange = Range(match.range(at: 2), in: trimmed) {
                    seconds += TimeInterval(Int(trimmed[minRange]) ?? 0) * 60
                }
                // Seconds
                if let secRange = Range(match.range(at: 3), in: trimmed) {
                    seconds += TimeInterval(Int(trimmed[secRange]) ?? 0)
                }
                // Title
                if let titleRange = Range(match.range(at: 4), in: trimmed) {
                    title = String(trimmed[titleRange]).trimmingCharacters(in: .whitespaces)
                } else {
                    continue
                }

                chapters.append(Chapter(title: title, startTime: seconds))
            }
        }

        // Only treat as chapters if there are at least 3 timestamps (avoids false positives)
        return chapters.count >= 3 ? chapters : []
    }

    // MARK: - Duration Parsing

    /// Parses "1:23:45" or "12:34" into seconds
    private static func parseDuration(_ text: String) -> TimeInterval {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 3: return TimeInterval(parts[0] * 3600 + parts[1] * 60 + parts[2])
        case 2: return TimeInterval(parts[0] * 60 + parts[1])
        case 1: return TimeInterval(parts[0])
        default: return 0
        }
    }

    // MARK: - View Count Parsing

    /// Parses "1,234,567 views" into an integer
    private static func parseViewCount(_ text: String) -> Int {
        let lowercased = text.lowercased()

        if lowercased.contains("no views") {
            return 0
        }

        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*([kmb]?)"#),
              let match = regex.firstMatch(
                in: lowercased,
                range: NSRange(lowercased.startIndex..., in: lowercased)
              ),
              let valueRange = Range(match.range(at: 1), in: lowercased) else {
            return Int(lowercased.filter { $0.isNumber }) ?? 0
        }

        let valueToken = normalizeNumericToken(String(lowercased[valueRange]))
        guard let baseValue = Double(valueToken) else {
            return Int(lowercased.filter { $0.isNumber }) ?? 0
        }

        let suffix = Range(match.range(at: 2), in: lowercased).map { String(lowercased[$0]) } ?? ""
        let multiplier: Double
        switch suffix {
        case "k": multiplier = 1_000
        case "m": multiplier = 1_000_000
        case "b": multiplier = 1_000_000_000
        default: multiplier = 1
        }

        return Int(baseValue * multiplier)
    }

    private static func normalizeNumericToken(_ token: String) -> String {
        if token.contains(",") && token.contains(".") {
            return token.replacingOccurrences(of: ",", with: "")
        }

        if token.contains(",") {
            let parts = token.split(separator: ",")
            if parts.count == 2, let fractional = parts.last, fractional.count <= 2 {
                return token.replacingOccurrences(of: ",", with: ".")
            }
            return token.replacingOccurrences(of: ",", with: "")
        }

        return token
    }

    // MARK: - Comment Parsing

    /// Walks the `next` response to find the continuation token that unlocks
    /// the video's comments section. YouTube places it inside an engagement
    /// panel; we hunt for the panel by identifier rather than relying on a
    /// fragile fixed path.
    static func findCommentsContinuationToken(in json: [String: Any]) -> String? {
        var target: String?

        func walk(_ node: Any) {
            if target != nil { return }

            if let dict = node as? [String: Any] {
                // The comments panel carries a `panelIdentifier` like
                // "engagement-panel-comments-section" or a target id of
                // "comments-section-identifier". When we see one, grab the
                // nearest continuationCommand.token inside.
                let panelId = (dict["panelIdentifier"] as? String)
                    ?? (dict["targetId"] as? String)
                    ?? ""
                if panelId.contains("comment"),
                   let token = extractContinuationToken(in: dict) {
                    target = token
                    return
                }

                for value in dict.values {
                    walk(value)
                    if target != nil { return }
                }
            } else if let array = node as? [Any] {
                for element in array {
                    walk(element)
                    if target != nil { return }
                }
            }
        }

        walk(json)
        return target
    }

    private static func extractContinuationToken(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if let command = dict["continuationCommand"] as? [String: Any],
               let token = command["token"] as? String, !token.isEmpty {
                return token
            }
            for value in dict.values {
                if let token = extractContinuationToken(in: value) { return token }
            }
        } else if let array = node as? [Any] {
            for element in array {
                if let token = extractContinuationToken(in: element) { return token }
            }
        }
        return nil
    }

    /// Parses top-level comment threads from a `next` continuation response.
    static func parseComments(_ json: [String: Any], videoId: String) -> [Comment] {
        var renderers: [[String: Any]] = []

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                if let thread = dict["commentThreadRenderer"] as? [String: Any] {
                    renderers.append(thread)
                }
                // Newer responses wrap threads inline; keep recursing so we
                // pick them up regardless of parent shape.
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for element in array { walk(element) }
            }
        }

        walk(json)
        return renderers.compactMap { parseCommentThreadRenderer($0, videoId: videoId) }
    }

    private static func parseCommentThreadRenderer(_ thread: [String: Any], videoId: String) -> Comment? {
        // YouTube has two shapes: legacy `comment.commentRenderer` and newer
        // `commentViewModel`. Try both.
        if let wrapper = thread["comment"] as? [String: Any],
           let renderer = wrapper["commentRenderer"] as? [String: Any] {
            return parseCommentRenderer(renderer, videoId: videoId, thread: thread)
        }

        if let viewModel = thread["commentViewModel"] as? [String: Any] {
            return parseCommentViewModel(viewModel, videoId: videoId, thread: thread)
        }

        return nil
    }

    private static func parseCommentRenderer(_ renderer: [String: Any], videoId: String, thread: [String: Any]) -> Comment? {
        let commentId = (renderer["commentId"] as? String) ?? UUID().uuidString
        let authorName = extractText(renderer["authorText"]) ?? "Unknown"
        let authorAvatar = extractThumbnailURL(from: renderer["authorThumbnail"])
        let authorChannelId = ((renderer["authorEndpoint"] as? [String: Any])?["browseEndpoint"] as? [String: Any])?["browseId"] as? String ?? ""
        let text = extractText(renderer["contentText"]) ?? ""
        let publishedText = extractText(renderer["publishedTimeText"]) ?? ""
        let publishedAt = parseRelativeDate(publishedText)

        var likeCount = 0
        if let countText = extractText(renderer["voteCount"]) {
            likeCount = Int(parseViewCount(countText))
        }

        let replyCount = extractReplyCount(from: thread)

        return Comment(
            id: commentId,
            videoId: videoId,
            authorName: authorName,
            authorAvatar: authorAvatar,
            authorChannelId: authorChannelId,
            text: text,
            likeCount: likeCount,
            publishedAt: publishedAt,
            isPinned: false,
            isCreatorHeart: false,
            replyCount: replyCount,
            replies: nil
        )
    }

    private static func parseCommentViewModel(_ viewModel: [String: Any], videoId: String, thread: [String: Any]) -> Comment? {
        let commentId = (viewModel["commentId"] as? String) ?? UUID().uuidString

        // commentViewModel references external keys; fall back to whatever
        // plain text is reachable in the wrapping structure.
        let text: String = {
            if let content = viewModel["commentText"] as? [String: Any] {
                return extractText(content) ?? ""
            }
            return ""
        }()

        let authorName: String = {
            if let author = viewModel["author"] as? [String: Any] {
                return extractText(author["displayName"]) ?? "Unknown"
            }
            return "Unknown"
        }()

        let avatar: String? = {
            if let author = viewModel["author"] as? [String: Any] {
                return extractThumbnailURL(from: author["avatar"]) ?? extractThumbnailURL(from: author["channelAvatar"])
            }
            return nil
        }()

        let publishedText: String = {
            if let time = viewModel["publishedTime"] as? [String: Any] {
                return extractText(time) ?? ""
            }
            return ""
        }()

        return Comment(
            id: commentId,
            videoId: videoId,
            authorName: authorName,
            authorAvatar: avatar,
            authorChannelId: "",
            text: text,
            likeCount: 0,
            publishedAt: parseRelativeDate(publishedText),
            isPinned: false,
            isCreatorHeart: false,
            replyCount: extractReplyCount(from: thread),
            replies: nil
        )
    }

    private static func extractReplyCount(from thread: [String: Any]) -> Int {
        if let replies = thread["replies"] as? [String: Any],
           let repliesRenderer = replies["commentRepliesRenderer"] as? [String: Any],
           let moreText = extractText(repliesRenderer["viewReplies"]) ?? extractText(repliesRenderer["moreText"]) {
            return Int(parseViewCount(moreText))
        }
        return 0
    }

    // MARK: - Relative Date Parsing

    /// Converts "3 days ago" etc. into an approximate Date
    private static func parseRelativeDate(_ text: String) -> Date {
        let components = text.lowercased().split(separator: " ")
        guard components.count >= 2, let value = Int(components[0]) else { return Date() }

        let unit = String(components[1])
        let seconds: Int
        if unit.hasPrefix("second") { seconds = value }
        else if unit.hasPrefix("minute") { seconds = value * 60 }
        else if unit.hasPrefix("hour") { seconds = value * 3600 }
        else if unit.hasPrefix("day") { seconds = value * 86400 }
        else if unit.hasPrefix("week") { seconds = value * 604800 }
        else if unit.hasPrefix("month") { seconds = value * 2592000 }
        else if unit.hasPrefix("year") { seconds = value * 31536000 }
        else { return Date() }

        return Date().addingTimeInterval(-Double(seconds))
    }
}

// MARK: - Response Models

struct PlayerResponse: Codable {
    let videoDetails: VideoDetails?
    let streamingData: StreamingData?
    
    struct VideoDetails: Codable {
        let videoId: String
        let title: String
        let lengthSeconds: String
        let channelId: String
        let shortDescription: String
        let thumbnail: ThumbnailContainer
        let viewCount: String?
        let author: String
        
        struct ThumbnailContainer: Codable {
            let thumbnails: [Thumbnail]
        }
        
        struct Thumbnail: Codable {
            let url: String
            let width: Int
            let height: Int
        }
    }
    
    struct StreamingData: Codable {
        let hlsManifestUrl: String?
        let dashManifestUrl: String?
        let formats: [Format]?
        let adaptiveFormats: [Format]?
        
        struct Format: Codable {
            let itag: Int
            let url: String?
            let mimeType: String
            let bitrate: Int?
            let width: Int?
            let height: Int?
            let qualityLabel: String?
        }
    }
}

