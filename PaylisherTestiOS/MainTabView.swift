import SwiftUI
import Paylisher

// MARK: - Tab bar (giriş sonrası ana ekran)
//
// iOS 13 hedefi: `NavigationStack`/`.navigationTitle`/`.toolbar`/`Label`/`Section("x")`/`LabeledContent`
// yok. Sırasıyla `NavigationView`(+StackStyle) / `.navigationBarTitle` / `.navigationBarItems` /
// `IconLabel` / `Section(header:)` / `HStack` kullanılır. İç içe navigasyon, router'ın path
// dizisini süren gizli `NavigationLink(isActive:)` zinciriyle yapılır.

struct MainTabView: View {
    let userId: String
    let onLogout: () -> Void
    @EnvironmentObject var router: DeepLinkRouter

    var body: some View {
        TabView(selection: $router.selectedTab) {
            HomeTabView()
                .tabItem { IconLabel("Ana Sayfa", systemImage: "house.fill") }
                .tag(AppTab.home)

            ProductsTabView()
                .tabItem { IconLabel("Ürünler", systemImage: "bag.fill") }
                .tag(AppTab.products)

            CampaignsTabView(userId: userId)
                .tabItem { IconLabel("Kampanyalar", systemImage: "gift.fill") }
                .tag(AppTab.campaigns)

            WalletTabView()
                .tabItem { IconLabel("Cüzdan", systemImage: "creditcard.fill") }
                .tag(AppTab.wallet)

            ProfileTabView(userId: userId, onLogout: onLogout)
                .tabItem { IconLabel("Profil", systemImage: "person.fill") }
                .tag(AppTab.profile)
        }
    }
}

// MARK: - Ana Sayfa (mevcut event + multi-SDK push testleri burada korunur)

struct HomeTabView: View {
    @EnvironmentObject var l10n: LocalizationManager
    @State private var logs: [String] = []

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text("Paylisher deeplink test uygulaması. Linkler gerçek ekranlara yönlenir; aşağıdan SDK event/push testlerini de tetikleyebilirsin.")
                        .font(.callout).foregroundColor(.secondary)
                }

                Section(header: Text(l10n.t("home_events_section"))) {
                    eventRow(l10n.t("event_screen_view"), event: "screen_view", props: ["screen": "home"])
                    eventRow(l10n.t("event_product_click"), event: "product_click", props: ["product_id": "abc123"])
                    eventRow(l10n.t("event_add_to_cart"), event: "add_to_cart", props: ["product_id": "abc123", "price": "99.9"])
                    eventRow(l10n.t("event_checkout_start"), event: "checkout_start", props: ["amount": "99.9"])
                }

                Section(header: Text(l10n.t("home_multisdk_section"))) {
                    Text(l10n.t("home_multisdk_desc")).font(.caption).foregroundColor(.secondary)
                    Button {
                        BankNotificationManager.shared.simulateBankPush(title: l10n.t("bank_transfer_title"), body: l10n.t("bank_transfer_body"), txId: "TRX-\(Int(Date().timeIntervalSince1970))")
                        addLog("BANK push: para transferi")
                    } label: { IconLabel(l10n.t("bank_transfer_button"), systemImage: "banknote.fill") }
                    Button {
                        BankNotificationManager.shared.simulateBankPush(title: l10n.t("bank_3ds_title"), body: l10n.t("bank_3ds_body"), txId: "AUTH-\(Int(Date().timeIntervalSince1970))")
                        addLog("BANK push: 3D Secure")
                    } label: { IconLabel(l10n.t("bank_3ds_button"), systemImage: "lock.shield.fill") }
                    Button {
                        XSdkSimulator.shared.simulateXSdkPush(title: l10n.t("xsdk_campaign_title"), body: l10n.t("xsdk_campaign_body"), campaignId: "camp-\(Int(Date().timeIntervalSince1970))")
                        addLog("XSDK push: kampanya")
                    } label: { IconLabel(l10n.t("xsdk_campaign_button"), systemImage: "megaphone.fill") }
                }

                if !logs.isEmpty {
                    Section(header: Text(l10n.t("home_sent_events_section"))) {
                        ForEach(logs, id: \.self) { Text($0).font(.caption).foregroundColor(.secondary) }
                    }
                }
            }
            .navigationBarTitle(l10n.t("home_title"))
            .navigationBarItems(trailing: LanguageMenu(l10n: l10n))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func addLog(_ s: String) {
        logs.append("[\(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium))] \(s)")
    }

    private func eventRow(_ title: String, event: String, props: [String: Any]) -> some View {
        Button {
            PaylisherSDK.shared.capture(event, properties: props)
            addLog(event)
        } label: { IconLabel(title, systemImage: "bolt.fill") }
    }
}

// MARK: - Ürünler (iç içe: liste → detay → içerik) — MANUEL STACK (Android paritesi)
//
// iOS 13 NavigationView'in programatik çok-seviye push'u kırılgan (içerik/apply açılıp geri pop
// ediyordu). Android'deki gibi DETERMİNİSTİK manuel stack: router.productsPath'in EN ÜSTTEKİ
// öğesine göre ekranı RENDER ediyoruz (push yok → pop yok). Geri = path'ten son öğeyi at.

struct ProductsTabView: View {
    @ObservedObject private var router = DeepLinkRouter.shared

    var body: some View {
        NavigationView {
            content
                .navigationBarTitle(Text(title), displayMode: .inline)
                .navigationBarItems(leading: backButton)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var title: String {
        guard let top = router.productsPath.last else { return "Ürünler" }
        switch top {
        case .detail(let id): return Product.find(id).name
        case .content: return "İçerik"
        }
    }

    @ViewBuilder private var backButton: some View {
        if !router.productsPath.isEmpty {
            Button { router.popProduct() } label: {
                HStack(spacing: 2) { Image(systemName: "chevron.left"); Text("Geri") }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let top = router.productsPath.last {
            switch top {
            case .detail(let id): ProductDetailContent(id: id)
            case .content(let id): ProductContentContent(id: id)
            }
        } else {
            List {
                ForEach(Product.all) { p in
                    Button { router.productsPath = [.detail(p.id)] } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name).font(.headline)
                                Text(p.summary).font(.caption).foregroundColor(.secondary)
                                Text(p.price).font(.caption).foregroundColor(.blue)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

struct ProductDetailContent: View {
    let id: String
    @ObservedObject private var router = DeepLinkRouter.shared
    private var product: Product { Product.find(id) }

    var body: some View {
        List {
            Section {
                Text(product.name).font(.largeTitle).bold()
                Text(product.summary).foregroundColor(.secondary)
                Text(product.price).font(.headline).foregroundColor(.blue)
            }
            Section(header: Text("Açıklama")) {
                Text("Bu \(product.name) için örnek detay ekranıdır. Deeplink: paylishertest://products/\(id)")
                    .font(.callout)
            }
            Section {
                Button { router.productsPath = [.detail(id), .content(id)] } label: {
                    IconLabel("İçeriği Gör (en iç ekran)", systemImage: "doc.text.fill")
                }
            }
        }
    }
}

struct ProductContentContent: View {
    let id: String
    private var product: Product { Product.find(id) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(product.name) — İçerik").font(.title).bold()
                Text("Bu, ürünler sekmesindeki 3. seviye (en iç) ekrandır.\n\nDeeplink: paylishertest://products/\(id)/content\n\nUygulama kapalıyken bu linke tıklanırsa, giriş sonrası doğrudan bu ekrana kadar yönlenir (Ürünler → \(product.name) → İçerik).")
                    .font(.body)
                Divider()
                ForEach(1...3, id: \.self) { i in
                    Text("İçerik bölümü \(i): \(product.name) hakkında örnek metin.").font(.callout).foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
}

// MARK: - Kampanyalar (iç içe: liste → detay → başvuru) — MANUEL STACK
//
// Bir firmanın deeplink ile bağlayacağı iniş hedefi. Çeyiz Hesabı senaryosu flagship.

struct CampaignsTabView: View {
    let userId: String
    @ObservedObject private var router = DeepLinkRouter.shared

    var body: some View {
        NavigationView {
            content
                .navigationBarTitle(Text(title), displayMode: .inline)
                .navigationBarItems(leading: backButton)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private var title: String {
        guard let top = router.campaignsPath.last else { return "Kampanyalar" }
        switch top {
        case .detail(let s): return Campaign.find(s).title
        case .apply: return "Başvuru"
        }
    }

    @ViewBuilder private var backButton: some View {
        if !router.campaignsPath.isEmpty {
            Button { router.popCampaign() } label: {
                HStack(spacing: 2) { Image(systemName: "chevron.left"); Text("Geri") }
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let top = router.campaignsPath.last {
            switch top {
            case .detail(let s): CampaignDetailContent(slug: s, userId: userId)
            case .apply(let s): CampaignApplyContent(slug: s, userId: userId)
            }
        } else {
            List {
                if let r = router.resolvedCampaign {
                    Section(header: Text("🎯 Studio'dan çözülen kampanya")) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title ?? "—").font(.headline)
                            if let k = r.keyName { Text("key=\(k)").font(.system(.caption, design: .monospaced)).foregroundColor(.secondary) }
                            if let t = r.targetUrl { Text("hedef=\(t)").font(.system(.caption, design: .monospaced)).foregroundColor(.secondary) }
                            if let a = r.adId { Text("adId=\(a)").font(.system(.caption, design: .monospaced)).foregroundColor(.secondary) }
                        }
                    }
                }
                Section {
                    Text("Bu sekme, bir firmanın kurduğu kampanyaya bağlayacağı deeplink iniş hedefidir. Örn. paylishertest://campaigns/ceyiz")
                        .font(.caption).foregroundColor(.secondary)
                }
                Section {
                    ForEach(Campaign.all) { c in
                        Button { router.campaignsPath = [.detail(c.slug)] } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(c.emoji)  \(c.title)").font(.headline)
                                    Text(c.tagline).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
        }
    }
}

struct CampaignDetailContent: View {
    let slug: String
    let userId: String
    @ObservedObject private var router = DeepLinkRouter.shared
    private var c: Campaign { Campaign.find(slug) }

    var body: some View {
        List {
            Section {
                Text("\(c.emoji)  \(c.title)").font(.largeTitle).bold()
                Text(c.tagline).font(.subheadline).foregroundColor(.secondary)
                Text(c.summary).font(.callout)
            }
            Section(header: Text("Öne çıkanlar")) {
                ForEach(c.highlights, id: \.self) { h in
                    IconLabel(h, systemImage: "checkmark.seal.fill")
                }
            }
            Section {
                Button { router.campaignsPath = [.detail(slug), .apply(slug)] } label: {
                    IconLabel("Hemen Başvur", systemImage: "square.and.pencil")
                }
            }
            Section(header: Text("Firma bu kampanyayı deeplink ile şöyle bağlar")) {
                Text("paylishertest://campaigns/\(slug)?keyName=\(c.keyName)&source=push")
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
                Text("Başvuru (auth-gate): paylishertest://campaigns/\(slug)/apply?auth=required")
                    .font(.system(.caption, design: .monospaced)).foregroundColor(.secondary)
            }
        }
        .onAppear {
            PaylisherSDK.shared.capture("campaign_view", properties: ["campaign": slug, "keyName": c.keyName])
        }
    }
}

struct CampaignApplyContent: View {
    let slug: String
    let userId: String
    @State private var submitted = false
    private var c: Campaign { Campaign.find(slug) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    IconLabel("Bu ekran auth-gate'li", systemImage: "lock.fill").foregroundColor(.orange).font(.subheadline)
                    Text("Kapalı uygulamaya gelen paylishertest://campaigns/\(slug)/apply?auth=required linki önce giriş ister, sonra doğrudan bu ekrana yönlenir.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if submitted {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        IconLabel("Başvurun alındı", systemImage: "checkmark.circle.fill").foregroundColor(.green)
                        Text("Müşteri No: \(userId) · Kampanya: \(c.title)").font(.caption).foregroundColor(.secondary)
                    }
                }
            } else {
                Section {
                    HStack { Text("Müşteri No"); Spacer(); Text(userId).foregroundColor(.secondary) }
                    Text("“\(c.title)” için başvurunu tamamla. Onayınca SDK'ya campaign_apply event'i gider.")
                        .font(.caption).foregroundColor(.secondary)
                    Button {
                        PaylisherSDK.shared.capture("campaign_apply", properties: ["campaign": slug, "keyName": c.keyName, "userId": userId])
                        submitted = true
                    } label: {
                        IconLabel("Başvuruyu Gönder", systemImage: "paperplane.fill")
                    }
                }
            }
        }
    }
}

// MARK: - Cüzdan (auth-gate'li hedef)
//
// Tab'a yalnızca app'e login'liyken ulaşılır → içerik DOĞRUDAN gösterilir (re-login yok).
// Auth-gate, login YOKKEN (kill sonrası cold-start'ta wallet deeplink'i) devreye girer: SDK
// deeplink'i bekletir, kullanıcı login olunca DeepLinkRouter.setAuthenticated(true) ile tamamlanır.

struct WalletTabView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Bakiye")) {
                    Text("₺ 4.250,00").font(.largeTitle).bold()
                }
                Section(header: Text("Son İşlemler")) {
                    IconLabel("Market — ₺120", systemImage: "cart")
                    IconLabel("Maaş + ₺3.000", systemImage: "arrow.down.circle")
                    IconLabel("Fatura — ₺340", systemImage: "doc.text")
                }
            }
            .navigationBarTitle("Cüzdan")
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Profil (oturum + debug log + çıkış)

struct ProfileTabView: View {
    let userId: String
    let onLogout: () -> Void
    @EnvironmentObject var l10n: LocalizationManager
    @EnvironmentObject var router: DeepLinkRouter

    var body: some View {
        NavigationView {
            List {
                Section(header: Text(l10n.t("home_session_section"))) {
                    HStack { Text("userId"); Spacer(); Text(userId).foregroundColor(.secondary) }
                    HStack { Text("deviceID"); Spacer(); Text(UIDevice.staticID).foregroundColor(.secondary) }.font(.caption)
                }
                Section(header: Text("Geliştirici")) {
                    NavigationLink(destination: DeepLinkTestView()) {
                        IconLabel("🔗 Deeplink Log & Manuel Test", systemImage: "ladybug")
                    }
                    HStack { Text("Deferred"); Spacer(); Text(router.deferredStatus).foregroundColor(.secondary) }.font(.caption)
                }
                Section {
                    Button(action: onLogout) {
                        IconLabel(l10n.t("logout_button"), systemImage: "rectangle.portrait.and.arrow.right")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationBarTitle("Profil")
            .navigationBarItems(trailing: LanguageMenu(l10n: l10n))
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
