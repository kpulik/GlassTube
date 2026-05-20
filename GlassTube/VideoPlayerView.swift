//
//  VideoPlayerView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AVKit
import AVFoundation
import AppKit
import Combine

@MainActor
final class PictureInPictureCoordinator: ObservableObject {
    fileprivate var controller: AVPictureInPictureController?
    @Published var isSupported: Bool = AVPictureInPictureController.isPictureInPictureSupported()
    @Published var isActive: Bool = false

    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else {
            controller.startPictureInPicture()
        }
    }
}

struct VideoPlayerView: View {

        @AppStorage("showLiveCaptionsInfo") private var showLiveCaptionsInfo = true
    @EnvironmentObject private var appNavigationModel: AppNavigationModel
    @StateObject private var viewModel = VideoPlayerViewModel()
    @StateObject private var pipCoordinator = PictureInPictureCoordinator()
    @State private var isHovering = false
    @State private var showingSettings = false

    let videoURL: URL
    let videoTitle: String
    let channelName: String
    let thumbnailURL: String
    let sponsorSegments: [SponsorSegment]
    let chapters: [Chapter]
    let availableQualities: [StreamQualityOption]

    init(
        videoURL: URL,
        videoTitle: String = "",
        channelName: String = "",
        thumbnailURL: String = "",
        sponsorSegments: [SponsorSegment] = [],
        chapters: [Chapter] = [],
        availableQualities: [StreamQualityOption] = []
    ) {
        self.videoURL = videoURL
        self.videoTitle = videoTitle
        self.channelName = channelName
        self.thumbnailURL = thumbnailURL
        self.sponsorSegments = sponsorSegments
        self.chapters = chapters
        self.availableQualities = availableQualities
    }
    
    var body: some View {
        VStack(spacing: 0) {
            Group {
                if appNavigationModel.isVideoFullscreen {
                    playerStage(isFullscreen: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    playerStage(isFullscreen: false)
                        .aspectRatio(16/9, contentMode: .fit)
                }
            }
            .onAppear {
                viewModel.loadVideo(url: videoURL)
                viewModel.updateSponsorSegments(sponsorSegments)
                viewModel.updateChapters(chapters)
                viewModel.setQualityOptions(availableQualities, defaultURL: videoURL)
                viewModel.setNowPlayingMetadata(title: videoTitle, channelName: channelName, thumbnailURL: thumbnailURL)
            }
            .onDisappear {
                viewModel.stopPlaybackImmediately()
            }
            .onChange(of: videoURL) { _, newURL in
                viewModel.loadVideo(url: newURL)
                viewModel.updateSponsorSegments(sponsorSegments)
                viewModel.updateChapters(chapters)
                viewModel.setQualityOptions(availableQualities, defaultURL: newURL)
                viewModel.setNowPlayingMetadata(title: videoTitle, channelName: channelName, thumbnailURL: thumbnailURL)
            }
            .onChange(of: videoTitle) { _, _ in
                viewModel.setNowPlayingMetadata(title: videoTitle, channelName: channelName, thumbnailURL: thumbnailURL)
            }
            .onChange(of: sponsorSegments) { _, newSegments in
                viewModel.updateSponsorSegments(newSegments)
            }
            .onChange(of: chapters) { _, newChapters in
                viewModel.updateChapters(newChapters)
            }
            .onChange(of: availableQualities) { _, newQualities in
                viewModel.setQualityOptions(newQualities, defaultURL: videoURL)
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeStopPlayback)) { _ in
                viewModel.stopPlaybackImmediately()
            }

            if showLiveCaptionsInfo {
                HStack(spacing: 10) {
                    Image(systemName: "captions.bubble.fill")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Need captions?")
                            .font(.caption.weight(.semibold))
                        Text("Enable Live Captions in macOS System Settings for on-device subtitles on any video.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Button("Open System Settings") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?LiveCaptions") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .font(.caption2)
                    }
                    Spacer()
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            }
        }
    }

    @ViewBuilder
    private func playerStage(isFullscreen: Bool) -> some View {
        GeometryReader { _ in
            ZStack {
                if let player = viewModel.player {
                    PlayerSurfaceView(player: player, pipCoordinator: pipCoordinator)
                } else {
                    Color.black
                        .overlay {
                            ProgressView()
                                .scaleEffect(1.5)
                                .tint(.white)
                        }
                }

                SeekGestureOverlay(viewModel: viewModel)

                VStack(spacing: 0) {
                    Spacer()

                    if viewModel.controlsVisible || isHovering || !viewModel.isPlaying {
                        PlayerControlsOverlay(
                            viewModel: viewModel,
                            pipCoordinator: pipCoordinator,
                            showingSettings: $showingSettings,
                            isFullscreen: isFullscreen,
                            isTheaterMode: appNavigationModel.isTheaterMode,
                            onToggleFullscreen: togglePlayerFullscreen,
                            onToggleTheaterMode: toggleTheaterMode
                        )
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.controlsVisible)

                if !viewModel.isPlaying && !viewModel.isBuffering {
                    CenterPlayButton(viewModel: viewModel)
                }

                if viewModel.isBuffering {
                    ProgressView()
                        .scaleEffect(2)
                        .tint(.white)
                }
            }
            .background(Color.black)
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    viewModel.showControls()
                    viewModel.cancelControlsHide()
                } else if viewModel.isPlaying {
                    viewModel.scheduleControlsHide()
                }
            }
            .onTapGesture {
                viewModel.togglePlayPause()
            }
            .focusable()
            .onKeyPress(.space) {
                viewModel.togglePlayPause()
                return .handled
            }
            .onKeyPress(.leftArrow) {
                viewModel.seekBackward()
                return .handled
            }
            .onKeyPress(.rightArrow) {
                viewModel.seekForward()
                return .handled
            }
            .onKeyPress(.upArrow) {
                viewModel.increaseVolume()
                return .handled
            }
            .onKeyPress(.downArrow) {
                viewModel.decreaseVolume()
                return .handled
            }
            .onKeyPress("m") {
                viewModel.toggleMute()
                return .handled
            }
            .onKeyPress("k") {
                viewModel.togglePlayPause()
                return .handled
            }
            .onKeyPress("j") {
                viewModel.seekBackward(10)
                return .handled
            }
            .onKeyPress("l") {
                viewModel.seekForward(10)
                return .handled
            }
            .onKeyPress("t") {
                toggleTheaterMode()
                return .handled
            }
            .onKeyPress("f") {
                togglePlayerFullscreen()
                return .handled
            }
            .onKeyPress("0") {
                viewModel.seekToPercent(0)
                return .handled
            }
            .onKeyPress("1") {
                viewModel.seekToPercent(10)
                return .handled
            }
            .onKeyPress("2") {
                viewModel.seekToPercent(20)
                return .handled
            }
            .onKeyPress("3") {
                viewModel.seekToPercent(30)
                return .handled
            }
            .onKeyPress("4") {
                viewModel.seekToPercent(40)
                return .handled
            }
            .onKeyPress("5") {
                viewModel.seekToPercent(50)
                return .handled
            }
            .onKeyPress("6") {
                viewModel.seekToPercent(60)
                return .handled
            }
            .onKeyPress("7") {
                viewModel.seekToPercent(70)
                return .handled
            }
            .onKeyPress("8") {
                viewModel.seekToPercent(80)
                return .handled
            }
            .onKeyPress("9") {
                viewModel.seekToPercent(90)
                return .handled
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubePlaybackToggle)) { _ in
                viewModel.togglePlayPause()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeSeekForward)) { _ in
                viewModel.seekForward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeSeekBackward)) { _ in
                viewModel.seekBackward()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeVolumeUp)) { _ in
                viewModel.increaseVolume()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeVolumeDown)) { _ in
                viewModel.decreaseVolume()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeToggleVideoFullscreen)) { _ in
                togglePlayerFullscreen()
            }
            .onReceive(NotificationCenter.default.publisher(for: .glassTubeToggleTheaterMode)) { _ in
                toggleTheaterMode()
            }
        }
    }

    private func togglePlayerFullscreen() {
        withAnimation(.easeInOut(duration: 0.2)) {
            appNavigationModel.isVideoFullscreen.toggle()
        }
    }

    private func toggleTheaterMode() {
        withAnimation(.easeInOut(duration: 0.2)) {
            appNavigationModel.isTheaterMode.toggle()
        }
    }
}

private struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer
    let pipCoordinator: PictureInPictureCoordinator

    func makeCoordinator() -> PiPControllerCoordinator {
        PiPControllerCoordinator(pipCoordinator: pipCoordinator)
    }

    func makeNSView(context: Context) -> PlayerSurfaceNSView {
        let view = PlayerSurfaceNSView()
        view.playerLayer.player = player
        context.coordinator.attach(to: view.playerLayer)
        return view
    }

    func updateNSView(_ nsView: PlayerSurfaceNSView, context: Context) {
        nsView.playerLayer.player = player
        context.coordinator.attach(to: nsView.playerLayer)
    }
}

@MainActor
final class PiPControllerCoordinator: NSObject, AVPictureInPictureControllerDelegate {
    private weak var pipCoordinator: PictureInPictureCoordinator?
    private var controller: AVPictureInPictureController?
    private weak var attachedLayer: AVPlayerLayer?

    init(pipCoordinator: PictureInPictureCoordinator) {
        self.pipCoordinator = pipCoordinator
        super.init()
    }

    func attach(to layer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        guard attachedLayer !== layer else { return }

        attachedLayer = layer
        let newController = AVPictureInPictureController(playerLayer: layer)
        newController?.delegate = self
        controller = newController
        pipCoordinator?.controller = newController
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.pipCoordinator?.isActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            self?.pipCoordinator?.isActive = false
        }
    }
}

private final class PlayerSurfaceNSView: NSView {
    var playerLayer: AVPlayerLayer {
        guard let layer = layer as? AVPlayerLayer else {
            let fallback = AVPlayerLayer()
            fallback.videoGravity = .resizeAspect
            self.layer = fallback
            return fallback
        }
        return layer
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspect
        self.layer = layer
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Player Controls Overlay

struct PlayerControlsOverlay: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @ObservedObject var pipCoordinator: PictureInPictureCoordinator
    @Binding var showingSettings: Bool
    let isFullscreen: Bool
    let isTheaterMode: Bool
    let onToggleFullscreen: () -> Void
    let onToggleTheaterMode: () -> Void
    
    var body: some View {
        VStack(spacing: 10) {
            // Progress bar
            VideoProgressBar(viewModel: viewModel)
                .padding(.horizontal, 8)
            
            // Controls bar
            HStack(spacing: 12) {
                // Play/Pause
                Button(action: { viewModel.seekBackward() }) {
                    Image(systemName: "gobackward.5")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.togglePlayPause() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)

                Button(action: { viewModel.seekForward() }) {
                    Image(systemName: "goforward.5")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                
                // Volume
                VolumeControl(viewModel: viewModel)
                
                // Time display
                HStack(spacing: 4) {
                    Text(formatTime(viewModel.currentTime))
                    Text("/")
                    Text(formatTime(viewModel.duration))
                }
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.9))
                .monospacedDigit()

                // Current chapter name
                if let chapter = viewModel.currentChapter {
                    Text("•")
                        .foregroundStyle(.white.opacity(0.45))
                    Text(chapter.title)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                }

                Spacer()
                
                // Settings
                Button(action: { showingSettings.toggle() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingSettings, arrowEdge: .top) {
                    SettingsPopover(viewModel: viewModel)
                }
                // Embedded HLS caption track support has been removed from the
                // player control bar — YouTube's HLS manifests rarely expose
                // legible renditions, so the in-player CC button was almost
                // always inert. Captions are now handled exclusively through
                // macOS Live Captions, surfaced via the "Need captions?"
                // panel above the player and the Settings toggle.

                if pipCoordinator.isSupported {
                    Button(action: { pipCoordinator.toggle() }) {
                        Image(systemName: pipCoordinator.isActive
                              ? "pip.exit"
                              : "pip.enter")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Picture in Picture")
                }

                Button(action: { onToggleTheaterMode() }) {
                    Image(systemName: isTheaterMode ? "rectangle.compress.vertical" : "rectangle.expand.vertical")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)

                Button(action: {
                    onToggleFullscreen()
                }) {
                    Image(systemName: isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background {
                Capsule(style: .continuous)
                    .fill(.black.opacity(0.44))
                    .overlay {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.62)
                    }
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.8)
                    }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "0:00" }
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let mins = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, mins, secs)
        }
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Video Progress Bar

struct VideoProgressBar: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @State private var isHovering = false
    @State private var isDragging = false
    @State private var dragProgress: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: isHovering || isDragging ? 6 : 4)
                
                // Played portion
                Rectangle()
                    .fill(Color.red)
                    .frame(width: geometry.size.width * progress, height: isHovering || isDragging ? 6 : 4)

                // SponsorBlock markers
                ForEach(viewModel.sponsorSegments) { segment in
                    if let range = normalizedRange(for: segment) {
                        Rectangle()
                            .fill(segment.categoryColor.opacity(0.95))
                            .frame(
                                width: markerWidth(for: range, totalWidth: geometry.size.width),
                                height: isHovering || isDragging ? 6 : 4
                            )
                            .offset(x: geometry.size.width * range.lowerBound)
                    }
                }
                .allowsHitTesting(false)

                // Chapter dividers (thin vertical lines at chapter boundaries)
                if viewModel.chapters.count > 1 {
                    ForEach(viewModel.chapters.dropFirst()) { chapter in
                        let normalized = viewModel.duration > 0 ? chapter.startTime / viewModel.duration : 0
                        Rectangle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 2, height: isHovering || isDragging ? 10 : 6)
                            .offset(x: geometry.size.width * normalized - 1)
                    }
                    .allowsHitTesting(false)
                }

                // Scrubber
                if isHovering || isDragging {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 14, height: 14)
                        .offset(x: geometry.size.width * progress - 7)
                }
            }
            .frame(height: 20)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        dragProgress = progress
                        viewModel.currentTime = progress * viewModel.duration
                    }
                    .onEnded { value in
                        isDragging = false
                        let progress = max(0, min(1, value.location.x / geometry.size.width))
                        viewModel.seek(to: progress * viewModel.duration)
                    }
            )
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovering = hovering
                }
            }
        }
        .frame(height: 20)
        .animation(.easeInOut(duration: 0.2), value: isHovering)
        .animation(.easeInOut(duration: 0.2), value: isDragging)
    }
    
    private var progress: Double {
        guard viewModel.duration > 0 else { return 0 }
        if isDragging {
            return dragProgress
        }
        return viewModel.currentTime / viewModel.duration
    }

    private func normalizedRange(for segment: SponsorSegment) -> ClosedRange<Double>? {
        guard viewModel.duration > 0 else { return nil }

        let lower = max(0, min(1, segment.startTime / viewModel.duration))
        let upper = max(0, min(1, segment.endTime / viewModel.duration))
        guard upper > lower else { return nil }

        return lower...upper
    }

    private func markerWidth(for range: ClosedRange<Double>, totalWidth: CGFloat) -> CGFloat {
        let rawWidth = totalWidth * (range.upperBound - range.lowerBound)
        return max(2, rawWidth)
    }
}

// MARK: - Volume Control

struct VolumeControl: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    
    var body: some View {
        HStack(spacing: 8) {
            Button(action: { viewModel.toggleMute() }) {
                Image(systemName: volumeIcon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)

            Slider(value: Binding(
                get: { Double(viewModel.isMuted ? 0 : viewModel.volume) },
                set: { viewModel.setVolume(Float($0)) }
            ), in: 0...1)
            .frame(width: 104)
            .tint(.white)
        }
    }
    
    private var volumeIcon: String {
        if viewModel.isMuted || viewModel.volume == 0 {
            return "speaker.slash.fill"
        } else if viewModel.volume < 0.33 {
            return "speaker.fill"
        } else if viewModel.volume < 0.66 {
            return "speaker.wave.1.fill"
        } else {
            return "speaker.wave.3.fill"
        }
    }
}

// MARK: - Center Play Button

struct CenterPlayButton: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    
    var body: some View {
        Button(action: { viewModel.play() }) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: 80, height: 80)
                
                Image(systemName: "play.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(.white)
                    .offset(x: 3)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Seek Gesture Overlay

struct SeekGestureOverlay: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @State private var showLeftIndicator = false
    @State private var showRightIndicator = false
    
    var body: some View {
        HStack(spacing: 0) {
            // Left side - seek backward
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    viewModel.seekBackward()
                    withAnimation {
                        showLeftIndicator = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        withAnimation {
                            showLeftIndicator = false
                        }
                    }
                }
                .overlay {
                    if showLeftIndicator {
                        Image(systemName: "gobackward.5")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
            
            // Center - play/pause (handled by outer tap gesture)
            Color.clear
                .frame(maxWidth: 200)
            
            // Right side - seek forward
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    viewModel.seekForward()
                    withAnimation {
                        showRightIndicator = true
                    }
                    Task {
                        try? await Task.sleep(for: .seconds(0.5))
                        withAnimation {
                            showRightIndicator = false
                        }
                    }
                }
                .overlay {
                    if showRightIndicator {
                        Image(systemName: "goforward.5")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale))
                    }
                }
        }
    }
}

// MARK: - Settings Popover

struct SettingsPopover: View {
    @ObservedObject var viewModel: VideoPlayerViewModel
    @State private var showQualityMenu = false
    @State private var showSpeedMenu = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Quality
            SettingsRow(
                icon: "video.fill",
                title: "Quality",
                value: viewModel.selectedQualityLabel,
                isExpanded: showQualityMenu
            ) {
                showQualityMenu.toggle()
                showSpeedMenu = false
            }
            
            if showQualityMenu {
                ForEach(viewModel.availableQualityOptions) { quality in
                    Button(action: {
                        viewModel.selectQuality(quality)
                        showQualityMenu = false
                    }) {
                        HStack {
                            Text(quality.label)
                                .font(.caption)
                            Spacer()
                            if quality.id == viewModel.selectedQualityOptionID {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider()
            
            // Playback Speed
            SettingsRow(
                icon: "speedometer",
                title: "Speed",
                value: PlaybackSpeed(rawValue: viewModel.playbackRate)?.displayName ?? "Normal",
                isExpanded: showSpeedMenu
            ) {
                showSpeedMenu.toggle()
                showQualityMenu = false
            }
            
            if showSpeedMenu {
                ForEach(PlaybackSpeed.allCases) { speed in
                    Button(action: {
                        viewModel.setPlaybackRate(speed.rawValue)
                        showSpeedMenu = false
                    }) {
                        HStack {
                            Text(speed.displayName)
                                .font(.caption)
                            Spacer()
                            if speed.rawValue == viewModel.playbackRate {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                            }
                        }
                        .padding(.horizontal, 32)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 220)
        .background(.ultraThinMaterial)
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String
    let isExpanded: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 20)
                Text(title)
                    .font(.body)
                Spacer()
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VideoPlayerView(videoURL: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4")!)
        .frame(height: 400)
}
