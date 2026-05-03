import Foundation
import FrameflowCore

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
