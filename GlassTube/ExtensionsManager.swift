//
//  ExtensionsManager.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import Foundation
import SwiftUI
import Combine
import CryptoKit

/// Manages third-party extension data: SponsorBlock, Return YouTube Dislike, DeArrow
@MainActor
class ExtensionsManager: ObservableObject {

    // MARK: - Published State

    @Published var sponsorSegments: [SponsorSegment] = []
    @Published var likeCount: Int?
    @Published var dislikeCount: Int?
    @Published var deArrowTitle: String?
    @Published var deArrowThumbnailTimestamp: Double?

    // MARK: - Settings

    private let defaults = UserDefaults.standard
    private let sponsorBlockKey = "sponsorBlockEnabled"
    private let returnYoutubeDislikeKey = "returnYoutubeDislikeEnabled"
    private let dearrowKey = "dearrowEnabled"

    // MARK: - API endpoints

    private let sponsorBlockBase = "https://sponsor.ajay.app/api"
    private let rydBase = "https://returnyoutubedislikeapi.com"
    private let dearrowBase = "https://sponsor.ajay.app/api"

    // MARK: - Background refresh

    private var currentVideoId: String?
    private var refreshTask: Task<Void, Never>?

    private var sponsorBlockEnabledSetting: Bool {
        defaults.object(forKey: sponsorBlockKey) as? Bool ?? true
    }

    private var returnYoutubeDislikeEnabledSetting: Bool {
        defaults.object(forKey: returnYoutubeDislikeKey) as? Bool ?? true
    }

    private var dearrowEnabledSetting: Bool {
        defaults.object(forKey: dearrowKey) as? Bool ?? true
    }

    // MARK: - Load All Extensions for a Video

    /// Call this when a video starts playing. Fetches all enabled extension data.
    func loadExtensions(for videoId: String) {
        currentVideoId = videoId
        refreshTask?.cancel()

        // Reset state
        resetExtensionState()

        refreshTask = Task {
            await fetchAll(videoId: videoId)

            // Auto-refresh in background every 5 minutes (segments can be updated)
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                guard !Task.isCancelled, currentVideoId == videoId else { break }
                await fetchAll(videoId: videoId)
            }
        }
    }

    func applyUserSettings(
        sponsorBlockEnabled: Bool,
        returnYoutubeDislikeEnabled: Bool,
        deArrowEnabled: Bool
    ) {
        defaults.set(sponsorBlockEnabled, forKey: sponsorBlockKey)
        defaults.set(returnYoutubeDislikeEnabled, forKey: returnYoutubeDislikeKey)
        defaults.set(deArrowEnabled, forKey: dearrowKey)

        Task {
            await refreshCurrentVideoExtensions()
        }
    }

    func refreshCurrentVideoExtensions() async {
        guard let currentVideoId else {
            resetExtensionState()
            return
        }
        await fetchAll(videoId: currentVideoId)
    }

    /// Stop background refreshes
    func stopRefreshing() {
        refreshTask?.cancel()
        refreshTask = nil
        currentVideoId = nil
    }

    // MARK: - Fetch All

    private func fetchAll(videoId: String) async {
        let sponsorEnabled = sponsorBlockEnabledSetting
        let dislikeEnabled = returnYoutubeDislikeEnabledSetting
        let deArrowEnabled = dearrowEnabledSetting

        if !sponsorEnabled {
            sponsorSegments = []
        }
        if !dislikeEnabled {
            likeCount = nil
            dislikeCount = nil
        }
        if !deArrowEnabled {
            deArrowTitle = nil
            deArrowThumbnailTimestamp = nil
        }

        await withTaskGroup(of: Void.self) { group in
            if sponsorEnabled {
                group.addTask { await self.fetchSponsorSegments(videoId: videoId) }
            }
            if dislikeEnabled {
                group.addTask { await self.fetchDislikeCount(videoId: videoId) }
            }
            if deArrowEnabled {
                group.addTask { await self.fetchDeArrow(videoId: videoId) }
            }
        }
    }

    private func resetExtensionState() {
        sponsorSegments = []
        likeCount = nil
        dislikeCount = nil
        deArrowTitle = nil
        deArrowThumbnailTimestamp = nil
    }

    // MARK: - SponsorBlock

    /// Uses privacy-preserving hash-based lookup (only sends first 4 chars of SHA256)
    private func fetchSponsorSegments(videoId: String) async {
        let hash = sha256Prefix(videoId)

        guard let url = URL(string: "\(sponsorBlockBase)/skipSegments/\(hash)?categories=[\"sponsor\",\"selfpromo\",\"interaction\",\"intro\",\"outro\",\"preview\",\"music_offtopic\",\"filler\"]") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let results = try JSONDecoder().decode([SponsorBlockHashResult].self, from: data)

            // Find our video in the hash results
            let segments = results
                .first(where: { $0.videoID == videoId })?
                .segments ?? []

            await MainActor.run {
                self.sponsorSegments = segments
            }
        } catch {
            // Silent fail -- extension data is non-critical
        }
    }

    // MARK: - Return YouTube Dislike

    private func fetchDislikeCount(videoId: String) async {
        guard let url = URL(string: "\(rydBase)/votes?videoId=\(videoId)") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let result = try JSONDecoder().decode(RYDResponse.self, from: data)

            await MainActor.run {
                self.likeCount = result.likes
                self.dislikeCount = result.dislikes
            }
        } catch {
            // Silent fail
        }
    }

    // MARK: - DeArrow

    private func fetchDeArrow(videoId: String) async {
        let hash = sha256Prefix(videoId)

        guard let url = URL(string: "\(dearrowBase)/branding/\(hash)") else { return }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return }

            let results = try JSONDecoder().decode([String: DeArrowResult].self, from: data)

            guard let result = results[videoId] else { return }

            await MainActor.run {
                // Use the most voted title
                if let title = result.titles.max(by: { $0.votes < $1.votes }),
                   title.votes >= 0 {
                    self.deArrowTitle = title.title
                }
                // Use the most voted thumbnail timestamp
                if let thumb = result.thumbnails.max(by: { $0.votes < $1.votes }),
                   thumb.votes >= 0 {
                    self.deArrowThumbnailTimestamp = thumb.timestamp
                }
            }
        } catch {
            // Silent fail
        }
    }

    // MARK: - Helpers

    /// Returns first 4 hex chars of SHA256 hash (SponsorBlock privacy API)
    private func sha256Prefix(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(4))
    }
}

// MARK: - SponsorBlock Models

struct SponsorBlockHashResult: Codable {
    let videoID: String
    let segments: [SponsorSegment]
}

struct SponsorSegment: Identifiable, Codable, Equatable {
    let UUID: String
    let segment: [Double]        // [startTime, endTime]
    let category: String
    let actionType: String

    var id: String { UUID }
    var startTime: Double { segment.first ?? 0 }
    var endTime: Double { segment.last ?? 0 }

    var categoryColor: Color {
        switch category {
        case "sponsor": return .green
        case "selfpromo": return .yellow
        case "interaction": return .purple
        case "intro": return .cyan
        case "outro": return .blue
        case "preview": return .indigo
        case "music_offtopic": return .orange
        case "filler": return .gray
        default: return .secondary
        }
    }

    var categoryLabel: String {
        switch category {
        case "sponsor": return "Sponsor"
        case "selfpromo": return "Self-Promotion"
        case "interaction": return "Interaction"
        case "intro": return "Intro"
        case "outro": return "Outro"
        case "preview": return "Preview"
        case "music_offtopic": return "Non-Music"
        case "filler": return "Filler"
        default: return category.capitalized
        }
    }
}

// MARK: - Return YouTube Dislike Models

struct RYDResponse: Codable {
    let id: String
    let likes: Int
    let dislikes: Int
    let rating: Double
    let viewCount: Int
}

// MARK: - DeArrow Models

struct DeArrowResult: Codable {
    let titles: [DeArrowTitle]
    let thumbnails: [DeArrowThumbnail]
}

struct DeArrowTitle: Codable {
    let title: String
    let votes: Int
}

struct DeArrowThumbnail: Codable {
    let timestamp: Double?
    let votes: Int
}
