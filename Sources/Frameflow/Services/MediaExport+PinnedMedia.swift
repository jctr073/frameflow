@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import FrameflowCore
import UniformTypeIdentifiers

extension MediaExport {
    static func exportRasterImage(_ item: MediaItem, crop: NormalizedCrop, to destinationURL: URL) async throws {
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

    static func exportAnimatedGIF(
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

    static func exportVideo(_ item: MediaItem, crop: NormalizedCrop, trim: MediaTrim?, to destinationURL: URL) async throws {
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
}
