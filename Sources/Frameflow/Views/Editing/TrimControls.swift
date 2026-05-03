import FrameflowCore
import SwiftUI

struct TrimControls: View {
    @Binding var trim: MediaTrim
    let duration: TimeInterval
    let onApply: () -> Void

    @State private var startText = ""
    @State private var endText = ""
    @FocusState private var focusedField: TimeField?

    var body: some View {
        HStack(spacing: 6) {
            TrimRangeSlider(trim: $trim, duration: duration)
                .frame(width: 150, height: 24)
                .quickTooltip("Drag to Set Trim Start and End")
                .accessibilityLabel("Trim Range")

            TextField("Start", text: $startText)
                .font(.caption.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .focused($focusedField, equals: .start)
                .onSubmit(commitTextFields)
                .onChange(of: startText) {
                    commitTextField(.start)
                }
                .quickTooltip("Trim Start Time (MM:SS:CC)")
                .accessibilityLabel("Trim Start Time")

            TextField("End", text: $endText)
                .font(.caption.monospacedDigit())
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .focused($focusedField, equals: .end)
                .onSubmit(commitTextFields)
                .onChange(of: endText) {
                    commitTextField(.end)
                }
                .quickTooltip("Trim End Time (MM:SS:CC)")
                .accessibilityLabel("Trim End Time")

            Button {
                commitTextFields()
                onApply()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(trim.isFullLength(for: duration))
            .quickTooltip("Apply Trim")
            .accessibilityLabel("Apply Trim")
        }
        .onAppear(perform: syncTextFields)
        .onChange(of: trim) {
            syncTextFields()
        }
        .onChange(of: duration) {
            trim = trim.clamped(to: duration)
            syncTextFields()
        }
    }

    private func syncTextFields() {
        let clamped = trim.clamped(to: duration)
        if focusedField != .start {
            startText = MediaTrim.format(clamped.start)
        }
        if focusedField != .end {
            endText = MediaTrim.format(clamped.end)
        }
    }

    private func commitTextFields() {
        let current = trim.clamped(to: duration)
        let nextStart = parseTime(startText) ?? current.start
        let nextEnd = parseTime(endText) ?? current.end
        trim = MediaTrim(start: nextStart, end: nextEnd).clamped(to: duration)
        focusedField = nil
        syncTextFields()
    }

    private func commitTextField(_ field: TimeField) {
        guard focusedField == field else { return }

        let current = trim.clamped(to: duration)
        switch field {
        case .start:
            guard let nextStart = parseTime(startText) else { return }
            trim = MediaTrim(start: nextStart, end: current.end).clamped(to: duration)
        case .end:
            guard let nextEnd = parseTime(endText) else { return }
            trim = MediaTrim(start: current.start, end: nextEnd).clamped(to: duration)
        }
    }

    private func parseTime(_ text: String) -> TimeInterval? {
        let parts = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)

        guard !parts.isEmpty,
              parts.allSatisfy({ !$0.isEmpty })
        else { return nil }
        if parts.count == 1 {
            return TimeInterval(parts[0])
        }
        if parts.count == 2,
           let minutes = TimeInterval(parts[0]),
           let seconds = TimeInterval(parts[1]) {
            return minutes * 60 + seconds
        }
        if parts.count == 3,
           let minutes = TimeInterval(parts[0]),
           let seconds = TimeInterval(parts[1]),
           let centiseconds = TimeInterval(parts[2]) {
            return minutes * 60 + seconds + centiseconds / 100
        }
        if parts.count == 4,
           let hours = TimeInterval(parts[0]),
           let minutes = TimeInterval(parts[1]),
           let seconds = TimeInterval(parts[2]),
           let centiseconds = TimeInterval(parts[3]) {
            return hours * 3600 + minutes * 60 + seconds + centiseconds / 100
        }
        return nil
    }

    private enum TimeField: Hashable {
        case start
        case end
    }
}

private struct TrimRangeSlider: View {
    @Environment(\.editorTheme) private var theme
    @Binding var trim: MediaTrim
    let duration: TimeInterval

    @State private var activeHandle: TrimHandle?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let handleSize: CGFloat = 12
            let trackWidth = max(size.width - handleSize, 1)
            let clamped = trim.clamped(to: duration)
            let startX = xPosition(for: clamped.start, width: trackWidth, handleSize: handleSize)
            let endX = xPosition(for: clamped.end, width: trackWidth, handleSize: handleSize)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.28))
                    .frame(height: 4)
                    .position(x: size.width / 2, y: size.height / 2)

                Capsule()
                    .fill(theme.accent.opacity(0.82))
                    .frame(width: max(endX - startX, 2), height: 4)
                    .position(x: (startX + endX) / 2, y: size.height / 2)

                Circle()
                    .fill(activeHandle == .start ? theme.accent : theme.panelRaised)
                    .stroke(theme.accent, lineWidth: 1.5)
                    .frame(width: handleSize, height: handleSize)
                    .position(x: startX, y: size.height / 2)

                Circle()
                    .fill(activeHandle == .end ? theme.accent : theme.panelRaised)
                    .stroke(theme.accent, lineWidth: 1.5)
                    .frame(width: handleSize, height: handleSize)
                    .position(x: endX, y: size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let seconds = seconds(for: value.location.x, width: trackWidth, handleSize: handleSize)
                        if activeHandle == nil {
                            activeHandle = abs(seconds - clamped.start) <= abs(seconds - clamped.end) ? .start : .end
                        }

                        switch activeHandle {
                        case .start:
                            trim = MediaTrim(start: seconds, end: clamped.end).clamped(to: duration)
                        case .end:
                            trim = MediaTrim(start: clamped.start, end: seconds).clamped(to: duration)
                        case nil:
                            break
                        }
                    }
                    .onEnded { _ in
                        activeHandle = nil
                    }
            )
        }
    }

    private func xPosition(for seconds: TimeInterval, width: CGFloat, handleSize: CGFloat) -> CGFloat {
        let percent = duration > 0 ? min(max(seconds / duration, 0), 1) : 0
        return handleSize / 2 + CGFloat(percent) * width
    }

    private func seconds(for xPosition: CGFloat, width: CGFloat, handleSize: CGFloat) -> TimeInterval {
        let percent = min(max((xPosition - handleSize / 2) / width, 0), 1)
        return TimeInterval(percent) * duration
    }

    private enum TrimHandle {
        case start
        case end
    }
}
