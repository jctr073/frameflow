# Frameflow

Frameflow is a native macOS media sorting and lightweight video composition tool built with SwiftUI, AppKit, and AVFoundation. It is designed for quickly reviewing folders of images, GIFs, WebP files, and videos, pinning selects, making simple crops or trims, and assembling video clips on a timeline for export.

## Features

- Browse a folder of supported media with generated thumbnails and expandable subfolders.
- Preview images, animated GIFs, WebP files, and videos in a dark native macOS interface.
- Filter, multi-select, pin, unpin, and copy selected media into another folder.
- Apply crop and trim edits before exporting pinned media.
- Capture video frame snapshots into `~/Pictures/FrameflowSnapshots`.
- Build video timelines from imported clips with drag-and-drop ordering.
- Trim, split, reorder, mute, and adjust volume on timeline clips.
- Add timeline crop adjustment spans with keyframes and interpolated crop motion.
- Export the timeline as an MP4 file.
- Switch between built-in color themes from the macOS View menu.

## Requirements

- macOS 14 or newer.
- Swift 6.0-compatible toolchain.
- Xcode command line tools for local builds.

Frameflow currently targets macOS only.

## Supported Media

Frameflow recognizes common raster images and video formats through file extensions and Apple media type detection:

- Images: `jpg`, `jpeg`, `png`, `tif`, `tiff`, `bmp`, `heic`, `heif`
- Animated/static web media: `gif`, `webp`
- Video: `mp4`, `mov`, `m4v`

## Getting Started

Clone the repository and build the app with Swift Package Manager:

```sh
git clone <repository-url>
cd frameflow
swift build
```

Run the app from the package:

```sh
swift run Frameflow
```

You can also pass an initial media folder:

```sh
swift run Frameflow /path/to/media-folder
```

## Building a macOS App Bundle

The repository includes a script that creates a signed local `.app` bundle in `.build/app`:

```sh
./scripts/build-app.sh
```

The script prints the app bundle path when it finishes, usually:

```text
.build/app/Frameflow.app
```

To build and install Frameflow into `/Applications`:

```sh
./scripts/install-system.sh
```

The install script uses `sudo` only when `/Applications` is not writable by the current user.

## Basic Workflow

1. Open a folder with the folder button or `Command-O`.
2. Browse media in the thumbnail panel.
3. Pin keepers from the context menu or by using the pin controls.
4. Crop, trim, or snapshot the selected media when needed.
5. Copy pinned files to a destination folder.
6. Switch to Composer to add clips to a video timeline.
7. Drag clips onto the timeline, trim/split/reorder them, add crop adjustment spans, then export the timeline.

## Useful Controls

- `Command-O`: open a folder.
- `Space`: toggle playback when focus is not in a text field.
- `Return`: apply an active crop, trim, or adjustment crop keyframe.
- `Escape`: clear an active crop or trim.
- Arrow keys: nudge an active adjustment crop in Composer.
- View menu: show or hide the Quick Sort and Composer panels, or switch color themes.

## Development

Run the logic test executable:

```sh
swift run FrameflowLogicTests
```

Build the release app:

```sh
swift build -c release --product Frameflow
```

The current test target is a small executable test runner for core timeline adjustment logic. It is intentionally simple and prints a success message when the assertions pass.

## Project Layout

```text
Sources/
  Frameflow/       macOS app UI, media browsing, preview, editor, export wiring
  FrameflowCore/   shared crop, trim, and timeline adjustment logic
Tests/
  FrameflowLogicTests/  executable logic tests
scripts/
  build-app.sh          builds a local .app bundle
  install-system.sh     installs the app into /Applications
  create-icon.swift     generates the app icon set
structure.md            UI and code map for maintainers
```

## Notes

- Timeline export currently supports video clips and writes MP4 output.
- Pinned media export preserves unedited files by copying them, while edited images, GIFs, WebP files, and videos are rendered to new files.
- No license file is included yet. Add one before distributing the project publicly.
