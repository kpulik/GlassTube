//
//  TestVideoView.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI

/// Test view to verify YouTube API and video playback
struct TestVideoView: View {
    @StateObject private var service = YouTubeService()
    @State private var testVideoId = "jNQXAC9IVRw" // Sample video: "Me at the zoo" (first YouTube video)
    @State private var video: Video?
    @State private var streamURL: URL?
    @State private var error: String?
    @State private var isLoading = false
    @State private var showingPlayer = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("YouTube API Test")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            // Video ID input
            HStack {
                Text("Video ID:")
                TextField("Enter YouTube video ID", text: $testVideoId)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
            }
            
            // Test buttons
            HStack(spacing: 12) {
                Button("Fetch Video Details") {
                    fetchVideoDetails()
                }
                .buttonStyle(.borderedProminent)
                
                Button("Get Stream URL") {
                    fetchStreamURL()
                }
                .buttonStyle(.borderedProminent)
                .disabled(video == nil)
                
                Button("Play Video") {
                    showingPlayer = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(streamURL == nil)
            }
            
            Divider()
            
            // Loading state
            if isLoading {
                ProgressView("Loading...")
            }
            
            // Error display
            if let error {
                Text("Error: \(error)")
                    .foregroundStyle(.red)
                    .padding()
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
            
            // Video details
            if let video {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Video Details:")
                        .font(.headline)
                    
                    Group {
                        Text("Title: \(video.title)")
                        Text("Channel: \(video.channelName)")
                        Text("Views: \(video.formattedViews)")
                        Text("Duration: \(video.formattedDuration)")
                        Text("Upload: \(video.relativeTime)")
                    }
                    .font(.caption)
                    .padding(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.primary.opacity(0.05))
                .cornerRadius(8)
            }
            
            // Stream URL
            if let streamURL {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Stream URL Found!")
                        .font(.headline)
                        .foregroundStyle(.green)
                    
                    Text(streamURL.absoluteString)
                        .font(.caption2)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 600, height: 500)
        .sheet(isPresented: $showingPlayer) {
            if let streamURL, let video {
                WatchView(
                    videoURL: streamURL,
                    videoId: video.id,
                    videoTitle: video.title,
                    videoDescription: video.description,
                    channelId: video.channelId,
                    channelName: video.channelName,
                    channelAvatar: "",
                    thumbnailURL: video.thumbnailURL,
                    subscribers: "Unknown",
                    views: video.formattedViews,
                    uploadDate: video.relativeTime
                )
            }
        }
    }
    
    private func fetchVideoDetails() {
        isLoading = true
        error = nil
        video = nil
        streamURL = nil
        
        Task {
            do {
                let fetchedVideo = try await service.getVideo(id: testVideoId)
                await MainActor.run {
                    video = fetchedVideo
                    isLoading = false
                    error = nil
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
    
    private func fetchStreamURL() {
        isLoading = true
        error = nil
        streamURL = nil
        
        Task {
            do {
                let url = try await service.getStreamURL(videoId: testVideoId)
                await MainActor.run {
                    streamURL = url
                    isLoading = false
                    error = nil
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}

#Preview {
    TestVideoView()
}
