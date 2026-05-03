import SwiftUI

struct TimelineClipReorderDropDelegate: DropDelegate {
    let targetClipID: EditorTimelineClip.ID
    @Binding var draggingClipID: EditorTimelineClip.ID?
    let moveClip: (EditorTimelineClip.ID, EditorTimelineClip.ID) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        draggingClipID != nil
    }

    func dropEntered(info: DropInfo) {
        guard let draggingClipID,
              draggingClipID != targetClipID
        else {
            return
        }

        moveClip(draggingClipID, targetClipID)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingClipID = nil
        return true
    }
}
