import SwiftUI
import Paylisher

// MARK: - Tab bar (giriş sonrası ana ekran)

struct MainTabView: View {
    let userId: String
    let onLogout: () -> Void
    @EnvironmentObject var router: DeepLinkRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeTabView()
                .tabItem { Label("Ana Sayfa", systemImage: "house.fill") }
                .tag(AppTab.home)

            ProductsTabView()
                .tabItem { Label("Ürünler", systemImage: "bag.fill") }
                .tag(AppTab.products)

            WalletTabView()
                .tabItem { Label("Cüzdan", systemImage: "creditcard.fill") }
                .tag(AppTab.wallet)

            ProfileTabView(userId: userId, onLogout: onLogout)
                .tabItem { Label("Profil", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
    }
}

// MARK: - Ana Sayfa (mevcut event + multi-SDK push testleri burada korunur)

struct HomeTabView: View {
    @EnvironmentObject var l10n: LocalizationManager
    @State private var logs: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Paylisher deeplink test uygulaması. Linkler gerçek ekranlara yönlenir; aşağıdan SDK event/push testlerini de tetikleyebilirsin.")
                        .font(.callout).foregroundColor(.secondary)
                }

                Section(l10n.t("home_events_section")) {
                    eventRow(l10n.t("event_screen_view"), event: "screen_view", props: ["screen": "home"])
                    eventRow(l10n.t("event_product_click"), event: "product_click", props: ["product_id": "abc123"])
                    eventRow(l10n.t("event_add_to_cart"), event: "add_to_cart", props: ["product_id": "abc123", "price": "99.9"])
                    eventRow(l10n.t("event_checkout_start"), event: "checkout_start", props: ["amount": "99.9"])
                }

                Section(l10n.t("home_multisdk_section")) {
                    Text(l10n.t("home_multisdk_desc")).font(.caption2).foregroundColor(.secondary)
                    Button {
                        BankNotificationManager.shared.simulateBankPush(title: l10n.t("bank_transfer_title"), body: l10n.t("bank_transfer_body"), txId: "TRX-\(Int(Date().timeIntervalSince1970))")
                        addLog("BANK push: para transferi")
                    } label: { Label(l10n.t("bank_transfer_button"), systemImage: "banknote.fill") }
                    Button {
                        BankNotificationManager.shared.simulateBankPush(title: l10n.t("bank_3ds_title"), body: l10n.t("bank_3ds_body"), txId: "AUTH-\(Int(Date().timeIntervalSince1970))")
                        addLog("BANK push: 3D Secure")
                    } label: { Label(l10n.t("bank_3ds_button"), systemImage: "lock.shield.fill") }
                    Button {
                        XSdkSimulator.shared.simulateXSdkPush(title: l10n.t("xsdk_campaign_title"), body: l10n.t("xsdk_campaign_body"), campaignId: "camp-\(Int(Date().timeIntervalSince1970))")
                        addLog("XSDK push: kampanya")
                    } label: { Label(l10n.t("xsdk_campaign_button"), systemImage: "megaphone.fill") }
                }

                if !logs.isEmpty {
                    Section(l10n.t("home_sent_events_section")) {
                        ForEach(logs, id: \.self) { Text($0).font(.caption2).foregroundColor(.secondary) }
                    }
                }
            }
            .navigationTitle(l10n.t("home_title"))
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { LanguageMenu(l10n: l10n) } }
        }
    }

    private func addLog(_ s: String) {
        logs.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(s)")
    }

    private func eventRow(_ title: String, event: String, props: [String: Any]) -> some View {
        Button {
            PaylisherSDK.shared.capture(event, properties: props)
            addLog(event)
        } label: { Label(title, systemImage: "bolt.fill") }
    }
}

// MARK: - Ürünler (iç içe: liste → detay → içerik)

struct ProductsTabView: View {
    @EnvironmentObject var router: DeepLinkRouter

    var body: some View {
        NavigationStack(path: $router.productsPath) {
            List(Product.all) { p in
                NavigationLink(value: ProductRoute.detail(p.id)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.name).font(.headline)
                        Text(p.summary).font(.caption).foregroundColor(.secondary)
                        Text(p.price).font(.caption2).foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("Ürünler")
            .navigationDestination(for: ProductRoute.self) { route in
                switch route {
                case .detail(let id): ProductDetailView(id: id)
                case .content(let id): ProductContentView(id: id)
                }
            }
        }
    }
}

struct ProductDetailView: View {
    let id: String
    private var product: Product { Product.find(id) }

    var body: some View {
        List {
            Section {
                Text(product.name).font(.largeTitle).bold()
                Text(product.summary).foregroundColor(.secondary)
                Text(product.price).font(.title3).foregroundColor(.blue)
            }
            Section("Açıklama") {
                Text("Bu \(product.name) için örnek detay ekranıdır. Deeplink: paylishertest://products/\(id)")
                    .font(.callout)
            }
            Section {
                NavigationLink(value: ProductRoute.content(id)) {
                    Label("İçeriği Gör (en iç ekran)", systemImage: "doc.text.fill")
                }
            }
        }
        .navigationTitle(product.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ProductContentView: View {
    let id: String
    private var product: Product { Product.find(id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(product.name) — İçerik").font(.title2).bold()
                Text("Bu, ürünler sekmesindeki 3. seviye (en iç) ekrandır.\n\nDeeplink: paylishertest://products/\(id)/content\n\nUygulama kapalıyken bu linke tıklanırsa, giriş sonrası doğrudan bu ekrana kadar yönlenir (Ürünler → \(product.name) → İçerik).")
                    .font(.body)
                Divider()
                ForEach(1...3, id: \.self) { i in
                    Text("İçerik bölümü \(i): \(product.name) hakkında örnek metin.").font(.callout).foregroundColor(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("İçerik")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Cüzdan (auth-gate'li hedef)
//
// Tab'a yalnızca app'e login'liyken ulaşılır → içerik DOĞRUDAN gösterilir (re-login yok).
// Auth-gate, login YOKKEN (kill sonrası cold-start'ta wallet deeplink'i) devreye girer: SDK
// deeplink'i bekletir, kullanıcı login olunca DeepLinkRouter.setAuthenticated(true) ile tamamlanır.

struct WalletTabView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Bakiye") {
                    Text("₺ 4.250,00").font(.largeTitle).bold()
                }
                Section("Son İşlemler") {
                    Label("Market — ₺120", systemImage: "cart")
                    Label("Maaş + ₺3.000", systemImage: "arrow.down.circle")
                    Label("Fatura — ₺340", systemImage: "doc.text")
                }
            }
            .navigationTitle("Cüzdan")
        }
    }
}

// MARK: - Profil (oturum + debug log + çıkış)

struct ProfileTabView: View {
    let userId: String
    let onLogout: () -> Void
    @EnvironmentObject var l10n: LocalizationManager
    @EnvironmentObject var router: DeepLinkRouter

    var body: some View {
        NavigationStack {
            List {
                Section(l10n.t("home_session_section")) {
                    LabeledContent("userId", value: userId)
                    LabeledContent("deviceID", value: UIDevice.staticID).font(.caption)
                }
                Section("Geliştirici") {
                    NavigationLink {
                        DeepLinkTestView()
                    } label: { Label("🔗 Deeplink Log & Manuel Test", systemImage: "ladybug") }
                    LabeledContent("Deferred", value: router.deferredStatus).font(.caption)
                }
                Section {
                    Button(role: .destructive, action: onLogout) {
                        Label(l10n.t("logout_button"), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profil")
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { LanguageMenu(l10n: l10n) } }
        }
    }
}
