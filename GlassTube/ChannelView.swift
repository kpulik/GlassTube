import SwiftUI
import AppKit

private let channelVideoGridColumns: [GridItem] = [
    GridItem(.adaptive(minimum: 300, maximum: 300), spacing: 20, alignment: .top)
]

struct ChannelView: View {
    let channelId: String
    let initialChannelName: String
    let initialChannelAvatarURL: String?
    let onSelectVideo: (Video) -> Void

    @EnvironmentObject private var youtubeService: YouTubeService
    @EnvironmentObject private var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss

    @State private var channel: Channel?
    @State private var videos: [Video] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && videos.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.3)
                        Text("Loading channel...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage, videos.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Retry") {
                            Task {
                                await loadChannel()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            channelHeader

                            Divider()

                            if videos.isEmpty {
                                VStack(spacing: 10) {
                                    Image(systemName: "play.rectangle")
                                        .font(.system(size: 36))
                                        .foregroundStyle(.secondary)
                                    Text("No videos found for this channel")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                            } else {
                                Text("Videos")
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .padding(.horizontal, 20)

                                LazyVGrid(columns: channelVideoGridColumns, spacing: 28) {
                                    ForEach(videos) { video in
                                        VideoCardView(video: video) {
                                            dismiss()
                                            DispatchQueue.main.async {
                                                onSelectVideo(video)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.bottom, 24)
                            }
                        }
                    }
                }
            }
            .navigationTitle(displayChannel.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .automatic) {
                    Button("Open on YouTube") {
                        openChannelInBrowser()
                    }
                }
            }
        }
        .frame(minWidth: 980, minHeight: 700)
        .task(id: channelId) {
            await loadChannel()
        }
    }

    private var displayChannel: Channel {
        if let channel {
            return channel
        }

        return Channel(
            id: channelId,
            name: initialChannelName.isEmpty ? "Channel" : initialChannelName,
            handle: "",
            avatarURL: initialChannelAvatarURL,
            bannerURL: nil,
            subscriberCount: nil,
            videoCount: nil,
            description: "",
            isVerified: false
        )
    }

    private var channelHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 14) {
                if let avatar = displayChannel.avatarURL,
                   let url = URL(string: avatar),
                   !avatar.isEmpty {
                    CachedAsyncImage(url: url) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .clipShape(Circle())
                    } placeholder: {
                        Circle()
                            .fill(Color.primary.opacity(0.12))
                            .overlay {
                                ProgressView()
                                    .scaleEffect(0.65)
                            }
                    }
                    .frame(width: 72, height: 72)
                } else {
                    Circle()
                        .fill(Color.primary.opacity(0.12))
                        .frame(width: 72, height: 72)
                        .overlay {
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                        }
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(displayChannel.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        if displayChannel.isVerified {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.blue)
                        }
                    }

                    if !displayChannel.handle.isEmpty {
                        Text(displayChannel.handle)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 8) {
                        if let subscriberCount = displayChannel.subscriberCount, subscriberCount > 0 {
                            Text("\(displayChannel.formattedSubscribers) subscribers")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let videoCount = displayChannel.videoCount, videoCount > 0 {
                            Text("•")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(videoCount) videos")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()
            }

            if !displayChannel.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(displayChannel.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private func loadChannel() async {
        guard !channelId.isEmpty else {
            channel = displayChannel
            videos = []
            errorMessage = "Missing channel ID for this video."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Try without auth first — Innertube browse doesn't need auth for public channels
        // and sending an auth token can trigger quota limits from the Data API layer.
        var fetchedChannel: Channel?
        var fetchedVideos: [Video] = []
        var errors: [Error] = []

        do {
            fetchedChannel = try await youtubeService.fetchChannel(channelId: channelId)
        } catch {
            errors.append(error)
        }

        do {
            fetchedVideos = try await youtubeService.fetchChannelVideos(channelId: channelId, maxResults: 60)
        } catch {
            errors.append(error)
        }

        channel = fetchedChannel ?? displayChannel
        videos = fetchedVideos

        if videos.isEmpty, let firstError = errors.first {
            errorMessage = firstError.localizedDescription
        }
    }

    private func openChannelInBrowser() {
        if !channelId.isEmpty,
           let url = URL(string: "https://www.youtube.com/channel/\(channelId)") {
            NSWorkspace.shared.open(url)
            return
        }

        let fallbackName = displayChannel.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? displayChannel.name
        if let fallbackURL = URL(string: "https://www.youtube.com/results?search_query=\(fallbackName)") {
            NSWorkspace.shared.open(fallbackURL)
        }
    }
}
