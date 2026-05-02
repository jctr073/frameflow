import AppKit
import AVFoundation
import ImageIO
import MediaBrowserCore
import UniformTypeIdentifiers

enum MediaSnapshot {
    static func captureVideoFrame(
        from item: MediaItem,
        at time: TimeInterval,
        crop: NormalizedCrop
    ) async throws -> (item: MediaItem, thumbnail: NSImage) {
        try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: item.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero

            let requestedTime = CMTime(seconds: max(0, time), preferredTimescale: 600)
            let sourceImage = try generator.copyCGImage(at: requestedTime, actualTime: nil)
            let imageSize = CGSize(width: sourceImage.width, height: sourceImage.height)
            let cropRect = crop.pixelRect(in: imageSize)

            guard cropRect.width > 1,
                  cropRect.height > 1,
                  let outputImage = crop.isFullFrame ? sourceImage : sourceImage.cropping(to: cropRect)
            else {
                throw MediaSnapshotError.invalidFrame
            }

            let snapshotURL = try snapshotURL(for: item, time: time)
            guard let destination = CGImageDestinationCreateWithURL(
                snapshotURL as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            ) else {
                throw MediaSnapshotError.cannotWriteSnapshot
            }

            CGImageDestinationAddImage(destination, outputImage, [:] as CFDictionary)
            guard CGImageDestinationFinalize(destination) else {
                throw MediaSnapshotError.cannotWriteSnapshot
            }

            let snapshotItem = MediaItem(id: snapshotURL, url: snapshotURL, kind: .image)
            let thumbnail = NSImage(
                cgImage: outputImage,
                size: CGSize(width: outputImage.width, height: outputImage.height)
            )
            return (snapshotItem, thumbnail)
        }.value
    }

    private static func snapshotURL(for item: MediaItem, time: TimeInterval) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MediaBrowserSnapshots", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        let baseName = item.url.deletingPathExtension().lastPathComponent
        let centiseconds = Int((max(0, time) * 100).rounded())
        let fileName = "\(baseName)-snapshot-\(centiseconds)-\(UUID().uuidString.prefix(8)).png"
        return directory.appendingPathComponent(fileName)
    }
}

enum MediaSnapshotError: LocalizedError {
    case invalidFrame
    case cannotWriteSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidFrame:
            return "The current video frame could not be captured."
        case .cannotWriteSnapshot:
            return "The snapshot image could not be saved."
        }
    }
}
