import AppKit
import SwiftUI

struct SplitViewResizeCursorInstaller: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> SplitViewResizeCursorHostView {
        let view = SplitViewResizeCursorHostView()
        view.coordinator = context.coordinator
        context.coordinator.install(on: view)
        return view
    }

    func updateNSView(_ nsView: SplitViewResizeCursorHostView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.hostView = nsView
        nsView.window?.acceptsMouseMovedEvents = true
    }

    static func dismantleNSView(_ nsView: SplitViewResizeCursorHostView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator {
        weak var hostView: NSView?
        private var monitor: Any?
        private var resizeCursorIsActive = false

        func install(on view: NSView) {
            hostView = view
            view.window?.acceptsMouseMovedEvents = true

            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] event in
                MainActor.assumeIsolated {
                    self?.updateCursor(for: event)
                }
                return event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            resizeCursorIsActive = false
        }

        private func updateCursor(for event: NSEvent) {
            guard let hostView,
                  let window = hostView.window,
                  let eventWindow = event.window,
                  eventWindow === window
            else {
                resetResizeCursorIfNeeded()
                return
            }

            window.acceptsMouseMovedEvents = true

            if let cursor = resizeCursor(at: event.locationInWindow, in: window) {
                cursor.set()
                resizeCursorIsActive = true
            } else {
                resetResizeCursorIfNeeded()
            }
        }

        private func resetResizeCursorIfNeeded() {
            guard resizeCursorIsActive else { return }
            NSCursor.arrow.set()
            resizeCursorIsActive = false
        }

        private func resizeCursor(at windowPoint: NSPoint, in window: NSWindow) -> NSCursor? {
            guard let contentView = window.contentView else { return nil }

            for splitView in splitViews(in: contentView) {
                guard !splitView.isHidden,
                      splitView.bounds.width > 0,
                      splitView.bounds.height > 0
                else {
                    continue
                }

                let point = splitView.convert(windowPoint, from: nil)
                if let cursor = resizeCursor(at: point, in: splitView) {
                    return cursor
                }
            }

            return nil
        }

        private func resizeCursor(at point: NSPoint, in splitView: NSSplitView) -> NSCursor? {
            let views = splitView.arrangedSubviews.filter { !$0.isHidden && !$0.frame.isEmpty }
            guard views.count > 1 else { return nil }

            for index in 0..<(views.count - 1) {
                let rect = dividerHitRect(between: views[index], and: views[index + 1], in: splitView)
                if rect.contains(point) {
                    return splitView.isVertical ? .resizeLeftRight : .resizeUpDown
                }
            }

            return nil
        }

        private func dividerHitRect(between first: NSView, and second: NSView, in splitView: NSSplitView) -> NSRect {
            let thickness = max(splitView.dividerThickness, 10)

            if splitView.isVertical {
                let boundary = first.frame.midX < second.frame.midX
                    ? (first.frame.maxX + second.frame.minX) / 2
                    : (second.frame.maxX + first.frame.minX) / 2
                return NSRect(
                    x: boundary - thickness / 2,
                    y: splitView.bounds.minY,
                    width: thickness,
                    height: splitView.bounds.height
                )
            }

            let boundary = first.frame.midY < second.frame.midY
                ? (first.frame.maxY + second.frame.minY) / 2
                : (second.frame.maxY + first.frame.minY) / 2
            return NSRect(
                x: splitView.bounds.minX,
                y: boundary - thickness / 2,
                width: splitView.bounds.width,
                height: thickness
            )
        }

        private func splitViews(in view: NSView) -> [NSSplitView] {
            var found = view.subviews.flatMap(splitViews)
            if let splitView = view as? NSSplitView {
                found.insert(splitView, at: 0)
            }
            return found
        }
    }
}

final class SplitViewResizeCursorHostView: NSView {
    weak var coordinator: SplitViewResizeCursorInstaller.Coordinator?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.acceptsMouseMovedEvents = true
        if let coordinator {
            coordinator.hostView = self
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
