import SwiftUI
import UIKit

// MARK: - Global "tap anywhere to dismiss keyboard"

/// Marker subclass so the window gesture is installed only once per window.
private final class KeyboardDismissTapGesture: UITapGestureRecognizer {}

private final class KeyboardDismissCoordinator: NSObject, UIGestureRecognizerDelegate {
    static let shared = KeyboardDismissCoordinator()

    @objc func dismiss() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
    }

    // Never block the app's own taps / list selection / buttons.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    // Ignore taps that land on a text input or control, so tapping from one
    // field to another focuses cleanly (no dismiss flicker) and controls work.
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        var view = touch.view
        while let v = view {
            if v is UITextField || v is UITextView { return false }
            view = v.superview
        }
        return true
    }
}

extension UIApplication {
    /// Installs a window-wide tap recognizer that dismisses the keyboard on any
    /// tap, without swallowing the touch (buttons, rows, etc. keep working).
    /// Idempotent — safe to call on every scene activation.
    func installKeyboardDismissTapIfNeeded() {
        let windows = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        for window in windows {
            let already = window.gestureRecognizers?
                .contains { $0 is KeyboardDismissTapGesture } ?? false
            guard !already else { continue }
            let tap = KeyboardDismissTapGesture(
                target: KeyboardDismissCoordinator.shared,
                action: #selector(KeyboardDismissCoordinator.dismiss)
            )
            tap.cancelsTouchesInView = false
            tap.requiresExclusiveTouchType = false
            tap.delegate = KeyboardDismissCoordinator.shared
            window.addGestureRecognizer(tap)
        }
    }
}

// MARK: - Imperative helper

/// Dismiss the keyboard from anywhere.
func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
    )
}

// MARK: - "Done" keyboard toolbar

extension View {
    /// Adds a trailing **Done** button to the keyboard toolbar for text inputs
    /// in this view's scope.
    func doneKeyboardToolbar() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { hideKeyboard() }
                    .fontWeight(.semibold)
            }
        }
    }
}
