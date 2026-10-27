import Foundation

/// The game's languages. "Automatic" follows the device; the choice is saved.
enum AppLanguage: String, CaseIterable, Identifiable {
    case automatic, turkish = "tr", english = "en", spanish = "es"

    var id: String { rawValue }

    /// Name shown in the picker, in its own language.
    var displayName: String {
        switch self {
        case .automatic: return Strings.automaticLanguage
        case .turkish: return "Türkçe"
        case .english: return "English"
        case .spanish: return "Español"
        }
    }
}

/// TR/EN/ES text, from the chosen language or the device's preferred one.
enum Strings {
    private static let languageKey = "appLanguage"

    /// The saved choice (automatic by default).
    static var languageChoice: AppLanguage {
        get { AppLanguage(rawValue: UserDefaults.standard.string(forKey: languageKey) ?? "") ?? .automatic }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: languageKey)
            current = resolve(newValue)
        }
    }

    /// The language texts are shown in right now.
    private(set) static var current: AppLanguage = resolve(languageChoice)

    private static func resolve(_ choice: AppLanguage) -> AppLanguage {
        guard choice == .automatic else { return choice }
        for preferred in Locale.preferredLanguages {
            let code = preferred.lowercased()
            if code.hasPrefix("tr") { return .turkish }
            if code.hasPrefix("es") { return .spanish }
            if code.hasPrefix("en") { return .english }
        }
        return .english
    }

    static var isTurkish: Bool { current == .turkish }
    static var isSpanish: Bool { current == .spanish }

    private static func t(_ tr: String, _ en: String, _ es: String) -> String {
        switch current {
        case .turkish: return tr
        case .spanish: return es
        default: return en
        }
    }

    /// For the few texts written elsewhere (level names, credits).
    static func pick(_ tr: String, _ en: String, _ es: String) -> String { t(tr, en, es) }

    static var automaticLanguage: String { t("Otomatik (cihaz dili)", "Automatic (device)", "Automático (dispositivo)") }
    static var languageTitle: String { t("Dil", "Language", "Idioma") }

    static let appName = "Parkrift"
    static var tagline: String { t("Arkadaşınla aynı otoparkta, en temiz parkı kim yapacak?", "Same parking lot, two drivers. Who parks cleanest?", "Mismo aparcamiento, dos pilotos. ¿Quién aparca mejor?") }
    static var playSolo: String { t("Tek Başına", "Play Solo", "Jugar solo") }
    static var createRoom: String { t("Oda Kur", "Create Room", "Crear sala") }
    static var joinRoom: String { t("Odaya Katıl", "Join Room", "Unirse a sala") }
    static var codePlaceholder: String { t("KOD", "CODE", "CÓDIGO") }
    static var join: String { t("Katıl", "Join", "Unirse") }
    static var back: String { t("Geri", "Back", "Atrás") }
    static var start: String { t("Başlat", "Start", "Empezar") }
    static var startLevel: String { t("Başlangıç bölümü", "Start at level", "Empezar en el nivel") }
    static var roomCode: String { t("Oda kodu", "Room code", "Código de sala") }
    static var shareCode: String { t("Bu kodu arkadaşına söyle", "Tell your friend this code", "Dile este código a tu amigo") }
    static var waitingFriend: String { t("Arkadaşın bekleniyor…", "Waiting for your friend…", "Esperando a tu amigo…") }
    static var friendJoined: String { t("Arkadaşın geldi!", "Your friend is here!", "¡Tu amigo ha llegado!") }
    static var waitingHost: String { t("Oda sahibi oyunu başlatınca başlayacak", "The game starts when the host taps Start", "La partida empieza cuando el anfitrión pulse Empezar") }
    static var connecting: String { t("Bağlanıyor…", "Connecting…", "Conectando…") }
    static var noRoom: String { t("Bu kodla açık bir oda yok.", "No open room with this code.", "No hay ninguna sala abierta con este código.") }
    static var roomFull: String { t("Oda dolu.", "That room is full.", "La sala está llena.") }
    static var connectionLost: String { t("Bağlantı koptu.", "Connection lost.", "Se perdió la conexión.") }
    static var friendLeft: String { t("Arkadaşın ayrıldı", "Your friend left", "Tu amigo se ha ido") }
    static var leave: String { t("Ayrıl", "Leave", "Salir") }
    static var left: String { t("SOL", "LEFT", "IZQ") }
    static var right: String { t("SAĞ", "RIGHT", "DER") }
    static var levels: String { t("Bölümler", "Levels", "Niveles") }

    static func level(_ n: Int, of total: Int) -> String { t("Bölüm \(n)/\(total)", "Level \(n)/\(total)", "Nivel \(n)/\(total)") }
    static func hits(_ n: Int) -> String { t("Çarpma: \(n)", "Bumps: \(n)", "Golpes: \(n)") }
    static var you: String { t("SEN", "YOU", "TÚ") }
    static var friend: String { t("ARKADAŞ", "FRIEND", "AMIGO") }
    static var go: String { t("BAŞLA!", "GO!", "¡YA!") }
    static var parked: String { t("Park edildi!", "Parked!", "¡Aparcado!") }
    static var hold: String { t("Bekle…", "Hold…", "Quieto…") }
    static var waitingFriendPark: String { t("Arkadaşının park etmesi bekleniyor", "Waiting for your friend to park", "Esperando a que tu amigo aparque") }
    static var nextLevelSoon: String { t("Sıradaki bölüm geliyor…", "Next level coming up…", "Llega el siguiente nivel…") }
    static var allDone: String { t("Tüm bölümler bitti!", "All levels complete!", "¡Todos los niveles completados!") }
    static var backToMenu: String { t("Menüye dön", "Back to menu", "Volver al menú") }
    static var winner: String { t("Önce park etti", "Parked first", "Aparcó primero") }
    static var steer: String { t("Direksiyon", "Steer", "Dirección") }
    static var forward: String { t("İLERİ", "DRIVE", "AVANZA") }
    static var reverse: String { t("GERİ", "REV", "ATRÁS") }
    static var notParked: String { t("park etmedi", "not parked", "sin aparcar") }
    static var resetHint: String { t("↻ arabayı başa alır", "↻ puts your car back at the start", "↻ devuelve tu coche a la salida") }

    static var parkedTitle: String { t("PARK ETTİN!", "PARKED!", "¡APARCADO!") }
    static var timeLabel: String { t("SÜRE", "TIME", "TIEMPO") }
    static var bumpsLabel: String { t("ÇARPMA", "BUMPS", "GOLPES") }
    static var bestLabel: String { t("EN İYİ", "BEST", "MEJOR") }
    static var newBest: String { t("Yeni rekor!", "New best!", "¡Nuevo récord!") }
    static var retry: String { t("Tekrar", "Retry", "Reintentar") }
    static var next: String { t("Sonraki", "Next", "Siguiente") }
    static var menu: String { t("Menü", "Menu", "Menú") }
    static var horn: String { t("KORNA", "HORN", "CLAXON") }
    static var players: String { t("Oyuncular", "Players", "Jugadores") }
    static var levelShort: String { t("Bölüm", "Level", "Nivel") }
    static var starHint: String { t("Çarpmadan park et: 3 yıldız", "Park without bumps: 3 stars", "Aparca sin golpes: 3 estrellas") }
    static func round(_ n: Int, of total: Int) -> String { t("Tur \(n)/\(total)", "Round \(n)/\(total)", "Ronda \(n)/\(total)") }
    static var cityDrive: String { t("Şehirde Sür", "City Drive", "Conducir en la ciudad") }
    static var cityRace: String { t("Şehir yarışı", "City race", "Carrera urbana") }
    static var cityRaceInfo: String { t("5 tur · trafikte ilk park eden kazanır", "5 rounds · first to park in traffic wins", "5 rondas · gana quien aparque primero entre el tráfico") }
    static var turnLeft: String { t("Sola dön", "Turn left", "Gira a la izquierda") }
    static var turnRight: String { t("Sağa dön", "Turn right", "Gira a la derecha") }
    static var uTurn: String { t("Geri dön", "Turn around", "Da la vuelta") }
    static var toTarget: String { t("Hedef", "Target", "Destino") }
    static var parkHere: String { t("Park et!", "Park here!", "¡Aparca aquí!") }
    static func friendParkedHurry(_ s: Int) -> String { t("Arkadaşın park etti! \(s) sn", "Your friend parked! \(s)s", "¡Tu amigo aparcó! \(s) s") }
    static var allRounds: String { t("Yarış bitti!", "Race over!", "¡Carrera terminada!") }
    static var youWon: String { t("Kazandın!", "You won!", "¡Has ganado!") }
    static var friendWon: String { t("Arkadaşın kazandı", "Your friend won", "Ha ganado tu amigo") }
    static var draw: String { t("Berabere", "Draw", "Empate") }
    static func score(_ a: Int, _ b: Int) -> String { t("Skor \(a) – \(b)", "Score \(a) – \(b)", "Marcador \(a) – \(b)") }
    static func raceRound(_ n: Int, of total: Int) -> String { t("Yarış \(n)/\(total)", "Race \(n)/\(total)", "Carrera \(n)/\(total)") }
    static var carRace: String { t("Araba Yarışı", "Car Race", "Carrera") }
    static var parkRace: String { t("Park Yarışı", "Park Race", "Carrera de aparcar") }
    static var carRaceInfo: String { t("3 tur · yoğun trafik · en hızlı ve en az kazayla varan kazanır", "3 rounds · heavy traffic · fastest with fewest crashes wins", "3 rondas · tráfico denso · gana el más rápido con menos choques") }
    static var finished: String { t("BİTİRDİN!", "FINISHED!", "¡TERMINADO!") }
    static var finishLine: String { t("Bitiş", "Finish", "Meta") }
    static var scoreLabel: String { t("PUAN", "SCORE", "PUNTOS") }
    static var penaltyHint: String { t("Puan = süre + her kaza 3 sn", "Score = time + 3 s per crash", "Puntos = tiempo + 3 s por choque") }
    static func crashes(_ n: Int) -> String { t("\(n) kaza", "\(n) crashes", "\(n) choques") }
    static var mode: String { t("MOD", "MODE", "MODO") }
    static var nitro: String { t("NİTRO", "NITRO", "NITRO") }
    static var nitroGo: String { t("NİTRO!", "NITRO!", "¡NITRO!") }
    static var finishBig: String { t("FİNİŞ!", "FINISH!", "¡META!") }
    static var parkedBig: String { t("PARK EDİLDİ!", "PARKED!", "¡APARCADO!") }
    static var levelComplete: String { t("BÖLÜM TAMAMLANDI", "LEVEL COMPLETE", "NIVEL COMPLETADO") }
    static func place(_ n: Int) -> String { t("\(n). sırada", "Place \(n)", "Puesto \(n)") }
    static var loadingText: String { t("Harita hazırlanıyor…", "Preparing the map…", "Preparando el mapa…") }
    static var tips: [String] {
        switch current {
        case .turkish:
            return ["Nitro dolunca halka turkuaz olur, düz yolda bas.",
                    "Araba Yarışı'nda her kaza puanına 3 saniye ekler.",
                    "Mini haritadaki sarı çizgi en kısa yolu gösterir.",
                    "Botlar önlerindeki arabaya göre durur; karşı şeritten sollayabilirsin.",
                    "Kornaya basınca arkadaşın da duyar.",
                    "Park ederken yavaşla ve 1 saniye bekle.",
                    "DRİFT tuşuna basılı tutup direksiyonu çevir: drift puanı nitroya dönüşür.",
                    "Binaların arasındaki ara sokaklar kestirmedir; ortadaki rampadan uç!",
                    "Radara 70 km/s üstünde girersen polis peşine düşer."]
        case .spanish:
            return ["Cuando el anillo se vuelve turquesa, el nitro está listo: úsalo en una recta.",
                    "En la Carrera cada choque suma 3 segundos a tu puntuación.",
                    "La línea amarilla del minimapa es la ruta más corta.",
                    "Los bots frenan ante los coches de delante; adelanta por el otro carril.",
                    "Tu amigo oye tu claxon.",
                    "Para aparcar, frena y quédate quieto un segundo.",
                    "Mantén DERRAPE y gira: los puntos de derrape se convierten en nitro.",
                    "Los callejones entre edificios son atajos; ¡salta en la rampa!",
                    "Si pasas un radar a más de 70 km/h, te perseguirá la policía."]
        default:
            return ["When the ring turns turquoise, nitro is ready — use it on a straight.",
                    "In the Car Race every crash adds 3 seconds to your score.",
                    "The yellow line on the minimap is the shortest route.",
                    "Bots stop for cars in front; overtake through the other lane.",
                    "Your friend hears your horn.",
                    "To park, slow down and hold still for a second.",
                    "Hold DRIFT and steer: drift points turn into nitro.",
                    "Alleys between buildings are shortcuts — jump the ramp!",
                    "Pass a speed camera above 70 km/h and the police will chase you."]
        }
    }
    static var modeSoloTitle: String { t("Park Ustası", "Park Master", "Maestro del aparcamiento") }
    static var modeSoloSub: String { t("Tek başına 10 bölüm, 3 yıldızı topla", "10 solo levels, collect all the stars", "10 niveles en solitario, consigue todas las estrellas") }
    static var modeCityTitle: String { t("Şehir", "City", "Ciudad") }
    static var modeCitySub: String { t("Trafikte yarış ya da en hızlı park et", "Race through traffic or park fastest", "Corre entre el tráfico o aparca más rápido") }
    static var modeOnlineTitle: String { t("Arkadaşınla", "With a Friend", "Con un amigo") }
    static var modeOnlineSub: String { t("Oda kur, kodu paylaş, birlikte yarışın", "Make a room, share the code, race together", "Crea una sala, comparte el código y corred juntos") }
    static func levelsCount(_ n: Int) -> String { t("\(n) bölüm", "\(n) levels", "\(n) niveles") }
    static var twoPlayersOnline: String { t("2 oyuncu · online", "2 players · online", "2 jugadores · online") }
    static var play: String { t("Oyna", "Play", "Jugar") }
    static var enterCode: String { t("Kodu gir", "Enter code", "Introduce el código") }
    static var createRoomSub: String { t("Bir oda kodu oluştur ve arkadaşına gönder.", "Create a room code and send it to your friend.", "Crea un código de sala y envíaselo a tu amigo.") }
    static var joinRoomSub: String { t("Arkadaşının verdiği 4 harfli kodu yaz.", "Type the 4-letter code your friend gave you.", "Escribe el código de 4 letras que te dio tu amigo.") }
    static var credits: String { t("Araba modelleri: Meshy AI ile üretilen özgün tasarımlar, Khronos Group (CC BY 4.0) · Kenney, Khronos (CC0)",
                                     "Car models: original designs made with Meshy AI, Khronos Group (CC BY 4.0) · Kenney, Khronos (CC0)", "Modelos de coches: diseños originales hechos con Meshy AI, Khronos Group (CC BY 4.0) · Kenney, Khronos (CC0)") }
    static var about: String { t("Hakkında", "About", "Acerca de") }
    static var privacyPolicy: String { t("Gizlilik Politikası", "Privacy Policy", "Política de privacidad") }
    static var support: String { t("Destek", "Support", "Soporte") }
    static var licenses: String { t("3D modeller ve lisanslar", "3D models and licenses", "Modelos 3D y licencias") }
    static var aboutText: String { t("Parkrift kişisel veri toplamaz; hesap, reklam ve takip yoktur. Online oyunda yalnızca oda kodu ve araba hareketleri arkadaşına iletilir.",
                                     "Parkrift collects no personal data: no accounts, ads or tracking. In online play only the room code and car movements are relayed to your friend.", "Parkrift no recopila datos personales: sin cuentas, anuncios ni seguimiento. En el modo online solo se envían a tu amigo el código de sala y los movimientos del coche.") }
    static var close: String { t("Kapat", "Close", "Cerrar") }

    // Garage
    static var garage: String { t("Garaj", "Garage", "Garaje") }
    static var paint: String { t("Boya", "Paint", "Pintura") }
    static var carClass: String { t("SINIF", "CLASS", "CLASE") }
    static var statSpeed: String { t("Hız", "Speed", "Velocidad") }
    static var statAccel: String { t("Hızlanma", "Accel", "Aceleración") }
    static var statHandling: String { t("Yol tutuş", "Handling", "Manejo") }
    static var statNitro: String { t("Nitro", "Nitro", "Nitro") }
    static var raceStart: String { t("Yarışa başla", "Race", "Correr") }
    static var selectCar: String { t("Arabayı seç", "Select car", "Elegir coche") }
    static var changeCar: String { t("Arabayı değiştir", "Change car", "Cambiar coche") }
    static var yourCar: String { t("Araban", "Your car", "Tu coche") }
    static var paintRed: String { t("Yarış kırmızısı", "Racing red", "Rojo carreras") }
    static var paintBlue: String { t("Gece mavisi", "Midnight blue", "Azul noche") }
    static var paintLime: String { t("Neon yeşil", "Neon lime", "Lima neón") }
    static var paintYellow: String { t("Sarı", "Yellow", "Amarillo") }
    static var paintOrange: String { t("Turuncu", "Orange", "Naranja") }
    static var paintPurple: String { t("Mor", "Purple", "Morado") }
    static var paintWhite: String { t("İnci beyaz", "Pearl white", "Blanco perla") }
    static var paintBlack: String { t("Gece siyahı", "Jet black", "Negro azabache") }

    // Finish plate
    static var raceComplete: String { t("YARIŞ TAMAMLANDI", "RACE COMPLETE", "CARRERA COMPLETADA") }
    static var placeShort: String { t("SIRA", "PLACE", "PUESTO") }
    static var roundShort: String { t("TUR", "ROUND", "RONDA") }

    // Menu
    static var chooseMode: String { t("Mod seç", "Choose mode", "Elige modo") }
    static var playNow: String { t("Oyna", "Play", "Jugar") }

    // City bonuses
    static var nitroPickup: String { t("+NİTRO", "+NITRO", "+NITRO") }
    static func radarBonus(_ speed: String) -> String { t("RADAR \(speed) · +NİTRO", "SPEED CAM \(speed) · +NITRO", "RADAR \(speed) · +NITRO") }
    static func radarSlow(_ speed: String, _ need: Int) -> String { t("RADAR \(speed) · \(need)+ gerek", "SPEED CAM \(speed) · need \(need)+", "RADAR \(speed) · necesitas \(need)+") }
    static var pedestrianHit: String { t("DİKKAT! YAYA · +1 KAZA", "WATCH OUT! · +1 CRASH", "¡CUIDADO! · +1 CHOQUE") }
    static var police: String { t("POLİS", "POLICE", "POLICÍA") }
    static var taxi: String { t("TAKSİ", "CAB", "TAXI") }
    // Arcade
    static var driftButton: String { t("DRİFT", "DRIFT", "DERRAPE") }
    static var driftLabel: String { t("DRİFT", "DRIFT", "DERRAPE") }
    static func driftBonus(_ score: Int) -> String { t("DRİFT +\(score) · +NİTRO", "DRIFT +\(score) · +NITRO", "DERRAPE +\(score) · +NITRO") }
    static var driftLost: String { t("DRİFT BOZULDU", "DRIFT LOST", "DERRAPE PERDIDO") }
    static var driftPark: String { t("DRİFT PARK! −2 sn", "DRIFT PARK! −2 s", "¡APARCAMIENTO DERRAPANDO! −2 s") }
    static var nearMiss: String { t("KIL PAYI! +NİTRO", "NEAR MISS! +NITRO", "¡POR LOS PELOS! +NITRO") }
    static var jump: String { t("UÇUŞ! +NİTRO", "BIG AIR! +NITRO", "¡A VOLAR! +NITRO") }
    static var policeChase: String { t("POLİS PEŞİNDE!", "POLICE CHASE!", "¡TE PERSIGUE LA POLICÍA!") }
    static var policeCaught: String { t("YAKALANDIN! +2 KAZA", "BUSTED! +2 CRASHES", "¡TE PILLARON! +2 CHOQUES") }
    static var policeEscaped: String { t("KAÇTIN! NİTRO DOLU", "ESCAPED! FULL NITRO", "¡ESCAPASTE! NITRO LLENO") }
    static var nightDrive: String { t("Gece", "Night", "Noche") }
    static var rainyDrive: String { t("Yağmurlu", "Rain", "Lluvia") }
    static var factoryLivery: String { t("Özel boya", "Signature livery", "Pintura de fábrica") }
}
