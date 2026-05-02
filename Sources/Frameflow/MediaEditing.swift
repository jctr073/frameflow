@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import FrameflowCore
import UniformTypeIdentifiers

struct PinnedMediaItem: Identifiable, Hashable, Sendable {
    var item: MediaItem
    var crop: NormalizedCrop?
    var trim: MediaTrim?

    var id: URL { item.id }

    var isEdited: Bool {
        crop?.isFullFrame == false || trim != nil
    }
}

struct TimelineExportClip: Sendable {
    let item: MediaItem
    let trim: MediaTrim?
    let volume: Float
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

    private struct TimelineComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix?
    }

    private static func buildTimelineComposition(
        _ clips: [TimelineExportClip],
        adjustmentSpans: [TimelineAdjustmentSpan]
    ) async throws -> TimelineComposition {
        let composition = AVMutableComposition()
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        var cursor = CMTime.zero
        var renderSize: CGSize?
        var frameRate: Float = 30

        for clip in clips {
            let asset = AVURLAsset(url: clip.item.url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                throw MediaExportError.cannotLoadSource
            }

            let sourceTimeRange = (clip.trim?.timeRange(in: duration) ?? CMTimeRange(start: .zero, duration: duration))
            guard sourceTimeRange.duration.seconds > MediaTrim.minimumDuration else {
                throw MediaExportError.invalidTrim
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first,
                  let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  )
            else {
                throw MediaExportError.cannotLoadSource
            }

            try compositionVideoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: cursor)

            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let transformedBounds = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
                .standardized
            let displaySize = CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))
            let normalize = CGAffineTransform(
                translationX: -transformedBounds.minX,
                y: -transformedBounds.minY
            )
            let displayTransform = preferredTransform.concatenating(normalize)
            if renderSize == nil {
                let timelineRenderSize = TimelineCropRenderer.renderSize(
                    displaySize: displaySize,
                    adjustmentSpans: adjustmentSpans
                )
                renderSize = CGSize(width: even(timelineRenderSize.width), height: even(timelineRenderSize.height))
            }

            if let nominalFrameRate = try? await sourceVideoTrack.load(.nominalFrameRate), nominalFrameRate > frameRate {
                frameRate = nominalFrameRate
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: sourceTimeRange.duration)
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            if let renderSize {
                TimelineCropRenderer.applyTransformRamps(
                    to: layerInstruction,
                    timelineStart: cursor.seconds,
                    timelineEnd: (cursor + sourceTimeRange.duration).seconds,
                    displayTransform: displayTransform,
                    displaySize: displaySize,
                    renderSize: renderSize,
                    adjustmentSpans: adjustmentSpans
                )
            } else {
                layerInstruction.setTransform(preferredTransform, at: cursor)
            }
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            for audioTrack in audioTracks {
                guard let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }
                try? compositionAudioTrack.insertTimeRange(sourceTimeRange, of: audioTrack, at: cursor)
                let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                parameters.setVolume(max(0, clip.volume), at: cursor)
                audioParameters.append(parameters)
            }

            cursor = cursor + sourceTimeRange.duration
        }

        guard cursor.seconds > MediaTrim.minimumDuration,
              let renderSize
        else {
            throw MediaExportError.emptyTimeline
        }

        let effectiveFrameRate = max(frameRate.rounded(), 24)
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(effectiveFrameRate))
        videoComposition.instructions = instructions

        let audioMix: AVMutableAudioMix?
        if audioParameters.isEmpty {
            audioMix = nil
        } else {
            let mix = AVMutableAudioMix()
            mix.inputParameters = audioParameters
            audioMix = mix
        }

        return TimelineComposition(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: audioMix
        )
    }

    private static func encodeTimelineAsMP4(
        _ built: TimelineComposition,
        to destinationURL: URL
    ) async throws {
        guard let exportSession = AVAssetExportSession(asset: built.composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw MediaExportError.cannotCreateDestination
        }

        exportSession.outputURL = destinationURL
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        exportSession.videoComposition = built.videoComposition
        exportSession.audioMix = built.audioMix

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

    private static func encodeWebPClipsAsAnimatedWebP(
        _ clips: [TimelineExportClip],
        to destinationURL: URL
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            var clipFrames: [AnimatedWebPMuxer.ClipFrames] = []

            for clip in clips {
                let document = try AnimatedWebPMuxer.Document(url: clip.item.url)
                let totalDuration = document.duration
                let effectiveTrim = clip.trim?.clamped(to: totalDuration)
                let trimStart = effectiveTrim?.start ?? 0
                let trimEnd = effectiveTrim?.end ?? totalDuration
                guard trimEnd > trimStart else {
                    throw MediaExportError.invalidTrim
                }

                let frames = document.frames(overlappingStart: trimStart, end: trimEnd)
                guard !frames.isEmpty else {
                    throw MediaExportError.invalidTrim
                }
                clipFrames.append(AnimatedWebPMuxer.ClipFrames(canvas: document.canvas, frames: frames))
            }

            try AnimatedWebPMuxer.write(clipFrames, to: destinationURL)
        }.value
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
    case emptyTimeline
    case unsupportedTimelineClip
    case invalidCrop
    case invalidTrim
    case cannotCreateDestination
    case cannotFinalizeDestination
    case unsupportedTimelineWebPClip

    var errorDescription: String? {
        switch self {
        case .cannotLoadSource:
            return "The source media could not be loaded."
        case .emptyTimeline:
            return "The timeline is empty."
        case .invalidCrop:
            return "The crop area is too small."
        case .invalidTrim:
            return "The trim range is too short."
        case .cannotCreateDestination:
            return "The destination file could not be created."
        case .cannotFinalizeDestination:
            return "The edited media could not be saved."
        case .unsupportedTimelineWebPClip:
            return "WebP timeline export currently supports WebP clips only."
        case .unsupportedTimelineClip:
            return "Timeline export currently supports all-video MP4 exports or all-WebP animated WebP exports."
        }
    }
}

private final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}

private enum AnimatedWebPMuxer {
    struct Canvas: Sendable {
        let width: Int
        let height: Int
    }

    struct Frame: Sendable {
        var x: Int
        var y: Int
        let width: Int
        let height: Int
        var durationMS: Int
        var flags: UInt8
        let payload: Data
        let hasAlpha: Bool

        var duration: TimeInterval {
            TimeInterval(durationMS) / 1000
        }
    }

    struct ClipFrames: Sendable {
        let canvas: Canvas
        let frames: [Frame]
    }

    struct Document: Sendable {
        let canvas: Canvas
        let frames: [Frame]

        var duration: TimeInterval {
            frames.reduce(TimeInterval(0)) { $0 + $1.duration }
        }

        init(url: URL) throws {
            let data = try Data(contentsOf: url)
            let parsed = try AnimatedWebPMuxer.parse(data: data, url: url)
            canvas = parsed.canvas
            frames = parsed.frames
        }

        func frames(overlappingStart trimStart: TimeInterval, end trimEnd: TimeInterval) -> [Frame] {
            var selected: [Frame] = []
            var frameStart = TimeInterval(0)

            for frame in frames {
                let frameDuration = frame.duration
                let frameEnd = frameStart + frameDuration
                defer { frameStart = frameEnd }

                guard frameEnd > trimStart, frameStart < trimEnd else {
                    continue
                }

                let clippedDuration = min(frameEnd, trimEnd) - max(frameStart, trimStart)
                guard clippedDuration > 0 else {
                    continue
                }

                var clippedFrame = frame
                clippedFrame.durationMS = max(20, Int((clippedDuration * 1000).rounded()))
                selected.append(clippedFrame)
            }

            return selected
        }
    }

    private struct Chunk {
        let type: String
        let payload: Data
    }

    static func write(_ clips: [ClipFrames], to destinationURL: URL) throws {
        let clips = clips.filter { !$0.frames.isEmpty }
        guard !clips.isEmpty else {
            throw MediaExportError.emptyTimeline
        }

        let outputCanvas = Canvas(
            width: clips.map(\.canvas.width).max() ?? 0,
            height: clips.map(\.canvas.height).max() ?? 0
        )
        guard outputCanvas.width > 0, outputCanvas.height > 0 else {
            throw MediaExportError.cannotCreateDestination
        }

        let hasAlpha = clips.flatMap(\.frames).contains { $0.hasAlpha }
        var body = Data()

        var vp8x = Data()
        vp8x.appendUInt8((hasAlpha ? 0x10 : 0) | 0x02)
        vp8x.append(contentsOf: [0, 0, 0])
        vp8x.appendUInt24LE(outputCanvas.width - 1)
        vp8x.appendUInt24LE(outputCanvas.height - 1)
        body.appendWebPChunk(type: "VP8X", payload: vp8x)

        var anim = Data()
        anim.append(contentsOf: [0, 0, 0, 255])
        anim.appendUInt16LE(0)
        body.appendWebPChunk(type: "ANIM", payload: anim)

        for clip in clips {
            let baseX = evenOffset(forContent: clip.canvas.width, in: outputCanvas.width)
            let baseY = evenOffset(forContent: clip.canvas.height, in: outputCanvas.height)

            for (index, frame) in clip.frames.enumerated() {
                let isFirstFrameInClip = index == clip.frames.startIndex
                let isLastFrameInClip = index == clip.frames.index(before: clip.frames.endIndex)
                var flags = frame.flags
                if isFirstFrameInClip {
                    flags |= 0x02
                }
                if isLastFrameInClip {
                    flags |= 0x01
                }

                var payload = Data()
                payload.appendUInt24LE((frame.x + baseX) / 2)
                payload.appendUInt24LE((frame.y + baseY) / 2)
                payload.appendUInt24LE(frame.width - 1)
                payload.appendUInt24LE(frame.height - 1)
                payload.appendUInt24LE(frame.durationMS)
                payload.appendUInt8(flags)
                payload.append(frame.payload)
                body.appendWebPChunk(type: "ANMF", payload: payload)
            }
        }

        var output = Data()
        output.appendASCII("RIFF")
        output.appendUInt32LE(body.count + 4)
        output.appendASCII("WEBP")
        output.append(body)
        try output.write(to: destinationURL, options: .atomic)
    }

    private static func parse(data: Data, url: URL) throws -> (canvas: Canvas, frames: [Frame]) {
        let bytes = [UInt8](data)
        guard bytes.count >= 12,
              ascii(bytes, 0, 4) == "RIFF",
              ascii(bytes, 8, 4) == "WEBP"
        else {
            throw MediaExportError.cannotLoadSource
        }

        var chunks: [Chunk] = []
        var offset = 12
        while offset + 8 <= bytes.count {
            let type = ascii(bytes, offset, 4)
            let size = Int(readUInt32LE(bytes, offset + 4))
            let payloadStart = offset + 8
            let payloadEnd = payloadStart + size
            guard payloadEnd <= bytes.count else {
                throw MediaExportError.cannotLoadSource
            }
            chunks.append(Chunk(type: type, payload: Data(bytes[payloadStart..<payloadEnd])))
            offset = payloadEnd + (size & 1)
        }

        let vp8x = chunks.first { $0.type == "VP8X" }
        let vp8xBytes = vp8x.map { [UInt8]($0.payload) }
        let canvasFromHeader: Canvas? = vp8xBytes.flatMap { payload in
            guard payload.count >= 10 else { return nil }
            return Canvas(width: readUInt24LE(payload, 4) + 1, height: readUInt24LE(payload, 7) + 1)
        }
        let sourceHasAlpha = (vp8xBytes?.first ?? 0) & 0x10 != 0

        let animatedFrames = chunks.filter { $0.type == "ANMF" }.compactMap { chunk -> Frame? in
            let payload = [UInt8](chunk.payload)
            guard payload.count >= 16 else { return nil }
            let imagePayload = chunk.payload.dropFirst(16)
            return Frame(
                x: readUInt24LE(payload, 0) * 2,
                y: readUInt24LE(payload, 3) * 2,
                width: readUInt24LE(payload, 6) + 1,
                height: readUInt24LE(payload, 9) + 1,
                durationMS: max(20, readUInt24LE(payload, 12)),
                flags: payload[15],
                payload: Data(imagePayload),
                hasAlpha: sourceHasAlpha || containsAlphaChunk(Data(imagePayload))
            )
        }

        if !animatedFrames.isEmpty {
            guard let canvas = canvasFromHeader else {
                throw MediaExportError.cannotLoadSource
            }
            return (canvas, animatedFrames)
        }

        let frameChunks = chunks.filter { $0.type == "ALPH" || $0.type == "VP8 " || $0.type == "VP8L" }
        guard let imageChunk = frameChunks.last(where: { $0.type == "VP8 " || $0.type == "VP8L" }) else {
            throw MediaExportError.cannotLoadSource
        }

        let canvas = canvasFromHeader
            ?? imageCanvas(from: imageChunk)
            ?? imageCanvas(from: url)
        guard let canvas else {
            throw MediaExportError.cannotLoadSource
        }

        var payload = Data()
        for chunk in frameChunks {
            payload.appendWebPChunk(type: chunk.type, payload: chunk.payload)
        }

        let frame = Frame(
            x: 0,
            y: 0,
            width: canvas.width,
            height: canvas.height,
            durationMS: 1000,
            flags: 0x02,
            payload: payload,
            hasAlpha: sourceHasAlpha || frameChunks.contains { $0.type == "ALPH" || $0.type == "VP8L" }
        )
        return (canvas, [frame])
    }

    private static func imageCanvas(from chunk: Chunk) -> Canvas? {
        let bytes = [UInt8](chunk.payload)
        switch chunk.type {
        case "VP8 ":
            guard bytes.count >= 10 else { return nil }
            return Canvas(
                width: Int(readUInt16LE(bytes, 6) & 0x3fff),
                height: Int(readUInt16LE(bytes, 8) & 0x3fff)
            )
        case "VP8L":
            guard bytes.count >= 5, bytes[0] == 0x2f else { return nil }
            let b1 = Int(bytes[1])
            let b2 = Int(bytes[2])
            let b3 = Int(bytes[3])
            let b4 = Int(bytes[4])
            let width = 1 + (((b2 & 0x3f) << 8) | b1)
            let height = 1 + (((b4 & 0x0f) << 10) | (b3 << 2) | ((b2 & 0xc0) >> 6))
            return Canvas(width: width, height: height)
        default:
            return nil
        }
    }

    private static func imageCanvas(from url: URL) -> Canvas? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return nil
        }
        return Canvas(width: width, height: height)
    }

    private static func containsAlphaChunk(_ data: Data) -> Bool {
        let bytes = [UInt8](data)
        var offset = 0
        while offset + 8 <= bytes.count {
            let type = ascii(bytes, offset, 4)
            if type == "ALPH" || type == "VP8L" {
                return true
            }
            let size = Int(readUInt32LE(bytes, offset + 4))
            let nextOffset = offset + 8 + size + (size & 1)
            guard nextOffset > offset, nextOffset <= bytes.count else {
                return false
            }
            offset = nextOffset
        }
        return false
    }

    private static func evenOffset(forContent contentSize: Int, in canvasSize: Int) -> Int {
        let offset = max(0, (canvasSize - contentSize) / 2)
        return offset - (offset % 2)
    }

    private static func ascii(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> String {
        String(bytes: bytes[offset..<(offset + count)], encoding: .ascii) ?? ""
    }

    private static func readUInt16LE(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt24LE(_ bytes: [UInt8], _ offset: Int) -> Int {
        Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8) | (Int(bytes[offset + 2]) << 16)
    }

    private static func readUInt32LE(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(contentsOf: value.utf8)
    }

    mutating func appendUInt8(_ value: UInt8) {
        append(value)
    }

    mutating func appendUInt16LE(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt24LE(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
    }

    mutating func appendUInt32LE(_ value: Int) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }

    mutating func appendWebPChunk(type: String, payload: Data) {
        appendASCII(type)
        appendUInt32LE(payload.count)
        append(payload)
        if payload.count.isMultiple(of: 2) == false {
            appendUInt8(0)
        }
    }
}
