# Parkrift (eski adı ParkPark)

Arkadaşınla aynı otoparkta, online araba park etme oyunu (SwiftUI + SceneKit 3D dünya + SpriteKit HUD, yatay ekran). Repo adı ve bundle ID tarihsel olarak `hop`.

- **Oynanış:** Kuşbakışı otoparkta arabanı kendi renginde işaretli yere park et. Araba tamamen çizgilerin içinde, yönü hizalı ve durmuş halde 1 saniye kalınca park sayılır. 10 bölüm, kolaydan zora: düz park, dik park, araba arası, açılı park, etrafından dolaşma, paralel park, labirent, dar yerler, sıkı paralel, final garaj.
- **Online:** "Oda Kur" 4 harfli kod üretir, arkadaşın "Odaya Katıl" ile kodu girer. İkiniz aynı haritada, herkesin kendi park yeri var; ikiniz de park edince bölüm geçilir, önce park eden 👑 alır. Süre ve çarpma sayısı karşılaştırılır.
- **Tek başına:** Aynı bölümler, sadece kendi yerin.
- **Kontroller:** Sol altta ◀ ▶ yön tuşları (basılı tutunca tekerlekler yavaşça döner, bırakınca ortalanır; üstteki sarı çubuk dönüş miktarını gösterir), sağ altta İLERİ ve GERİ pedalları. Otomatik vites (D/R): ters pedal önce fren yapar, durunca vites değişir; pedal bırakılınca araba yavaşça süzülür. Üstte ✕ menü, ↻ arabayı başa alır. Gaz pedalının üstündeki KORNA butonu korna çalar; iki kişilik oyunda arkadaşın da duyar (sunucu üzerinden `{"t":"hn"}` mesajı).
- **Şehir yarışı (iki kişilik oyun / "Şehirde Sür"):** 340 x 230 m'lik cadde ızgarası (`Hop/City.swift`), binalar, yol kenarı park yerleri, sağ şeritten giden ve kavşakta rastgele dönen trafik botları (online'da botları oda sahibi yönetir, `{"t":"b"}`). Mini harita ve üstteki yön göstergesi en kısa rotayı gösterir ("Sola dön · 40 m"). 5 tur; ilk park eden turu kazanır, diğerine 20 sn kalır.
- **Kenarlar:** Kaldırım, duvar veya park etmiş arabaya sürtününce araba durmaz, boş eksende kayarak devam eder; sadece sert çarpmalar çarpma sayılır.
- **Ses:** `.playback` oturumu, telefon sessizdeyken de korna/müzik duyulur.
- **Araba Yarışı:** Aynı şehirde, uzaktaki damalı bitiş çizgisine yarış; 40 trafik botu. Puan = süre + her kaza (çarpma) için 3 sn (`Levels.raceScore`); en düşük puan turu kazanır. 3 tur. Lobide oda sahibi Araba Yarışı / Park Yarışı seçer (`{"t":"mode"}`).
- **Nitro:** Depo sürerken 10 sn'de dolar; dolunca NİTRO butonu (geri pedalının solunda) 3 sn boyunca ekstra itiş ve %70 daha yüksek tavan hız verir. Egzoz alevleri (online'da arkadaşın da görür), hız çizgileri, mavi kenar parlaması, geniş kamera açısı ve whoosh sesi (`tools/make_nitro.py`).
- **Oyuncu arabaları:** Yarış arabası modeli (alçak gövde, çift beyaz şerit, arka kanat, splitter, çift egzoz).
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

## Credits

Garage cars:

- "Rosso GT", "Strada S", "Tempesta", "Arrow GT", "Bison", "Classico 87": original designs made for this
  game with Meshy AI (https://www.meshy.ai; text-to-image, then image-to-3D). They were prompted as invented
  cars that do not copy any real make or model, and carry no badges, logos or plates. Converted with
  `tools/convert_meshy_cars.py` (Blender). Files `Hop/Models/<id>_body.usdz`, `<id>_wheel.usdz`,
  `<id>_basecolor.jpg`, `<id>_mask.png`. Meshy's free plan licenses its output under CC BY 4.0 (credit: Meshy AI);
  paid plans give full ownership.
- "Vector X": "Car Concept" from the Khronos glTF Sample Assets (https://github.com/KhronosGroup/glTF-Sample-Assets),
  CC BY 4.0 © Khronos Group, based on the CC0 "Free Concept Car 004" by Unity Fan (an original concept design).
  Modified: licence plate and Khronos logos removed, wipers removed, decimated, converted to USDZ (`tools/convert_cars.py`).
- "Hot Rod 55": "Toy Car" from the Khronos glTF Sample Assets, CC0. Modified: fabric and cameras removed,
  wheels cut out to spin, paint areas made tintable, decimated, converted to USDZ (`tools/convert_cars.py`).
- Traffic and parked vehicles: Kenney's "Car Kit" (https://kenney.nl/assets/car-kit), CC0, generic designs.
  Converted with `tools/convert_kenney.py` (stretched a little). Files `Hop/Models/kenney_*`.

Street props and the police car: Polyfork (https://polyfork.dev, licence: use in commercial projects, no
attribution required, no redistribution of the files themselves): "Site Traffic Cone", "Oil-drum", "Wire Trash
Basket", "Police Barricade", "Police Cruiser" (free low poly editions, USDZ exports). Files `Hop/Models/pf_*.usdz`.
Pedestrians and the traffic light: original Meshy AI models (`tools/convert_meshy_people.py`,
`tools/convert_meshy_props.py`). Street textures and sounds: procedural (`tools/make_road_textures.py`,
`tools/make_crash.py`, `tools/make_arcade_sounds.py`).

No car in the game is a replica of a real make or model (earlier builds used Sketchfab replicas of real
cars; they were removed because a free model licence does not cover the car maker's design and trademark rights).

## App Store

- Privacy policy: https://parkpark.huseyinglc0-946.workers.dev/privacy
- Support: https://parkpark.huseyinglc0-946.workers.dev/support
- Both pages are served by the room server (`server/index.js`).
- The benchmark modes only exist in builds compiled with the `BENCHMARK` condition (benchmark workflow).
