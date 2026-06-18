# Paylisher Deeplink — Test Runbook (iOS + Android)

`test-ios-paylisher` ve `test-android-paylisher` artık **gerçek ekranlı, alt tab bar'lı** uygulamalar.
Paylisher Studio'dan oluşturduğun deeplink'ler somut ekranlara yönlenir.

> Aynı runbook her iki repoda da bulunur.

---

## 1) Ne kuruldu

- Akış: **Login → alt tab bar.** Sekmeler: **🏠 Ana Sayfa · 🛍️ Ürünler · 🎁 Kampanyalar · 💳 Cüzdan (auth) · 👤 Profil**
- **Ürünler iç içe:** Liste → Ürün detayı → Ürün İçeriği (3 seviye).
- **Kampanyalar iç içe:** Liste → Kampanya detayı → Başvuru (auth-gate'li, en iç). Vakıf Katılım "Çeyiz Hesabı" senaryosundan esinli; firmaların deeplink ile bağlayacağı iniş hedefi.
- **Cüzdan auth-gate'li:** kilitli; deeplink/giriş ile açılır.
- Yönlendirme, gelen deeplink **URL'i parse edilerek** yapılır (host + path) → sekme + iç içe yol.
- Mevcut **event / multi-SDK push** testleri **Ana Sayfa**'da; **deeplink debug log** **Profil → Geliştirici**'de.
- Scheme `paylishertest` · App-link domain `link.paylisher.com` · auth-gate hedefi `wallet` + `?auth=required` taşıyan her link (örn. kampanya başvurusu).

---

## 1b) Minimal entegrasyon (yeni SDK API — müşterinin yazacağı tüm kod)

Attribution (`campaign_key`/`deeplink_key`/`jid`, session-scoped), manager-init ve cold-start **otomatik**. Protokol/interface yok.

**iOS (SwiftUI):**
```swift
let config = PaylisherConfig(apiKey: "...", host: "...")
config.deepLinkConfig = PaylisherDeepLinkConfig()   // customSchemes / universalLinkDomains / authRequiredDestinations
PaylisherSDK.shared.setup(config)                   // deeplink manager + attribution otomatik

PaylisherSDK.shared.onDeepLink { deepLink, requiresAuth in /* hedefe git */ }
PaylisherSDK.shared.onDeepLinkRequiresAuth { deepLink, complete in /* login → */ complete(true) }

// root view'a tek satır (onOpenURL + onContinueUserActivity):
ContentView().paylisherDeepLinks()
```

**Android:**
```kotlin
// Application.onCreate
val config = PaylisherAndroidConfig(apiKey = "...").apply {
    deepLinkConfig = PaylisherDeepLinkConfig(customSchemes = listOf("paylishertest"), authRequiredDestinations = listOf("wallet"))
}
PaylisherAndroid.setup(this, config)                // cold-start (onCreate) dâhil otomatik
PaylisherAndroid.onDeepLink { deepLink, requiresAuth -> /* hedefe git */ }
PaylisherAndroid.onDeepLinkRequiresAuth { deepLink, complete -> complete(true) }

// MainActivity — sadece warm start için tek satır:
override fun onNewIntent(intent: Intent) { super.onNewIntent(intent); setIntent(intent); PaylisherAndroid.handleDeepLink(intent) }
```
> Info.plist scheme + associated-domains / AndroidManifest intent-filter + AASA/assetlinks **OS gereği** hâlâ gerekir; kod tarafı yukarısı kadar.

---

## 2) Deeplink → ekran haritası  ⭐ (Studio'da kullanacakların)

| Deeplink | Açılan ekran |
|---|---|
| `paylishertest://home` | Ana Sayfa |
| `paylishertest://products` | Ürünler (liste) |
| `paylishertest://products/a` | Ürün A detayı (`a` / `b` / `c`) |
| `paylishertest://products/a/content` | Ürün A İçeriği (en iç ekran) |
| `paylishertest://campaigns` | Kampanyalar (liste) |
| `paylishertest://campaigns/ceyiz` | Çeyiz Hesabı detayı (`ceyiz` / `konut` / `altin` / `cocuk`) |
| `paylishertest://campaigns/ceyiz/apply` | Çeyiz başvuru — auth-gate'li (en iç ekran) |
| `paylishertest://wallet` | Cüzdan (önce auth-gate → kilit açılır) |
| `paylishertest://profile` | Profil |

`products?id=a` ve `campaigns?slug=ceyiz` (query) de path biçimiyle aynı çalışır. Bilinmeyen host → Ana Sayfa.

---

## 2b) Firma kampanya deeplink'i 🏢 (kampanya oluşturan firmalar için)

Bir firma Paylisher Studio'da kampanyayı kurunca bir **`keyName`** alır ve deeplink'ine ekler.
SDK bu `keyName`'i **`campaignData`**'ya resolve eder (Kampanyalar sekmesinde "🎯 Studio'dan çözülen kampanya" banner'ı). Firmanın bağlayacağı tipik link biçimleri:

| Deeplink | Ne yapar |
|---|---|
| `paylishertest://campaigns/ceyiz?keyName=CEYIZ2026&source=push` | Çeyiz detayına gider; `keyName` resolve, `source` attribution |
| `paylishertest://campaigns/ceyiz/apply?auth=required&source=email` | Başvuruya gider; **`auth=required`** giriş yoksa cold-start'ta önce login ister |
| `paylishertest://campaigns?keyName=CEYIZ2026&source=sms` | Sadece key — SDK resolve eder, banner'da görünür |

Firma-tarafı parametreler (SDK parse eder): **`keyName`/`key`** → kampanya resolve · **`campaign_id`/`campaign`** · **`source`** · **`jid`** · **`auth=required`** → auth-gate.
Bu linkler app içinde **Profil → Geliştirici → Deeplink Log → 🏢 Firma kampanya deeplink'i** bölümünden tek tıkla denenir.

---

## 3) Paylisher Studio'da deeplink oluşturma

"Deeplink oluştur" formunda:
- **Web URL** (zorunlu): örn. `https://paylisher.com`
- **Scheme (Custom URI Scheme):** yukarıdaki tablodan biri — örn. `paylishertest://products/a/content`
- (Universal Link de istiyorsan) **Universal / App Link (HTTPS):** `https://link.paylisher.com/products/a`

Linki oluştur → çıkan `pyl.sh/<key>` linkini cihazda aç → bridge `paylishertest://...`'i açar → uygulama o ekrana yönlenir.

---

## 4) Studio olmadan hızlı test (komut satırı)

### iOS (simülatör)
```bash
xcrun simctl openurl booted "paylishertest://home"
xcrun simctl openurl booted "paylishertest://products"
xcrun simctl openurl booted "paylishertest://products/a"
xcrun simctl openurl booted "paylishertest://products/a/content"   # en iç ekrana kadar
xcrun simctl openurl booted "paylishertest://campaigns"
xcrun simctl openurl booted "paylishertest://campaigns/ceyiz"      # Çeyiz Hesabı detayı
xcrun simctl openurl booted "paylishertest://campaigns/ceyiz/apply?auth=required"  # başvuru (auth-gate)
xcrun simctl openurl booted "paylishertest://campaigns/ceyiz?keyName=CEYIZ2026&source=push"  # firma linki
xcrun simctl openurl booted "paylishertest://wallet"               # auth-gate
xcrun simctl openurl booted "paylishertest://profile"
```
Build + kur:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project PaylisherTestiOS.xcodeproj -scheme PaylisherTestiOS -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/plt-ios-build build
xcrun simctl install booted /tmp/plt-ios-build/Build/Products/Debug-iphonesimulator/PaylisherTestiOS.app
xcrun simctl launch booted com.paylisher.test.ios
```

### Android (emülatör/cihaz)
```bash
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
export ANDROID_HOME="$HOME/Library/Android/sdk"
./gradlew :app:installDebug
PKG=com.paylisher.test
adb shell am start -W -a android.intent.action.VIEW -d "paylishertest://products/a" $PKG
adb shell am start -W -a android.intent.action.VIEW -d "paylishertest://products/a/content" $PKG
adb shell am start -W -a android.intent.action.VIEW -d "paylishertest://campaigns/ceyiz" $PKG
adb shell am start -W -a android.intent.action.VIEW -d "paylishertest://campaigns/ceyiz/apply?auth=required" $PKG
adb shell am start -W -a android.intent.action.VIEW -d "paylishertest://campaigns/ceyiz?keyName=CEYIZ2026&source=push" $PKG
adb shell am start -W -a android.intent.action.VIEW -d "paylishertest://wallet" $PKG
```
Log: `adb logcat -s DeepLink:* Paylisher:*`

---

## 5) Cold-start (uygulama kapalıyken)

Login ekranı korunuyor: deeplink kapalı uygulamada tıklanırsa, önce **giriş yap** → tab bar açılır
açılmaz **hedef ekrana yönlenir** (URL, login sırasında DeepLinkRouter durumuna yazıldığı için).
Örn. `paylishertest://products/a/content` → giriş → Ürünler → Ürün A → İçerik.

---

## 6) Auth-gate testi (Cüzdan + Kampanya başvurusu)

1. `paylishertest://wallet` aç → SDK `requiresAuth` → **Cüzdan kilit ekranı** açılır.
2. **"Giriş Yap / Kimlik Doğrula"** → kilit açılır, cüzdan içeriği görünür (SDK `completion(true)` → pending tamamlanır).
3. Cüzdan içindeki **"Kilidi Sıfırla"** ile yeniden test edebilirsin.
4. Kilitliyken Cüzdan sekmesine elle dokunmak da aynı kilit ekranını gösterir.

**İki auth-gate mekanizması var:**
- **Destination tabanlı:** `authRequiredDestinations = ["wallet"]` — `wallet` hedefi her zaman auth ister.
- **Link tabanlı (`?auth=required`):** firmanın işaretlediği herhangi bir link. SDK içinde `isAuthRequired = config.isAuthRequired(destination) || authParamRequired`. Kampanya başvurusu bunu kullanır:
  - Kapalı uygulamada `paylishertest://campaigns/ceyiz/apply?auth=required` → önce **login** → giriş sonrası doğrudan **Çeyiz → Başvuru** ekranına yönlenir.
  - Açık (login'li) uygulamada aynı link doğrudan başvuruya gider (re-login yok).

---

## 7) Universal Link / App Link + sunucu dosyaları

Gerçek OS açılışı için `link.paylisher.com` üzerinde iki dosya yayınlanmalı (repolardaki `well-known/`):

**iOS** → `https://link.paylisher.com/.well-known/apple-app-site-association` (uzantısız, `application/json`):
```json
{ "applinks": { "apps": [], "details": [
  { "appID": "5442A5ZMH8.com.paylisher.test.ios",
    "paths": ["/home","/products","/products/*","/campaigns","/campaigns/*","/wallet","/profile"] } ] } }
```
**Android** → `https://link.paylisher.com/.well-known/assetlinks.json`:
```json
[ { "relation": ["delegate_permission/common.handle_all_urls"],
    "target": { "namespace": "android_app", "package_name": "com.paylisher.test",
      "sha256_cert_fingerprints": ["FB:E8:32:A7:26:E8:E1:1B:2D:9E:D0:2B:69:27:18:A1:7F:63:3E:98:A5:E6:1C:9D:86:54:EE:39:86:2E:95:0C"] } } ]
```
> ⚠️ Domain dietapp ile paylaşımlıysa **mevcut girdilere EKLE, üzerine yazma.**

Doğrulama:
```bash
curl -s https://link.paylisher.com/.well-known/apple-app-site-association | jq .
adb shell pm get-app-links com.paylisher.test
```
AASA yayınlanana kadar: iOS'ta Profil→Geliştirici→Deeplink Log'daki "Simüle Et", Android'de `adb VIEW` ile test edilir.

---

## 8) Deferred deeplink

Profil → Geliştirici → Deeplink Log'da son kontrol sonucu görünür. Gerçek match için: uygulamayı sil →
backend'de cihaz fingerprint'i ile tıklama kaydı oluştur → yeniden kur ve giriş yap → ilk açılışta eşleşirse
hedefe yönlenir.

---

## 9) Debug log (Profil → Geliştirici → Deeplink Log)

Handler'a düşen her olayı (url, destination, scheme, jid, campaignKey, title) listeler; ayrıca Studio'ya
gitmeden hızlı URL denemesi için hazır butonlar içerir. Asıl test gerçek ekranlarla yapılır; bu yalnızca debug.

---

## 10) Sorun giderme
- **Ekran açılmıyor:** doğru host/path mi? (`products/a`, `products/a/content`). Bilinmeyen host Ana Sayfa'ya düşer.
- **Universal link uygulamayı açmıyor:** AASA/assetlinks yayınlanmamış olabilir (Bölüm 7). iOS AASA cache'i için uygulamayı silip yeniden kur.
- **Cüzdan hep kilitli:** auth-gate beklenen davranış; "Giriş Yap" ile açılır, "Kilidi Sıfırla" ile tekrar kilitlenir.

---

## 11) Sana bağlı (production öncesi)
1. **Canlı `keyName`** → `DeepLinkTestConfig.defaultCampaignKey` (iOS) / `DeepLinkTestConfig.DEFAULT_CAMPAIGN_KEY` (Android), şu an `REPLACE_WITH_LIVE_KEY`.
2. **AASA + assetlinks.json**'ı `link.paylisher.com/.well-known/`'a yayınla (mevcut girdilere ekle).
3. **Release imzası:** assetlinks debug SHA256 içeriyor; Play öncesi release SHA256 ekle.
4. Deferred endpoint host parity (iOS `pyl.sh` / Android `link.paylisher.com`).
