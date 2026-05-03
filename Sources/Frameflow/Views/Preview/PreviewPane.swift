import AppKit
import FrameflowCore
import SwiftUI

struct PreviewPane: View {
    @Environment(\.editorTheme) private var theme
    let item: MediaItem
    let zoomMultiplier: Double
    let fillsFrame: Bool
    let isCropToolActive: Bool
    let appliedCrop: NormalizedCrop
    let appliedTrim: MediaTrim?
    let playbackToggleRequest: PlaybackToggleRequest?
    let onApplyCrop: () -> Void
    let onVideoTimeChange: (TimeInterval) -> Void
    @Binding var crop: NormalizedCrop

    @State private var naturalSize: CGSize?
    @State private var failedToLoad = false

    var body: some View {
        GeometryReader { geometry in
            if failedToLoad {
                Text("This file could not be loaded.")
                    .font(.title3)
                    .foregroundStyle(theme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let naturalSize, naturalSize.width > 0, naturalSize.height > 0 {
                fittedMedia(in: geometry.size, naturalSize: naturalSize)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.id) {
            naturalSize = nil
            failedToLoad = false
            if let size = await MediaSizing.naturalSize(for: item) {
                naturalSize = size
            } else {
                failedToLoad = true
            }
        }
    }

    private func fittedMedia(in containerSize: CGSize, naturalSize: CGSize) -> some View {
        let displayCrop = isCropToolActive ? NormalizedCrop.full : appliedCrop
        let sourceRect = displayCrop.pixelRect(in: naturalSize)
        let displayNaturalSize = displayCrop.isFullFrame ? naturalSize : sourceRect.size
        let widthFitScale = containerSize.width / displayNaturalSize.width
        let heightFitScale = containerSize.height / displayNaturalSize.height
        let baseFitScale = fillsFrame
            ? max(widthFitScale, heightFitScale)
            : min(widthFitScale, heightFitScale)
        let fitScale = item.kind.shouldUpscaleToFit ? baseFitScale : min(baseFitScale, 1.0)
        let scale = max(0.08, fitScale * zoomMultiplier)
        let mediaSize = CGSize(width: displayNaturalSize.width * scale, height: displayNaturalSize.height * scale)
        let contentSize = CGSize(
            width: max(containerSize.width, mediaSize.width),
            height: max(containerSize.height, mediaSize.height)
        )

        return ScrollView([.horizontal, .vertical]) {
            ZStack {
                if item.kind == .video, !isCropToolActive {
                    NativeVideoView(
                        url: item.url,
                        crop: displayCrop,
                        displaySize: naturalSize,
                        trim: appliedTrim,
                        playbackToggleRequest: playbackToggleRequest,
                        onTimeChange: onVideoTimeChange
                    )
                    .frame(width: mediaSize.width, height: mediaSize.height)
                } else {
                    viewportedMediaView(sourceRect: sourceRect, naturalSize: naturalSize, scale: scale)
                        .frame(width: mediaSize.width, height: mediaSize.height)
                }

                if isCropToolActive {
                    CropOverlay(crop: $crop, isEditable: isCropToolActive, onApply: onApplyCrop)
                        .frame(width: mediaSize.width, height: mediaSize.height)
                }
            }
            .frame(width: contentSize.width, height: contentSize.height)
        }
        .defaultScrollAnchor(.center)
    }

    @ViewBuilder
    private var mediaView: some View {
        switch item.kind {
        case .image:
            StaticImagePreview(url: item.url)
        case .gif:
            NativeGIFImageView(url: item.url, trim: appliedTrim)
        case .webp:
            NativeWebImageView(url: item.url)
        case .video:
            NativeVideoView(
                url: item.url,
                crop: .full,
                displaySize: nil,
                trim: appliedTrim,
                onTimeChange: onVideoTimeChange
            )
        }
    }

    private func viewportedMediaView(sourceRect: CGRect, naturalSize: CGSize, scale: CGFloat) -> some View {
        mediaView
            .frame(width: naturalSize.width * scale, height: naturalSize.height * scale)
            .offset(x: -sourceRect.minX * scale, y: -sourceRect.minY * scale)
            .frame(width: sourceRect.width * scale, height: sourceRect.height * scale, alignment: .topLeading)
            .clipped()
    }
}
