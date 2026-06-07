//
//  WidgetEsBundle.swift
//  WidgetEs (widget target)
//
//  Điểm vào @main của extension — gom Widget + Live Activity.
//  (Control widget mẫu "WidgetEsControl" được giữ trong project nhưng không
//   liệt kê ở đây vì chưa dùng tới.)
//
import WidgetKit
import SwiftUI

@main
struct WidgetEsBundle: WidgetBundle {
    var body: some Widget {
        NextEventWidget()
        ScheduleLiveActivity()
    }
}

// MARK: - Chuỗi widget đa ngôn ngữ (en / vi / ja / ko)
// Tự gói gọn để hiển thị đúng 4 ngôn ngữ ngay, không phải đụng tới
// Localizable.xcstrings (3600+ key). Sau này có thể migrate vào catalog.
enum WidgetStrings {
    static var now: String        { pick(en: "NOW",  vi: "ĐANG DIỄN RA", ja: "進行中",   ko: "진행 중") }
    static var next: String       { pick(en: "NEXT", vi: "TIẾP THEO",    ja: "次の予定", ko: "다음 일정") }
    static var endsIn: String     { pick(en: "ends in", vi: "còn", ja: "終了まで", ko: "종료까지") }
    static var startsIn: String   { pick(en: "in",      vi: "sau", ja: "開始まで", ko: "시작까지") }
    static var noEvents: String   { pick(en: "No events", vi: "Không có lịch", ja: "予定なし", ko: "일정 없음") }
    static var free: String       { pick(en: "All clear", vi: "Đang rảnh", ja: "予定なし", ko: "여유 시간") }
    static var today: String      { pick(en: "Today", vi: "Hôm nay", ja: "今日", ko: "오늘") }
    static var widgetName: String { pick(en: "Next Event", vi: "Việc tiếp theo", ja: "次の予定", ko: "다음 일정") }
    static var widgetDesc: String {
        pick(en: "Your current or upcoming event at a glance.",
             vi: "Việc đang diễn ra hoặc sắp tới, xem nhanh.",
             ja: "進行中・次の予定をひと目で。",
             ko: "진행 중이거나 다음 일정을 한눈에.")
    }

    private static func pick(en: String, vi: String, ja: String, ko: String) -> String {
        switch Locale.current.language.languageCode?.identifier {
        case "vi": return vi
        case "ja": return ja
        case "ko": return ko
        default:   return en
        }
    }
}
