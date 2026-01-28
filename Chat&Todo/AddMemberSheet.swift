//
//  AddMemberSheet.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 28/1/26.
//

import SwiftUI
import FirebaseAuth

struct AddMemberSheet: View {

    let event: CalendarEvent

    @EnvironmentObject var eventManager: EventManager
    @Environment(\.dismiss) var dismiss

    @State private var uidText = ""
    @State private var isLoading = false
    @State private var error: String?
    @State private var showHistory = false

    var body: some View {

        NavigationStack {
            Form {

                Section("User UID") {

                    TextField("Enter UID", text: $uidText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        showHistory = true
                    } label: {
                        Label("Choose from history", systemImage: "clock.arrow.circlepath")
                            .font(.subheadline)
                    }
                }


                if let error {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle("Add member")
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        handleAdd()
                    }
                    .disabled(uidText.isEmpty || isLoading)
                }
            }
        }
        
        .sheet(isPresented: $showHistory) {

            NavigationStack {
                HistoryLinksView { uid in

                    uidText = uid    
                    showHistory = false

                }
                .environmentObject(eventManager)
            }
        }

    }
    
    private func addMember(_ uid: String) {

        guard !uid.isEmpty else { return }

        // Không add trùng
        if event.participants.contains(uid) {
            return
        }

        eventManager.addMember(
            eventId: event.id,
            userId: uid
        )
    }

    private func handleAdd() {

        guard let myUid = Auth.auth().currentUser?.uid else {
            error = "Not logged in"
            return
        }

        let newUid = uidText.trimmingCharacters(in: .whitespaces)

        guard !newUid.isEmpty else {
            error = "Invalid UID"
            return
        }

        // ❌ Không add chính mình
        if newUid == myUid {
            error = "You are already in this event"
            return
        }

        // ❌ Tránh duplicate
        if event.participants.contains(newUid) {
            error = "User already joined"
            return
        }

        isLoading = true
        error = nil

        eventManager.addParticipant(newUid, to: event) { success in

            DispatchQueue.main.async {

                isLoading = false

                if success {
                    dismiss()
                } else {
                    error = "Failed to add member"
                }
            }
        }
    }
}
