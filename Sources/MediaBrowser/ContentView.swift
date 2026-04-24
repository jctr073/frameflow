import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = MediaLibrary()
    @State private var isDropTargeted = false
    @State private var zoomIndex = 3
    @State private var filterText = ""
    @State private var selectedStatus = MediaStatus(size: nil, duration: nil)
    @State private var pinnedItems: [MediaItem] = []
    @State private var pinnedThumbnails: [URL: NSImage] = [:]
    @State private var activePanel: SidePanel = .thumbnail
    @State private var thumbnailSelectionID: URL?
    @State private var isCopyingPinnedFiles = false

    private let initialFolderURL: URL?
    private let zoomLevels = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    private let sidePanelRowInsets = EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)

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

                if !pinnedItems.isEmpty {
                    pinnedPanel
                        .frame(minWidth: 170, idealWidth: 230, maxWidth: 280)
                }
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
            if activePanel == .thumbnail,
               let selectedID = library.selectedID,
               visibleThumbnailEntries.contains(where: { $0.id == selectedID }) {
                thumbnailSelectionID = selectedID
            }
        }
        .task(id: library.selectedID) {
            await loadSelectedStatus()
        }
        .onChange(of: filterText) {
            selectFirstVisibleItemIfNeeded()
        }
        .onChange(of: library.thumbnailEntries) {
            selectFirstVisibleItemIfNeeded()
        }
        .onChange(of: pinnedItems) {
            if pinnedItems.isEmpty, activePanel == .pinned {
                activePanel = .thumbnail
            }
        }
    }

    private var thumbnailPanel: some View {
        VStack(spacing: 0) {
            folderHeader
            filterControl

            if visibleThumbnailEntries.isEmpty {
                Text(thumbnailEmptyMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $thumbnailSelectionID) {
                        ForEach(visibleThumbnailEntries) { entry in
                            switch entry {
                            case .folder(let folderEntry):
                                FolderRow(entry: folderEntry)
                                    .listRowInsets(sidePanelRowInsets)
                                    .tag(entry.id)
                                    .accessibilityLabel(folderEntry.folder.name)
                                    .onTapGesture {
                                        activePanel = .thumbnail
                                        thumbnailSelectionID = entry.id
                                        library.toggleFolder(folderEntry.folder)
                                    }
                            case .item(let itemEntry):
                                ThumbnailRow(
                                    item: itemEntry.item,
                                    thumbnail: library.thumbnails[itemEntry.item.url],
                                    depth: itemEntry.depth
                                )
                                .listRowInsets(sidePanelRowInsets)
                                .tag(entry.id)
                                .accessibilityLabel(itemEntry.item.fileName)
                                .onTapGesture {
                                    activePanel = .thumbnail
                                    thumbnailSelectionID = entry.id
                                    library.selectedID = itemEntry.item.id
                                }
                                .contextMenu {
                                    Button(pinMenuTitle(for: itemEntry.item)) {
                                        pin(itemEntry.item)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .overlay(panelFocusOverlay(for: .thumbnail))
                    .onChange(of: thumbnailSelectionID) {
                        guard let thumbnailSelectionID else { return }
                        withAnimation(.snappy(duration: 0.16)) {
                            proxy.scrollTo(thumbnailSelectionID, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var pinnedPanel: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Pinned")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if isCopyingPinnedFiles {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        copyPinnedFilesToFolder()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("Copy Pinned Files")
                    .accessibilityLabel("Copy Pinned Files")
                }

                Text("\(pinnedItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollViewReader { proxy in
                List(selection: $library.selectedID) {
                    ForEach(pinnedItems) { item in
                        ThumbnailRow(item: item, thumbnail: pinnedThumbnail(for: item))
                            .listRowInsets(sidePanelRowInsets)
                            .tag(item.id)
                            .accessibilityLabel(item.fileName)
                            .onTapGesture {
                                activePanel = .pinned
                                library.selectedID = item.id
                            }
                            .contextMenu {
                                Button("Remove from Pinned") {
                                    unpin(item)
                                }
                            }
                            .task(id: item.id) {
                                await loadPinnedThumbnailIfNeeded(for: item)
                            }
                    }
                }
                .listStyle(.sidebar)
                .overlay(panelFocusOverlay(for: .pinned))
                .onChange(of: library.selectedID) {
                    guard activePanel == .pinned,
                          let selectedID = library.selectedID,
                          pinnedItems.contains(where: { $0.id == selectedID })
                    else {
                        return
                    }
                    withAnimation(.snappy(duration: 0.16)) {
                        proxy.scrollTo(selectedID, anchor: .center)
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var folderHeader: some View {
        HStack(spacing: 8) {
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

            Text(library.folderURL?.lastPathComponent ?? "No Folder")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
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

    private var visibleThumbnailEntries: [ThumbnailPanelEntry] {
        let pattern = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !pattern.isEmpty else {
            return library.thumbnailEntries
        }

        return library.thumbnailEntries.filter { entry in
            entry.displayName.matchesFileFilter(pattern)
        }
    }

    private var visibleItems: [MediaItem] {
        visibleThumbnailEntries.compactMap(\.item)
    }

    private var thumbnailEmptyMessage: String {
        if !library.thumbnailEntries.isEmpty,
           !filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No files match this filter."
        }

        return library.stateMessage
    }

    private var selectedItem: MediaItem? {
        guard let selectedID = library.selectedID else { return nil }
        return library.item(withID: selectedID)
            ?? pinnedItems.first { $0.id == selectedID }
    }

    private var previewPanel: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let item = selectedItem {
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
        .contentShape(Rectangle())
        .contextMenu {
            if let item = selectedItem {
                Button(pinMenuTitle(for: item)) {
                    pin(item)
                }
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
            selectPreviousItemInActivePanel()
            return true
        case 125:
            selectNextItemInActivePanel()
            return true
        case 123:
            moveToPreviousPanel()
            return true
        case 124:
            moveToNextPanel()
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
           visibleItems.contains(where: { $0.id == selectedID })
            || pinnedItems.contains(where: { $0.id == selectedID }) {
            if activePanel == .thumbnail {
                thumbnailSelectionID = selectedID
            }
            return
        }

        if let currentSelection = thumbnailSelectionID,
           visibleThumbnailEntries.contains(where: { $0.id == currentSelection }) {
            return
        }

        thumbnailSelectionID = visibleThumbnailEntries.first?.id
        library.selectedID = visibleItems.first?.id
    }

    private func selectPreviousItemInActivePanel() {
        switch activePanel {
        case .thumbnail:
            moveThumbnailSelection(by: -1)
        case .pinned:
            movePinnedSelection(by: -1)
        }
    }

    private func selectNextItemInActivePanel() {
        switch activePanel {
        case .thumbnail:
            moveThumbnailSelection(by: 1)
        case .pinned:
            movePinnedSelection(by: 1)
        }
    }

    private func moveThumbnailSelection(by offset: Int) {
        let entries = visibleThumbnailEntries
        guard !entries.isEmpty else {
            return
        }

        let currentIndex = thumbnailSelectionID.flatMap { selectionID in
            entries.firstIndex { $0.id == selectionID }
        } ?? (offset > 0 ? -1 : entries.count)
        let nextIndex = min(max(currentIndex + offset, entries.startIndex), entries.index(before: entries.endIndex))
        activateThumbnailEntry(entries[nextIndex])
    }

    private func movePinnedSelection(by offset: Int) {
        let items = pinnedItems
        guard !items.isEmpty else {
            return
        }

        let currentIndex = library.selectedID.flatMap { selectedID in
            items.firstIndex { $0.id == selectedID }
        } ?? (offset > 0 ? -1 : items.count)
        let nextIndex = min(max(currentIndex + offset, items.startIndex), items.index(before: items.endIndex))
        library.selectedID = items[nextIndex].id
    }

    private func activateThumbnailEntry(_ entry: ThumbnailPanelEntry) {
        activePanel = .thumbnail
        thumbnailSelectionID = entry.id

        switch entry {
        case .folder(let folderEntry):
            library.expandFolder(folderEntry.folder)
        case .item(let itemEntry):
            library.selectedID = itemEntry.item.id
        }
    }

    private func moveToPreviousPanel() {
        guard activePanel == .pinned else { return }
        activePanel = .thumbnail
        if let selectedID = library.selectedID,
           visibleThumbnailEntries.contains(where: { $0.id == selectedID }) {
            thumbnailSelectionID = selectedID
            return
        }

        if let firstEntry = visibleThumbnailEntries.first {
            activateThumbnailEntry(firstEntry)
        }
    }

    private func moveToNextPanel() {
        guard activePanel == .thumbnail, !pinnedItems.isEmpty else { return }
        activePanel = .pinned
        if let selectedID = library.selectedID,
           pinnedItems.contains(where: { $0.id == selectedID }) {
            return
        }
        library.selectedID = pinnedItems.first?.id
    }

    private func pin(_ item: MediaItem) {
        guard !pinnedItems.contains(where: { $0.id == item.id }) else { return }
        pinnedItems.append(item)
        if let thumbnail = library.thumbnails[item.url] {
            pinnedThumbnails[item.url] = thumbnail
        }
    }

    private func unpin(_ item: MediaItem) {
        pinnedItems.removeAll { $0.id == item.id }
        pinnedThumbnails[item.url] = nil
        if library.selectedID == item.id {
            if activePanel == .pinned {
                library.selectedID = pinnedItems.first?.id ?? visibleItems.first?.id
            } else if !visibleItems.contains(where: { $0.id == item.id }) {
                library.selectedID = visibleItems.first?.id
            }
        }
    }

    private func pinMenuTitle(for item: MediaItem) -> String {
        pinnedItems.contains(where: { $0.id == item.id }) ? "Pinned" : "Pin File"
    }

    private func pinnedThumbnail(for item: MediaItem) -> NSImage? {
        pinnedThumbnails[item.url] ?? library.thumbnails[item.url]
    }

    private func copyPinnedFilesToFolder() {
        guard !pinnedItems.isEmpty, !isCopyingPinnedFiles else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Copy"
        panel.message = "Choose or create a folder for the pinned file copies."
        panel.directoryURL = library.folderURL

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        let itemsToCopy = pinnedItems
        isCopyingPinnedFiles = true
        Task {
            let result = await copyPinnedItems(itemsToCopy, to: destinationURL)
            isCopyingPinnedFiles = false
            showPinnedCopyResult(result, destinationURL: destinationURL)
        }
    }

    private func copyPinnedItems(_ items: [MediaItem], to destinationURL: URL) async -> PinnedCopyResult {
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            var copiedCount = 0
            var failures: [String] = []
            var reservedNames = Set<String>()

            for item in items {
                do {
                    let copyURL = uniqueCopyURL(for: item.url, in: destinationURL, reservedNames: &reservedNames)
                    try fileManager.copyItem(at: item.url, to: copyURL)
                    copiedCount += 1
                } catch {
                    failures.append("\(item.fileName): \(error.localizedDescription)")
                }
            }

            return PinnedCopyResult(copiedCount: copiedCount, failures: failures)
        }.value
    }

    private func showPinnedCopyResult(_ result: PinnedCopyResult, destinationURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = result.failures.isEmpty ? .informational : .warning
        alert.messageText = result.failures.isEmpty ? "Pinned Files Copied" : "Some Pinned Files Could Not Be Copied"
        alert.informativeText = pinnedCopyInformativeText(for: result, destinationURL: destinationURL)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func pinnedCopyInformativeText(for result: PinnedCopyResult, destinationURL: URL) -> String {
        let noun = result.copiedCount == 1 ? "file" : "files"
        var text = "Copied \(result.copiedCount) \(noun) to \(destinationURL.path)."

        if !result.failures.isEmpty {
            let shownFailures = result.failures.prefix(5).joined(separator: "\n")
            text += "\n\n\(shownFailures)"
            if result.failures.count > 5 {
                text += "\n…and \(result.failures.count - 5) more."
            }
        }

        return text
    }

    @MainActor
    private func loadPinnedThumbnailIfNeeded(for item: MediaItem) async {
        if pinnedThumbnails[item.url] != nil {
            return
        }
        if let thumbnail = library.thumbnails[item.url] {
            pinnedThumbnails[item.url] = thumbnail
            return
        }

        pinnedThumbnails[item.url] = await ThumbnailProvider.thumbnail(for: item)
    }

    @ViewBuilder
    private func panelFocusOverlay(for panel: SidePanel) -> some View {
        if activePanel == panel {
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                .padding(3)
                .allowsHitTesting(false)
        }
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
        guard let item = selectedItem else {
            selectedStatus = MediaStatus(size: nil, duration: nil)
            return
        }

        selectedStatus = await MediaMetadata.status(for: item)
    }
}

private enum SidePanel {
    case thumbnail
    case pinned
}

private struct PinnedCopyResult: Sendable {
    let copiedCount: Int
    let failures: [String]
}

private func uniqueCopyURL(for sourceURL: URL, in destinationURL: URL, reservedNames: inout Set<String>) -> URL {
    let fileManager = FileManager.default
    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    var index = 1

    while true {
        let fileName: String
        if index == 1 {
            fileName = sourceURL.lastPathComponent
        } else if pathExtension.isEmpty {
            fileName = "\(baseName) \(index)"
        } else {
            fileName = "\(baseName) \(index).\(pathExtension)"
        }

        let candidateURL = destinationURL.appendingPathComponent(fileName)
        if !reservedNames.contains(fileName),
           !fileManager.fileExists(atPath: candidateURL.path) {
            reservedNames.insert(fileName)
            return candidateURL
        }

        index += 1
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
    var depth = 0

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
        .padding(.leading, CGFloat(depth) * 18)
        .padding(.vertical, 6)
    }
}

struct FolderRow: View {
    let entry: FolderPanelEntry

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: entry.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)

            Image(systemName: entry.isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24)

            Text(entry.folder.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if entry.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
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
