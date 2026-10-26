import Foundation

/// Minimal TR/EN text helper based on the device's preferred language.
enum Strings {
    static let isTurkish: Bool = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("tr")

    static var title: String { "Hop!" }
    static var tapToStart: String { isTurkish ? "Başlamak için dokun" : "Tap to start" }
    static var hint: String { isTurkish ? "Her dokunuşta yüksel · Sütunların arasından geç" : "Tap to fly up · Pass between the pillars" }
    static var gameOver: String { isTurkish ? "Oyun bitti" : "Game over" }
    static var tapToRetry: String { isTurkish ? "Tekrar için dokun" : "Tap to try again" }
    static func best(_ value: Int) -> String { isTurkish ? "Rekor: \(value)" : "Best: \(value)" }
    static var newBest: String { isTurkish ? "Yeni rekor!" : "New best!" }
}
