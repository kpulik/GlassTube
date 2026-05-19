//
//  VideoPlayerViewModel.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AVFoundation
import AVKit
import Combine
import MediaPlayer
import AppKit

@MainActor
class VideoPlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var volume: Float = 1.0
    @Published var isMuted = false
    @Published var playbackRate: Float = 1.0
    @Published var isBuffering = false
    @Published var controlsVisible = true
    @Published var availableQualityOptions: [StreamQualityOption] = []
    @Published var selectedQualityOptionID: String = "auto"
    @Published var selectedQualityLabel: String = "Auto"
    @Published var subtitlesEnabled = false {
        didSet {
            applySubtitleSelection()
        }
    }
    @Published var availableSubtitleOptions: [AVMediaSelectionOption] = []
    @Published var selectedSubtitleOption: AVMediaSelectionOption?
    @Published var sponsorSegments: [SponsorSegment] = []
    @Published var chapters: [Chapter] = []
    @Published var currentChapter: Chapter?

    @AppStorage("sponsorBlockEnabled") private var sponsorBlockEnabled = true
    
    // MARK: - Player State
    
    private var timeObserver: Any?
    private var cancellables = Set<AnyCancellable>()
    private var playbackStateCancellable: AnyCancellable?
    private var controlsHideTask: Task<Void, Never>?
    private var recentlySkippedSegments: [String: TimeInterval] = [:]
    private var currentVideoURL: URL?

    // MARK: - Now Playing Metadata

    private var nowPlayingTitle: String = ""
    private var nowPlayingArtist: String = ""
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var nowPlayingArtworkURL: String = ""
    private var remoteCommandsConfigured = false
    
    // MARK: - Initialization
    
    init() {
        setupPlayerObservers()
        setupRemoteCommands()
    }
    
    nonisolated deinit {
        // Note: Cannot access @MainActor properties in deinit
        // The time observer will be cleaned up when the player is deallocated
    }
    
    // MARK: - Video Loading
    
    func loadVideo(url: URL) {
        if let currentPlayer = player, let timeObserver {
            currentPlayer.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }

        currentVideoURL = url

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.volume = volume
        player?.isMuted = isMuted
        player?.rate = 0

        if let player {
            observePlaybackState(for: player)
        }

        currentTime = 0
        duration = 0
        recentlySkippedSegments = [:]
        
        setupTimeObserver()
        setupPlayerItemObservers(playerItem)
    }

    func setQualityOptions(_ options: [StreamQualityOption], defaultURL: URL) {
        var deduplicatedByID: [String: StreamQualityOption] = [:]
        for option in options {
            deduplicatedByID[option.id] = option
        }

        let sorted = deduplicatedByID.values.sorted { lhs, rhs in
            if lhs.label == "Auto" { return true }
            if rhs.label == "Auto" { return false }
            return lhs.height > rhs.height
        }

        if sorted.isEmpty {
            availableQualityOptions = [
                StreamQualityOption(id: "auto", label: "Auto", url: defaultURL, height: Int.max)
            ]
            selectedQualityOptionID = "auto"
            selectedQualityLabel = "Auto"
            return
        }

        let hasAuto = sorted.contains(where: { $0.label == "Auto" })
        if hasAuto {
            availableQualityOptions = sorted
        } else {
            availableQualityOptions = [
                StreamQualityOption(id: "auto", label: "Auto", url: defaultURL, height: Int.max)
            ] + sorted
        }

        if let currentVideoURL,
           let matching = availableQualityOptions.first(where: { $0.url == currentVideoURL }) {
            selectedQualityOptionID = matching.id
            selectedQualityLabel = matching.label
        } else {
            selectedQualityOptionID = availableQualityOptions.first?.id ?? "auto"
            selectedQualityLabel = availableQualityOptions.first?.label ?? "Auto"
        }
    }

    func selectQuality(_ option: StreamQualityOption) {
        selectedQualityOptionID = option.id
        selectedQualityLabel = option.label

        // Same underlying URL (HLS path): clamp resolution on the existing
        // AVPlayerItem and let HLS adaptive bitrate pick the matching rung.
        // No item swap → no black reload, no seek, no audio glitch.
        if currentVideoURL == option.url, let playerItem = player?.currentItem {
            if option.height >= Int.max / 2 {
                playerItem.preferredMaximumResolution = .zero
                playerItem.preferredPeakBitRate = 0
            } else {
                playerItem.preferredMaximumResolution = CGSize(width: 0, height: CGFloat(option.height))
                playerItem.preferredPeakBitRate = 0
            }
            return
        }

        let resumeTime = currentTime
        let shouldResumePlayback = isPlaying

        loadVideo(url: option.url)

        if resumeTime > 0.25 {
            let seekTime = resumeTime
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(220))
                guard let self else { return }
                self.seek(to: seekTime)
                if shouldResumePlayback {
                    self.play()
                } else {
                    self.pause()
                }
            }
        } else if shouldResumePlayback {
            play()
        } else {
            pause()
        }
    }

    func stopPlaybackImmediately() {
        player?.pause()
        player?.isMuted = true
        isPlaying = false
        cancelControlsHide()
        showControls()
        clearNowPlayingInfo()
    }

    func updateSponsorSegments(_ segments: [SponsorSegment]) {
        sponsorSegments = segments
            .filter { $0.endTime > $0.startTime }
            .sorted { $0.startTime < $1.startTime }

        // Keep only entries that still exist in the latest segment list.
        let validIDs = Set(sponsorSegments.map(\.id))
        recentlySkippedSegments = recentlySkippedSegments.filter { validIDs.contains($0.key) }
    }

    func updateChapters(_ newChapters: [Chapter]) {
        chapters = newChapters.sorted { $0.startTime < $1.startTime }
        updateCurrentChapter(at: currentTime)
    }

    private func updateCurrentChapter(at time: TimeInterval) {
        guard !chapters.isEmpty else {
            currentChapter = nil
            return
        }
        // Find the last chapter whose startTime <= current time
        currentChapter = chapters.last { $0.startTime <= time }
    }
    
    // MARK: - Playback Controls
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func play() {
        player?.playImmediately(atRate: playbackRate)
        isPlaying = true
        scheduleControlsHide()
        updateNowPlayingPlaybackState()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        cancelControlsHide()
        showControls()
        updateNowPlayingPlaybackState()
    }
    
    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = time
            }
        }
        showControls()
        scheduleControlsHide()
    }
    
    func seekForward(_ seconds: TimeInterval = 5) {
        let newTime = min(currentTime + seconds, duration)
        seek(to: newTime)
    }
    
    func seekBackward(_ seconds: TimeInterval = 5) {
        let newTime = max(currentTime - seconds, 0)
        seek(to: newTime)
    }

    func seekToPercent(_ percent: Int) {
        let clamped = max(0, min(100, percent))
        guard duration > 0 else { return }
        seek(to: duration * Double(clamped) / 100.0)
    }
    
    func setVolume(_ newVolume: Float) {
        volume = max(0, min(1, newVolume))
        player?.volume = volume
        if volume > 0 {
            isMuted = false
            player?.isMuted = false
        }
    }
    
    func increaseVolume() {
        setVolume(volume + 0.05)
    }
    
    func decreaseVolume() {
        setVolume(volume - 0.05)
    }
    
    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
    
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player?.rate = isPlaying ? rate : 0
    }
    
    // MARK: - Controls Visibility
    
    func showControls() {
        controlsVisible = true
    }
    
    func hideControls() {
        if isPlaying {
            controlsVisible = false
        }
    }
    
    func scheduleControlsHide() {
        cancelControlsHide()
        controlsHideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && isPlaying {
                withAnimation(.easeOut(duration: 0.3)) {
                    hideControls()
                }
            }
        }
    }
    
    func cancelControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = nil
    }
    
    // MARK: - Observers
    
    private func setupPlayerObservers() {
        // Observe playing state
        NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)
            .sink { [weak self] _ in
                self?.isPlaying = false
                self?.showControls()
            }
            .store(in: &cancellables)
    }
    
    private func setupTimeObserver() {
        guard let player else { return }

        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        var nowPlayingTick: Int = 0
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentTime = time.seconds

                if let duration = self.player?.currentItem?.duration.seconds, duration.isFinite {
                    self.duration = duration
                }

                self.updateCurrentChapter(at: time.seconds)
                self.handleSponsorBlockAutoSkip(at: time.seconds)

                // Refresh Now Playing elapsed time every ~1s (4 ticks @ 0.25s)
                nowPlayingTick += 1
                if nowPlayingTick >= 4 {
                    nowPlayingTick = 0
                    self.updateNowPlayingPlaybackState()
                }
            }
        }
    }

    private func observePlaybackState(for player: AVPlayer) {
        playbackStateCancellable?.cancel()
        playbackStateCancellable = player.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self else { return }
                let playing = status == .playing
                if self.isPlaying != playing {
                    self.isPlaying = playing
                }

                if !playing {
                    self.cancelControlsHide()
                    self.showControls()
                }
            }
    }

    private func handleSponsorBlockAutoSkip(at currentTime: TimeInterval) {
        guard sponsorBlockEnabled,
              !sponsorSegments.isEmpty,
              currentTime.isFinite,
              duration > 0 else {
            return
        }

        // Expire old cooldown entries so a rewound segment can be skipped again later.
        recentlySkippedSegments = recentlySkippedSegments.filter { currentTime - $0.value < 8 }

        guard let segment = sponsorSegments.first(where: { segment in
            guard isAutoSkippable(segment),
                  segment.endTime > segment.startTime,
                  segment.endTime - segment.startTime > 0.25 else {
                return false
            }

            if let lastSkippedAt = recentlySkippedSegments[segment.id], currentTime - lastSkippedAt < 1.5 {
                return false
            }

            return currentTime >= segment.startTime && currentTime < segment.endTime - 0.05
        }) else {
            return
        }

        let targetTime = min(duration, max(currentTime, segment.endTime + 0.05))
        guard targetTime > currentTime + 0.05 else { return }

        recentlySkippedSegments[segment.id] = currentTime
        seekWithoutAffectingControls(to: targetTime)
    }

    private func isAutoSkippable(_ segment: SponsorSegment) -> Bool {
        let actionType = segment.actionType.lowercased()
        return actionType.isEmpty || actionType == "skip" || actionType == "full"
    }

    private func seekWithoutAffectingControls(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.currentTime = time
            }
        }
    }
    
    private func setupPlayerItemObservers(_ playerItem: AVPlayerItem) {
        // Observe buffering state
        playerItem.publisher(for: \.isPlaybackBufferEmpty)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isEmpty in
                self?.isBuffering = isEmpty
            }
            .store(in: &cancellables)

        // Update Now Playing duration once the item reports it
        playerItem.publisher(for: \.duration)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateNowPlayingPlaybackState()
            }
            .store(in: &cancellables)

        // Load subtitle tracks when the asset finishes loading its media
        // selection groups. HLS manifests expose their caption renditions
        // through the `legible` selection group.
        availableSubtitleOptions = []
        selectedSubtitleOption = nil

        let asset = playerItem.asset
        Task { [weak self, weak playerItem] in
            let options: [AVMediaSelectionOption]
            do {
                if let group = try await asset.loadMediaSelectionGroup(for: .legible) {
                    options = AVMediaSelectionGroup.playableMediaSelectionOptions(from: group.options)
                } else {
                    options = []
                }
            } catch {
                options = []
            }

            await MainActor.run { [weak self, weak playerItem] in
                guard let self, playerItem === self.player?.currentItem else { return }
                self.availableSubtitleOptions = options
                // If the user already had subtitles toggled on, apply now
                // that the tracks are known.
                if self.subtitlesEnabled {
                    self.applySubtitleSelection()
                }
            }
        }
    }

    // MARK: - Subtitles

    var hasSubtitles: Bool { !availableSubtitleOptions.isEmpty }

    func selectSubtitleOption(_ option: AVMediaSelectionOption?) {
        selectedSubtitleOption = option
        // Setting the option implicitly turns subtitles on.
        if option != nil && !subtitlesEnabled {
            // Avoid didSet re-entering applySubtitleSelection with the default
            // option; flip the flag first, then apply once below.
            subtitlesEnabled = true
            return
        }
        applySubtitleSelection()
    }

    private func applySubtitleSelection() {
        guard let playerItem = player?.currentItem else { return }
        Task { [weak self, weak playerItem] in
            guard let playerItem else { return }
            do {
                guard let group = try await playerItem.asset.loadMediaSelectionGroup(for: .legible) else {
                    return
                }
                await MainActor.run {
                    guard let self else { return }
                    if self.subtitlesEnabled {
                        let option = self.selectedSubtitleOption
                            ?? self.preferredSubtitleOption(in: group)
                        if let option {
                            playerItem.select(option, in: group)
                            self.selectedSubtitleOption = option
                        }
                    } else {
                        playerItem.select(nil, in: group)
                    }
                }
            } catch {
                // Non-fatal: subtitle group failed to load.
            }
        }
    }

    private nonisolated func preferredSubtitleOption(
        in group: AVMediaSelectionGroup
    ) -> AVMediaSelectionOption? {
        let playable = AVMediaSelectionGroup.playableMediaSelectionOptions(from: group.options)
        // Prefer English if present, otherwise the first available option.
        let english = playable.first(where: { option in
            option.locale?.language.languageCode?.identifier == "en"
                || option.extendedLanguageTag?.hasPrefix("en") == true
        })
        return english ?? playable.first
    }

    // MARK: - Now Playing / Media Keys

    func setNowPlayingMetadata(title: String, channelName: String, thumbnailURL: String) {
        nowPlayingTitle = title
        nowPlayingArtist = channelName

        if thumbnailURL != nowPlayingArtworkURL {
            nowPlayingArtworkURL = thumbnailURL
            nowPlayingArtwork = nil
            loadNowPlayingArtwork(from: thumbnailURL)
        }

        updateNowPlayingPlaybackState()
    }

    private func setupRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true

        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.play() }
            return .success
        }

        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.pause() }
            return .success
        }

        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.preferredIntervals = [10]
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.seekForward(10) }
            return .success
        }

        center.skipBackwardCommand.preferredIntervals = [10]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            Task { @MainActor in self.seekBackward(10) }
            return .success
        }

        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in self.seek(to: positionEvent.positionTime) }
            return .success
        }
    }

    private func updateNowPlayingPlaybackState() {
        guard !nowPlayingTitle.isEmpty else { return }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nowPlayingTitle,
            MPMediaItemPropertyArtist: nowPlayingArtist,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue
        ]

        if duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }

        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func loadNowPlayingArtwork(from urlString: String) {
        guard let url = URL(string: urlString) else { return }
        Task { [weak self] in
            guard let data = try? await URLSession.shared.data(from: url).0,
                  let image = NSImage(data: data) else { return }
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            await MainActor.run { [weak self] in
                guard let self, self.nowPlayingArtworkURL == urlString else { return }
                self.nowPlayingArtwork = artwork
                self.updateNowPlayingPlaybackState()
            }
        }
    }
}

// MARK: - Supporting Types

enum PlaybackSpeed: Float, CaseIterable, Identifiable {
    case x0_25 = 0.25
    case x0_5 = 0.5
    case x0_75 = 0.75
    case normal = 1.0
    case x1_25 = 1.25
    case x1_5 = 1.5
    case x1_75 = 1.75
    case x2 = 2.0
    
    var id: Float { rawValue }
    
    var displayName: String {
        if self == .normal {
            return "Normal"
        }
        return "\(rawValue)x"
    }
}
