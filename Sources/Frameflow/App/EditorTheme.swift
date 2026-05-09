import AppKit
import SwiftUI

enum EditorThemeID: String, CaseIterable, Identifiable {
    case amberStudio
    case resolveTeal
    case finalCutSapphire
    case graphiteMono
    case ultraviolet
    case crimsonLab
    case forestConsole
    case copperPrint
    case polarIce

    var id: String { rawValue }

    var title: String {
        switch self {
        case .amberStudio:       return "Amber Studio"
        case .resolveTeal:       return "Resolve Teal"
        case .finalCutSapphire:  return "Final Cut Sapphire"
        case .graphiteMono:      return "Graphite Mono"
        case .ultraviolet:       return "Ultraviolet"
        case .crimsonLab:        return "Crimson Lab"
        case .forestConsole:     return "Forest Console"
        case .copperPrint:       return "Copper Print"
        case .polarIce:          return "Polar Ice"
        }
    }

    var palette: EditorThemePalette {
        switch self {
        case .amberStudio:       return .amberStudio
        case .resolveTeal:       return .resolveTeal
        case .finalCutSapphire:  return .finalCutSapphire
        case .graphiteMono:      return .graphiteMono
        case .ultraviolet:       return .ultraviolet
        case .crimsonLab:        return .crimsonLab
        case .forestConsole:     return .forestConsole
        case .copperPrint:       return .copperPrint
        case .polarIce:          return .polarIce
        }
    }
}

enum EditorThemeKind {
    case dark
    case light
}

struct EditorThemePalette: Equatable {
    let id: EditorThemeID
    let kind: EditorThemeKind

    // Surfaces
    let windowBackground: Color
    let canvasBackground: Color
    let panelBackground: Color
    let panelRaised: Color
    let toolbarBackground: Color
    let timelineBackground: Color
    let trackBackground: Color
    let trackAlternateBackground: Color
    let thumbnailWell: Color

    // Clip / accent
    let clipBlue: Color
    let clipBlueSelected: Color
    let clipText: Color
    let accent: Color
    let accentText: Color
    let danger: Color

    // Text
    let primaryText: Color
    let secondaryText: Color
    let mutedText: Color

    // Lines / grid
    let hairline: Color
    let strongHairline: Color
    let gridLine: Color

    // Playback HUD overlays (rendered on top of media — kept dark regardless of theme).
    let playbackControlBackground: Color
    let playbackControlBorder: Color
    let playbackSecondaryText: Color

    // Bridge for AppKit (NSWindow background, etc.)
    let windowBackgroundNSColor: NSColor

    var controlBackground: Color { playbackControlBackground }
    var controlBorder: Color { playbackControlBorder }
}

// MARK: - Hex helpers

private extension Color {
    /// Build a Color from a hex string like "#1B1A17" or "1B1A17".
    static func hex(_ hex: String, opacity: Double = 1) -> Color {
        let (r, g, b) = parseHex(hex)
        return Color(red: r, green: g, blue: b, opacity: opacity)
    }

    /// `rgba(255,255,255,.62)` style — alpha as a percentage of white/black/etc.
    static func rgba(_ red: Int, _ green: Int, _ blue: Int, _ alpha: Double) -> Color {
        Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255, opacity: alpha)
    }
}

private extension NSColor {
    static func hex(_ hex: String) -> NSColor {
        let (r, g, b) = parseHex(hex)
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

private func parseHex(_ raw: String) -> (Double, Double, Double) {
    var s = raw
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else {
        return (0, 0, 0)
    }
    let r = Double((v >> 16) & 0xFF) / 255
    let g = Double((v >> 8) & 0xFF) / 255
    let b = Double(v & 0xFF) / 255
    return (r, g, b)
}

// MARK: - Palettes

extension EditorThemePalette {
    static let amberStudio = EditorThemePalette(
        id: .amberStudio,
        kind: .dark,
        windowBackground:   .hex("#1B1A17"),
        canvasBackground:   .hex("#0E0F11"),
        panelBackground:    .hex("#15171B"),
        panelRaised:        .hex("#1F2126"),
        toolbarBackground:  .hex("#1B1D22"),
        timelineBackground: .hex("#101216"),
        trackBackground:    .hex("#13161B"),
        trackAlternateBackground: .hex("#1B1E24"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#5C9EC0"),
        clipBlueSelected:   .hex("#67B0D0"),
        clipText:           .hex("#0C1D2A"),
        accent:             .hex("#F4BC28"),
        accentText:         .hex("#1A1408"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.94),
        secondaryText:      .rgba(255, 255, 255, 0.62),
        mutedText:          .rgba(255, 255, 255, 0.42),
        hairline:           .rgba(255, 255, 255, 0.07),
        strongHairline:     .rgba(255, 255, 255, 0.13),
        gridLine:           .rgba(255, 255, 255, 0.04),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#1B1A17")
    )

    static let resolveTeal = EditorThemePalette(
        id: .resolveTeal,
        kind: .dark,
        windowBackground:   .hex("#1A1A18"),
        canvasBackground:   .hex("#08120F"),
        panelBackground:    .hex("#0B1A17"),
        panelRaised:        .hex("#0F2522"),
        toolbarBackground:  .hex("#0E211E"),
        timelineBackground: .hex("#070F0E"),
        trackBackground:    .hex("#0A1714"),
        trackAlternateBackground: .hex("#0F221F"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#5DA1B9"),
        clipBlueSelected:   .hex("#68B5CC"),
        clipText:           .hex("#06181B"),
        accent:             .hex("#18C2B4"),
        accentText:         .hex("#03201D"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.94),
        secondaryText:      .rgba(255, 255, 255, 0.62),
        mutedText:          .rgba(255, 255, 255, 0.42),
        hairline:           .rgba(255, 255, 255, 0.07),
        strongHairline:     .rgba(255, 255, 255, 0.13),
        gridLine:           .rgba(255, 255, 255, 0.04),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#1A1A18")
    )

    static let finalCutSapphire = EditorThemePalette(
        id: .finalCutSapphire,
        kind: .dark,
        windowBackground:   .hex("#161616"),
        canvasBackground:   .hex("#070C1A"),
        panelBackground:    .hex("#0B1226"),
        panelRaised:        .hex("#11183A"),
        toolbarBackground:  .hex("#101638"),
        timelineBackground: .hex("#050A18"),
        trackBackground:    .hex("#080F22"),
        trackAlternateBackground: .hex("#0E1633"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#5096C0"),
        clipBlueSelected:   .hex("#4380F0"),
        clipText:           .white,
        accent:             .hex("#3B83F7"),
        accentText:         .hex("#040820"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.95),
        secondaryText:      .rgba(255, 255, 255, 0.62),
        mutedText:          .rgba(255, 255, 255, 0.42),
        hairline:           .rgba(255, 255, 255, 0.08),
        strongHairline:     .rgba(255, 255, 255, 0.13),
        gridLine:           .rgba(255, 255, 255, 0.045),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#161616")
    )

    static let graphiteMono = EditorThemePalette(
        id: .graphiteMono,
        kind: .dark,
        windowBackground:   .hex("#161616"),
        canvasBackground:   .hex("#0C0C0C"),
        panelBackground:    .hex("#121212"),
        panelRaised:        .hex("#1A1A1A"),
        toolbarBackground:  .hex("#161616"),
        timelineBackground: .hex("#0A0A0A"),
        trackBackground:    .hex("#101010"),
        trackAlternateBackground: .hex("#181818"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#6E6E6E"),
        clipBlueSelected:   .hex("#9E9E9E"),
        clipText:           .hex("#0A0A0A"),
        accent:             .hex("#EAEAEA"),
        accentText:         .hex("#0A0A0A"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.94),
        secondaryText:      .rgba(255, 255, 255, 0.58),
        mutedText:          .rgba(255, 255, 255, 0.38),
        hairline:           .rgba(255, 255, 255, 0.07),
        strongHairline:     .rgba(255, 255, 255, 0.13),
        gridLine:           .rgba(255, 255, 255, 0.04),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#161616")
    )

    static let ultraviolet = EditorThemePalette(
        id: .ultraviolet,
        kind: .dark,
        windowBackground:   .hex("#15131B"),
        canvasBackground:   .hex("#0A0716"),
        panelBackground:    .hex("#100B1F"),
        panelRaised:        .hex("#181230"),
        toolbarBackground:  .hex("#15102A"),
        timelineBackground: .hex("#080513"),
        trackBackground:    .hex("#0C081C"),
        trackAlternateBackground: .hex("#150F2C"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#7E63B2"),
        clipBlueSelected:   .hex("#A079D6"),
        clipText:           .hex("#0D0820"),
        accent:             .hex("#A06BFF"),
        accentText:         .hex("#150A28"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.94),
        secondaryText:      .rgba(255, 255, 255, 0.62),
        mutedText:          .rgba(255, 255, 255, 0.42),
        hairline:           .rgba(255, 255, 255, 0.08),
        strongHairline:     .rgba(255, 255, 255, 0.14),
        gridLine:           .rgba(255, 255, 255, 0.05),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#15131B")
    )

    static let crimsonLab = EditorThemePalette(
        id: .crimsonLab,
        kind: .dark,
        windowBackground:   .hex("#181312"),
        canvasBackground:   .hex("#100806"),
        panelBackground:    .hex("#170D0C"),
        panelRaised:        .hex("#22110F"),
        toolbarBackground:  .hex("#1E0F0D"),
        timelineBackground: .hex("#0D0605"),
        trackBackground:    .hex("#13080A"),
        trackAlternateBackground: .hex("#1D0F11"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#A36868"),
        clipBlueSelected:   .hex("#D77979"),
        clipText:           .hex("#1C0707"),
        accent:             .hex("#FF5A5F"),
        accentText:         .hex("#1F0707"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.94),
        secondaryText:      .rgba(255, 255, 255, 0.62),
        mutedText:          .rgba(255, 255, 255, 0.42),
        hairline:           .rgba(255, 255, 255, 0.08),
        strongHairline:     .rgba(255, 255, 255, 0.14),
        gridLine:           .rgba(255, 255, 255, 0.04),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#181312")
    )

    static let forestConsole = EditorThemePalette(
        id: .forestConsole,
        kind: .dark,
        windowBackground:   .hex("#13181A"),
        canvasBackground:   .hex("#08110B"),
        panelBackground:    .hex("#0D1A11"),
        panelRaised:        .hex("#132518"),
        toolbarBackground:  .hex("#112116"),
        timelineBackground: .hex("#060E08"),
        trackBackground:    .hex("#0A1610"),
        trackAlternateBackground: .hex("#102218"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#67A26E"),
        clipBlueSelected:   .hex("#7DBC85"),
        clipText:           .hex("#08180C"),
        accent:             .hex("#7CD64E"),
        accentText:         .hex("#0A1F08"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.93),
        secondaryText:      .rgba(255, 255, 255, 0.60),
        mutedText:          .rgba(255, 255, 255, 0.40),
        hairline:           .rgba(255, 255, 255, 0.07),
        strongHairline:     .rgba(255, 255, 255, 0.13),
        gridLine:           .rgba(255, 255, 255, 0.04),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#13181A")
    )

    static let copperPrint = EditorThemePalette(
        id: .copperPrint,
        kind: .dark,
        windowBackground:   .hex("#1A1612"),
        canvasBackground:   .hex("#100B07"),
        panelBackground:    .hex("#171008"),
        panelRaised:        .hex("#22180F"),
        toolbarBackground:  .hex("#1F160D"),
        timelineBackground: .hex("#0E0905"),
        trackBackground:    .hex("#140D08"),
        trackAlternateBackground: .hex("#1D140C"),
        thumbnailWell:      .black,
        clipBlue:           .hex("#A4814F"),
        clipBlueSelected:   .hex("#C29761"),
        clipText:           .hex("#1A0F05"),
        accent:             .hex("#E07A3D"),
        accentText:         .hex("#1A0A04"),
        danger:             .hex("#E5484D"),
        primaryText:        .rgba(255, 255, 255, 0.93),
        secondaryText:      .rgba(255, 255, 255, 0.60),
        mutedText:          .rgba(255, 255, 255, 0.40),
        hairline:           .rgba(255, 255, 255, 0.07),
        strongHairline:     .rgba(255, 255, 255, 0.13),
        gridLine:           .rgba(255, 255, 255, 0.04),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#1A1612")
    )

    static let polarIce = EditorThemePalette(
        id: .polarIce,
        kind: .light,
        windowBackground:   .hex("#E6EBF1"),
        canvasBackground:   .hex("#F5F7FA"),
        panelBackground:    .hex("#FBFCFD"),
        panelRaised:        .hex("#FFFFFF"),
        toolbarBackground:  .hex("#F0F3F7"),
        timelineBackground: .hex("#EDF1F5"),
        trackBackground:    .hex("#E5EAF0"),
        trackAlternateBackground: .hex("#F1F4F8"),
        thumbnailWell:      .hex("#0F1620"),
        clipBlue:           .hex("#7AA8C7"),
        clipBlueSelected:   .hex("#5B95C0"),
        clipText:           .white,
        accent:             .hex("#0058D4"),
        accentText:         .white,
        danger:             .hex("#D11C2A"),
        primaryText:        .rgba(15, 22, 32, 0.94),
        secondaryText:      .rgba(15, 22, 32, 0.62),
        mutedText:          .rgba(15, 22, 32, 0.42),
        hairline:           .rgba(15, 22, 32, 0.10),
        strongHairline:     .rgba(15, 22, 32, 0.18),
        gridLine:           .rgba(15, 22, 32, 0.05),
        playbackControlBackground: .black.opacity(0.70),
        playbackControlBorder:     .white.opacity(0.12),
        playbackSecondaryText:     .white.opacity(0.66),
        windowBackgroundNSColor:   .hex("#E6EBF1")
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
