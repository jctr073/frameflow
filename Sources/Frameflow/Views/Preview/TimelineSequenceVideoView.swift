@preconcurrency import AppKit
import AVKit
import FrameflowCore
import SwiftUI

struct TimelinePlaybackClip: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let trim: MediaTrim?
    let volume: Float
}

struct TimelinePlaybackSeekRequest: Equatable {
    let id = UUID()
    let time: TimeInterval
}

struct PlaybackToggleRequest: Equatable {
    let id = UUID()
}

struct TimelinePlaybackPosition: Equatable {
    let timelineTime: TimeInterval
    let clipID: UUID?
    let sourceTime: TimeInterval
}

struct TimelineSequenceVideoView: View {
    @Environment(\.editorTheme) private var theme
    let clips: [TimelinePlaybackClip]
    let zoomMultiplier: Double
    let fillsFrame: Bool
    let seekRequest: TimelinePlaybackSeekRequest?
    let playbackToggleRequest: PlaybackToggleRequest?
    let onPlaybackPositionChange: (TimelinePlaybackPosition) -> Void

    @StateObject private var controller = TimelineSequenceVideoController()

    var body: some View {
        ZStack(alignment: .bottom) {
            ZoomableNativeVideoSurface(
                player: controller.player,
                zoomMultiplier: zoomMultiplier,
                fillsFrame: fillsFrame
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if controller.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if clips.isEmpty || controller.duration <= 0 {
                Text("No playable video clips.")
                    .font(.title3)
                    .foregroundStyle(theme.playbackSecondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            TimelineSequenceVideoControls(controller: controller)
        }
        .onAppear {
            controller.load(clips, seekTime: seekRequest?.time)
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: clips) {
            controller.load(clips)
        }
        .onChange(of: seekRequest) {
            guard let seekRequest else { return }
            controller.seek(to: seekRequest.time)
        }
        .onChange(of: playbackToggleRequest) {
            guard playbackToggleRequest != nil else { return }
            controller.togglePlayback()
        }
        .onChange(of: controller.position) {
            onPlaybackPositionChange(controller.position)
        }
    }
}

private struct TimelineSequenceVideoControls: View {
    @Environment(\.editorTheme) private var theme
    @ObservedObject var controller: TimelineSequenceVideoController

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
            .disabled(controller.duration <= 0)
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
            .disabled(controller.duration <= 0)
            .quickTooltip(controller.isPlaying ? "Pause Timeline" : "Play Timeline", placement: .above)
            .accessibilityLabel(controller.isPlaying ? "Pause Timeline" : "Play Timeline")

            Button {
                controller.skip(by: 15)
            } label: {
                Image(systemName: "goforward.15")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(theme.primaryText)
            .disabled(controller.duration <= 0)
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
                .quickTooltip("Current Timeline Time", placement: .above)
                .accessibilityLabel("Current Timeline Time")

            Slider(
                value: Binding(
                    get: { controller.sliderTime },
                    set: { controller.seek(to: $0) }
                ),
                in: controller.seekRange
            )
            .controlSize(.small)
            .disabled(controller.duration <= 0)
            .frame(minWidth: 120, maxWidth: .infinity)
            .quickTooltip("Seek Timeline", placement: .above)
            .accessibilityLabel("Seek Timeline")

            Text(MediaTrim.format(controller.duration))
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.secondaryText)
                .lineLimit(1)
                .quickTooltip("Timeline Duration", placement: .above)
                .accessibilityLabel("Timeline Duration")

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
private final class TimelineSequenceVideoController: ObservableObject {
    static let loopDefaultsKey = "videoPlayerLoop"

    let player = AVPlayer()

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isLoading = false
    @Published var loop: Bool = UserDefaults.standard.object(forKey: TimelineSequenceVideoController.loopDefaultsKey) as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(loop, forKey: TimelineSequenceVideoController.loopDefaultsKey)
        }
    }
    @Published var position = TimelinePlaybackPosition(timelineTime: 0, clipID: nil, sourceTime: 0)

    private var clips: [TimelinePlaybackClip] = []
    private var ranges: [TimelinePlaybackRange] = []
    private var loadTask: Task<Void, Never>?
    private var endObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var timeControlObservation: NSKeyValueObservation?
    private var pendingSeekTime: TimeInterval?

    var sliderTime: TimeInterval {
        min(max(currentTime, seekRange.lowerBound), seekRange.upperBound)
    }

    var seekRange: ClosedRange<TimeInterval> {
        0...max(duration, 0.01)
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

    func load(
        _ clips: [TimelinePlaybackClip],
        seekTime: TimeInterval? = nil
    ) {
        installTimeObserverIfNeeded()

        guard clips != self.clips else {
            return
        }

        let resumePlayback = isPlaying
        let requestedTime = seekTime ?? min(currentTime, duration)
        pendingSeekTime = seekTime
        self.clips = clips
        loadTask?.cancel()
        removeEndObserver()

        guard !clips.isEmpty else {
            isLoading = false
            pendingSeekTime = nil
            ranges = []
            duration = 0
            updatePosition(to: 0)
            player.replaceCurrentItem(with: nil)
            return
        }

        isLoading = true
        loadTask = Task { @MainActor in
            do {
                let result = try await Self.playerItem(for: clips)
                guard !Task.isCancelled else { return }

                ranges = result.ranges
                duration = result.duration
                player.replaceCurrentItem(with: result.item)
                installEndObserver(for: result.item)
                seek(to: min(pendingSeekTime ?? requestedTime, result.duration))
                pendingSeekTime = nil
                isLoading = false

                if resumePlayback {
                    player.play()
                } else {
                    player.pause()
                }
            } catch {
                guard !Task.isCancelled else { return }
                isLoading = false
                pendingSeekTime = nil
                ranges = []
                duration = 0
                updatePosition(to: 0)
                player.replaceCurrentItem(with: nil)
            }
        }
    }

    func togglePlayback() {
        guard duration > 0 else {
            return
        }

        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.01 {
                seek(to: 0)
            }
            player.play()
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    func seek(to seconds: TimeInterval) {
        if duration <= 0, isLoading {
            pendingSeekTime = seconds
            return
        }

        let clampedSeconds = min(max(seconds, 0), duration)
        updatePosition(to: clampedSeconds)
        let time = CMTime(seconds: clampedSeconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func stop() {
        loadTask?.cancel()
        removeEndObserver()
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.pause()
    }

    private func installTimeObserverIfNeeded() {
        guard timeObserver == nil else { return }

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.03, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            let seconds = CMTimeGetSeconds(time)
            guard seconds.isFinite else { return }
            Task { @MainActor in
                self?.updatePosition(to: seconds)
            }
        }
    }

    private func updatePosition(to seconds: TimeInterval) {
        let clampedSeconds = min(max(seconds, 0), max(duration, 0))
        currentTime = clampedSeconds

        let activeRange = range(containing: clampedSeconds)
        let nextPosition = TimelinePlaybackPosition(
            timelineTime: clampedSeconds,
            clipID: activeRange?.clipID,
            sourceTime: activeRange?.sourceTime(for: clampedSeconds) ?? 0
        )

        if position != nextPosition {
            position = nextPosition
        }
    }

    private func range(containing time: TimeInterval) -> TimelinePlaybackRange? {
        if let range = ranges.first(where: { $0.contains(time) }) {
            return range
        }

        if time >= duration - 0.01 {
            return ranges.last
        }

        return nil
    }

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
                    self.seek(to: 0)
                    self.player.play()
                } else {
                    self.updatePosition(to: self.duration)
                    self.player.pause()
                }
            }
        }
    }

    private func removeEndObserver() {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    @MainActor
    private static func playerItem(for clips: [TimelinePlaybackClip]) async throws -> TimelineSequenceBuildResult {
        let composition = AVMutableComposition()
        var instructions: [AVMutableVideoCompositionInstruction] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []
        var ranges: [TimelinePlaybackRange] = []
        var cursor = CMTime.zero
        var renderSize: CGSize?
        var frameRate: Float = 30

        for clip in clips {
            let asset = AVURLAsset(url: clip.url)
            let duration = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(duration)
            guard durationSeconds.isFinite, durationSeconds > 0 else {
                continue
            }

            let sourceTimeRange = clip.trim?.timeRange(in: duration) ?? CMTimeRange(start: .zero, duration: duration)
            guard sourceTimeRange.duration.seconds > MediaTrim.minimumDuration else {
                continue
            }

            let videoTracks = try await asset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = videoTracks.first,
                  let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  )
            else {
                continue
            }

            try compositionVideoTrack.insertTimeRange(sourceTimeRange, of: sourceVideoTrack, at: cursor)

            let naturalSize = try await sourceVideoTrack.load(.naturalSize)
            let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
            let transformedBounds = CGRect(origin: .zero, size: naturalSize)
                .applying(preferredTransform)
                .standardized
            let displaySize = CGSize(width: abs(transformedBounds.width), height: abs(transformedBounds.height))
            let normalize = CGAffineTransform(
                translationX: -transformedBounds.minX,
                y: -transformedBounds.minY
            )
            let displayTransform = preferredTransform.concatenating(normalize)
            if renderSize == nil {
                renderSize = CGSize(
                    width: evenPlaybackDimension(displaySize.width),
                    height: evenPlaybackDimension(displaySize.height)
                )
            }

            if let nominalFrameRate = try? await sourceVideoTrack.load(.nominalFrameRate), nominalFrameRate > frameRate {
                frameRate = nominalFrameRate
            }

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = CMTimeRange(start: cursor, duration: sourceTimeRange.duration)
            instruction.backgroundColor = CGColor(gray: 0, alpha: 1)

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            if let renderSize {
                TimelineCropRenderer.applyTransformRamps(
                    to: layerInstruction,
                    timelineStart: cursor.seconds,
                    timelineEnd: (cursor + sourceTimeRange.duration).seconds,
                    displayTransform: displayTransform,
                    displaySize: displaySize,
                    renderSize: renderSize,
                    adjustmentSpans: []
                )
            } else {
                layerInstruction.setTransform(preferredTransform, at: cursor)
            }
            instruction.layerInstructions = [layerInstruction]
            instructions.append(instruction)

            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            for audioTrack in audioTracks {
                guard let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    continue
                }
                try? compositionAudioTrack.insertTimeRange(sourceTimeRange, of: audioTrack, at: cursor)
                let parameters = AVMutableAudioMixInputParameters(track: compositionAudioTrack)
                parameters.setVolume(max(0, clip.volume), at: cursor)
                audioParameters.append(parameters)
            }

            let timelineStart = cursor.seconds
            cursor = cursor + sourceTimeRange.duration
            ranges.append(TimelinePlaybackRange(
                clipID: clip.id,
                timelineStart: timelineStart,
                timelineEnd: cursor.seconds,
                sourceStart: sourceTimeRange.start.seconds
            ))
        }

        guard cursor.seconds > MediaTrim.minimumDuration,
              let renderSize
        else {
            throw TimelineSequenceVideoError.empty
        }

        let item = AVPlayerItem(asset: composition)

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = renderSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(frameRate.rounded(), 24)))
        videoComposition.instructions = instructions
        item.videoComposition = videoComposition

        if !audioParameters.isEmpty {
            let audioMix = AVMutableAudioMix()
            audioMix.inputParameters = audioParameters
            item.audioMix = audioMix
        }

        return TimelineSequenceBuildResult(item: item, duration: cursor.seconds, ranges: ranges)
    }

    private static func evenPlaybackDimension(_ value: CGFloat) -> CGFloat {
        max(2, floor(value / 2) * 2)
    }
}

private struct TimelineSequenceBuildResult {
    let item: AVPlayerItem
    let duration: TimeInterval
    let ranges: [TimelinePlaybackRange]
}

private struct TimelinePlaybackRange {
    let clipID: UUID
    let timelineStart: TimeInterval
    let timelineEnd: TimeInterval
    let sourceStart: TimeInterval

    func contains(_ time: TimeInterval) -> Bool {
        time >= timelineStart && time < timelineEnd
    }

    func sourceTime(for timelineTime: TimeInterval) -> TimeInterval {
        sourceStart + min(max(timelineTime - timelineStart, 0), max(timelineEnd - timelineStart, 0))
    }
}

private enum TimelineSequenceVideoError: Error {
    case empty
}
