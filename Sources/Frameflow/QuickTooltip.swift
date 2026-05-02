import SwiftUI

enum QuickTooltipPlacement {
    case above
    case below
}

struct QuickTooltipItem {
    let text: String
    let placement: QuickTooltipPlacement
    let anchor: Anchor<CGRect>
}

struct QuickTooltipPreferenceKey: PreferenceKey {
    static let defaultValue: [QuickTooltipItem] = []

    static func reduce(value: inout [QuickTooltipItem], nextValue: () -> [QuickTooltipItem]) {
        value.append(contentsOf: nextValue())
    }
}

struct QuickTooltipModifier: ViewModifier {
    let text: String
    var delay: Duration = .milliseconds(120)
    var placement: QuickTooltipPlacement = .below

    @State private var isVisible = false
    @State private var hoverTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .anchorPreference(key: QuickTooltipPreferenceKey.self, value: .bounds) { anchor in
                guard isVisible else { return [] }
                return [QuickTooltipItem(text: text, placement: placement, anchor: anchor)]
            }
            .onHover { isHovering in
                hoverTask?.cancel()

                if isHovering {
                    hoverTask = Task { @MainActor in
                        try? await Task.sleep(for: delay)
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.08)) {
                            isVisible = true
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.06)) {
                        isVisible = false
                    }
                }
            }
    }
}

struct QuickTooltipOverlayModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(QuickTooltipPreferenceKey.self) { items in
                GeometryReader { geometry in
                    if let item = items.last {
                        let rect = geometry[item.anchor]
                        QuickTooltipBubble(text: item.text)
                            .position(
                                x: rect.midX,
                                y: item.placement == .above ? rect.minY - 22 : rect.maxY + 22
                            )
                            .transition(.opacity.combined(with: .scale(scale: 0.96)))
                            .zIndex(10_000)
                    }
                }
                .allowsHitTesting(false)
            }
    }
}

private struct QuickTooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.86), in: RoundedRectangle(cornerRadius: 5))
    }
}

extension View {
    func quickTooltip(
        _ text: String,
        delay: Duration = .milliseconds(120),
        placement: QuickTooltipPlacement = .below
    ) -> some View {
        modifier(QuickTooltipModifier(text: text, delay: delay, placement: placement))
    }

    func quickTooltipOverlay() -> some View {
        modifier(QuickTooltipOverlayModifier())
    }
}
