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
    @AppStorage("timeColorHex") private var timeColorHex: String = "#007AFF"

    // CHAT COLOR
    @AppStorage("chat_my_preset")
    private var myPresetRaw: String = ChatColorPreset.blue.rawValue

    @AppStorage("chat_other_preset")
    private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue

    @AppStorage("event_time_display_mode")
    private var timeDisplayModeRaw: String = EventTimeDisplayMode.startTime.rawValue

    private var timeDisplayMode: EventTimeDisplayMode {
        EventTimeDisplayMode(rawValue: timeDisplayModeRaw) ?? .startTime
    }

    @EnvironmentObject var uiAccent: UIAccentStore


    var body: some View {
        NavigationStack {
            List {

                // =====================
                // EVENT DISPLAY
                // =====================
                Section("Event time") {

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Time font size: \(Int(timeFontSize))")
                            .font(.caption)

                        Slider(
                            value: $timeFontSize,
                            in: 11...25,
                            step: 1
                        )
                    }
                    .padding(.vertical, 4)

                }

                // =====================
                // UI THEME
                // =====================
                Section("App theme") {

                    VStack(alignment: .leading, spacing: 8) {

                        Text("Accent color")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 14) {
                                ForEach(UIAccentPreset.allCases, id: \.rawValue) { preset in
                                    Circle()
                                        .fill(Color(hex: preset.hex))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Circle()
                                                .stroke(
                                                    uiAccent.hex == preset.hex
                                                    ? Color.primary
                                                    : Color.clear,
                                                    lineWidth: 2
                                                )
                                        )
                                        .overlay(
                                            // subtle inner highlight for dark mode
                                            Circle()
                                                .stroke(
                                                    Color.white.opacity(0.15),
                                                    lineWidth: 0.5
                                                )
                                        )
                                        .onTapGesture {
                                            uiAccent.set(hex: preset.hex)
                                        }

                                        .accessibilityLabel(preset.title)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                
                Section("Event time format") {
                    ForEach(EventTimeDisplayMode.allCases, id: \.rawValue) { mode in
                        HStack {
                            Text(mode.title)
                            Spacer()
                            if timeDisplayModeRaw == mode.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            timeDisplayModeRaw = mode.rawValue
                        }
                    }
                }

                // =====================
                // CHAT COLORS
                // =====================
                Section("Chat colors") {

                    ChatColorPresetPicker(
                        title: "Your messages",
                        selectedRaw: $myPresetRaw
                    )

                    ChatColorPresetPicker(
                        title: "Other messages",
                        selectedRaw: $otherPresetRaw
                    )
                }
            }
            .navigationTitle("Display settings")
            .navigationBarTitleDisplayMode(.inline)
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
