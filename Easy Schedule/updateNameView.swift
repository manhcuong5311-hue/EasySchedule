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
            Section(String(localized: "enter_new_display_name")) {
                TextField(String(localized: "display_name"), text: $newName)
                    .textInputAutocapitalization(.words)
            }

            Button(String(localized: "save")) {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                session.updateUserName(trimmed) { ok in
                    if ok { showSaved = true }
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .navigationTitle(String(localized: "change_display_name"))
        .onAppear {
            newName = session.currentUserName
        }
        .alert( String(localized: "saved"), isPresented: $showSaved) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(String(localized: "display_name_updated"))
        }
    }
}
