import SwiftUI

extension Font {
    static func stage(_ style: Font.TextStyle, weight: Font.Weight = .regular, display: Bool = false) -> Font {
        .system(style).weight(display && weight == .regular ? .semibold : weight)
    }
}
