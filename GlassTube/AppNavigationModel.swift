import Foundation
import SwiftUI
import Combine

@MainActor
final class AppNavigationModel: ObservableObject {
    struct WatchTab: Identifiable, Equatable {
        let id: UUID
        let video: Video

        init(video: Video, id: UUID = UUID()) {
            self.id = id
            self.video = video
        }

        static func == (lhs: WatchTab, rhs: WatchTab) -> Bool {
            lhs.id == rhs.id
        }
    }

    @Published var watchTabs: [WatchTab] = []
    @Published var activeWatchTabID: WatchTab.ID?
    @Published var isVideoFullscreen = false
    @Published var isTheaterMode = false

    var activeWatchVideo: Video? {
        guard let activeWatchTabID else { return nil }
        return watchTabs.first(where: { $0.id == activeWatchTabID })?.video
    }

    var hasWatchTabs: Bool {
        !watchTabs.isEmpty
    }

    func open(video: Video) {
        if let existingTab = watchTabs.first(where: { $0.video.id == video.id }) {
            activeWatchTabID = existingTab.id
            return
        }

        let tab = WatchTab(video: video)
        watchTabs.append(tab)
        activeWatchTabID = tab.id
    }

    func activate(tabID: WatchTab.ID) {
        guard watchTabs.contains(where: { $0.id == tabID }) else { return }
        activeWatchTabID = tabID
    }

    func showBrowse() {
        isVideoFullscreen = false
        isTheaterMode = false
        activeWatchTabID = nil
    }

    func close(tabID: WatchTab.ID) {
        guard let index = watchTabs.firstIndex(where: { $0.id == tabID }) else { return }
        let wasActive = watchTabs[index].id == activeWatchTabID
        watchTabs.remove(at: index)

        guard wasActive else { return }

        if watchTabs.isEmpty {
            isVideoFullscreen = false
            isTheaterMode = false
            activeWatchTabID = nil
            return
        }

        let nextIndex = min(index, watchTabs.count - 1)
        activeWatchTabID = watchTabs[nextIndex].id
    }

    func closeAll() {
        isVideoFullscreen = false
        isTheaterMode = false
        watchTabs.removeAll()
        activeWatchTabID = nil
    }
}
