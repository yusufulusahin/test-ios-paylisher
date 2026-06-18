import SwiftUI

// MARK: - Desteklenen diller

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    /// Menüde gösterilecek isim. Diller kendi adlarıyla (endonym) gösterilir;
    /// "Sistem" seçeneği aktif dile göre çevrilir.
    func displayName(_ l10n: LocalizationManager) -> String {
        switch self {
        case .system:  return l10n.t("language_system")
        case .turkish: return "Türkçe"
        case .english: return "English"
        }
    }
}

// MARK: - Localization manager
//
// Uygulama dilini yöneten merkez. Seçim UserDefaults'ta saklanır; `.system`
// seçildiğinde cihaz diline göre (desteklenmiyorsa İngilizce) çözümlenir.
// SwiftUI view'ları bu objeyi `@EnvironmentObject` ile dinler; dil değiştiğinde
// (uygulamayı yeniden başlatmadan) anında güncellenir.

final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    private let storageKey = "app_language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: storageKey) }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: storageKey)
        language = saved.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Aktif olarak kullanılacak dil kodu ("tr" / "en").
    var resolvedCode: String {
        switch language {
        case .turkish: return "tr"
        case .english: return "en"
        case .system:
            let deviceCode = String((Locale.preferredLanguages.first ?? "en").prefix(2))
            return Strings.table[deviceCode] != nil ? deviceCode : "en"
        }
    }

    /// Tarih / sayı biçimlendirmesi için locale.
    var locale: Locale { Locale(identifier: resolvedCode) }

    /// Anahtarı aktif dile çevirir. Bilinmeyen anahtarda İngilizce'ye, o da yoksa
    /// anahtarın kendisine düşer.
    func t(_ key: String) -> String {
        let code = resolvedCode
        return Strings.table[code]?[key] ?? Strings.table["en"]?[key] ?? key
    }
}

// MARK: - iOS 13 uyumlu Label (SwiftUI `Label` iOS 14+; iOS 13 için HStack)

struct IconLabel: View {
    let title: String
    let systemImage: String
    init(_ title: String, systemImage: String) { self.title = title; self.systemImage = systemImage }
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
            Text(title)
        }
    }
}

// MARK: - Dil seçici (🌐) — iOS 13: `Menu` yok, ActionSheet kullanılır

struct LanguageMenu: View {
    @ObservedObject var l10n: LocalizationManager
    @State private var showSheet = false

    var body: some View {
        Button { showSheet = true } label: {
            Image(systemName: "globe")
        }
        .accessibility(label: Text(l10n.t("language_menu")))
        .actionSheet(isPresented: $showSheet) {
            ActionSheet(
                title: Text(l10n.t("language_menu")),
                buttons: AppLanguage.allCases.map { lang in
                    .default(Text(lang.displayName(l10n) + (l10n.language == lang ? "  ✓" : ""))) {
                        l10n.language = lang
                    }
                } + [.cancel()]
            )
        }
    }
}

// MARK: - Çeviri tablosu
//
// iOS tarafında çalışma zamanında (restart olmadan) dil değiştirebilmek için
// çeviriler kod içinde tutulur. Apple'ın `Text("anahtar")` tablosu iOS 16'da
// runtime'da güvenilir biçimde dil değiştirmediğinden bu yaklaşım tercih edildi.

enum Strings {
    static let table: [String: [String: String]] = [
        "en": [
            // Login
            "login_title": "Paylisher Test",
            "login_nav_title": "Login",
            "login_userid_label": "Customer No (userId)",
            "login_userid_placeholder": "e.g. 12345",
            "login_button": "Sign In (identify)",

            // Home
            "home_title": "Home",
            "home_session_section": "Session",
            "home_events_section": "Send Event",
            "event_screen_view": "Screen Viewed",
            "event_product_click": "Product Clicked",
            "event_add_to_cart": "Added to Cart",
            "event_checkout_start": "Checkout Started",

            // Multi-SDK push simulation
            "home_multisdk_section": "Multi-SDK Push Simulation",
            "home_multisdk_desc": "These buttons bypass the Paylisher forward code and test each SDK's own notification path. They should produce the same result regardless of Phase 1/Phase 2.",
            "bank_transfer_button": "Bank: Money Transfer",
            "bank_transfer_title": "Money Transfer Received",
            "bank_transfer_body": "1,250.00 TL was transferred to your account. (Test)",
            "bank_3ds_button": "Bank: 3D Secure",
            "bank_3ds_title": "3D Secure Approval",
            "bank_3ds_body": "Enter the code sent to your phone. (Test)",
            "xsdk_campaign_button": "X SDK: Campaign",
            "xsdk_campaign_title": "Campaign",
            "xsdk_campaign_body": "20% off this weekend! (XSdk Test)",

            "home_sent_events_section": "Sent Events",
            "logout_button": "Sign Out (reset)",

            // Language picker
            "language_menu": "Language",
            "language_system": "System default",
        ],
        "tr": [
            // Login
            "login_title": "Paylisher Test",
            "login_nav_title": "Giriş",
            "login_userid_label": "Müşteri No (userId)",
            "login_userid_placeholder": "Örn: 12345",
            "login_button": "Giriş Yap (identify)",

            // Home
            "home_title": "Ana Sayfa",
            "home_session_section": "Oturum",
            "home_events_section": "Event Gönder",
            "event_screen_view": "Ekran Görüntülendi",
            "event_product_click": "Ürün Tıklandı",
            "event_add_to_cart": "Sepete Eklendi",
            "event_checkout_start": "Ödeme Başlatıldı",

            // Çoklu SDK push simülasyonu
            "home_multisdk_section": "Multi-SDK Push Simülasyonu",
            "home_multisdk_desc": "Bu butonlar Paylisher forward kodunu bypass edip her SDK'nın kendi notification yolunu test eder. Faz 1/Faz 2 fark etmeden aynı sonucu vermesi beklenir.",
            "bank_transfer_button": "Banka: Para Transferi",
            "bank_transfer_title": "Para Transferi Alındı",
            "bank_transfer_body": "Hesabınıza 1.250,00 TL EFT yapıldı. (Test)",
            "bank_3ds_button": "Banka: 3D Secure",
            "bank_3ds_title": "3D Secure Onay",
            "bank_3ds_body": "Cep telefonunuza gelen kodu giriniz. (Test)",
            "xsdk_campaign_button": "X SDK: Kampanya",
            "xsdk_campaign_title": "Kampanya",
            "xsdk_campaign_body": "Bu hafta sonu %20 indirim! (XSdk Test)",

            "home_sent_events_section": "Gönderilen Eventler",
            "logout_button": "Çıkış Yap (reset)",

            // Dil seçici
            "language_menu": "Dil",
            "language_system": "Sistem varsayılanı",
        ],
    ]
}
