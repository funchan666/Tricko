import SwiftUI

extension Font {
    // A single native family keeps headings and body copy aligned across languages.
    static func stage(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        .system(style).weight(display && weight == .regular ? .semibold : weight)
    }
}
