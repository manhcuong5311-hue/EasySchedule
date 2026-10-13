//
//  FAQ.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

struct FAQView: View {

    @State private var expandedSection: String? = nil
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        List {

            FAQSectionView(
                id: "sharing",
                titleKey: "faq_section_sharing",
                questions: [
                    // Core concepts
                    ("faq_1_q", "faq_1_a"),
                    ("faq_2_q", "faq_2_a"),
                    ("faq_3_q", "faq_3_a"),
                    ("faq_8_q", "faq_8_a"),

                    // ⭐ NEW — Busy Hours explanation
                    ("faq_busy_hours_q", "faq_busy_hours_a"),

                    // Calendar Help
                    ("my_calendar_help_section_calendar_title",
                     "my_calendar_help_section_calendar_desc"),
                    ("my_calendar_help_section_offday_title",
                     "my_calendar_help_section_offday_desc"),
                    ("my_calendar_help_section_share_title",
                     "my_calendar_help_section_share_desc"),

                    // Events Help
                    ("events_help_segment_title",
                     "events_help_segment_desc"),
                    ("events_help_search_title",
                     "events_help_search_desc"),
                    ("events_help_weekgroup_title",
                     "events_help_weekgroup_desc"),

                    // General Help
                    ("help_section_paste_uid_title",
                     "help_section_paste_uid_desc"),
                    ("help_section_history_title",
                     "help_section_history_desc"),
                    ("help_section_created_for_others_title",
                     "help_section_created_for_others_desc"),
                    ("help_section_access_title",
                     "help_section_access_desc")
                ],
                expandedSection: $expandedSection,
                icon: "person.2.fill",
                color: .blue
            )




            FAQSectionView(
                id: "limits",
                titleKey: "faq_section_limits",
                questions: [
                    // Existing limits
                    ("faq_4_q", "faq_4_a"),
                    ("faq_5_q", "faq_5_a"),
                    ("faq_6_q", "faq_6_a"),
                    ("faq_members_limit_q", "faq_members_limit_a"),
                    ("faq_chat_limit_q", "faq_chat_limit_a"),
                    ("faq_todo_limit_q", "faq_todo_limit_a"),

                    // From Calendar Help
                    ("my_calendar_help_section_conflict_title",
                     "my_calendar_help_section_conflict_desc"),

                    // From Events Help
                    ("events_help_delete_title",
                     "events_help_delete_desc"),
                    ("events_help_chat_title",
                     "events_help_chat_desc"),
                    ("my_calendar_help_section_todo_title",
                     "my_calendar_help_section_todo_desc"),

                    // ⬇️ FROM GENERAL HELP SHEET
                    ("help_section_add_event_title",
                     "help_section_add_event_desc")
                ],
                expandedSection: $expandedSection,
                icon: "crown.fill",
                color: .orange
            )





            FAQSectionView(
                id: "notifications",
                titleKey: "faq_section_notifications",
                questions: [
                    ("faq_7_q", "faq_7_a")
                ],
                expandedSection: $expandedSection,
                icon: "bell.fill",
                color: .red
            )
        }
        .scrollContentBackground(.hidden)
        .background(AppBackground.settings(colorScheme).ignoresSafeArea())
        .tint(uiAccent.color)
        .navigationTitle(SettingsText.plain(String(localized: "faq")))
        .navigationBarTitleDisplayMode(.inline)
    }
}
struct FAQSectionView: View {
    let id: String
    let titleKey: String
    let questions: [(String, String)]

    @Binding var expandedSection: String?

    /// Leading icon tile for the section header row.
    var icon: String = "questionmark"
    var color: Color = .gray

    @Environment(\.colorScheme) private var colorScheme

    private var isExpanded: Bool { expandedSection == id }

    var body: some View {
        Section {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    expandedSection = isExpanded ? nil : id
                }
            } label: {
                HStack(spacing: 12) {
                    SettingsIconTile(systemName: icon, color: color)

                    Text(LocalizedStringKey(titleKey))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    Text(verbatim: "\(questions.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(.vertical, 2)
                .contentShape(Rectangle())
            }

            if isExpanded {
                ForEach(questions, id: \.0) { q, a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(q))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(LocalizedStringKey(a))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .listRowBackground(AppBackground.card(colorScheme))
    }
}

struct FAQItem: View {
    let qKey: String
    let aKey: String

    init(_ q: String, _ a: String) {
        self.qKey = q
        self.aKey = a
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(qKey))
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)

            Text(LocalizedStringKey(aKey))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }
}




// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    @EnvironmentObject var uiAccent: UIAccentStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss

    private let policyURL = URL(string: "https://manhcuong5311-hue.github.io/easyschedule-privacy/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {

                    // Heading card
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 12) {
                            Image(systemName: "hand.raised.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 40, height: 40)
                                .background(
                                    RoundedRectangle(cornerRadius: AppRadius.chip, style: .continuous)
                                        .fill(uiAccent.color.gradient)
                                )
                                .accessibilityHidden(true)

                            Text(SettingsText.plain(String(localized: "privacy_title")))
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Divider()

                        policyBody
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                            .fill(AppBackground.card(colorScheme))
                    )

                    // Full policy on the web
                    Link(destination: policyURL) {
                        HStack(spacing: 10) {
                            Image(systemName: "safari")
                                .font(.system(size: 16, weight: .semibold))
                            Text(SettingsText.plain(String(localized: "privacy_policy_link")))
                                .font(.subheadline.weight(.semibold))
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 8)
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(uiAccent.color)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                .fill(uiAccent.color.opacity(0.12))
                        )
                    }
                }
                .padding(16)
            }
            .background(AppBackground.settings(colorScheme).ignoresSafeArea())
            .navigationTitle(String(localized: "privacy_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "done")) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .tint(uiAccent.color)
    }

    /// "privacy_text" rendered paragraph by paragraph; "• " lines get a hanging indent.
    private var policyBody: some View {
        let lines = String(localized: "privacy_text")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        return VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if line.hasPrefix("•") {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Circle()
                            .fill(uiAccent.color)
                            .frame(width: 5, height: 5)
                            .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 1 }
                        Text(line.dropFirst().trimmingCharacters(in: .whitespaces))
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(line)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.subheadline)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
    }
}


