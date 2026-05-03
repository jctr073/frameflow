@preconcurrency import AVFoundation
import CoreGraphics
import Foundation
import FrameflowCore

extension MediaExport {
    struct TimelineComposition {
        let composition: AVMutableComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix?
    }

    static func buildTimelineComposition(
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

    static func encodeTimelineAsMP4(
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
}
