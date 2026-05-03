import AppKit
import FrameflowCore
import SwiftUI

struct EditorClipCard: View {
    @Environment(\.editorTheme) private var theme
    let clip: EditorClip
    let thumbnail: NSImage?
    let isSelected: Bool

    private let cornerRadius: CGFloat = 4
    private let labelHeight: CGFloat = 22
    private let selectionOutlineColor = Color(red: 0.86, green: 0.42, blue: 0.08)

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                Group {
                    if let thumbnail {
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(height: 64)
                .frame(maxWidth: .infinity)
                .background(theme.thumbnailWell)
                .clipped()

                Text(durationBadge)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(4)
            }

            Text(clip.item.fileName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: labelHeight)
                .background(isSelected ? theme.clipBlueSelected : theme.clipBlue)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    isSelected ? selectionOutlineColor : Color.white.opacity(0.18),
                    lineWidth: isSelected ? 2 : 1
                )
        }
    }

    private var durationBadge: String {
        if let duration = clip.status?.duration {
            return MediaTrim.format(duration)
        }
        return clip.item.kind.label
    }
}
