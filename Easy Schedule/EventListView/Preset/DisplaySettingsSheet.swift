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
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {
                uiAccentSection
                chatColorSection
            }
            .scrollContentBackground(.hidden)
            .background(AppBackground.settings(colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: "display_settings_navigation_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                cardLayoutRaw = EventCardLayout.timeline.rawValue
            }
        }
        .tint(uiAccent.color)
    }

    // MARK: - Sections

    private var uiAccentSection: some View {
        Section(String(localized: "display_settings_ui_accent")) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(UIAccentPreset.allCases, id: \.rawValue) { preset in
                        DisplayColorSwatch(
                            color: Color(hex: preset.hex),
                            isSelected: uiAccent.hex == preset.hex,
                            title: preset.title
                        ) {
                            uiAccent.set(hex: preset.hex)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 2)
            }
        }
        .listRowBackground(AppBackground.card(colorScheme))
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
        .listRowBackground(AppBackground.card(colorScheme))
    }

}


struct ChatColorPresetPicker: View {

    let title: String
    @Binding var selectedRaw: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(ChatColorPreset.allCases, id: \.rawValue) { preset in
                        DisplayColorSwatch(
                            color: Color(hex: preset.hex),
                            isSelected: selectedRaw == preset.rawValue,
                            title: preset.title
                        ) {
                            selectedRaw = preset.rawValue
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 2)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Round color chip: selected = ring with a small gap + checkmark.
private struct DisplayColorSwatch: View {
    let color: Color
    let isSelected: Bool
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
                .padding(3)
                .overlay(
                    Circle()
                        .stroke(isSelected ? color : Color.clear, lineWidth: 2)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}
