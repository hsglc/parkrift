import Foundation

/// Minimal TR/EN text helper based on the device's preferred language.
enum Strings {
    static let isTurkish: Bool = (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("tr")

    private static func t(_ tr: String, _ en: String) -> String { isTurkish ? tr : en }

    static let appName = "ParkPark"
    static var tagline: String { t("Arkadaşınla aynı otoparkta, en temiz parkı kim yapacak?", "Same parking lot, two drivers. Who parks cleanest?") }
    static var playSolo: String { t("Tek Başına", "Play Solo") }
    static var createRoom: String { t("Oda Kur", "Create Room") }
    static var joinRoom: String { t("Odaya Katıl", "Join Room") }
    static var codePlaceholder: String { t("KOD", "CODE") }
    static var join: String { t("Katıl", "Join") }
    static var back: String { t("Geri", "Back") }
    static var start: String { t("Başlat", "Start") }
    static var startLevel: String { t("Başlangıç bölümü", "Start at level") }
    static var roomCode: String { t("Oda kodu", "Room code") }
    static var shareCode: String { t("Bu kodu arkadaşına söyle", "Tell your friend this code") }
    static var waitingFriend: String { t("Arkadaşın bekleniyor…", "Waiting for your friend…") }
    static var friendJoined: String { t("Arkadaşın geldi!", "Your friend is here!") }
    static var waitingHost: String { t("Oda sahibi oyunu başlatınca başlayacak", "The game starts when the host taps Start") }
    static var connecting: String { t("Bağlanıyor…", "Connecting…") }
    static var noRoom: String { t("Bu kodla açık bir oda yok.", "No open room with this code.") }
    static var roomFull: String { t("Oda dolu.", "That room is full.") }
    static var connectionLost: String { t("Bağlantı koptu.", "Connection lost.") }
    static var friendLeft: String { t("Arkadaşın ayrıldı", "Your friend left") }
    static var leave: String { t("Ayrıl", "Leave") }
    static var levels: String { t("Bölümler", "Levels") }

    static func level(_ n: Int, of total: Int) -> String { t("Bölüm \(n)/\(total)", "Level \(n)/\(total)") }
    static func hits(_ n: Int) -> String { t("Çarpma: \(n)", "Bumps: \(n)") }
    static var you: String { t("SEN", "YOU") }
    static var friend: String { t("ARKADAŞ", "FRIEND") }
    static var go: String { t("BAŞLA!", "GO!") }
    static var parked: String { t("Park edildi!", "Parked!") }
    static var hold: String { t("Bekle…", "Hold…") }
    static var waitingFriendPark: String { t("Arkadaşının park etmesi bekleniyor", "Waiting for your friend to park") }
    static var nextLevelSoon: String { t("Sıradaki bölüm geliyor…", "Next level coming up…") }
    static var allDone: String { t("Tüm bölümler bitti!", "All levels complete!") }
    static var backToMenu: String { t("Menüye dön", "Back to menu") }
    static var winner: String { t("Önce park etti", "Parked first") }
    static var steer: String { t("Direksiyon", "Steer") }
    static var forward: String { t("İLERİ", "DRIVE") }
    static var reverse: String { t("GERİ", "REV") }
    static var notParked: String { t("park etmedi", "not parked") }
    static var resetHint: String { t("↻ arabayı başa alır", "↻ puts your car back at the start") }
}
