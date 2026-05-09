import SwiftUI

@main
struct FrameflowApp: App {
    @StateObject private var mainPanelState = MainPanelState()
    @AppStorage("editorThemeID") private var editorThemeRawValue = EditorThemeID.amberStudio.rawValue
    @AppStorage("tweakDensity") private var densityRawValue = TweakDensity.regular.rawValue
    @AppStorage("tweakMonoTimecodes") private var monoTimecodes = true
    @AppStorage("tweakShowTechSpecs") private var showTechSpecs = true

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
            ContentView(
                initialFolderURL: initialFolderURL,
                mainPanelState: mainPanelState,
                themeID: Binding(
                    get: { selectedTheme },
                    set: { editorThemeRawValue = $0.rawValue }
                ),
                density: Binding(
                    get: { TweakDensity(rawValue: densityRawValue) ?? .regular },
                    set: { densityRawValue = $0.rawValue }
                ),
                monoTimecodes: $monoTimecodes,
                showTechSpecs: $showTechSpecs
            )
            .environment(\.editorTheme, selectedTheme.palette)
            .frame(minWidth: 760, minHeight: 500)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .toolbar) {
                Divider()

                Toggle("Quick Sort Panel", isOn: Binding(
                    get: { mainPanelState.isVisible(.preview) },
                    set: { mainPanelState.setVisible(.preview, $0) }
                ))

                Toggle("Composer Panel", isOn: Binding(
                    get: { mainPanelState.isVisible(.videoComposer) },
                    set: { mainPanelState.setVisible(.videoComposer, $0, activate: $0) }
                ))

                Menu("Color Theme") {
                    ForEach(EditorThemeID.allCases) { theme in
                        Button {
                            editorThemeRawValue = theme.rawValue
                        } label: {
                            if selectedTheme == theme {
                                Label(theme.title, systemImage: "checkmark")
                            } else {
                                Text(theme.title)
                            }
                        }
                    }
                }
            }
        }
    }

    private var selectedTheme: EditorThemeID {
        EditorThemeID(rawValue: editorThemeRawValue) ?? .amberStudio
    }
}
