import Foundation

enum EditorDragPayload {
    static let editorClipPrefix = "editor-clip:"
    static let timelineClipPrefix = "timeline-clip:"

    static func editorClipPayload(for clipID: EditorClip.ID) -> String {
        "\(editorClipPrefix)\(clipID.absoluteString)"
    }

    static func timelineClipPayload(for clipID: EditorTimelineClip.ID) -> String {
        "\(timelineClipPrefix)\(clipID.uuidString)"
    }

    static func editorClipID(from payload: String) -> EditorClip.ID? {
        if payload.hasPrefix(editorClipPrefix) {
            let rawValue = String(payload.dropFirst(editorClipPrefix.count))
            return URL(string: rawValue)
        }

        return URL(string: payload)
    }

    static func timelineClipID(from payload: String) -> EditorTimelineClip.ID? {
        guard payload.hasPrefix(timelineClipPrefix) else {
            return nil
        }

        let rawValue = String(payload.dropFirst(timelineClipPrefix.count))
        return UUID(uuidString: rawValue)
    }
}
