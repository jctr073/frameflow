@preconcurrency import AVFoundation
import Foundation

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

final class ExportSessionBox: @unchecked Sendable {
    let session: AVAssetExportSession

    init(_ session: AVAssetExportSession) {
        self.session = session
    }
}
