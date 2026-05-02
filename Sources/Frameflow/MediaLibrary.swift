import AppKit
import Foundation
import ImageIO
import QuickLookThumbnailing

@MainActor
final class MediaLibrary: ObservableObject {
    @Published private(set) var folderURL: URL?
    @Published var selectedID: MediaItem.ID?
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?
    @Published private(set) var rootContent = FolderContents()
    @Published private(set) var folderContents: [URL: FolderContents] = [:]
    @Published private(set) var expandedFolderURLs: Set<URL> = []
    @Published private(set) var loadingFolderURLs: Set<URL> = []

    private var loadTask: Task<Void, Never>?
    private var folderLoadTasks: [URL: Task<Void, Never>] = [:]
    private var thumbnailTasks: [URL: Task<Void, Never>] = [:]

    var items: [MediaItem] {
        thumbnailEntries.compactMap(\.item)
    }

    var thumbnailEntries: [ThumbnailPanelEntry] {
        entries(in: rootContent, depth: 0)
    }

    var selectedItem: MediaItem? {
        guard let selectedID else { return nil }
        return item(withID: selectedID)
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
        return "No supported media files or subfolders found in this folder."
    }

    deinit {
        loadTask?.cancel()
        for task in folderLoadTasks.values {
            task.cancel()
        }
        for task in thumbnailTasks.values {
            task.cancel()
        }
    }

    func openFolder(_ url: URL) {
        loadTask?.cancel()
        for task in folderLoadTasks.values {
            task.cancel()
        }
        for task in thumbnailTasks.values {
            task.cancel()
        }
        folderLoadTasks.removeAll()
        thumbnailTasks.removeAll()

        folderURL = url
        rootContent = FolderContents()
        folderContents = [:]
        expandedFolderURLs = []
        loadingFolderURLs = []
        selectedID = nil
        thumbnails = [:]
        isLoading = true
        loadError = nil

        loadTask = Task {
            do {
                let discovered = try await Self.scanFolder(url)
                guard !Task.isCancelled else { return }
                rootContent = discovered
                selectedID = discovered.items.first?.id
                isLoading = false
                startThumbnailGeneration(for: discovered.items)
            } catch {
                guard !Task.isCancelled else { return }
                rootContent = FolderContents()
                folderContents = [:]
                expandedFolderURLs = []
                loadingFolderURLs = []
                selectedID = nil
                isLoading = false
                loadError = "This folder could not be loaded."
            }
        }
    }

    func item(withID id: MediaItem.ID) -> MediaItem? {
        if let item = rootContent.items.first(where: { $0.id == id }) {
            return item
        }

        for contents in folderContents.values {
            if let item = contents.items.first(where: { $0.id == id }) {
                return item
            }
        }

        return nil
    }

    func expandFolder(_ folder: MediaFolder) {
        expandedFolderURLs.insert(folder.url)
        loadFolderIfNeeded(folder)
    }

    func toggleFolder(_ folder: MediaFolder) {
        if expandedFolderURLs.contains(folder.url) {
            expandedFolderURLs.remove(folder.url)
        } else {
            expandFolder(folder)
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

    private static func scanFolder(_ url: URL) async throws -> FolderContents {
        try await Task.detached(priority: .userInitiated) {
            let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .isHiddenKey, .isPackageKey, .isRegularFileKey]
            let urls = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            )

            var folders: [MediaFolder] = []
            var items: [MediaItem] = []

            for fileURL in urls {
                guard let values = try? fileURL.resourceValues(forKeys: resourceKeys),
                      values.isHidden != true
                else {
                    continue
                }

                if values.isDirectory == true, values.isPackage != true {
                    folders.append(MediaFolder(id: fileURL, url: fileURL))
                    continue
                }

                if values.isRegularFile == true,
                   let kind = MediaItem.kind(for: fileURL) {
                    items.append(MediaItem(id: fileURL, url: fileURL, kind: kind))
                }
            }

            return FolderContents(
                folders: folders.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                },
                items: items.sorted {
                    $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending
                }
            )
        }.value
    }

    private func loadFolderIfNeeded(_ folder: MediaFolder) {
        guard folderContents[folder.url] == nil,
              folderLoadTasks[folder.url] == nil
        else {
            return
        }

        loadingFolderURLs.insert(folder.url)
        folderLoadTasks[folder.url] = Task {
            do {
                let contents = try await Self.scanFolder(folder.url)
                guard !Task.isCancelled else { return }
                folderContents[folder.url] = contents
                loadingFolderURLs.remove(folder.url)
                folderLoadTasks[folder.url] = nil
                startThumbnailGeneration(for: contents.items)
            } catch {
                guard !Task.isCancelled else { return }
                folderContents[folder.url] = FolderContents()
                loadingFolderURLs.remove(folder.url)
                folderLoadTasks[folder.url] = nil
            }
        }
    }

    private func startThumbnailGeneration(for items: [MediaItem]) {
        for item in items {
            guard thumbnails[item.url] == nil,
                  thumbnailTasks[item.url] == nil
            else {
                continue
            }

            let task = Task {
                let image = await ThumbnailProvider.thumbnail(for: item)
                guard !Task.isCancelled else { return }
                thumbnails[item.url] = image
                thumbnailTasks[item.url] = nil
            }
            thumbnailTasks[item.url] = task
        }
    }

    private func entries(in content: FolderContents, depth: Int) -> [ThumbnailPanelEntry] {
        var entries: [ThumbnailPanelEntry] = []

        for folder in content.folders {
            let isExpanded = expandedFolderURLs.contains(folder.url)
            entries.append(.folder(
                FolderPanelEntry(
                    folder: folder,
                    depth: depth,
                    isExpanded: isExpanded,
                    isLoading: loadingFolderURLs.contains(folder.url)
                )
            ))

            if isExpanded, let childContent = folderContents[folder.url] {
                entries.append(contentsOf: self.entries(in: childContent, depth: depth + 1))
            }
        }

        entries.append(contentsOf: content.items.map { .item(ItemPanelEntry(item: $0, depth: depth)) })
        return entries
    }
}

struct FolderContents: Hashable, Sendable {
    var folders: [MediaFolder] = []
    var items: [MediaItem] = []
}

struct MediaFolder: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL

    var name: String {
        url.lastPathComponent
    }
}

struct FolderPanelEntry: Identifiable, Hashable {
    var id: URL { folder.id }
    let folder: MediaFolder
    let depth: Int
    let isExpanded: Bool
    let isLoading: Bool
}

struct ItemPanelEntry: Identifiable, Hashable {
    var id: URL { item.id }
    let item: MediaItem
    let depth: Int
}

enum ThumbnailPanelEntry: Identifiable, Hashable {
    case folder(FolderPanelEntry)
    case item(ItemPanelEntry)

    var id: URL {
        switch self {
        case .folder(let entry):
            entry.id
        case .item(let entry):
            entry.id
        }
    }

    var item: MediaItem? {
        switch self {
        case .folder:
            nil
        case .item(let entry):
            entry.item
        }
    }

    var displayName: String {
        switch self {
        case .folder(let entry):
            entry.folder.name
        case .item(let entry):
            entry.item.fileName
        }
    }
}

enum ThumbnailProvider {
    private static let thumbnailSize = CGSize(width: 112, height: 80)

    static func thumbnail(for item: MediaItem) async -> NSImage {
        switch item.kind {
        case .image, .gif, .webp:
            return await rasterThumbnail(for: item.url)
                ?? NSWorkspace.shared.icon(forFile: item.url.path)
        case .video:
            return await quickLookThumbnail(for: item.url)
                ?? NSWorkspace.shared.icon(forFile: item.url.path)
        }
    }

    private static func rasterThumbnail(for url: URL) async -> NSImage? {
        await Task.detached(priority: .userInitiated) {
            let sourceOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false
            ]
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: max(thumbnailSize.width, thumbnailSize.height) * 2
            ]

            if let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary),
               let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary) {
                return NSImage(
                    cgImage: cgImage,
                    size: CGSize(width: cgImage.width, height: cgImage.height)
                )
            }

            return NSImage(contentsOf: url)
        }.value
    }

    private static func quickLookThumbnail(for url: URL) async -> NSImage? {
        let scale = await MainActor.run {
            NSScreen.main?.backingScaleFactor ?? 2
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: thumbnailSize,
            scale: scale,
            representationTypes: .thumbnail
        )

        do {
            let representation = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            return representation.nsImage
        } catch {
            return nil
        }
    }
}
