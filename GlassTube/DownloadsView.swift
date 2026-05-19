//
//  DownloadsView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI
import AVKit
import AppKit

struct DownloadsView: View {
    @EnvironmentObject private var downloadManager: DownloadManager

    @State private var offlinePlayerPayload: OfflinePlayerPayload?
    @State private var showingAlert = false
    @State private var alertMessage = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                downloadsToolbar

                if downloadManager.downloads.isEmpty {
                    emptyState
                } else {
                    activeSection
                    completedSection
                    missingSection
                    failedSection
                }

                Spacer(minLength: 20)
            }
        }
        .navigationTitle("Downloads")
        .onAppear {
            downloadManager.refreshMissingFiles()
        }
        .sheet(item: $offlinePlayerPayload) { payload in
            OfflinePlayerView(fileURL: payload.fileURL, title: payload.title)
        }
        .alert("Downloads", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Downloads")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("\(completedCount) item\(completedCount == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)

                Text(downloadManager.downloadsDirectoryDisplayPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            HStack(spacing: 8) {
                Button("Choose Folder") {
                    downloadManager.chooseDownloadsDirectory()
                }
                .buttonStyle(.bordered)

                Button("Open Folder") {
                    NSWorkspace.shared.open(downloadManager.downloadsDirectory)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var downloadsToolbar: some View {
        HStack(spacing: 14) {
            Button("Choose Folder") {
                downloadManager.chooseDownloadsDirectory()
            }
            .buttonStyle(.bordered)

            Button("Reset to Default") {
                downloadManager.resetDownloadsDirectory()
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 20)
    }

    private var activeSection: some View {
        let active = downloadManager.downloads.filter { $0.isDownloading }
        return Group {
            if !active.isEmpty {
                Text("Downloading")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ForEach(active) { item in
                    DownloadRow(
                        item: item,
                        onPlay: nil,
                        onDelete: {
                            downloadManager.cancelDownload(videoId: item.videoId)
                        },
                        onRetry: nil,
                        onRemoveMissing: nil
                    )
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var completedSection: some View {
        let completed = downloadManager.downloads.filter { $0.isCompleted }
        return Group {
            if !completed.isEmpty {
                if !downloadManager.downloads.filter({ $0.isDownloading }).isEmpty {
                    Text("Completed")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 20)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 280, maximum: 360), spacing: 16)],
                    spacing: 20
                ) {
                    ForEach(completed) { item in
                        DownloadCard(item: item) {
                            guard let fileURL = downloadManager.fileURL(for: item.videoId) else {
                                alertMessage = "This file is missing from disk. Remove it from the list or re-download it."
                                showingAlert = true
                                return
                            }
                            offlinePlayerPayload = OfflinePlayerPayload(fileURL: fileURL, title: item.title)
                        } onDelete: {
                            downloadManager.deleteDownload(item)
                        }
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var missingSection: some View {
        let missing = downloadManager.downloads.filter { $0.isMissingFile }
        return Group {
            if !missing.isEmpty {
                Text("Missing Files")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ForEach(missing) { item in
                    DownloadRow(
                        item: item,
                        onPlay: nil,
                        onDelete: nil,
                        onRetry: {
                            downloadManager.download(
                                videoId: item.videoId,
                                title: item.title,
                                channelName: item.channelName,
                                thumbnailURL: item.thumbnailURL
                            )
                        },
                        onRemoveMissing: {
                            downloadManager.deleteDownload(item)
                        }
                    )
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var failedSection: some View {
        let failed = downloadManager.downloads.filter {
            if case .failed = $0.status { return true }
            return false
        }
        return Group {
            if !failed.isEmpty {
                Text("Failed")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ForEach(failed) { item in
                    DownloadRow(
                        item: item,
                        onPlay: nil,
                        onDelete: {
                            downloadManager.deleteDownload(item)
                        },
                        onRetry: {
                            downloadManager.download(
                                videoId: item.videoId,
                                title: item.title,
                                channelName: item.channelName,
                                thumbnailURL: item.thumbnailURL
                            )
                        },
                        onRemoveMissing: nil
                    )
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var completedCount: Int {
        downloadManager.downloads.filter { $0.isCompleted }.count
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("No downloads yet")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Download videos to watch offline.\nUse the download button on any video.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }
}

private struct OfflinePlayerPayload: Identifiable {
    let id = UUID()
    let fileURL: URL
    let title: String
}

// MARK: - Download Card (completed videos)

struct DownloadCard: View {
    let item: DownloadItem
    let onPlay: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                CachedAsyncImage(url: URL(string: item.thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                        .clipped()
                } placeholder: {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.primary.opacity(0.1))
                        .aspectRatio(16/9, contentMode: .fit)
                }
                .cornerRadius(12)

                if isHovered {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.black.opacity(0.35))
                    Image(systemName: "play.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.white)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
            .onTapGesture(perform: onPlay)

            Text(item.title)
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(2)
                .foregroundStyle(.primary)

            if !item.channelName.isEmpty {
                Text(item.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Downloaded")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)

                Spacer()

                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.plain)
                    .font(.caption)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

// MARK: - Download Row (active/failed/missing)

struct DownloadRow: View {
    let item: DownloadItem
    let onPlay: (() -> Void)?
    let onDelete: (() -> Void)?
    let onRetry: (() -> Void)?
    let onRemoveMissing: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            CachedAsyncImage(url: URL(string: item.thumbnailURL)) { image in
                image
                    .resizable()
                    .aspectRatio(16/9, contentMode: .fill)
                    .clipped()
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.1))
                    .aspectRatio(16/9, contentMode: .fit)
            }
            .frame(width: 160, height: 90)
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(2)

                if !item.channelName.isEmpty {
                    Text(item.channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                switch item.status {
                case .downloading(let progress):
                    ProgressView(value: progress)
                        .tint(.accentColor)
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                case .failed(let error):
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)

                case .missingFile:
                    Text("File is missing from this folder.")
                        .font(.caption)
                        .foregroundStyle(.orange)

                case .completed:
                    EmptyView()
                }
            }

            Spacer()

            if let onPlay, case .completed = item.status {
                Button(action: onPlay) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if let onRetry {
                switch item.status {
                case .failed, .missingFile:
                    Button(action: onRetry) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
            }

            if let onRemoveMissing, case .missingFile = item.status {
                Button("Remove", role: .destructive, action: onRemoveMissing)
                    .buttonStyle(.plain)
                    .font(.caption)
            } else if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(0.03))
        }
    }
}

// MARK: - Offline Player

struct OfflinePlayerView: View {
    let fileURL: URL
    let title: String

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayerView(videoURL: fileURL)
                .frame(maxWidth: .infinity)

            HStack {
                Text(title)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(20)
        }
        .frame(minWidth: 640, minHeight: 480)
    }
}
