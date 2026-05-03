import Foundation
import FrameflowCore

extension MediaExport {
    static func encodeWebPClipsAsAnimatedWebP(
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
}
