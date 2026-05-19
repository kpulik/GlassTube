//
//  Video.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import Foundation

// MARK: - Video Model

struct Video: Identifiable, Codable, Hashable {
    let id: String
    let title: String
    let description: String
    let channelId: String
    let channelName: String
    let channelAvatar: String?
    let thumbnailURL: String
    let duration: TimeInterval
    let viewCount: Int
    let likeCount: Int?
    let publishedAt: Date
    let isLive: Bool
    let isUpcoming: Bool
    
    // Computed properties
    var formattedViews: String {
        formatCount(viewCount)
    }
    
    var formattedDuration: String {
        formatDuration(duration)
    }
    
    var relativeTime: String {
        formatRelativeTime(publishedAt)
    }
    
    // MARK: - Formatting Helpers
    
    private func formatCount(_ count: Int) -> String {
        if count >= 1_000_000_000 {
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        } else if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        let secs = Int(seconds) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
    
    private func formatRelativeTime(_ date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        let seconds = Int(interval)
        
        if seconds < 60 {
            return "just now"
        } else if seconds < 3600 {
            let minutes = seconds / 60
            return "\(minutes) minute\(minutes == 1 ? "" : "s") ago"
        } else if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if seconds < 604800 {
            let days = seconds / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if seconds < 2592000 {
            let weeks = seconds / 604800
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if seconds < 31536000 {
            let months = seconds / 2592000
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else {
            let years = seconds / 31536000
            return "\(years) year\(years == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Channel Model

struct Channel: Identifiable, Codable {
    let id: String
    let name: String
    let handle: String
    let avatarURL: String?
    let bannerURL: String?
    let subscriberCount: Int?
    let videoCount: Int?
    let description: String
    let isVerified: Bool
    
    var formattedSubscribers: String {
        guard let count = subscriberCount else { return "Unknown" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return "\(count)"
    }
}

// MARK: - Playlist Model

struct Playlist: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let channelId: String
    let channelName: String
    let thumbnailURL: String?
    let videoCount: Int
    let videos: [Video]
}

// MARK: - Comment Model

struct Comment: Identifiable, Codable {
    let id: String
    let videoId: String
    let authorName: String
    let authorAvatar: String?
    let authorChannelId: String
    let text: String
    let likeCount: Int
    let publishedAt: Date
    let isPinned: Bool
    let isCreatorHeart: Bool
    let replyCount: Int
    let replies: [Comment]?
    
    var relativeTime: String {
        let interval = Date.now.timeIntervalSince(publishedAt)
        let seconds = Int(interval)
        
        if seconds < 86400 {
            let hours = seconds / 3600
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else if seconds < 604800 {
            let days = seconds / 86400
            return "\(days) day\(days == 1 ? "" : "s") ago"
        } else if seconds < 2592000 {
            let weeks = seconds / 604800
            return "\(weeks) week\(weeks == 1 ? "" : "s") ago"
        } else if seconds < 31536000 {
            let months = seconds / 2592000
            return "\(months) month\(months == 1 ? "" : "s") ago"
        } else {
            let years = seconds / 31536000
            return "\(years) year\(years == 1 ? "" : "s") ago"
        }
    }
}

// MARK: - Chapter Model

struct Chapter: Identifiable, Equatable {
    let id: String
    let title: String
    let startTime: TimeInterval
    let thumbnailURL: String?

    init(title: String, startTime: TimeInterval, thumbnailURL: String? = nil) {
        self.id = "\(startTime)-\(title)"
        self.title = title
        self.startTime = startTime
        self.thumbnailURL = thumbnailURL
    }
}

// MARK: - Search Result

struct SearchResult: Identifiable {
    let id: String
    let type: SearchResultType
    
    enum SearchResultType {
        case video(Video)
        case channel(Channel)
        case playlist(Playlist)
    }
}
