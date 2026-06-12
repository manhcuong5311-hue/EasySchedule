//
//  updateNameView.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 26/11/25.
//
import SwiftUI
import Combine
import PhotosUI

struct UpdateUserNameView: View {
    @EnvironmentObject var session: SessionStore
    @EnvironmentObject var uiAccent: UIAccentStore
    @State private var newName: String = ""
    @State private var showSaved = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var network: NetworkMonitor
    @State private var showOfflineAlert = false
    @State private var showEmptyNameAlert = false

    @ObservedObject private var avatars = UserAvatarStore.shared
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false


    var body: some View {
        Form {

            if !network.isOnline {
                    OfflineBannerView()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }

            photoSection

            Section(String(localized: "enter_new_display_name")) {
                TextField(String(localized: "display_name"), text: $newName)
                    .textInputAutocapitalization(.words)
            }

            Button(String(localized: "save")) {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)

                guard !trimmed.isEmpty else {
                    showEmptyNameAlert = true
                    return
                }

                session.updateUserName(trimmed) { ok in
                    if ok { showSaved = true }
                }

            }
            .buttonStyle(.borderedProminent)
            .disabled(!network.isOnline)
        }

        .navigationTitle(String(localized: "change_display_name"))
        .onAppear {
            let name = session.currentUserName
            newName = (name == String(localized: "no_name")) ? "" : name
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
        .alert(
            String(localized: "invalid_name"),
            isPresented: $showEmptyNameAlert
        ) {
            Button(String(localized: "ok"), role: .cancel) {}
        } message: {
            Text(String(localized: "name_cannot_be_empty"))
        }

    }

    // MARK: - Profile photo

    private var photoSection: some View {
        Section(String(localized: "profile_photo")) {
            HStack(spacing: 16) {
                AvatarView(uid: session.currentUserId ?? "", size: 64) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [uiAccent.color, uiAccent.color.opacity(0.75)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 64, height: 64)
                        Text(nameInitial)
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label(
                            isUploadingPhoto
                                ? String(localized: "photo_uploading")
                                : String(localized: "change_photo"),
                            systemImage: "camera.fill"
                        )
                        .font(.subheadline.weight(.medium))
                    }
                    .disabled(isUploadingPhoto || !network.isOnline)

                    if avatars.hasOwnPhoto, !isUploadingPhoto {
                        Button(role: .destructive) {
                            guard let uid = session.currentUserId else { return }
                            avatars.removeMyAvatar(uid: uid) { _ in }
                        } label: {
                            Label(String(localized: "remove_photo"), systemImage: "trash")
                                .font(.subheadline)
                        }
                        .disabled(!network.isOnline)
                    }
                }
            }
            .padding(.vertical, 4)
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            isUploadingPhoto = true
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = UIImage(data: data),
                      let uid = session.currentUserId else {
                    await MainActor.run {
                        isUploadingPhoto = false
                        photoItem = nil
                    }
                    return
                }
                await MainActor.run {
                    UserAvatarStore.shared.uploadMyAvatar(image, uid: uid) { _ in
                        isUploadingPhoto = false
                        photoItem = nil
                    }
                }
            }
        }
    }

    private var nameInitial: String {
        let trimmed = session.currentUserName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "?" : trimmed.prefix(1).uppercased()
    }
}
