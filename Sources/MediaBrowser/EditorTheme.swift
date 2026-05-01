import AppKit
import SwiftUI

enum EditorThemeID: String, CaseIterable, Identifiable {
    case amberStudio
    case resolveTeal
    case finalCutSapphire

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amberStudio:
            return "Amber studio"
        case .resolveTeal:
            return "Resolve teal"
        case .finalCutSapphire:
            return "Final cut sapphire"
        }
    }

    var palette: EditorThemePalette {
        switch self {
        case .amberStudio:
            return .amberStudio
        case .resolveTeal:
            return .resolveTeal
        case .finalCutSapphire:
            return .finalCutSapphire
        }
    }
}

struct EditorThemePalette: Equatable {
    let id: EditorThemeID
    let windowBackground: Color
    let canvasBackground: Color
    let panelBackground: Color
    let panelRaised: Color
    let toolbarBackground: Color
    let timelineBackground: Color
    let trackBackground: Color
    let trackAlternateBackground: Color
    let thumbnailWell: Color
    let clipBlue: Color
    let clipBlueSelected: Color
    let accent: Color
    let accentText: Color
    let primaryText: Color
    let secondaryText: Color
    let mutedText: Color
    let hairline: Color
    let playbackControlBackground: Color
    let playbackControlBorder: Color
    let playbackSecondaryText: Color
    let windowBackgroundNSColor: NSColor

    var controlBackground: Color { playbackControlBackground }
    var controlBorder: Color { playbackControlBorder }

    static let amberStudio = EditorThemePalette(
        id: .amberStudio,
        windowBackground: Color(red: 0.140, green: 0.138, blue: 0.126),
        canvasBackground: Color(red: 0.071, green: 0.077, blue: 0.086),
        panelBackground: Color(red: 0.095, green: 0.101, blue: 0.111),
        panelRaised: Color(red: 0.128, green: 0.132, blue: 0.145),
        toolbarBackground: Color(red: 0.124, green: 0.128, blue: 0.142),
        timelineBackground: Color(red: 0.068, green: 0.073, blue: 0.082),
        trackBackground: Color(red: 0.076, green: 0.081, blue: 0.090),
        trackAlternateBackground: Color(red: 0.112, green: 0.116, blue: 0.128),
        thumbnailWell: Color.black.opacity(0.74),
        clipBlue: Color(red: 0.350, green: 0.615, blue: 0.745),
        clipBlueSelected: Color(red: 0.405, green: 0.690, blue: 0.815),
        accent: Color(red: 0.957, green: 0.737, blue: 0.157),
        accentText: Color(red: 0.075, green: 0.065, blue: 0.040),
        primaryText: Color.white.opacity(0.92),
        secondaryText: Color.white.opacity(0.58),
        mutedText: Color.white.opacity(0.38),
        hairline: Color.white.opacity(0.085),
        playbackControlBackground: Color.black.opacity(0.70),
        playbackControlBorder: Color.white.opacity(0.12),
        playbackSecondaryText: Color.white.opacity(0.66),
        windowBackgroundNSColor: NSColor(red: 0.140, green: 0.138, blue: 0.126, alpha: 1)
    )

    static let resolveTeal = EditorThemePalette(
        id: .resolveTeal,
        windowBackground: Color(red: 0.137, green: 0.139, blue: 0.129),
        canvasBackground: Color(red: 0.029, green: 0.055, blue: 0.054),
        panelBackground: Color(red: 0.037, green: 0.070, blue: 0.069),
        panelRaised: Color(red: 0.060, green: 0.105, blue: 0.103),
        toolbarBackground: Color(red: 0.054, green: 0.092, blue: 0.089),
        timelineBackground: Color(red: 0.020, green: 0.041, blue: 0.041),
        trackBackground: Color(red: 0.026, green: 0.052, blue: 0.052),
        trackAlternateBackground: Color(red: 0.055, green: 0.094, blue: 0.091),
        thumbnailWell: Color.black.opacity(0.76),
        clipBlue: Color(red: 0.345, green: 0.620, blue: 0.740),
        clipBlueSelected: Color(red: 0.400, green: 0.705, blue: 0.800),
        accent: Color(red: 0.094, green: 0.761, blue: 0.706),
        accentText: Color(red: 0.015, green: 0.070, blue: 0.064),
        primaryText: Color.white.opacity(0.93),
        secondaryText: Color.white.opacity(0.58),
        mutedText: Color.white.opacity(0.39),
        hairline: Color.white.opacity(0.080),
        playbackControlBackground: Color.black.opacity(0.70),
        playbackControlBorder: Color.white.opacity(0.12),
        playbackSecondaryText: Color.white.opacity(0.66),
        windowBackgroundNSColor: NSColor(red: 0.137, green: 0.139, blue: 0.129, alpha: 1)
    )

    static let finalCutSapphire = EditorThemePalette(
        id: .finalCutSapphire,
        windowBackground: Color(red: 0.128, green: 0.131, blue: 0.125),
        canvasBackground: Color(red: 0.024, green: 0.038, blue: 0.071),
        panelBackground: Color(red: 0.036, green: 0.052, blue: 0.091),
        panelRaised: Color(red: 0.064, green: 0.089, blue: 0.150),
        toolbarBackground: Color(red: 0.065, green: 0.086, blue: 0.143),
        timelineBackground: Color(red: 0.017, green: 0.029, blue: 0.055),
        trackBackground: Color(red: 0.022, green: 0.035, blue: 0.065),
        trackAlternateBackground: Color(red: 0.065, green: 0.086, blue: 0.143),
        thumbnailWell: Color.black.opacity(0.76),
        clipBlue: Color(red: 0.315, green: 0.600, blue: 0.735),
        clipBlueSelected: Color(red: 0.260, green: 0.490, blue: 0.945),
        accent: Color(red: 0.231, green: 0.510, blue: 0.965),
        accentText: Color(red: 0.020, green: 0.035, blue: 0.070),
        primaryText: Color.white.opacity(0.94),
        secondaryText: Color.white.opacity(0.60),
        mutedText: Color.white.opacity(0.40),
        hairline: Color.white.opacity(0.085),
        playbackControlBackground: Color.black.opacity(0.70),
        playbackControlBorder: Color.white.opacity(0.12),
        playbackSecondaryText: Color.white.opacity(0.66),
        windowBackgroundNSColor: NSColor(red: 0.128, green: 0.131, blue: 0.125, alpha: 1)
    )
}

private struct EditorThemeEnvironmentKey: EnvironmentKey {
    static let defaultValue = EditorThemePalette.amberStudio
}

extension EnvironmentValues {
    var editorTheme: EditorThemePalette {
        get { self[EditorThemeEnvironmentKey.self] }
        set { self[EditorThemeEnvironmentKey.self] = newValue }
    }
}
