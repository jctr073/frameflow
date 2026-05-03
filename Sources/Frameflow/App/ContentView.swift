import AppKit
import FrameflowCore
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.editorTheme) private var theme
    @StateObject private var library = MediaLibrary()
    @ObservedObject private var mainPanelState: MainPanelState
    @State private var isDropTargeted = false
    @State private var zoomIndex = 3
    @State private var filterText = ""
    @State private var selectedStatus = MediaStatus(size: nil, duration: nil)
    @State private var pinnedItems: [PinnedMediaItem] = []
    @State private var pinnedThumbnails: [URL: NSImage] = [:]
    @State private var editorClips: [EditorClip] = []
    @State private var selectedEditorClipID: EditorClip.ID?
    @State private var timelineClips: [EditorTimelineClip] = []
    @State private var selectedTimelineClipID: EditorTimelineClip.ID?
    @State private var adjustmentSpans: [TimelineAdjustmentSpan] = []
    @State private var selectedAdjustmentSpanID: TimelineAdjustmentSpan.ID?
    @State private var draggingTimelineClipID: EditorTimelineClip.ID?
    @State private var editorPlayerTime: TimeInterval = 0
    @State private var timelinePlaybackTime: TimeInterval = 0
    @State private var timelineSeekRequest: TimelinePlaybackSeekRequest?
    @State private var previewPlaybackToggleRequest: PlaybackToggleRequest?
    @State private var playerPlaybackToggleRequest: PlaybackToggleRequest?
    @State private var playerZoomMultiplier = 1.0
    @State private var isPlayerFillMode = false
    @State private var isTimelineDropTargeted = false
    @State private var timelineZoom = 1.75
    @State private var timelineRulerWidth: CGFloat = 0
    @State private var autoZoomedTimelineClipID: EditorTimelineClip.ID?
    @State private var timelinePlayheadDragStartTime: TimeInterval?
    @State private var isExportingTimeline = false
    @State private var activePanel: SidePanel = .thumbnail
    @State private var showThumbnailPanel: Bool = true
    @State private var showPinnedPanel: Bool = true
    private let collapsedPanelWidth: CGFloat = 44
    @State private var thumbnailSelectionIDs: Set<URL> = []
    @State private var thumbnailSelectionAnchorID: URL?
    @State private var isCopyingPinnedFiles = false
    @State private var isCropToolActive = false
    @State private var isPlayerCropToolActive = false
    @State private var isTrimToolActive = false
    @State private var isCapturingSnapshot = false
    @State private var previewVideoTime: TimeInterval = 0
    @State private var cropRects: [URL: NormalizedCrop] = [:]
    @State private var adjustmentCropDraft = NormalizedCrop.full
    @State private var trimRanges: [URL: MediaTrim] = [:]
    @State private var appliedCrops: [URL: NormalizedCrop] = [:]
    @State private var appliedTrims: [URL: MediaTrim] = [:]

    private let initialFolderURL: URL?
    private let zoomLevels = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    private let playerZoomRange = 0.25...4.0
    private let playerZoomStep = 0.25
    private let sidePanelRowInsets = EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
    private let topToolbarHeight: CGFloat = 48
    private let timelineBasePixelsPerSecond: CGFloat = 12
    private let timelineRulerHeight: CGFloat = 34
    private let timelineAdjustmentLayerHeight: CGFloat = 44
    private let timelineVideoTrackHeight: CGFloat = 84
    private let timelineTrackHeaderWidth: CGFloat = 64
    private let timelineRulerLabelTrailingPadding: CGFloat = 72
    private let timelineZoomRange = 0.05...12.0
    private let timelinePlayheadColor = Color(red: 0.96, green: 0.30, blue: 0.10)
    private let timelineSelectionOutlineColor = Color(red: 0.86, green: 0.42, blue: 0.08)
    private let timelinePlayheadHandleSize = CGSize(width: 14, height: 16)
    private let timelinePlayheadHitWidth: CGFloat = 32

    init(initialFolderURL: URL?, mainPanelState: MainPanelState) {
        self.initialFolderURL = initialFolderURL
        self.mainPanelState = mainPanelState
    }

    var body: some View {
        VStack(spacing: 0) {
            mainPanelTabBar

            activeWorkbench
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            statusBar
        }
        .padding(6)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(theme.windowBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .tint(theme.accent)
        .accentColor(theme.accent)
        .preferredColorScheme(.dark)
        .overlay(dropOverlay)
        .quickTooltipOverlay()
        .background(KeyboardMonitor(onKeyDown: handleKeyDown).frame(width: 0, height: 0))
        .background(SplitViewResizeCursorInstaller().frame(width: 0, height: 0))
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTargeted, perform: handleDrop)
        .task {
            if let initialFolderURL, library.folderURL == nil {
                library.openFolder(initialFolderURL)
            }
        }
        .onAppear {
            activateAppWindow()
        }
        .onChange(of: theme.id) {
            activateAppWindow()
        }
        .onChange(of: library.selectedID) {
            zoomIndex = 3
            previewVideoTime = 0
            if activePanel == .thumbnail,
               let selectedID = library.selectedID,
               visibleThumbnailEntries.contains(where: { $0.id == selectedID }) {
                if !thumbnailSelectionIDs.contains(selectedID) {
                    thumbnailSelectionIDs = [selectedID]
                }
                thumbnailSelectionAnchorID = selectedID
            }
            if selectedItem?.kind != .video && selectedItem?.kind != .gif {
                isTrimToolActive = false
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
        .onChange(of: mainPanelState.activeTab) {
            switch mainPanelState.activeTab {
            case .preview:
                showThumbnailPanel = true
                showPinnedPanel = true
            case .videoComposer:
                showThumbnailPanel = false
                showPinnedPanel = false
            }
        }
    }

    private var thumbnailPanel: some View {
        VStack(spacing: 0) {
            panelHeader {
                Button {
                    showThumbnailPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showThumbnailPanel ? theme.primaryText : theme.secondaryText)
                .quickTooltip(showThumbnailPanel ? "Hide Folders Panel" : "Show Folders Panel")
                .accessibilityLabel(showThumbnailPanel ? "Hide Folders Panel" : "Show Folders Panel")

                if showThumbnailPanel {
                    Button {
                        chooseFolder()
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("o", modifiers: .command)
                    .quickTooltip("Open Folder")
                    .accessibilityLabel("Open Folder")

                    headerFilterControl
                }
            }

            if !showThumbnailPanel {
                Spacer(minLength: 0)
            } else {
                thumbnailBatchControl

                if visibleThumbnailEntries.isEmpty {
                Text(thumbnailEmptyMessage)
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollViewReader { proxy in
                    List(selection: $thumbnailSelectionIDs) {
                        ForEach(visibleThumbnailEntries) { entry in
                            switch entry {
                            case .folder(let folderEntry):
                                FolderRow(entry: folderEntry)
                                    .listRowInsets(sidePanelRowInsets)
                                    .tag(entry.id)
                                .accessibilityLabel(folderEntry.folder.name)
                                .help(folderEntry.folder.url.path)
                                .onTapGesture {
                                    handleThumbnailEntryTap(entry)
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
                                    handleThumbnailEntryTap(entry)
                                }
                                .contextMenu {
                                    let contextItems = thumbnailContextItems(for: itemEntry.item)

                                    Button(editorClipMenuTitle(for: contextItems)) {
                                        addToEditorClips(contextItems)
                                    }

                                    Button(timelineClipMenuTitle(for: contextItems)) {
                                        addToTimeline(contextItems, activateComposer: false)
                                    }

                                    Button(pinMenuTitle(for: contextItems)) {
                                        pin(contextItems)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(theme.panelBackground)
                    .onChange(of: thumbnailSelectionIDs) {
                        guard let thumbnailSelectionID = primaryThumbnailSelectionID else { return }
                        withAnimation(.snappy(duration: 0.16)) {
                            proxy.scrollTo(thumbnailSelectionID, anchor: .center)
                        }
                    }
                }
            }
            }
        }
        .background(theme.panelBackground)
    }

    private func panelHeader<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 6) {
            content()
        }
        .frame(height: 30)
        .padding(.horizontal, 10)
        .foregroundStyle(theme.primaryText)
        .background(theme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private func panelColumnHeader<Actions: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        panelHeader {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 0)

            actions()

            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.mutedText)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var thumbnailBatchControl: some View {
        let selectedItems = selectedThumbnailItems
        if selectedItems.count > 1 {
            HStack(spacing: 8) {
                Text("\(selectedItems.count) selected")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button {
                    addToEditorClips(selectedItems)
                } label: {
                    Image(systemName: "film.stack")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .quickTooltip("Show in Clips")
                .accessibilityLabel("Show in Clips")

                Button {
                    pin(selectedItems)
                } label: {
                    Image(systemName: "pin")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .quickTooltip("Pin Files")
                .accessibilityLabel("Pin Files")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(theme.primaryText)
            .background(theme.panelBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 1)
            }
        }
    }

    private var pinnedPanel: some View {
        VStack(spacing: 0) {
            panelHeader {
                if showPinnedPanel {
                    Text("Pinned")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if showPinnedPanel {
                    if isCopyingPinnedFiles {
                        ProgressView()
                            .controlSize(.small)
                            .quickTooltip("Saving Pinned Files")
                    } else {
                        Button {
                            copyPinnedFilesToFolder()
                        } label: {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .quickTooltip("Copy Pinned Files")
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
                    .disabled(pinnedItems.isEmpty)
                    .quickTooltip("Clear Pinned Files")
                    .accessibilityLabel("Clear Pinned Files")

                    Text("\(pinnedItems.count)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.mutedText)
                        .lineLimit(1)
                }

                Button {
                    showPinnedPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showPinnedPanel ? theme.primaryText : theme.secondaryText)
                .quickTooltip(showPinnedPanel ? "Hide Pinned Panel" : "Show Pinned Panel")
                .accessibilityLabel(showPinnedPanel ? "Hide Pinned Panel" : "Show Pinned Panel")
            }

            if !showPinnedPanel {
                Spacer(minLength: 0)
            } else if pinnedItems.isEmpty {
                Text("No pinned files.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
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
                    .scrollContentBackground(.hidden)
                    .background(theme.panelBackground)
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
        }
        .background(theme.panelBackground)
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
            .quickTooltip("Open Folder")
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
        .foregroundStyle(theme.primaryText)
        .background(theme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var filterControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)

            TextField("Filter files", text: $filterText)
                .textFieldStyle(.plain)
                .font(.caption)
                .quickTooltip("Filter Files")

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .quickTooltip("Clear Filter")
                .accessibilityLabel("Clear Filter")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .foregroundStyle(theme.primaryText)
        .background(theme.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var headerFilterControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)

            TextField("Filter files", text: $filterText)
                .textFieldStyle(.plain)
                .font(.caption)
                .quickTooltip("Filter Files")

            if !filterText.isEmpty {
                Button {
                    filterText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .quickTooltip("Clear Filter")
                .accessibilityLabel("Clear Filter")
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .frame(height: 22)
        .foregroundStyle(theme.primaryText)
        .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 5))
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Button {
                chooseFolder()
            } label: {
                Image(systemName: "tray.and.arrow.up")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
            .quickTooltip("Open Folder")
            .accessibilityLabel("Open Folder")

            Button {
                openTerminalAtCurrentFolder()
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(library.folderURL == nil)
            .quickTooltip("Open Terminal Here")
            .accessibilityLabel("Open Terminal Here")

            Circle()
                .fill(theme.accent)
                .frame(width: 10, height: 10)

            Text(statusPathText)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(statusPathText)

            Text(statusOpenFolderFileCount)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .help(statusOpenFolderFileCount)

            Text("·")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.mutedText)

            Text(statusClipCount)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .help(statusClipCount)

            if !statusTimelineDuration.isEmpty {
                Text("·")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.mutedText)

                Text(statusTimelineDuration)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .help(statusTimelineDuration)
            }
        }
        .frame(height: 36)
        .padding(.leading, 18)
        .padding(.trailing, 24)
        .foregroundStyle(theme.primaryText)
        .background(theme.toolbarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var statusPathText: String {
        guard let folderURL = library.folderURL else {
            return "No folder open"
        }

        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        if folderURL.path == homePath {
            return "~"
        }
        if folderURL.path.hasPrefix(homePath + "/") {
            return "~" + String(folderURL.path.dropFirst(homePath.count))
        }
        return folderURL.path
    }

    private var statusOpenFolderFileCount: String {
        let count = library.items.count
        let noun = count == 1 ? "open file" : "open files"
        if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(count) \(noun)"
        }

        let visibleCount = visibleItems.count
        return "\(visibleCount) of \(count) \(noun)"
    }

    private var statusClipCount: String {
        let count = timelineClips.count
        let noun = count == 1 ? "clip" : "clips"
        return "\(count) \(noun)"
    }

    private var statusTimelineDuration: String {
        let duration = actualTimelineDuration
        guard duration > 0 else { return "" }
        return "Duration \(MediaTrim.format(duration))"
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

    private var selectedThumbnailItems: [MediaItem] {
        visibleThumbnailEntries.compactMap { entry in
            guard thumbnailSelectionIDs.contains(entry.id) else { return nil }
            return entry.item
        }
    }

    private var primaryThumbnailSelectionID: URL? {
        if let thumbnailSelectionAnchorID,
           thumbnailSelectionIDs.contains(thumbnailSelectionAnchorID),
           visibleThumbnailEntries.contains(where: { $0.id == thumbnailSelectionAnchorID }) {
            return thumbnailSelectionAnchorID
        }

        return visibleThumbnailEntries.first { thumbnailSelectionIDs.contains($0.id) }?.id
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

    private var selectedEditorClip: EditorClip? {
        if let selectedEditorClipID,
           let clip = editorClips.first(where: { $0.id == selectedEditorClipID }) {
            return clip
        }

        return editorClips.first
    }

    private var selectedTimelineClip: EditorTimelineClip? {
        guard let selectedTimelineClipID else { return nil }
        return timelineClips.first { $0.id == selectedTimelineClipID }
    }

    private var selectedAdjustmentSpan: TimelineAdjustmentSpan? {
        guard let selectedAdjustmentSpanID else { return nil }
        return adjustmentSpans.first { $0.id == selectedAdjustmentSpanID }
    }

    private var hasPairedTimelineSelection: Bool {
        selectedTimelineClipID != nil && selectedAdjustmentSpanID != nil
    }

    private var activeEditorClip: EditorClip? {
        if let timelineClip = selectedTimelineClip,
           let clip = editorClip(for: timelineClip) {
            return clip
        }

        return selectedEditorClip
    }

    private var activeTimelineTrim: MediaTrim? {
        guard let selectedTimelineClip,
              let sourceClip = editorClip(for: selectedTimelineClip),
              let duration = sourceClip.status?.duration
        else {
            return nil
        }

        return timelineTrim(for: selectedTimelineClip, duration: duration)
    }

    private var activeTimelineTrimForPreview: MediaTrim? {
        guard let activeTimelineTrim,
              let duration = activeEditorClip?.status?.duration,
              !activeTimelineTrim.isFullLength(for: duration)
        else {
            return nil
        }

        return activeTimelineTrim
    }

    private var activeEditorDisplayedTime: TimeInterval {
        guard let trim = activeTimelineTrim else {
            return editorPlayerTime
        }

        return min(max(editorPlayerTime - trim.start, 0), trim.duration)
    }

    private var activeEditorDisplayedDuration: TimeInterval? {
        activeTimelineTrim?.duration ?? activeEditorClip?.status?.duration
    }

    private var isShowingTimelinePlayback: Bool {
        canPlayTimelineSequence
    }

    private var canPlayTimelineSequence: Bool {
        !timelineClips.isEmpty
            && timelineClips.allSatisfy { timelineClip in
                editorClip(for: timelineClip)?.item.kind == .video
            }
    }

    private var activeTimelineSourceClip: EditorClip? {
        guard let selectedTimelineClip else {
            return nil
        }

        return editorClip(for: selectedTimelineClip)
    }

    private var playerPaneTitle: String {
        if let selectedAdjustmentSpan {
            return "Adjustment Crop \(MediaTrim.format(selectedAdjustmentSpan.start))-\(MediaTrim.format(selectedAdjustmentSpan.end))"
        }

        if isShowingTimelinePlayback {
            if let activeTimelineSourceClip {
                return activeTimelineSourceClip.item.fileName
            }

            return "Timeline"
        }

        return activeEditorClip?.item.fileName ?? "No Clip"
    }

    private var playerPaneDurationText: String? {
        if isShowingTimelinePlayback {
            return "\(MediaTrim.format(timelinePlaybackTime)) / \(MediaTrim.format(actualTimelineDuration))"
        }

        guard let duration = activeEditorDisplayedDuration else {
            return nil
        }

        return "\(MediaTrim.format(activeEditorDisplayedTime)) / \(MediaTrim.format(duration))"
    }

    private var canZoomPlayerPane: Bool {
        isShowingTimelinePlayback || activeEditorClip != nil
    }

    private var playerZoomPercentageText: String {
        "\(Int((playerZoomMultiplier * 100).rounded()))%"
    }

    private var timelinePlaybackClips: [TimelinePlaybackClip] {
        timelineClips.compactMap { timelineClip in
            guard let sourceClip = editorClip(for: timelineClip),
                  sourceClip.item.kind == .video
            else {
                return nil
            }

            let adjustments = timelineClip.adjustments
            return TimelinePlaybackClip(
                id: timelineClip.id,
                url: sourceClip.item.url,
                trim: timelineClip.trim,
                volume: adjustments.isMuted ? 0 : Float(adjustments.volume)
            )
        }
    }

    private var isAdjustmentCropEditing: Bool {
        isPlayerCropToolActive && selectedAdjustmentSpan != nil
    }

    private var canEditPlayerCrop: Bool {
        selectedAdjustmentSpan != nil || (selectedTimelineClip == nil && activeEditorClip != nil)
    }

    private var canAddAdjustmentKeyframe: Bool {
        guard let selectedAdjustmentSpan else { return false }
        let crop = adjustmentCropDraft.clamped()
        guard !crop.isFullFrame else { return false }
        return timelinePlaybackTime >= selectedAdjustmentSpan.start
            && timelinePlaybackTime <= selectedAdjustmentSpan.end
    }

    @ViewBuilder
    private var timelineToolbarSeparator: some View {
        Rectangle()
            .fill(theme.hairline)
            .frame(width: 1, height: 16)
            .padding(.horizontal, 2)
    }

    private var timelinePixelsPerSecond: CGFloat {
        timelineBasePixelsPerSecond * CGFloat(timelineZoom)
    }

    private var selectedTimelineDeleteLabel: String {
        let base: String
        switch (selectedTimelineClipID, selectedAdjustmentSpanID) {
        case (.some, .some):
            base = "Delete Selected Timeline Items"
        case (.some, .none):
            base = "Delete Timeline Clip"
        case (.none, .some):
            base = "Delete Adjustment Crop"
        case (.none, .none):
            base = "Delete Timeline Selection"
        }
        return "\(base) (⇧⌫ Ripple)"
    }

    private var visibleEditorTabs: [MainPanelTab] {
        [.preview, .videoComposer].filter { mainPanelState.isVisible($0) }
    }

    private var selectedCrop: NormalizedCrop {
        guard let selectedItem else { return .full }
        return cropRects[selectedItem.id]
            ?? selectedPinnedItem?.crop
            ?? .full
    }

    private var selectedAppliedCrop: NormalizedCrop {
        guard let item = selectedItem else { return .full }
        return appliedCrops[item.id]
            ?? selectedPinnedItem?.crop
            ?? pinnedItems.first { $0.id == item.id }?.crop
            ?? .full
    }

    private var activeEditorCrop: NormalizedCrop {
        if selectedAdjustmentSpan != nil {
            return adjustmentCropDraft
        }

        if selectedTimelineClip != nil {
            return .full
        }

        guard let item = activeEditorClip?.item else { return .full }
        return cropRects[item.id]
            ?? pinnedItems.first { $0.id == item.id }?.crop
            ?? .full
    }

    private var activeEditorAppliedCrop: NormalizedCrop {
        if let selectedAdjustmentSpan {
            let time = min(max(timelinePlaybackTime, selectedAdjustmentSpan.start), selectedAdjustmentSpan.end)
            return selectedAdjustmentSpan.crop(at: time)
                ?? adjustmentCropDraft
        }

        if selectedTimelineClip != nil {
            return .full
        }

        guard let item = activeEditorClip?.item else { return .full }
        return appliedCrops[item.id]
            ?? pinnedItems.first { $0.id == item.id }?.crop
            ?? .full
    }

    private var activeEditorCanSnapshot: Bool {
        selectedAdjustmentSpan == nil && activeEditorClip?.item.kind == .video
    }

    private var selectedCanTrim: Bool {
        guard let item = selectedItem,
              item.kind == .video || item.kind == .gif,
              let duration = selectedStatus.duration
        else {
            return false
        }
        return duration > MediaTrim.minimumDuration
    }

    private var selectedTrim: MediaTrim {
        guard let item = selectedItem,
              let duration = selectedStatus.duration
        else {
            return .full(duration: 0)
        }

        return (trimRanges[item.id]
            ?? appliedTrims[item.id]
            ?? pinnedItems.first { $0.id == item.id }?.trim
            ?? .full(duration: duration))
            .clamped(to: duration)
    }

    private var selectedAppliedTrim: MediaTrim? {
        guard let item = selectedItem,
              let duration = selectedStatus.duration,
              let trim = (appliedTrims[item.id]
                ?? selectedPinnedItem?.trim
                ?? pinnedItems.first { $0.id == item.id }?.trim)?
                    .clamped(to: duration),
              !trim.isFullLength(for: duration)
        else {
            return nil
        }

        return trim
    }

    private var selectedPreviewTrim: MediaTrim? {
        if isTrimToolActive,
           selectedCanTrim,
           let duration = selectedStatus.duration {
            let trim = selectedTrim.clamped(to: duration)
            return trim.isFullLength(for: duration) ? nil : trim
        }

        return selectedAppliedTrim
    }

    private var hasSelectedAppliedEdits: Bool {
        !selectedAppliedCrop.isFullFrame || selectedAppliedTrim != nil
    }

    private var hasSelectedPendingOrAppliedEdits: Bool {
        guard selectedItem != nil else { return false }
        return !selectedCrop.isFullFrame
            || !selectedAppliedCrop.isFullFrame
            || !selectedTrim.isFullLength(for: selectedStatus.duration)
            || selectedAppliedTrim != nil
    }

    private var applyEditIsDisabled: Bool {
        if isTrimToolActive {
            return !selectedCanTrim || selectedTrim.isFullLength(for: selectedStatus.duration)
        }

        return selectedItem == nil || selectedCrop.isFullFrame || !isCropToolActive
    }

    private var editSummaryLabel: String {
        var parts: [String] = []
        if !selectedCrop.isFullFrame {
            parts.append(selectedCrop.displayLabel)
        }
        if !selectedTrim.isFullLength(for: selectedStatus.duration) {
            parts.append(selectedTrim.displayLabel)
        }
        return parts.joined(separator: "  ")
    }

    @ViewBuilder
    private var activeWorkbench: some View {
        switch mainPanelState.activeTab {
        case .preview:
            quickSortWorkbench
        case .videoComposer:
            composerWorkbench
        }
    }

    private var quickSortWorkbench: some View {
        HSplitView {
            thumbnailPanel
                .frame(
                    minWidth: showThumbnailPanel ? 190 : collapsedPanelWidth,
                    idealWidth: showThumbnailPanel ? 230 : collapsedPanelWidth,
                    maxWidth: showThumbnailPanel ? 320 : collapsedPanelWidth
                )

            previewMainPanel
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)

            pinnedPanel
                .frame(
                    minWidth: showPinnedPanel ? 180 : collapsedPanelWidth,
                    idealWidth: showPinnedPanel ? 220 : collapsedPanelWidth,
                    maxWidth: showPinnedPanel ? 300 : collapsedPanelWidth
                )
        }
        .background(theme.canvasBackground)
    }

    private var composerWorkbench: some View {
        VSplitView {
            HSplitView {
                thumbnailPanel
                    .frame(
                        minWidth: showThumbnailPanel ? 190 : collapsedPanelWidth,
                        idealWidth: showThumbnailPanel ? 230 : collapsedPanelWidth,
                        maxWidth: showThumbnailPanel ? 320 : collapsedPanelWidth
                    )

                clipsPane
                    .frame(minWidth: 180, idealWidth: 220, maxWidth: 290)

                playerPane
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)

                pinnedPanel
                    .frame(
                        minWidth: showPinnedPanel ? 180 : collapsedPanelWidth,
                        idealWidth: showPinnedPanel ? 220 : collapsedPanelWidth,
                        maxWidth: showPinnedPanel ? 290 : collapsedPanelWidth
                    )
            }
            .frame(minHeight: 300, maxHeight: .infinity)

            timelinePane
                .frame(minHeight: 120, idealHeight: 150, maxHeight: 190)
        }
        .background(theme.canvasBackground)
    }

    private var mainPanelTabBar: some View {
        ZStack {
            HStack(spacing: 0) {
                Spacer(minLength: 0)

                Button {
                    exportTimeline()
                } label: {
                    if isExportingTimeline {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 86, height: 38)
                    } else {
                        Text("Export")
                            .font(.system(size: 14, weight: .bold))
                            .frame(width: 86, height: 38)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentText)
                .background(theme.accent, in: RoundedRectangle(cornerRadius: 7))
                .disabled(timelineClips.isEmpty || isExportingTimeline)
                .quickTooltip("Export Timeline")
                .accessibilityLabel("Export Timeline")
            }

            HStack(spacing: 0) {
                ForEach(visibleEditorTabs) { tab in
                    let isActive = mainPanelState.activeTab == tab
                    Button {
                        mainPanelState.activate(tab)
                    } label: {
                        Text(tab.title)
                            .font(.system(size: 14, weight: .semibold))
                            .lineLimit(1)
                            .frame(width: 112, height: topToolbarHeight)
                            .background(isActive ? theme.panelRaised : Color.clear)
                            .overlay(alignment: .top) {
                                if isActive {
                                    Rectangle()
                                        .fill(theme.accent)
                                        .frame(height: 3)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isActive ? theme.primaryText : theme.secondaryText)
                    .accessibilityLabel(tab.title)
                }
            }
        }
        .frame(height: topToolbarHeight)
        .padding(.leading, 16)
        .padding(.trailing, 16)
        .background(theme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var previewMainPanel: some View {
        VStack(spacing: 0) {
            mediaPreviewHeader
            editingToolbar
            previewPanel
        }
    }

    private var mediaPreviewHeader: some View {
        HStack(spacing: 10) {
            Text(selectedItem?.fileName ?? "No media selected")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(selectedItem?.url.path ?? "No media selected")

            if !selectedStatus.detailText.isEmpty {
                Text(selectedStatus.detailText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
        .background(theme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var clipsPane: some View {
        VStack(spacing: 0) {
            panelColumnHeader(title: "Clips") {
                Button {
                    importEditorClips()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accent)
                .quickTooltip("Import Clips")
                .accessibilityLabel("Import Clips")
            }

            if editorClips.isEmpty {
                Text("Import media to start building a timeline.")
                    .font(.callout)
                    .foregroundStyle(theme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(editorClips) { clip in
                            Button {
                                selectedTimelineClipID = nil
                                selectedAdjustmentSpanID = nil
                                selectedEditorClipID = clip.id
                                editorPlayerTime = 0
                            } label: {
                                EditorClipCard(
                                    clip: clip,
                                    thumbnail: editorClipThumbnail(for: clip),
                                    isSelected: selectedEditorClipID == clip.id
                                )
                            }
                            .buttonStyle(.plain)
                            .onDrag {
                                NSItemProvider(object: dragPayload(for: clip) as NSString)
                            }
                            .contextMenu {
                                Button("Add to Timeline") {
                                    addTimelineClip(sourceClipID: clip.id)
                                }

                                Button("Remove from Clips") {
                                    removeEditorClip(clip)
                                }
                            }
                            .task(id: clip.id) {
                                await loadEditorClipMetadataIfNeeded(for: clip)
                            }
                        }
                    }
                    .padding(8)
                }
            }
        }
        .background(theme.panelBackground)
    }

    private var playerPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(playerPaneTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(playerPaneTitle)

                if let durationText = playerPaneDurationText {
                    Text(durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(theme.secondaryText)
                        .lineLimit(1)
                }

                playerAudioControls
            }
            .frame(height: topToolbarHeight)
            .padding(.horizontal, 12)
            .background(theme.toolbarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 1)
            }

            ZStack {
                theme.windowBackground

                if isShowingTimelinePlayback && (selectedAdjustmentSpan != nil || !isPlayerCropToolActive) {
                    ZStack {
                        TimelineSequenceVideoView(
                            clips: timelinePlaybackClips,
                        zoomMultiplier: playerZoomMultiplier,
                        fillsFrame: isPlayerFillMode,
                        seekRequest: timelineSeekRequest,
                        playbackToggleRequest: playerPlaybackToggleRequest,
                        onPlaybackPositionChange: handleTimelinePlaybackPosition
                    )

                        if isAdjustmentCropEditing {
                            CropOverlay(
                                crop: adjustmentCropBinding,
                                isEditable: true,
                                onApply: applyActiveEditorCrop,
                                outlineColor: timelineSelectionOutlineColor,
                                usesDashedOutline: false
                            )
                        }
                    }
                } else if let clip = activeEditorClip {
                    PreviewPane(
                        item: clip.item,
                        zoomMultiplier: playerZoomMultiplier,
                        fillsFrame: isPlayerFillMode,
                        isCropToolActive: isPlayerCropToolActive,
                        appliedCrop: activeEditorAppliedCrop,
                        appliedTrim: activeTimelineTrimForPreview,
                        playbackToggleRequest: playerPlaybackToggleRequest,
                        onApplyCrop: applyActiveEditorCrop,
                        onVideoTimeChange: { editorPlayerTime = $0 },
                        crop: activeEditorCropBinding(for: clip.item)
                    )
                    .id(activeEditorPreviewID(for: clip))
                } else {
                    Text("No clips added.")
                        .font(.title3)
                        .foregroundStyle(theme.secondaryText)
                }
            }
        }
        .background(theme.windowBackground)
    }

    @ViewBuilder
    private var playerAudioControls: some View {
        if selectedTimelineClip != nil {
            HStack(spacing: 7) {
                Button {
                    updateSelectedTimelineAdjustments { adjustments in
                        adjustments.isMuted.toggle()
                    }
                } label: {
                    Image(systemName: selectedTimelineClip?.adjustments.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selectedTimelineClip?.adjustments.isMuted == true ? theme.accent : theme.primaryText)
                .quickTooltip(selectedTimelineClip?.adjustments.isMuted == true ? "Unmute Clip" : "Mute Clip")
                .accessibilityLabel(selectedTimelineClip?.adjustments.isMuted == true ? "Unmute Clip" : "Mute Clip")

                Slider(
                    value: timelineAdjustmentBinding(\.volume, default: 1),
                    in: 0...2
                )
                .controlSize(.small)
                .frame(width: 110)
                .quickTooltip("Clip Volume")
                .accessibilityLabel("Clip Volume")

                Text(String(format: "%.2f", selectedTimelineClip?.adjustments.volume ?? 1))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(theme.secondaryText)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.panelBackground, in: RoundedRectangle(cornerRadius: 7))
        }
    }

    private var timelinePane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    exportTimeline()
                } label: {
                    if isExportingTimeline {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(timelineClips.isEmpty || isExportingTimeline)
                .quickTooltip("Export Timeline")
                .accessibilityLabel("Export Timeline")

                timelineToolbarSeparator

                Button {
                    resetSelectedTimelineTrim()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!selectedTimelineClipHasTrim)
                .quickTooltip("Reset Timeline Trim")
                .accessibilityLabel("Reset Timeline Trim")

                Button {
                    splitSelectedTimelineClip()
                } label: {
                    Image(systemName: "scissors")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!canSplitSelectedTimelineClip)
                .quickTooltip("Split Clip")
                .accessibilityLabel("Split Clip")

                Button {
                    removeSelectedTimelineSelection()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(selectedTimelineClipID == nil && selectedAdjustmentSpanID == nil)
                .quickTooltip(selectedTimelineDeleteLabel)
                .accessibilityLabel(selectedTimelineDeleteLabel)

                timelineToolbarSeparator

                Button {
                    addAdjustmentCropSpan()
                } label: {
                    Image(systemName: "rectangle.badge.plus")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(actualTimelineDuration <= 0)
                .quickTooltip("Add Adjustment Crop")
                .accessibilityLabel("Add Adjustment Crop")

                Button {
                    applyAdjustmentCropKeyframe()
                } label: {
                    Image(systemName: "diamond")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!canAddAdjustmentKeyframe)
                .quickTooltip("Add Keyframe")
                .accessibilityLabel("Add Keyframe")

                Button {
                    isPlayerCropToolActive.toggle()
                    if isPlayerCropToolActive {
                        isCropToolActive = false
                        isTrimToolActive = false
                        syncAdjustmentCropDraft()
                    }
                } label: {
                    Image(systemName: "crop")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!canEditPlayerCrop)
                .foregroundStyle(isPlayerCropToolActive ? theme.accent : theme.primaryText)
                .quickTooltip(selectedAdjustmentSpan == nil ? "Crop Tool" : "Adjustment Crop Tool")
                .accessibilityLabel(selectedAdjustmentSpan == nil ? "Crop Tool" : "Adjustment Crop Tool")

                Menu {
                    Button("Square 1:1") {
                        applyActiveEditorCropPreset(width: 1, height: 1)
                    }
                    Button("Portrait 4:5") {
                        applyActiveEditorCropPreset(width: 4, height: 5)
                    }
                    Button("Story/Reel 9:16") {
                        applyActiveEditorCropPreset(width: 9, height: 16)
                    }
                    Button("Landscape 16:9") {
                        applyActiveEditorCropPreset(width: 16, height: 9)
                    }
                    Button("Classic 4:3") {
                        applyActiveEditorCropPreset(width: 4, height: 3)
                    }
                    Button("Open Graph 1.91:1") {
                        applyActiveEditorCropPreset(width: 1.91, height: 1)
                    }
                } label: {
                    Image(systemName: "aspectratio")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(theme.primaryText)
                .disabled(!canEditPlayerCrop)
                .quickTooltip("Crop Presets")
                .accessibilityLabel("Crop Presets")

                Button {
                    clearActiveEditorCrop()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!canEditPlayerCrop || (selectedAdjustmentSpan == nil && activeEditorCrop.isFullFrame && activeEditorAppliedCrop.isFullFrame))
                .quickTooltip(selectedAdjustmentSpan == nil ? "Reset Crop" : "Remove Adjustment Crop")
                .accessibilityLabel(selectedAdjustmentSpan == nil ? "Reset Crop" : "Remove Adjustment Crop")

                timelineToolbarSeparator

                Button {
                    snapshotActiveEditorFrame()
                } label: {
                    if isCapturingSnapshot {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "camera")
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 22, height: 22)
                    }
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!activeEditorCanSnapshot || isCapturingSnapshot)
                .quickTooltip("Snapshot Current Frame")
                .accessibilityLabel("Snapshot Current Frame")

                Button {
                    zoomPlayerOut()
                } label: {
                    Image(systemName: "minus.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!canZoomPlayerPane || playerZoomMultiplier <= playerZoomRange.lowerBound)
                .quickTooltip("Zoom Out Player")
                .accessibilityLabel("Zoom Out Player")

                Text(playerZoomPercentageText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .frame(width: 40)
                    .quickTooltip("Player Zoom")
                    .accessibilityLabel("Player Zoom")

                Button {
                    zoomPlayerIn()
                } label: {
                    Image(systemName: "plus.magnifyingglass")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.primaryText)
                .disabled(!canZoomPlayerPane || playerZoomMultiplier >= playerZoomRange.upperBound)
                .quickTooltip("Zoom In Player")
                .accessibilityLabel("Zoom In Player")

                Button {
                    isPlayerFillMode.toggle()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .disabled(!canZoomPlayerPane)
                .foregroundStyle(isPlayerFillMode ? theme.accent : theme.primaryText)
                .quickTooltip(isPlayerFillMode ? "Use Fit Player" : "Fill Player")
                .accessibilityLabel(isPlayerFillMode ? "Use Fit Player" : "Fill Player")

                Spacer(minLength: 0)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.secondaryText)

                Slider(value: $timelineZoom, in: timelineZoomRange)
                    .controlSize(.small)
                    .frame(width: 118)
                    .quickTooltip("Timeline Zoom")
                    .accessibilityLabel("Timeline Zoom")
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(theme.toolbarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(theme.hairline)
                    .frame(height: 1)
            }

            timelineBody
                .frame(height: timelineRulerHeight + timelineAdjustmentLayerHeight + timelineVideoTrackHeight)
        }
        .background(theme.timelineBackground)
        .onDrop(
            of: [UTType.plainText.identifier],
            isTargeted: $isTimelineDropTargeted,
            perform: handleTimelineDrop
        )
        .onChange(of: timelineClips.count) { oldValue, newValue in
            if newValue == 0 {
                autoZoomedTimelineClipID = nil
            } else if oldValue == 0 && newValue == 1 {
                autoZoomTimelineForFirstClip()
            }
        }
    }

    private var timelineBody: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    timelineRuler
                        .frame(height: timelineRulerHeight)

                    adjustmentLayer
                        .frame(height: timelineAdjustmentLayerHeight)

                    timelineTrackRow(title: "Video", systemImage: "film", clips: timelineClips, acceptsDrops: true)
                        .frame(height: timelineVideoTrackHeight)
                }

                timelinePlayheadOverlay(in: geometry.size)
            }
            .onAppear { timelineRulerWidth = geometry.size.width }
            .onChange(of: geometry.size.width) { _, newValue in
                timelineRulerWidth = newValue
            }
        }
    }

    private var timelineRuler: some View {
        GeometryReader { geometry in
            let interval = timelineMarkerInterval
            let minorInterval = timelineMinorMarkerInterval
            let visibleDuration = timelineDurationToFillWidth(geometry.size.width)
            let contentDuration = max(totalTimelineDuration, interval * 5, visibleDuration)
            let markerCount = max(1, Int(ceil(contentDuration / interval)))
            let tickCount = max(1, Int(ceil(contentDuration / minorInterval)))
            let majorTickStride = max(1, Int(round(interval / minorInterval)))
            let contentWidth = timelineContentWidth(for: contentDuration, minimumWidth: geometry.size.width)

            ZStack(alignment: .topLeading) {
                ForEach(0...tickCount, id: \.self) { tick in
                    let seconds = TimeInterval(tick) * minorInterval
                    let isMajorTick = tick % majorTickStride == 0

                    Rectangle()
                        .fill(theme.secondaryText.opacity(isMajorTick ? 0.55 : 0.28))
                        .frame(width: 1, height: isMajorTick ? 9 : 4)
                        .offset(
                            x: timelineTrackHeaderWidth + CGFloat(seconds) * timelinePixelsPerSecond,
                            y: geometry.size.height - (isMajorTick ? 13 : 8)
                        )
                }

                ForEach(0...markerCount, id: \.self) { marker in
                    let seconds = TimeInterval(marker) * interval

                    Text(MediaTrim.format(seconds))
                        .font(.system(size: 10, weight: .regular, design: .monospaced))
                        .foregroundStyle(theme.secondaryText.opacity(0.78))
                        .lineLimit(1)
                        .fixedSize()
                        .offset(x: timelineTrackHeaderWidth + CGFloat(seconds) * timelinePixelsPerSecond, y: 4)
                }
            }
            .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
        }
        .background(theme.timelineBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var adjustmentLayer: some View {
        HStack(spacing: 0) {
            timelineTrackHeader(title: "Adjust", systemImage: "slider.horizontal.3")

            GeometryReader { geometry in
                let contentWidth = timelineContentWidth(for: totalTimelineDuration, minimumWidth: geometry.size.width)

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(theme.trackAlternateBackground.opacity(0.58))

                    ForEach(adjustmentSpans) { span in
                        TimelineAdjustmentSpanBlock(
                            span: span,
                            isSelected: selectedAdjustmentSpanID == span.id,
                            isPaired: hasPairedTimelineSelection,
                            pixelsPerSecond: timelinePixelsPerSecond,
                            onSelect: {
                                selectAdjustmentSpan(span)
                            },
                            onMove: { proposedStart in
                                moveAdjustmentSpan(span, proposedStart: proposedStart)
                            },
                            onResizeStart: { proposedStart in
                                resizeAdjustmentSpanStart(span, proposedStart: proposedStart)
                            },
                            onResizeEnd: { proposedEnd in
                                resizeAdjustmentSpanEnd(span, proposedEnd: proposedEnd)
                            },
                            onDeleteKeyframe: { keyframeID in
                                deleteAdjustmentKeyframe(keyframeID, from: span)
                            },
                            onMoveKeyframe: { keyframeID, proposedTime in
                                moveAdjustmentKeyframe(keyframeID, in: span.id, proposedTime: proposedTime)
                            }
                        )
                        .frame(
                            width: max(CGFloat(span.duration) * timelinePixelsPerSecond, 18),
                            height: 36
                        )
                        .offset(
                            x: CGFloat(span.start) * timelinePixelsPerSecond,
                            y: 4
                        )
                        .contextMenu {
                            Button("Remove Adjustment Crop") {
                                removeAdjustmentSpan(span)
                            }
                        }
                    }

                    Rectangle()
                        .fill(theme.hairline)
                        .frame(height: 1)
                        .offset(y: geometry.size.height - 1)
                }
                .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
            }
            .background(theme.trackAlternateBackground.opacity(0.58))
        }
    }

    private func timelinePlayheadOverlay(in size: CGSize) -> some View {
        let clampedTime = clampedTimelinePlayheadTime(timelinePlaybackTime)
        let playheadX = timelineTrackHeaderWidth + CGFloat(clampedTime) * timelinePixelsPerSecond
        let handleTopOffset = timelineRulerHeight - timelinePlayheadHandleSize.height
        let lineTop = handleTopOffset + timelinePlayheadHandleSize.height - 1

        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(timelinePlayheadColor)
                .frame(width: 1.5, height: max(0, size.height - lineTop))
                .offset(x: playheadX - 0.75, y: lineTop)
                .allowsHitTesting(false)

            TimelinePlayheadHandleShape()
                .fill(timelinePlayheadColor)
                .frame(width: timelinePlayheadHandleSize.width, height: timelinePlayheadHandleSize.height)
                .offset(x: playheadX - timelinePlayheadHandleSize.width / 2, y: handleTopOffset)
                .allowsHitTesting(false)

            Rectangle()
                .fill(Color.black.opacity(0.001))
                .frame(width: timelinePlayheadHitWidth, height: size.height)
                .contentShape(Rectangle())
                .offset(x: playheadX - timelinePlayheadHitWidth / 2)
                .gesture(timelinePlayheadDragGesture)
                .quickTooltip("Drag Playhead")
                .accessibilityLabel("Drag Playhead")
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    private var timelinePlayheadDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startTime = timelinePlayheadDragStartTime ?? timelinePlaybackTime
                timelinePlayheadDragStartTime = startTime

                let delta = TimeInterval(value.translation.width / max(timelinePixelsPerSecond, 0.1))
                seekTimelinePlayhead(to: startTime + delta)
            }
            .onEnded { value in
                let startTime = timelinePlayheadDragStartTime ?? timelinePlaybackTime
                let delta = TimeInterval(value.translation.width / max(timelinePixelsPerSecond, 0.1))
                seekTimelinePlayhead(to: startTime + delta)
                timelinePlayheadDragStartTime = nil
            }
    }

    private func timelineTrackHeader(title: String, systemImage: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 16)
            Text(title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(theme.secondaryText)
        .padding(.horizontal, 5)
        .frame(width: timelineTrackHeaderWidth, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(theme.trackAlternateBackground)
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1)
        }
    }

    private func timelineTrackRow(
        title: String,
        systemImage: String,
        clips: [EditorTimelineClip],
        acceptsDrops: Bool
    ) -> some View {
        HStack(spacing: 0) {
            timelineTrackHeader(title: title, systemImage: systemImage)

            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(clips) { clip in
                        let sourceClip = editorClip(for: clip)
                        let duration = sourceClip?.status?.duration ?? 0
                        let trim = timelineTrim(for: clip, duration: duration)
                        let gapWidth = max(0, CGFloat(max(0, clip.leadingGap)) * timelinePixelsPerSecond)

                        if gapWidth > 0 {
                            Color.clear
                                .frame(width: gapWidth, height: 76)
                        }

                        TimelineClipBlock(
                            sourceClip: sourceClip,
                            thumbnail: sourceClip.flatMap(editorClipThumbnail(for:)),
                            filmstrip: sourceClip?.filmstrip,
                            isSelected: selectedTimelineClipID == clip.id,
                            isPaired: hasPairedTimelineSelection,
                            trim: trim,
                            totalDuration: duration,
                            pixelsPerSecond: timelinePixelsPerSecond,
                            onTrimChange: { nextTrim in
                                updateTimelineClipTrim(clip, trim: nextTrim)
                            }
                        )
                        .frame(width: timelineClipWidth(for: clip), height: 76)
                        .contentShape(Rectangle())
                        .opacity(draggingTimelineClipID == clip.id ? 0.72 : 1)
                        .onTapGesture {
                            selectTimelineClip(clip)
                        }
                        .onDrag {
                            draggingTimelineClipID = clip.id
                            selectTimelineClip(clip)
                            return NSItemProvider(object: timelineDragPayload(for: clip) as NSString)
                        }
                        .onDrop(
                            of: [UTType.plainText.identifier],
                            delegate: TimelineClipReorderDropDelegate(
                                targetClipID: clip.id,
                                draggingClipID: $draggingTimelineClipID,
                                moveClip: { draggedID, targetID in
                                    moveTimelineClip(draggedID, around: targetID)
                                }
                            )
                        )
                        .contextMenu {
                            Button("Remove from Timeline") {
                                removeTimelineClip(clip)
                            }
                            Button("Ripple Delete from Timeline") {
                                removeTimelineClip(clip, ripple: true)
                            }
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
                .frame(maxHeight: .infinity, alignment: .leading)
            }
            .background {
                if acceptsDrops && isTimelineDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(theme.accent.opacity(0.10))
                        .padding(4)
                }
            }
            .overlay {
                if acceptsDrops && isTimelineDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .padding(4)
                }
            }
            .background(theme.trackBackground)
        }
    }

    private var editingToolbar: some View {
        HStack(spacing: 4) {
            Button {
                snapshotSelectedPreviewFrame()
            } label: {
                if isCapturingSnapshot {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 28, height: 26)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 14, weight: .medium))
                        .frame(width: 28, height: 26)
                }
            }
            .buttonStyle(.plain)
            .disabled(!selectedCanSnapshot || isCapturingSnapshot)
            .quickTooltip("Snapshot Current Frame")
            .accessibilityLabel("Snapshot Current Frame")

            Button {
                isCropToolActive.toggle()
                if isCropToolActive {
                    isPlayerCropToolActive = false
                }
            } label: {
                Image(systemName: "crop")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil)
            .foregroundStyle(isCropToolActive ? theme.accent : theme.primaryText)
            .quickTooltip("Crop Tool")
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
            .quickTooltip("Crop Presets")
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
            .quickTooltip("Reset Crop")
            .accessibilityLabel("Reset Crop")

            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)

            Button {
                isTrimToolActive.toggle()
                if isTrimToolActive {
                    isCropToolActive = false
                    prepareSelectedTrimDraft()
                }
            } label: {
                Image(systemName: "timeline.selection")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!selectedCanTrim)
            .foregroundStyle(isTrimToolActive ? theme.accent : theme.primaryText)
            .quickTooltip("Trim Tool")
            .accessibilityLabel("Trim Tool")

            Button {
                clearSelectedTrim()
            } label: {
                Image(systemName: "gobackward")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!selectedCanTrim || selectedTrim.isFullLength(for: selectedStatus.duration))
            .quickTooltip("Reset Trim")
            .accessibilityLabel("Reset Trim")

            if isTrimToolActive, selectedCanTrim, let duration = selectedStatus.duration {
                TrimControls(
                    trim: trimBinding(for: selectedItem, duration: duration),
                    duration: duration,
                    onApply: applySelectedTrim
                )
                .frame(width: 360)
            }

            Button {
                undoSelectedEdits()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(!hasSelectedPendingOrAppliedEdits)
            .quickTooltip("Undo Edits")
            .accessibilityLabel("Undo Edits")

            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1, height: 18)
                .padding(.horizontal, 3)

            Button {
                if isTrimToolActive {
                    applySelectedTrim()
                } else {
                    applySelectedCrop()
                }
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(applyEditIsDisabled)
            .quickTooltip(isTrimToolActive ? "Apply Trim" : "Apply Crop")
            .accessibilityLabel(isTrimToolActive ? "Apply Trim" : "Apply Crop")

            Button {
                pinEditedSelectedItem()
            } label: {
                Image(systemName: "pin")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil || !hasSelectedAppliedEdits)
            .quickTooltip("Move Edited Media to Pinned")
            .accessibilityLabel("Move Edited Media to Pinned")

            if !selectedCrop.isFullFrame || !selectedTrim.isFullLength(for: selectedStatus.duration) {
                Text(editSummaryLabel)
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .help("Current Edit Summary")
            }

            Spacer(minLength: 0)
        }
        .frame(height: topToolbarHeight)
        .padding(.horizontal, 10)
        .foregroundStyle(theme.primaryText)
        .background(theme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }

    private var previewPanel: some View {
        ZStack {
            theme.canvasBackground

            if let item = selectedItem {
                PreviewPane(
                    item: item,
                    zoomMultiplier: zoomLevels[zoomIndex],
                    fillsFrame: false,
                    isCropToolActive: isCropToolActive,
                    appliedCrop: selectedAppliedCrop,
                    appliedTrim: selectedPreviewTrim,
                    playbackToggleRequest: previewPlaybackToggleRequest,
                    onApplyCrop: applySelectedCrop,
                    onVideoTimeChange: { previewVideoTime = $0 },
                    crop: cropBinding(for: item)
                )
                    .id(item.id)
            } else {
                Text(library.stateMessage)
                    .font(.title3)
                    .foregroundStyle(theme.secondaryText)
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
                .stroke(theme.accent, lineWidth: 3)
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
        if event.keyCode == 49,
           !isTextInputFocused,
           !event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.control),
           !event.modifierFlags.contains(.option) {
            return toggleActivePlayback()
        }

        if canAddAdjustmentKeyframe,
           !isTextInputFocused,
           mainPanelState.activeTab == .videoComposer {
            switch event.keyCode {
            case 36, 76:
                applyAdjustmentCropKeyframe()
                return true
            case 123:
                nudgeAdjustmentCrop(x: -adjustmentCropKeyboardStep(for: event), y: 0)
                return true
            case 124:
                nudgeAdjustmentCrop(x: adjustmentCropKeyboardStep(for: event), y: 0)
                return true
            case 125:
                nudgeAdjustmentCrop(x: 0, y: adjustmentCropKeyboardStep(for: event))
                return true
            case 126:
                nudgeAdjustmentCrop(x: 0, y: -adjustmentCropKeyboardStep(for: event))
                return true
            default:
                break
            }
        }

        if selectedCanTrim,
           isTrimToolActive || !selectedTrim.isFullLength(for: selectedStatus.duration) {
            switch event.keyCode {
            case 36, 76:
                DispatchQueue.main.async {
                    applySelectedTrim()
                }
                return true
            case 53:
                DispatchQueue.main.async {
                    clearSelectedTrim()
                }
                return true
            default:
                break
            }
        }

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
           event.charactersIgnoringModifiers?.lowercased() == "c" {
            return addActiveThumbnailToEditorClips()
        }

        if event.modifierFlags.contains(.control),
           event.charactersIgnoringModifiers?.lowercased() == "p" {
            pinActiveThumbnailOrPreview()
            return true
        }

        if mainPanelState.activeTab == .videoComposer,
           selectedTimelineClipID != nil || selectedAdjustmentSpanID != nil {
            switch event.keyCode {
            case 51, 117:
                removeSelectedTimelineSelection(ripple: event.modifierFlags.contains(.shift))
                return true
            default:
                break
            }
        }

        if event.modifierFlags.contains(.command) {
            switch event.charactersIgnoringModifiers {
            case "z":
                undoSelectedEdits()
                return true
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

    private var isTextInputFocused: Bool {
        guard let firstResponder = NSApp.keyWindow?.firstResponder else {
            return false
        }

        return firstResponder is NSTextView || firstResponder is NSTextField
    }

    private func toggleActivePlayback() -> Bool {
        switch mainPanelState.activeTab {
        case .preview:
            guard selectedItem?.kind == .video, !isCropToolActive else {
                return false
            }
            previewPlaybackToggleRequest = PlaybackToggleRequest()
            return true
        case .videoComposer:
            if isShowingTimelinePlayback && (selectedAdjustmentSpan != nil || !isPlayerCropToolActive) {
                guard !timelinePlaybackClips.isEmpty else { return false }
                playerPlaybackToggleRequest = PlaybackToggleRequest()
                return true
            }

            guard activeEditorClip?.item.kind == .video, !isPlayerCropToolActive else {
                return false
            }
            playerPlaybackToggleRequest = PlaybackToggleRequest()
            return true
        }
    }

    private func adjustmentCropKeyboardStep(for event: NSEvent) -> CGFloat {
        event.modifierFlags.contains(.option) ? 0.025 : 0.005
    }

    private func nudgeAdjustmentCrop(x deltaX: CGFloat, y deltaY: CGFloat) {
        let crop = adjustmentCropDraft.clamped()
        updateAdjustmentCropDraft(NormalizedCrop(
            x: crop.x + deltaX,
            y: crop.y + deltaY,
            width: crop.width,
            height: crop.height
        ).clamped())
    }

    private func zoomIn() {
        zoomIndex = min(zoomIndex + 1, zoomLevels.index(before: zoomLevels.endIndex))
    }

    private func zoomOut() {
        zoomIndex = max(zoomIndex - 1, zoomLevels.startIndex)
    }

    private func zoomPlayerIn() {
        playerZoomMultiplier = min(playerZoomMultiplier + playerZoomStep, playerZoomRange.upperBound)
    }

    private func zoomPlayerOut() {
        playerZoomMultiplier = max(playerZoomMultiplier - playerZoomStep, playerZoomRange.lowerBound)
    }

    private func cropBinding(for item: MediaItem) -> Binding<NormalizedCrop> {
        Binding {
            cropRects[item.id] ?? pinnedItems.first { $0.id == item.id }?.crop ?? .full
        } set: { newValue in
            cropRects[item.id] = newValue.clamped()
        }
    }

    private func activeEditorCropBinding(for item: MediaItem) -> Binding<NormalizedCrop> {
        Binding {
            activeEditorCrop
        } set: { newValue in
            if selectedTimelineClip == nil {
                cropRects[item.id] = newValue.clamped()
            }
        }
    }

    private var adjustmentCropBinding: Binding<NormalizedCrop> {
        Binding {
            adjustmentCropDraft
        } set: { newValue in
            updateAdjustmentCropDraft(newValue.clamped())
        }
    }

    private func trimBinding(for item: MediaItem?, duration: TimeInterval) -> Binding<MediaTrim> {
        Binding {
            guard let item else { return .full(duration: duration) }
            return (trimRanges[item.id]
                ?? appliedTrims[item.id]
                ?? pinnedItems.first { $0.id == item.id }?.trim
                ?? .full(duration: duration))
                .clamped(to: duration)
        } set: { newValue in
            guard let item else { return }
            trimRanges[item.id] = newValue.clamped(to: duration)
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
        isTrimToolActive = false
        isPlayerCropToolActive = false
    }

    private func applyActiveEditorCropPreset(width: CGFloat, height: CGFloat) {
        if selectedAdjustmentSpan != nil {
            let crop = adjustmentCropPreset(width: width, height: height)
            updateAdjustmentCropDraft(crop)
            isPlayerCropToolActive = true
            isCropToolActive = false
            isTrimToolActive = false
            return
        }

        guard let clip = activeEditorClip else { return }
        let naturalSize = clip.status?.size ?? CGSize(width: width, height: height)
        let crop = NormalizedCrop.centered(
            aspectRatio: width / height,
            naturalSize: naturalSize
        )
        if selectedTimelineClip == nil {
            cropRects[clip.item.id] = crop
        }
        isPlayerCropToolActive = true
        isCropToolActive = false
        isTrimToolActive = false
    }

    private func clearSelectedCrop() {
        guard let item = selectedItem else { return }
        cropRects[item.id] = .full
        appliedCrops[item.id] = nil
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            pinnedItems[index].crop = nil
        }
        isCropToolActive = false
    }

    private func clearActiveEditorCrop() {
        if let selectedAdjustmentSpan {
            removeAdjustmentSpan(selectedAdjustmentSpan)
            isPlayerCropToolActive = false
            return
        }

        guard selectedTimelineClip == nil else { return }
        guard let item = activeEditorClip?.item else { return }
        cropRects[item.id] = .full
        appliedCrops[item.id] = nil
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            pinnedItems[index].crop = nil
        }
        isPlayerCropToolActive = false
    }

    private func applySelectedCrop() {
        guard let item = selectedItem else { return }
        let crop = selectedCrop.clamped()
        guard !crop.isFullFrame else { return }
        appliedCrops[item.id] = crop
        cropRects[item.id] = crop
        isCropToolActive = false
    }

    private func applyActiveEditorCrop() {
        if selectedAdjustmentSpan != nil {
            applyAdjustmentCropKeyframe()
            return
        }

        guard selectedTimelineClip == nil else { return }
        guard let item = activeEditorClip?.item else { return }
        let crop = activeEditorCrop.clamped()
        guard !crop.isFullFrame else { return }
        appliedCrops[item.id] = crop
        cropRects[item.id] = crop
        isPlayerCropToolActive = false
    }

    private func prepareSelectedTrimDraft() {
        guard let item = selectedItem,
              let duration = selectedStatus.duration
        else {
            return
        }

        trimRanges[item.id] = selectedTrim.clamped(to: duration)
    }

    private func clearSelectedTrim() {
        guard let item = selectedItem,
              let duration = selectedStatus.duration
        else {
            return
        }

        trimRanges[item.id] = .full(duration: duration)
        appliedTrims[item.id] = nil
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            pinnedItems[index].trim = nil
        }
        isTrimToolActive = false
    }

    private func applySelectedTrim() {
        guard let item = selectedItem,
              let duration = selectedStatus.duration
        else {
            return
        }

        let trim = selectedTrim.clamped(to: duration)
        guard !trim.isFullLength(for: duration) else { return }
        appliedTrims[item.id] = trim
        trimRanges[item.id] = trim
        isTrimToolActive = false
    }

    private func undoSelectedEdits() {
        guard let item = selectedItem else { return }

        cropRects[item.id] = .full
        trimRanges[item.id] = selectedStatus.duration.map(MediaTrim.full(duration:))
        appliedCrops[item.id] = nil
        appliedTrims[item.id] = nil
        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            pinnedItems[index].crop = nil
            pinnedItems[index].trim = nil
        }
        isCropToolActive = false
        isTrimToolActive = false
    }

    private func pinEditedSelectedItem() {
        guard let item = selectedItem else { return }
        let crop = selectedAppliedCrop.clamped()
        let trim = selectedAppliedTrim
        guard !crop.isFullFrame || trim != nil else { return }
        pin(item, crop: crop, trim: trim)
        activePanel = .pinned
        library.selectedID = item.id
    }

    private func selectFirstVisibleItemIfNeeded() {
        if let selectedID = library.selectedID,
           visibleItems.contains(where: { $0.id == selectedID })
            || pinnedItems.contains(where: { $0.id == selectedID }) {
            if activePanel == .thumbnail {
                thumbnailSelectionIDs = [selectedID]
                thumbnailSelectionAnchorID = selectedID
            }
            return
        }

        let visibleSelectionIDs = thumbnailSelectionIDs.filter { selectionID in
            visibleThumbnailEntries.contains { $0.id == selectionID }
        }
        if !visibleSelectionIDs.isEmpty {
            thumbnailSelectionIDs = visibleSelectionIDs
            if let thumbnailSelectionAnchorID,
               !visibleSelectionIDs.contains(thumbnailSelectionAnchorID) {
                self.thumbnailSelectionAnchorID = visibleSelectionIDs.first
            }
            return
        }

        if let firstEntry = visibleThumbnailEntries.first {
            thumbnailSelectionIDs = [firstEntry.id]
            thumbnailSelectionAnchorID = firstEntry.id
        } else {
            thumbnailSelectionIDs = []
            thumbnailSelectionAnchorID = nil
        }
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

        let currentIndex = primaryThumbnailSelectionID.flatMap { selectionID in
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
        thumbnailSelectionIDs = [entry.id]
        thumbnailSelectionAnchorID = entry.id

        switch entry {
        case .folder(let folderEntry):
            library.expandFolder(folderEntry.folder)
        case .item(let itemEntry):
            library.selectedID = itemEntry.item.id
        }
    }

    private func handleThumbnailEntryTap(_ entry: ThumbnailPanelEntry) {
        activePanel = .thumbnail

        let flags = NSApp.currentEvent?.modifierFlags ?? []
        if flags.contains(.shift) {
            selectThumbnailRange(through: entry)
        } else if flags.contains(.command) {
            toggleThumbnailSelection(entry)
        } else {
            thumbnailSelectionIDs = [entry.id]
            thumbnailSelectionAnchorID = entry.id
        }

        if let item = entry.item {
            library.selectedID = item.id
        }
    }

    private func selectThumbnailRange(through entry: ThumbnailPanelEntry) {
        let entries = visibleThumbnailEntries
        guard let targetIndex = entries.firstIndex(where: { $0.id == entry.id }) else {
            return
        }

        let anchorID = thumbnailSelectionAnchorID ?? primaryThumbnailSelectionID ?? entry.id
        guard let anchorIndex = entries.firstIndex(where: { $0.id == anchorID }) else {
            thumbnailSelectionIDs = [entry.id]
            thumbnailSelectionAnchorID = entry.id
            return
        }

        let range = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        thumbnailSelectionIDs = Set(entries[range].map(\.id))
    }

    private func toggleThumbnailSelection(_ entry: ThumbnailPanelEntry) {
        if thumbnailSelectionIDs.contains(entry.id) {
            thumbnailSelectionIDs.remove(entry.id)
            if thumbnailSelectionAnchorID == entry.id {
                thumbnailSelectionAnchorID = primaryThumbnailSelectionID
            }
        } else {
            thumbnailSelectionIDs.insert(entry.id)
            thumbnailSelectionAnchorID = entry.id
        }

        if thumbnailSelectionIDs.isEmpty {
            thumbnailSelectionAnchorID = nil
        }
    }

    private func moveToPreviousPanel() {
        guard activePanel == .pinned else { return }
        activePanel = .thumbnail
        if let selectedID = library.selectedID,
           visibleThumbnailEntries.contains(where: { $0.id == selectedID }) {
            thumbnailSelectionIDs = [selectedID]
            thumbnailSelectionAnchorID = selectedID
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

    private func addToEditorClips(_ item: MediaItem) {
        addToEditorClips([item])
    }

    private func addToEditorClips(_ items: [MediaItem]) {
        guard !items.isEmpty else { return }
        selectedTimelineClipID = nil
        selectedAdjustmentSpanID = nil

        for item in items {
            ensureEditorClip(for: item)
        }
        selectedEditorClipID = items.last?.id

        mainPanelState.show(.videoComposer)
    }

    private func addToTimeline(_ items: [MediaItem], activateComposer: Bool) {
        guard !items.isEmpty else { return }

        mainPanelState.show(.videoComposer, activate: activateComposer)

        var clipsToLoad: [EditorClip] = []
        for item in items {
            let sourceClipID = ensureEditorClip(for: item)
            if let clip = editorClips.first(where: { $0.id == sourceClipID }) {
                clipsToLoad.append(clip)
            }
            addTimelineClip(sourceClipID: sourceClipID)
        }

        for clip in clipsToLoad {
            Task {
                await loadEditorClipMetadataIfNeeded(for: clip)
            }
        }
    }

    @discardableResult
    private func ensureEditorClip(for item: MediaItem) -> EditorClip.ID {
        if !editorClips.contains(where: { $0.id == item.id }) {
            editorClips.append(EditorClip(
                item: item,
                thumbnail: library.thumbnails[item.url],
                status: item.id == selectedItem?.id ? selectedStatus : nil
            ))
        }

        return item.id
    }

    private func addTimelineClip(sourceClipID: EditorClip.ID) {
        guard editorClips.contains(where: { $0.id == sourceClipID }) else {
            return
        }

        let timelineClip = EditorTimelineClip(sourceClipID: sourceClipID)
        timelineClips.append(timelineClip)
        selectTimelineClip(timelineClip)
    }

    private func selectTimelineClip(_ timelineClip: EditorTimelineClip) {
        let shouldKeepAdjustmentSelection = selectedAdjustmentSpan.map { span in
            adjustmentSpan(span, overlaps: timelineClip)
        } ?? false

        selectedTimelineClipID = timelineClip.id
        selectedEditorClipID = nil

        if shouldKeepAdjustmentSelection {
            isPlayerCropToolActive = true
        } else {
            selectedAdjustmentSpanID = nil
            isPlayerCropToolActive = false
        }

        let timelineStart = timelineStartTime(for: timelineClip)
        timelinePlaybackTime = timelineStart
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelineStart)

        if let duration = editorClip(for: timelineClip)?.status?.duration {
            editorPlayerTime = timelineTrim(for: timelineClip, duration: duration).start
        } else {
            editorPlayerTime = 0
        }

        if shouldKeepAdjustmentSelection {
            syncAdjustmentCropDraft()
        }
    }

    private func handleTimelinePlaybackPosition(_ position: TimelinePlaybackPosition) {
        timelinePlaybackTime = position.timelineTime

        guard let clipID = position.clipID,
              timelineClips.contains(where: { $0.id == clipID })
        else {
            return
        }

        if selectedTimelineClipID != clipID {
            selectedTimelineClipID = clipID
            selectedEditorClipID = nil
        }

        editorPlayerTime = position.sourceTime
        syncTimelineAdjustmentSelection(to: position.timelineTime)
        syncAdjustmentCropDraft()
    }

    private func addActiveThumbnailToEditorClips() -> Bool {
        let selectedItems = selectedThumbnailItems
        if selectedItems.count > 1 {
            addToEditorClips(selectedItems)
            return true
        }

        guard let item = activeThumbnailItem() else {
            return false
        }

        addToEditorClips(item)
        return true
    }

    private func activeThumbnailItem() -> MediaItem? {
        guard activePanel == .thumbnail else {
            return nil
        }

        if let thumbnailSelectionID = primaryThumbnailSelectionID,
           let item = visibleThumbnailEntries.first(where: { $0.id == thumbnailSelectionID })?.item {
            return item
        }

        return thumbnailSelectionIDs.isEmpty ? selectedItem : nil
    }

    private func removeEditorClip(_ clip: EditorClip) {
        editorClips.removeAll { $0.id == clip.id }
        timelineClips.removeAll { $0.sourceClipID == clip.id }
        clampAdjustmentSpansToTimeline()
        if selectedEditorClipID == clip.id {
            selectedEditorClipID = editorClips.first?.id
        }
        if let selectedTimelineClipID,
           !timelineClips.contains(where: { $0.id == selectedTimelineClipID }) {
            if let firstTimelineClip = timelineClips.first {
                selectTimelineClip(firstTimelineClip)
            } else {
                self.selectedTimelineClipID = nil
                timelinePlaybackTime = 0
                editorPlayerTime = 0
            }
        }
    }

    private func importEditorClips() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Import"
        panel.message = "Choose media files to add to clips."

        guard panel.runModal() == .OK else {
            return
        }

        for url in panel.urls.map(\.standardizedFileURL) {
            guard let kind = MediaItem.kind(for: url) else {
                continue
            }
            addToEditorClips(MediaItem(id: url, url: url, kind: kind))
        }
    }

    private func editorClipThumbnail(for clip: EditorClip) -> NSImage? {
        clip.thumbnail ?? library.thumbnails[clip.item.url]
    }

    private func editorClip(for timelineClip: EditorTimelineClip) -> EditorClip? {
        editorClips.first { $0.id == timelineClip.sourceClipID }
    }

    private func timelineAdjustmentBinding<Value>(
        _ keyPath: WritableKeyPath<EditorTimelineAdjustments, Value>,
        default defaultValue: Value
    ) -> Binding<Value> {
        Binding {
            selectedTimelineClip?.adjustments[keyPath: keyPath] ?? defaultValue
        } set: { newValue in
            updateSelectedTimelineAdjustments { adjustments in
                adjustments[keyPath: keyPath] = newValue
            }
        }
    }

    private func updateSelectedTimelineAdjustments(_ update: (inout EditorTimelineAdjustments) -> Void) {
        guard let selectedTimelineClipID,
              let index = timelineClips.firstIndex(where: { $0.id == selectedTimelineClipID })
        else {
            return
        }

        update(&timelineClips[index].adjustments)
    }

    private func timelineTrim(for clip: EditorTimelineClip, duration: TimeInterval) -> MediaTrim {
        (clip.trim ?? .full(duration: duration)).clamped(to: duration)
    }

    private func timelineDuration(for clip: EditorTimelineClip) -> TimeInterval {
        guard let duration = editorClip(for: clip)?.status?.duration else {
            return 10
        }

        return timelineTrim(for: clip, duration: duration).duration
    }

    private var actualTimelineDuration: TimeInterval {
        timelineClips.reduce(TimeInterval(0)) { total, clip in
            total + max(0, clip.leadingGap) + timelineDuration(for: clip)
        }
    }

    private var totalTimelineDuration: TimeInterval {
        max(actualTimelineDuration, 30)
    }

    private var timelineSeekableDuration: TimeInterval {
        timelineClips.isEmpty ? totalTimelineDuration : max(actualTimelineDuration, 0)
    }

    private var timelineMarkerInterval: TimeInterval {
        switch timelineZoom {
        case 0.75...:
            return 5
        case 0.5..<0.75:
            return 10
        case 0.25..<0.5:
            return 30
        case 0.1..<0.25:
            return 60
        default:
            return 120
        }
    }

    private var timelineMinorMarkerInterval: TimeInterval {
        if timelineMarkerInterval <= 5 {
            return 1
        }

        if timelineMarkerInterval <= 10 {
            return 2
        }

        if timelineMarkerInterval <= 30 {
            return 5
        }

        if timelineMarkerInterval <= 60 {
            return 15
        }

        return 30
    }

    private func timelineContentWidth(for duration: TimeInterval, minimumWidth: CGFloat) -> CGFloat {
        max(
            minimumWidth,
            timelineTrackHeaderWidth + CGFloat(duration) * timelinePixelsPerSecond + timelineRulerLabelTrailingPadding
        )
    }

    private func timelineDurationToFillWidth(_ width: CGFloat) -> TimeInterval {
        TimeInterval(max(width - timelineTrackHeaderWidth, 0) / max(timelinePixelsPerSecond, 0.1))
    }

    private func autoZoomTimelineForFirstClip() {
        guard let firstClip = timelineClips.first else { return }
        guard autoZoomedTimelineClipID != firstClip.id else { return }
        let duration = timelineDuration(for: firstClip)
        guard duration > 0, timelineRulerWidth > 0 else { return }

        let availableWidth = max(timelineRulerWidth - timelineTrackHeaderWidth, 1)
        let targetFraction: CGFloat = 0.125
        let rawZoom = (targetFraction * availableWidth) / (timelineBasePixelsPerSecond * CGFloat(duration))
        let clamped = min(max(Double(rawZoom), timelineZoomRange.lowerBound), timelineZoomRange.upperBound)

        autoZoomedTimelineClipID = firstClip.id
        withAnimation(.easeInOut(duration: 0.25)) {
            timelineZoom = clamped
        }
    }

    private func timelineClipWidth(for clip: EditorTimelineClip) -> CGFloat {
        max(CGFloat(timelineDuration(for: clip)) * timelinePixelsPerSecond, 18)
    }

    private func timelineRange(for clip: EditorTimelineClip) -> MediaTrim {
        let start = timelineStartTime(for: clip)
        return MediaTrim(start: start, end: start + timelineDuration(for: clip))
    }

    private func adjustmentSpan(_ span: TimelineAdjustmentSpan, overlaps clip: EditorTimelineClip) -> Bool {
        let clipRange = timelineRange(for: clip)
        return span.start < clipRange.end && span.end > clipRange.start
    }

    private func selectAdjustmentSpan(_ span: TimelineAdjustmentSpan) {
        selectedAdjustmentSpanID = span.id
        selectedEditorClipID = nil

        if !span.contains(timelinePlaybackTime) {
            seekTimelinePlayhead(to: span.start)
        }

        syncAdjustmentCropDraft()
        isPlayerCropToolActive = true
        isCropToolActive = false
        isTrimToolActive = false
    }

    private func addAdjustmentCropSpan() {
        guard actualTimelineDuration > 0,
              let range = newAdjustmentSpanRange()
        else {
            return
        }

        let crop = defaultAdjustmentCrop()
        let span = TimelineAdjustmentSpan(
            start: range.start,
            end: range.end,
            keyframes: [TimelineCropKeyframe(time: range.start, crop: crop)]
        ).normalized(to: actualTimelineDuration)

        adjustmentSpans.append(span)
        adjustmentSpans.sort { $0.start < $1.start }
        adjustmentCropDraft = crop
        selectAdjustmentSpan(span)
    }

    private func moveAdjustmentSpan(_ span: TimelineAdjustmentSpan, proposedStart: TimeInterval) {
        guard let index = adjustmentSpans.firstIndex(where: { $0.id == span.id }),
              actualTimelineDuration > 0
        else {
            return
        }

        let range = TimelineAdjustmentSpan.clampedMoveRange(
            start: span.start,
            end: span.end,
            proposedStart: proposedStart,
            timelineDuration: actualTimelineDuration,
            occupiedRanges: occupiedAdjustmentRanges(excluding: span.id)
        )
        let delta = range.start - span.start
        adjustmentSpans[index].start = range.start
        adjustmentSpans[index].end = range.end
        adjustmentSpans[index].keyframes = adjustmentSpans[index].keyframes.map { keyframe in
            TimelineCropKeyframe(id: keyframe.id, time: keyframe.time + delta, crop: keyframe.crop)
        }
        adjustmentSpans.sort { $0.start < $1.start }
        selectedAdjustmentSpanID = span.id
        syncAdjustmentCropDraft()
    }

    private func resizeAdjustmentSpanStart(_ span: TimelineAdjustmentSpan, proposedStart: TimeInterval) {
        guard let index = adjustmentSpans.firstIndex(where: { $0.id == span.id }),
              actualTimelineDuration > 0
        else {
            return
        }

        adjustmentSpans[index].start = TimelineAdjustmentSpan.clampedResizeStart(
            proposedStart: proposedStart,
            fixedEnd: span.end,
            timelineDuration: actualTimelineDuration,
            occupiedRanges: occupiedAdjustmentRanges(excluding: span.id)
        )
        adjustmentSpans[index] = adjustmentSpans[index].normalized(to: actualTimelineDuration)
        selectedAdjustmentSpanID = span.id
        syncAdjustmentCropDraft()
    }

    private func resizeAdjustmentSpanEnd(_ span: TimelineAdjustmentSpan, proposedEnd: TimeInterval) {
        guard let index = adjustmentSpans.firstIndex(where: { $0.id == span.id }),
              actualTimelineDuration > 0
        else {
            return
        }

        adjustmentSpans[index].end = TimelineAdjustmentSpan.clampedResizeEnd(
            fixedStart: span.start,
            proposedEnd: proposedEnd,
            timelineDuration: actualTimelineDuration,
            occupiedRanges: occupiedAdjustmentRanges(excluding: span.id)
        )
        adjustmentSpans[index] = adjustmentSpans[index].normalized(to: actualTimelineDuration)
        selectedAdjustmentSpanID = span.id
        syncAdjustmentCropDraft()
    }

    private func removeAdjustmentSpan(_ span: TimelineAdjustmentSpan) {
        adjustmentSpans.removeAll { $0.id == span.id }
        if selectedAdjustmentSpanID == span.id {
            selectedAdjustmentSpanID = nil
            adjustmentCropDraft = defaultAdjustmentCrop()
            isPlayerCropToolActive = false
        }
    }

    private func moveAdjustmentKeyframe(
        _ keyframeID: TimelineCropKeyframe.ID,
        in spanID: TimelineAdjustmentSpan.ID,
        proposedTime: TimeInterval
    ) {
        guard let spanIndex = adjustmentSpans.firstIndex(where: { $0.id == spanID }) else { return }
        var span = adjustmentSpans[spanIndex]
        guard let keyframeIndex = span.keyframes.firstIndex(where: { $0.id == keyframeID }) else { return }

        let clampedTime = min(max(proposedTime, span.start), span.end)
        span.keyframes[keyframeIndex].time = clampedTime
        span.keyframes.sort { $0.time < $1.time }
        adjustmentSpans[spanIndex] = span

        if selectedAdjustmentSpanID == span.id {
            syncAdjustmentCropDraft()
        }
    }

    private func deleteAdjustmentKeyframe(_ keyframeID: TimelineCropKeyframe.ID, from span: TimelineAdjustmentSpan) {
        guard let index = adjustmentSpans.firstIndex(where: { $0.id == span.id }) else {
            return
        }

        selectedAdjustmentSpanID = span.id
        adjustmentSpans[index].keyframes.removeAll { $0.id == keyframeID }
        if adjustmentSpans[index].keyframes.isEmpty {
            removeAdjustmentSpan(adjustmentSpans[index])
        } else {
            syncAdjustmentCropDraft()
        }
    }

    private func clampAdjustmentSpansToTimeline() {
        let timelineDuration = actualTimelineDuration
        guard timelineDuration > 0 else {
            adjustmentSpans.removeAll()
            selectedAdjustmentSpanID = nil
            return
        }

        var clampedSpans: [TimelineAdjustmentSpan] = []
        for span in adjustmentSpans
            .map({ $0.normalized(to: timelineDuration) })
            .sorted(by: { $0.start < $1.start }) {
            let occupiedRanges = clampedSpans.map { MediaTrim(start: $0.start, end: $0.end) }
            let range = TimelineAdjustmentSpan.clampedMoveRange(
                start: span.start,
                end: span.end,
                proposedStart: span.start,
                timelineDuration: timelineDuration,
                occupiedRanges: occupiedRanges
            )
            guard range.duration >= TimelineAdjustmentSpan.minimumDuration,
                  !occupiedRanges.contains(where: { range.start < $0.end && range.end > $0.start })
            else {
                continue
            }

            let delta = range.start - span.start
            clampedSpans.append(TimelineAdjustmentSpan(
                id: span.id,
                start: range.start,
                end: range.end,
                keyframes: span.keyframes.map { keyframe in
                    TimelineCropKeyframe(id: keyframe.id, time: keyframe.time + delta, crop: keyframe.crop)
                }
            ).normalized(to: timelineDuration))
        }

        adjustmentSpans = clampedSpans

        if let selectedAdjustmentSpanID,
           !adjustmentSpans.contains(where: { $0.id == selectedAdjustmentSpanID }) {
            self.selectedAdjustmentSpanID = nil
            isPlayerCropToolActive = false
        }
    }

    private func updateAdjustmentCropDraft(_ crop: NormalizedCrop) {
        let sizeChanged = abs(crop.width - adjustmentCropDraft.width) > 0.000_1
            || abs(crop.height - adjustmentCropDraft.height) > 0.000_1
        if selectedAdjustmentSpan != nil, sizeChanged {
            adjustmentSpans = adjustmentSpans.map { span in
                span.replacingCropSize(width: crop.width, height: crop.height)
            }
        }

        adjustmentCropDraft = crop
    }

    private func syncAdjustmentCropDraft() {
        guard let selectedAdjustmentSpan else {
            return
        }

        let time = min(max(timelinePlaybackTime, selectedAdjustmentSpan.start), selectedAdjustmentSpan.end)
        adjustmentCropDraft = selectedAdjustmentSpan.crop(at: time)
            ?? selectedAdjustmentSpan.crop(at: selectedAdjustmentSpan.start)
            ?? defaultAdjustmentCrop()
    }

    private func applyAdjustmentCropKeyframe() {
        guard let selectedAdjustmentSpan,
              let index = adjustmentSpans.firstIndex(where: { $0.id == selectedAdjustmentSpan.id })
        else {
            return
        }

        let time = min(max(timelinePlaybackTime, selectedAdjustmentSpan.start), selectedAdjustmentSpan.end)
        let crop = adjustmentCropDraft.clamped()
        guard !crop.isFullFrame else {
            return
        }

        adjustmentSpans[index] = adjustmentSpans[index].upsertingKeyframe(at: time, crop: crop)
        timelinePlaybackTime = time
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: time)
        isPlayerCropToolActive = true
        syncAdjustmentCropDraft()
    }

    private func defaultAdjustmentCrop() -> NormalizedCrop {
        adjustmentCropPreset(width: 9, height: 16)
    }

    private func adjustmentCropPreset(width: CGFloat, height: CGFloat) -> NormalizedCrop {
        NormalizedCrop.centered(
            aspectRatio: width / height,
            naturalSize: adjustmentCropReferenceSize
        )
    }

    private var adjustmentCropReferenceSize: CGSize {
        for timelineClip in timelineClips {
            if let size = editorClip(for: timelineClip)?.status?.size,
               size.width > 0,
               size.height > 0 {
                return size
            }
        }

        return CGSize(width: 16, height: 9)
    }

    private func newAdjustmentSpanRange() -> MediaTrim? {
        let preferredRange: MediaTrim
        if let selectedTimelineClip {
            let start = timelineStartTime(for: selectedTimelineClip)
            preferredRange = MediaTrim(start: start, end: start + timelineDuration(for: selectedTimelineClip))
        } else {
            preferredRange = MediaTrim(start: 0, end: actualTimelineDuration)
        }

        let duration = min(max(preferredRange.duration, TimelineAdjustmentSpan.minimumDuration), actualTimelineDuration)
        let gaps = adjustmentGaps(excluding: nil)
            .filter { $0.duration >= TimelineAdjustmentSpan.minimumDuration }
        guard !gaps.isEmpty else {
            return nil
        }

        let bestGap = gaps.min { lhs, rhs in
            let lhsStart = min(max(preferredRange.start, lhs.start), max(lhs.start, lhs.end - min(duration, lhs.duration)))
            let rhsStart = min(max(preferredRange.start, rhs.start), max(rhs.start, rhs.end - min(duration, rhs.duration)))
            return abs(lhsStart - preferredRange.start) < abs(rhsStart - preferredRange.start)
        } ?? gaps[0]
        let nextDuration = min(duration, bestGap.duration)
        let nextStart = min(max(preferredRange.start, bestGap.start), bestGap.end - nextDuration)
        return MediaTrim(start: nextStart, end: nextStart + nextDuration)
    }

    private func occupiedAdjustmentRanges(excluding id: TimelineAdjustmentSpan.ID?) -> [MediaTrim] {
        adjustmentSpans
            .filter { $0.id != id }
            .map { MediaTrim(start: $0.start, end: $0.end) }
    }

    private func adjustmentGaps(excluding id: TimelineAdjustmentSpan.ID?) -> [MediaTrim] {
        let timelineDuration = actualTimelineDuration
        guard timelineDuration > 0 else {
            return []
        }

        let ranges = occupiedAdjustmentRanges(excluding: id)
            .map { MediaTrim(start: min(max($0.start, 0), timelineDuration), end: min(max($0.end, 0), timelineDuration)) }
            .filter { $0.duration > 0 }
            .sorted { $0.start < $1.start }
        var gaps: [MediaTrim] = []
        var cursor = TimeInterval(0)

        for range in ranges {
            if range.start > cursor {
                gaps.append(MediaTrim(start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }

        if cursor < timelineDuration {
            gaps.append(MediaTrim(start: cursor, end: timelineDuration))
        }

        return gaps
    }

    private func clampedTimelinePlayheadTime(_ time: TimeInterval) -> TimeInterval {
        min(max(time, 0), max(timelineSeekableDuration, 0))
    }

    private func seekTimelinePlayhead(to time: TimeInterval) {
        let timelineTime = clampedTimelinePlayheadTime(time)
        timelinePlaybackTime = timelineTime
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelineTime)
        syncTimelineSelection(to: timelineTime)
        syncTimelineAdjustmentSelection(to: timelineTime)
    }

    private func syncTimelineSelection(to timelineTime: TimeInterval) {
        guard !timelineClips.isEmpty else {
            selectedTimelineClipID = nil
            editorPlayerTime = 0
            return
        }

        let timelineTime = clampedTimelinePlayheadTime(timelineTime)
        var cursor = TimeInterval(0)

        for index in timelineClips.indices {
            let clip = timelineClips[index]
            let duration = timelineDuration(for: clip)
            let end = cursor + duration
            let isLastClip = index == timelineClips.index(before: timelineClips.endIndex)
            let containsTime = timelineTime >= cursor
                && (timelineTime < end || (isLastClip && timelineTime <= end) || (duration <= 0 && timelineTime == cursor))

            if containsTime {
                selectedTimelineClipID = clip.id
                selectedEditorClipID = nil

                if let sourceDuration = editorClip(for: clip)?.status?.duration {
                    let trim = timelineTrim(for: clip, duration: sourceDuration)
                    let sourceTime = trim.start + max(0, timelineTime - cursor)
                    editorPlayerTime = min(max(sourceTime, trim.start), trim.end)
                } else {
                    editorPlayerTime = 0
                }
                return
            }

            cursor = end
        }
    }

    private func syncTimelineAdjustmentSelection(to timelineTime: TimeInterval) {
        let timelineTime = clampedTimelinePlayheadTime(timelineTime)
        let sortedSpans = adjustmentSpans.sorted { $0.start < $1.start }
        let activeSpan = sortedSpans.indices.lazy.compactMap { index -> TimelineAdjustmentSpan? in
            let span = sortedSpans[index]
            let isLastSpan = index == sortedSpans.index(before: sortedSpans.endIndex)
            let containsTime =
                timelineTime >= span.start
                && (timelineTime < span.end || (isLastSpan && abs(timelineTime - span.end) < 0.000_1))
            return containsTime ? span : nil
        }.first

        let activeSpanID = activeSpan?.id
        let needsOverlayActivation = activeSpan != nil && !isPlayerCropToolActive

        guard selectedAdjustmentSpanID != activeSpanID || needsOverlayActivation else {
            return
        }

        selectedAdjustmentSpanID = activeSpanID
        if activeSpan != nil {
            selectedEditorClipID = nil
            isPlayerCropToolActive = true
            isCropToolActive = false
            isTrimToolActive = false
        } else if isPlayerCropToolActive {
            isPlayerCropToolActive = false
        }

        if isPlayerCropToolActive {
            syncAdjustmentCropDraft()
        }
    }

    private func timelineStartTime(for targetClip: EditorTimelineClip) -> TimeInterval {
        var cursor = TimeInterval(0)
        for clip in timelineClips {
            cursor += max(0, clip.leadingGap)
            if clip.id == targetClip.id {
                return cursor
            }
            cursor += timelineDuration(for: clip)
        }

        return 0
    }

    private var selectedTimelineClipHasTrim: Bool {
        guard let selectedTimelineClip,
              let duration = editorClip(for: selectedTimelineClip)?.status?.duration
        else {
            return false
        }

        return !timelineTrim(for: selectedTimelineClip, duration: duration).isFullLength(for: duration)
    }

    private var selectedTimelineSplitTime: TimeInterval? {
        guard let selectedTimelineClip,
              let duration = editorClip(for: selectedTimelineClip)?.status?.duration
        else {
            return nil
        }

        let trim = timelineTrim(for: selectedTimelineClip, duration: duration)
        return min(max(editorPlayerTime, trim.start), trim.end)
    }

    private var canSplitSelectedTimelineClip: Bool {
        guard let selectedTimelineClip,
              let duration = editorClip(for: selectedTimelineClip)?.status?.duration,
              let splitTime = selectedTimelineSplitTime
        else {
            return false
        }

        let trim = timelineTrim(for: selectedTimelineClip, duration: duration)
        return splitTime - trim.start >= MediaTrim.minimumDuration
            && trim.end - splitTime >= MediaTrim.minimumDuration
    }

    private func updateTimelineClipTrim(_ clip: EditorTimelineClip, trim: MediaTrim) {
        guard let index = timelineClips.firstIndex(where: { $0.id == clip.id }),
              let duration = editorClip(for: clip)?.status?.duration
        else {
            return
        }

        let nextTrim = trim.clamped(to: duration)

        timelineClips[index].trim = nextTrim.isFullLength(for: duration) ? nil : nextTrim
        clampAdjustmentSpansToTimeline()

        if selectedTimelineClipID == clip.id {
            editorPlayerTime = min(max(editorPlayerTime, nextTrim.start), nextTrim.end)
            let timelineTime = timelineStartTime(for: timelineClips[index]) + max(0, editorPlayerTime - nextTrim.start)
            timelinePlaybackTime = timelineTime
            timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelineTime)
        }
    }

    private func resetSelectedTimelineTrim() {
        guard let selectedTimelineClip,
              let index = timelineClips.firstIndex(where: { $0.id == selectedTimelineClip.id }),
              let duration = editorClip(for: selectedTimelineClip)?.status?.duration
        else {
            return
        }

        timelineClips[index].trim = nil
        clampAdjustmentSpansToTimeline()
        editorPlayerTime = min(max(editorPlayerTime, 0), duration)
        let timelineTime = timelineStartTime(for: timelineClips[index]) + editorPlayerTime
        timelinePlaybackTime = timelineTime
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelineTime)
    }

    private func splitSelectedTimelineClip() {
        guard let selectedTimelineClip,
              let index = timelineClips.firstIndex(where: { $0.id == selectedTimelineClip.id }),
              let duration = editorClip(for: selectedTimelineClip)?.status?.duration,
              let splitTime = selectedTimelineSplitTime
        else {
            return
        }

        let trim = timelineTrim(for: selectedTimelineClip, duration: duration)
        guard splitTime - trim.start >= MediaTrim.minimumDuration,
              trim.end - splitTime >= MediaTrim.minimumDuration
        else {
            return
        }

        let splitTimelineTime = timelineStartTime(for: selectedTimelineClip) + (splitTime - trim.start)

        timelineClips[index].trim = MediaTrim(start: trim.start, end: splitTime).clamped(to: duration)
        let rightClip = EditorTimelineClip(
            sourceClipID: selectedTimelineClip.sourceClipID,
            trim: MediaTrim(start: splitTime, end: trim.end).clamped(to: duration)
        )
        timelineClips.insert(rightClip, at: timelineClips.index(after: index))
        splitAdjustmentSpans(at: splitTimelineTime)
        selectTimelineClip(rightClip)
        editorPlayerTime = splitTime
        timelinePlaybackTime = timelineStartTime(for: rightClip)
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelinePlaybackTime)
    }

    private func splitAdjustmentSpans(at splitTimelineTime: TimeInterval) {
        let tolerance = TimelineAdjustmentSpan.keyframeMergeTolerance
        var nextSpans: [TimelineAdjustmentSpan] = []
        var didSplit = false

        for span in adjustmentSpans {
            guard span.start + tolerance < splitTimelineTime,
                  span.end - tolerance > splitTimelineTime
            else {
                nextSpans.append(span)
                continue
            }

            let cropAtSplit = span.crop(at: splitTimelineTime) ?? defaultAdjustmentCrop()
            let leftKeyframes = span.keyframes.filter { $0.time < splitTimelineTime - tolerance }
            let rightKeyframes = span.keyframes.filter { $0.time > splitTimelineTime + tolerance }

            var left = TimelineAdjustmentSpan(
                start: span.start,
                end: splitTimelineTime,
                keyframes: leftKeyframes
            )
            var right = TimelineAdjustmentSpan(
                start: splitTimelineTime,
                end: span.end,
                keyframes: rightKeyframes
            )

            if (left.keyframes.last?.time ?? -.infinity) < splitTimelineTime - tolerance {
                left.keyframes.append(TimelineCropKeyframe(time: splitTimelineTime, crop: cropAtSplit))
            }
            if (right.keyframes.first?.time ?? .infinity) > splitTimelineTime + tolerance {
                right.keyframes.insert(
                    TimelineCropKeyframe(time: splitTimelineTime, crop: cropAtSplit),
                    at: 0
                )
            }

            if left.duration >= TimelineAdjustmentSpan.minimumDuration {
                nextSpans.append(left)
            }
            if right.duration >= TimelineAdjustmentSpan.minimumDuration {
                nextSpans.append(right)
            }
            didSplit = true
        }

        guard didSplit else { return }

        nextSpans.sort { $0.start < $1.start }
        adjustmentSpans = nextSpans

        if let selectedID = selectedAdjustmentSpanID,
           !adjustmentSpans.contains(where: { $0.id == selectedID }) {
            selectedAdjustmentSpanID = nil
            adjustmentCropDraft = defaultAdjustmentCrop()
            isPlayerCropToolActive = false
        }
    }

    private func activeEditorPreviewID(for clip: EditorClip) -> String {
        if let selectedTimelineClipID {
            return selectedTimelineClipID.uuidString
        }

        return clip.id.absoluteString
    }

    private func dragPayload(for clip: EditorClip) -> String {
        EditorDragPayload.editorClipPayload(for: clip.id)
    }

    private func timelineDragPayload(for clip: EditorTimelineClip) -> String {
        EditorDragPayload.timelineClipPayload(for: clip.id)
    }

    private func handleTimelineDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { item, _ in
            let payload: String?
            if let data = item as? Data {
                payload = String(data: data, encoding: .utf8)
            } else if let string = item as? String {
                payload = string
            } else if let string = item as? NSString {
                payload = string as String
            } else {
                payload = nil
            }

            guard let payload else {
                return
            }

            if EditorDragPayload.timelineClipID(from: payload) != nil {
                Task { @MainActor in
                    draggingTimelineClipID = nil
                }
                return
            }

            if let sourceClipID = EditorDragPayload.editorClipID(from: payload) {
                Task { @MainActor in
                    addTimelineClip(sourceClipID: sourceClipID)
                }
            }
        }

        return true
    }

    private func moveTimelineClip(
        _ draggedID: EditorTimelineClip.ID,
        around targetID: EditorTimelineClip.ID
    ) {
        guard draggedID != targetID,
              let fromIndex = timelineClips.firstIndex(where: { $0.id == draggedID }),
              let toIndex = timelineClips.firstIndex(where: { $0.id == targetID })
        else {
            return
        }

        withAnimation(.snappy(duration: 0.16)) {
            timelineClips.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex
            )
        }

        selectedTimelineClipID = draggedID
        selectedAdjustmentSpanID = nil
        isPlayerCropToolActive = false
        syncTimelinePlaybackToSelectedClip()
    }

    private func syncTimelinePlaybackToSelectedClip() {
        guard let selectedTimelineClip,
              let duration = editorClip(for: selectedTimelineClip)?.status?.duration
        else {
            return
        }

        let trim = timelineTrim(for: selectedTimelineClip, duration: duration)
        editorPlayerTime = min(max(editorPlayerTime, trim.start), trim.end)
        let timelineTime = timelineStartTime(for: selectedTimelineClip) + max(0, editorPlayerTime - trim.start)
        timelinePlaybackTime = timelineTime
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelineTime)
    }

    private func removeTimelineClip(_ clip: EditorTimelineClip, ripple: Bool = false) {
        guard let removedIndex = timelineClips.firstIndex(where: { $0.id == clip.id }) else {
            return
        }

        let removedClip = timelineClips[removedIndex]
        let removedDuration = timelineDuration(for: removedClip)
        let removedLeadingGap = max(0, removedClip.leadingGap)
        let removedClipStart = timelineStartTime(for: removedClip)
        let removedSpan = removedLeadingGap + removedDuration

        timelineClips.remove(at: removedIndex)

        if ripple {
            shiftAdjustmentSpansLeft(after: removedClipStart, by: removedSpan)
        } else if removedIndex < timelineClips.count {
            timelineClips[removedIndex].leadingGap += removedSpan
        }

        clampAdjustmentSpansToTimeline()

        if selectedTimelineClipID == clip.id {
            if !timelineClips.isEmpty {
                let nextIndex = min(removedIndex, timelineClips.index(before: timelineClips.endIndex))
                selectTimelineClip(timelineClips[nextIndex])
            } else {
                selectedTimelineClipID = nil
                timelinePlaybackTime = 0
                editorPlayerTime = 0
            }
        }
    }

    private func shiftAdjustmentSpansLeft(after referenceTime: TimeInterval, by amount: TimeInterval) {
        guard amount > 0 else { return }
        let tolerance = TimelineAdjustmentSpan.keyframeMergeTolerance

        adjustmentSpans = adjustmentSpans.map { span in
            guard span.start >= referenceTime - tolerance else { return span }
            let newStart = max(0, span.start - amount)
            let newEnd = max(newStart, span.end - amount)
            let shiftedKeyframes = span.keyframes.map { keyframe in
                TimelineCropKeyframe(
                    id: keyframe.id,
                    time: max(0, keyframe.time - amount),
                    crop: keyframe.crop
                )
            }
            return TimelineAdjustmentSpan(
                id: span.id,
                start: newStart,
                end: newEnd,
                keyframes: shiftedKeyframes
            )
        }
    }

    private func removeSelectedTimelineSelection(ripple: Bool = false) {
        let spanToRemove = selectedAdjustmentSpan
        let clipToRemove = selectedTimelineClip

        if let spanToRemove {
            removeAdjustmentSpan(spanToRemove)
        }

        if let clipToRemove {
            removeTimelineClip(clipToRemove, ripple: ripple)
        }
    }

    private func exportTimeline() {
        guard !timelineClips.isEmpty, !isExportingTimeline else {
            return
        }

        let exportClips = timelineExportClips()
        guard !exportClips.isEmpty else {
            showTimelineExportFailure(MediaExportError.emptyTimeline)
            return
        }

        let allWebPSources = exportClips.allSatisfy { $0.item.kind == .webp }
        let allVideoSources = exportClips.allSatisfy { $0.item.kind == .video }
        guard allWebPSources || allVideoSources else {
            showTimelineExportFailure(MediaExportError.unsupportedTimelineClip)
            return
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = allWebPSources ? [.webP] : [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = allWebPSources ? "Timeline Export.webp" : "Timeline Export.mp4"
        panel.directoryURL = library.folderURL
        panel.message = "Choose where to save the timeline export."

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isExportingTimeline = true
        Task {
            do {
                try await MediaExport.exportTimeline(
                    exportClips,
                    adjustmentSpans: adjustmentSpans,
                    to: destinationURL
                )
                showTimelineExportSuccess(destinationURL)
            } catch {
                showTimelineExportFailure(error)
            }
            isExportingTimeline = false
        }
    }

    private func timelineExportClips() -> [TimelineExportClip] {
        timelineClips.compactMap { timelineClip in
            guard let sourceClip = editorClip(for: timelineClip) else {
                return nil
            }

            let adjustments = timelineClip.adjustments
            return TimelineExportClip(
                item: sourceClip.item,
                trim: timelineClip.trim,
                volume: adjustments.isMuted ? 0 : Float(adjustments.volume)
            )
        }
    }

    private func showTimelineExportSuccess(_ destinationURL: URL) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Timeline Exported"
        alert.informativeText = "Saved timeline export to \(destinationURL.path)."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showTimelineExportFailure(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Timeline Export Failed"
        alert.runModal()
    }

    @MainActor
    private func loadEditorClipMetadataIfNeeded(for clip: EditorClip) async {
        guard let index = editorClips.firstIndex(where: { $0.id == clip.id }) else {
            return
        }

        var thumbnail = editorClips[index].thumbnail ?? library.thumbnails[clip.item.url]
        var status = editorClips[index].status

        if thumbnail == nil {
            thumbnail = await ThumbnailProvider.thumbnail(for: clip.item)
        }

        if status == nil {
            status = await MediaMetadata.status(for: clip.item)
        }

        guard let currentIndex = editorClips.firstIndex(where: { $0.id == clip.id }) else {
            return
        }
        editorClips[currentIndex].thumbnail = thumbnail
        editorClips[currentIndex].status = status

        autoZoomTimelineForFirstClip()

        if editorClips[currentIndex].filmstrip == nil,
           clip.item.kind == .video,
           let duration = status?.duration,
           duration > 0 {
            let url = clip.item.url
            if let filmstrip = await MediaFilmstrip.generate(for: url, duration: duration),
               let updateIndex = editorClips.firstIndex(where: { $0.id == clip.id }) {
                editorClips[updateIndex].filmstrip = filmstrip
            }
        }
    }

    private func pin(_ item: MediaItem, crop: NormalizedCrop? = nil, trim: MediaTrim? = nil) {
        let normalizedCrop = crop?.clamped()
        let normalizedTrim: MediaTrim?
        if let trim,
           let duration = selectedStatus.duration,
           !trim.isFullLength(for: duration) {
            normalizedTrim = trim.clamped(to: duration)
        } else {
            normalizedTrim = nil
        }

        if let index = pinnedItems.firstIndex(where: { $0.id == item.id }) {
            if let normalizedCrop, !normalizedCrop.isFullFrame {
                pinnedItems[index].crop = normalizedCrop
            }
            if let normalizedTrim {
                pinnedItems[index].trim = normalizedTrim
            }
            return
        }

        pinnedItems.append(PinnedMediaItem(
            item: item,
            crop: normalizedCrop?.isFullFrame == false ? normalizedCrop : nil,
            trim: normalizedTrim
        ))
        if let thumbnail = library.thumbnails[item.url] {
            pinnedThumbnails[item.url] = thumbnail
        }
    }

    private func pin(_ items: [MediaItem]) {
        for item in items {
            pin(item)
        }
    }

    private func pinActiveThumbnailOrPreview() {
        guard activePanel == .thumbnail else { return }

        let selectedItems = selectedThumbnailItems
        if selectedItems.count > 1 {
            pin(selectedItems)
            return
        }

        if let thumbnailSelectionID = primaryThumbnailSelectionID,
           let item = visibleThumbnailEntries.first(where: { $0.id == thumbnailSelectionID })?.item {
            pin(item)
            return
        }

        if let selectedItem {
            pin(selectedItem)
        }
    }

    private var selectedCanSnapshot: Bool {
        selectedItem?.kind == .video
    }

    private func snapshotSelectedPreviewFrame() {
        guard let item = selectedItem,
              item.kind == .video,
              !isCapturingSnapshot
        else {
            return
        }

        let snapshotTime = selectedSnapshotTime()
        let snapshotCrop = isCropToolActive ? .full : selectedAppliedCrop
        isCapturingSnapshot = true

        Task {
            do {
                let snapshot = try await MediaSnapshot.captureVideoFrame(
                    from: item,
                    at: snapshotTime,
                    crop: snapshotCrop
                )
                pinnedItems.append(PinnedMediaItem(item: snapshot.item))
                pinnedThumbnails[snapshot.item.url] = snapshot.thumbnail
                activePanel = .pinned
                library.selectedID = snapshot.item.id
            } catch {
                showSnapshotFailure(error)
            }
            isCapturingSnapshot = false
        }
    }

    private func snapshotActiveEditorFrame() {
        guard let item = activeEditorClip?.item,
              item.kind == .video,
              !isCapturingSnapshot
        else {
            return
        }

        let snapshotTime = activeEditorSnapshotTime()
        let snapshotCrop = isPlayerCropToolActive ? .full : activeEditorAppliedCrop
        isCapturingSnapshot = true

        Task {
            do {
                let snapshot = try await MediaSnapshot.captureVideoFrame(
                    from: item,
                    at: snapshotTime,
                    crop: snapshotCrop
                )
                pinnedItems.append(PinnedMediaItem(item: snapshot.item))
                pinnedThumbnails[snapshot.item.url] = snapshot.thumbnail
                activePanel = .pinned
                library.selectedID = snapshot.item.id
            } catch {
                showSnapshotFailure(error)
            }
            isCapturingSnapshot = false
        }
    }

    private func selectedSnapshotTime() -> TimeInterval {
        guard let duration = selectedStatus.duration else {
            return max(0, previewVideoTime)
        }

        let trim = selectedPreviewTrim?.clamped(to: duration)
        let lowerBound = trim?.start ?? 0
        let upperBound = trim?.end ?? duration
        return min(max(previewVideoTime, lowerBound), upperBound)
    }

    private func activeEditorSnapshotTime() -> TimeInterval {
        guard let duration = activeEditorClip?.status?.duration else {
            return max(0, editorPlayerTime)
        }

        let trim = activeTimelineTrimForPreview?.clamped(to: duration)
        let lowerBound = trim?.start ?? 0
        let upperBound = trim?.end ?? duration
        return min(max(editorPlayerTime, lowerBound), upperBound)
    }

    private func showSnapshotFailure(_ error: Error) {
        let alert = NSAlert(error: error)
        alert.messageText = "Snapshot Failed"
        alert.runModal()
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

    private func pinMenuTitle(for items: [MediaItem]) -> String {
        guard items.count > 1 else {
            return items.first.map(pinMenuTitle(for:)) ?? "Pin File"
        }

        let allPinned = items.allSatisfy { item in
            pinnedItems.contains(where: { $0.id == item.id })
        }
        return allPinned ? "Pinned" : "Pin \(items.count) Files"
    }

    private func editorClipMenuTitle(for item: MediaItem) -> String {
        editorClips.contains(where: { $0.id == item.id }) ? "Show in Clips" : "Add to Clips"
    }

    private func editorClipMenuTitle(for items: [MediaItem]) -> String {
        guard items.count > 1 else {
            return items.first.map(editorClipMenuTitle(for:)) ?? "Add to Clips"
        }

        let allInClips = items.allSatisfy { item in
            editorClips.contains(where: { $0.id == item.id })
        }
        return allInClips ? "Show in Clips" : "Add \(items.count) to Clips"
    }

    private func timelineClipMenuTitle(for items: [MediaItem]) -> String {
        guard items.count > 1 else {
            return "Add to Timeline"
        }

        return "Add \(items.count) to Timeline"
    }

    private func thumbnailContextItems(for item: MediaItem) -> [MediaItem] {
        let selectedItems = selectedThumbnailItems
        if selectedItems.count > 1,
           thumbnailSelectionIDs.contains(item.id) {
            return selectedItems
        }

        return [item]
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
                .stroke(theme.accent.opacity(0.55), lineWidth: 1)
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
        let activeTheme = theme
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first {
                window.title = "Frameflow"
                window.titleVisibility = .hidden
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = activeTheme.windowBackgroundNSColor
                window.titlebarAppearsTransparent = true
                if let titlebar = window.standardWindowButton(.closeButton)?.superview {
                    let titleLabelTag = 901_202
                    let label: NSTextField
                    if let existing = titlebar.viewWithTag(titleLabelTag) as? NSTextField {
                        label = existing
                    } else {
                        label = NSTextField(labelWithString: "Frameflow")
                        label.tag = titleLabelTag
                        label.font = .systemFont(ofSize: 13, weight: .semibold)
                        label.alignment = .center
                        titlebar.addSubview(label)
                    }
                    label.textColor = .white.withAlphaComponent(0.82)
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

