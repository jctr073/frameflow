import FrameflowCore
import SwiftUI

struct TimelineAdjustmentSpanBlock: View {
    @Environment(\.editorTheme) private var theme
    let span: TimelineAdjustmentSpan
    let isSelected: Bool
    let isPaired: Bool
    let pixelsPerSecond: CGFloat
    let onSelect: () -> Void
    let onMove: (TimeInterval) -> Void
    let onResizeStart: (TimeInterval) -> Void
    let onResizeEnd: (TimeInterval) -> Void
    let onDeleteKeyframe: (TimelineCropKeyframe.ID) -> Void
    let onMoveKeyframe: (TimelineCropKeyframe.ID, TimeInterval) -> Void

    @State private var dragStartTime: TimeInterval?
    @State private var activeHandle: SpanHandle?
    @State private var keyframeDragStartTime: TimeInterval?
    @State private var draggingKeyframeID: TimelineCropKeyframe.ID?

    private let cornerRadius: CGFloat = 4
    private let labelHeight: CGFloat = 16
    private let yellowFill = Color(red: 0.96, green: 0.78, blue: 0.18)
    private let yellowFillSelected = Color(red: 1.00, green: 0.86, blue: 0.30)
    private let yellowLabel = Color(red: 0.88, green: 0.66, blue: 0.10)
    private let yellowLabelSelected = Color(red: 0.96, green: 0.74, blue: 0.14)
    private let selectionOutlineColor = Color(red: 0.86, green: 0.42, blue: 0.08)
    private let pairedOutlineColor = Color(red: 1.00, green: 0.62, blue: 0.10)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let showsLabel = width >= 30 && height > labelHeight + 10
            let contentHeight = max(0, height - (showsLabel ? labelHeight : 0))

            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(isSelected ? yellowFillSelected : yellowFill)

                    ForEach(span.sortedKeyframes) { keyframe in
                        Diamond()
                            .fill(Color.white)
                            .overlay {
                                Diamond()
                                    .stroke(
                                        draggingKeyframeID == keyframe.id ? theme.accent : Color.black.opacity(0.45),
                                        lineWidth: draggingKeyframeID == keyframe.id ? 1.5 : 1
                                    )
                            }
                            .frame(width: 9, height: 9)
                            .frame(width: 18, height: contentHeight)
                            .contentShape(Rectangle())
                            .offset(x: keyframeOffset(keyframe, width: width) - 9)
                            .highPriorityGesture(keyframeDragGesture(for: keyframe))
                            .contextMenu {
                                Button("Delete Keyframe") {
                                    onDeleteKeyframe(keyframe.id)
                                }
                            }
                            .quickTooltip("Crop Keyframe")
                            .accessibilityLabel("Crop Keyframe")
                    }
                }
                .frame(height: contentHeight)
                .clipped()

                if showsLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "crop")
                            .font(.system(size: 9, weight: .bold))

                        if width >= 70 {
                            Text(MediaTrim.format(span.duration))
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .lineLimit(1)
                        }
                    }
                    .foregroundStyle(Color.black.opacity(0.78))
                    .padding(.horizontal, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: labelHeight)
                    .background(isSelected ? yellowLabelSelected : yellowLabel)
                    .allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? (isPaired ? pairedOutlineColor : selectionOutlineColor) : Color.white.opacity(0.18),
                        lineWidth: isSelected ? (isPaired ? 3 : 2) : 1
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .gesture(moveGesture)
            .overlay(alignment: .leading) {
                resizeHandle(.leading)
            }
            .overlay(alignment: .trailing) {
                resizeHandle(.trailing)
            }
        }
    }

    private func keyframeOffset(_ keyframe: TimelineCropKeyframe, width: CGFloat) -> CGFloat {
        guard span.duration > 0 else { return 0 }
        let progress = min(max((keyframe.time - span.start) / span.duration, 0), 1)
        return CGFloat(progress) * width
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let startTime = dragStartTime ?? span.start
                dragStartTime = startTime
                onMove(startTime + TimeInterval(value.translation.width / max(pixelsPerSecond, 0.1)))
            }
            .onEnded { _ in
                dragStartTime = nil
            }
    }

    private func keyframeDragGesture(for keyframe: TimelineCropKeyframe) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                let startTime = keyframeDragStartTime ?? keyframe.time
                keyframeDragStartTime = startTime
                draggingKeyframeID = keyframe.id
                let delta = TimeInterval(value.translation.width / max(pixelsPerSecond, 0.1))
                onMoveKeyframe(keyframe.id, startTime + delta)
            }
            .onEnded { _ in
                keyframeDragStartTime = nil
                draggingKeyframeID = nil
            }
    }

    private func resizeHandle(_ handle: SpanHandle) -> some View {
        let active = activeHandle == handle
        let baseColor: Color = isSelected
            ? (isPaired ? pairedOutlineColor : selectionOutlineColor)
            : Color.black.opacity(0.32)
        return ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(baseColor.opacity(active ? 1.0 : 0.92))
            Capsule()
                .fill(Color.white.opacity(active ? 0.85 : 0.55))
                .frame(width: 1.5, height: 10)
        }
        .frame(width: 5)
        .padding(.vertical, 4)
        .padding(.horizontal, 1)
        .contentShape(Rectangle())
        .gesture(resizeGesture(handle))
        .quickTooltip(handle == .leading ? "Adjustment Start" : "Adjustment End")
        .accessibilityLabel(handle == .leading ? "Adjustment Start" : "Adjustment End")
    }

    private func resizeGesture(_ handle: SpanHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                activeHandle = handle
                let delta = TimeInterval(value.translation.width / max(pixelsPerSecond, 0.1))
                switch handle {
                case .leading:
                    let startTime = dragStartTime ?? span.start
                    dragStartTime = startTime
                    onResizeStart(startTime + delta)
                case .trailing:
                    let endTime = dragStartTime ?? span.end
                    dragStartTime = endTime
                    onResizeEnd(endTime + delta)
                }
            }
            .onEnded { _ in
                activeHandle = nil
                dragStartTime = nil
            }
    }

    private enum SpanHandle {
        case leading
        case trailing
    }
}
