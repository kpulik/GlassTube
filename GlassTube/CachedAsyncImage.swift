//
//  CachedAsyncImage.swift
//  GlassTube
//
//  Created by Kevin Pulikkottil on 4/11/26.
//

import SwiftUI

/// A cached async image view that loads and caches thumbnails
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    
    @State private var image: Image?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image {
                content(image)
            } else {
                placeholder()
                    .task {
                        await loadImage()
                    }
            }
        }
    }
    
    private func loadImage() async {
        guard let url, image == nil, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        // Check cache first
        if let cached = ImageCache.shared.get(url: url) {
            image = cached
            return
        }
        
        do {
            if let loadedImage = try await fetchImage(from: url) {
                ImageCache.shared.set(url: url, image: loadedImage)
                image = loadedImage
                return
            }

            // Some ytimg variants are flaky; try a fallback chain by video ID.
            for fallbackURL in fallbackThumbnailURLs(for: url) where fallbackURL != url {
                if let loadedFallback = try await fetchImage(from: fallbackURL) {
                    ImageCache.shared.set(url: url, image: loadedFallback)
                    ImageCache.shared.set(url: fallbackURL, image: loadedFallback)
                    image = loadedFallback
                    return
                }
            }
        } catch {
            // Silent fail - will show placeholder
        }
    }

    private func fetchImage(from url: URL) async throws -> Image? {
        var request = URLRequest(url: url)
        request.setValue("https://www.youtube.com/", forHTTPHeaderField: "Referer")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let nsImage = NSImage(data: data) else {
            return nil
        }

        return Image(nsImage: nsImage)
    }

    private func fallbackThumbnailURLs(for url: URL) -> [URL] {
        guard let videoID = extractVideoID(from: url) else { return [] }

        let lowerPath = url.path.lowercased()
        var candidates: [String] = []

        if lowerPath.contains("/vi_webp/") || lowerPath.contains("/an_webp/") {
            candidates.append(contentsOf: [
                "https://i.ytimg.com/vi/\(videoID)/oardefault.jpg",
                "https://i.ytimg.com/vi/\(videoID)/oar2.jpg",
                "https://i.ytimg.com/vi/\(videoID)/maxresdefault.jpg",
                "https://i.ytimg.com/vi/\(videoID)/sddefault.jpg"
            ])
        }

        candidates.append("https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg")

        var urls: [URL] = []
        var seen = Set<String>()
        for candidate in candidates where seen.insert(candidate).inserted {
            if let candidateURL = URL(string: candidate) {
                urls.append(candidateURL)
            }
        }

        return urls
    }

    private func extractVideoID(from url: URL) -> String? {
        let pathComponents = url.pathComponents
        let thumbnailPathMarkers: Set<String> = ["vi", "vi_webp", "an_webp"]

        if let markerIndex = pathComponents.firstIndex(where: { thumbnailPathMarkers.contains($0.lowercased()) }) {
            let idIndex = markerIndex + 1
            if idIndex < pathComponents.count {
                return pathComponents[idIndex]
            }
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let videoID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           !videoID.isEmpty {
            return videoID
        }

        return nil
    }
}

// MARK: - Image Cache

@MainActor
class ImageCache {
    static let shared = ImageCache()
    
    private var cache: [URL: Image] = [:]
    private let maxCacheSize = 200 // Maximum number of cached images
    
    private init() {}
    
    func get(url: URL) -> Image? {
        return cache[url]
    }
    
    func set(url: URL, image: Image) {
        // Simple LRU: if cache is full, remove first item
        if cache.count >= maxCacheSize, let firstKey = cache.keys.first {
            cache.removeValue(forKey: firstKey)
        }
        cache[url] = image
    }
    
    func clear() {
        cache.removeAll()
    }
}

// MARK: - Convenience Initializer

extension CachedAsyncImage where Content == Image, Placeholder == Color {
    init(url: URL?) {
        self.url = url
        self.content = { image in image }
        self.placeholder = { Color.gray.opacity(0.2) }
    }
}
