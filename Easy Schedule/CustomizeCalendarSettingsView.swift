//
//  CustomizeCalendarSettingsView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 7/12/25.
//
import SwiftUI
import Combine

struct CustomizeCalendarSettingsView: View {
    @Environment(\.dismiss) var dismiss

    @AppStorage("showOwnerLabel") private var showOwnerLabel: Bool = true
    @AppStorage("timeFontSize") private var timeFontSize: Double = 13.0
    @AppStorage("timeColorHex") private var timeColorHex: String = "#007AFF"

    // local Color để dùng ColorPicker, sync về hex khi thay đổi
    @State private var timeColor: Color = .blue

    init() {
        // nothing here - state sẽ được khởi tạo trong onAppear
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Hiển thị")) {
                    Toggle("Hiện nhãn 'Lịch của tôi'", isOn: $showOwnerLabel)
                }

                Section(header: Text("Giờ hiển thị")) {
                    HStack {
                        Text("Kích thước")
                        Spacer()
                        Text("\(Int(timeFontSize)) pt")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $timeFontSize, in: 10...22, step: 1)

                    ColorPicker("Màu giờ", selection: $timeColor)
                        .onChange(of: timeColor) {
                            if let hex = timeColor.toHex() {
                                timeColorHex = hex
                            }
                        }

                }

                Section {
                    Button("Đóng") {
                        dismiss()
                    }
                }
            }
            .navigationTitle("Tùy chỉnh hiển thị")
            .onAppear {
                // khởi tạo ColorPicker từ hex lưu trong UserDefaults
                timeColor = Color(hex: timeColorHex)
            }
        }
    }
}
