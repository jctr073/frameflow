import CoreGraphics
import MediaBrowserCore

@main
struct TimelineAdjustmentTestRunner {
    static func main() {
        testKeyframeUpsertUpdatesNearbyKeyframe()
        testKeyframeUpsertAddsDistantKeyframe()
        testCropInterpolationBetweenKeyframes()
        testMoveRangeClampsIntoNearestGap()
        testResizeClampsAgainstNeighbors()
        testSharedCropResizePreservesKeyframeCenters()
        testRenderSizeUsesAdjustmentCropAspect()
        print("Timeline adjustment logic tests passed.")
    }

    private static func testKeyframeUpsertUpdatesNearbyKeyframe() {
        let originalCrop = NormalizedCrop(x: 0.1, y: 0, width: 0.5, height: 1)
        let updatedCrop = NormalizedCrop(x: 0.35, y: 0, width: 0.5, height: 1)
        let span = TimelineAdjustmentSpan(
            start: 0,
            end: 10,
            keyframes: [TimelineCropKeyframe(time: 2, crop: originalCrop)]
        )

        let updated = span.upsertingKeyframe(at: 2.03, crop: updatedCrop)

        expect(updated.keyframes.count == 1, "nearby upsert should update instead of adding")
        expect(approximatelyEqual(updated.keyframes[0].time, 2.03), "nearby upsert should move keyframe time")
        expect(updated.keyframes[0].crop == updatedCrop, "nearby upsert should update crop")
    }

    private static func testKeyframeUpsertAddsDistantKeyframe() {
        let firstCrop = NormalizedCrop(x: 0.1, y: 0, width: 0.5, height: 1)
        let secondCrop = NormalizedCrop(x: 0.4, y: 0, width: 0.5, height: 1)
        let span = TimelineAdjustmentSpan(
            start: 0,
            end: 10,
            keyframes: [TimelineCropKeyframe(time: 2, crop: firstCrop)]
        )

        let updated = span.upsertingKeyframe(at: 4, crop: secondCrop)

        expect(updated.keyframes.count == 2, "distant upsert should add a keyframe")
        expect(updated.sortedKeyframes.map(\.time) == [2, 4], "keyframes should stay sorted by time")
    }

    private static func testCropInterpolationBetweenKeyframes() {
        let span = TimelineAdjustmentSpan(
            start: 0,
            end: 10,
            keyframes: [
                TimelineCropKeyframe(time: 0, crop: NormalizedCrop(x: 0, y: 0, width: 0.5, height: 1)),
                TimelineCropKeyframe(time: 10, crop: NormalizedCrop(x: 0.5, y: 0, width: 0.5, height: 1))
            ]
        )

        let midpointCrop = span.crop(at: 5)

        expect(approximatelyEqual(midpointCrop?.x ?? -1, 0.25), "crop x should interpolate")
        expect(approximatelyEqual(midpointCrop?.width ?? -1, 0.5), "crop width should remain fixed")
    }

    private static func testMoveRangeClampsIntoNearestGap() {
        let range = TimelineAdjustmentSpan.clampedMoveRange(
            start: 20,
            end: 25,
            proposedStart: 4,
            timelineDuration: 30,
            occupiedRanges: [
                MediaTrim(start: 0, end: 5),
                MediaTrim(start: 10, end: 15)
            ]
        )

        expect(approximatelyEqual(range.start, 5), "move should clamp to nearest available gap start")
        expect(approximatelyEqual(range.end, 10), "move should preserve duration in the gap")
    }

    private static func testResizeClampsAgainstNeighbors() {
        let start = TimelineAdjustmentSpan.clampedResizeStart(
            proposedStart: 4,
            fixedEnd: 12,
            timelineDuration: 20,
            occupiedRanges: [MediaTrim(start: 0, end: 6)]
        )
        let end = TimelineAdjustmentSpan.clampedResizeEnd(
            fixedStart: 8,
            proposedEnd: 16,
            timelineDuration: 20,
            occupiedRanges: [MediaTrim(start: 14, end: 18)]
        )

        expect(approximatelyEqual(start, 6), "resize start should clamp after previous span")
        expect(approximatelyEqual(end, 14), "resize end should clamp before next span")
    }

    private static func testSharedCropResizePreservesKeyframeCenters() {
        let span = TimelineAdjustmentSpan(
            start: 0,
            end: 10,
            keyframes: [
                TimelineCropKeyframe(time: 0, crop: NormalizedCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
            ]
        )

        let resized = span.replacingCropSize(width: 0.25, height: 0.25)
        let crop = resized.keyframes[0].crop

        expect(approximatelyEqual(crop.x + crop.width / 2, 0.5), "resized crop should preserve x center")
        expect(approximatelyEqual(crop.y + crop.height / 2, 0.5), "resized crop should preserve y center")
        expect(approximatelyEqual(crop.width, 0.25), "resized crop should update width")
        expect(approximatelyEqual(crop.height, 0.25), "resized crop should update height")
    }

    private static func testRenderSizeUsesAdjustmentCropAspect() {
        let span = TimelineAdjustmentSpan(
            start: 0,
            end: 10,
            keyframes: [
                TimelineCropKeyframe(time: 0, crop: NormalizedCrop(x: 0.25, y: 0, width: 0.5, height: 1))
            ]
        )

        let renderSize = TimelineCropRenderer.renderSize(
            displaySize: CGSize(width: 1920, height: 1080),
            adjustmentSpans: [span]
        )

        expect(approximatelyEqual(renderSize.width, 960), "render width should follow crop window")
        expect(approximatelyEqual(renderSize.height, 1080), "render height should follow crop window")
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 0.0001) -> Bool {
        abs(lhs - rhs) < tolerance
    }

    private static func approximatelyEqual(_ lhs: CGFloat, _ rhs: CGFloat, tolerance: CGFloat = 0.0001) -> Bool {
        abs(lhs - rhs) < tolerance
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else {
            fatalError(message)
        }
    }
}
