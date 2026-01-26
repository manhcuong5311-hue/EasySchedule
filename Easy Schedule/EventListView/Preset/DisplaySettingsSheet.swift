//
//  DisplaySettingsSheet.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI

struct DisplaySettingsSheet: View {

    // EVENT TIME
    @AppStorage("timeFontSize_v2")
    private var timeFontSize: Int = 13


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

<<<<<<< HEAD
    @AppStorage("timeline_start_hour")
    private var timelineStartHour: Int = 6
=======
    // ⭐ TIMELINE SETTINGS
    @AppStorage("timeline_start_hour")
    private var timelineStartHour: Int = 8
>>>>>>> 2f1e950 (feat(event): update event feature)

    @AppStorage("timeline_end_hour")
    private var timelineEndHour: Int = 22

<<<<<<< HEAD
    @State private var localTimeFontSize: Double = 13

    
=======
    
    private var isTimelineLayout: Bool {
        cardLayout == .timeline
    }

>>>>>>> 2f1e950 (feat(event): update event feature)
    
    
    var body: some View {
        NavigationStack {
            List {
                uiAccentSection
                eventCardLayoutSection
<<<<<<< HEAD
                if cardLayout == .timeline {
                       timelineHourSection
                   }
=======
                if isTimelineLayout {
                    timelineSettingsSection
                }

>>>>>>> 2f1e950 (feat(event): update event feature)
                eventTimeSection
                eventTimeFormatSection
                chatColorSection
            }
<<<<<<< HEAD
            .onAppear {
                let defaults = UserDefaults.standard

                // Nếu từng lưu Double → reset key
                if defaults.object(forKey: "timeFontSize") is Double {
                    defaults.removeObject(forKey: "timeFontSize")
                    timeFontSize = 13
                }

                // Clamp an toàn
                timeFontSize = max(11, min(timeFontSize, 25))

                if cardLayout == .timeline {
                    sanitizeTimelineHours()
                }
            }

            .onChange(of: timeFontSize) { _, newValue in
                if newValue < 11 {
                    timeFontSize = 11
                } else if newValue > 25 {
                    timeFontSize = 25
                }
            }


            .onChange(of: timelineStartHour) { _, newValue in
                if newValue >= timelineEndHour {
                    timelineEndHour = min(newValue + 1, 24)
                }
            }
            .onChange(of: timelineEndHour) { _, newValue in
                if newValue <= timelineStartHour {
                    timelineStartHour = max(newValue - 1, 0)
                }
            }

=======
            // ⭐ GUARD TIMELINE HOURS (SHEET LEVEL)
               .onChange(of: timelineStartHour) { _, _ in
                   clampTimelineHours()
               }
               .onChange(of: timelineEndHour) { _, _ in
                   clampTimelineHours()
               }
>>>>>>> 2f1e950 (feat(event): update event feature)
            .navigationTitle(
                String(localized: "display_settings_navigation_title")
            )
            .navigationBarTitleDisplayMode(.inline)
            
        }
    }

    private func clampTimelineHours() {
        // ⛔️ Absolute bounds
        timelineStartHour = min(max(timelineStartHour, 0), 23)
        timelineEndHour   = min(max(timelineEndHour, 1), 24)

        // ⛔️ Logical order
        if timelineStartHour >= timelineEndHour {
            timelineEndHour = min(timelineStartHour + 1, 24)
        }
    }

    private var timelineSettingsSection: some View {
        Section(
            String(localized: "display_settings_timeline_range")
        ) {
            VStack(alignment: .leading, spacing: 12) {

                // ===== START HOUR =====
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
                            set: { newValue in
                                let value = Int(newValue)
                                timelineStartHour = min(value, timelineEndHour - 1)
                            }
                        ),
                        in: 0...23,
                        step: 1
                    )
                }

                // ===== END HOUR =====
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
                            set: { newValue in
                                let value = Int(newValue)
                                timelineEndHour = max(value, timelineStartHour + 1)
                            }
                        ),
                        in: 1...24,
                        step: 1
                    )
                }

                Text(
                    String(localized: "timeline_range_hint")
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

<<<<<<< HEAD
    private func sanitizeTimelineHours() {

        // 1️⃣ Clamp tuyệt đối
        timelineStartHour = min(max(timelineStartHour, 0), 23)
        timelineEndHour   = min(max(timelineEndHour, 1), 24)

        // 2️⃣ Đảm bảo start < end
        if timelineStartHour >= timelineEndHour {
            timelineEndHour = min(timelineStartHour + 1, 24)
        }
    }

    
=======
>>>>>>> 2f1e950 (feat(event): update event feature)
    
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

    private var timelineHourSection: some View {
        Section(
            String(localized: "display_settings_timeline_hours")
        ) {

            // START HOUR
            Stepper(
                value: $timelineStartHour,
                in: 0...(timelineEndHour - 1)
            ) {
                Text(
                    String(
                        format: String(localized: "timeline_start_hour"),
                        timelineStartHour
                    )
                )
            }

            // END HOUR
            Stepper(
                value: $timelineEndHour,
                in: (timelineStartHour + 1)...24
            ) {
                Text(
                    String(
                        format: String(localized: "timeline_end_hour"),
                        timelineEndHour
                    )
                )
            }

            Text(
                String(localized: "timeline_hours_hint")
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
            HStack {
                Button {
                    timeFontSize -= 1
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)   // ⭐️ DÒNG QUAN TRỌNG
                .disabled(timeFontSize <= 11)

                Spacer()

                Text(
                    String(
                        format: String(localized: "display_settings_time_font_size"),
                        timeFontSize
                    )
                )
                .font(.body)

                Spacer()

                Button {
                    timeFontSize += 1
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)   // ⭐️ DÒNG QUAN TRỌNG
                .disabled(timeFontSize >= 25)
            }
            .contentShape(Rectangle()) // optional, giúp tap ổn định hơn
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
