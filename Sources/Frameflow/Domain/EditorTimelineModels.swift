import AppKit
import FrameflowCore
import Foundation

struct EditorClip: Identifiable {
    var id: URL { item.id }
    let item: MediaItem
    var thumbnail: NSImage?
    var status: MediaStatus?
    var filmstrip: [NSImage]?
}

struct EditorTimelineClip: Identifiable, Hashable {
    let id = UUID()
    let sourceClipID: EditorClip.ID
    var trim: MediaTrim? = nil
    var adjustments = EditorTimelineAdjustments()
    var leadingGap: TimeInterval = 0
}

struct EditorTimelineAdjustments: Hashable {
    var viewMode: EditorViewMode = .wide
    var fieldOfView = 90.0
    var yaw = 0.0
    var pitch = 0.0
    var roll = 0.0
    var keyframesEnabled = false
    var deepTrackEnabled = false
    var transitionStyle: EditorKeyframeTransition = .linear
    var stabilizationEnabled = false
    var horizonLockEnabled = false
    var horizonLevel = 0.0
    var zoom = 1.0
    var offsetX = 0.0
    var offsetY = 0.0
    var isMuted = false
    var volume = 1.0
    var noiseReductionEnabled = false
    var exposure = 0.0
    var contrast = 1.0
    var saturation = 1.0
    var sharpness = 0.0
}

enum EditorViewMode: String, CaseIterable, Identifiable {
    case wide
    case linear
    case tinyPlanet
    case crystalBall

    var id: Self { self }

    var title: String {
        switch self {
        case .wide:
            return "Wide"
        case .linear:
            return "Linear"
        case .tinyPlanet:
            return "Tiny"
        case .crystalBall:
            return "Crystal"
        }
    }
}

enum EditorKeyframeTransition: String, CaseIterable, Identifiable {
    case linear
    case easeIn
    case easeOut
    case easeInOut

    var id: Self { self }

    var title: String {
        switch self {
        case .linear:
            return "Linear"
        case .easeIn:
            return "Ease In"
        case .easeOut:
            return "Ease Out"
        case .easeInOut:
            return "Ease"
        }
    }
}
