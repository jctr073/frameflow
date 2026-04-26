# Media Browser Structure

This document maps the main UI panels and controls to their names in the SwiftUI codebase.

```text
ContentView
└─ VStack
   ├─ HSplitView
   │  ├─ thumbnailPanel
   │  │  ├─ folderHeader
   │  │  │  ├─ Open Folder button
   │  │  │  └─ Current folder title
   │  │  ├─ filterControl
   │  │  │  ├─ Filter icon«
   │  │  │  ├─ Filter files TextField
   │  │  │  └─ Clear Filter button
   │  │  └─ List
   │  │     ├─ FolderRow
   │  │     └─ ThumbnailRow
   │  │
   │  ├─ mainPanel
   │  │  ├─ mainPanelTabBar
   │  │  │  ├─ Preview tab
   │  │  │  └─ Video Editor tab
   │  │  ├─ previewMainPanel
   │  │  │  ├─ editingToolbar
   │  │  │  │  ├─ Snapshot Current Frame
   │  │  │  │  ├─ Crop Tool
   │  │  │  │  ├─ Crop Presets
   │  │  │  │  ├─ Reset Crop
   │  │  │  │  ├─ Trim Tool
   │  │  │  │  ├─ Reset Trim
   │  │  │  │  ├─ TrimControls
   │  │  │  │  │  ├─ TrimRangeSlider
   │  │  │  │  │  ├─ Start time TextField
   │  │  │  │  │  ├─ End time TextField
   │  │  │  │  │  └─ Apply Trim button
   │  │  │  │  ├─ Undo Edits
   │  │  │  │  ├─ Apply Crop / Apply Trim
   │  │  │  │  ├─ Move Edited Media to Pinned
   │  │  │  │  └─ editSummaryLabel
   │  │  │  └─ previewPanel
   │  │  │     └─ PreviewPane
   │  │  │        ├─ StaticImagePreview / NativeGIFImageView / NativeWebImageView
   │  │  │        ├─ NativeVideoView
   │  │  │        │  ├─ NativeVideoSurface
   │  │  │        │  └─ NativeVideoControls
   │  │  │        └─ CropOverlay
   │  │  │           ├─ CropDimShape
   │  │  │           ├─ crop drag/resize handles
   │  │  │           └─ Apply Crop button
   │  │  └─ videoEditorPanel
   │  │     ├─ clipsPane
   │  │     │  ├─ Clips header
   │  │     │  ├─ Import Clips button
   │  │     │  ├─ Media / Music / Text / Transitions / Movement tabs
   │  │     │  └─ EditorClipCard grid
   │  │     ├─ playerPane
   │  │     │  ├─ selected clip header
   │  │     │  └─ PreviewPane
   │  │     └─ timelinePane
   │  │        ├─ disabled phase-1 timeline toolbar
   │  │        ├─ timelineRuler
   │  │        ├─ Video track
   │  │        │  └─ TimelineClipBlock
   │  │        └─ Audio track
   │  │
   │  └─ pinnedPanel
   │     ├─ Pinned header toolbar
   │     │  ├─ "Pinned" title
   │     │  ├─ Copy Pinned Files
   │     │  ├─ Clear Pinned Files
   │     │  └─ pinned count
   │     └─ List
   │        └─ ThumbnailRow
   │
   └─ statusBar
      ├─ Open Folder button
      ├─ Open Terminal Here button
      ├─ statusPathText
      ├─ selectedStatus.detailText
      └─ statusCountText
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
├─ Preview Panel checkbox
└─ Video Editor Panel checkbox
```

## Panel State

The active side panel is tracked with `SidePanel` in `ContentView.swift`.

```swift
private enum SidePanel {
    case thumbnail
    case pinned
}
```

The active main panel tab and visible main panel tabs are tracked with `MainPanelTab` and
`MainPanelState` in `MainPanelState.swift`.

```swift
enum MainPanelTab {
    case preview
    case videoEditor
}
```

The video editor clip list is owned by `ContentView` as `editorClips`. Clips are added from
`thumbnailPanel` through the thumbnail context menu's `Add to Clips` action or the
`Control+C` keyboard shortcut.

## Code Anchors

- Main app shell: `Sources/MediaBrowser/ContentView.swift`
- Main panel tab state: `Sources/MediaBrowser/MainPanelState.swift`
- `thumbnailPanel`: `Sources/MediaBrowser/ContentView.swift`
- `pinnedPanel`: `Sources/MediaBrowser/ContentView.swift`
- `statusBar`: `Sources/MediaBrowser/ContentView.swift`
- `mainPanel`, `mainPanelTabBar`, `editingToolbar`, `previewPanel`: `Sources/MediaBrowser/ContentView.swift`
- `videoEditorPanel`, `clipsPane`, `playerPane`, `timelinePane`: `Sources/MediaBrowser/ContentView.swift`
- `TrimControls`: `Sources/MediaBrowser/ContentView.swift`
- `PreviewPane`: `Sources/MediaBrowser/ContentView.swift`
- `NativeVideoView`, `NativeVideoSurface`, `NativeVideoControls`: `Sources/MediaBrowser/NativeMediaViews.swift`
- `quickTooltipOverlay`: `Sources/MediaBrowser/QuickTooltip.swift`
