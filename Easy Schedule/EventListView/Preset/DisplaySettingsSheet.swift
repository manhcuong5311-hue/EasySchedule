//
//  DisplaySettingsSheet.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI

struct DisplaySettingsSheet: View {

    // EVENT TIME
    @AppStorage("timeFontSize") private var timeFontSize: Double = 13

    // CHAT COLOR
    @AppStorage("chat_my_preset")
    private var myPresetRaw: String = ChatColorPreset.blue.rawValue

    @AppStorage("chat_other_preset")
    private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue

    // ⭐ TIME DISPLAY MODE (REFactored)
    @AppStorage("event_time_display_mode")
    private var timeDisplayModeRaw: String = EventTimeDisplayMode.timeRange.rawValue

    private var timeDisplayMode: EventTimeDisplayMode {
        EventTimeDisplayMode(rawValue: timeDisplayModeRaw) ?? .timeRange
    }
    
    // ⭐ EVENT CARD LAYOUT
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.normal.rawValue

    private var cardLayout: EventCardLayout {
        EventCardLayout(rawValue: cardLayoutRaw) ?? .normal
    }


    @EnvironmentObject var uiAccent: UIAccentStore

    private var isCompactLayout: Bool {
        cardLayout == .compact
    }

    
    
    
    
    
    var body: some View {
        NavigationStack {
            List {
                uiAccentSection
                eventCardLayoutSection
                eventTimeSection
                eventTimeFormatSection
                chatColorSection
            }
            .navigationTitle(
                String(localized: "display_settings_navigation_title")
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    
    
    
    private var eventCardLayoutSection: some View {
        Section(
            String(localized: "display_settings_event_card_layout")
        ) {
            ForEach(EventCardLayout.allCases) { layout in
                HStack {
                    Text(layout.title)

                    Spacer()

                    if cardLayout == layout {
                        Image(systemName: "checkmark")
                            .foregroundColor(.accentColor)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    applyLayout(layout)
                }
            }
        }
    }

    private func applyLayout(_ layout: EventCardLayout) {
        let wasLayout = cardLayout
        cardLayoutRaw = layout.rawValue

        guard wasLayout != layout else { return }

        if let defaultMode = layout.defaultTimeDisplayMode {
            timeDisplayModeRaw = defaultMode.rawValue
        }
    }





    private var eventTimeSection: some View {
        Section(
            String(localized: "display_settings_event_time")
        ) {
            VStack(alignment: .leading, spacing: 8) {

                Text(
                    String(
                        format: String(localized: "display_settings_time_font_size"),
                        arguments: [Int(timeFontSize)]
                    )
                )
                .font(.caption)
                .foregroundStyle(.primary)

                Slider(
                    value: $timeFontSize,
                    in: 11...25,
                    step: 1
                )
            }
            .padding(.vertical, 4)
        }
    }



    private var eventTimeFormatSection: some View {
        Section(
            String(localized: "display_settings_event_time_format")
        ) {
            ForEach(EventTimeDisplayMode.allCases) { mode in
                HStack {
                    Text(mode.title)
                        .foregroundStyle(
                            isCompactLayout ? .secondary : .primary
                        )

                    Spacer()

                    if timeDisplayMode == mode {
                        Image(systemName: "checkmark")
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    guard !isCompactLayout else { return }
                    timeDisplayModeRaw = mode.rawValue
                }
                .disabled(isCompactLayout)
            }

            if isCompactLayout {
                Text(String(localized: "compact_time_format_locked"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }


    private var uiAccentSection: some View {
        Section(
            String(localized: "display_settings_ui_accent")
        ) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(UIAccentPreset.allCases, id: \.rawValue) { preset in
                        Circle()
                            .fill(Color(hex: preset.hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(
                                        uiAccent.hex == preset.hex
                                        ? Color.primary
                                        : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .onTapGesture {
                                uiAccent.set(hex: preset.hex)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    
    private var chatColorSection: some View {
        Section(
            String(localized: "display_settings_chat_colors")
        ) {
            ChatColorPresetPicker(
                title: String(localized: "chat_color_my_messages"),
                selectedRaw: $myPresetRaw
            )

            ChatColorPresetPicker(
                title: String(localized: "chat_color_other_messages"),
                selectedRaw: $otherPresetRaw
            )
        }
    }

    
    
    
}

struct ColorPickerRow: View {

    let title: String
    @Binding var hex: String

    var body: some View {
        HStack {
            Text(title)

            Spacer()

            ColorPicker(
                "",
                selection: Binding(
                    get: { Color(hex: hex) },
                    set: { hex = $0.toHex() ?? hex }
                )
            )
            .labelsHidden()
        }
    }
}


struct ChatColorPresetPicker: View {

    let title: String
    @Binding var selectedRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(ChatColorPreset.allCases, id: \.rawValue) { preset in
                        Circle()
                            .fill(Color(hex: preset.hex))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(
                                        selectedRaw == preset.rawValue
                                        ? Color.primary
                                        : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                            .onTapGesture {
                                selectedRaw = preset.rawValue
                            }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
