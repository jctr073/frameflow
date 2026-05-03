import AppKit
import SwiftUI

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
