import SwiftUI

enum AppTheme {
    static let primary = Color(red: 22 / 255, green: 107 / 255, blue: 93 / 255)
    static let accent = Color(red: 226 / 255, green: 188 / 255, blue: 98 / 255)
    static let background = Color(red: 244 / 255, green: 247 / 255, blue: 244 / 255)
    static let surface = Color.white
    static let text = Color(red: 23 / 255, green: 32 / 255, blue: 27 / 255)
    static let secondaryText = Color(red: 104 / 255, green: 115 / 255, blue: 109 / 255)
    static let border = Color(red: 223 / 255, green: 228 / 255, blue: 223 / 255)
}

struct PageTitle: View {
    let eyebrow: String
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.secondaryText)
            Text(title)
                .font(.largeTitle.bold())
                .foregroundStyle(AppTheme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Surface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .background(AppTheme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(AppTheme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
