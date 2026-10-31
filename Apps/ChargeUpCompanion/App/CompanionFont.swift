import SwiftUI

/// Type for the companion. On iPhone and iPad it is the system text styles,
/// so Dynamic Type still applies. A Mac has no Dynamic Type and its styles
/// run about a quarter smaller than the iPad's, too small for a nurse a
/// metre from the screen, so on macOS each style is the iPad's default
/// size scaled up.
extension Font {
    static func companion(_ style: Font.TextStyle) -> Font {
        #if os(macOS)
        let (size, weight) = CompanionType.ipadDefault(style)
        return .system(size: size * CompanionType.macScale, weight: weight)
        #else
        return .system(style)
        #endif
    }

    static func companion(size: CGFloat, weight: Font.Weight) -> Font {
        #if os(macOS)
        return .system(size: size * CompanionType.macScale, weight: weight)
        #else
        return .system(size: size, weight: weight)
        #endif
    }
}

enum CompanionType {
    /// Mac type is the iPad's default size times this.
    static let macScale: CGFloat = 1.15

    /// The iPad's default (Large) point size and weight for each style.
    static func ipadDefault(_ style: Font.TextStyle) -> (CGFloat, Font.Weight) {
        switch style {
        case .largeTitle: (34, .regular)
        case .title: (28, .regular)
        case .title2: (22, .regular)
        case .title3: (20, .regular)
        case .headline: (17, .semibold)
        case .body: (17, .regular)
        case .callout: (16, .regular)
        case .subheadline: (15, .regular)
        case .footnote: (13, .regular)
        case .caption: (12, .regular)
        case .caption2: (11, .regular)
        @unknown default: (17, .regular)
        }
    }
}
