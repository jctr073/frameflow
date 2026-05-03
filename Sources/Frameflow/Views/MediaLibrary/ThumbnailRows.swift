import AppKit
import SwiftUI

struct ThumbnailRow: View {
    @Environment(\.editorTheme) private var theme
    let item: MediaItem
    let thumbnail: NSImage?
    var isEdited = false
    var depth = 0

    private let cardWidth: CGFloat = 134
    private let thumbnailHeight: CGFloat = 78
    private let labelHeight: CGFloat = 22
    private let cornerRadius: CGFloat = 4

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
                .frame(width: cardWidth, height: thumbnailHeight)
                .background(theme.thumbnailWell)
                .clipped()

                Text(item.kind.label)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.72), in: Capsule())
                    .padding(3)
            }
            .overlay(alignment: .topLeading) {
                if isEdited {
                    Image(systemName: "crop")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(theme.accent, in: Circle())
                        .padding(3)
                }
            }

            Text(item.fileName)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 6)
                .frame(width: cardWidth, height: labelHeight, alignment: .leading)
                .background(theme.clipBlue)
        }
        .frame(width: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
        }
        .padding(.leading, CGFloat(depth) * 14)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

struct FolderRow: View {
    @Environment(\.editorTheme) private var theme
    let entry: FolderPanelEntry

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: entry.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.mutedText)
                .frame(width: 12)

            Image(systemName: entry.isExpanded ? "folder.fill" : "folder")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.secondaryText)
                .frame(width: 24)

            Text(entry.folder.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 4)

            if entry.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(.leading, CGFloat(entry.depth) * 18)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
