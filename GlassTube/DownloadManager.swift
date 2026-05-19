//
//  DownloadManager.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import Foundation
import SwiftUI
import Combine
import AppKit

/// Manages video downloads using yt-dlp.
@MainActor
class DownloadManager: ObservableObject {

    // MARK: - Published State

    @Published var downloads: [DownloadItem] = []
    @Published var preferredQuality: DownloadQualityPreference
    @Published var preferredMediaType: DownloadMediaPreference
    @Published var customDownloadsDirectoryPath: String

    // MARK: - Configuration

    private let defaults = UserDefaults.standard
    private let downloadsDirectoryPathKey = "downloadsDirectoryPath"
    private let downloadQualityKey = "downloadQualityPreference"
    private let downloadMediaTypeKey = "downloadMediaPreference"
    private var activeProcesses: [String: Process] = [:]

    /// Where downloaded media is stored.
    var downloadsDirectory: URL {
        if !customDownloadsDirectoryPath.isEmpty {
            let customURL = URL(fileURLWithPath: customDownloadsDirectoryPath, isDirectory: true)
            ensureDirectoryExists(customURL)
            return customURL
        }

        if let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first {
            ensureDirectoryExists(downloadsURL)
            return downloadsURL
        }

        let fallback = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads", isDirectory: true)
        ensureDirectoryExists(fallback)
        return fallback
    }

    var downloadsDirectoryDisplayPath: String {
        downloadsDirectory.path
    }

    /// Path to yt-dlp binary.
    private var ytdlpPath: String? {
        let candidates = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp"
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    // MARK: - Init

    init() {
        let storedQuality = defaults.string(forKey: downloadQualityKey) ?? DownloadQualityPreference.auto.rawValue
        preferredQuality = DownloadQualityPreference(rawValue: storedQuality) ?? .auto

        let storedMediaType = defaults.string(forKey: downloadMediaTypeKey) ?? DownloadMediaPreference.videoWithAudio.rawValue
        preferredMediaType = DownloadMediaPreference(rawValue: storedMediaType) ?? .videoWithAudio

        customDownloadsDirectoryPath = defaults.string(forKey: downloadsDirectoryPathKey) ?? ""

        loadDownloadedVideos()
        refreshMissingFiles()
    }

    // MARK: - Preferences

    func setPreferredQuality(_ quality: DownloadQualityPreference) {
        preferredQuality = quality
        defaults.set(quality.rawValue, forKey: downloadQualityKey)
    }

    func setPreferredMediaType(_ mediaType: DownloadMediaPreference) {
        preferredMediaType = mediaType
        defaults.set(mediaType.rawValue, forKey: downloadMediaTypeKey)
    }

    func chooseDownloadsDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose Folder"
        panel.directoryURL = downloadsDirectory

        guard panel.runModal() == .OK, let selectedURL = panel.url else { return }
        setDownloadsDirectory(selectedURL)
    }

    func setDownloadsDirectory(_ directoryURL: URL) {
        customDownloadsDirectoryPath = directoryURL.path
        defaults.set(directoryURL.path, forKey: downloadsDirectoryPathKey)
        ensureDirectoryExists(directoryURL)
        reloadCompletedDownloadsFromDisk()
    }

    func resetDownloadsDirectory() {
        customDownloadsDirectoryPath = ""
        defaults.removeObject(forKey: downloadsDirectoryPathKey)
        reloadCompletedDownloadsFromDisk()
    }

    // MARK: - Download

    func download(videoId: String, title: String, channelName: String, thumbnailURL: String, quality: DownloadQualityPreference? = nil, mediaType: DownloadMediaPreference? = nil) {
        let resolvedQuality = quality ?? preferredQuality
        let resolvedMediaType = mediaType ?? preferredMediaType
        startDownload(videoId: videoId, title: title, channelName: channelName, thumbnailURL: thumbnailURL, quality: resolvedQuality, mediaType: resolvedMediaType)
    }

    private func startDownload(videoId: String, title: String, channelName: String, thumbnailURL: String, quality: DownloadQualityPreference, mediaType: DownloadMediaPreference) {
        guard let ytdlp = ytdlpPath else {
            let item = DownloadItem(
                videoId: videoId,
                title: title,
                channelName: channelName,
                thumbnailURL: thumbnailURL,
                status: .failed("yt-dlp not found. Install with: brew install yt-dlp"),
                fileURL: nil,
                downloadedAt: nil,
                mediaType: preferredMediaType,
                quality: preferredQuality
            )
            downloads.insert(item, at: 0)
            return
        }

        if let existingIndex = downloads.firstIndex(where: { $0.videoId == videoId }) {
            if case .completed = downloads[existingIndex].status { return }
            if case .downloading = downloads[existingIndex].status { return }
            downloads.remove(at: existingIndex)
        }

        let item = DownloadItem(
            videoId: videoId,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURL,
            status: .downloading(progress: 0),
            fileURL: nil,
            downloadedAt: nil,
            mediaType: mediaType,
            quality: quality
        )
        downloads.insert(item, at: 0)

        let outputTemplate = downloadsDirectory
            .appendingPathComponent("%(title)s [%(id)s].%(ext)s").path

        let arguments = buildDownloadArguments(
            videoId: videoId,
            outputTemplate: outputTemplate,
            quality: quality,
            mediaType: mediaType
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = arguments

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        activeProcesses[videoId] = process

        Task.detached { [weak self] in
            do {
                try process.run()

                let handle = pipe.fileHandleForReading
                for try await line in handle.bytes.lines {
                    if let progress = Self.parseProgress(line) {
                        await MainActor.run { [weak self] in
                            self?.updateProgress(videoId: videoId, progress: progress)
                        }
                    }
                }

                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let fileURL = await self?.findDownloadedFile(videoId: videoId, mediaType: mediaType)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.activeProcesses.removeValue(forKey: videoId)
                        guard let fileURL else {
                            self.markFailed(videoId: videoId, error: "Download finished, but the file could not be located.")
                            return
                        }
                        self.markCompleted(videoId: videoId, fileURL: fileURL)
                    }
                } else {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.activeProcesses.removeValue(forKey: videoId)

                        if process.terminationReason == .uncaughtSignal || process.terminationStatus == 15 {
                            self.markFailed(videoId: videoId, error: "Download canceled.")
                            return
                        }

                        self.markFailed(videoId: videoId, error: "yt-dlp exited with code \(process.terminationStatus)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.activeProcesses.removeValue(forKey: videoId)
                    self?.markFailed(videoId: videoId, error: error.localizedDescription)
                }
            }
        }
    }

    /// Fetches available download qualities for a video via yt-dlp --list-formats.
    nonisolated func fetchAvailableQualities(videoId: String) async -> [DownloadFormatOption] {
        await Task.detached(priority: .utility) { [ytdlpPath = await self.ytdlpPath] in
            guard let ytdlp = ytdlpPath else { return [] }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ytdlp)
            process.arguments = [
                "https://www.youtube.com/watch?v=\(videoId)",
                "--no-playlist",
                "-F"   // list available formats
            ]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                return []
            }

            guard process.terminationStatus == 0 else { return [] }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return Self.parseFormatList(output)
        }.value
    }

    /// Parse yt-dlp -F output into structured format options.
    private nonisolated static func parseFormatList(_ output: String) -> [DownloadFormatOption] {
        var options: [DownloadFormatOption] = []
        var seenHeights = Set<Int>()

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip header lines and non-format lines
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("ID"),
                  !trimmed.hasPrefix("["),
                  !trimmed.contains("---") else { continue }

            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 3 else { continue }

            let formatId = parts[0]
            let ext = parts[1]

            // Look for resolution like "1920x1080" or "1280x720"
            var height: Int?
            var hasVideo = false
            var hasAudio = false
            var fileSize: String?

            for part in parts {
                if part.contains("x"), let resHeight = part.split(separator: "x").last.flatMap({ Int($0) }) {
                    height = resHeight
                }
                if part.contains("video") { hasVideo = true }
                if part.contains("audio") { hasAudio = true }
            }

            // Check for "video only" or "audio only" markers
            let fullLine = trimmed.lowercased()
            if fullLine.contains("video only") { hasVideo = true; hasAudio = false }
            else if fullLine.contains("audio only") { hasAudio = true; hasVideo = false }
            else if height != nil { hasVideo = true; hasAudio = true }

            // Look for file size indicators (e.g., "~123.45MiB")
            for part in parts {
                if part.hasSuffix("MiB") || part.hasSuffix("GiB") || part.hasSuffix("KiB") {
                    fileSize = part.replacingOccurrences(of: "~", with: "")
                }
            }

            guard hasVideo, let h = height, h > 0 else { continue }

            // Deduplicate by height — keep only the best per resolution
            guard seenHeights.insert(h).inserted else { continue }

            let label: String
            switch h {
            case 4320: label = "8K (4320p)"
            case 2160: label = "4K (2160p)"
            case 1440: label = "1440p"
            default: label = "\(h)p"
            }

            options.append(DownloadFormatOption(
                formatId: formatId,
                ext: ext,
                height: h,
                label: label,
                fileSize: fileSize,
                hasAudio: hasAudio
            ))
        }

        return options.sorted { $0.height > $1.height }
    }

    /// Download a specific format by format ID.
    func downloadWithFormat(videoId: String, title: String, channelName: String, thumbnailURL: String, formatOption: DownloadFormatOption) {
        guard let ytdlp = ytdlpPath else {
            let item = DownloadItem(
                videoId: videoId,
                title: title,
                channelName: channelName,
                thumbnailURL: thumbnailURL,
                status: .failed("yt-dlp not found. Install with: brew install yt-dlp"),
                fileURL: nil,
                downloadedAt: nil,
                mediaType: .videoWithAudio,
                quality: .auto
            )
            downloads.insert(item, at: 0)
            return
        }

        if let existingIndex = downloads.firstIndex(where: { $0.videoId == videoId }) {
            if case .completed = downloads[existingIndex].status { return }
            if case .downloading = downloads[existingIndex].status { return }
            downloads.remove(at: existingIndex)
        }

        let item = DownloadItem(
            videoId: videoId,
            title: title,
            channelName: channelName,
            thumbnailURL: thumbnailURL,
            status: .downloading(progress: 0),
            fileURL: nil,
            downloadedAt: nil,
            mediaType: .videoWithAudio,
            quality: .auto
        )
        downloads.insert(item, at: 0)

        let outputTemplate = downloadsDirectory
            .appendingPathComponent("%(title)s [%(id)s].%(ext)s").path

        // Build format string: if video-only, merge with best audio
        let formatString: String
        if formatOption.hasAudio {
            formatString = formatOption.formatId
        } else {
            formatString = "\(formatOption.formatId)+bestaudio[ext=m4a]/\(formatOption.formatId)+bestaudio"
        }

        var args: [String] = [
            "https://www.youtube.com/watch?v=\(videoId)",
            "--no-playlist",
            "--newline",
            "--no-colors",
            "-o", outputTemplate,
            "-f", formatString,
            "--merge-output-format", "mp4",
            "--no-keep-video"
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlp)
        process.arguments = args

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        activeProcesses[videoId] = process

        Task.detached { [weak self] in
            do {
                try process.run()

                let handle = pipe.fileHandleForReading
                for try await line in handle.bytes.lines {
                    if let progress = Self.parseProgress(line) {
                        await MainActor.run { [weak self] in
                            self?.updateProgress(videoId: videoId, progress: progress)
                        }
                    }
                }

                process.waitUntilExit()

                if process.terminationStatus == 0 {
                    let fileURL = await self?.findDownloadedFile(videoId: videoId, mediaType: .videoWithAudio)
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.activeProcesses.removeValue(forKey: videoId)
                        guard let fileURL else {
                            self.markFailed(videoId: videoId, error: "Download finished, but the file could not be located.")
                            return
                        }
                        self.markCompleted(videoId: videoId, fileURL: fileURL)
                    }
                } else {
                    await MainActor.run { [weak self] in
                        guard let self else { return }
                        self.activeProcesses.removeValue(forKey: videoId)

                        if process.terminationReason == .uncaughtSignal || process.terminationStatus == 15 {
                            self.markFailed(videoId: videoId, error: "Download canceled.")
                            return
                        }

                        self.markFailed(videoId: videoId, error: "yt-dlp exited with code \(process.terminationStatus)")
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.activeProcesses.removeValue(forKey: videoId)
                    self?.markFailed(videoId: videoId, error: error.localizedDescription)
                }
            }
        }
    }

    func cancelDownload(videoId: String) {
        if let process = activeProcesses[videoId] {
            process.terminate()
            activeProcesses.removeValue(forKey: videoId)
        }

        if let index = downloads.firstIndex(where: { $0.videoId == videoId }) {
            downloads[index].status = .failed("Download canceled.")
        }
    }

    // MARK: - Delete / Missing Files

    func deleteDownload(_ item: DownloadItem) {
        if let fileURL = item.fileURL, FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        downloads.removeAll { $0.id == item.id }
    }

    func markFileMissing(videoId: String) {
        guard let index = downloads.firstIndex(where: { $0.videoId == videoId }) else { return }
        downloads[index].status = .missingFile
    }

    func refreshMissingFiles() {
        for index in downloads.indices {
            guard case .completed = downloads[index].status else { continue }

            guard let fileURL = downloads[index].fileURL,
                  FileManager.default.fileExists(atPath: fileURL.path) else {
                downloads[index].status = .missingFile
                continue
            }
        }
    }

    // MARK: - Play

    func fileURL(for videoId: String) -> URL? {
        guard let item = downloads.first(where: { $0.videoId == videoId && $0.isCompleted }) else { return nil }
        guard let fileURL = item.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            markFileMissing(videoId: videoId)
            return nil
        }
        return fileURL
    }

    // MARK: - Progress Parsing

    private nonisolated static func parseProgress(_ line: String) -> Double? {
        guard line.contains("[download]"), line.contains("%") else { return nil }

        let components = line.components(separatedBy: CharacterSet.whitespaces)
        for component in components {
            if component.hasSuffix("%"), let value = Double(component.dropLast()) {
                return value / 100.0
            }
        }
        return nil
    }

    // MARK: - State Updates

    private func updateProgress(videoId: String, progress: Double) {
        guard let index = downloads.firstIndex(where: { $0.videoId == videoId }) else { return }
        downloads[index].status = .downloading(progress: progress)
    }

    private func markCompleted(videoId: String, fileURL: URL) {
        guard let index = downloads.firstIndex(where: { $0.videoId == videoId }) else { return }
        downloads[index].status = .completed
        downloads[index].fileURL = fileURL
        downloads[index].downloadedAt = Date()
    }

    private func markFailed(videoId: String, error: String) {
        guard let index = downloads.firstIndex(where: { $0.videoId == videoId }) else { return }
        downloads[index].status = .failed(error)
    }

    // MARK: - Build yt-dlp Args

    private func buildDownloadArguments(
        videoId: String,
        outputTemplate: String,
        quality: DownloadQualityPreference,
        mediaType: DownloadMediaPreference
    ) -> [String] {
        var args: [String] = [
            "https://www.youtube.com/watch?v=\(videoId)",
            "--no-playlist",
            "--newline",
            "--no-colors",
            "-o", outputTemplate
        ]

        switch mediaType {
        case .videoWithAudio:
            args += [
                "-f", quality.combinedFormatSelector,
                "--merge-output-format", "mp4",
                "--no-keep-video"
            ]
        case .videoOnly:
            args += [
                "-f", quality.videoOnlyFormatSelector
            ]
        case .audioOnly:
            args += [
                "-f", "bestaudio[ext=m4a]/bestaudio",
                "--extract-audio",
                "--audio-format", "m4a",
                "--audio-quality", "0"
            ]
        }

        return args
    }

    // MARK: - File Discovery

    private func findDownloadedFile(videoId: String, mediaType: DownloadMediaPreference) -> URL? {
        let directory = downloadsDirectory
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let matchingFiles = contents.filter { url in
            let fileName = url.deletingPathExtension().lastPathComponent
            guard matchesDownloadedBaseName(fileName, videoId: videoId) else { return false }

            let ext = url.pathExtension.lowercased()
            switch mediaType {
            case .audioOnly:
                return ["m4a", "mp3", "aac", "opus", "ogg", "wav"].contains(ext)
            case .videoOnly, .videoWithAudio:
                return ["mp4", "mkv", "webm", "m4v", "mov"].contains(ext)
            }
        }

        return matchingFiles
            .sorted(by: { lhs, rhs in
                let leftDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate > rightDate
            })
            .first
    }

    // MARK: - Load Existing Downloads

    private func reloadCompletedDownloadsFromDisk() {
        downloads.removeAll { $0.isCompleted || $0.isMissingFile }
        loadDownloadedVideos()
        refreshMissingFiles()
    }

    private func loadDownloadedVideos() {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: downloadsDirectory,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey]
        ) else { return }

        let downloadableExtensions = ["mp4", "mkv", "webm", "m4v", "mov", "m4a", "mp3", "aac", "opus", "ogg", "wav"]
        let mediaFiles = contents.filter { url in
            guard downloadableExtensions.contains(url.pathExtension.lowercased()) else { return false }
            let candidateID = url.deletingPathExtension().lastPathComponent
            return extractedVideoID(from: candidateID) != nil
        }

        for file in mediaFiles {
            let baseName = file.deletingPathExtension().lastPathComponent
            guard let videoId = extractedVideoID(from: baseName) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: file.path)
            let date = attrs?[.creationDate] as? Date ?? Date()
            let ext = file.pathExtension.lowercased()

            guard !downloads.contains(where: { $0.videoId == videoId && $0.isCompleted }) else { continue }

            // Extract title from "Title [videoId]" pattern, fall back to video ID
            let title: String
            if baseName.hasSuffix(" [\(videoId)]") {
                title = String(baseName.dropLast(videoId.count + 3))
            } else {
                title = videoId
            }

            downloads.append(DownloadItem(
                videoId: videoId,
                title: title,
                channelName: "",
                thumbnailURL: "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg",
                status: .completed,
                fileURL: file,
                downloadedAt: date,
                mediaType: ["m4a", "mp3", "aac", "opus", "ogg", "wav"].contains(ext) ? .audioOnly : .videoWithAudio,
                quality: .auto
            ))
        }

        downloads.sort { ($0.downloadedAt ?? .distantPast) > ($1.downloadedAt ?? .distantPast) }
    }

    private func isLikelyYouTubeVideoID(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9_-]{11}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private func matchesDownloadedBaseName(_ baseName: String, videoId: String) -> Bool {
        // Matches: "videoId", "videoId.f137", "Title [videoId]"
        if baseName == videoId { return true }
        if baseName.hasPrefix("\(videoId).") { return true }
        if baseName.hasSuffix(" [\(videoId)]") { return true }
        return false
    }

    private func extractedVideoID(from baseName: String) -> String? {
        // Match "Title [videoId]" pattern first
        if baseName.hasSuffix("]") {
            if let openBracket = baseName.lastIndex(of: "[") {
                let start = baseName.index(after: openBracket)
                let end = baseName.index(before: baseName.endIndex)
                if start < end {
                    let candidate = String(baseName[start..<end])
                    if isLikelyYouTubeVideoID(candidate) {
                        return candidate
                    }
                }
            }
        }

        // Legacy: bare video ID as filename
        if isLikelyYouTubeVideoID(baseName) {
            return baseName
        }

        if baseName.count >= 11 {
            let prefix = String(baseName.prefix(11))
            if isLikelyYouTubeVideoID(prefix) {
                return prefix
            }
        }

        return nil
    }

    private func ensureDirectoryExists(_ url: URL) {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}

// MARK: - Download Preferences

enum DownloadMediaPreference: String, CaseIterable, Identifiable {
    case videoWithAudio = "video_with_audio"
    case videoOnly = "video_only"
    case audioOnly = "audio_only"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .videoWithAudio:
            return "Video + Audio"
        case .videoOnly:
            return "Video Only"
        case .audioOnly:
            return "Audio Only"
        }
    }
}

enum DownloadQualityPreference: String, CaseIterable, Identifiable {
    case auto = "auto"
    case p4320 = "4320p"
    case p2160 = "2160p"
    case p1440 = "1440p"
    case p1080 = "1080p"
    case p720 = "720p"
    case p480 = "480p"
    case p360 = "360p"
    case p240 = "240p"
    case p144 = "144p"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto:
            return "Auto"
        case .p4320:
            return "8K (4320p)"
        case .p2160:
            return "4K (2160p)"
        case .p1440:
            return "1440p"
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        case .p480:
            return "480p"
        case .p360:
            return "360p"
        case .p240:
            return "240p"
        case .p144:
            return "144p"
        }
    }

    private var maxHeight: Int? {
        switch self {
        case .auto:
            return nil
        case .p4320:
            return 4320
        case .p2160:
            return 2160
        case .p1440:
            return 1440
        case .p1080:
            return 1080
        case .p720:
            return 720
        case .p480:
            return 480
        case .p360:
            return 360
        case .p240:
            return 240
        case .p144:
            return 144
        }
    }

    var combinedFormatSelector: String {
        if let maxHeight {
            // bestvideo+bestaudio downloads separate streams and merges them.
            // This is required for 1080p+ since YouTube only serves combined
            // (muxed video+audio) formats up to 720p.
            return "bestvideo[height<=\(maxHeight)][ext=mp4]+bestaudio[ext=m4a]/bestvideo[height<=\(maxHeight)]+bestaudio/best[height<=\(maxHeight)]"
        }
        return "bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best"
    }

    var videoOnlyFormatSelector: String {
        if let maxHeight {
            return "bestvideo[height<=\(maxHeight)][ext=mp4]/bestvideo[height<=\(maxHeight)]"
        }
        return "bestvideo[ext=mp4]/bestvideo"
    }
}

// MARK: - Download Item

struct DownloadItem: Identifiable {
    let id = UUID()
    let videoId: String
    var title: String
    var channelName: String
    var thumbnailURL: String
    var status: DownloadStatus
    var fileURL: URL?
    var downloadedAt: Date?
    var mediaType: DownloadMediaPreference
    var quality: DownloadQualityPreference

    var isCompleted: Bool {
        if case .completed = status { return true }
        return false
    }

    var isDownloading: Bool {
        if case .downloading = status { return true }
        return false
    }

    var isMissingFile: Bool {
        if case .missingFile = status { return true }
        return false
    }
}

enum DownloadStatus: Equatable {
    case downloading(progress: Double)
    case completed
    case failed(String)
    case missingFile

    static func == (lhs: DownloadStatus, rhs: DownloadStatus) -> Bool {
        switch (lhs, rhs) {
        case (.completed, .completed): return true
        case (.missingFile, .missingFile): return true
        case (.downloading(let a), .downloading(let b)): return a == b
        case (.failed(let a), .failed(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Download Format Option (from yt-dlp -F)

struct DownloadFormatOption: Identifiable {
    let formatId: String
    let ext: String
    let height: Int
    let label: String
    let fileSize: String?
    let hasAudio: Bool

    var id: String { "\(formatId)-\(height)" }

    var displayName: String {
        var name = label
        if let fileSize {
            name += " (\(fileSize))"
        }
        if !hasAudio {
            name += " — video only, will merge audio"
        }
        return name
    }
}
