import AppKit
import FrameflowCore
import SwiftUI

struct TimelineClipBlock: View {
    @Environment(\.editorTheme) private var theme
    let sourceClip: EditorClip?
    let thumbnail: NSImage?
    let filmstrip: [NSImage]?
    let isSelected: Bool
    let isPaired: Bool
    let trim: MediaTrim
    let totalDuration: TimeInterval
    let pixelsPerSecond: CGFloat
    let onTrimChange: (MediaTrim) -> Void

    @State private var activeTrimHandle: TimelineTrimHandle?
    @State private var trimDragStart: MediaTrim?

    private let cornerRadius: CGFloat = 4
    private let labelHeight: CGFloat = 20
    private let selectionOutlineColor = Color(red: 0.86, green: 0.42, blue: 0.08)
    private let pairedOutlineColor = Color(red: 1.00, green: 0.62, blue: 0.10)

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let showsLabel = width >= 36 && height > labelHeight + 12
            let thumbnailHeight = max(0, height - (showsLabel ? labelHeight : 0))
            let widthCap = max(1, Int(floor(width / 24)))
            let frameCount = min(sampleCount(forDuration: trim.duration), widthCap)
            let frameWidth = width / CGFloat(frameCount)

            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(theme.thumbnailWell)

                    HStack(spacing: 0) {
                        ForEach(0..<frameCount, id: \.self) { index in
                            let frameImage = filmstripFrame(forTileIndex: index, frameCount: frameCount)
                            Group {
                                if let frameImage {
                                    Image(nsImage: frameImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                } else {
                                    Rectangle().fill(theme.thumbnailWell)
                                }
                            }
                            .frame(width: frameWidth, height: thumbnailHeight)
                            .clipped()
                            .overlay(alignment: .trailing) {
                                if index < frameCount - 1 {
                                    Rectangle()
                                        .fill(Color.black.opacity(0.18))
                                        .frame(width: 1)
                                }
                            }
                        }
                    }
                    .frame(width: width, height: thumbnailHeight, alignment: .leading)
                    .clipped()
                }
                .frame(height: thumbnailHeight)
                .clipped()

                if showsLabel {
                    Text(sourceClip?.item.fileName ?? "Missing Clip")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: labelHeight)
                        .background(isSelected ? theme.clipBlueSelected : theme.clipBlue)
                        .help(detailText)
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
            .overlay(alignment: .leading) {
                if canTrim {
                    trimHandle(.leading)
                }
            }
            .overlay(alignment: .trailing) {
                if canTrim {
                    trimHandle(.trailing)
                }
            }
        }
    }

    private func sampleCount(forDuration duration: TimeInterval) -> Int {
        if duration < 10 { return 1 }
        if duration < 30 { return 2 }
        if duration < 120 { return 3 }
        if duration < 600 { return 4 }
        if duration < 1800 { return 5 }
        return 6
    }

    private func filmstripFrame(forTileIndex index: Int, frameCount: Int) -> NSImage? {
        if let filmstrip, !filmstrip.isEmpty, totalDuration > 0 {
            let fraction = (Double(index) + 0.5) / Double(max(frameCount, 1))
            let absoluteTime = trim.start + fraction * trim.duration
            let frac = max(0, min(1, absoluteTime / totalDuration))
            let stripIndex = min(filmstrip.count - 1, max(0, Int((frac * Double(filmstrip.count - 1)).rounded())))
            return filmstrip[stripIndex]
        }
        return thumbnail
    }

    private var detailText: String {
        guard sourceClip != nil else {
            return "Offline"
        }

        guard totalDuration > 0 else {
            return sourceClip?.item.kind.label ?? "Media"
        }

        if trim.isFullLength(for: totalDuration) {
            return MediaTrim.format(totalDuration)
        }

        return "\(MediaTrim.format(trim.start))-\(MediaTrim.format(trim.end))"
    }

    private var canTrim: Bool {
        isSelected && totalDuration > MediaTrim.minimumDuration
    }

    private func trimHandle(_ handle: TimelineTrimHandle) -> some View {
        let active = activeTrimHandle == handle
        let baseColor = isPaired ? pairedOutlineColor : selectionOutlineColor
        return ZStack {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(baseColor.opacity(active ? 1.0 : 0.94))
            Capsule()
                .fill(Color.white.opacity(active ? 0.85 : 0.6))
                .frame(width: 1.5, height: 14)
        }
        .frame(width: 5, height: 30)
        .padding(.horizontal, 1)
        .contentShape(Rectangle())
        .gesture(trimGesture(handle))
        .quickTooltip(handle == .leading ? "Trim Start" : "Trim End")
        .accessibilityLabel(handle == .leading ? "Trim Start" : "Trim End")
    }

    private func trimGesture(_ handle: TimelineTrimHandle) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startTrim = trimDragStart ?? trim
                trimDragStart = startTrim
                activeTrimHandle = handle

                let delta = TimeInterval(value.translation.width / max(pixelsPerSecond, 0.1))
                switch handle {
                case .leading:
                    onTrimChange(MediaTrim(start: startTrim.start + delta, end: startTrim.end))
                case .trailing:
                    onTrimChange(MediaTrim(start: startTrim.start, end: startTrim.end + delta))
                }
            }
            .onEnded { _ in
                activeTrimHandle = nil
                trimDragStart = nil
            }
    }

    private enum TimelineTrimHandle {
        case leading
        case trailing
    }
}
