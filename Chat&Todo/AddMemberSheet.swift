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
    @State private var showKickConfirm = false
    @State private var memberToKick: String?

    
    private var sortedParticipants: [String] {

        let myUid = Auth.auth().currentUser?.uid

        return event.participants.sorted { a, b in

            if a == myUid { return true }
            if b == myUid { return false }

            return a < b
        }
    }

    
    
    var body: some View {

        NavigationStack {
            Form {

                Section(String(localized: "add_member_user_uid")) {

                    TextField(String(localized: "add_member_enter_uid"), text: $uidText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    Button {
                        showHistory = true
                    } label: {
                        Label(
                            String(localized: "add_member_choose_from_history"),
                            systemImage: "clock.arrow.circlepath"
                        )
                            .font(.subheadline)
                    }
                }

                Section(String(localized: "add_member_current_members")) {

                    ForEach(sortedParticipants, id: \.self) { uid in

                        HStack {

                            Text(
                                eventManager.userNames[uid]
                                ?? eventManager.displayName(for: uid)
                            )

                            Spacer()

                            // ⭐ OWNER BADGE
                            if uid == event.owner {
                                Text(String(localized: "add_member_owner"))
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(6)
                            }

                            // ⭐ YOU BADGE
                            if uid == Auth.auth().currentUser?.uid {
                                Text(String(localized: "add_member_you"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if canKick(uid) {

                                Button {
                                    memberToKick = uid
                                    showKickConfirm = true
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.red)
                                        .disabled(isLoading)
                                        .opacity(isLoading ? 0.4 : 1)

                                }
                                .disabled(isLoading)

                            }

                            
                        }

                        .onAppear {
                            eventManager.fetchUserNameIfNeeded(uid: uid)
                        }
                    }
                }

                
                if let error {
                    Text(error)
                        .foregroundColor(.red)
                }
            }
            .navigationTitle(String(localized: "add_member_title"))
            .toolbar {

                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized:"cancel")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized:"add")) {
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
        .alert(
            String(localized: "add_member_remove_confirm_title"),
            isPresented: $showKickConfirm
        ) {

            Button(String(localized:"cancel", role: .cancel)) {}

            Button(String(localized:"remove", role: .destructive)) {

                if let uid = memberToKick {

                    eventManager.removeParticipant(
                        uid,
                        from: event
                    ) { success in

                        if success {
                            dismiss()   // 🔑 reload lại event khi mở lại
                        } else {
                            error = String(localized: "add_member_error_no_permission")
                        }

                        memberToKick = nil

                    }
                }
            }

        } message: {
            Text(String(localized: "add_member_remove_confirm_message"))

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

    private func canKick(_ uid: String) -> Bool {

        guard let myUid = Auth.auth().currentUser?.uid else {
            return false
        }

        // Không kick mình
        if uid == myUid { return false }

        // Owner kick được tất cả (trừ mình)
        if myUid == event.owner {
            return uid != myUid
        }

        // Admin: không kick owner
        if event.admins?.contains(myUid) == true {
            return uid != event.owner
        }


        return false
    }

    
    
    private func handleAdd() {

        guard let myUid = Auth.auth().currentUser?.uid else {
            error = String(localized: "add_member_error_not_logged_in")
            return
        }

        let newUid = uidText.trimmingCharacters(in: .whitespaces)

        guard !newUid.isEmpty else {
            error = String(localized: "add_member_error_invalid_uid")
            return
        }

        // ❌ Không add chính mình
        if newUid == myUid {
            error = String(localized: "add_member_error_already_in_event")
            return
        }

        // ❌ Tránh duplicate
        if event.participants.contains(newUid) {
            error = String(localized: "add_member_error_user_already_joined")
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
                    error = String(localized: "add_member_error_failed_add")
                }
            }
        }
    }
}
