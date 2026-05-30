@preconcurrency import AppKit
import AVKit
import FrameflowCore
import SwiftUI

struct NativeVideoView: View {
    let url: URL
    var crop = NormalizedCrop.full
    var displaySize: CGSize?
    var trim: MediaTrim?
    var playbackToggleRequest: PlaybackToggleRequest?
    var onTimeChange: (TimeInterval) -> Void = { _ in }

    @StateObject private var controller = NativeVideoController()

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black

            NativeVideoSurface(player: controller.player, fillsFrame: false)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            NativeVideoControls(controller: controller)
        }
        .onAppear(perform: loadVideo)
        .onDisappear {
            controller.stop()
        }
        .onChange(of: url) {
            loadVideo()
        }
        .onChange(of: crop) {
            loadVideo()
        }
        .onChange(of: displaySize) {
            loadVideo()
        }
        .onChange(of: trim) {
            loadVideo()
        }
        .onChange(of: playbackToggleRequest) {
            guard playbackToggleRequest != nil else { return }
            controller.togglePlayback()
        }
        .onChange(of: controller.currentTime) {
            onTimeChange(controller.currentTime)
        }
    }

    private func loadVideo() {
        controller.play(url, crop: crop, displaySize: displaySize, trim: trim)
    }
}

private struct NativeVideoControls: View {
    @Environment(\.editorTheme) private var theme
    @ObservedObject var controller: NativeVideoController

    var body: some View {
        HStack(spacing: 6) {
            Button {
                controller.skip(by: -15)
            } label: {
                Image(systemName: "gobackward.15")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.primaryText)
            .quickTooltip("Back 15 Seconds", placement: .above)
            .accessibilityLabel("Back 15 Seconds")

            Button {
                controller.togglePlayback()
            } label: {
                Image(systemName: controller.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.primaryText)
            .quickTooltip(controller.isPlaying ? "Pause Video" : "Play Video", placement: .above)
            .accessibilityLabel(controller.isPlaying ? "Pause Video" : "Play Video")

            Button {
                controller.skip(by: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.primaryText)
            .quickTooltip("Forward 15 Seconds", placement: .above)
            .accessibilityLabel("Forward 15 Seconds")

            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            Text(MediaTrim.format(controller.currentTime))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .quickTooltip("Current Video Time", placement: .above)
                .accessibilityLabel("Current Video Time")

            Slider(
                value: Binding(
                    get: { controller.sliderTime },
                    set: { controller.seek(to: $0) }
                ),
                in: controller.seekRange
            )
            .controlSize(.small)
            .frame(minWidth: 120, maxWidth: .infinity)
            .quickTooltip("Seek Video", placement: .above)
            .accessibilityLabel("Seek Video")

            Text(MediaTrim.format(controller.playbackEnd))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .quickTooltip("Video End Time", placement: .above)
                .accessibilityLabel("Video End Time")

            Rectangle()
                .fill(theme.hairline)
                .frame(width: 1, height: 16)
                .padding(.horizontal, 2)

            Toggle(isOn: $controller.loop) {
                Text("Loop")
                    .font(.system(size: 11, weight: .medium))
            }
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .foregroundStyle(theme.secondaryText)
            .fixedSize()
            .quickTooltip("Loop Playback", placement: .above)
            .accessibilityLabel("Loop Playback")
        }
        .frame(height: 28)
        .padding(.horizontal, 10)
        .background(theme.toolbarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(theme.hairline)
                .frame(height: 1)
        }
    }
}

@MainActor
private final class NativeVideoController: ObservableObject {
    static let loopDefaultsKey = "videoPlayerLoop"

    let player = AVPlayer()

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var loop: Bool = UserDefaults.standard.object(forKey: NativeVideoController.loopDefaultsKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(loop, forKey: NativeVideoController.loopDefaultsKey)
        }
    }

    private var url: URL?
    private var crop = NormalizedCrop.full
    private var displaySize: CGSize?
    private var trim: MediaTrim?
    private var loadTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var boundaryObserver: Any?
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?

    var playbackStart: TimeInterval {
        trim?.start ?? 0
    }

    var playbackEnd: TimeInterval {
        trim?.end ?? duration
    }

    var sliderTime: TimeInterval {
        min(max(currentTime, seekRange.lowerBound), seekRange.upperBound)
    }

    var seekRange: ClosedRange<TimeInterval> {
        let lowerBound = playbackStart
        let upperBound = max(lowerBound + 0.01, playbackEnd)
        return lowerBound...upperBound
    }

    init() {
        installTimeObserverIfNeeded()

        timeControlObservation = player.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
            }
        }
    }

    deinit {
        loadTask?.cancel()
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    func play(_ url: URL, crop: NormalizedCrop, displaySize: CGSize?, trim: MediaTrim?) {
        installTimeObserverIfNeeded()

        guard sourceNeedsUpdate(url: url, crop: crop, displaySize: displaySize) else {
            if self.trim != trim {
                applyTrim(trim, seekToStart: true)
            }
            if let trim, boundaryObserver == nil {
                installBoundaryObserver(end: trim.end)
            }
            player.play()
            return
        }

        self.url = url
        self.crop = crop
        self.displaySize = displaySize
        self.trim = trim

        loadTask?.cancel()
        removeEndObserver()
        removeBoundaryObserver()
        let player = player
        loadTask = Task { @MainActor in
            let result = await Self.playerItem(url: url, crop: crop, displaySize: displaySize)
            guard !Task.isCancelled else { return }
            duration = result.duration
            player.replaceCurrentItem(with: result.item)
            installEndObserver(for: result.item)
            let start = trim?.start ?? 0
            currentTime = start
            let startTime = CMTime(seconds: start, preferredTimescale: 600)
            await player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
            if let trim {
                installBoundaryObserver(end: trim.end)
            }
            player.play()
        }
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.01, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self.currentTime = seconds
            }
        }
    }

    func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= playbackEnd - 0.01 {
                seek(to: playbackStart)
            }
            player.play()
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: TimeInterval) {
        let clampedSeconds = min(max(seconds, seekRange.lowerBound), seekRange.upperBound)
        currentTime = clampedSeconds
        let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        loadTask?.cancel()
        removeEndObserver()
        removeBoundaryObserver()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    private func sourceNeedsUpdate(url: URL, crop: NormalizedCrop, displaySize: CGSize?) -> Bool {
        self.url != url
            || self.crop != crop
            || self.displaySize != displaySize
    }

    private func applyTrim(_ trim: MediaTrim?, seekToStart: Bool) {
        self.trim = trim
        removeBoundaryObserver()

        if let trim {
            installBoundaryObserver(end: trim.end)
            if seekToStart {
                seek(to: trim.start)
            } else if currentTime < trim.start || currentTime > trim.end {
                seek(to: min(max(currentTime, trim.start), trim.end))
            }
        } else if seekToStart {
            seek(to: 0)
        }
    }

    @MainActor
    private static func playerItem(url: URL, crop: NormalizedCrop, displaySize: CGSize?) async -> (item: AVPlayerItem, duration: TimeInterval) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let duration = await duration(for: asset)
        guard !crop.isFullFrame,
              let displaySize,
              let videoComposition = await videoComposition(for: asset, crop: crop, displaySize: displaySize)
        else {
            return (item, duration)
        }

        item.videoComposition = videoComposition
        return (item, duration)
    }

    private static func duration(for asset: AVURLAsset) async -> TimeInterval {
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite ? max(0, seconds) : 0
        } catch {
            return 0
        }
    }

    private static func videoComposition(
        for asset: AVURLAsset,
        crop: NormalizedCrop,
        displaySize: CGSize
    ) async -> AVMutableVideoComposition? {
        do {
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return nil
            }

            let duration = try await asset.load(.duration)
            let naturalSize = try await track.load(.naturalSize)
            let preferredTransform = try await track.load(.preferredTransform)
            let transformedBounds = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
                .standardized
            let cropRect = crop.pixelRect(in: displaySize)
            guard cropRect.width > 1, cropRect.height > 1 else {
                return nil
            }

            let frameRate = try await track.load(.nominalFrameRate)
            let videoComposition = AVMutableVideoComposition()
            videoComposition.renderSize = CGSize(
                width: max(2, floor(cropRect.width / 2) * 2),
                height: max(2, floor(cropRect.height / 2) * 2)
            )
            videoComposition.frameDuration = CMTime(
                value: 1,
                timescale: CMTimeScale(max(frameRate.rounded(), 24))
            )

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: .zero, duration: duration)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
            let translation = CGAffineTransform(
                translationX: -transformedBounds.minX - cropRect.minX,
                y: -transformedBounds.minY - cropRect.minY
            )
            layerInstruction.setTransform(preferredTransform.concatenating(translation), at: .zero)
            instruction.layerInstructions = [layerInstruction]
            videoComposition.instructions = [instruction]

            return videoComposition
        } catch {
            return nil
        }
    }

    @MainActor
    private func installBoundaryObserver(end: TimeInterval) {
        removeBoundaryObserver()
        let endTime = CMTime(seconds: end, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                if self.loop {
                    self.seek(to: self.playbackStart)
                    self.player.play()
                } else {
                    self.currentTime = end
                    self.player.pause()
                }
            }
        }
    }

    @MainActor
    private func removeBoundaryObserver() {
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
    }

    @MainActor
    private func installEndObserver(for item: AVPlayerItem) {
        removeEndObserver()
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.loop {
                    self.seek(to: self.playbackStart)
                    self.player.play()
                } else {
                    self.currentTime = self.playbackEnd
                    self.player.pause()
                }
            }
        }
    }

    @MainActor
    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }
}
