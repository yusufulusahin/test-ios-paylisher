import Foundation
import SwiftUI
import Paylisher

// MARK: - Test uygulaması sabitleri
enum DeepLinkTestConfig {
    static let scheme = "paylishertest"
    static let universalDomain = "link.paylisher.com"
    /// TODO: Canlı kampanya keyName'i ile değiştir (debug log ekranındaki alandan da girilir).
    static let defaultCampaignKey = "REPLACE_WITH_LIVE_KEY"
}

// MARK: - Navigasyon modeli

enum AppTab: Int, Hashable, CaseIterable {
    case home, products, campaigns, wallet, profile
}

/// Ürünler sekmesinin iç içe yolları: liste → detay → içerik.
enum ProductRoute: Hashable {
    case detail(String)   // ürün id (a/b/c)
    case content(String)  // ürün içeriği (en iç ekran)
}

/// Kampanya sekmesinin iç içe yolları: liste → detay → başvuru (en iç, auth-gate'li).
enum CampaignRoute: Hashable {
    case detail(String)   // kampanya slug (ceyiz/konut/altin/cocuk)
    case apply(String)    // başvuru ekranı
}

struct NavTarget {
    let tab: AppTab
    var productsPath: [ProductRoute] = []
    var campaignsPath: [CampaignRoute] = []
}

/// Studio/keyName üzerinden SDK'nın çözdüğü kampanya verisi (firma tarafı).
struct ResolvedCampaignInfo {
    let title: String?
    let keyName: String?
    let targetUrl: String?   // iosUrl ?? scheme (firmanın bağladığı hedef)
    let webUrl: String?
    let adId: String?
}

// MARK: - Debug olay modeli
struct DeepLinkEvent: Identifiable {
    let id = UUID()
    let time: Date
    let kind: Kind
    let url: String
    let destination: String
    let scheme: String
    let jid: String?
    let campaignKey: String?
    let campaignTitle: String?
    let note: String?
    enum Kind: String { case received = "✅ received", auth = "🔐 auth", failed = "❌ failed", deferred = "🎯 deferred", info = "ℹ️ info" }
}

// MARK: - DeepLinkRouter
//
// Hem SDK'nın `PaylisherDeepLinkHandler`'ı, hem de uygulamanın MERKEZİ navigasyon
// durumu. Gelen deeplink URL'ini kendimiz parse edip (host + path) ilgili sekme ve
// iç içe ürün yoluna çeviriyoruz. Login ekranındayken gelen deeplink de bu duruma
// yazılır; tab bar açıldığında otomatik uygulanır (cold-start çözümü).

final class DeepLinkRouter: NSObject, ObservableObject {
    static let shared = DeepLinkRouter()

    // Navigasyon durumu (UI bunu dinler)
    @Published var selectedTab: AppTab = .home
    @Published var productsPath: [ProductRoute] = []
    @Published var campaignsPath: [CampaignRoute] = []
    @Published var resolvedCampaign: ResolvedCampaignInfo?   // keyName'den çözülen son kampanya
    @Published var isAuthenticated: Bool = false   // app login durumu — wallet auth-gate buna bakar

    // Debug
    @Published private(set) var events: [DeepLinkEvent] = []
    @Published private(set) var deferredStatus: String = "henüz kontrol edilmedi"

    // Auth-gate: login yoksa SDK completion'ı burada bekler; login olunca tamamlanır (cold-start).
    private var pendingAuthCompletion: ((Bool) -> Void)?

    private override init() { super.init() }

    // MARK: Deeplink handling (SDK closure'ları buraya yönlendirir — protokol implement edilmez)

    func handleReceived(_ deepLink: PaylisherDeepLink, requiresAuth: Bool) {
        captureResolved(deepLink)
        logEvent(deepLink, kind: requiresAuth ? .auth : .received, requiresAuth: requiresAuth)
        // requiresAuth=true ise henüz yönlenme — auth tamamlanınca SDK bu metodu
        // requiresAuth=false ile tekrar çağırır.
        if !requiresAuth { navigate(deepLink) }
    }

    /// keyName'den çözülmüş kampanya varsa (campaignData) UI'ya köprüle.
    private func captureResolved(_ dl: PaylisherDeepLink) {
        guard let cd = dl.campaignData else { return }
        DispatchQueue.main.async {
            self.resolvedCampaign = ResolvedCampaignInfo(
                title: cd.title, keyName: cd.keyName ?? dl.campaignKeyName,
                targetUrl: cd.iosUrl ?? cd.scheme, webUrl: cd.webUrl, adId: cd.adId?.oid
            )
        }
    }

    func handleAuthRequired(_ deepLink: PaylisherDeepLink, completion: @escaping (Bool) -> Void) {
        DispatchQueue.main.async {
            if self.isAuthenticated {
                completion(true)                       // app'e login'li → direkt geç (re-login yok)
            } else {
                self.pendingAuthCompletion = completion  // login yok (cold-start) → login'i bekle
            }
        }
    }

    func handleFailure(_ url: URL, error: Error?) {
        addEvent(DeepLinkEvent(time: Date(), kind: .failed, url: url.absoluteString,
                               destination: "-", scheme: url.scheme ?? "-", jid: nil,
                               campaignKey: nil, campaignTitle: nil, note: error?.localizedDescription))
    }

    // MARK: Navigasyon

    /// SDK'nın normalize edilmiş `pathSegments`'ini sekme + iç içe yola çevirir — URL re-parse YOK.
    func navigate(_ deepLink: PaylisherDeepLink) {
        guard let target = Self.parseTarget(deepLink) else { return }
        DispatchQueue.main.async {
            self.selectedTab = target.tab
            // Tam yolu DOĞRUDAN set et. İç içe 2. seviyeyi (içerik/başvuru) detay ekranı kendi
            // `onAppear`'ında — detay oturduktan SONRA, gecikmeli — push eder; böylece cold-start
            // dahil (yol UI'dan önce set edilse bile) eşzamanlı çift-push olmaz.
            if target.tab == .products { self.productsPath = target.productsPath }
            if target.tab == .campaigns { self.campaignsPath = target.campaignsPath }
        }
    }

    // Manuel stack: en üstteki ekranı at (geri butonu / sistem geri).
    func popProduct() { if !productsPath.isEmpty { productsPath.removeLast() } }
    func popCampaign() { if !campaignsPath.isEmpty { campaignsPath.removeLast() } }

    static func parseTarget(_ deepLink: PaylisherDeepLink) -> NavTarget? {
        // ["products","a","content"] — custom scheme + universal link, iOS + Android: hepsi aynı.
        let segs = deepLink.pathSegments
        switch segs.first?.lowercased() {
        case nil, "home": return NavTarget(tab: .home)
        case "products", "product":
            if let id = segs.dropFirst().first ?? deepLink.parameters["id"] {
                if segs.count >= 3, segs[2].lowercased() == "content" {
                    return NavTarget(tab: .products, productsPath: [.detail(id), .content(id)])
                }
                return NavTarget(tab: .products, productsPath: [.detail(id)])
            }
            return NavTarget(tab: .products, productsPath: [])
        case "campaigns", "campaign":
            if let slug = segs.dropFirst().first ?? deepLink.parameters["slug"] {
                if segs.count >= 3, segs[2].lowercased() == "apply" {
                    return NavTarget(tab: .campaigns, campaignsPath: [.detail(slug), .apply(slug)])
                }
                return NavTarget(tab: .campaigns, campaignsPath: [.detail(slug)])
            }
            return NavTarget(tab: .campaigns, campaignsPath: [])
        case "wallet": return NavTarget(tab: .wallet)
        case "profile": return NavTarget(tab: .profile)
        default: return NavTarget(tab: .home)
        }
    }

    // MARK: Auth (app login)

    /// App login/logout'ta çağrılır. Login olunca, login'i bekleyen (cold-start) auth-gate
    /// deeplink'i varsa onu tamamlar → SDK pending deeplink'i tamamlar → wallet'e yönlenir.
    func setAuthenticated(_ value: Bool) {
        isAuthenticated = value
        if value, let completion = pendingAuthCompletion {
            pendingAuthCompletion = nil
            completion(true)
            log("Login sonrası bekleyen auth-gate deeplink tamamlandı")
        }
    }

    // MARK: Deferred deeplink

    func runDeferredCheck(reset: Bool) {
        if reset { PaylisherSDK.shared.resetDeferredDeepLinkForTesting() }
        setDeferredStatus("kontrol ediliyor…")
        PaylisherSDK.shared.checkDeferredDeepLink(
            onSuccess: { [weak self] dl in
                self?.captureResolved(dl)
                self?.setDeferredStatus("🎯 match: \(dl.url.absoluteString)")
                self?.navigate(dl)
                self?.addEvent(DeepLinkEvent(time: Date(), kind: .deferred, url: dl.url.absoluteString,
                                             destination: dl.destination, scheme: dl.scheme, jid: dl.jid,
                                             campaignKey: dl.campaignKeyName, campaignTitle: dl.campaignData?.title,
                                             note: "deferred match"))
            },
            onNoMatch: { [weak self] in self?.setDeferredStatus("ℹ️ no-match (organik kurulum)") },
            onError: { [weak self] e in self?.setDeferredStatus("❌ error: \(e.localizedDescription)") }
        )
    }

    // MARK: Log yardımcıları

    func setDeferredStatus(_ s: String) { DispatchQueue.main.async { self.deferredStatus = s } }
    func clear() { DispatchQueue.main.async { self.events.removeAll() } }

    private func log(_ note: String) {
        addEvent(DeepLinkEvent(time: Date(), kind: .info, url: "-", destination: "-", scheme: "-",
                               jid: nil, campaignKey: nil, campaignTitle: nil, note: note))
    }

    private func logEvent(_ dl: PaylisherDeepLink, kind: DeepLinkEvent.Kind, requiresAuth: Bool) {
        addEvent(DeepLinkEvent(time: Date(), kind: kind, url: dl.url.absoluteString,
                               destination: dl.destination, scheme: dl.scheme, jid: dl.jid,
                               campaignKey: dl.campaignKeyName, campaignTitle: dl.campaignData?.title,
                               note: requiresAuth ? "auth gerekli" : nil))
    }

    private func addEvent(_ e: DeepLinkEvent) {
        DispatchQueue.main.async {
            self.events.insert(e, at: 0)
            if self.events.count > 100 { self.events.removeLast(self.events.count - 100) }
        }
    }
}

// MARK: - Ürün modeli (test verisi)
struct Product: Identifiable {
    let id: String
    let name: String
    let summary: String
    let price: String
    static let all: [Product] = [
        Product(id: "a", name: "Ürün A", summary: "Kablosuz kulaklık", price: "₺1.299"),
        Product(id: "b", name: "Ürün B", summary: "Akıllı saat", price: "₺2.499"),
        Product(id: "c", name: "Ürün C", summary: "Bluetooth hoparlör", price: "₺899"),
    ]
    static func find(_ id: String) -> Product {
        all.first { $0.id == id } ?? Product(id: id, name: "Ürün \(id.uppercased())",
                                             summary: "Deeplink ile gelen ürün", price: "—")
    }
}

// MARK: - Kampanya modeli (Vakıf Katılım "Çeyiz Hesabı" senaryosundan esinli)
//
// keyName: bir firmanın Paylisher Studio'da kampanyayı kurunca alacağı anahtar.
struct Campaign: Identifiable {
    let slug: String
    let emoji: String
    let title: String
    let tagline: String
    let summary: String
    let highlights: [String]
    let keyName: String
    var id: String { slug }

    static let all: [Campaign] = [
        Campaign(slug: "ceyiz", emoji: "💍", title: "Çeyiz Hesabı",
                 tagline: "Devlet katkılı evlilik birikimi",
                 summary: "Düzenli biriktir, evlenince devlet katkısını al. Katılım esaslı (faizsiz); birikimin kâr payı ile değerlenir.",
                 highlights: ["Devlet katkısı: birikimin %20'si (üst sınırlı)",
                              "Katılım hesabı — faizsiz, kâr payı esaslı",
                              "18–27 yaş, düzenli aylık ödeme planı",
                              "Min. birikim süresi sonunda evlilikte ödeme"],
                 keyName: "CEYIZ2026"),
        Campaign(slug: "konut", emoji: "🏠", title: "Konut Hesabı",
                 tagline: "Devlet destekli ev birikimi",
                 summary: "İlk evin için düzenli biriktir; devlet katkısıyla peşinatını büyüt.",
                 highlights: ["Devlet katkısı: %20 (üst sınırlı)",
                              "Katılım esaslı, faizsiz birikim",
                              "Konut alımında kullanım önceliği"],
                 keyName: "KONUT2026"),
        Campaign(slug: "altin", emoji: "🪙", title: "Altın Birikim Hesabı",
                 tagline: "Gram altın ile biriktir",
                 summary: "Birikimini gram altına çevir; dalgalanmaya karşı değer biriktir.",
                 highlights: ["Fiziki/sanal gram altın olarak birikim",
                              "Dilediğin an TL'ye dönüş",
                              "Aylık otomatik altın alım talimatı"],
                 keyName: "ALTIN2026"),
        Campaign(slug: "cocuk", emoji: "🧸", title: "Geleceğim Çocuk Hesabı",
                 tagline: "Çocuğun için erken başla",
                 summary: "Çocuğun 18 yaşına geldiğinde kullanabileceği uzun vadeli birikim.",
                 highlights: ["Uzun vadeli katılım hesabı",
                              "Düzenli küçük ödemelerle büyüyen birikim",
                              "18 yaşında hak sahibine devir"],
                 keyName: "COCUK2026"),
    ]

    static func find(_ slug: String) -> Campaign {
        all.first { $0.slug == slug } ?? Campaign(slug: slug, emoji: "🎁",
            title: "Kampanya \(slug.uppercased())", tagline: "Deeplink ile gelen kampanya",
            summary: "Bu kampanya bir deeplink ile açıldı.", highlights: ["Detaylar yakında"],
            keyName: slug.uppercased())
    }
}
