//
//  PartnerUIComponents.swift
//  Easy Schedule
//
//  Shared building blocks for the Partner tab: one consistent card surface,
//  QR generation, and the invitation QR / share sheet.
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - Unified card surface

extension View {
    /// One consistent surface for every card/row on the Partner tab so the
    /// invite card, "Manage Access" row and partner rows all match.
    func partnerCardSurface(cornerRadius: CGFloat = 18) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

// MARK: - Invitation QR

enum InviteQRCode {

    /// Friendly text shared via the iOS share sheet.
    static func shareText(_ code: String) -> String {
        String(format: String(localized: "partner.invitation_share_text"), code)
    }

    /// A crisp QR image encoding the raw invitation code (scannable with the
    /// system Camera; the value is the code the other person types in).
    static func image(from string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Mini QR thumbnail

/// Small always-visible QR preview for the invitation card. The image is
/// generated once per code (`.task(id:)`, not every body pass) and sits on a
/// white tile so scanners can read it in dark mode too.
struct InviteQRThumbnail: View {
    let code: String
    var side: CGFloat = 74

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white)
            if let image {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(7)
            }
        }
        .frame(width: side, height: side)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10))
        )
        .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        .task(id: code) {
            image = InviteQRCode.image(from: code)
        }
    }
}

// MARK: - Invitation QR sheet

struct InvitationQRSheet: View {
    let code: String
    var accent: Color = .accentColor

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 22) {

            Text(String(localized: "partner.qr_sheet_title"))
                .font(.headline)
                .multilineTextAlignment(.center)
                .padding(.top, 28)

            if let img = InviteQRCode.image(from: code) {
                Image(uiImage: img)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 220, height: 220)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color.white)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
            }

            Text(code)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .tracking(4)
                .foregroundStyle(accent)

            ShareLink(item: InviteQRCode.shareText(code)) {
                Label(String(localized: "partner.share_code"),
                      systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(accent.opacity(0.12))
                    )
                    .foregroundStyle(accent)
            }
            .buttonStyle(.plain)
            .padding(.horizontal)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .presentationDetents([.medium])
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(12)
        }
    }
}
