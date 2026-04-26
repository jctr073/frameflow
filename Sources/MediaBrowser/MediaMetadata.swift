import AVFoundation
import CoreGraphics
import Foundation
import ImageIO

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
        switch item.kind {
        case .video:
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
        case .gif:
            return await Task.detached(priority: .utility) {
                guard let source = CGImageSourceCreateWithURL(item.url as CFURL, nil) else {
                    return nil
                }

                let count = CGImageSourceGetCount(source)
                guard count > 0 else { return nil }
                let duration = (0..<count).reduce(TimeInterval(0)) { total, index in
                    total + gifFrameDuration(source: source, index: index)
                }
                return duration > 0 ? duration : nil
            }.value
        case .image, .webp:
            return nil
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
}
