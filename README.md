# ParkPark

Arkadaşınla aynı otoparkta, online araba park etme oyunu (SwiftUI + SceneKit 3D dünya + SpriteKit HUD, yatay ekran). Repo adı ve bundle ID tarihsel olarak `hop`.

- **Oynanış:** Kuşbakışı otoparkta arabanı kendi renginde işaretli yere park et. Araba tamamen çizgilerin içinde, yönü hizalı ve durmuş halde 1 saniye kalınca park sayılır. 10 bölüm, kolaydan zora: düz park, dik park, araba arası, açılı park, etrafından dolaşma, paralel park, labirent, dar yerler, sıkı paralel, final garaj.
- **Online:** "Oda Kur" 4 harfli kod üretir, arkadaşın "Odaya Katıl" ile kodu girer. İkiniz aynı haritada, herkesin kendi park yeri var; ikiniz de park edince bölüm geçilir, önce park eden 👑 alır. Süre ve çarpma sayısı karşılaştırılır.
- **Tek başına:** Aynı bölümler, sadece kendi yerin.
- **Kontroller:** Sol altta sürüklenerek çevrilen direksiyon (bırakınca ortalanır; çevresindeki sarı yay ve SOL/SAĞ yazısı tekerleklerin ne kadar döndüğünü gösterir), sağ altta İLERİ ve GERİ pedalları. Otomatik vites (D/R): ters pedal önce fren yapar, durunca vites değişir; pedal bırakılınca araba yavaşça süzülür. Üstte ✕ menü, ↻ arabayı başa alır. Gaz pedalının üstündeki KORNA butonu korna çalar; iki kişilik oyunda arkadaşın da duyar (sunucu üzerinden `{"t":"hn"}` mesajı).
- **Sürüş modeli:** Bisiklet modeli + hıza bağlı direksiyon açısı, azalan motor ivmesi, yuvarlanma ve hava direnci, frende/gazda/virajda gövde yatması, stop ve geri lambaları, fren izi, lastik dumanı, çarpınca seken geri tepme.
- **Grafik:** Low-poly 3D dünya (`Hop/World3D.swift`): arabanın arkasından takip eden kamera (yön her zaman ileri), sol üstte mini harita, güneş ışığı ve gölgeler, ilkel geometrilerden arabalar (dönen ve direksiyonla dönen tekerlekler, stop/geri lambaları, gövde yatması), duvarlar, dubalar, ağaçlar, direkler. Dokular kodla çiziliyor (`Hop/CarArt.swift`). HUD ve kontroller 2D (SpriteKit) katmanda.
- **Ses:** Özgün, kodla sentezlenmiş döngü müziği ve efektler (`Hop/Audio`): hıza göre perdesi değişen motor sesi, çarpma, park, geri sayım. Menüde ve oyunda ses kapatma düğmesi. Ses kategorisi `ambient`: telefon sessizdeyse ses çıkmaz.
- **Dil:** Cihaz Türkçe ise Türkçe, değilse İngilizce.
- **Gereksinimler (Ekim 2026):** Xcode 26 / iOS 26 SDK ile derlenir (`macos-15` runner + Xcode 26.x), minimum iOS 17, privacy manifest (UserDefaults · `CA92.1`), `ITSAppUsesNonExemptEncryption = NO` (yalnızca sistemin standart TLS'i kullanılıyor), tek boyutlu 1024px ikon.

## Proje yapısı

| Yol | Ne |
|---|---|
| `project.yml` | XcodeGen proje tanımı (Xcode projesi CI'da üretilir) |
| `Support/Info.plist` | Uygulama ayarları (yatay yön, görünen ad) |
| `Hop/HopApp.swift` | Uygulama girişi, AppModel, menü ve lobi ekranları |
| `Hop/ParkingScene.swift` | Oyun: araba fiziği, çarpışma, park algılama, kontroller, bölüm akışı |
| `Hop/Levels.swift` | 10 bölümün haritaları (1000×500 dünya) |
| `Hop/Geometry.swift` | Döndürülmüş kutu (OBB) çarpışma hesapları |
| `Hop/World3D.swift` | 3D sahne, kamera, araba modeli, bölüm nesneleri |
| `Hop/AudioManager.swift` | Müzik, motor sesi ve efektler (AVAudioEngine) |
| `Hop/Audio/` | Sentezlenmiş müzik ve ses dosyaları |
| `Hop/CarArt.swift` | Kodla çizilen dokular |
| `Hop/NetClient.swift` | Oda sunucusuna WebSocket bağlantısı |
| `Hop/Strings.swift` | TR/EN metinler |
| `server/index.js` | Cloudflare Worker + Durable Object oda sunucusu (`parkpark`) |
| `server/test-rooms.mjs` | İki sahte oyuncuyla sunucu testi |
| `.github/workflows/testflight.yml` | Derle → imzala → TestFlight'a yükle |
| `.github/workflows/server-check.yml` | Sunucu testi |

## Oda sunucusu

`https://parkpark.huseyinglc0-946.workers.dev` — `GET /health`, WebSocket: `/room/ABCD?role=host|guest`. Odada en fazla 2 kişi; sunucu sadece mesajları karşı tarafa iletir (`welcome`, `join`, `leave`, `full`, `noroom`, `ping/pong`; oyun mesajları `s` konum, `p` park etti, `lvl` bölüm başlat).

## Bir kerelik kurulum (telefondan yapılabilir)

1. **Bundle ID kaydı** — developer.apple.com/account → Certificates, IDs & Profiles → Identifiers → **+** → App IDs → App → Description: `Hop`, Bundle ID (Explicit): `com.huseyingulcu.hop` → Register.
2. **Uygulama kaydı** — appstoreconnect.apple.com → Apps → **+** → New App → iOS, isim (mağazada benzersiz olmalı, ör. `Hop! HG`), dil, Bundle ID: `com.huseyingulcu.hop`, SKU: `hop-001`.
3. **Yaş derecelendirmesi** — Uygulama → App Information → Age Rating → soruları yanıtla (bu oyun için hepsi "Hayır/Yok").
4. **API anahtarı** — App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **Generate API Key**, erişim: **Admin** (otomatik imzalama için gerekli). `.p8` dosyasını indir (yalnızca bir kez indirilebilir), **Key ID** ve **Issuer ID**'yi not al.
5. **Team ID ve Issuer ID** — workflow dosyasına yazılı (gizli bilgi değil; asıl gizli olan `.p8` dosyası).
6. **GitHub secrets** — repo → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID` → Key ID ("Copy Key ID" ile)
   - `ASC_KEY_P8` → `.p8` dosyasının tüm içeriği (`-----BEGIN PRIVATE KEY-----` dahil). iPhone'da: Dosyalar uygulamasında dosyayı `.txt` olarak yeniden adlandırıp açarsan metni kopyalayabilirsin.

## Derleme

`main` dalına her push'ta (veya Actions sekmesinden **Run workflow** ile) çalışır. Build numarası otomatik olarak çalıştırma sayısı olur. Yükleme bittikten sonra Apple'ın işlemesi 5–30 dk sürer; ardından App Store Connect → TestFlight → Internal Testing grubuna kendini ekle ve TestFlight uygulamasından yükle.
