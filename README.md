# Hop!

Dokun-zıpla tarzı basit bir iOS oyunu (SwiftUI + SpriteKit). Amacı, GitHub Actions üzerinden TestFlight hattını uçtan uca denemek.

- **Oynanış:** Dokun → zıpla, havada tekrar dokun → çift zıpla. Engelleri geç, skor yap. Rekor cihazda saklanır.
- **Dil:** Cihaz Türkçe ise Türkçe, değilse İngilizce.
- **Gereksinimler (Ekim 2026):** Xcode 26 / iOS 26 SDK ile derlenir (`macos-26` runner), minimum iOS 17, privacy manifest (UserDefaults · `CA92.1`), `ITSAppUsesNonExemptEncryption = NO`, tek boyutlu 1024px ikon.

## Proje yapısı

| Yol | Ne |
|---|---|
| `project.yml` | XcodeGen proje tanımı (Xcode projesi CI'da üretilir) |
| `Support/Info.plist` | Uygulama ayarları |
| `Hop/HopApp.swift` | Uygulama girişi ve SpriteView |
| `Hop/GameScene.swift` | Oyunun tamamı |
| `Hop/Strings.swift` | TR/EN metinler |
| `Hop/PrivacyInfo.xcprivacy` | Privacy manifest |
| `.github/workflows/testflight.yml` | Derle → imzala → TestFlight'a yükle |

## Bir kerelik kurulum (telefondan yapılabilir)

1. **Bundle ID kaydı** — developer.apple.com/account → Certificates, IDs & Profiles → Identifiers → **+** → App IDs → App → Description: `Hop`, Bundle ID (Explicit): `com.huseyingulcu.hop` → Register.
2. **Uygulama kaydı** — appstoreconnect.apple.com → Apps → **+** → New App → iOS, isim (mağazada benzersiz olmalı, ör. `Hop! HG`), dil, Bundle ID: `com.huseyingulcu.hop`, SKU: `hop-001`.
3. **Yaş derecelendirmesi** — Uygulama → App Information → Age Rating → soruları yanıtla (bu oyun için hepsi "Hayır/Yok").
4. **API anahtarı** — App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → **Generate API Key**, erişim: **Admin** (otomatik imzalama için gerekli). `.p8` dosyasını indir (yalnızca bir kez indirilebilir), **Key ID** ve **Issuer ID**'yi not al.
5. **Team ID** — developer.apple.com/account → Membership details → Team ID.
6. **GitHub secrets** — repo → Settings → Secrets and variables → Actions → New repository secret:
   - `ASC_KEY_ID` → Key ID
   - `ASC_ISSUER_ID` → Issuer ID
   - `TEAM_ID` → Team ID
   - `ASC_KEY_P8` → `.p8` dosyasının tüm içeriği (`-----BEGIN PRIVATE KEY-----` dahil). iPhone'da: Dosyalar uygulamasında dosyayı `.txt` olarak yeniden adlandırıp açarsan metni kopyalayabilirsin.

## Derleme

`main` dalına her push'ta (veya Actions sekmesinden **Run workflow** ile) çalışır. Build numarası otomatik olarak çalıştırma sayısı olur. Yükleme bittikten sonra Apple'ın işlemesi 5–30 dk sürer; ardından App Store Connect → TestFlight → Internal Testing grubuna kendini ekle ve TestFlight uygulamasından yükle.
