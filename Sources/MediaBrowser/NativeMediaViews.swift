@preconcurrency import AppKit
import AVKit
import ImageIO
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

struct NativeVideoView: NSViewRepresentable {
    let url: URL
    var crop = NormalizedCrop.full
    var displaySize: CGSize?
    var trim: MediaTrim?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        context.coordinator.play(url, crop: crop, displaySize: displaySize, trim: trim)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if context.coordinator.needsUpdate(url: url, crop: crop, displaySize: displaySize, trim: trim) {
            context.coordinator.play(url, crop: crop, displaySize: displaySize, trim: trim)
        } else {
            context.coordinator.player.play()
        }
        nsView.player = context.coordinator.player
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.stop()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator {
        let player = AVPlayer()
        var url: URL?
        var crop = NormalizedCrop.full
        var displaySize: CGSize?
        var trim: MediaTrim?
        private var loadTask: Task<Void, Never>?
        private var boundaryObserver: Any?

        func needsUpdate(url: URL, crop: NormalizedCrop, displaySize: CGSize?, trim: MediaTrim?) -> Bool {
            self.url != url
                || self.crop != crop
                || self.displaySize != displaySize
                || self.trim != trim
        }

        func play(_ url: URL, crop: NormalizedCrop, displaySize: CGSize?, trim: MediaTrim?) {
            self.url = url
            self.crop = crop
            self.displaySize = displaySize
            self.trim = trim

            loadTask?.cancel()
            removeBoundaryObserver()
            let player = player
            loadTask = Task { @MainActor in
                let playerItem = await Self.playerItem(url: url, crop: crop, displaySize: displaySize)
                guard !Task.isCancelled else { return }
                player.replaceCurrentItem(with: playerItem)
                let startTime = CMTime(seconds: trim?.start ?? 0, preferredTimescale: 600)
                await player.seek(to: startTime)
                if let trim {
                    installBoundaryObserver(end: trim.end, start: trim.start)
                }
                player.play()
            }
        }

        deinit {
            loadTask?.cancel()
        }

        func stop() {
            loadTask?.cancel()
            removeBoundaryObserver()
            player.pause()
        }

        @MainActor
        private static func playerItem(url: URL, crop: NormalizedCrop, displaySize: CGSize?) async -> AVPlayerItem {
            let asset = AVURLAsset(url: url)
            let item = AVPlayerItem(asset: asset)
            guard !crop.isFullFrame,
                  let displaySize,
                  let videoComposition = await videoComposition(for: asset, crop: crop, displaySize: displaySize)
            else {
                return item
            }

            item.videoComposition = videoComposition
            return item
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
        private func installBoundaryObserver(end: TimeInterval, start: TimeInterval) {
            removeBoundaryObserver()
            let endTime = CMTime(seconds: end, preferredTimescale: 600)
            boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: endTime)], queue: .main) { [weak self] in
                guard let self else { return }
                let startTime = CMTime(seconds: start, preferredTimescale: 600)
                self.player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                self.player.play()
            }
        }

        @MainActor
        private func removeBoundaryObserver() {
            if let boundaryObserver {
                player.removeTimeObserver(boundaryObserver)
                self.boundaryObserver = nil
            }
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
