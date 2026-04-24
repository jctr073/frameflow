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

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.videoGravity = .resizeAspect
        view.player = context.coordinator.player
        context.coordinator.play(url)
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if context.coordinator.url != url {
            context.coordinator.play(url)
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

        func play(_ url: URL) {
            self.url = url
            let item = AVPlayerItem(url: url)
            player.replaceCurrentItem(with: item)
            player.seek(to: .zero)
            player.play()
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
