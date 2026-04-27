import SwiftUI

@main
struct MediaBrowserApp: App {
    @StateObject private var mainPanelState = MainPanelState()

    private let initialFolderURL: URL?

    init() {
        initialFolderURL = CommandLine.arguments.dropFirst().first.flatMap { path in
            let url = URL(fileURLWithPath: path).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  isDirectory.boolValue
            else {
                return nil
            }
            return url
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(initialFolderURL: initialFolderURL, mainPanelState: mainPanelState)
                .frame(minWidth: 760, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Divider()

                Toggle("Preview Panel", isOn: Binding(
                    get: { mainPanelState.isVisible(.preview) },
                    set: { mainPanelState.setVisible(.preview, $0) }
                ))

                Toggle("Video Editor Panel", isOn: Binding(
                    get: { mainPanelState.isVisible(.videoEditor) },
                    set: { mainPanelState.setVisible(.videoEditor, $0, activate: $0) }
                ))
            }
        }
    }
}
