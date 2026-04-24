import SwiftUI

@main
struct MediaBrowserApp: App {
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
            ContentView(initialFolderURL: initialFolderURL)
                .frame(minWidth: 760, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
