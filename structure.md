# Frameflow Structure

This document maps the main UI panels and controls to their names in the SwiftUI codebase.

## Source Organization

```text
Sources/Frameflow/App
├─ FrameflowApp.swift          app entry point and command menu
├─ ContentView.swift           root layout, state coordination, app commands
├─ MainPanelState.swift        main tab visibility and activation state
├─ SidePanel.swift             thumbnail/pinned focus state
├─ EditorDragPayload.swift     drag-and-drop payload encoding
└─ EditorTheme.swift           theme IDs, palettes, environment value

Sources/Frameflow/Domain
├─ MediaItem.swift             supported media kind and identity
├─ MediaMetadata.swift         display metadata model and loader
├─ MediaSizing.swift           natural-size lookup
├─ ExportModels.swift          pinned media and timeline export clip values
├─ EditorTimelineModels.swift  composer clip and timeline clip state
└─ FileFilter.swift            Finder-style wildcard file filtering

Sources/Frameflow/Services
├─ MediaLibrary.swift          folder scanning, expansion, thumbnail queue
├─ MediaFilmstrip.swift        timeline filmstrip thumbnail generation
├─ MediaSnapshot.swift         video-frame snapshot export
├─ MediaExport.swift           export API and destination naming
├─ MediaExport+PinnedMedia.swift
├─ MediaExport+Timeline.swift
├─ MediaExport+AnimatedWebPTimeline.swift
├─ MediaExport+Geometry.swift
├─ AnimatedWebPMuxer.swift
├─ MediaExportError.swift
└─ PinnedCopyResult.swift

Sources/Frameflow/Support
├─ KeyboardMonitor.swift
├─ SplitViewResizeCursorInstaller.swift
└─ UniqueCopyURL.swift

Sources/Frameflow/Views
├─ Composer/                   clip-bin views
├─ Editing/                    trim controls
├─ MediaLibrary/               folder and thumbnail rows
├─ Preview/                    preview panes, crop overlay, native media views
├─ Shared/                     reusable SwiftUI modifiers
└─ Timeline/                   timeline blocks, drop delegates, shapes

Sources/FrameflowCore
└─ TimelineAdjustment.swift    crop, trim, adjustment spans, export crop renderer
```

Naming follows the app hierarchy: `Media*` types describe imported files and metadata,
`Editor*` types belong to the Composer media bin, `Timeline*` types belong to timeline
playback/export/editing, and view files use role words such as `Pane`, `Panel`, `Row`,
`Block`, `Overlay`, and `Controls`.

```text
ContentView
└─ VStack
   ├─ mainPanelTabBar
   │  ├─ Quick Sort tab
   │  ├─ Composer tab
   │  └─ Export Timeline button
   │
   ├─ activeWorkbench
   │  ├─ quickSortWorkbench (Quick Sort tab)
   │  │  └─ HSplitView
   │  │     ├─ thumbnailPanel
   │  │     ├─ previewMainPanel
   │  │     └─ pinnedPanel
   │  │
   │  └─ composerWorkbench (Composer tab)
   │     └─ VSplitView
   │        ├─ HSplitView
   │        │  ├─ thumbnailPanel
   │        │  ├─ clipsPane
   │        │  ├─ playerPane
   │        │  └─ pinnedPanel
   │        └─ timelinePane
   │
   └─ statusBar
      ├─ Open Folder button
      ├─ Open Terminal Here button
      ├─ theme accent status dot
      ├─ statusPathText
      ├─ statusCountText
      └─ selectedStatus.detailText
```

## Panel Contents

```text
thumbnailPanel
├─ panelHeader (Open Folder button, filterControl)
├─ thumbnailBatchControl
└─ vertical List
   ├─ FolderRow
   └─ ThumbnailRow

previewMainPanel
├─ mediaPreviewHeader
├─ editingToolbar
└─ previewPanel
   └─ PreviewPane
      ├─ StaticImagePreview / NativeGIFImageView / NativeWebImageView
      ├─ NativeVideoView
      │  ├─ NativeVideoSurface
      │  └─ NativeVideoControls
      └─ CropOverlay

clipsPane
├─ panelColumnHeader ("Clips", plus import button)
└─ vertical EditorClipCard stack

playerPane
├─ selected media-bin clip or active timeline clip header
├─ selected timeline clip audio mute / volume controls
├─ playerEditingToolbar with crop, crop preset, reset, zoom +/- and fill controls
├─ PreviewPane for media-bin preview
└─ TimelineSequenceVideoView for full timeline playback

timelinePane
├─ timeline toolbar
│  ├─ Export Timeline
│  ├─ Add Adjustment Crop
│  ├─ Reset Timeline Trim
│  ├─ Split Clip
│  ├─ Delete Timeline Clip
│  └─ Timeline Zoom slider
├─ timelineRuler
├─ adjustmentLayer
│  └─ TimelineAdjustmentSpanBlock list
│     ├─ drag-to-move behavior
│     ├─ resize start handle
│     ├─ resize end handle
│     └─ crop keyframe markers with delete context menu
├─ Video track drop target
│  └─ TimelineClipBlock list
│     ├─ drag-to-reorder behavior
│     ├─ trim start handle
│     └─ trim end handle
└─ timelinePlayheadOverlay
   ├─ vertical timeline position line
   └─ TimelinePlayheadHandleShape top drag handle

pinnedPanel
├─ panelColumnHeader ("Pinned", Copy Pinned Files, Clear Pinned Files, pinned count)
├─ empty state
└─ vertical List
   └─ ThumbnailRow
```

## Root Overlays And Helpers

```text
ContentView overlays/background helpers
├─ dropOverlay
├─ quickTooltipOverlay
└─ KeyboardMonitor
```

## App Commands

```text
View menu
├─ Quick Sort Panel checkbox
├─ Composer Panel checkbox
└─ Color Theme
   ├─ Amber studio
   ├─ Resolve teal
   └─ Final cut sapphire
```

## Panel State

The active side panel is tracked with `SidePanel` in `Sources/Frameflow/App/SidePanel.swift`.

```swift
enum SidePanel {
    case thumbnail
    case pinned
}
```

The active main panel tab and visible main panel tabs are tracked with `MainPanelTab` and
`MainPanelState` in `Sources/Frameflow/App/MainPanelState.swift`.

```swift
enum MainPanelTab {
    case preview
    case videoComposer
}
```

The video editor media-bin clip list is owned by `ContentView` as `editorClips`. Clips are
added from `thumbnailPanel` through the thumbnail context menu's `Add to Clips` action or
the `Control+C` keyboard shortcut.

Timeline clip instances are owned separately as `timelineClips`. Dragging an
`EditorClipCard` from `clipsPane` into `timelinePane`, or choosing `Add to Timeline` from
the clip context menu, creates a new `EditorTimelineClip` with its own UUID so the same
media-bin clip can appear on the timeline more than once. `selectedTimelineClipID` drives
timeline block highlighting and the compact audio controls in `playerPane`. Timeline
clips can also be reordered by dragging `TimelineClipBlock` instances within the video
track. Timeline playback also updates
`selectedTimelineClipID` as the playhead crosses clip boundaries, so the active
`TimelineClipBlock` is highlighted while the full sequence plays.

The red/orange timeline position indicator is `timelinePlayheadOverlay(in:)` in
`ContentView.swift`. It draws the vertical playhead line using `timelinePlayheadColor`,
uses `TimelinePlayheadHandleShape` for the top draggable handle, and updates
`timelinePlaybackTime` through `timelinePlayheadDragGesture`. As playback or dragging moves
the playhead, `syncTimelineAdjustmentSelection(to:)` activates the
`TimelineAdjustmentSpanBlock` under the playhead, matching the active-clip behavior on the
video track, and keeps the adjustment crop overlay visible while the playhead is inside an
adjustment crop span.

Each `EditorTimelineClip` may also carry its own `MediaTrim`. Timeline trim handles update
that per-instance trim, the player previews the selected timeline trim, and Split Clip
creates two timeline instances split at the current player time. `timelineZoom` controls
timeline clip width and ruler scale without changing media timing.

Timeline crop now lives in adjustment spans on the `adjustmentLayer`, not on
`EditorTimelineClip`. Selecting an adjustment span enables the crop overlay in
`playerPane`; applying the crop at the playhead creates or updates a crop keyframe, and
the overlay interpolates between those keyframes while timeline preview remains full-frame.
Export applies the active adjustment crop transforms to the output video.

The editor player has two playback paths. When a media-bin clip is selected,
`playerPane` still uses `PreviewPane` for single-clip preview. When a timeline clip is
selected, `playerPane` uses `TimelineSequenceVideoView` to build an in-memory full-frame
AV preview composition from the video timeline.
`timelinePlaybackTime` stores the sequence playhead time, `timelineSeekRequest` seeks the
sequence when a timeline block is selected, and `TimelinePlaybackPosition` maps sequence
time back to the active
timeline clip and source media time for highlighting, split, and trim behavior.

Timeline export is handled by `MediaExport.exportTimeline`. `ContentView` converts
`timelineClips` into `TimelineExportClip` values, including clip trims and audio volume /
mute state, and passes adjustment spans separately so playback and export share the same
timeline crop keyframes. Export supports all-video MP4 timelines and all-WebP
animated WebP timelines.

Per-timeline-clip `EditorTimelineAdjustments` still stores render settings. The visible
editor control surface currently exposes audio mute/volume in `playerPane`, and export
honors those audio settings.

## Code Anchors

- Main app shell and panel composition: `Sources/Frameflow/App/ContentView.swift`
- Theme model and palettes: `Sources/Frameflow/App/EditorTheme.swift`
- Main panel tab state: `Sources/Frameflow/App/MainPanelState.swift`
- `thumbnailPanel`, `pinnedPanel`, `statusBar`: `Sources/Frameflow/App/ContentView.swift`
- `mainPanelTabBar`, `activeWorkbench`, `quickSortWorkbench`, `composerWorkbench`: `Sources/Frameflow/App/ContentView.swift`
- `clipsPane`, `playerPane`, `timelinePane`, `editingToolbar`, `previewPanel`: `Sources/Frameflow/App/ContentView.swift`
- Clip-bin card view: `Sources/Frameflow/Views/Composer/EditorClipCard.swift`
- Folder and thumbnail rows: `Sources/Frameflow/Views/MediaLibrary/ThumbnailRows.swift`
- `TrimControls`: `Sources/Frameflow/Views/Editing/TrimControls.swift`
- `PreviewPane`: `Sources/Frameflow/Views/Preview/PreviewPane.swift`
- `CropOverlay`: `Sources/Frameflow/Views/Preview/CropOverlay.swift`
- native image bridges: `Sources/Frameflow/Views/Preview/NativeImageViews.swift`
- `NativeVideoView`, `NativeVideoControls`: `Sources/Frameflow/Views/Preview/NativeVideoView.swift`
- `NativeVideoSurface`, `ZoomableNativeVideoSurface`: `Sources/Frameflow/Views/Preview/NativeVideoSurfaces.swift`
- `TimelineSequenceVideoView`: `Sources/Frameflow/Views/Preview/TimelineSequenceVideoView.swift`
- Timeline clip blocks and adjustment spans: `Sources/Frameflow/Views/Timeline/`
- timeline export API: `Sources/Frameflow/Services/MediaExport.swift`
- pinned export encoders: `Sources/Frameflow/Services/MediaExport+PinnedMedia.swift`
- timeline export composition: `Sources/Frameflow/Services/MediaExport+Timeline.swift`
- animated WebP muxing: `Sources/Frameflow/Services/AnimatedWebPMuxer.swift`
- timeline adjustment crop model: `Sources/FrameflowCore/TimelineAdjustment.swift`
- `KeyboardMonitor`: `Sources/Frameflow/Support/KeyboardMonitor.swift`
- `quickTooltipOverlay`: `Sources/Frameflow/Views/Shared/QuickTooltip.swift`
