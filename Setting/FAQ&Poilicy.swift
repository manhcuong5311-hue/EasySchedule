//
//  FAQ.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 2/1/26.
//
import SwiftUI

struct FAQView: View {

    @State private var expandedSection: String? = nil

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
                expandedSection: $expandedSection
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
                expandedSection: $expandedSection
            )





            FAQSectionView(
                id: "notifications",
                titleKey: "faq_section_notifications",
                questions: [
                    ("faq_7_q", "faq_7_a")
                ],
                expandedSection: $expandedSection
            )
        }
        .navigationTitle(String(localized: "faq"))
    }
}
struct FAQSectionView: View {
    let id: String
    let titleKey: String
    let questions: [(String, String)]

    @Binding var expandedSection: String?

    var body: some View {
        Section {
            Button {
                withAnimation(.easeInOut) {
                    expandedSection = expandedSection == id ? nil : id
                }
            } label: {
                HStack {
                    Text(LocalizedStringKey(titleKey))
                        .font(.headline)

                    Spacer()

                    Image(systemName: expandedSection == id ? "chevron.down" : "chevron.right")
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }

            if expandedSection == id {
                ForEach(questions, id: \.0) { q, a in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(q))
                            .font(.subheadline)
                            .bold()

                        Text(LocalizedStringKey(a))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
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
                .font(.headline)

            Text(LocalizedStringKey(aKey))
                .font(.body)
                .foregroundColor(.secondary)
        }
    }
}




// MARK: - Privacy Policy View
struct PrivacyPolicyView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(String(localized: "privacy_title"))
                        .font(.headline)
                    Text(String(localized: "privacy_text"))
                        .font(.body)
                    Link(String(localized: "privacy_policy_link"), destination: URL(string: "https://manhcuong5311-hue.github.io/easyschedule-privacy/")!)
                }
                .padding()
            }
            .navigationTitle(String(localized: "privacy_nav_title"))
        }
    }
}


