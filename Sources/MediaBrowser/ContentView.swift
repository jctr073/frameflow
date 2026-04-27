import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum EditorTheme {
    static let windowBackground = Color(red: 0.015, green: 0.017, blue: 0.018)
    static let canvasBackground = Color(red: 0.055, green: 0.060, blue: 0.064)
    static let panelBackground = Color(red: 0.075, green: 0.080, blue: 0.084)
    static let panelRaised = Color(red: 0.105, green: 0.110, blue: 0.115)
    static let toolbarBackground = Color(red: 0.095, green: 0.100, blue: 0.105)
    static let timelineBackground = Color(red: 0.060, green: 0.065, blue: 0.068)
    static let trackBackground = Color(red: 0.070, green: 0.076, blue: 0.080)
    static let trackAlternateBackground = Color(red: 0.080, green: 0.086, blue: 0.090)
    static let thumbnailWell = Color.black.opacity(0.74)
    static let clipBlue = Color(red: 0.135, green: 0.350, blue: 0.650)
    static let clipBlueSelected = Color(red: 0.165, green: 0.445, blue: 0.805)
    static let accent = Color(red: 1.000, green: 0.820, blue: 0.000)
    static let primaryText = Color.white.opacity(0.92)
    static let secondaryText = Color.white.opacity(0.56)
    static let mutedText = Color.white.opacity(0.36)
    static let hairline = Color.white.opacity(0.070)
}

private enum EditorDragPayload {
    static let editorClipPrefix = "editor-clip:"
    static let timelineClipPrefix = "timeline-clip:"

    static func editorClipPayload(for clipID: EditorClip.ID) -> String {
        "\(editorClipPrefix)\(clipID.absoluteString)"
    }

    static func timelineClipPayload(for clipID: EditorTimelineClip.ID) -> String {
        "\(timelineClipPrefix)\(clipID.uuidString)"
    }

    static func editorClipID(from payload: String) -> EditorClip.ID? {
        if payload.hasPrefix(editorClipPrefix) {
            let rawValue = String(payload.dropFirst(editorClipPrefix.count))
            return URL(string: rawValue)
        }

        return URL(string: payload)
    }

    static func timelineClipID(from payload: String) -> EditorTimelineClip.ID? {
        guard payload.hasPrefix(timelineClipPrefix) else {
            return nil
        }

        let rawValue = String(payload.dropFirst(timelineClipPrefix.count))
        return UUID(uuidString: rawValue)
    }
}

struct ContentView: View {
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
    @State private var draggingTimelineClipID: EditorTimelineClip.ID?
    @State private var editorPlayerTime: TimeInterval = 0
    @State private var timelinePlaybackTime: TimeInterval = 0
    @State private var timelineSeekRequest: TimelinePlaybackSeekRequest?
    @State private var isTimelineDropTargeted = false
    @State private var timelineZoom = 1.0
    @State private var isExportingTimeline = false
    @State private var activePanel: SidePanel = .thumbnail
    @State private var thumbnailSelectionID: URL?
    @State private var isCopyingPinnedFiles = false
    @State private var isCropToolActive = false
    @State private var isTrimToolActive = false
    @State private var isCapturingSnapshot = false
    @State private var previewVideoTime: TimeInterval = 0
    @State private var cropRects: [URL: NormalizedCrop] = [:]
    @State private var trimRanges: [URL: MediaTrim] = [:]
    @State private var appliedCrops: [URL: NormalizedCrop] = [:]
    @State private var appliedTrims: [URL: MediaTrim] = [:]

    private let initialFolderURL: URL?
    private let zoomLevels = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0]
    private let sidePanelRowInsets = EdgeInsets(top: 8, leading: 18, bottom: 8, trailing: 18)
    private let topToolbarHeight: CGFloat = 48
    private let timelineBasePixelsPerSecond: CGFloat = 12

    init(initialFolderURL: URL?, mainPanelState: MainPanelState) {
        self.initialFolderURL = initialFolderURL
        self.mainPanelState = mainPanelState
    }

    var body: some View {
        VStack(spacing: 6) {
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
        .padding(6)
        .background(EditorTheme.windowBackground)
        .tint(EditorTheme.accent)
        .accentColor(EditorTheme.accent)
        .preferredColorScheme(.dark)
        .overlay(dropOverlay)
        .quickTooltipOverlay()
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
            previewVideoTime = 0
            if activePanel == .thumbnail,
               let selectedID = library.selectedID,
               visibleThumbnailEntries.contains(where: { $0.id == selectedID }) {
                thumbnailSelectionID = selectedID
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
    }

    private var thumbnailPanel: some View {
        VStack(spacing: 0) {
            folderHeader
            filterControl

            if visibleThumbnailEntries.isEmpty {
                Text(thumbnailEmptyMessage)
                    .font(.callout)
                    .foregroundStyle(EditorTheme.secondaryText)
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
                                    Button(editorClipMenuTitle(for: itemEntry.item)) {
                                        addToEditorClips(itemEntry.item)
                                    }

                                    Button(pinMenuTitle(for: itemEntry.item)) {
                                        pin(itemEntry.item)
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(EditorTheme.panelBackground)
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
        .background(EditorTheme.panelBackground)
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
                .quickTooltip("Clear Pinned Files")
                .accessibilityLabel("Clear Pinned Files")

                Text("\(pinnedItems.count)")
                    .font(.caption)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .help("\(pinnedItems.count) Pinned Files")
            }
            .frame(height: topToolbarHeight)
            .padding(.horizontal, 10)
            .foregroundStyle(EditorTheme.primaryText)
            .background(EditorTheme.toolbarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 1)
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
                .scrollContentBackground(.hidden)
                .background(EditorTheme.panelBackground)
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
        .background(EditorTheme.panelBackground)
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
        .foregroundStyle(EditorTheme.primaryText)
        .background(EditorTheme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorTheme.hairline)
                .frame(height: 1)
        }
    }

    private var filterControl: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(EditorTheme.secondaryText)

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
                        .foregroundStyle(EditorTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .quickTooltip("Clear Filter")
                .accessibilityLabel("Clear Filter")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .foregroundStyle(EditorTheme.primaryText)
        .background(EditorTheme.panelBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorTheme.hairline)
                .frame(height: 1)
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
            .quickTooltip("Open Folder")
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
            .quickTooltip("Open Terminal Here")
            .accessibilityLabel("Open Terminal Here")

            Text(statusPathText)
                .font(.caption)
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(statusPathText)

            if !selectedStatus.detailText.isEmpty {
                Text(selectedStatus.detailText)
                    .font(.caption)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .help(selectedStatus.detailText)
            }

            Text(statusCountText)
                .font(.caption)
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(1)
                .help(statusCountText)
        }
        .frame(height: 28)
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .foregroundStyle(EditorTheme.primaryText)
        .background(EditorTheme.toolbarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(EditorTheme.hairline)
                .frame(height: 1)
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

    private var timelinePixelsPerSecond: CGFloat {
        timelineBasePixelsPerSecond * CGFloat(timelineZoom)
    }

    private var visibleEditorTabs: [MainPanelTab] {
        [.preview, .videoEditor].filter { mainPanelState.isVisible($0) }
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

    private var mainPanel: some View {
        VStack(spacing: 0) {
            if visibleEditorTabs.count > 1 {
                mainPanelTabBar
            }

            activeMainPanelContent
        }
        .background(EditorTheme.canvasBackground)
    }

    private var mainPanelTabBar: some View {
        HStack(spacing: 10) {
            Spacer(minLength: 0)

            HStack(spacing: 2) {
                ForEach(visibleEditorTabs) { tab in
                    let isActive = mainPanelState.activeTab == tab
                    Button {
                        mainPanelState.activate(tab)
                    } label: {
                        Text(tab.editorTabTitle)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .frame(minWidth: 82)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 7)
                                    .fill(isActive ? EditorTheme.panelRaised : Color.clear)
                            )
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isActive ? EditorTheme.accent : EditorTheme.secondaryText)
                    .accessibilityLabel(tab.title)
                }
            }
            .padding(2)
            .background(EditorTheme.panelBackground, in: RoundedRectangle(cornerRadius: 9))

            Spacer(minLength: 0)

            Button {
                exportTimeline()
            } label: {
                if isExportingTimeline {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 68, height: 28)
                } else {
                    Label("Export", systemImage: "square.and.arrow.up")
                        .font(.caption.weight(.bold))
                        .labelStyle(.titleAndIcon)
                        .frame(width: 78, height: 28)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.black)
            .background(EditorTheme.accent, in: RoundedRectangle(cornerRadius: 7))
            .disabled(timelineClips.isEmpty || isExportingTimeline)
            .quickTooltip("Export Timeline")
            .accessibilityLabel("Export Timeline")
        }
        .frame(height: 44)
        .padding(.horizontal, 10)
        .background(EditorTheme.windowBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorTheme.hairline)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private var activeMainPanelContent: some View {
        switch mainPanelState.activeTab {
        case .preview:
            previewMainPanel
        case .videoEditor:
            videoEditorPanel
        }
    }

    private var previewMainPanel: some View {
        VStack(spacing: 0) {
            editingToolbar
            previewPanel
        }
    }

    private var videoEditorPanel: some View {
        VSplitView {
            HSplitView {
                clipsPane
                    .frame(minWidth: 190, idealWidth: 230, maxWidth: 320)

                playerPane
                    .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(minHeight: 280, maxHeight: .infinity)

            timelinePane
                .frame(minHeight: 88, idealHeight: 116, maxHeight: 150)
        }
        .background(EditorTheme.canvasBackground)
    }

    private var clipsPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Project Media")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(EditorTheme.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    importEditorClips()
                } label: {
                    Label("Import", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 9)
                        .frame(height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(EditorTheme.accent)
                .background(EditorTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
                .quickTooltip("Import Clips")
                .accessibilityLabel("Import Clips")
            }
            .frame(height: topToolbarHeight)
            .padding(.horizontal, 10)
            .background(EditorTheme.toolbarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 1)
            }

            if editorClips.isEmpty {
                Text("Import media to start building a timeline.")
                    .font(.callout)
                    .foregroundStyle(EditorTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 94, maximum: 132), spacing: 10)],
                        spacing: 12
                    ) {
                        ForEach(editorClips) { clip in
                            Button {
                                selectedTimelineClipID = nil
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
                    .padding(10)
                }
            }
        }
        .background(EditorTheme.panelBackground)
    }

    private var playerPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(playerPaneTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(EditorTheme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(playerPaneTitle)

                if let durationText = playerPaneDurationText {
                    Text(durationText)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(EditorTheme.secondaryText)
                        .lineLimit(1)
                }

                playerAudioControls
            }
            .frame(height: topToolbarHeight)
            .padding(.horizontal, 12)
            .background(EditorTheme.toolbarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 1)
            }

            ZStack {
                EditorTheme.windowBackground

                if isShowingTimelinePlayback {
                    TimelineSequenceVideoView(
                        clips: timelinePlaybackClips,
                        seekRequest: timelineSeekRequest,
                        onPlaybackPositionChange: handleTimelinePlaybackPosition
                    )
                } else if let clip = activeEditorClip {
                    PreviewPane(
                        item: clip.item,
                        zoomMultiplier: 1,
                        isCropToolActive: false,
                        appliedCrop: .full,
                        appliedTrim: activeTimelineTrimForPreview,
                        onApplyCrop: { },
                        onVideoTimeChange: { editorPlayerTime = $0 },
                        crop: .constant(.full)
                    )
                    .id(activeEditorPreviewID(for: clip))
                } else {
                    Text("No clips added.")
                        .font(.title3)
                        .foregroundStyle(EditorTheme.secondaryText)
                }
            }
        }
        .background(EditorTheme.windowBackground)
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
                .foregroundStyle(selectedTimelineClip?.adjustments.isMuted == true ? EditorTheme.accent : EditorTheme.primaryText)
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
                    .foregroundStyle(EditorTheme.secondaryText)
                    .frame(width: 34, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(EditorTheme.panelBackground, in: RoundedRectangle(cornerRadius: 7))
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
                .foregroundStyle(EditorTheme.primaryText)
                .disabled(timelineClips.isEmpty || isExportingTimeline)
                .quickTooltip("Export Timeline")
                .accessibilityLabel("Export Timeline")

                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(width: 1, height: 16)

                Button {
                    resetSelectedTimelineTrim()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(EditorTheme.primaryText)
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
                .foregroundStyle(EditorTheme.primaryText)
                .disabled(!canSplitSelectedTimelineClip)
                .quickTooltip("Split Clip")
                .accessibilityLabel("Split Clip")

                Button {
                    removeSelectedTimelineClip()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .foregroundStyle(EditorTheme.primaryText)
                .disabled(selectedTimelineClipID == nil)
                .quickTooltip("Delete Timeline Clip")
                .accessibilityLabel("Delete Timeline Clip")

                Spacer(minLength: 0)

                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(EditorTheme.secondaryText)

                Slider(value: $timelineZoom, in: 0.5...3.0)
                    .controlSize(.small)
                    .frame(width: 118)
                    .quickTooltip("Timeline Zoom")
                    .accessibilityLabel("Timeline Zoom")
            }
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(EditorTheme.toolbarBackground)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(height: 1)
            }

            timelineRuler
                .frame(height: 18)

            VStack(spacing: 0) {
                timelineTrackRow(title: "Video", systemImage: "film", clips: timelineClips, acceptsDrops: true)
            }
            .frame(height: 62)
        }
        .background(EditorTheme.timelineBackground)
        .onDrop(
            of: [UTType.plainText.identifier],
            isTargeted: $isTimelineDropTargeted,
            perform: handleTimelineDrop
        )
    }

    private var timelineRuler: some View {
        GeometryReader { geometry in
            let interval = timelineMarkerInterval
            let contentDuration = max(totalTimelineDuration, interval * 5)
            let markerCount = max(1, Int(ceil(contentDuration / interval)))
            let labelGutter: CGFloat = 64
            let contentWidth = max(geometry.size.width, labelGutter + CGFloat(contentDuration) * timelinePixelsPerSecond)

            ZStack(alignment: .topLeading) {
                ForEach(0...markerCount, id: \.self) { marker in
                    let seconds = TimeInterval(marker) * interval
                    VStack(alignment: .leading, spacing: 2) {
                        Rectangle()
                            .fill(EditorTheme.secondaryText.opacity(0.55))
                            .frame(width: 1, height: 5)

                        Text(MediaTrim.format(seconds))
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(EditorTheme.mutedText)
                    }
                    .offset(x: labelGutter + CGFloat(seconds) * timelinePixelsPerSecond)
                }
            }
            .frame(width: contentWidth, height: geometry.size.height, alignment: .topLeading)
        }
        .background(EditorTheme.timelineBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorTheme.hairline)
                .frame(height: 1)
        }
    }

    private func timelineTrackRow(
        title: String,
        systemImage: String,
        clips: [EditorTimelineClip],
        acceptsDrops: Bool
    ) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 16)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(EditorTheme.secondaryText)
            .frame(width: 54, alignment: .leading)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 5)
            .background(EditorTheme.trackAlternateBackground)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(EditorTheme.hairline)
                    .frame(width: 1)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(clips) { clip in
                        let sourceClip = editorClip(for: clip)
                        let duration = sourceClip?.status?.duration ?? 0
                        let trim = timelineTrim(for: clip, duration: duration)

                        TimelineClipBlock(
                            sourceClip: sourceClip,
                            thumbnail: sourceClip.flatMap(editorClipThumbnail(for:)),
                            isSelected: selectedTimelineClipID == clip.id,
                            playheadProgress: timelinePlayheadProgress(for: clip),
                            trim: trim,
                            totalDuration: duration,
                            pixelsPerSecond: timelinePixelsPerSecond,
                            onTrimChange: { nextTrim in
                                updateTimelineClipTrim(clip, trim: nextTrim)
                            }
                        )
                        .frame(width: timelineClipWidth(for: clip), height: 42)
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
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxHeight: .infinity, alignment: .leading)
            }
            .background {
                if acceptsDrops && isTimelineDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(EditorTheme.accent.opacity(0.10))
                        .padding(4)
                }
            }
            .overlay {
                if acceptsDrops && isTimelineDropTargeted {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(EditorTheme.accent.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                        .padding(4)
                }
            }
            .background(EditorTheme.trackBackground)
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
            } label: {
                Image(systemName: "crop")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 28, height: 26)
            }
            .buttonStyle(.plain)
            .disabled(selectedItem == nil)
            .foregroundStyle(isCropToolActive ? EditorTheme.accent : EditorTheme.primaryText)
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
                .fill(EditorTheme.hairline)
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
            .foregroundStyle(isTrimToolActive ? EditorTheme.accent : EditorTheme.primaryText)
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
                .fill(EditorTheme.hairline)
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
                    .foregroundStyle(EditorTheme.secondaryText)
                    .lineLimit(1)
                    .padding(.leading, 4)
                    .help("Current Edit Summary")
            }

            Spacer(minLength: 0)
        }
        .frame(height: topToolbarHeight)
        .padding(.horizontal, 10)
        .foregroundStyle(EditorTheme.primaryText)
        .background(EditorTheme.toolbarBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(EditorTheme.hairline)
                .frame(height: 1)
        }
    }

    private var previewPanel: some View {
        ZStack {
            EditorTheme.canvasBackground

            if let item = selectedItem {
                PreviewPane(
                    item: item,
                    zoomMultiplier: zoomLevels[zoomIndex],
                    isCropToolActive: isCropToolActive,
                    appliedCrop: selectedAppliedCrop,
                    appliedTrim: selectedPreviewTrim,
                    onApplyCrop: applySelectedCrop,
                    onVideoTimeChange: { previewVideoTime = $0 },
                    crop: cropBinding(for: item)
                )
                    .id(item.id)
            } else {
                Text(library.stateMessage)
                    .font(.title3)
                    .foregroundStyle(EditorTheme.secondaryText)
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
                .stroke(EditorTheme.accent, lineWidth: 3)
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

        if mainPanelState.activeTab == .videoEditor,
           selectedTimelineClipID != nil {
            switch event.keyCode {
            case 51, 117:
                removeSelectedTimelineClip()
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

    private func applySelectedCrop() {
        guard let item = selectedItem else { return }
        let crop = selectedCrop.clamped()
        guard !crop.isFullFrame else { return }
        appliedCrops[item.id] = crop
        cropRects[item.id] = crop
        isCropToolActive = false
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

    private func addToEditorClips(_ item: MediaItem) {
        selectedTimelineClipID = nil

        if editorClips.contains(where: { $0.id == item.id }) {
            selectedEditorClipID = item.id
        } else {
            editorClips.append(EditorClip(
                item: item,
                thumbnail: library.thumbnails[item.url],
                status: item.id == selectedItem?.id ? selectedStatus : nil
            ))
            selectedEditorClipID = item.id
        }

        mainPanelState.show(.videoEditor)
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
        selectedTimelineClipID = timelineClip.id
        selectedEditorClipID = nil

        let timelineStart = timelineStartTime(for: timelineClip)
        timelinePlaybackTime = timelineStart
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelineStart)

        if let duration = editorClip(for: timelineClip)?.status?.duration {
            editorPlayerTime = timelineTrim(for: timelineClip, duration: duration).start
        } else {
            editorPlayerTime = 0
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
    }

    private func addActiveThumbnailToEditorClips() -> Bool {
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

        if let thumbnailSelectionID,
           let item = visibleThumbnailEntries.first(where: { $0.id == thumbnailSelectionID })?.item {
            return item
        }

        return thumbnailSelectionID == nil ? selectedItem : nil
    }

    private func removeEditorClip(_ clip: EditorClip) {
        editorClips.removeAll { $0.id == clip.id }
        timelineClips.removeAll { $0.sourceClipID == clip.id }
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
            total + timelineDuration(for: clip)
        }
    }

    private var totalTimelineDuration: TimeInterval {
        max(actualTimelineDuration, 30)
    }

    private var timelineMarkerInterval: TimeInterval {
        switch timelineZoom {
        case 2.0...:
            return 5
        case 1.25..<2.0:
            return 10
        case 0.75..<1.25:
            return 30
        default:
            return 60
        }
    }

    private func timelineClipWidth(for clip: EditorTimelineClip) -> CGFloat {
        min(max(CGFloat(timelineDuration(for: clip)) * timelinePixelsPerSecond, 18), 900)
    }

    private func timelineStartTime(for targetClip: EditorTimelineClip) -> TimeInterval {
        var cursor = TimeInterval(0)
        for clip in timelineClips {
            if clip.id == targetClip.id {
                return cursor
            }
            cursor += timelineDuration(for: clip)
        }

        return 0
    }

    private func timelineRange(for targetClip: EditorTimelineClip) -> ClosedRange<TimeInterval> {
        let start = timelineStartTime(for: targetClip)
        return start...max(start, start + timelineDuration(for: targetClip))
    }

    private func timelinePlayheadProgress(for clip: EditorTimelineClip) -> Double? {
        let range = timelineRange(for: clip)
        if timelinePlaybackTime >= range.lowerBound,
           (timelinePlaybackTime < range.upperBound || timelineClips.last?.id == clip.id),
           range.upperBound > range.lowerBound {
            return min(max((timelinePlaybackTime - range.lowerBound) / (range.upperBound - range.lowerBound), 0), 1)
        }

        guard selectedTimelineClipID == clip.id,
              let duration = editorClip(for: clip)?.status?.duration,
              duration > 0
        else {
            return nil
        }

        let trim = timelineTrim(for: clip, duration: duration)
        guard trim.duration > 0 else { return nil }
        return min(max((editorPlayerTime - trim.start) / trim.duration, 0), 1)
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

        timelineClips[index].trim = MediaTrim(start: trim.start, end: splitTime).clamped(to: duration)
        let rightClip = EditorTimelineClip(
            sourceClipID: selectedTimelineClip.sourceClipID,
            trim: MediaTrim(start: splitTime, end: trim.end).clamped(to: duration)
        )
        timelineClips.insert(rightClip, at: timelineClips.index(after: index))
        selectTimelineClip(rightClip)
        editorPlayerTime = splitTime
        timelinePlaybackTime = timelineStartTime(for: rightClip)
        timelineSeekRequest = TimelinePlaybackSeekRequest(time: timelinePlaybackTime)
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

    private func removeTimelineClip(_ clip: EditorTimelineClip) {
        let removedIndex = timelineClips.firstIndex { $0.id == clip.id }
        timelineClips.removeAll { $0.id == clip.id }

        if selectedTimelineClipID == clip.id {
            if let removedIndex, !timelineClips.isEmpty {
                let nextIndex = min(removedIndex, timelineClips.index(before: timelineClips.endIndex))
                selectTimelineClip(timelineClips[nextIndex])
            } else {
                selectedTimelineClipID = nil
                timelinePlaybackTime = 0
                editorPlayerTime = 0
            }
        }
    }

    private func removeSelectedTimelineClip() {
        guard let selectedTimelineClip else {
            return
        }

        removeTimelineClip(selectedTimelineClip)
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

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Timeline Export.mp4"
        panel.directoryURL = library.folderURL
        panel.message = "Choose where to save the timeline export."

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        isExportingTimeline = true
        Task {
            do {
                try await MediaExport.exportTimeline(exportClips, to: destinationURL)
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

    private func selectedSnapshotTime() -> TimeInterval {
        guard let duration = selectedStatus.duration else {
            return max(0, previewVideoTime)
        }

        let trim = selectedPreviewTrim?.clamped(to: duration)
        let lowerBound = trim?.start ?? 0
        let upperBound = trim?.end ?? duration
        return min(max(previewVideoTime, lowerBound), upperBound)
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

    private func editorClipMenuTitle(for item: MediaItem) -> String {
        editorClips.contains(where: { $0.id == item.id }) ? "Show in Clips" : "Add to Clips"
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
                .stroke(EditorTheme.accent.opacity(0.55), lineWidth: 1)
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
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = NSColor(
                    red: 0.015,
                    green: 0.017,
                    blue: 0.018,
                    alpha: 1
                )
                window.titlebarAppearsTransparent = true
                if let titlebar = window.standardWindowButton(.closeButton)?.superview {
                    let titleLabelTag = 901_202
                    let label: NSTextField
                    if let existing = titlebar.viewWithTag(titleLabelTag) as? NSTextField {
                        label = existing
                    } else {
                        label = NSTextField(labelWithString: "MediaBrowser")
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

private enum SidePanel {
    case thumbnail
    case pinned
}

private extension MainPanelTab {
    var editorTabTitle: String {
        switch self {
        case .preview:
            return "Media"
        case .videoEditor:
            return "Video Editor"
        }
    }
}

private struct EditorClip: Identifiable {
    var id: URL { item.id }
    let item: MediaItem
    var thumbnail: NSImage?
    var status: MediaStatus?
}

private struct EditorTimelineClip: Identifiable, Hashable {
    let id = UUID()
    let sourceClipID: EditorClip.ID
    var trim: MediaTrim? = nil
    var adjustments = EditorTimelineAdjustments()
}

private struct EditorTimelineAdjustments: Hashable {
    var viewMode: EditorViewMode = .wide
    var fieldOfView = 90.0
    var yaw = 0.0
    var pitch = 0.0
    var roll = 0.0
    var keyframesEnabled = false
    var deepTrackEnabled = false
    var transitionStyle: EditorKeyframeTransition = .linear
    var stabilizationEnabled = false
    var horizonLockEnabled = false
    var horizonLevel = 0.0
    var zoom = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var isMuted = false
    var volume = 1.0
    var noiseReductionEnabled = false
    var exposure = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var sharpness = 0.0
}

private enum EditorViewMode: String, CaseIterable, Identifiable {
    case wide
    case linear
    case tinyPlanet
    case crystalBall

    var id: Self { self }

    var title: String {
        switch self {
        case .wide:
            return "Wide"
        case .linear:
            return "Linear"
        case .tinyPlanet:
            return "Tiny"
        case .crystalBall:
            return "Crystal"
        }
    }
}

private enum EditorKeyframeTransition: String, CaseIterable, Identifiable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    var id: Self { self }

    var title: String {
        switch self {
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease"
        }
    }
}

private struct PinnedCopyResult: Sendable {
    let copiedCount: Int
    let failures: [String]
}

private struct TrimControls: View {
    @Binding var trim: MediaTrim
    let duration: TimeInterval
    let onApply: () -> Void

    @State private var startText = ""
    @State private var endText = ""
    @FocusState private var focusedField: TimeField?

    var body: some View {
        HStack(spacing: 6) {
            TrimRangeSlider(trim: $trim, duration: duration)
                .frame(width: 150, height: 24)
                .quickTooltip("Drag to Set Trim Start and End")
                .accessibilityLabel("Trim Range")

            TextField("Start", text: $startText)
                .font(.caption.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .focused($focusedField, equals: .start)
                .onSubmit(commitTextFields)
                .onChange(of: startText) {
                    commitTextField(.start)
                }
                .quickTooltip("Trim Start Time (MM:SS:CC)")
                .accessibilityLabel("Trim Start Time")

            TextField("End", text: $endText)
                .font(.caption.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .focused($focusedField, equals: .end)
                .onSubmit(commitTextFields)
                .onChange(of: endText) {
                    commitTextField(.end)
                }
                .quickTooltip("Trim End Time (MM:SS:CC)")
                .accessibilityLabel("Trim End Time")

            Button {
                commitTextFields()
                onApply()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(trim.isFullLength(for: duration))
            .quickTooltip("Apply Trim")
            .accessibilityLabel("Apply Trim")
        }
        .onAppear(perform: syncTextFields)
        .onChange(of: trim) {
            syncTextFields()
        }
        .onChange(of: duration) {
            trim = trim.clamped(to: duration)
            syncTextFields()
        }
    }

    private func syncTextFields() {
        let clamped = trim.clamped(to: duration)
        if focusedField != .start {
            startText = MediaTrim.format(clamped.start)
        }
        if focusedField != .end {
            endText = MediaTrim.format(clamped.end)
        }
    }

    private func commitTextFields() {
        let current = trim.clamped(to: duration)
        let nextStart = parseTime(startText) ?? current.start
        let nextEnd = parseTime(endText) ?? current.end
        trim = MediaTrim(start: nextStart, end: nextEnd).clamped(to: duration)
        focusedField = nil
        syncTextFields()
    }

    private func commitTextField(_ field: TimeField) {
        guard focusedField == field else { return }

        let current = trim.clamped(to: duration)
        switch field {
        case .start:
            guard let nextStart = parseTime(startText) else { return }
            trim = MediaTrim(start: nextStart, end: current.end).clamped(to: duration)
        case .end:
            guard let nextEnd = parseTime(endText) else { return }
            trim = MediaTrim(start: current.start, end: nextEnd).clamped(to: duration)
        }
    }

    private func parseTime(_ text: String) -> TimeInterval? {
        let parts = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty })
        else { return nil }
        if parts.count == 1 {
            return TimeInterval(parts[0])
        }
        if parts.count == 2,
           let minutes = TimeInterval(parts[0]),
           let seconds = TimeInterval(parts[1]) {
            return minutes * 60 + seconds
        }
        if parts.count == 3,
           let minutes = TimeInterval(parts[0]),
           let seconds = TimeInterval(parts[1]),
           let centiseconds = TimeInterval(parts[2]) {
            return minutes * 60 + seconds + centiseconds / 100
        }
        if parts.count == 4,
           let hours = TimeInterval(parts[0]),
           let minutes = TimeInterval(parts[1]),
           let seconds = TimeInterval(parts[2]),
           let centiseconds = TimeInterval(parts[3]) {
            return hours * 3600 + minutes * 60 + seconds + centiseconds / 100
        }
        return nil
    }

    private enum TimeField: Hashable {
        case start
        case end
    }
}

private struct TrimRangeSlider: View {
    @Binding var trim: MediaTrim
    let duration: TimeInterval

    @State private var activeHandle: TrimHandle?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let handleSize: CGFloat = 12
            let trackWidth = max(size.width - handleSize, 1)
            let clamped = trim.clamped(to: duration)
            let startX = xPosition(for: clamped.start, width: trackWidth, handleSize: handleSize)
            let endX = xPosition(for: clamped.end, width: trackWidth, handleSize: handleSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(height: 4)
                    .position(x: size.width / 2, y: size.height / 2)

                Capsule()
                    .fill(EditorTheme.accent.opacity(0.82))
                    .frame(width: max(endX - startX, 2), height: 4)
                    .position(x: (startX + endX) / 2, y: size.height / 2)

                Circle()
                    .fill(activeHandle == .start ? EditorTheme.accent : EditorTheme.panelRaised)
                    .stroke(EditorTheme.accent, lineWidth: 1.5)
                    .frame(width: handleSize, height: handleSize)
                    .position(x: startX, y: size.height / 2)

                Circle()
                    .fill(activeHandle == .end ? EditorTheme.accent : EditorTheme.panelRaised)
                    .stroke(EditorTheme.accent, lineWidth: 1.5)
                    .frame(width: handleSize, height: handleSize)
                    .position(x: endX, y: size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let seconds = seconds(for: value.location.x, width: trackWidth, handleSize: handleSize)
                        if activeHandle == nil {
                            activeHandle = abs(seconds - clamped.start) <= abs(seconds - clamped.end) ? .start : .end
                        }

                        switch activeHandle {
                        case .start:
                            trim = MediaTrim(start: seconds, end: clamped.end).clamped(to: duration)
                        case .end:
                            trim = MediaTrim(start: clamped.start, end: seconds).clamped(to: duration)
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
        }
    }

    private func xPosition(for seconds: TimeInterval, width: CGFloat, handleSize: CGFloat) -> CGFloat {
        let percent = duration > 0 ? min(max(seconds / duration, 0), 1) : 0
        return handleSize / 2 + CGFloat(percent) * width
    }

    private func seconds(for xPosition: CGFloat, width: CGFloat, handleSize: CGFloat) -> TimeInterval {
        let percent = min(max((xPosition - handleSize / 2) / width, 0), 1)
        return TimeInterval(percent) * duration
    }

    private enum TrimHandle {
        case start
        case end
    }
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

private struct EditorClipCard: View {
    let clip: EditorClip
    let thumbnail: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 7) {
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
                .frame(height: 76)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(EditorTheme.thumbnailWell)
                }

                Text(durationBadge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(4)
            }

            Text(clip.item.fileName)
                .font(.caption2)
                .foregroundStyle(EditorTheme.secondaryText)
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? EditorTheme.panelRaised : Color.clear)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? EditorTheme.accent : EditorTheme.hairline, lineWidth: isSelected ? 2 : 1)
        }
    }

    private var durationBadge: String {
        if let duration = clip.status?.duration {
            return MediaTrim.format(duration)
        }
        return clip.item.kind.label
    }
}

private struct TimelineClipReorderDropDelegate: DropDelegate {
    let targetClipID: EditorTimelineClip.ID
    @Binding var draggingClipID: EditorTimelineClip.ID?
    let moveClip: (EditorTimelineClip.ID, EditorTimelineClip.ID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingClipID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggingClipID,
              draggingClipID != targetClipID
        else {
            return
        }

        moveClip(draggingClipID, targetClipID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingClipID = nil
        return true
    }
}

private struct TimelineClipBlock: View {
    let sourceClip: EditorClip?
    let thumbnail: NSImage?
    let isSelected: Bool
    let playheadProgress: Double?
    let trim: MediaTrim
    let totalDuration: TimeInterval
    let pixelsPerSecond: CGFloat
    let onTrimChange: (MediaTrim) -> Void

    @State private var activeTrimHandle: TimelineTrimHandle?
    @State private var trimDragStart: MediaTrim?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let showsThumbnail = width >= 26
            let showsDetails = width >= 74
            let horizontalPadding: CGFloat = width < 42 ? 3 : 7
            let thumbnailWidth = min(44, max(18, width * 0.45))

            HStack(spacing: showsDetails ? 7 : 0) {
                if showsThumbnail {
                    Group {
                        if let thumbnail {
                            Image(nsImage: thumbnail)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            EditorTheme.thumbnailWell
                        }
                    }
                    .frame(width: thumbnailWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }

                if showsDetails {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(sourceClip?.item.fileName ?? "Missing Clip")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Text(detailText)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.78))
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, 6)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? EditorTheme.clipBlueSelected : EditorTheme.clipBlue)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? EditorTheme.accent : Color.white.opacity(0.16), lineWidth: isSelected ? 2 : 1)
            }
            .overlay(alignment: .leading) {
                if let playheadProgress {
                    Rectangle()
                        .fill(Color.white.opacity(0.88))
                        .frame(width: 2)
                        .offset(x: max(0, min(geometry.size.width - 2, geometry.size.width * playheadProgress)))
                        .shadow(color: .black.opacity(0.25), radius: 2)
                }
            }
            .overlay(alignment: .leading) {
                if canTrim {
                    trimHandle(.leading)
                }
            }
            .overlay(alignment: .trailing) {
                if canTrim {
                    trimHandle(.trailing)
                }
            }
        }
        .frame(height: 46)
    }

    private var detailText: String {
        guard sourceClip != nil else {
            return "Offline"
        }

        guard totalDuration > 0 else {
            return sourceClip?.item.kind.label ?? "Media"
        }

        if trim.isFullLength(for: totalDuration) {
            return MediaTrim.format(totalDuration)
        }

        return "\(MediaTrim.format(trim.start))-\(MediaTrim.format(trim.end))"
    }

    private var canTrim: Bool {
        isSelected && totalDuration > MediaTrim.minimumDuration
    }

    private func trimHandle(_ handle: TimelineTrimHandle) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(activeTrimHandle == handle ? Color.white : Color.white.opacity(0.78))
            .frame(width: 8, height: 36)
            .padding(.horizontal, 2)
            .shadow(color: .black.opacity(0.22), radius: 2)
            .gesture(trimGesture(handle))
            .quickTooltip(handle == .leading ? "Trim Start" : "Trim End")
            .accessibilityLabel(handle == .leading ? "Trim Start" : "Trim End")
    }

    private func trimGesture(_ handle: TimelineTrimHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startTrim = trimDragStart ?? trim
                trimDragStart = startTrim
                activeTrimHandle = handle

                let delta = TimeInterval(value.translation.width / max(pixelsPerSecond, 1))
                switch handle {
                case .leading:
                    onTrimChange(MediaTrim(start: startTrim.start + delta, end: startTrim.end))
                case .trailing:
                    onTrimChange(MediaTrim(start: startTrim.start, end: startTrim.end + delta))
                }
            }
            .onEnded { _ in
                activeTrimHandle = nil
                trimDragStart = nil
            }
    }

    private enum TimelineTrimHandle {
        case leading
        case trailing
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
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .background {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(EditorTheme.thumbnailWell)
                }

                Text(item.kind.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(3)
            }
            .overlay(alignment: .topLeading) {
                if isEdited {
                    Image(systemName: "crop")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(EditorTheme.accent, in: Circle())
                        .padding(3)
                }
            }

            Text(item.fileName)
                .font(.caption)
                .foregroundStyle(EditorTheme.secondaryText)
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
                .foregroundStyle(EditorTheme.mutedText)
                .frame(width: 12)

            Image(systemName: entry.isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(EditorTheme.secondaryText)
                .frame(width: 24)

            Text(entry.folder.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(EditorTheme.primaryText)
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
    let appliedTrim: MediaTrim?
    let onApplyCrop: () -> Void
    let onVideoTimeChange: (TimeInterval) -> Void
    @Binding var crop: NormalizedCrop

    @State private var naturalSize: CGSize?
    @State private var failedToLoad = false

    var body: some View {
        GeometryReader { geometry in
            if failedToLoad {
                Text("This file could not be loaded.")
                    .font(.title3)
                    .foregroundStyle(EditorTheme.secondaryText)
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
                        displaySize: naturalSize,
                        trim: appliedTrim,
                        onTimeChange: onVideoTimeChange
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
            NativeGIFImageView(url: item.url, trim: appliedTrim)
        case .webp:
            NativeWebImageView(url: item.url)
        case .video:
            NativeVideoView(
                url: item.url,
                crop: .full,
                displaySize: nil,
                trim: appliedTrim,
                onTimeChange: onVideoTimeChange
            )
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
                    .strokeBorder(EditorTheme.accent, style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .allowsHitTesting(false)

                if isEditable {
                    ForEach(CropHandle.allCases) { handle in
                        Circle()
                            .fill(EditorTheme.accent)
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
                        .background(EditorTheme.accent, in: Capsule())
                        .position(
                            x: min(max(cropRect.maxX - 38, 42), geometry.size.width - 42),
                            y: min(max(cropRect.minY + 22, 22), geometry.size.height - 22)
                        )
                        .quickTooltip("Apply Crop")
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
