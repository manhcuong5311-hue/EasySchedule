import SwiftUI
import FirebaseAuth

struct AddPartnerSheet: View {
    
    @EnvironmentObject var eventManager: EventManager
    @Binding var isPresented: Bool
    
    @State private var input: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var successMessage: String?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                
                // MARK: Header
                VStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: 42))
                        .foregroundColor(.accentColor)
                    
                    Text(String(localized: "partner.add_title"))
                        .font(.system(size: 22, weight: .bold))
                    
                    Text(String(localized: "partner.enter_uid_or_link"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
                
                
                // MARK: Input Card
                VStack(spacing: 14) {
                    
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundColor(.secondary)
                        
                        TextField(String(localized: "partner.paste_uid_or_link"), text: $input)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                    )
                    
                    
                    // MARK: Error / Success
                    if let error = errorMessage {
                        Label(error, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    
                    if let success = successMessage {
                        Label(success, systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                            .transition(.opacity)
                    }
                    
                    
                    // MARK: Load Button
                    Button {
                        loadPartner()
                    } label: {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .scaleEffect(0.9)
                            }
                            
                            Text(String(localized: "partner.load"))
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .cornerRadius(16)
                    .disabled(isLoading || input.trimmingCharacters(in: .whitespaces).isEmpty)
                    
                    
                    // MARK: Helper Text
                    Text(String(localized: "partner.ask_for_uid"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 22))
                
                
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.close")) {
                        isPresented = false
                    }
                }
            }
        }
    }
}

extension AddPartnerSheet {
    
    private func loadPartner() {
        
        errorMessage = nil
        successMessage = nil
        
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty else {
            errorMessage = String(localized: "uid_required")
            return
        }
        
        guard let me = Auth.auth().currentUser?.uid else {
            errorMessage = String(localized: "login_required")
            return
        }
        
        isLoading = true
        
        // ⭐ NEW: resolve UID or Invitation Code
        eventManager.resolveUid(from: trimmed) { resolvedUid in
            
            DispatchQueue.main.async {
                
                guard let uid = resolvedUid else {
                    self.isLoading = false
                    self.errorMessage = String(localized: "uid_not_found")
                    return
                }
                
                // Không add chính mình
                if uid == me {
                    self.isLoading = false
                    self.errorMessage = String(localized: "cannot_add_self")
                    return
                }
                
                // Validate user tồn tại
                self.eventManager.validateUserExists(uid: uid) { exists in
                    
                    DispatchQueue.main.async {
                        
                        guard exists else {
                            self.isLoading = false
                            self.errorMessage = String(localized: "uid_not_found")
                            return
                        }
                        
                    
                        // ⭐ THÊM: Ghi 2 chiều lên Firestore
                        self.eventManager.addSharedLink(for: me, otherUid: uid)   // A có B
                        self.eventManager.addSharedLink(for: uid, otherUid: me)   // B có A ← QUAN TRỌNG
                        
                        // Check Access
                        AccessService.shared.isAllowed(ownerUid: uid, otherUid: me) { allowed in
                            
                            DispatchQueue.main.async {
                                self.isLoading = false
                                
                                if allowed {
                                    self.successMessage = String(localized: "connected_success")
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                                        self.isPresented = false
                                    }
                                    
                                } else {
                                    
                                    let requesterName =
                                        self.eventManager.userNames[me] ?? me
                                    
                                    AccessService.shared.createRequest(
                                        owner: uid,
                                        requester: me,
                                        requesterName: requesterName
                                    )
                                    
                                    self.successMessage =
                                        String(localized: "request_not_allowed_sent")
                                    
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                                        self.isPresented = false
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    private func isValidUIDFormat(_ uid: String) -> Bool {
        let regex = "^[A-Za-z0-9_-]{20,}$"
        return NSPredicate(format: "SELF MATCHES %@", regex)
            .evaluate(with: uid)
    }
}


struct InvitationCodeCard: View {
    
    @EnvironmentObject var eventManager: EventManager
    
    var body: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            
            Text(String(localized: "partner.invitation_title"))
                .font(.headline)
            
            if let code = eventManager.invitationCode {
                
                HStack {
                    
                    Text(code)
                        .font(.system(size: 28, weight: .bold, design: .monospaced))
                        .tracking(4)
                    
                    Spacer()
                    
                    Button {
                        UIPasteboard.general.string = code
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                }
                
                Text(String(localized: "partner.invitation_subtitle"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
            } else {
                
                ProgressView()
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 5)
    }
}
