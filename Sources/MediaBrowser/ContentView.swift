import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = MediaLibrary()
    @State private var isDropTargeted = false
    @State private var zoomIndex = 3
    @State private var filterText = ""
    @State private var selectedStatus = MediaStatus(size: nil, duration: nil)

    private let initialFolderURL: URL?
    private let zoomLevels = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    init(initialFolderURL: URL?) {
        self.initialFolderURL = initialFolderURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                thumbnailPanel
                    .frame(minWidth: 132, idealWidth: 170, maxWidth: 260)

                previewPanel
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }

            statusBar
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(dropOverlay)
        .background(KeyboardMonitor(onKeyDown: handleKeyDown).frame(width: 0, height: 0))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
        .task {
            if let initialFolderURL, library.folderURL == nil {
                library.openFolder(initialFolderURL)
            }
        }
        .onAppear {
            activateAppWindow()
        }
        .onChange(of: library.selectedID) {
            zoomIndex = 3
        }
        .task(id: library.selectedID) {
            await loadSelectedStatus()
        }
        .onChange(of: filterText) {
            selectFirstVisibleItemIfNeeded()
        }
        .onChange(of: library.items) {
            selectFirstVisibleItemIfNeeded()
        }
    }

    private var thumbnailPanel: some View {
        VStack(spacing: 0) {
            folderHeader
            filterControl

            if visibleItems.isEmpty {
                Text(thumbnailEmptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $library.selectedID) {
                        ForEach(visibleItems) { item in
                            ThumbnailRow(item: item, thumbnail: library.thumbnails[item.url])
                                .tag(item.id)
                                .accessibilityLabel(item.fileName)
                        }
                    }
                    .listStyle(.sidebar)
                    .onChange(of: library.selectedID) {
                        guard let selectedID = library.selectedID else { return }
                        withAnimation(.snappy(duration: 0.16)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var folderHeader: some View {
        HStack(spacing: 8) {
            Text(library.folderURL?.lastPathComponent ?? "No Folder")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                chooseFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .help("Open Folder")
            .accessibilityLabel("Open Folder")
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var filterControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("Filter files", text: $filterText)
                .textFieldStyle(.plain)
                .font(.caption)

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear Filter")
                .accessibilityLabel("Clear Filter")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Button {
                chooseFolder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .help("Open Folder")
            .accessibilityLabel("Open Folder")

            Button {
                openTerminalAtCurrentFolder()
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .disabled(library.folderURL == nil)
            .help("Open Terminal Here")
            .accessibilityLabel("Open Terminal Here")

            Text(statusPathText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !selectedStatus.detailText.isEmpty {
                Text(selectedStatus.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(statusCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(height: 28)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private var statusPathText: String {
        guard let folderURL = library.folderURL else {
            return "No folder open"
        }

        return folderURL.path
    }

    private var statusCountText: String {
        let count = library.items.count
        let noun = count == 1 ? "file" : "files"
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(count) \(noun)"
        }

        let visibleCount = visibleItems.count
        return "\(visibleCount) of \(count) \(noun)"
    }

    private var visibleItems: [MediaItem] {
        let pattern = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return library.items
        }

        return library.items.filter { item in
            item.fileName.matchesFileFilter(pattern)
        }
    }

    private var thumbnailEmptyMessage: String {
        if !library.items.isEmpty,
           !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No files match this filter."
        }

        return library.stateMessage
    }

    private var previewPanel: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let item = library.selectedItem {
                PreviewPane(item: item, zoomMultiplier: zoomLevels[zoomIndex])
                    .id(item.id)
            } else {
                Text(library.stateMessage)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.accentColor, lineWidth: 3)
                .padding(10)
                .allowsHitTesting(false)
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"

        if panel.runModal() == .OK, let url = panel.url {
            library.openFolder(url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let data = item as? Data,
               let string = String(data: data, encoding: .utf8) {
                url = URL(string: string)
            } else {
                url = item as? URL
            }

            guard let url else { return }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return
            }

            Task { @MainActor in
                library.openFolder(url)
            }
        }
        return true
    }

    private func handleKeyDown(_ event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "+", "=":
                zoomIn()
                return true
            case "-":
                zoomOut()
                return true
            default:
                return false
            }
        }

        switch event.keyCode {
        case 126:
            selectPreviousVisibleItem()
            return true
        case 125:
            selectNextVisibleItem()
            return true
        default:
            return false
        }
    }

    private func zoomIn() {
        zoomIndex = min(zoomIndex + 1, zoomLevels.index(before: zoomLevels.endIndex))
    }

    private func zoomOut() {
        zoomIndex = max(zoomIndex - 1, zoomLevels.startIndex)
    }

    private func selectFirstVisibleItemIfNeeded() {
        if let selectedID = library.selectedID,
           visibleItems.contains(where: { $0.id == selectedID }) {
            return
        }

        library.selectedID = visibleItems.first?.id
    }

    private func selectPreviousVisibleItem() {
        guard let selectedID = library.selectedID,
              let index = visibleItems.firstIndex(where: { $0.id == selectedID }),
              index > 0
        else {
            return
        }
        library.selectedID = visibleItems[index - 1].id
    }

    private func selectNextVisibleItem() {
        guard let selectedID = library.selectedID,
              let index = visibleItems.firstIndex(where: { $0.id == selectedID }),
              index < visibleItems.index(before: visibleItems.endIndex)
        else {
            return
        }
        library.selectedID = visibleItems[index + 1].id
    }

    private func openTerminalAtCurrentFolder() {
        guard let folderURL = library.folderURL else { return }

        let terminalURL = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open([folderURL], withApplicationAt: terminalURL, configuration: configuration)
    }

    private func activateAppWindow() {
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.title = "MediaBrowser"
                window.titleVisibility = .hidden
                if let titlebar = window.standardWindowButton(.closeButton)?.superview {
                    let titleLabelTag = 901_202
                    let label: NSTextField
                    if let existing = titlebar.viewWithTag(titleLabelTag) as? NSTextField {
                        label = existing
                    } else {
                        label = NSTextField(labelWithString: "MediaBrowser")
                        label.tag = titleLabelTag
                        label.font = .systemFont(ofSize: 13, weight: .semibold)
                        label.textColor = .labelColor
                        label.alignment = .center
                        titlebar.addSubview(label)
                    }
                    label.translatesAutoresizingMaskIntoConstraints = false
                    NSLayoutConstraint.activate([
                        label.centerXAnchor.constraint(equalTo: titlebar.centerXAnchor),
                        label.centerYAnchor.constraint(equalTo: titlebar.centerYAnchor)
                    ])
                }
                window.makeKeyAndOrderFront(nil)
            }
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    private func loadSelectedStatus() async {
        guard let item = library.selectedItem else {
            selectedStatus = MediaStatus(size: nil, duration: nil)
            return
        }

        selectedStatus = await MediaMetadata.status(for: item)
    }
}

private extension String {
    func matchesFileFilter(_ pattern: String) -> Bool {
        if pattern.contains("*") || pattern.contains("?") {
            return range(of: wildcardRegex(for: pattern), options: [.regularExpression, .caseInsensitive]) != nil
        }

        return localizedCaseInsensitiveContains(pattern)
    }

    private func wildcardRegex(for pattern: String) -> String {
        var regex = "^"
        for character in pattern {
            switch character {
            case "*":
                regex += ".*"
            case "?":
                regex += "."
            default:
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
        }
        regex += "$"
        return regex
    }
}

struct ThumbnailRow: View {
    let item: MediaItem
    let thumbnail: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 112, height: 78)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .background {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color(nsColor: .quaternaryLabelColor))
                }

                Text(item.kind.label)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.thinMaterial, in: Capsule())
                    .padding(3)
            }

            Text(item.fileName)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(width: 116)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

struct PreviewPane: View {
    let item: MediaItem
    let zoomMultiplier: Double

    @State private var naturalSize: CGSize?
    @State private var failedToLoad = false

    var body: some View {
        GeometryReader { geometry in
            if failedToLoad {
                Text("This file could not be loaded.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let naturalSize, naturalSize.width > 0, naturalSize.height > 0 {
                fittedMedia(in: geometry.size, naturalSize: naturalSize)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) {
            naturalSize = nil
            failedToLoad = false
            if let size = await MediaSizing.naturalSize(for: item) {
                naturalSize = size
            } else {
                failedToLoad = true
            }
        }
    }

    private func fittedMedia(in containerSize: CGSize, naturalSize: CGSize) -> some View {
        let baseFitScale = min(
            containerSize.width / naturalSize.width,
            containerSize.height / naturalSize.height
        )
        let fitScale = item.kind.shouldUpscaleToFit ? baseFitScale : min(baseFitScale, 1.0)
        let scale = max(0.08, fitScale * zoomMultiplier)
        let mediaSize = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let contentSize = CGSize(
            width: max(containerSize.width, mediaSize.width),
            height: max(containerSize.height, mediaSize.height)
        )

        return ScrollView([.horizontal, .vertical]) {
            ZStack {
                mediaView
                    .frame(width: mediaSize.width, height: mediaSize.height)
                    .clipped()
            }
            .frame(width: contentSize.width, height: contentSize.height)
        }
    }

    @ViewBuilder
    private var mediaView: some View {
        switch item.kind {
        case .image:
            StaticImagePreview(url: item.url)
        case .gif:
            NativeImageView(url: item.url, animates: true)
        case .webp:
            NativeWebImageView(url: item.url)
        case .video:
            NativeVideoView(url: item.url)
        }
    }
}

struct StaticImagePreview: View {
    let url: URL
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            image = await Task.detached(priority: .userInitiated) {
                NSImage(contentsOf: url)
            }.value
        }
    }
}
