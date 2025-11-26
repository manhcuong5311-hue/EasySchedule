//
//  updateNameView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/11/25.
//
import SwiftUI
import Combine

struct UpdateUserNameView: View {
    @EnvironmentObject var session: SessionStore
    @State private var newName: String = ""
    @State private var showSaved = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Nhập tên hiển thị mới") {
                TextField("Tên hiển thị", text: $newName)
                    .textInputAutocapitalization(.words)
            }

            Button("Lưu") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                session.updateUserName(trimmed) { ok in
                    if ok { showSaved = true }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle("Đổi tên hiển thị")
        .onAppear {
            newName = session.currentUserName
        }
        .alert("Đã lưu", isPresented: $showSaved) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Tên hiển thị đã được cập nhật.")
        }
    }
}
