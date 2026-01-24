import SwiftUI

struct EmptyEventsStateView: View {

    let onAdd: () -> Void
    let onShare: () -> Void
    let onBookPartner: () -> Void

    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 18) {

            // 🧠 EMPTY STATE COPY
            VStack(spacing: 6) {
                Text(String(localized: "empty_events_title"))
                    .font(.title3.weight(.semibold))

                Text(String(localized: "empty_events_subtitle"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            // ➕ ADD EVENT (SELF)
            Button(action: onAdd) {
                actionRow(
                    icon: "plus.circle.fill",
                    title: String(localized: "empty_events_add_title"),
                    subtitle: String(localized: "empty_events_add_subtitle")
                )
            }

            // 🔗 SHARE CALENDAR
            Button(action: onShare) {
                actionRow(
                    icon: "link.circle.fill",
                    title: String(localized: "empty_events_share_title"),
                    subtitle: String(localized: "empty_events_share_subtitle")
                )
            }

            // 🤝 BOOK PARTNER
            Button(action: onBookPartner) {
                actionRow(
                    icon: "person.2.circle.fill",
                    title: String(localized: "empty_events_partner_title"),
                    subtitle: String(localized: "empty_events_partner_subtitle")
                )
            }
        }
        .padding(.top, 24)
        .padding(.horizontal)
    }

    // MARK: - Row UI
    private func actionRow(
        icon: String,
        title: String,
        subtitle: String
    ) -> some View {

        HStack(spacing: 14) {

            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundColor(uiAccent.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(14)
        .shadow(
            color: colorScheme == .dark
                ? Color.white.opacity(0.08)
                : Color.black.opacity(0.08),
            radius: 4,
            y: 2
        )
    }
}
