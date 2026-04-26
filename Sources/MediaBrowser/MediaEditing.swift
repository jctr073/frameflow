@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct NormalizedCrop: Equatable, Hashable, Sendable {
    var x: CGFloat
    var y: CGFloat
    var width: CGFloat
    var height: CGFloat

    static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)

    var isFullFrame: Bool {
        abs(x) < 0.0001
            && abs(y) < 0.0001
            && abs(width - 1) < 0.0001
            && abs(height - 1) < 0.0001
    }

    var displayLabel: String {
        "\(Int((width * 100).rounded()))% x \(Int((height * 100).rounded()))%"
    }

    func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    func pixelRect(in size: CGSize) -> CGRect {
        rect(in: size)
            .intersection(CGRect(origin: .zero, size: size))
            .integral
    }

    func clamped(minimumSize: CGFloat = 0.04) -> NormalizedCrop {
        let nextWidth = min(max(width, minimumSize), 1)
        let nextHeight = min(max(height, minimumSize), 1)
        let nextX = min(max(x, 0), 1 - nextWidth)
        let nextY = min(max(y, 0), 1 - nextHeight)
        return NormalizedCrop(x: nextX, y: nextY, width: nextWidth, height: nextHeight)
    }

    static func centered(aspectRatio targetAspectRatio: CGFloat, naturalSize: CGSize) -> NormalizedCrop {
        guard targetAspectRatio > 0,
              naturalSize.width > 0,
              naturalSize.height > 0
        else {
            return .full
        }

        let mediaAspectRatio = naturalSize.width / naturalSize.height
        let normalizedAspectRatio = targetAspectRatio / mediaAspectRatio
        let size: CGSize

        if normalizedAspectRatio >= 1 {
            size = CGSize(width: 1, height: 1 / normalizedAspectRatio)
        } else {
            size = CGSize(width: normalizedAspectRatio, height: 1)
        }

        return NormalizedCrop(
            x: (1 - size.width) / 2,
            y: (1 - size.height) / 2,
            width: size.width,
            height: size.height
        ).clamped()
    }
}

struct MediaTrim: Equatable, Hashable, Sendable {
    var start: TimeInterval
    var end: TimeInterval

    static let minimumDuration: TimeInterval = 0.1

    var duration: TimeInterval {
        max(0, end - start)
    }

    var displayLabel: String {
        "\(Self.format(start))-\(Self.format(end))"
    }

    func isFullLength(for totalDuration: TimeInterval?) -> Bool {
        guard let totalDuration, totalDuration > 0 else { return true }
        let trimmed = clamped(to: totalDuration)
        return trimmed.start <= 0.001 && abs(trimmed.end - totalDuration) <= 0.001
    }

    func clamped(to totalDuration: TimeInterval) -> MediaTrim {
        guard totalDuration > 0 else {
            return MediaTrim(start: 0, end: 0)
        }

        let minimumDuration = min(Self.minimumDuration, totalDuration)
        let nextStart = min(max(start, 0), max(0, totalDuration - minimumDuration))
        let nextEnd = min(max(end, nextStart + minimumDuration), totalDuration)
        return MediaTrim(start: nextStart, end: nextEnd)
    }

    func timeRange(in totalDuration: CMTime) -> CMTimeRange {
        let totalSeconds = CMTimeGetSeconds(totalDuration)
        let trimmed = clamped(to: totalSeconds)
        let startTime = CMTime(seconds: trimmed.start, preferredTimescale: 600)
        let durationTime = CMTime(seconds: trimmed.end - trimmed.start, preferredTimescale: 600)
        return CMTimeRange(start: startTime, duration: durationTime)
    }

    static func full(duration: TimeInterval) -> MediaTrim {
        MediaTrim(start: 0, end: max(0, duration))
    }

    static func format(_ time: TimeInterval) -> String {
        let totalSeconds = max(0, Int(time.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct PinnedMediaItem: Identifiable, Hashable, Sendable {
    var item: MediaItem
    var crop: NormalizedCrop?
    var trim: MediaTrim?

    var id: URL { item.id }

    var isEdited: Bool {
        crop?.isFullFrame == false || trim != nil
    }
}

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

    private static func exportRasterImage(_ item: MediaItem, crop: NormalizedCrop, to destinationURL: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                throw MediaExportError.cannotLoadSource
            }

            let sourceSize = CGSize(width: image.width, height: image.height)
            let cropRect = crop.pixelRect(in: sourceSize)
            guard cropRect.width > 1,
                  cropRect.height > 1,
                  let croppedImage = image.cropping(to: cropRect)
            else {
                throw MediaExportError.invalidCrop
            }

            let typeIdentifier = rasterTypeIdentifier(for: destinationURL)
            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                typeIdentifier as CFString,
                1,
                nil
            ) else {
                throw MediaExportError.cannotCreateDestination
            }

            let options: [CFString: Any]
            if typeIdentifier == UTType.jpeg.identifier {
                options = [kCGImageDestinationLossyCompressionQuality: 0.94]
            } else {
                options = [:]
            }

            CGImageDestinationAddImage(destination, croppedImage, options as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw MediaExportError.cannotFinalizeDestination
            }
        }.value
    }

    private static func exportAnimatedGIF(
        _ item: MediaItem,
        crop: NormalizedCrop,
        trim: MediaTrim?,
        to destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else {
                throw MediaExportError.cannotLoadSource
            }

            let frameCount = CGImageSourceGetCount(source)
            guard frameCount > 0 else {
                throw MediaExportError.cannotLoadSource
            }

            let frameDurations = (0..<frameCount).map { gifFrameDuration(source: source, index: $0) }
            let totalDuration = frameDurations.reduce(0, +)
            let effectiveTrim = trim?.clamped(to: totalDuration)
            let trimStart = effectiveTrim?.start ?? 0
            let trimEnd = effectiveTrim?.end ?? totalDuration
            guard trimEnd > trimStart else {
                throw MediaExportError.invalidTrim
            }

            var selectedFrames: [(index: Int, delay: TimeInterval)] = []
            var frameStart: TimeInterval = 0
            for index in 0..<frameCount {
                let originalDelay = frameDurations[index]
                let frameEnd = frameStart + originalDelay
                defer { frameStart = frameEnd }

                guard frameEnd > trimStart, frameStart < trimEnd else {
                    continue
                }

                let clippedDelay = min(frameEnd, trimEnd) - max(frameStart, trimStart)
                selectedFrames.append((index, max(0.02, clippedDelay.isFinite ? clippedDelay : originalDelay)))
            }

            guard !selectedFrames.isEmpty else {
                throw MediaExportError.invalidTrim
            }

            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.gif.identifier as CFString,
                selectedFrames.count,
                nil
            ) else {
                throw MediaExportError.cannotCreateDestination
            }

            CGImageDestinationSetProperties(destination, [
                kCGImagePropertyGIFDictionary: [
                    kCGImagePropertyGIFLoopCount: 0
                ]
            ] as CFDictionary)

            var exportedFrames = 0
            for frame in selectedFrames {
                guard let image = CGImageSourceCreateImageAtIndex(source, frame.index, nil) else {
                    continue
                }

                let sourceSize = CGSize(width: image.width, height: image.height)
                let cropRect = crop.pixelRect(in: sourceSize)
                guard cropRect.width > 1, cropRect.height > 1,
                      let outputImage = crop.isFullFrame ? image : image.cropping(to: cropRect)
                else {
                    throw MediaExportError.invalidCrop
                }

                CGImageDestinationAddImage(destination, outputImage, [
                    kCGImagePropertyGIFDictionary: [
                        kCGImagePropertyGIFDelayTime: frame.delay,
                        kCGImagePropertyGIFUnclampedDelayTime: frame.delay
                    ]
                ] as CFDictionary)
                exportedFrames += 1
            }

            guard exportedFrames > 0 else {
                throw MediaExportError.invalidTrim
            }
            guard CGImageDestinationFinalize(destination) else {
                throw MediaExportError.cannotFinalizeDestination
            }
        }.value
    }

    private static func exportVideo(_ item: MediaItem, crop: NormalizedCrop, trim: MediaTrim?, to destinationURL: URL) async throws {
        let asset = AVURLAsset(url: item.url)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)
        guard let sourceVideoTrack = videoTracks.first else {
            throw MediaExportError.cannotLoadSource
        }

        let duration = try await asset.load(.duration)
        let sourceTimeRange = trim?.timeRange(in: duration) ?? CMTimeRange(start: .zero, duration: duration)
        let naturalSize = try await sourceVideoTrack.load(.naturalSize)
        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        let transformedBounds = CGRect(origin: .zero, size: naturalSize)
            .applying(preferredTransform)
            .standardized
        let displaySize = CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))
        let cropRect = crop.pixelRect(in: displaySize)
        guard cropRect.width > 1, cropRect.height > 1 else {
            throw MediaExportError.invalidCrop
        }

        let composition = AVMutableComposition()
        guard let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw MediaExportError.cannotCreateDestination
        }
        try compositionVideoTrack.insertTimeRange(
            sourceTimeRange,
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = preferredTransform

        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        for audioTrack in audioTracks {
            guard let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continue
            }
            try? compositionAudioTrack.insertTimeRange(
                sourceTimeRange,
                of: audioTrack,
                at: .zero
            )
        }

        let videoComposition: AVMutableVideoComposition?
        if crop.isFullFrame {
            videoComposition = nil
        } else {
            let nextVideoComposition = AVMutableVideoComposition()
            nextVideoComposition.renderSize = CGSize(width: even(cropRect.width), height: even(cropRect.height))
            let frameRate = try await sourceVideoTrack.load(.nominalFrameRate)
            nextVideoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate.rounded(), 24)))

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: sourceTimeRange.duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            let translation = CGAffineTransform(
                translationX: -transformedBounds.minX - cropRect.minX,
                y: -transformedBounds.minY - cropRect.minY
            )
            layerInstruction.setTransform(preferredTransform.concatenating(translation), at: .zero)
            instruction.layerInstructions = [layerInstruction]
            nextVideoComposition.instructions = [instruction]
            videoComposition = nextVideoComposition
        }

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaExportError.cannotCreateDestination
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = videoComposition

        let exportSessionBox = ExportSessionBox(exportSession)
        try await withCheckedThrowingContinuation { continuation in
            exportSession.exportAsynchronously {
                switch exportSessionBox.session.status {
                case .completed:
                    continuation.resume()
                case .failed, .cancelled:
                    continuation.resume(throwing: exportSessionBox.session.error ?? MediaExportError.cannotFinalizeDestination)
                default:
                    continuation.resume(throwing: MediaExportError.cannotFinalizeDestination)
                }
            }
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

    private static func gifFrameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }

        let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
        let delay = unclampedDelay ?? gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval ?? 0.1
        return max(0.02, delay)
    }

    private static func supportedRasterExtension(_ pathExtension: String) -> String {
        let normalizedExtension = pathExtension.lowercased()
        if ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"].contains(normalizedExtension) {
            return normalizedExtension
        }
        return "png"
    }

    private static func rasterTypeIdentifier(for url: URL) -> String {
        switch supportedRasterExtension(url.pathExtension) {
        case "jpg", "jpeg":
            return UTType.jpeg.identifier
        case "tif", "tiff":
            return UTType.tiff.identifier
        case "heic", "heif":
            return UTType.heic.identifier
        default:
            return UTType.png.identifier
        }
    }

    private static func even(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }
}

enum MediaExportError: LocalizedError {
    case cannotLoadSource
    case invalidCrop
    case invalidTrim
    case cannotCreateDestination
    case cannotFinalizeDestination

    var errorDescription: String? {
        switch self {
        case .cannotLoadSource:
            return "The source media could not be loaded."
        case .invalidCrop:
            return "The crop area is too small."
        case .invalidTrim:
            return "The trim range is too short."
        case .cannotCreateDestination:
            return "The destination file could not be created."
        case .cannotFinalizeDestination:
            return "The edited media could not be saved."
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
