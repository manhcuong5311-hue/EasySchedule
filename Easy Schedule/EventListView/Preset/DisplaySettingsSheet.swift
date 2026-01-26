//
//  DisplaySettingsSheet.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//

import SwiftUI

struct DisplaySettingsSheet: View {

    // MARK: - Event Time
    @AppStorage("timeFontSize_v2")
    private var timeFontSize: Int = 13

    // MARK: - Chat Color
    @AppStorage("chat_my_preset")
    private var myPresetRaw: String = ChatColorPreset.blue.rawValue

    @AppStorage("chat_other_preset")
    private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue

    // MARK: - Time Display Mode
    @AppStorage("event_time_display_mode")
    private var timeDisplayModeRaw: String = EventTimeDisplayMode.timeRange.rawValue

    private var timeDisplayMode: EventTimeDisplayMode {
        EventTimeDisplayMode(rawValue: timeDisplayModeRaw) ?? .timeRange
    }

    // MARK: - Event Card Layout
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.normal.rawValue

    private var cardLayout: EventCardLayout {
        EventCardLayout(rawValue: cardLayoutRaw) ?? .normal
    }

    private var isCompactLayout: Bool {
        cardLayout == .compact
    }

    private var isTimelineLayout: Bool {
        cardLayout == .timeline
    }

    // MARK: - Timeline Settings
    @AppStorage("timeline_start_hour")
    private var timelineStartHour: Int = 8

    @AppStorage("timeline_end_hour")
    private var timelineEndHour: Int = 22

    // MARK: - Env
    @EnvironmentObject var uiAccent: UIAccentStore

    // MARK: - Body
    var body: some View {
        NavigationStack {
            List {
                uiAccentSection
                eventCardLayoutSection

                if isTimelineLayout {
                    timelineSettingsSection
                }

                eventTimeSection
                eventTimeFormatSection
                chatColorSection
            }
            .navigationTitle(
                String(localized: "display_settings_navigation_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: timelineStartHour) { _, _ in
                clampTimelineHours()
            }
            .onChange(of: timelineEndHour) { _, _ in
                clampTimelineHours()
            }
            .onAppear {
                clampTimelineHours()
                clampTimeFontSize()
            }
        }
    }

    // MARK: - Guards

    private func clampTimelineHours() {
        timelineStartHour = min(max(timelineStartHour, 0), 23)
        timelineEndHour   = min(max(timelineEndHour, 1), 24)

        if timelineStartHour >= timelineEndHour {
            timelineEndHour = min(timelineStartHour + 1, 24)
        }
    }

    private func clampTimeFontSize() {
        timeFontSize = min(max(timeFontSize, 11), 25)
    }

    // MARK: - Sections

    private var eventCardLayoutSection: some View {
        Section(String(localized: "display_settings_event_card_layout")) {
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

    private var timelineSettingsSection: some View {
        Section(String(localized: "display_settings_timeline_range")) {
            VStack(alignment: .leading, spacing: 12) {

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        String(
                            format: String(localized: "timeline_start_hour_format"),
                            timelineStartHour
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { Double(timelineStartHour) },
                            set: { timelineStartHour = Int($0) }
                        ),
                        in: 0...23,
                        step: 1
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        String(
                            format: String(localized: "timeline_end_hour_format"),
                            timelineEndHour
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Slider(
                        value: Binding(
                            get: { Double(timelineEndHour) },
                            set: { timelineEndHour = Int($0) }
                        ),
                        in: 1...24,
                        step: 1
                    )
                }

                Text(String(localized: "timeline_range_hint"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var eventTimeSection: some View {
        Section(String(localized: "display_settings_event_time")) {
            HStack {
                Button {
                    timeFontSize -= 1
                    clampTimeFontSize()
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .disabled(timeFontSize <= 11)

                Spacer()

                Text(
                    String(
                        format: String(localized: "display_settings_time_font_size"),
                        timeFontSize
                    )
                )

                Spacer()

                Button {
                    timeFontSize += 1
                    clampTimeFontSize()
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(timeFontSize >= 25)
            }
        }
    }

    private var eventTimeFormatSection: some View {
        Section(String(localized: "display_settings_event_time_format")) {
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
            }

            if isCompactLayout {
                Text(String(localized: "compact_time_format_locked"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var uiAccentSection: some View {
        Section(String(localized: "display_settings_ui_accent")) {
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
            }
        }
    }

    private var chatColorSection: some View {
        Section(String(localized: "display_settings_chat_colors")) {
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

    // MARK: - Helpers

    private func applyLayout(_ layout: EventCardLayout) {
        let old = cardLayout
        cardLayoutRaw = layout.rawValue

        guard old != layout else { return }

        if let defaultMode = layout.defaultTimeDisplayMode {
            timeDisplayModeRaw = defaultMode.rawValue
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
