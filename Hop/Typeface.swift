import SwiftUI
import UIKit

/// The game's typeface: Barlow (SIL Open Font License, bundled in Fonts/). Barlow for text and
/// labels, Barlow Condensed italic for the racing titles and big numbers. Both carry tabular
/// figures, so `.monospacedDigit()` keeps counting numbers steady.
enum Typeface {
    /// Barlow at a weight (the bundled cuts: Regular to Black).
    static func text(_ weight: UIFont.Weight) -> String {
        switch weight.rawValue {
        case ..<(-0.1): return "Barlow-Regular"
        case ..<0.1: return "Barlow-Medium"
        case ..<0.35: return "Barlow-SemiBold"
        case ..<0.5: return "Barlow-Bold"
        case ..<0.6: return "Barlow-ExtraBold"
        default: return "Barlow-Black"
        }
    }

    /// Barlow Condensed italic at a weight (the racing face).
    static func race(_ weight: UIFont.Weight) -> String {
        switch weight.rawValue {
        case ..<0.35: return "BarlowCondensed-SemiBoldItalic"
        case ..<0.5: return "BarlowCondensed-BoldItalic"
        case ..<0.6: return "BarlowCondensed-ExtraBoldItalic"
        default: return "BarlowCondensed-BlackItalic"
        }
    }

    static func uiWeight(_ weight: Font.Weight) -> UIFont.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        default: return .regular
        }
    }
}

extension Font {
    /// Text and labels in Barlow.
    static func ui(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(Typeface.text(Typeface.uiWeight(weight)), fixedSize: size)
    }
}

extension UIFont {
    /// Barlow at a weight (falls back to the system font if the file is missing).
    static func ui(_ size: CGFloat, _ weight: UIFont.Weight = .regular) -> UIFont {
        UIFont(name: Typeface.text(weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// Barlow Condensed italic, the racing face.
    static func race(_ size: CGFloat, _ weight: UIFont.Weight = .black) -> UIFont {
        UIFont(name: Typeface.race(weight), size: size) ?? .systemFont(ofSize: size, weight: weight)
    }

    /// The same font with tabular figures (numbers that count without jumping).
    var tabular: UIFont {
        let settings: [[UIFontDescriptor.FeatureKey: Any]] = [[.type: kNumberSpacingType, .selector: kMonospacedNumbersSelector]]
        return UIFont(descriptor: fontDescriptor.addingAttributes([.featureSettings: settings]), size: pointSize)
    }
}
