@preconcurrency import AVFoundation
import CoreGraphics
import Foundation

package struct NormalizedCrop: Equatable, Hashable, Sendable {
    package var x: CGFloat
    package var y: CGFloat
    package var width: CGFloat
    package var height: CGFloat

    package init(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    package static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)

    package var isFullFrame: Bool {
        abs(x) < 0.0001
            && abs(y) < 0.0001
            && abs(width - 1) < 0.0001
            && abs(height - 1) < 0.0001
    }

    package var displayLabel: String {
        "\(Int((width * 100).rounded()))% x \(Int((height * 100).rounded()))%"
    }

    package func rect(in size: CGSize) -> CGRect {
        CGRect(
            x: x * size.width,
            y: y * size.height,
            width: width * size.width,
            height: height * size.height
        )
    }

    package func pixelRect(in size: CGSize) -> CGRect {
        rect(in: size)
            .intersection(CGRect(origin: .zero, size: size))
            .integral
    }

    package func clamped(minimumSize: CGFloat = 0.04) -> NormalizedCrop {
        let nextWidth = min(max(width, minimumSize), 1)
        let nextHeight = min(max(height, minimumSize), 1)
        let nextX = min(max(x, 0), 1 - nextWidth)
        let nextY = min(max(y, 0), 1 - nextHeight)
        return NormalizedCrop(x: nextX, y: nextY, width: nextWidth, height: nextHeight)
    }

    package func resized(width nextWidth: CGFloat, height nextHeight: CGFloat) -> NormalizedCrop {
        let centerX = x + width / 2
        let centerY = y + height / 2
        return NormalizedCrop(
            x: centerX - nextWidth / 2,
            y: centerY - nextHeight / 2,
            width: nextWidth,
            height: nextHeight
        ).clamped()
    }

    package static func interpolated(from start: NormalizedCrop, to end: NormalizedCrop, progress: Double) -> NormalizedCrop {
        let clampedProgress = min(max(progress, 0), 1)
        let progress = CGFloat(clampedProgress)
        return NormalizedCrop(
            x: start.x + (end.x - start.x) * progress,
            y: start.y + (end.y - start.y) * progress,
            width: start.width + (end.width - start.width) * progress,
            height: start.height + (end.height - start.height) * progress
        ).clamped()
    }

    package static func centered(aspectRatio targetAspectRatio: CGFloat, naturalSize: CGSize) -> NormalizedCrop {
        guard targetAspectRatio > 0,
              naturalSize.width > 0,
              naturalSize.height > 0
        else {
            return .full
        }

        let mediaAspectRatio = naturalSize.width / naturalSize.height
        let normalizedAspectRatio = targetAspectRatio / mediaAspectRatio
        let size: CGSize

        if normalizedAspectRatio >= 1 {
            size = CGSize(width: 1, height: 1 / normalizedAspectRatio)
        } else {
            size = CGSize(width: normalizedAspectRatio, height: 1)
        }

        return NormalizedCrop(
            x: (1 - size.width) / 2,
            y: (1 - size.height) / 2,
            width: size.width,
            height: size.height
        ).clamped()
    }
}

package struct MediaTrim: Equatable, Hashable, Sendable {
    package var start: TimeInterval
    package var end: TimeInterval

    package static let minimumDuration: TimeInterval = 0.1

    package init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    package var duration: TimeInterval {
        max(0, end - start)
    }

    package var displayLabel: String {
        "\(Self.format(start))-\(Self.format(end))"
    }

    package func isFullLength(for totalDuration: TimeInterval?) -> Bool {
        guard let totalDuration, totalDuration > 0 else { return true }
        let trimmed = clamped(to: totalDuration)
        return trimmed.start <= 0.001 && abs(trimmed.end - totalDuration) <= 0.001
    }

    package func clamped(to totalDuration: TimeInterval) -> MediaTrim {
        guard totalDuration > 0 else {
            return MediaTrim(start: 0, end: 0)
        }

        let minimumDuration = min(Self.minimumDuration, totalDuration)
        let nextStart = min(max(start, 0), max(0, totalDuration - minimumDuration))
        let nextEnd = min(max(end, nextStart + minimumDuration), totalDuration)
        return MediaTrim(start: nextStart, end: nextEnd)
    }

    package func timeRange(in totalDuration: CMTime) -> CMTimeRange {
        let totalSeconds = CMTimeGetSeconds(totalDuration)
        let trimmed = clamped(to: totalSeconds)
        let startTime = CMTime(seconds: trimmed.start, preferredTimescale: 600)
        let durationTime = CMTime(seconds: trimmed.end - trimmed.start, preferredTimescale: 600)
        return CMTimeRange(start: startTime, duration: durationTime)
    }

    package static func full(duration: TimeInterval) -> MediaTrim {
        MediaTrim(start: 0, end: max(0, duration))
    }

    package static func format(_ time: TimeInterval) -> String {
        let totalCentiseconds = max(0, Int((time * 100).rounded()))
        let totalSeconds = totalCentiseconds / 100
        let centiseconds = totalCentiseconds % 100
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d:%02d", hours, minutes, seconds, centiseconds)
        }

        return String(format: "%02d:%02d:%02d", minutes, seconds, centiseconds)
    }
}

package struct TimelineCropKeyframe: Identifiable, Hashable, Sendable {
    package var id: UUID
    package var time: TimeInterval
    package var crop: NormalizedCrop

    package init(id: UUID = UUID(), time: TimeInterval, crop: NormalizedCrop) {
        self.id = id
        self.time = time
        self.crop = crop.clamped()
    }
}

package struct TimelineAdjustmentSpan: Identifiable, Hashable, Sendable {
    package var id: UUID
    package var start: TimeInterval
    package var end: TimeInterval
    package var keyframes: [TimelineCropKeyframe]

    package static let minimumDuration = MediaTrim.minimumDuration
    package static let keyframeMergeTolerance: TimeInterval = 0.05

    package init(
        id: UUID = UUID(),
        start: TimeInterval,
        end: TimeInterval,
        keyframes: [TimelineCropKeyframe]
    ) {
        self.id = id
        self.start = start
        self.end = end
        self.keyframes = keyframes
    }

    package var duration: TimeInterval {
        max(0, end - start)
    }

    package var sortedKeyframes: [TimelineCropKeyframe] {
        keyframes.sorted { lhs, rhs in
            if lhs.time == rhs.time {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.time < rhs.time
        }
    }

    package func contains(_ time: TimeInterval) -> Bool {
        time >= start && time <= end
    }

    package func normalized(to timelineDuration: TimeInterval) -> TimelineAdjustmentSpan {
        let timelineDuration = max(timelineDuration, 0)
        guard timelineDuration > 0 else {
            return TimelineAdjustmentSpan(id: id, start: 0, end: 0, keyframes: [])
        }

        let duration = min(max(self.duration, Self.minimumDuration), timelineDuration)
        let nextStart = min(max(start, 0), max(0, timelineDuration - duration))
        let nextEnd = min(max(nextStart + duration, nextStart), timelineDuration)
        let nextKeyframes = sortedKeyframes.map { keyframe in
            TimelineCropKeyframe(
                id: keyframe.id,
                time: min(max(keyframe.time, nextStart), nextEnd),
                crop: keyframe.crop
            )
        }

        return TimelineAdjustmentSpan(id: id, start: nextStart, end: nextEnd, keyframes: nextKeyframes)
    }

    package func crop(at time: TimeInterval) -> NormalizedCrop? {
        let keyframes = sortedKeyframes
        guard !keyframes.isEmpty else { return nil }

        let time = min(max(time, start), end)
        guard keyframes.count > 1 else {
            return keyframes[0].crop
        }

        if time <= keyframes[0].time {
            return keyframes[0].crop
        }

        if let last = keyframes.last, time >= last.time {
            return last.crop
        }

        for index in keyframes.indices.dropLast() {
            let left = keyframes[index]
            let right = keyframes[keyframes.index(after: index)]
            guard time >= left.time, time <= right.time else { continue }

            let duration = max(right.time - left.time, 0.000_001)
            return .interpolated(from: left.crop, to: right.crop, progress: (time - left.time) / duration)
        }

        return keyframes.last?.crop
    }

    package func upsertingKeyframe(
        at time: TimeInterval,
        crop: NormalizedCrop,
        tolerance: TimeInterval = Self.keyframeMergeTolerance
    ) -> TimelineAdjustmentSpan {
        let time = min(max(time, start), end)
        var next = self
        let crop = crop.clamped()

        if let nearestIndex = next.keyframes.indices.min(by: {
            abs(next.keyframes[$0].time - time) < abs(next.keyframes[$1].time - time)
        }),
           abs(next.keyframes[nearestIndex].time - time) <= tolerance {
            next.keyframes[nearestIndex].time = time
            next.keyframes[nearestIndex].crop = crop
        } else {
            next.keyframes.append(TimelineCropKeyframe(time: time, crop: crop))
        }

        next.keyframes.sort { $0.time < $1.time }
        return next
    }

    package func replacingCropSize(width: CGFloat, height: CGFloat) -> TimelineAdjustmentSpan {
        TimelineAdjustmentSpan(
            id: id,
            start: start,
            end: end,
            keyframes: keyframes.map { keyframe in
                TimelineCropKeyframe(
                    id: keyframe.id,
                    time: keyframe.time,
                    crop: keyframe.crop.resized(width: width, height: height)
                )
            }
        )
    }

    package static func clampedMoveRange(
        start: TimeInterval,
        end: TimeInterval,
        proposedStart: TimeInterval,
        timelineDuration: TimeInterval,
        occupiedRanges: [MediaTrim]
    ) -> MediaTrim {
        let timelineDuration = max(timelineDuration, 0)
        guard timelineDuration > 0 else {
            return MediaTrim(start: 0, end: 0)
        }

        let duration = min(max(end - start, Self.minimumDuration), timelineDuration)
        let gaps = availableGaps(in: timelineDuration, occupiedRanges: occupiedRanges)
            .filter { $0.duration >= duration }

        guard !gaps.isEmpty else {
            return MediaTrim(start: 0, end: min(duration, timelineDuration))
        }

        let best = gaps.min { lhs, rhs in
            let lhsStart = min(max(proposedStart, lhs.start), lhs.end - duration)
            let rhsStart = min(max(proposedStart, rhs.start), rhs.end - duration)
            return abs(lhsStart - proposedStart) < abs(rhsStart - proposedStart)
        } ?? gaps[0]
        let nextStart = min(max(proposedStart, best.start), best.end - duration)
        return MediaTrim(start: nextStart, end: nextStart + duration)
    }

    package static func clampedResizeStart(
        proposedStart: TimeInterval,
        fixedEnd: TimeInterval,
        timelineDuration: TimeInterval,
        occupiedRanges: [MediaTrim]
    ) -> TimeInterval {
        let previousEnd = occupiedRanges
            .filter { $0.end <= fixedEnd }
            .map(\.end)
            .max() ?? 0
        let latestStart = max(previousEnd, fixedEnd - Self.minimumDuration)
        return min(max(proposedStart, previousEnd), latestStart)
    }

    package static func clampedResizeEnd(
        fixedStart: TimeInterval,
        proposedEnd: TimeInterval,
        timelineDuration: TimeInterval,
        occupiedRanges: [MediaTrim]
    ) -> TimeInterval {
        let nextStart = occupiedRanges
            .filter { $0.start >= fixedStart }
            .map(\.start)
            .min() ?? max(timelineDuration, 0)
        let earliestEnd = fixedStart + Self.minimumDuration
        return max(min(proposedEnd, nextStart), earliestEnd)
    }

    private static func availableGaps(in timelineDuration: TimeInterval, occupiedRanges: [MediaTrim]) -> [MediaTrim] {
        let ranges = occupiedRanges
            .map { MediaTrim(start: min(max($0.start, 0), timelineDuration), end: min(max($0.end, 0), timelineDuration)) }
            .filter { $0.end - $0.start > 0 }
            .sorted { $0.start < $1.start }
        var gaps: [MediaTrim] = []
        var cursor = TimeInterval(0)

        for range in ranges {
            if range.start > cursor {
                gaps.append(MediaTrim(start: cursor, end: range.start))
            }
            cursor = max(cursor, range.end)
        }

        if cursor < timelineDuration {
            gaps.append(MediaTrim(start: cursor, end: timelineDuration))
        }

        return gaps
    }
}

package enum TimelineCropRenderer {
    package static func activeSpan(in spans: [TimelineAdjustmentSpan], at time: TimeInterval) -> TimelineAdjustmentSpan? {
        spans
            .sorted { $0.start < $1.start }
            .first { $0.contains(time) && !$0.keyframes.isEmpty }
    }

    package static func activeCrop(in spans: [TimelineAdjustmentSpan], at time: TimeInterval) -> NormalizedCrop? {
        activeSpan(in: spans, at: time)?.crop(at: time)
    }

    package static func outputCrop(in spans: [TimelineAdjustmentSpan]) -> NormalizedCrop? {
        spans
            .sorted { $0.start < $1.start }
            .lazy
            .compactMap { $0.sortedKeyframes.first?.crop }
            .first
    }

    package static func renderSize(displaySize: CGSize, adjustmentSpans: [TimelineAdjustmentSpan]) -> CGSize {
        guard let crop = outputCrop(in: adjustmentSpans),
              !crop.isFullFrame
        else {
            return displaySize
        }

        let cropRect = crop.rect(in: displaySize)
            .intersection(CGRect(origin: .zero, size: displaySize))
        guard cropRect.width > 1, cropRect.height > 1 else {
            return displaySize
        }

        return cropRect.size
    }

    package static func applyTransformRamps(
        to layerInstruction: AVMutableVideoCompositionLayerInstruction,
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval,
        displayTransform: CGAffineTransform,
        displaySize: CGSize,
        renderSize: CGSize,
        adjustmentSpans: [TimelineAdjustmentSpan]
    ) {
        let points = breakpoints(
            timelineStart: timelineStart,
            timelineEnd: timelineEnd,
            adjustmentSpans: adjustmentSpans
        )

        for index in points.indices.dropLast() {
            let start = points[index]
            let end = points[points.index(after: index)]
            guard end - start > 0.000_001 else { continue }

            let midpoint = (start + end) / 2
            let activeSpan = activeSpan(in: adjustmentSpans, at: midpoint)
            let startCrop = activeSpan?.crop(at: start)
            let endCrop = activeSpan?.crop(at: end)
            let startTransform = transform(
                displayTransform: displayTransform,
                displaySize: displaySize,
                renderSize: renderSize,
                crop: startCrop
            )
            let endTransform = transform(
                displayTransform: displayTransform,
                displaySize: displaySize,
                renderSize: renderSize,
                crop: endCrop
            )
            let timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                duration: CMTime(seconds: end - start, preferredTimescale: 600)
            )

            layerInstruction.setTransformRamp(
                fromStart: startTransform,
                toEnd: endTransform,
                timeRange: timeRange
            )
        }
    }

    package static func transform(
        displayTransform: CGAffineTransform,
        displaySize: CGSize,
        renderSize: CGSize,
        crop: NormalizedCrop?
    ) -> CGAffineTransform {
        guard let crop,
              !crop.isFullFrame
        else {
            return fittedTransform(
                displayTransform: displayTransform,
                displaySize: displaySize,
                renderSize: renderSize
            )
        }

        let cropRect = crop.rect(in: displaySize)
            .intersection(CGRect(origin: .zero, size: displaySize))
        guard cropRect.width > 1, cropRect.height > 1 else {
            return fittedTransform(
                displayTransform: displayTransform,
                displaySize: displaySize,
                renderSize: renderSize
            )
        }

        let scale = max(renderSize.width / max(cropRect.width, 1), renderSize.height / max(cropRect.height, 1))
        let scaledCropSize = CGSize(width: cropRect.width * scale, height: cropRect.height * scale)
        let center = CGAffineTransform(
            translationX: (renderSize.width - scaledCropSize.width) / 2,
            y: (renderSize.height - scaledCropSize.height) / 2
        )

        return displayTransform
            .concatenating(CGAffineTransform(translationX: -cropRect.minX, y: -cropRect.minY))
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(center)
    }

    private static func fittedTransform(
        displayTransform: CGAffineTransform,
        displaySize: CGSize,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let scale = min(renderSize.width / max(displaySize.width, 1), renderSize.height / max(displaySize.height, 1))
        let scaledSize = CGSize(width: displaySize.width * scale, height: displaySize.height * scale)
        let center = CGAffineTransform(
            translationX: (renderSize.width - scaledSize.width) / 2,
            y: (renderSize.height - scaledSize.height) / 2
        )
        return displayTransform
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(center)
    }

    private static func breakpoints(
        timelineStart: TimeInterval,
        timelineEnd: TimeInterval,
        adjustmentSpans: [TimelineAdjustmentSpan]
    ) -> [TimeInterval] {
        var points = [timelineStart, timelineEnd]

        for span in adjustmentSpans where span.end > timelineStart && span.start < timelineEnd {
            points.append(min(max(span.start, timelineStart), timelineEnd))
            points.append(min(max(span.end, timelineStart), timelineEnd))

            for keyframe in span.keyframes where keyframe.time > timelineStart && keyframe.time < timelineEnd {
                points.append(keyframe.time)
            }
        }

        return points
            .sorted()
            .reduce(into: [TimeInterval]()) { unique, point in
                if unique.last.map({ abs($0 - point) > 0.000_5 }) ?? true {
                    unique.append(point)
                }
            }
    }
}
