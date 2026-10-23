import SwiftUI
import UIKit

/// uKivi's look: near-black surfaces with one red accent.
enum Theme {
    static let background = Color(red: 0.04, green: 0.04, blue: 0.045)
    static let card = Color(red: 0.09, green: 0.09, blue: 0.10)
    static let cardBorder = Color.white.opacity(0.07)
    static let red = Color(red: 1.0, green: 0.30, blue: 0.33)
    static let redDeep = Color(red: 0.76, green: 0.13, blue: 0.17)
    static let secondary = Color.white.opacity(0.55)

    static let redGradient = LinearGradient(
        colors: [red, redDeep],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// The rounded dark panel used for every section.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.cardBorder)
        )
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.secondary)
            .padding(.leading, 6)
    }
}

/// The kiwi bird, bundled as KiviLogo.png (made by Tools/make_icons.py).
struct KiviLogo: View {
    var body: some View {
        if let image = UIImage(named: "KiviLogo") {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "bird.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(Theme.redGradient)
        }
    }
}
