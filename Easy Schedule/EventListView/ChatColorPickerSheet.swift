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
                Section("Your messages") {
                    ForEach(ChatColorPreset.allCases, id: \.rawValue) { preset in
                        HStack {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 20, height: 20)

                            Text(preset.title)

                            Spacer()

                            if myPresetRaw == preset.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            myPresetRaw = preset.rawValue
                        }
                    }
                }

                Section("Other messages") {
                    ForEach(ChatColorPreset.allCases, id: \.rawValue) { preset in
                        HStack {
                            Circle()
                                .fill(Color(hex: preset.hex))
                                .frame(width: 20, height: 20)

                            Text(preset.title)

                            Spacer()

                            if otherPresetRaw == preset.rawValue {
                                Image(systemName: "checkmark")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            otherPresetRaw = preset.rawValue
                        }
                    }
                }
            }
            .navigationTitle("Chat colors")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

