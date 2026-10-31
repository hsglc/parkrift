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

    /// Upper case by the game's language (Turkish i → İ, not I).
    static func upper(_ text: String) -> String {
        text.uppercased(with: Locale(identifier: current == .turkish ? "tr" : (current == .spanish ? "es" : "en")))
    }

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
    static var resultSlip: String { t("SONUÇ FİŞİ", "RESULT SLIP", "TICKET DE RESULTADO") }
    static var totalLabel: String { t("TOPLAM", "TOTAL", "TOTAL") }
    static var secondsShort: String { t("sn", "s", "s") }
    static var coinsWord: String { t("altın", "coins", "monedas") }
    static var raceFailedTitle: String { t("BİTİREMEDİN", "DID NOT FINISH", "SIN TERMINAR") }
    static var getReady: String { t("HAZIR OL", "GET READY", "PREPÁRATE") }
    static var parked: String { t("Park edildi!", "Parked!", "¡Aparcado!") }
    static var hold: String { t("Kıpırdama", "Hold still", "No te muevas") }
    static func resetsIn(_ time: String) -> String { t("Yenilenme \(time)", "Resets in \(time)", "Se renueva en \(time)") }
    static func dayN(_ n: Int) -> String { t("\(n). gün ödülü", "Day \(n) reward", "Premio del día \(n)") }
    static var taskDone: String { t("Tamamlandı", "Completed", "Completado") }
    static var statTime: String { t("SÜRE", "TIME", "TIEMPO") }
    static var statCrashes: String { t("KAZA", "CRASHES", "CHOQUES") }
    static var statRound: String { t("TUR", "ROUND", "RONDA") }
    static var statPlace: String { t("SIRA", "PLACE", "PUESTO") }
    static var tabPark: String { t("Park", "Park", "Aparcar") }
    static var tabCity: String { t("Şehir", "City", "Ciudad") }
    static var tabRace: String { t("Yarış", "Race", "Carrera") }
    static var tabOnline: String { t("Online", "Online", "Online") }
    static var curtainGarage: String { t("Arabanı seç, rengini ayarla", "Pick your car and its colour", "Elige tu coche y su color") }
    static var curtainSearching: String { t("Seninle aynı anda oynamak isteyen biri aranıyor", "Looking for someone to play with right now", "Buscando a alguien para jugar ahora") }
    static func curtainConnecting(_ code: String) -> String {
        code.isEmpty ? t("Sunucuya bağlanılıyor", "Reaching the server", "Conectando con el servidor")
                     : t("Oda \(code)", "Room \(code)", "Sala \(code)")
    }
    static var cancelAction: String { t("Vazgeç", "Cancel", "Cancelar") }
    static var liveTag: String { t("CANLI", "LIVE", "EN VIVO") }
    static var spectatingFriend: String { t("Rakibini izliyorsun", "Watching your rival", "Viendo a tu rival") }
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
    static var notParkedTitle: String { t("PARK EDEMEDİN", "NOT PARKED", "SIN APARCAR") }
    static var tryAgain: String { t("Tekrar dene", "Try again", "Reintentar") }
    static var lastRoundFailed: String { t("Son turu bitiremedin", "You did not finish the last round", "No terminaste la última ronda") }
    static var lastRoundWon: String { t("Son turu sen kazandın", "You won the last round", "Ganaste la última ronda") }
    static var lastRoundLost: String { t("Son turu arkadaşın aldı", "Your friend took the last round", "Tu amigo ganó la última ronda") }
    static var lastRoundDraw: String { t("Son tur berabere", "Last round: a draw", "Última ronda: empate") }
    static var didNotFinish: String { t("Bitiremedi", "Did not finish", "No terminó") }
    static var timeLabel: String { t("SÜRE", "TIME", "TIEMPO") }
    static var gapLabel: String { t("FARK", "GAP", "DIF.") }
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
    /// Online match rules, shown in the lobby.
    static var onlineRaceInfo: String { t("3 tur · turu ilk varan alır · 2 turu alan maçı kazanır", "Best of 3 · first to finish takes the round · 2 rounds win", "Al mejor de 3 · gana la ronda quien llega primero · 2 rondas ganan") }
    static var onlineParkInfo: String { t("3 tur · turu ilk park eden alır · 2 turu alan maçı kazanır", "Best of 3 · first to park takes the round · 2 rounds win", "Al mejor de 3 · gana la ronda quien aparca primero · 2 rondas ganan") }
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
    static var parkTicket: String { t("Otopark fişi", "Parking ticket", "Ticket de aparcamiento") }
    static var ticketIn: String { t("Giriş", "In", "Entrada") }
    static var ticketOut: String { t("Çıkış", "Out", "Salida") }
    // Santim Ölçer (parking precision)
    static var precision: String { t("Hassasiyet", "Precision", "Precisión") }
    static func percent(_ n: Int) -> String { t("%\(n)", "\(n)%", "\(n) %") }
    static var precisionCheck: String { t("SANTİM ÖLÇER", "PRECISION CHECK", "MEDIDOR DE PRECISIÓN") }
    static var gapLeft: String { t("SOL", "LEFT", "IZQ") }
    static var gapRight: String { t("SAĞ", "RIGHT", "DER") }
    static var angleShort: String { t("AÇI", "ANGLE", "ÁNGULO") }
    static func rewardPrecision(_ grade: String) -> String { t("Hassas park \(grade)", "Precision \(grade)", "Precisión \(grade)") }
    static func gradeTitle(_ grade: String) -> String {
        switch grade {
        case "S": return t("KUSURSUZ PARK", "FLAWLESS PARK", "APARCAMIENTO PERFECTO")
        case "A": return t("ÇOK İYİ", "GREAT", "MUY BIEN")
        case "B": return t("İYİ", "GOOD", "BIEN")
        default: return t("GEÇER", "OK", "VALE")
        }
    }
    static var newPrecisionBest: String { t("Yeni en iyi ölçüm", "New best precision", "Nueva mejor precisión") }
    static var newBestShort: String { t("Yeni rekor", "New best", "Nuevo récord") }
    static func place(_ n: Int) -> String { t("\(n). sırada", "Place \(n)", "Puesto \(n)") }
    // Parking challenge
    static var tierNames: [String] {
        [t("KOLAY", "EASY", "FÁCIL"), t("ORTA", "MEDIUM", "MEDIO"), t("ZOR", "HARD", "DIFÍCIL"),
         t("UZMAN", "EXPERT", "EXPERTO"), t("USTA", "MASTER", "MAESTRO")]
    }
    static func ruleTime(_ seconds: Int) -> String { t("\(seconds) sn", "\(seconds) s", "\(seconds) s") }
    static func ruleHits(_ count: Int) -> String { t("En fazla \(count) çarpma", "Max \(count) hits", "Máx. \(count) golpes") }
    static var ruleNoHits: String { t("Sıfır çarpma", "Zero hits", "Cero golpes") }
    static var ruleReverse: String { t("Geri geri park et", "Back it in", "Aparca marcha atrás") }
    static var ruleWet: String { t("Yağmur: ıslak zemin, uzun fren", "Rain: wet ground, longer braking", "Lluvia: suelo mojado, frenada larga") }
    static var ruleSnow: String { t("Kar: çok kaygan, yavaş fren", "Snow: very slippery, slow braking", "Nieve: muy resbaladizo, frenada lenta") }
    static func rulePatrol(_ count: Int) -> String {
        count > 1 ? t("\(count) devriye araç", "\(count) patrol cars", "\(count) coches patrulla")
                  : t("Devriye araç", "Patrol car", "Coche patrulla")
    }
    static var rulePrecise: String { t("Tam hizalama", "Precise alignment", "Alineación exacta") }
    static var timeUp: String { t("Süre doldu!", "Time's up!", "¡Se acabó el tiempo!") }
    static var tooManyHits: String { t("Çok fazla çarpma!", "Too many hits!", "¡Demasiados golpes!") }
    static var reverseHint: String { t("Geri geri gir!", "Back in!", "¡Entra marcha atrás!") }
    static var straightenHint: String { t("Düzelt!", "Straighten up!", "¡Endereza!") }
    static var lastHit: String { t("Son hakkın!", "Last chance!", "¡Última oportunidad!") }
    static func levelTier(_ name: String) -> String { t("Zorluk: \(name)", "Difficulty: \(name)", "Dificultad: \(name)") }
    // Home screen
    static var homeProgress: String { t("Yıldızlar", "Stars", "Estrellas") }
    static var homeYourCar: String { t("Araban", "Your car", "Tu coche") }
    static var homeCareerKicker: String { t("Kariyer", "Career", "Carrera") }
    static var homeCityKicker: String { t("Trafikte yarış", "Race in traffic", "Carrera entre el tráfico") }
    static var homeOnlineKicker: String { t("2 oyuncu", "2 players", "2 jugadores") }
    static var homeTrafficKicker: String { t("Trafikte park", "Park in traffic", "Aparca entre el tráfico") }
    static var homePrivateKicker: String { t("Özel oda", "Private room", "Sala privada") }
    static var playerYou: String { t("Sen", "You", "Tú") }
    static var playerFriend: String { t("Arkadaşın", "Your friend", "Tu amigo") }
    static var waitingShort: String { t("Bekleniyor…", "Waiting…", "Esperando…") }
    static var shareButton: String { t("Kodu paylaş", "Share code", "Compartir código") }
    static var garageRotateHint: String { t("Döndürmek için kaydır", "Swipe to turn", "Desliza para girar") }
    // Spot Wars (city rounds)
    static func spotsLeft(_ n: Int) -> String {
        n == 1 ? t("Son boş yer!", "Last free spot!", "¡Última plaza libre!")
               : t("\(n) boş yer", "\(n) free spots", "\(n) plazas libres")
    }
    static var spotWarsHint: String { t("Dörtlü yakan sürücüler de yer arıyor, onlardan önce park et!",
                                        "Drivers with hazard lights want the same spots: park first!",
                                        "Los conductores con las luces de emergencia buscan las mismas plazas: ¡aparca antes!") }
    static var spotTaken: String { t("Bir sürücü yer kaptı!", "A driver took a spot!", "¡Un conductor cogió una plaza!") }
    static var yourSpotTaken: String { t("Yerini kaptılar! Sıradakine", "Your spot's gone! Next one", "¡Te quitaron la plaza! A la siguiente") }
    static var friendTookSpot: String { t("Rakibin yerini kaptı!", "Your rival took it!", "¡Tu rival te la quitó!") }
    static var lastSpot: String { t("Son boş yer!", "Last free spot!", "¡Última plaza libre!") }
    static var noSpotsLeft: String { t("Yer kalmadı!", "No spots left!", "¡No quedan plazas!") }
    // Taxi
    static var taxiTitle: String { t("Taksi", "Taxi", "Taxi") }
    static var taxiKicker: String { t("Müşteri kap", "Grab the fare", "Consigue clientes") }
    static var taxiInfo: String { t("3 müşteri · rakip taksilerden önce al, isteğini yerine getir, santimine park et", "3 customers · beat the rival taxis to them, give them the ride they want, park spot on", "3 clientes · gánales a los taxis rivales, dales el viaje que quieren y aparca al milímetro") }
    static var onlineTaxiInfo: String { t("3 tur · müşteriyi ilk alan götürür · 2 turu alan kazanır", "Best of 3 · first to pick up the customer takes them · 2 rounds win", "Al mejor de 3 · quien recoge primero al cliente se lo lleva · 2 rondas ganan") }
    static func customerRound(_ n: Int, of total: Int) -> String { t("Müşteri \(n)/\(total)", "Customer \(n)/\(total)", "Cliente \(n)/\(total)") }
    static var pickUpShort: String { t("Müşteriyi al!", "Pick up!", "¡Recógelo!") }
    static var pickUpCustomer: String { t("Yanında dur, binsin", "Stop by them to pick up", "Para a su lado para que suba") }
    static var customerComing: String { t("Müşteri biniyor…", "Customer getting in…", "El cliente sube…") }
    static func riderLine(_ rider: Rider) -> String {
        switch rider {
        case .hurry: return t("\"Acelem var, uçur!\"", "\"I'm late, step on it!\"", "\"¡Llego tarde, písale!\"")
        case .coffee: return t("\"Kahvem dolu, yavaş ol!\"", "\"Full coffee, go easy!\"", "\"Café lleno, ¡con calma!\"")
        case .show: return t("\"Drift at, video çekiyorum!\"", "\"Drift for me, I'm filming!\"", "\"¡Derrapa, estoy grabando!\"")
        case .getaway: return t("\"Polis peşimde, kaçır beni!\"", "\"Cops on my tail, lose them!\"", "\"¡La poli me sigue, despístala!\"")
        }
    }
    static var riderLate: String { t("Geç kaldın, bahşiş yok", "Too late, no tip", "Tarde, sin propina") }
    static var riderSpilled: String { t("Kahve döküldü!", "Coffee spilled!", "¡Café derramado!") }
    static var riderCaught: String { t("Polise yakalandınız!", "The police got you!", "¡Os pilló la poli!") }
    static var crimeGetaway: String { t("Kaçak yolcu", "Runaway passenger", "Pasajero fugitivo") }
    static var rivalGotCustomer: String { t("Rakip taksi müşteriyi kaptı!", "A rival taxi got the customer!", "¡Un taxi rival se llevó al cliente!") }
    static var friendGotCustomer: String { t("Rakibin müşteriyi önce aldı!", "Your rival picked them up first!", "¡Tu rival lo recogió antes!") }
    static func riderTimeLeft(_ s: Int) -> String { t("\(s) sn", "\(s) s", "\(s) s") }
    static func riderCup(_ p: Int) -> String { t("Dökülme %\(p)", "Spill \(p)%", "Derrame \(p)%") }
    static func riderDrift(_ have: Int, _ want: Int) -> String { t("Drift \(max(0, have))/\(want)", "Drift \(max(0, have))/\(want)", "Derrape \(max(0, have))/\(want)") }
    static var riderLoseThem: String { t("Polisi ekt!", "Lose the police!", "¡Despista a la poli!") }
    static var customerHappy: String { t("Müşteri memnun!", "Happy customer!", "¡Cliente feliz!") }
    static var customerDelivered: String { t("Müşteri teslim", "Customer dropped off", "Cliente entregado") }
    static var rewardFare: String { t("Taksi ücreti", "Fare", "Tarifa") }
    static var rewardTip: String { t("Bahşiş", "Tip", "Propina") }
    // Rival racers
    static func racePlace(_ n: Int, of total: Int) -> String { t("Sıra \(n)/\(total)", "Place \(n)/\(total)", "Puesto \(n)/\(total)") }
    static func racePlaceHeadline(_ n: Int) -> String {
        n == 1 ? t("Birinci!", "First place!", "¡Primero!") : t("\(n). oldun", "\(n)\(n == 2 ? "nd" : (n == 3 ? "rd" : "th")) place", "Puesto \(n)")
    }
    static func racePlaceReward(_ n: Int) -> String { t("\(n). sıra", "Place \(n)", "Puesto \(n)") }
    static func racerFinished(_ name: String) -> String { t("\(name) bitirdi!", "\(name) finished!", "¡\(name) llegó!") }
    static var carClassTitle: String { t("Sınıf", "Class", "Clase") }
    static var dailyKicker: String { t("HER GÜN YENİLENİR", "RESETS EVERY DAY", "SE RENUEVA CADA DÍA") }
    static func streakDays(_ days: Int) -> String { t("Seri: \(days) gün", "Streak: \(days) days", "Racha: \(days) días") }
    static var homeContinue: String { t("Devam et", "Continue", "Continuar") }
    static var splashTagline: String { t("Park et. Drift at. Kazan.", "Park it. Drift it. Win it.", "Aparca. Derrapa. Gana.") }
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
    static var policeComing: String { t("POLİS GELİYOR!", "POLICE INCOMING!", "¡VIENE LA POLICÍA!") }
    static var crimeCrash: String { t("Kaza yaptın", "You caused a crash", "Provocaste un choque") }
    static var crimeReckless: String { t("Tehlikeli sürüş", "Reckless driving", "Conducción temeraria") }
    static var crimePedestrian: String { t("Yayaya çarptın", "You hit a pedestrian", "Atropellaste a un peatón") }
    static var crimeDrift: String { t("Yasadışı drift", "Illegal drifting", "Derrape ilegal") }
    static func crimeSpeeding(_ speed: String) -> String { t("Hız ihlali: \(speed)", "Speeding: \(speed)", "Exceso de velocidad: \(speed)") }
    static var policeCaught: String { t("YAKALANDIN! +2 KAZA", "BUSTED! +2 CRASHES", "¡TE PILLARON! +2 CHOQUES") }
    static var bustedTitle: String { t("YAKALANDIN!", "BUSTED!", "¡TE PILLARON!") }
    static var bustedPenalty: String { t("Ceza: +2 kaza · polis seni durdurdu", "Penalty: +2 crashes · pulled over", "Multa: +2 choques · te pararon") }
    static var bustedReleased: String { t("SERBESTSİN, DEVAM!", "YOU'RE FREE, GO!", "¡LIBRE, SIGUE!") }
    static var policeEscaped: String { t("KAÇTIN! NİTRO DOLU", "ESCAPED! FULL NITRO", "¡ESCAPASTE! NITRO LLENO") }
    static var nightDrive: String { t("Gece", "Night", "Noche") }
    static var rainyDrive: String { t("Yağmurlu", "Rain", "Lluvia") }
    static var factoryLivery: String { t("Özel boya", "Signature livery", "Pintura de fábrica") }

    // Progression
    static var coinsLabel: String { t("Para", "Coins", "Monedas") }
    static var rewardFinish: String { t("Tur", "Round", "Ronda") }
    static var rewardStars: String { t("Yıldız", "Stars", "Estrellas") }
    static var rewardClean: String { t("Temiz", "Clean", "Limpio") }
    static var rewardDrift: String { t("Drift", "Drift", "Derrape") }
    static var rewardNearMiss: String { t("Kıl payı", "Near miss", "Por los pelos") }
    static var rewardEscape: String { t("Polisten kaçış", "Police escape", "Fuga") }
    static var taskComplete: String { t("GÖREV TAMAM", "TASK DONE", "TAREA HECHA") }
    static var taskReadyTag: String { t("GÖREV TAMAM · MENÜDEN TOPLA", "TASK DONE · COLLECT IN MENU", "TAREA HECHA · RECÓGELA EN EL MENÚ") }
    static var collectTag: String { t("TOPLA", "COLLECT", "RECOGER") }
    static var collectAll: String { t("Hepsini topla", "Collect all", "Recoger todo") }
    static var claimed: String { t("Toplandı", "Collected", "Recogido") }
    static func rewardsReady(_ n: Int) -> String {
        t("\(n) görev ödülü hazır", n == 1 ? "1 task reward ready" : "\(n) task rewards ready", n == 1 ? "1 premio listo" : "\(n) premios listos")
    }
    static var dailyTitle: String { t("Günlük", "Daily", "Diario") }
    static var dailyTasks: String { t("Bugünün görevleri", "Today's tasks", "Tareas de hoy") }
    static var dailyTasksHint: String { t("Her gün yenilenir; tamamladığın görevin ödülünü buradan topla.", "New every day; collect a finished task's coins here.", "Nuevas cada día; recoge aquí las monedas de cada tarea hecha.") }
    static var rewardWaiting: String { t("Ödül hazır", "Reward ready", "Premio listo") }
    static var dailyGift: String { t("Günlük hediye", "Daily gift", "Regalo diario") }
    static var dailyGiftHint: String { t("Her gün gel, hediye büyüsün. Bir gün kaçırırsan seri baştan başlar.", "Come back daily and the gift grows. Miss a day and the streak restarts.", "Vuelve cada día y el regalo crece. Si faltas un día, la racha se reinicia.") }
    static func dayLabel(_ day: Int) -> String { t("\(day). gün", "Day \(day)", "Día \(day)") }
    static var collect: String { t("Al", "Collect", "Recoger") }
    static var collected: String { t("Alındı", "Collected", "Recogido") }
    static var comeBackTomorrow: String { t("Yarın yine gel", "Come back tomorrow", "Vuelve mañana") }
    static func unlockFor(_ price: Int) -> String { t("\(price) PARAYA AÇ", "UNLOCK · \(price)", "DESBLOQUEAR · \(price)") }
    static func needMoreCoins(_ missing: Int) -> String { t("\(missing) para daha gerek", "\(missing) more coins needed", "Faltan \(missing) monedas") }
    static var locked: String { t("Kilitli", "Locked", "Bloqueado") }
    static var carUnlocked: String { t("Yeni araba açıldı", "New car unlocked", "Coche desbloqueado") }
    static var addedToGarage: String { t("Garajına eklendi", "Added to your garage", "Añadido a tu garaje") }
    static var tapToContinue: String { t("Devam etmek için dokun", "Tap to continue", "Toca para continuar") }
    static var quickMatch: String { t("Hızlı eşleşme", "Quick match", "Partida rápida") }
    static var quickMatchSub: String { t("Rastgele bir rakiple hemen yarış", "Race a random opponent right away", "Compite ya contra un rival al azar") }
    static var searching: String { t("Rakip aranıyor…", "Finding an opponent…", "Buscando rival…") }
    static var noOpponent: String { t("Şu an rakip bulunamadı: trafiğe karşı yarışa başlıyorsun.", "No opponent found right now: racing the city traffic instead.", "No hay rivales ahora: corres contra el tráfico.") }
    /// A quiet greeting on the home screen, by the time of day.
    static var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 5 || hour >= 22 { return t("İyi geceler", "Good night", "Buenas noches") }
        if hour < 12 { return t("Günaydın", "Good morning", "Buenos días") }
        if hour < 18 { return t("İyi günler", "Good afternoon", "Buenas tardes") }
        return t("İyi akşamlar", "Good evening", "Buenas noches")
    }
    static var weekendBonus: String { t("Hafta sonu x2", "Weekend x2", "Fin de semana x2") }
    static var weekendEvent: String { t("HAFTA SONU ETKİNLİĞİ · 2x PARA", "WEEKEND EVENT · 2x COINS", "EVENTO DE FIN DE SEMANA · 2x MONEDAS") }
    static var upgrade: String { t("Geliştir", "Upgrade", "Mejorar") }
    static var upgradeHint: String { t("Her seviye arabanı her modda güçlendirir: motor +5 km/sa son hız ve daha güçlü çekiş, yol tutuş daha keskin viraj, nitro daha güçlü itiş ve daha hızlı dolum.", "Every level makes your car better in every mode: engine +5 km/h top speed and more pull, grip sharper corners, nitro a stronger push that refills faster.", "Cada nivel mejora tu coche en todos los modos: motor +5 km/h de punta y más empuje, agarre curvas más cerradas, nitro más fuerte y que se recarga antes.") }
    static var upgradeEngine: String { t("Motor", "Engine", "Motor") }
    static var upgradeGrip: String { t("Yol tutuş", "Grip", "Agarre") }
    static var upgradeNitro: String { t("Nitro", "Nitro", "Nitro") }
    static var upgradeEngineInfo: String { t("+5 km/sa son hız, daha güçlü çekiş", "+5 km/h top speed, more pull", "+5 km/h de punta, más empuje") }
    static var upgradeGripInfo: String { t("Virajda daha az kayma", "Less sliding in corners", "Menos derrape en curvas") }
    static var upgradeNitroInfo: String { t("Daha güçlü ve hızlı dolan nitro", "Stronger nitro that fills faster", "Nitro más fuerte y rápido") }
    static var maxLevel: String { t("MAKS", "MAX", "MÁX") }
    static var rims: String { t("Jant", "Rims", "Llantas") }
    static func taskTitle(_ kind: Progression.TaskKind) -> String {
        let n = kind.target
        switch kind {
        case .parkRounds: return t("\(n) park bölümü bitir", "Finish \(n) parking levels", "Termina \(n) niveles de aparcamiento")
        case .threeStars: return t("\(n) bölümü 3 yıldızla bitir", "3-star \(n) levels", "Termina \(n) niveles con 3 estrellas")
        case .parkClean: return t("\(n) bölümü hiç çarpmadan park et", "Park \(n) levels without a hit", "Aparca \(n) niveles sin chocar")
        case .parkFlawless: return t("Bir bölümü 3 yıldız ve sıfır çarpmayla bitir", "A level with 3 stars and zero hits", "Un nivel con 3 estrellas y sin golpes")
        case .parkStars: return t("Park bölümlerinden \(n) yıldız topla", "Collect \(n) stars in parking levels", "Consigue \(n) estrellas aparcando")
        case .cityRounds: return t("Şehirde \(n) tur bitir", "Finish \(n) city rounds", "Termina \(n) rondas en la ciudad")
        case .nearMiss: return t("Şehirde \(n) kıl payı geçiş", "\(n) near misses in the city", "\(n) adelantamientos por los pelos en la ciudad")
        case .escape: return t("Polisten kaç", "Escape the police", "Escapa de la policía")
        case .drift: return t("Şehirde \(n) drift puanı", "\(n) drift points in the city", "\(n) puntos de derrape en la ciudad")
        case .cityClean: return t("Bir şehir turunu hiç çarpmadan bitir", "A city round without a crash", "Una ronda en la ciudad sin chocar")
        case .raceRounds: return t("\(n) yarış bitir", "Finish \(n) races", "Termina \(n) carreras")
        case .raceClean: return t("Bir yarışı hiç çarpmadan bitir", "A race without a crash", "Una carrera sin chocar")
        case .topSpeed: return t("Yarışta \(n) km/sa hıza çık", "Reach \(n) km/h in a race", "Alcanza \(n) km/h en una carrera")
        case .raceDrift: return t("Yarışlarda \(n) drift puanı", "\(n) drift points in races", "\(n) puntos de derrape en carreras")
        case .raceNearMiss: return t("Yarışlarda \(n) kıl payı geçiş", "\(n) near misses in races", "\(n) adelantamientos por los pelos en carreras")
        case .onlineRounds: return t("Arkadaşınla \(n) tur oyna", "Play \(n) rounds with a friend", "Juega \(n) rondas con un amigo")
        case .onlineWin: return t("Arkadaşına karşı kazan", "Beat your friend", "Gana a tu amigo")
        case .perfectPark: return t("Bir bölümü kusursuz (S) park et", "Make a flawless (S) park", "Aparca a la perfección (S)")
        }
    }
}

extension String {
    /// Upper case by the game's language (Turkish i → İ).
    var localUpper: String { Strings.upper(self) }
}
