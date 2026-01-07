//
//  GuideManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 7/1/26.
//

import Foundation
import Combine

//
//  GuideManager.swift
//  Easy Schedule
//
//  Created by Sam Manh Cuong on 7/1/26.
//

import Foundation
import Combine

final class GuideManager: ObservableObject {

    @Published var activeGuide: GuideKey?

    /// Đánh dấu đã hoàn thành toàn bộ main guide
    private let storageKey = "didFinishMainGuide"

    // MARK: - Public API

    /// Gọi 1 lần khi user vào main app (sau login)
    func startIfNeeded() {
        // Nếu đã hoàn thành toàn bộ flow → không start nữa
        guard !UserDefaults.standard.bool(forKey: storageKey) else { return }

        // Nếu user đã disable riêng eventsIntro → không hiện
        guard !isDisabled(.eventsIntro) else { return }

        activeGuide = .eventsIntro
    }

    /// Hoàn thành guide hiện tại (flow tự động)
    func complete(_ guide: GuideKey) {
        switch guide {

        case .eventsIntro:
            // Nếu calendarIntro bị disable → nhảy tiếp
            if isDisabled(.calendarIntro) {
                complete(.calendarIntro)
            } else {
                activeGuide = .calendarIntro
            }

        case .calendarIntro:
            if isDisabled(.partnersIntro) {
                complete(.partnersIntro)
            } else {
                activeGuide = .partnersIntro
            }

        case .partnersIntro:
            activeGuide = nil
            UserDefaults.standard.set(true, forKey: storageKey)

        default:
            activeGuide = nil
        }
    }

    /// User chủ động mở lại guide (ví dụ bấm nút ?)
    func show(_ guide: GuideKey) {
        activeGuide = guide
    }

    /// User chọn "Do not show again"
    func disablePermanently(_ guide: GuideKey) {
        UserDefaults.standard.set(true, forKey: disabledKey(for: guide))

        // Nếu đang hiển thị guide đó → ẩn luôn
        if activeGuide == guide {
            activeGuide = nil
        }
    }

    /// Check guide đang active
    func isActive(_ guide: GuideKey) -> Bool {
        activeGuide == guide
    }

    /// Check guide có bị disable không
    func isDisabled(_ guide: GuideKey) -> Bool {
        UserDefaults.standard.bool(forKey: disabledKey(for: guide))
    }

    // MARK: - Private

    private func disabledKey(for guide: GuideKey) -> String {
        "guide_disabled_\(guide.rawValue)"
    }
}
