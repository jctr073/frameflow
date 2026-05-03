import Foundation
import FrameflowCore

enum MediaExport {
    static func export(_ pinnedItem: PinnedMediaItem, to destinationURL: URL) async throws {
        let crop = pinnedItem.crop ?? .full
        let trim = pinnedItem.trim

        guard pinnedItem.isEdited else {
            try FileManager.default.copyItem(at: pinnedItem.item.url, to: destinationURL)
            return
        }

        switch pinnedItem.item.kind {
        case .image, .webp:
            try await exportRasterImage(pinnedItem.item, crop: crop, to: destinationURL)
        case .gif:
            try await exportAnimatedGIF(pinnedItem.item, crop: crop, trim: trim, to: destinationURL)
        case .video:
            try await exportVideo(pinnedItem.item, crop: crop, trim: trim, to: destinationURL)
        }
    }

    static func exportTimeline(
        _ clips: [TimelineExportClip],
        adjustmentSpans: [TimelineAdjustmentSpan] = [],
        to destinationURL: URL
    ) async throws {
        guard !clips.isEmpty else {
            throw MediaExportError.emptyTimeline
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        let outputExtension = destinationURL.pathExtension.lowercased()
        let allWebPSources = clips.allSatisfy { $0.item.kind == .webp }
        let allVideoSources = clips.allSatisfy { $0.item.kind == .video }

        if outputExtension == "webp" {
            guard allWebPSources else {
                throw MediaExportError.unsupportedTimelineWebPClip
            }
            try await encodeWebPClipsAsAnimatedWebP(clips, to: destinationURL)
            return
        }

        guard allVideoSources else {
            throw MediaExportError.unsupportedTimelineClip
        }

        let built = try await buildTimelineComposition(clips, adjustmentSpans: adjustmentSpans)
        try await encodeTimelineAsMP4(built, to: destinationURL)
    }

    static func destinationFileName(for pinnedItem: PinnedMediaItem) -> String {
        guard pinnedItem.isEdited else {
            return pinnedItem.item.fileName
        }

        let baseName = pinnedItem.item.url.deletingPathExtension().lastPathComponent
        let suffix = editSuffix(for: pinnedItem)
        switch pinnedItem.item.kind {
        case .video:
            return "\(baseName)\(suffix).mp4"
        case .image:
            let ext = supportedRasterExtension(pinnedItem.item.url.pathExtension)
            return "\(baseName)\(suffix).\(ext)"
        case .gif:
            return "\(baseName)\(suffix).gif"
        case .webp:
            return "\(baseName)\(suffix).png"
        }
    }

    private static func editSuffix(for pinnedItem: PinnedMediaItem) -> String {
        var parts: [String] = []
        if pinnedItem.crop?.isFullFrame == false {
            parts.append("cropped")
        }
        if pinnedItem.trim != nil {
            parts.append("trimmed")
        }
        return parts.isEmpty ? "" : "-" + parts.joined(separator: "-")
    }

    static func supportedRasterExtension(_ pathExtension: String) -> String {
        let normalizedExtension = pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"].contains(normalizedExtension) {
            return normalizedExtension
        }
        return "png"
    }
}
