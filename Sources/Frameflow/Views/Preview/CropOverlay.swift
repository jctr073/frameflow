import FrameflowCore
import SwiftUI

struct CropOverlay: View {
    @Environment(\.editorTheme) private var theme
    @Binding var crop: NormalizedCrop
    let isEditable: Bool
    let onApply: () -> Void
    var outlineColor: Color?
    var usesDashedOutline = true

    @State private var activeDragStart: NormalizedCrop?

    var body: some View {
        GeometryReader { geometry in
            let cropRect = crop.rect(in: geometry.size)
            let accentColor = outlineColor ?? theme.accent

            ZStack(alignment: .topLeading) {
                CropDimShape(cropRect: cropRect)
                    .fill(Color.black.opacity(0.62), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)

                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .gesture(moveGesture(in: geometry.size))
                    .allowsHitTesting(isEditable)

                if isEditable {
                    CropThirdsGuide(rect: cropRect)
                        .stroke(Color.white.opacity(0.22), lineWidth: 0.6)
                        .allowsHitTesting(false)
                }

                Rectangle()
                    .strokeBorder(Color.black.opacity(0.45), lineWidth: 0.75)
                    .frame(width: cropRect.width + 1.5, height: cropRect.height + 1.5)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .allowsHitTesting(false)

                Rectangle()
                    .strokeBorder(
                        accentColor.opacity(isEditable ? 0.95 : 0.85),
                        style: isEditable
                            ? StrokeStyle(lineWidth: 1.25)
                            : StrokeStyle(lineWidth: 1.5, dash: usesDashedOutline ? [7, 5] : [])
                    )
                    .frame(width: cropRect.width, height: cropRect.height)
                    .position(x: cropRect.midX, y: cropRect.midY)
                    .allowsHitTesting(false)

                if isEditable {
                    ForEach(CropHandle.allCases) { handle in
                        ZStack {
                            Rectangle()
                                .fill(Color.white.opacity(0.001))
                                .frame(width: 30, height: 30)

                            if handle.isCorner {
                                CropCornerBracket(corner: handle, armLength: 16, thickness: 3)
                                    .fill(accentColor)
                                    .frame(width: 32, height: 32)
                            } else if let size = handle.edgeCapsuleSize {
                                Capsule()
                                    .fill(accentColor)
                                    .frame(width: size.width, height: size.height)
                            }
                        }
                        .shadow(color: Color.black.opacity(0.35), radius: 1.5, x: 0, y: 0.5)
                        .contentShape(Rectangle())
                        .position(handle.position(in: cropRect))
                        .gesture(resizeGesture(handle: handle, in: geometry.size))
                    }

                    if !crop.isFullFrame {
                        Button {
                            onApply()
                        } label: {
                            Label("Apply", systemImage: "checkmark")
                                .font(.caption.weight(.semibold))
                                .labelStyle(.titleAndIcon)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white)
                        .background(theme.accent, in: Capsule())
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 1)
                        .position(
                            x: min(max(cropRect.maxX - 38, 42), geometry.size.width - 42),
                            y: min(max(cropRect.minY + 22, 22), geometry.size.height - 22)
                        )
                        .zIndex(2)
                        .allowsHitTesting(true)
                        .quickTooltip("Apply Crop")
                    }
                }
            }
        }
    }

    private func moveGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startCrop = activeDragStart ?? crop
                activeDragStart = startCrop
                crop = NormalizedCrop(
                    x: startCrop.x + value.translation.width / max(size.width, 1),
                    y: startCrop.y + value.translation.height / max(size.height, 1),
                    width: startCrop.width,
                    height: startCrop.height
                ).clamped()
            }
            .onEnded { _ in
                activeDragStart = nil
            }
    }

    private func resizeGesture(handle: CropHandle, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let startCrop = activeDragStart ?? crop
                activeDragStart = startCrop
                let deltaX = value.translation.width / max(size.width, 1)
                let deltaY = value.translation.height / max(size.height, 1)
                crop = handle.resizedCrop(from: startCrop, deltaX: deltaX, deltaY: deltaY)
            }
            .onEnded { _ in
                activeDragStart = nil
            }
    }
}

private struct CropDimShape: Shape {
    let cropRect: CGRect

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(cropRect)
        return path
    }
}

private struct CropThirdsGuide: Shape {
    let rect: CGRect

    func path(in _: CGRect) -> Path {
        var path = Path()
        let widthThird = rect.width / 3
        let heightThird = rect.height / 3

        for column in 1...2 {
            let x = rect.minX + widthThird * CGFloat(column)
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        for row in 1...2 {
            let y = rect.minY + heightThird * CGFloat(row)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

private struct CropCornerBracket: Shape {
    let corner: CropHandle
    let armLength: CGFloat
    let thickness: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let mid = CGPoint(x: rect.midX, y: rect.midY)
        let arm = armLength
        let thick = thickness

        switch corner {
        case .topLeading:
            path.addRect(CGRect(x: mid.x, y: mid.y, width: arm, height: thick))
            path.addRect(CGRect(x: mid.x, y: mid.y, width: thick, height: arm))
        case .topTrailing:
            path.addRect(CGRect(x: mid.x - arm, y: mid.y, width: arm, height: thick))
            path.addRect(CGRect(x: mid.x - thick, y: mid.y, width: thick, height: arm))
        case .bottomLeading:
            path.addRect(CGRect(x: mid.x, y: mid.y - thick, width: arm, height: thick))
            path.addRect(CGRect(x: mid.x, y: mid.y - arm, width: thick, height: arm))
        case .bottomTrailing:
            path.addRect(CGRect(x: mid.x - arm, y: mid.y - thick, width: arm, height: thick))
            path.addRect(CGRect(x: mid.x - thick, y: mid.y - arm, width: thick, height: arm))
        default:
            break
        }
        return path
    }
}

private enum CropHandle: CaseIterable, Identifiable {
    case topLeading
    case top
    case topTrailing
    case trailing
    case bottomTrailing
    case bottom
    case bottomLeading
    case leading

    var id: Self { self }

    func position(in rect: CGRect) -> CGPoint {
        switch self {
        case .topLeading:
            CGPoint(x: rect.minX, y: rect.minY)
        case .top:
            CGPoint(x: rect.midX, y: rect.minY)
        case .topTrailing:
            CGPoint(x: rect.maxX, y: rect.minY)
        case .trailing:
            CGPoint(x: rect.maxX, y: rect.midY)
        case .bottomTrailing:
            CGPoint(x: rect.maxX, y: rect.maxY)
        case .bottom:
            CGPoint(x: rect.midX, y: rect.maxY)
        case .bottomLeading:
            CGPoint(x: rect.minX, y: rect.maxY)
        case .leading:
            CGPoint(x: rect.minX, y: rect.midY)
        }
    }

    var isCorner: Bool {
        switch self {
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return true
        case .top, .bottom, .leading, .trailing:
            return false
        }
    }

    var edgeCapsuleSize: CGSize? {
        switch self {
        case .top, .bottom:
            return CGSize(width: 26, height: 3.5)
        case .leading, .trailing:
            return CGSize(width: 3.5, height: 26)
        case .topLeading, .topTrailing, .bottomLeading, .bottomTrailing:
            return nil
        }
    }

    func resizedCrop(from crop: NormalizedCrop, deltaX: CGFloat, deltaY: CGFloat) -> NormalizedCrop {
        let minimumSize = 0.04
        var minX = crop.x
        var minY = crop.y
        var maxX = crop.x + crop.width
        var maxY = crop.y + crop.height

        switch self {
        case .topLeading:
            minX += deltaX
            minY += deltaY
        case .top:
            minY += deltaY
        case .topTrailing:
            maxX += deltaX
            minY += deltaY
        case .trailing:
            maxX += deltaX
        case .bottomTrailing:
            maxX += deltaX
            maxY += deltaY
        case .bottom:
            maxY += deltaY
        case .bottomLeading:
            minX += deltaX
            maxY += deltaY
        case .leading:
            minX += deltaX
        }

        minX = min(max(minX, 0), maxX - minimumSize)
        minY = min(max(minY, 0), maxY - minimumSize)
        maxX = max(min(maxX, 1), minX + minimumSize)
        maxY = max(min(maxY, 1), minY + minimumSize)

        return NormalizedCrop(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        ).clamped(minimumSize: minimumSize)
    }
}
