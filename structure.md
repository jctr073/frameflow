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
   │  │  ├─ editingToolbar
   │  │  │  ├─ Crop Tool
   │  │  │  ├─ Crop Presets
   │  │  │  ├─ Reset Crop
   │  │  │  ├─ Trim Tool
   │  │  │  ├─ Reset Trim
   │  │  │  ├─ TrimControls
   │  │  │  │  ├─ TrimRangeSlider
   │  │  │  │  ├─ Start time TextField
   │  │  │  │  ├─ End time TextField
   │  │  │  │  └─ Apply Trim button
   │  │  │  ├─ Undo Edits
   │  │  │  ├─ Apply Crop / Apply Trim
   │  │  │  ├─ Move Edited Media to Pinned
   │  │  │  └─ editSummaryLabel
   │  │  │
   │  │  └─ previewPanel
   │  │     └─ PreviewPane
   │  │        ├─ StaticImagePreview / NativeGIFImageView / NativeWebImageView
   │  │        ├─ NativeVideoView
   │  │        │  ├─ NativeVideoSurface
   │  │        │  └─ NativeVideoControls
   │  │        └─ CropOverlay
   │  │           ├─ CropDimShape
   │  │           ├─ crop drag/resize handles
   │  │           └─ Apply Crop button
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

## Panel State

The active side panel is tracked with `SidePanel` in `ContentView.swift`.

```swift
private enum SidePanel {
    case thumbnail
    case pinned
}
```

## Code Anchors

- Main app shell: `Sources/MediaBrowser/ContentView.swift`
- `thumbnailPanel`: `Sources/MediaBrowser/ContentView.swift`
- `pinnedPanel`: `Sources/MediaBrowser/ContentView.swift`
- `statusBar`: `Sources/MediaBrowser/ContentView.swift`
- `mainPanel`, `editingToolbar`, `previewPanel`: `Sources/MediaBrowser/ContentView.swift`
- `TrimControls`: `Sources/MediaBrowser/ContentView.swift`
- `PreviewPane`: `Sources/MediaBrowser/ContentView.swift`
- `NativeVideoView`, `NativeVideoSurface`, `NativeVideoControls`: `Sources/MediaBrowser/NativeMediaViews.swift`
- `quickTooltipOverlay`: `Sources/MediaBrowser/QuickTooltip.swift`
