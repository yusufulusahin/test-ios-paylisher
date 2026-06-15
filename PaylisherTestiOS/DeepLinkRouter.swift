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
    case home, products, wallet, profile
}

/// Ürünler sekmesinin iç içe yolları: liste → detay → içerik.
enum ProductRoute: Hashable {
    case detail(String)   // ürün id (a/b/c)
    case content(String)  // ürün içeriği (en iç ekran)
}

struct NavTarget {
    let tab: AppTab
    var productsPath: [ProductRoute] = []
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
    @Published var isAuthenticated: Bool = false   // app login durumu — wallet auth-gate buna bakar

    // Debug
    @Published private(set) var events: [DeepLinkEvent] = []
    @Published private(set) var deferredStatus: String = "henüz kontrol edilmedi"

    // Auth-gate: login yoksa SDK completion'ı burada bekler; login olunca tamamlanır (cold-start).
    private var pendingAuthCompletion: ((Bool) -> Void)?

    private override init() { super.init() }

    // MARK: Deeplink handling (SDK closure'ları buraya yönlendirir — protokol implement edilmez)

    func handleReceived(_ deepLink: PaylisherDeepLink, requiresAuth: Bool) {
        logEvent(deepLink, kind: requiresAuth ? .auth : .received, requiresAuth: requiresAuth)
        // requiresAuth=true ise henüz yönlenme — auth tamamlanınca SDK bu metodu
        // requiresAuth=false ile tekrar çağırır.
        if !requiresAuth { navigate(to: deepLink.url) }
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

    /// Deeplink URL'ini sekme + iç içe yola çevirip uygular.
    func navigate(to url: URL) {
        guard let target = Self.parseTarget(url) else { return }
        DispatchQueue.main.async {
            self.selectedTab = target.tab
            if target.tab == .products { self.productsPath = target.productsPath }
        }
    }

    static func parseTarget(_ url: URL) -> NavTarget? {
        let host = (url.host ?? "").lowercased()
        let segs = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        switch host {
        case "home", "": return NavTarget(tab: .home)
        case "products", "product":
            if let id = segs.first ?? queryValue(url, "id") {
                if segs.count >= 2, segs[1].lowercased() == "content" {
                    return NavTarget(tab: .products, productsPath: [.detail(id), .content(id)])
                }
                return NavTarget(tab: .products, productsPath: [.detail(id)])
            }
            return NavTarget(tab: .products, productsPath: [])
        case "wallet": return NavTarget(tab: .wallet)
        case "profile": return NavTarget(tab: .profile)
        default: return NavTarget(tab: .home)
        }
    }

    private static func queryValue(_ url: URL, _ key: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == key })?.value
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
                self?.setDeferredStatus("🎯 match: \(dl.url.absoluteString)")
                self?.navigate(to: dl.url)
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
