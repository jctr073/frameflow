import AVFoundation
import CoreGraphics
import Foundation

struct MediaStatus: Equatable, Sendable {
    let size: CGSize?
    let duration: TimeInterval?

    var detailText: String {
        if let duration {
            return "Duration \(Self.formatDuration(duration))"
        }

        if let size {
            return "\(Int(size.width)) x \(Int(size.height)) px"
        }

        return ""
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%d:%02d", minutes, seconds)
    }
}

enum MediaMetadata {
    static func status(for item: MediaItem) async -> MediaStatus {
        async let size = MediaSizing.naturalSize(for: item)
        async let duration = duration(for: item)
        return await MediaStatus(size: size, duration: duration)
    }

    private static func duration(for item: MediaItem) async -> TimeInterval? {
        guard item.kind == .video else { return nil }

        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: item.url)
            do {
                let duration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(duration)
                guard seconds.isFinite, seconds > 0 else { return nil }
                return seconds
            } catch {
                return nil
            }
        }.value
    }
}
