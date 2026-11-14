import SwiftUI

extension Color {
    /// Orange for warnings like "Overdue". The system orange is too light to
    /// read as small text on white (about 2.2:1), so light mode uses a
    /// deeper burnt orange (about 5:1 on white and on grouped-list gray);
    /// dark mode keeps the system orange, which reads well on dark grays.
    ///
    /// `nonisolated` because the system may resolve dynamic colors off the
    /// main thread, and this project makes code main-actor-only by default.
    nonisolated static let warning: Color = {
        let lightOrange = (red: 0.639, green: 0.322, blue: 0.0)
        #if canImport(UIKit)
        return Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? .systemOrange
                : UIColor(red: lightOrange.red, green: lightOrange.green, blue: lightOrange.blue, alpha: 1)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                ? .systemOrange
                : NSColor(red: lightOrange.red, green: lightOrange.green, blue: lightOrange.blue, alpha: 1)
        })
        #endif
    }()
}
