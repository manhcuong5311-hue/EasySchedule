//
//  ChatColorPickerSheet.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 22/1/26.
//
import SwiftUI

struct ChatColorPickerSheet: View {

    @AppStorage("chat_my_preset")
    private var myPresetRaw: String = ChatColorPreset.blue.rawValue

    @AppStorage("chat_other_preset")
    private var otherPresetRaw: String = ChatColorPreset.graphite.rawValue

    var body: some View {
        NavigationStack {
            List {

                Section(
                    String(localized: "chat_color_section_my_messages")
                ) {
                    ForEach(ChatColorPreset.allCases, id: \.rawValue) { preset in
                        colorRow(
                            preset: preset,
                            selected: myPresetRaw == preset.rawValue
                        ) {
                            myPresetRaw = preset.rawValue
                        }
                    }
                }

                Section(
                    String(localized: "chat_color_section_other_messages")
                ) {
                    ForEach(ChatColorPreset.allCases, id: \.rawValue) { preset in
                        colorRow(
                            preset: preset,
                            selected: otherPresetRaw == preset.rawValue
                        ) {
                            otherPresetRaw = preset.rawValue
                        }
                    }
                }
            }
            .navigationTitle(
                String(localized: "chat_color_navigation_title")
            )
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Row
    @ViewBuilder
    private func colorRow(
        preset: ChatColorPreset,
        selected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {

        HStack {
            Circle()
                .fill(Color(hex: preset.hex))
                .frame(width: 20, height: 20)

            Text(preset.title)

            Spacer()

            if selected {
                Image(systemName: "checkmark")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }
}
