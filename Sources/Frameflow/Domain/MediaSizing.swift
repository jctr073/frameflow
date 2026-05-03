import AppKit
import AVFoundation
import ImageIO
import Foundation

enum MediaSizing {
    static func naturalSize(for item: MediaItem) async -> CGSize? {
        switch item.kind {
        case .image, .gif, .webp:
            return await Task.detached(priority: .userInitiated) {
                if let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
                   let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                   let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
                   let height = properties[kCGImagePropertyPixelHeight] as? CGFloat,
                   width > 0,
                   height > 0 {
                    return CGSize(width: width, height: height)
                }

                guard let image = NSImage(contentsOf: item.url) else { return nil }
                if let representation = image.representations.max(by: { lhs, rhs in
                    (lhs.pixelsWide * lhs.pixelsHigh) < (rhs.pixelsWide * rhs.pixelsHigh)
                }), representation.pixelsWide > 0, representation.pixelsHigh > 0 {
                    return CGSize(width: representation.pixelsWide, height: representation.pixelsHigh)
                }
                return image.size
            }.value
        case .video:
            return await Task.detached(priority: .userInitiated) {
                let asset = AVURLAsset(url: item.url)
                do {
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else { return nil }
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let transformed = size.applying(transform)
                    let width = abs(transformed.width)
                    let height = abs(transformed.height)
                    guard width > 0, height > 0 else { return nil }
                    return CGSize(width: width, height: height)
                } catch {
                    return nil
                }
            }.value
        }
    }
}
