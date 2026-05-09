import SwiftUI

enum TweakDensity: String, CaseIterable, Identifiable {
    case compact, regular, comfy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .comfy:   return "Comfy"
        }
    }
}

struct TweaksPanel: View {
    @Environment(\.editorTheme) private var theme

    @Binding var themeID: EditorThemeID
    @Binding var density: TweakDensity
    @Binding var monoTimecodes: Bool
    @Binding var showTechSpecs: Bool
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionLabel("Theme")
                    paletteChips
                    presetPicker

                    sectionLabel("Layout")
                    densityRadio
                    monoTimecodesToggle
                    showSpecsToggle
                }
                .padding(14)
            }
        }
        .frame(width: 280)
        .frame(maxHeight: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Tweaks")
                .font(.system(size: 12, weight: .semibold))

            Spacer(minLength: 0)

            Button {
                isPresented = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Close Tweaks")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Sections

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private var paletteChips: some View {
        let chips = EditorThemeID.allCases
        let columns = [GridItem(.adaptive(minimum: 44), spacing: 6)]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(chips) { id in
                paletteChip(for: id)
            }
        }
    }

    private func paletteChip(for id: EditorThemeID) -> some View {
        let palette = id.palette
        let selected = themeID == id
        return Button {
            themeID = id
        } label: {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    Rectangle().fill(palette.accent)
                    VStack(spacing: 0) {
                        Rectangle().fill(palette.windowBackground)
                        Rectangle().fill(palette.panelBackground)
                    }
                    .frame(width: 14)
                }
                .frame(height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 5))

                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.accentText)
                        .padding(3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .stroke(selected ? Color.primary.opacity(0.85) : Color.black.opacity(0.18), lineWidth: selected ? 1.5 : 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(id.title)
        .accessibilityLabel(id.title)
    }

    private var presetPicker: some View {
        HStack(spacing: 8) {
            Text("Preset")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Picker("", selection: $themeID) {
                ForEach(EditorThemeID.allCases) { id in
                    Text(id.title).tag(id)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
        }
    }

    private var densityRadio: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Density")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Picker("", selection: $density) {
                ForEach(TweakDensity.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
        }
    }

    private var monoTimecodesToggle: some View {
        Toggle(isOn: $monoTimecodes) {
            Text("Mono timecodes")
                .font(.system(size: 11, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }

    private var showSpecsToggle: some View {
        Toggle(isOn: $showTechSpecs) {
            Text("Show tech specs")
                .font(.system(size: 11, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}
