//
//  CustomizeCalendarSettingsView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 7/12/25.
//
import SwiftUI
import Combine

struct CustomizeCalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    // MARK: - Calendar settings
    @AppStorage("showOwnerLabel") private var showOwnerLabel: Bool = true
    @AppStorage("timeFontSize") private var timeFontSize: Double = 13.0
    @AppStorage("timeColorHex") private var timeColorHex: String = "#007AFF"

    @State private var timeColor: Color = .blue

    // MARK: - Chat preset settings
    @AppStorage("chat_my_preset") private var chatMyPresetRaw: String = ChatColorPreset.blue.rawValue
    @AppStorage("chat_other_preset") private var chatOtherPresetRaw: String = ChatColorPreset.graphite.rawValue

    private var chatMyPreset: ChatColorPreset {
        ChatColorPreset(rawValue: chatMyPresetRaw) ?? .blue
    }

    private var chatOtherPreset: ChatColorPreset {
        ChatColorPreset(rawValue: chatOtherPresetRaw) ?? .graphite
    }

    var body: some View {
        NavigationStack {
            Form {

                // MARK: - Display
                Section(header: Text(String(localized: "display_section_title"))) {
                    Toggle(
                        String(localized: "show_owner_label"),
                        isOn: $showOwnerLabel
                    )
                }

                // MARK: - Time display
                Section(header: Text(String(localized: "time_display_section_title"))) {

                    HStack {
                        Text(String(localized: "size_label"))
                        Spacer()
                        Text("\(Int(timeFontSize)) pt")
                            .foregroundColor(.secondary)
                    }

                    Slider(value: $timeFontSize, in: 10...22, step: 1)

                    ColorPicker(
                        String(localized: "time_color_label"),
                        selection: $timeColor
                    )
                    .onChange(of: timeColor) {
                        if let hex = timeColor.toHex() {
                            timeColorHex = hex
                        }
                    }
                }

                // MARK: - Chat appearance (PRESET ONLY)
                Section(header: Text(String(localized: "chat_appearance_title"))) {

                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "chat_my_message_color"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        presetRow(
                            selected: chatMyPreset,
                            onSelect: { chatMyPresetRaw = $0.rawValue }
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(String(localized: "chat_other_message_color"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        presetRow(
                            selected: chatOtherPreset,
                            onSelect: { chatOtherPresetRaw = $0.rawValue }
                        )
                    }
                }

                // MARK: - Close
                Section {
                    Button(String(localized: "close")) {
                        dismiss()
                    }
                }
            }
            .navigationTitle(String(localized: "display_customization_title"))
            .onAppear {
                timeColor = Color(hex: timeColorHex)
            }
        }
    }

    // MARK: - Preset Row
    @ViewBuilder
    private func presetRow(
        selected: ChatColorPreset,
        onSelect: @escaping (ChatColorPreset) -> Void
    ) -> some View {

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(ChatColorPreset.allCases) { preset in
                    Button {
                        onSelect(preset)
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(preset.color)
                                .frame(width: 44, height: 28)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(
                                            preset == selected
                                            ? Color.primary
                                            : Color.clear,
                                            lineWidth: 2
                                        )
                                )

                            Text(preset.title)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }
}


enum ChatColorPreset: String, CaseIterable, Identifiable {
    case blue
    case green
    case purple
    case orange
    case dark
    case graphite

    var id: String { rawValue }

    var hex: String {
        switch self {
        case .blue:     return "#007AFF"
        case .green:    return "#34C759"
        case .purple:   return "#AF52DE"
        case .orange:   return "#FF9500"
        case .dark:     return "#1C1C1E"
        case .graphite: return "#3A3A3C"
        }
    }

    var title: String {
        switch self {
        case .blue:     return String(localized: "preset_blue")
        case .green:    return String(localized: "preset_green")
        case .purple:   return String(localized: "preset_purple")
        case .orange:   return String(localized: "preset_orange")
        case .dark:     return String(localized: "preset_dark")
        case .graphite: return String(localized: "preset_graphite")
        }
    }

    var color: Color {
        Color(hex: hex)
    }
}

import SwiftUI

// MARK: - Chat Bubble Style
struct ChatBubbleStyle {
    let background: Color
    let text: Color
    let secondaryText: Color
    let innerButtonBackground: Color
    let border: Color
}

// MARK: - Style Factory
enum ChatBubbleStyleFactory {

    static func make(
        backgroundHex: String,
        isMe: Bool,
        isPremium: Bool
    ) -> ChatBubbleStyle {

        let bg = Color(hex: backgroundHex)
        let isDark = bg.isDarkColor

        return ChatBubbleStyle(
            background: bg,
            text: isDark ? .white : .black,
            secondaryText: isDark
                ? Color.white.opacity(0.7)
                : Color.black.opacity(0.6),
            innerButtonBackground: isDark
                ? Color.white.opacity(0.18)
                : Color.black.opacity(0.08),
            border: (isMe && isPremium)
                ? AppColors.premiumAccent.opacity(0.4)
                : .clear
        )
    }
}

// MARK: - Color helper
extension Color {

    var isDarkColor: Bool {
        let ui = UIColor(self)

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        ui.getRed(&r, green: &g, blue: &b, alpha: &a)

        // WCAG luminance
        let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
        return luminance < 0.5
    }
}
