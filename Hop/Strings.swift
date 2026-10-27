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
    static var left: String { t("SOL", "LEFT") }
    static var right: String { t("SAĞ", "RIGHT") }
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

    static var parkedTitle: String { t("PARK ETTİN!", "PARKED!") }
    static var timeLabel: String { t("SÜRE", "TIME") }
    static var bumpsLabel: String { t("ÇARPMA", "BUMPS") }
    static var bestLabel: String { t("EN İYİ", "BEST") }
    static var newBest: String { t("Yeni rekor!", "New best!") }
    static var retry: String { t("Tekrar", "Retry") }
    static var next: String { t("Sonraki", "Next") }
    static var menu: String { t("Menü", "Menu") }
    static var horn: String { t("KORNA", "HORN") }
    static var players: String { t("Oyuncular", "Players") }
    static var levelShort: String { t("Bölüm", "Level") }
    static var starHint: String { t("Çarpmadan park et: 3 yıldız", "Park without bumps: 3 stars") }
    static func round(_ n: Int, of total: Int) -> String { t("Tur \(n)/\(total)", "Round \(n)/\(total)") }
    static var cityDrive: String { t("Şehirde Sür", "City Drive") }
    static var cityRace: String { t("Şehir yarışı", "City race") }
    static var cityRaceInfo: String { t("5 tur · trafikte ilk park eden kazanır", "5 rounds · first to park in traffic wins") }
    static var turnLeft: String { t("Sola dön", "Turn left") }
    static var turnRight: String { t("Sağa dön", "Turn right") }
    static var uTurn: String { t("Geri dön", "Turn around") }
    static var toTarget: String { t("Hedef", "Target") }
    static var parkHere: String { t("Park et!", "Park here!") }
    static func friendParkedHurry(_ s: Int) -> String { t("Arkadaşın park etti! \(s) sn", "Your friend parked! \(s)s") }
    static var allRounds: String { t("Yarış bitti!", "Race over!") }
    static var youWon: String { t("Kazandın!", "You won!") }
    static var friendWon: String { t("Arkadaşın kazandı", "Your friend won") }
    static var draw: String { t("Berabere", "Draw") }
    static func score(_ a: Int, _ b: Int) -> String { t("Skor \(a) – \(b)", "Score \(a) – \(b)") }
    static func raceRound(_ n: Int, of total: Int) -> String { t("Yarış \(n)/\(total)", "Race \(n)/\(total)") }
    static var carRace: String { t("Araba Yarışı", "Car Race") }
    static var parkRace: String { t("Park Yarışı", "Park Race") }
    static var carRaceInfo: String { t("3 tur · yoğun trafik · en hızlı ve en az kazayla varan kazanır", "3 rounds · heavy traffic · fastest with fewest crashes wins") }
    static var finished: String { t("BİTİRDİN!", "FINISHED!") }
    static var finishLine: String { t("Bitiş", "Finish") }
    static var scoreLabel: String { t("PUAN", "SCORE") }
    static var penaltyHint: String { t("Puan = süre + her kaza 3 sn", "Score = time + 3 s per crash") }
    static func crashes(_ n: Int) -> String { t("\(n) kaza", "\(n) crashes") }
    static var mode: String { t("MOD", "MODE") }
    static var nitro: String { t("NİTRO", "NITRO") }
    static var nitroGo: String { t("NİTRO!", "NITRO!") }
    static var finishBig: String { t("FİNİŞ!", "FINISH!") }
    static func place(_ n: Int) -> String { t("\(n). sırada", "Place \(n)") }
    static var loadingText: String { t("Harita hazırlanıyor…", "Preparing the map…") }
    static var tips: [String] {
        isTurkish ? ["Nitro dolunca halka turkuaz olur, düz yolda bas.",
                     "Araba Yarışı'nda her kaza puanına 3 saniye ekler.",
                     "Mini haritadaki sarı çizgi en kısa yolu gösterir.",
                     "Botlar önlerindeki arabaya göre durur; karşı şeritten sollayabilirsin.",
                     "Kornaya basınca arkadaşın da duyar.",
                     "Park ederken yavaşla ve 1 saniye bekle."]
                  : ["When the ring turns turquoise, nitro is ready — use it on a straight.",
                     "In the Car Race every crash adds 3 seconds to your score.",
                     "The yellow line on the minimap is the shortest route.",
                     "Bots stop for cars in front; overtake through the other lane.",
                     "Your friend hears your horn.",
                     "To park, slow down and hold still for a second."]
    }
    static var modeSoloTitle: String { t("Park Ustası", "Park Master") }
    static var modeSoloSub: String { t("Tek başına 10 bölüm, 3 yıldızı topla", "10 solo levels, collect all the stars") }
    static var modeCityTitle: String { t("Şehir", "City") }
    static var modeCitySub: String { t("Trafikte yarış ya da en hızlı park et", "Race through traffic or park fastest") }
    static var modeOnlineTitle: String { t("Arkadaşınla", "With a Friend") }
    static var modeOnlineSub: String { t("Oda kur, kodu paylaş, birlikte yarışın", "Make a room, share the code, race together") }
    static func levelsCount(_ n: Int) -> String { t("\(n) bölüm", "\(n) levels") }
    static var twoPlayersOnline: String { t("2 oyuncu · online", "2 players · online") }
    static var play: String { t("Oyna", "Play") }
    static var enterCode: String { t("Kodu gir", "Enter code") }
    static var createRoomSub: String { t("Bir oda kodu oluştur ve arkadaşına gönder.", "Create a room code and send it to your friend.") }
    static var joinRoomSub: String { t("Arkadaşının verdiği 4 harfli kodu yaz.", "Type the 4-letter code your friend gave you.") }
    static var credits: String { t("Araba modelleri: \"Ferrari 458 Italia\" — vicent091036, CC BY 4.0 · \"Car Concept\" — Khronos Group, CC BY 4.0 · \"Toy Car\" — Khronos, CC0 (değiştirildi)",
                                     "Car models: \"Ferrari 458 Italia\" by vicent091036, CC BY 4.0 · \"Car Concept\" by Khronos Group, CC BY 4.0 · \"Toy Car\" by Khronos, CC0 (modified)") }

    // Garage
    static var garage: String { t("Garaj", "Garage") }
    static var paint: String { t("Boya", "Paint") }
    static var carClass: String { t("SINIF", "CLASS") }
    static var statSpeed: String { t("Hız", "Speed") }
    static var statAccel: String { t("Hızlanma", "Accel") }
    static var statHandling: String { t("Yol tutuş", "Handling") }
    static var statNitro: String { t("Nitro", "Nitro") }
    static var raceStart: String { t("Yarışa başla", "Race") }
    static var selectCar: String { t("Arabayı seç", "Select car") }
    static var changeCar: String { t("Arabayı değiştir", "Change car") }
    static var yourCar: String { t("Araban", "Your car") }
    static var paintRed: String { t("Yarış kırmızısı", "Racing red") }
    static var paintBlue: String { t("Gece mavisi", "Midnight blue") }
    static var paintLime: String { t("Neon yeşil", "Neon lime") }
    static var paintYellow: String { t("Sarı", "Yellow") }
    static var paintOrange: String { t("Turuncu", "Orange") }
    static var paintPurple: String { t("Mor", "Purple") }
    static var paintWhite: String { t("İnci beyaz", "Pearl white") }
    static var paintBlack: String { t("Gece siyahı", "Jet black") }

    // Finish plate
    static var raceComplete: String { t("YARIŞ TAMAMLANDI", "RACE COMPLETE") }
    static var placeShort: String { t("SIRA", "PLACE") }
    static var roundShort: String { t("TUR", "ROUND") }

    // Menu
    static var chooseMode: String { t("Mod seç", "Choose mode") }
    static var playNow: String { t("Oyna", "Play") }
}
