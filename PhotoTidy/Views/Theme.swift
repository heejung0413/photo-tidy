import SwiftUI

/// 앱 전체에서 쓰는 색과 공통 모양.
enum Theme {
    static let accent = Color(red: 0.05, green: 0.52, blue: 0.48)
    static let gradient = LinearGradient(
        colors: [Color(red: 0.10, green: 0.62, blue: 0.55), Color(red: 0.20, green: 0.45, blue: 0.85)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let background = Color(.systemGroupedBackground)
    static let cardBackground = Color(.secondarySystemGroupedBackground)
    static let cornerRadius: CGFloat = 16
}

extension View {
    /// 둥근 카드 모양 배경.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.cardBackground,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }
}

/// 숫자 동그라미(타임라인 순번).
struct NumberBadge: View {
    let number: Int

    var body: some View {
        Text("\(number)")
            .font(.caption.bold())
            .monospacedDigit()
            .foregroundStyle(.white)
            .frame(minWidth: 26, minHeight: 26)
            .background(Theme.accent, in: Circle())
    }
}
