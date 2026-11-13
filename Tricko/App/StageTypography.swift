import SwiftUI

// Display headings use the bundled OFL Cormorant Garamond (Latin subset); body copy,
// controls and numbers use the system font. Both scale with Dynamic Type, and
// Core Text supplies the system cascade for Arabic, Japanese and Korean glyphs.
extension Font {
    static func stage(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        guard display else { return .system(style, design: .default).weight(weight) }
        let points: CGFloat
        switch style {
        case .largeTitle: points = 38
        case .title: points = 32
        case .title2: points = 26
        case .title3: points = 23
        case .headline, .body: points = 19
        case .callout: points = 18
        case .subheadline: points = 17
        case .footnote: points = 15
        case .caption: points = 14
        case .caption2: points = 13
        @unknown default: points = 19
        }
        // Cormorant runs small on the x-height; sizes are set ~12% above system equivalents.
        let name = weight == .bold || weight == .heavy || weight == .black
            ? "CormorantGaramond-Bold" : "CormorantGaramond-SemiBold"
        return .custom(name, size: points, relativeTo: style)
    }
}
