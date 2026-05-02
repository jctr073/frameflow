@preconcurrency import AppKit
import AVKit
import ImageIO
import FrameflowCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct NativeImageView: NSViewRepresentable {
    let url: URL
    let animates: Bool

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageAlignment = .alignCenter
        view.imageScaling = .scaleProportionallyUpOrDown
        view.canDrawSubviewsIntoLayer = false
        view.animates = animates
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.animates = animates
        nsView.image = NSImage(contentsOf: url)
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: ()) {
        nsView.animates = false
        nsView.image = nil
    }
}

struct NativeGIFImageView: NSViewRepresentable {
    let url: URL
    var trim: MediaTrim?

    func makeNSView(context: Context) -> NSImageView {
        let view = NSImageView()
        view.imageAlignment = .alignCenter
        view.imageScaling = .scaleProportionallyUpOrDown
        view.canDrawSubviewsIntoLayer = false
        view.animates = true
        context.coordinator.load(url: url, trim: trim, into: view)
        return view
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        if context.coordinator.needsUpdate(url: url, trim: trim) {
            context.coordinator.load(url: url, trim: trim, into: nsView)
        }
        nsView.animates = true
    }

    static func dismantleNSView(_ nsView: NSImageView, coordinator: Coordinator) {
        coordinator.cancel()
        nsView.animates = false
        nsView.image = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        private var url: URL?
        private var trim: MediaTrim?
        private var loadTask: Task<Void, Never>?

        func needsUpdate(url: URL, trim: MediaTrim?) -> Bool {
            self.url != url || self.trim != trim
        }

        func load(url: URL, trim: MediaTrim?, into imageView: NSImageView) {
            self.url = url
            self.trim = trim
            loadTask?.cancel()

            loadTask = Task {
                let image = await Self.image(url: url, trim: trim)
                guard !Task.isCancelled else { return }
                imageView.image = image
                imageView.animates = true
            }
        }

        func cancel() {
            loadTask?.cancel()
        }

        private static func image(url: URL, trim: MediaTrim?) async -> NSImage? {
            await Task.detached(priority: .userInitiated) {
                if trim == nil {
                    return NSImage(contentsOf: url)
                }

                guard let data = trimmedGIFData(url: url, trim: trim) else {
                    return NSImage(contentsOf: url)
                }
                return NSImage(data: data as Data)
            }.value
        }
    }
}

struct NativeWebImageView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false

        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        view.allowsMagnification = false
        context.coordinator.load(url, in: view)
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.load(url, in: nsView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    @MainActor
    final class Coordinator {
        var url: URL

        init(url: URL) {
            self.url = url
        }

        @MainActor
        func load(_ url: URL, in webView: WKWebView) {
            self.url = url
            guard let data = try? Data(contentsOf: url) else {
                webView.loadHTMLString("", baseURL: nil)
                return
            }

            let src = "data:image/webp;base64,\(data.base64EncodedString())"
            let html = """
            <!doctype html>
            <html>
            <head>
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <style>
            html, body {
                margin: 0;
                width: 100%;
                height: 100%;
                overflow: hidden;
                background: transparent;
            }
            img {
                display: block;
                width: 100vw;
                height: 100vh;
                object-fit: contain;
            }
            </style>
            </head>
            <body><img src="\(src)" alt=""></body>
            </html>
            """
            webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        }
    }
}

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

private struct NativeVideoSurface: NSViewRepresentable {
    let player: AVPlayer
    let fillsFrame: Bool

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .none
        view.videoGravity = videoGravity
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
        nsView.videoGravity = videoGravity
    }

    private var videoGravity: AVLayerVideoGravity {
        fillsFrame ? .resizeAspectFill : .resizeAspect
    }
}

private struct ZoomableNativeVideoSurface: View {
    let player: AVPlayer
    let zoomMultiplier: Double
    let fillsFrame: Bool

    var body: some View {
        GeometryReader { geometry in
            NativeVideoSurface(player: player, fillsFrame: fillsFrame)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .scaleEffect(CGFloat(max(0.08, zoomMultiplier)), anchor: .center)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
        .background(Color.black)
        .clipped()
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
    let player = AVPlayer()

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false
    @Published var isLoading = false
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
                self.updatePosition(to: self.duration)
                self.player.pause()
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

@MainActor
private final class NativeVideoController: ObservableObject {
    let player = AVPlayer()

    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var isPlaying = false

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
                self.currentTime = end
                self.player.pause()
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
                self.currentTime = self.playbackEnd
                self.player.pause()
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

private func trimmedGIFData(url: URL, trim: MediaTrim?) -> NSData? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
        return nil
    }

    let frameCount = CGImageSourceGetCount(source)
    guard frameCount > 0 else {
        return nil
    }

    let frameDurations = (0..<frameCount).map { gifFrameDuration(source: source, index: $0) }
    let totalDuration = frameDurations.reduce(0, +)
    let effectiveTrim = trim?.clamped(to: totalDuration)
    let trimStart = effectiveTrim?.start ?? 0
    let trimEnd = effectiveTrim?.end ?? totalDuration

    var selectedFrames: [(index: Int, delay: TimeInterval)] = []
    var frameStart: TimeInterval = 0
    for index in 0..<frameCount {
        let originalDelay = frameDurations[index]
        let frameEnd = frameStart + originalDelay
        defer { frameStart = frameEnd }

        guard frameEnd > trimStart, frameStart < trimEnd else {
            continue
        }

        let clippedDelay = min(frameEnd, trimEnd) - max(frameStart, trimStart)
        selectedFrames.append((index, max(0.02, clippedDelay)))
    }

    guard !selectedFrames.isEmpty else {
        return nil
    }

    let data = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        data,
        UTType.gif.identifier as CFString,
        selectedFrames.count,
        nil
    ) else {
        return nil
    }

    CGImageDestinationSetProperties(destination, [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]
    ] as CFDictionary)

    for frame in selectedFrames {
        guard let image = CGImageSourceCreateImageAtIndex(source, frame.index, nil) else {
            continue
        }
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: frame.delay,
                kCGImagePropertyGIFUnclampedDelayTime: frame.delay
            ]
        ] as CFDictionary)
    }

    guard CGImageDestinationFinalize(destination) else {
        return nil
    }
    return data
}

private func gifFrameDuration(source: CGImageSource, index: Int) -> TimeInterval {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let gifProperties = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
    else {
        return 0.1
    }

    let unclampedDelay = gifProperties[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval
    let delay = unclampedDelay ?? gifProperties[kCGImagePropertyGIFDelayTime] as? TimeInterval ?? 0.1
    return max(0.02, delay)
}

struct KeyboardMonitor: NSViewRepresentable {
    let onKeyDown: (NSEvent) -> Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.install(handler: onKeyDown)
        DispatchQueue.main.async { [weak view, weak coordinator = context.coordinator] in
            coordinator?.hostWindow = view?.window
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.hostWindow = nsView.window
        context.coordinator.handler = onKeyDown
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        weak var hostWindow: NSWindow?
        var handler: ((NSEvent) -> Bool)?
        private var monitor: Any?

        func install(handler: @escaping (NSEvent) -> Bool) {
            self.handler = handler
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      event.window === self.hostWindow,
                      self.handler?(event) == true
                else {
                    return event
                }
                return nil
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            uninstall()
        }
    }
}
