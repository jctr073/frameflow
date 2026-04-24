import AppKit
import Foundation
import QuickLookThumbnailing

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published private(set) var items: [MediaItem] = []
    @Published var selectedID: MediaItem.ID?
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private var loadTask: Task<Void, Never>?
    private var thumbnailTasks: [URL: Task<Void, Never>] = [:]

    var selectedItem: MediaItem? {
        guard let selectedID else { return nil }
        return items.first { $0.id == selectedID }
    }

    var stateMessage: String {
        if isLoading {
            return "Loading media..."
        }
        if let loadError {
            return loadError
        }
        if folderURL == nil {
            return "Open a folder to browse media."
        }
        return "No supported media files found in this folder."
    }

    deinit {
        loadTask?.cancel()
        for task in thumbnailTasks.values {
            task.cancel()
        }
    }

    func openFolder(_ url: URL) {
        loadTask?.cancel()
        for task in thumbnailTasks.values {
            task.cancel()
        }
        thumbnailTasks.removeAll()

        folderURL = url
        items = []
        selectedID = nil
        thumbnails = [:]
        isLoading = true
        loadError = nil

        loadTask = Task {
            do {
                let discovered = try await Self.scanFolder(url)
                guard !Task.isCancelled else { return }
                items = discovered
                selectedID = discovered.first?.id
                isLoading = false
                startThumbnailGeneration(for: discovered)
            } catch {
                guard !Task.isCancelled else { return }
                items = []
                selectedID = nil
                isLoading = false
                loadError = "This folder could not be loaded."
            }
        }
    }

    func selectPrevious() {
        guard let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID }),
              index > 0
        else {
            return
        }
        self.selectedID = items[index - 1].id
    }

    func selectNext() {
        guard let selectedID,
              let index = items.firstIndex(where: { $0.id == selectedID }),
              index < items.index(before: items.endIndex)
        else {
            return
        }
        self.selectedID = items[index + 1].id
    }

    private static func scanFolder(_ url: URL) async throws -> [MediaItem] {
        try await Task.detached(priority: .userInitiated) {
            let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            )

            return urls.compactMap { fileURL -> MediaItem? in
                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                      values.isRegularFile == true,
                      values.isHidden != true,
                      let kind = MediaItem.kind(for: fileURL)
                else {
                    return nil
                }
                return MediaItem(id: fileURL, url: fileURL, kind: kind)
            }
            .sorted {
                $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
            }
        }.value
    }

    private func startThumbnailGeneration(for items: [MediaItem]) {
        for item in items {
            let task = Task {
                let image = await ThumbnailProvider.thumbnail(for: item)
                guard !Task.isCancelled else { return }
                thumbnails[item.url] = image
            }
            thumbnailTasks[item.url] = task
        }
    }
}

enum ThumbnailProvider {
    static func thumbnail(for item: MediaItem) async -> NSImage {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: item.url,
            size: CGSize(width: 112, height: 80),
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return NSWorkspace.shared.icon(forFile: item.url.path)
        }
    }
}
