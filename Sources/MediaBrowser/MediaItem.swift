import Foundation
import UniformTypeIdentifiers

enum MediaKind: String, CaseIterable, Sendable {
    case image
    case gif
    case webp
    case video

    var label: String {
        switch self {
        case .image: "Image"
        case .gif: "GIF"
        case .webp: "WebP"
        case .video: "Video"
        }
    }

    var shouldUpscaleToFit: Bool {
        switch self {
        case .gif, .webp:
            return true
        case .image, .video:
            return false
        }
    }
}

struct MediaItem: Identifiable, Hashable, Sendable {
    let id: URL
    let url: URL
    let kind: MediaKind

    var fileName: String {
        url.lastPathComponent
    }

    static func kind(for url: URL) -> MediaKind? {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "png", "tif", "tiff", "bmp", "heic", "heif":
            return .image
        case "webp":
            return .webp
        case "gif":
            return .gif
        case "mp4", "mov", "m4v":
            return .video
        default:
            guard let type = UTType(filenameExtension: ext) else { return nil }
            if type.conforms(to: .gif) {
                return .gif
            }
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .movie) || type.conforms(to: .audiovisualContent) {
                return .video
            }
            return nil
        }
    }
}
