import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var library = MediaLibrary()
    @State private var isDropTargeted = false
    @State private var zoomIndex = 3
    @State private var filterText = ""
    @State private var selectedStatus = MediaStatus(size: nil, duration: nil)
    @State private var pinnedItems: [PinnedMediaItem] = []
    @State private var pinnedThumbnails: [URL: NSImage] = [:]
    @State private var activePanel: SidePanel = .thumbnail
    @State private var thumbnailSelectionID: URL?
    @State private var isCopyingPinnedFiles = false
    @State private var isCropToolActive = false
    @State private var cropRects: [URL: NormalizedCrop] = [:]

    private let initialFolderURL: URL?
    private let zoomLevels = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    private let sidePanelRowInsets = EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
    private let topToolbarHeight: CGFloat = 48

    init(initialFolderURL: URL?) {
        self.initialFolderURL = initialFolderURL
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                thumbnailPanel
                    .frame(minWidth: 132, idealWidth: 170, maxWidth: 260)

                mainPanel
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
                                .help(folderEntry.folder.url.path)
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
                                .help(itemEntry.item.url.path)
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
                        .help("Saving Pinned Files")
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

                Button {
                    clearPinnedItems()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("Clear Pinned Files")
                .accessibilityLabel("Clear Pinned Files")

                Text("\(pinnedItems.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("\(pinnedItems.count) Pinned Files")
            }
            .frame(height: topToolbarHeight)
            .padding(.horizontal, 10)
            .background(.bar)
            .overlay(alignment: .bottom) {
                Divider()
            }

            ScrollViewReader { proxy in
                List(selection: $library.selectedID) {
                    ForEach(pinnedItems) { pinnedItem in
                        ThumbnailRow(
                            item: pinnedItem.item,
                            thumbnail: pinnedThumbnail(for: pinnedItem.item),
                            isEdited: pinnedItem.isEdited
                        )
                            .listRowInsets(sidePanelRowInsets)
                            .tag(pinnedItem.id)
                            .accessibilityLabel(pinnedItem.item.fileName)
                            .help(pinnedItem.item.url.path)
                            .onTapGesture {
                                activePanel = .pinned
                                library.selectedID = pinnedItem.id
                            }
                            .contextMenu {
                                Button("Remove from Pinned") {
                                    unpin(pinnedItem.item)
                                }
                            }
                            .task(id: pinnedItem.id) {
                                await loadPinnedThumbnailIfNeeded(for: pinnedItem.item)
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
                .help(library.folderURL?.path ?? "No Folder")
        }
        .frame(height: topToolbarHeight)
        .padding(.leading, 10)
        .padding(.trailing, 8)
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
                .help("Filter Files")

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
                .help(statusPathText)

            if !selectedStatus.detailText.isEmpty {
                Text(selectedStatus.detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(selectedStatus.detailText)
            }

            Text(statusCountText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .help(statusCountText)
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
            ?? pinnedItems.first { $0.id == selectedID }?.item
    }

    private var selectedPinnedItem: PinnedMediaItem? {
        guard activePanel == .pinned,
              let selectedID = library.selectedID
        else {
            return nil
        }
        return pinnedItems.first { $0.id == selectedID }
    }

    private var selectedCrop: NormalizedCrop {
        guard let selectedItem else { return .full }
        return cropRects[selectedItem.id]
            ?? selectedPinnedItem?.crop
            ?? .full
    }

    private var selectedAppliedCrop: NormalizedCrop {
        guard let selectedID = library.selectedID else { return .full }
        return pinnedItems.first { $0.id == selectedID }?.crop ?? .full
    }

    private var mainPanel: some View {
        VStack(spacing: 0) {
            editingToolbar
            previewPanel
        }
    }

    private var editingToolbar: some View {
        HStack(spacing: 4) {
            Button {
                isCropToolActive.toggle()
            } label: {
                Image(systemName: "crop")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil)
            .foregroundStyle(isCropToolActive ? Color.accentColor : Color.primary)
            .help("Crop Tool")
            .accessibilityLabel("Crop Tool")

            Menu {
                Button("Square 1:1") {
                    applyCropPreset(width: 1, height: 1)
                }
                Button("Portrait 4:5") {
                    applyCropPreset(width: 4, height: 5)
                }
                Button("Story/Reel 9:16") {
                    applyCropPreset(width: 9, height: 16)
                }
                Button("Landscape 16:9") {
                    applyCropPreset(width: 16, height: 9)
                }
                Button("Classic 4:3") {
                    applyCropPreset(width: 4, height: 3)
                }
                Button("Open Graph 1.91:1") {
                    applyCropPreset(width: 1.91, height: 1)
                }
            } label: {
                Image(systemName: "aspectratio")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil)
            .help("Crop Presets")
            .accessibilityLabel("Crop Presets")

            Button {
                clearSelectedCrop()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil || selectedCrop.isFullFrame)
            .help("Reset Crop")
            .accessibilityLabel("Reset Crop")

            Divider()
                .frame(height: 18)
                .padding(.horizontal, 3)

            Button {
                applySelectedCrop()
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil || selectedCrop.isFullFrame || !isCropToolActive)
            .help("Apply Crop")
            .accessibilityLabel("Apply Crop")

            Button {
                pinEditedSelectedItem()
            } label: {
                Image(systemName: "pin")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil || selectedAppliedCrop.isFullFrame)
            .help("Move Edited Media to Pinned")
            .accessibilityLabel("Move Edited Media to Pinned")

            if !selectedCrop.isFullFrame {
                Text(selectedCrop.displayLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.leading, 4)
            }

            Spacer(minLength: 0)
        }
        .frame(height: topToolbarHeight)
        .padding(.horizontal, 10)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var previewPanel: some View {
        ZStack {
            Color(nsColor: .underPageBackgroundColor)

            if let item = selectedItem {
                PreviewPane(
                    item: item,
                    zoomMultiplier: zoomLevels[zoomIndex],
                    isCropToolActive: isCropToolActive,
                    appliedCrop: selectedAppliedCrop,
                    onApplyCrop: applySelectedCrop,
                    crop: cropBinding(for: item)
                )
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
        if selectedItem != nil,
           isCropToolActive || !selectedCrop.isFullFrame {
            switch event.keyCode {
            case 36, 76:
                DispatchQueue.main.async {
                    applySelectedCrop()
                }
                return true
            case 53:
                DispatchQueue.main.async {
                    clearSelectedCrop()
                }
                return true
            default:
                break
            }
        }

        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "p" {
            pinActiveThumbnailOrPreview()
            return true
        }

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

    private func cropBinding(for item: MediaItem) -> Binding<NormalizedCrop> {
        Binding {
            cropRects[item.id] ?? selectedPinnedItem?.crop ?? .full
        } set: { newValue in
            cropRects[item.id] = newValue.clamped()
        }
    }

    private func applyCropPreset(width: CGFloat, height: CGFloat) {
        guard let item = selectedItem else { return }
        let naturalSize = selectedStatus.size ?? CGSize(width: width, height: height)
        cropRects[item.id] = NormalizedCrop.centered(
            aspectRatio: width / height,
            naturalSize: naturalSize
        )
        isCropToolActive = true
    }

    private func clearSelectedCrop() {
        guard let item = selectedItem else { return }
        cropRects[item.id] = .full
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            pinnedItems[index].crop = nil
        }
        isCropToolActive = false
    }

    private func applySelectedCrop() {
        guard let item = selectedItem else { return }
        let crop = selectedCrop.clamped()
        guard !crop.isFullFrame else { return }
        pin(item, crop: crop)
        cropRects[item.id] = crop
        isCropToolActive = false
    }

    private func pinEditedSelectedItem() {
        guard let item = selectedItem else { return }
        let crop = selectedAppliedCrop.clamped()
        guard !crop.isFullFrame else { return }
        pin(item, crop: crop)
        activePanel = .pinned
        library.selectedID = item.id
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

    private func pin(_ item: MediaItem, crop: NormalizedCrop? = nil) {
        let normalizedCrop = crop?.clamped()
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            if let normalizedCrop, !normalizedCrop.isFullFrame {
                pinnedItems[index].crop = normalizedCrop
            }
            return
        }

        pinnedItems.append(PinnedMediaItem(
            item: item,
            crop: normalizedCrop?.isFullFrame == false ? normalizedCrop : nil
        ))
        if let thumbnail = library.thumbnails[item.url] {
            pinnedThumbnails[item.url] = thumbnail
        }
    }

    private func pinActiveThumbnailOrPreview() {
        guard activePanel == .thumbnail else { return }

        if let thumbnailSelectionID,
           let item = visibleThumbnailEntries.first(where: { $0.id == thumbnailSelectionID })?.item {
            pin(item)
            return
        }

        if let selectedItem {
            pin(selectedItem)
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

    private func clearPinnedItems() {
        let removedIDs = Set(pinnedItems.map(\.id))
        pinnedItems.removeAll()
        pinnedThumbnails.removeAll()
        activePanel = .thumbnail

        guard let selectedID = library.selectedID,
              removedIDs.contains(selectedID),
              !visibleItems.contains(where: { $0.id == selectedID })
        else {
            return
        }

        library.selectedID = visibleItems.first?.id
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

    private func copyPinnedItems(_ items: [PinnedMediaItem], to destinationURL: URL) async -> PinnedCopyResult {
        await Task.detached(priority: .userInitiated) {
            var copiedCount = 0
            var failures: [String] = []
            var reservedNames = Set<String>()

            for pinnedItem in items {
                do {
                    let copyURL = uniqueCopyURL(
                        fileName: MediaExport.destinationFileName(for: pinnedItem),
                        in: destinationURL,
                        reservedNames: &reservedNames
                    )
                    try await MediaExport.export(pinnedItem, to: copyURL)
                    copiedCount += 1
                } catch {
                    failures.append("\(pinnedItem.item.fileName): \(error.localizedDescription)")
                }
            }

            return PinnedCopyResult(copiedCount: copiedCount, failures: failures)
        }.value
    }

    private func showPinnedCopyResult(_ result: PinnedCopyResult, destinationURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = result.failures.isEmpty ? .informational : .warning
        alert.messageText = result.failures.isEmpty ? "Pinned Files Saved" : "Some Pinned Files Could Not Be Saved"
        alert.informativeText = pinnedCopyInformativeText(for: result, destinationURL: destinationURL)
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func pinnedCopyInformativeText(for result: PinnedCopyResult, destinationURL: URL) -> String {
        let noun = result.copiedCount == 1 ? "file" : "files"
        var text = "Saved \(result.copiedCount) \(noun) to \(destinationURL.path)."

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

private func uniqueCopyURL(fileName sourceFileName: String, in destinationURL: URL, reservedNames: inout Set<String>) -> URL {
    let fileManager = FileManager.default
    let sourceURL = URL(fileURLWithPath: sourceFileName)
    let baseName = sourceURL.deletingPathExtension().lastPathComponent
    let pathExtension = sourceURL.pathExtension
    var index = 1

    while true {
        let fileName: String
        if index == 1 {
            fileName = sourceFileName
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
    var isEdited = false
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
            .overlay(alignment: .topLeading) {
                if isEdited {
                    Image(systemName: "crop")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.accentColor, in: Circle())
                        .padding(3)
                }
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
    let isCropToolActive: Bool
    let appliedCrop: NormalizedCrop
    let onApplyCrop: () -> Void
    @Binding var crop: NormalizedCrop

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
        let displayCrop = isCropToolActive ? NormalizedCrop.full : appliedCrop
        let sourceRect = displayCrop.pixelRect(in: naturalSize)
        let displayNaturalSize = displayCrop.isFullFrame ? naturalSize : sourceRect.size
        let baseFitScale = min(
            containerSize.width / displayNaturalSize.width,
            containerSize.height / displayNaturalSize.height
        )
        let fitScale = item.kind.shouldUpscaleToFit ? baseFitScale : min(baseFitScale, 1.0)
        let scale = max(0.08, fitScale * zoomMultiplier)
        let mediaSize = CGSize(width: displayNaturalSize.width * scale, height: displayNaturalSize.height * scale)
        let contentSize = CGSize(
            width: max(containerSize.width, mediaSize.width),
            height: max(containerSize.height, mediaSize.height)
        )

        return ScrollView([.horizontal, .vertical]) {
            ZStack {
                if item.kind == .video, !isCropToolActive {
                    NativeVideoView(
                        url: item.url,
                        crop: displayCrop,
                        displaySize: naturalSize
                    )
                    .frame(width: mediaSize.width, height: mediaSize.height)
                } else {
                    viewportedMediaView(sourceRect: sourceRect, naturalSize: naturalSize, scale: scale)
                        .frame(width: mediaSize.width, height: mediaSize.height)
                }

                if isCropToolActive {
                    CropOverlay(crop: $crop, isEditable: isCropToolActive, onApply: onApplyCrop)
                        .frame(width: mediaSize.width, height: mediaSize.height)
                }
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
            NativeVideoView(url: item.url, crop: .full, displaySize: nil)
        }
    }

    private func viewportedMediaView(sourceRect: CGRect, naturalSize: CGSize, scale: CGFloat) -> some View {
        mediaView
            .frame(width: naturalSize.width * scale, height: naturalSize.height * scale)
            .offset(x: -sourceRect.minX * scale, y: -sourceRect.minY * scale)
            .frame(width: sourceRect.width * scale, height: sourceRect.height * scale, alignment: .topLeading)
            .clipped()
    }
}

private struct CropOverlay: View {
    @Binding var crop: NormalizedCrop
    let isEditable: Bool
    let onApply: () -> Void

    @State private var activeDragStart: NormalizedCrop?

    var body: some View {
        GeometryReader { geometry in
            let cropRect = crop.rect(in: geometry.size)

            ZStack(alignment: .topLeading) {
                CropDimShape(cropRect: cropRect)
                    .fill(Color.black.opacity(0.46), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(Color.white, lineWidth: 1)
                    .background(Color.white.opacity(0.001))
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(moveGesture(in: geometry.size))
                    .allowsHitTesting(isEditable)

                Rectangle()
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .allowsHitTesting(false)

                if isEditable {
                    ForEach(CropHandle.allCases) { handle in
                        Circle()
                            .fill(Color.accentColor)
                            .stroke(Color.white, lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                            .position(handle.position(in: cropRect))
                            .gesture(resizeGesture(handle: handle, in: geometry.size))
                    }

                    if !crop.isFullFrame {
                        Button {
                            onApply()
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(Color.accentColor, in: Capsule())
                        .position(
                            x: min(max(cropRect.maxX - 38, 42), geometry.size.width - 42),
                            y: min(max(cropRect.minY + 22, 22), geometry.size.height - 22)
                        )
                        .help("Apply Crop")
                    }
                }
            }
        }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startCrop = activeDragStart ?? crop
                activeDragStart = startCrop
                crop = NormalizedCrop(
                    x: startCrop.x + value.translation.width / max(size.width, 1),
                    y: startCrop.y + value.translation.height / max(size.height, 1),
                    width: startCrop.width,
                    height: startCrop.height
                ).clamped()
            }
            .onEnded { _ in
                activeDragStart = nil
            }
    }

    private func resizeGesture(handle: CropHandle, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startCrop = activeDragStart ?? crop
                activeDragStart = startCrop
                let deltaX = value.translation.width / max(size.width, 1)
                let deltaY = value.translation.height / max(size.height, 1)
                crop = handle.resizedCrop(from: startCrop, deltaX: deltaX, deltaY: deltaY)
            }
            .onEnded { _ in
                activeDragStart = nil
            }
    }
}

private struct CropDimShape: Shape {
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cropRect)
        return path
    }
}

private enum CropHandle: CaseIterable, Identifiable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading

    var id: Self { self }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeading:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topTrailing:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .trailing:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomTrailing:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeading:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .leading:
            CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    func resizedCrop(from crop: NormalizedCrop, deltaX: CGFloat, deltaY: CGFloat) -> NormalizedCrop {
        let minimumSize = 0.04
        var minX = crop.x
        var minY = crop.y
        var maxX = crop.x + crop.width
        var maxY = crop.y + crop.height

        switch self {
        case .topLeading:
            minX += deltaX
            minY += deltaY
        case .top:
            minY += deltaY
        case .topTrailing:
            maxX += deltaX
            minY += deltaY
        case .trailing:
            maxX += deltaX
        case .bottomTrailing:
            maxX += deltaX
            maxY += deltaY
        case .bottom:
            maxY += deltaY
        case .bottomLeading:
            minX += deltaX
            maxY += deltaY
        case .leading:
            minX += deltaX
        }

        minX = min(max(minX, 0), maxX - minimumSize)
        minY = min(max(minY, 0), maxY - minimumSize)
        maxX = max(min(maxX, 1), minX + minimumSize)
        maxY = max(min(maxY, 1), minY + minimumSize)

        return NormalizedCrop(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).clamped(minimumSize: minimumSize)
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
