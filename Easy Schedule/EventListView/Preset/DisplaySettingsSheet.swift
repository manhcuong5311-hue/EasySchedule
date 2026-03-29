//
//  DisplaySettingsSheet.swift
//  Easy Schedule
//
import SwiftUI

struct DisplaySettingsSheet: View {

    // MARK: - Chat Color
    @AppStorage("chat_my_preset")
    private var myPresetRaw: String = ChatColorPreset.blue.rawValue

    @AppStorage("chat_other_preset")
    private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue

    // Force layout to timeline (write once, keep in sync)
    @AppStorage("event_card_layout")
    private var cardLayoutRaw: String = EventCardLayout.timeline.rawValue

    // MARK: - Env
    @EnvironmentObject var uiAccent: UIAccentStore

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                uiAccentSection
                chatColorSection
            }
            .navigationTitle(String(localized: "display_settings_navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                cardLayoutRaw = EventCardLayout.timeline.rawValue
            }
        }
    }

    // MARK: - Sections

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
                            .onTapGesture { uiAccent.set(hex: preset.hex) }
                    }
                }
            }
        }
    }

    // MARK: - Helpers

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
                            .onTapGesture { selectedRaw = preset.rawValue }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}
