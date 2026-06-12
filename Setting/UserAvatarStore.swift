//
//  UserAvatarStore.swift
//  Easy Schedule
//
//  Profile photos with a strict read/write budget:
//  • The image bytes live in Firebase Storage (avatars/{uid}.jpg). Firestore
//    only carries an Int `photoVersion` on the user doc the app already reads
//    for display names — so showing avatars costs no extra Firestore reads.
//  • Each device downloads a photo once per version, then serves it from a
//    disk + memory cache. Version bumps are learned by piggybacking on the
//    existing user-doc fetches (name resolver, profile load, preload).
//  • Changing a photo costs exactly 1 Storage upload + 1 Firestore field write.
//

import SwiftUI
import Combine
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

final class UserAvatarStore: ObservableObject {

    static let shared = UserAvatarStore()

    /// uid → photo, for everything currently on screen.
    @Published private(set) var images: [String: UIImage] = [:]

    /// Version of the file sitting in the disk cache, per uid.
    private var localVersions: [String: Int]
    /// Latest version seen on the server (piggybacked off user-doc reads).
    private var remoteVersions: [String: Int]

    private var inFlight: Set<String> = []
    /// Failed downloads are not retried until the next launch (no hot loops).
    private var failedThisSession: Set<String> = []

    private let kLocal  = "es_avatarLocalVersions_v1"
    private let kRemote = "es_avatarRemoteVersions_v1"

    private let dir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let d = base.appendingPathComponent("Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    private init() {
        localVersions  = (UserDefaults.standard.dictionary(forKey: kLocal)  as? [String: Int]) ?? [:]
        remoteVersions = (UserDefaults.standard.dictionary(forKey: kRemote) as? [String: Int]) ?? [:]
    }

    private func fileURL(_ uid: String) -> URL {
        dir.appendingPathComponent("\(uid).jpg")
    }

    private func persistVersions() {
        UserDefaults.standard.set(localVersions,  forKey: kLocal)
        UserDefaults.standard.set(remoteVersions, forKey: kRemote)
    }

    // MARK: - Remote version piggyback

    /// Feed this from any place that already fetched a `users/{uid}` document —
    /// it never triggers a Firestore read of its own.
    func noteProfileData(_ data: [String: Any]?, for uid: String) {
        guard let version = data?["photoVersion"] as? Int else { return }
        DispatchQueue.main.async {
            guard self.remoteVersions[uid] != version else { return }
            self.remoteVersions[uid] = version
            self.failedThisSession.remove(uid)
            if version <= 0 {
                // Photo removed → drop caches so the letter fallback returns.
                self.images[uid] = nil
                self.localVersions[uid] = nil
                try? FileManager.default.removeItem(at: self.fileURL(uid))
            }
            self.persistVersions()
        }
    }

    // MARK: - Lookup

    /// Memory → disk → (only if the server has a newer version) one Storage
    /// download. Safe to call from a view `body`; publishes when the photo lands.
    func image(for uid: String) -> UIImage? {
        guard (remoteVersions[uid] ?? 0) > 0 else { return nil }

        var available = images[uid]
        if available == nil,
           let data = try? Data(contentsOf: fileURL(uid)),
           let img = UIImage(data: data) {
            available = img
            DispatchQueue.main.async {
                if self.images[uid] == nil { self.images[uid] = img }
            }
        }

        if (localVersions[uid] ?? 0) < (remoteVersions[uid] ?? 0) {
            download(uid: uid)   // stale or missing → fetch once, show old copy meanwhile
        }
        return available
    }

    private func download(uid: String) {
        DispatchQueue.main.async {
            guard !self.inFlight.contains(uid),
                  !self.failedThisSession.contains(uid),
                  let target = self.remoteVersions[uid], target > 0 else { return }
            self.inFlight.insert(uid)

            Storage.storage().reference(withPath: "avatars/\(uid).jpg")
                .getData(maxSize: 2 * 1024 * 1024) { data, error in
                    DispatchQueue.main.async {
                        self.inFlight.remove(uid)
                        guard let data, let img = UIImage(data: data) else {
                            self.failedThisSession.insert(uid)
                            if let error {
                                print("⚠️ avatar download \(uid):", error.localizedDescription)
                            }
                            return
                        }
                        try? data.write(to: self.fileURL(uid))
                        self.localVersions[uid] = target
                        self.images[uid] = img
                        self.persistVersions()
                    }
                }
        }
    }

    // MARK: - Own avatar (upload / remove)

    /// One Storage upload + one Firestore field write. Local caches update
    /// immediately, so the new photo shows everywhere without any read-back.
    func uploadMyAvatar(_ raw: UIImage, uid: String, completion: @escaping (Bool) -> Void) {
        let prepared = Self.squareThumbnail(raw, side: 256)
        guard let data = prepared.jpegData(compressionQuality: 0.75) else {
            completion(false)
            return
        }
        let version = Int(Date().timeIntervalSince1970)
        let meta = StorageMetadata()
        meta.contentType = "image/jpeg"

        Storage.storage().reference(withPath: "avatars/\(uid).jpg")
            .putData(data, metadata: meta) { _, error in
                if let error {
                    print("❌ avatar upload:", error.localizedDescription)
                    DispatchQueue.main.async { completion(false) }
                    return
                }
                Firestore.firestore().collection("users").document(uid)
                    .setData(["photoVersion": version], merge: true) { err in
                        DispatchQueue.main.async {
                            if err == nil {
                                try? data.write(to: self.fileURL(uid))
                                self.images[uid] = prepared
                                self.localVersions[uid] = version
                                self.remoteVersions[uid] = version
                                self.failedThisSession.remove(uid)
                                self.persistVersions()
                            } else {
                                print("❌ photoVersion write:", err!.localizedDescription)
                            }
                            completion(err == nil)
                        }
                    }
            }
    }

    func removeMyAvatar(uid: String, completion: @escaping (Bool) -> Void) {
        Storage.storage().reference(withPath: "avatars/\(uid).jpg").delete { _ in }
        Firestore.firestore().collection("users").document(uid)
            .setData(["photoVersion": 0], merge: true) { err in
                DispatchQueue.main.async {
                    if err == nil {
                        self.images[uid] = nil
                        self.localVersions[uid] = nil
                        self.remoteVersions[uid] = 0
                        try? FileManager.default.removeItem(at: self.fileURL(uid))
                        self.persistVersions()
                    }
                    completion(err == nil)
                }
            }
    }

    var hasOwnPhoto: Bool {
        guard let uid = Auth.auth().currentUser?.uid else { return false }
        return (remoteVersions[uid] ?? 0) > 0
    }

    /// Center-crop to a square and scale down — keeps uploads at ~15-30 KB.
    private static func squareThumbnail(_ image: UIImage, side: CGFloat) -> UIImage {
        let s = min(image.size.width, image.size.height)
        guard s > 0 else { return image }
        let scaleFactor = side / s
        let drawSize = CGSize(width: image.size.width * scaleFactor,
                              height: image.size.height * scaleFactor)
        let drawOrigin = CGPoint(x: -(image.size.width - s) / 2 * scaleFactor,
                                 y: -(image.size.height - s) / 2 * scaleFactor)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side),
                                       format: format).image { _ in
            image.draw(in: CGRect(origin: drawOrigin, size: drawSize))
        }
    }
}

// MARK: - AvatarView

/// Circular avatar: the user's photo when set (served from cache), otherwise
/// the caller's existing letter/monogram fallback — so each screen keeps its
/// own fallback styling.
struct AvatarView<Fallback: View>: View {
    let uid: String
    var size: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    @ObservedObject private var store = UserAvatarStore.shared

    var body: some View {
        if let photo = store.image(for: uid) {
            Image(uiImage: photo)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            fallback()
        }
    }
}
