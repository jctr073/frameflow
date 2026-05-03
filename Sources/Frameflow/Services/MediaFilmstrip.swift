import AppKit
import AVFoundation
import FrameflowCore

enum MediaFilmstrip {
    static let frameCount = 16

    static func generate(for url: URL, duration: TimeInterval) async -> [NSImage]? {
        guard duration > 0 else { return nil }

        return await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity

            var images: [NSImage] = []
            images.reserveCapacity(frameCount)

            for index in 0..<frameCount {
                let fraction = (Double(index) + 0.5) / Double(frameCount)
                let seconds = max(0, fraction * duration)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else {
                    continue
                }
                let size = CGSize(width: cgImage.width, height: cgImage.height)
                images.append(NSImage(cgImage: cgImage, size: size))
            }

            return images.isEmpty ? nil : images
        }.value
    }
}
