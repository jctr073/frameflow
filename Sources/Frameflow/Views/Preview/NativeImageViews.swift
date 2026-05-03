@preconcurrency import AppKit
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
