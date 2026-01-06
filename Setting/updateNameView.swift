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
    @EnvironmentObject var network: NetworkMonitor
    @State private var showOfflineAlert = false

    
    var body: some View {
        Form {

            if !network.isOnline {
                    OfflineBannerView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

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
            .disabled(!network.isOnline)
        }

        .navigationTitle(String(localized: "change_display_name"))
        .onAppear {
            newName = session.currentUserName
        }
        .alert( String(localized: "saved"), isPresented: $showSaved) {
            Button(String(localized:"ok")) {
                dismiss()
            }
        } message: {
            Text(String(localized: "display_name_updated"))
        }
        .alert(String(localized: "no_internet"), isPresented: $showOfflineAlert) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "check_connection"))
        }

    }
}
