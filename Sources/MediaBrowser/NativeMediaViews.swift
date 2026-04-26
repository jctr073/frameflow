@preconcurrency import AppKit
import AVKit
import SwiftUI
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

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        context.coordinator.play(url, crop: crop, displaySize: displaySize)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if context.coordinator.needsUpdate(url: url, crop: crop, displaySize: displaySize) {
            context.coordinator.play(url, crop: crop, displaySize: displaySize)
        } else {
            context.coordinator.player.play()
        }
        nsView.player = context.coordinator.player
    }

    static func dismantleNSView(_ nsView: AVPlayerView, coordinator: Coordinator) {
        coordinator.player.pause()
        nsView.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        let player = AVPlayer()
        var url: URL?
        var crop = NormalizedCrop.full
        var displaySize: CGSize?
        private var loadTask: Task<Void, Never>?

        func needsUpdate(url: URL, crop: NormalizedCrop, displaySize: CGSize?) -> Bool {
            self.url != url
                || self.crop != crop
                || self.displaySize != displaySize
        }

        func play(_ url: URL, crop: NormalizedCrop, displaySize: CGSize?) {
            self.url = url
            self.crop = crop
            self.displaySize = displaySize

            loadTask?.cancel()
            let player = player
            loadTask = Task { @MainActor in
                let playerItem = await Self.playerItem(url: url, crop: crop, displaySize: displaySize)
                guard !Task.isCancelled else { return }
                player.replaceCurrentItem(with: playerItem)
                await player.seek(to: .zero)
                player.play()
            }
        }

        deinit {
            loadTask?.cancel()
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
    }
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
