import SwiftUI
import Paylisher

// MARK: - Deeplink Log & Manuel Test (Profil → Geliştirici)
//
// Asıl test artık gerçek ekranlarla yapılır; bu ekran yalnızca debug içindir:
// handler'a düşen her olayı listeler ve Studio'ya gitmeden hızlı URL denemesi sağlar.
// iOS 13: Section("x"){} / Section{}header:{} / LabeledContent / Label / .borderedProminent yok.

struct DeepLinkTestView: View {
    @EnvironmentObject var router: DeepLinkRouter
    @State private var campaignKey: String = DeepLinkTestConfig.defaultCampaignKey

    private var scheme: String { DeepLinkTestConfig.scheme }
    private var domain: String { DeepLinkTestConfig.universalDomain }

    private var customURLs: [(String, String)] {
        [
            ("Ana Sayfa", "\(scheme)://home"),
            ("Ürünler", "\(scheme)://products"),
            ("Ürün A detay", "\(scheme)://products/a"),
            ("Ürün A içerik (en iç)", "\(scheme)://products/a/content"),
            ("Kampanyalar", "\(scheme)://campaigns"),
            ("Çeyiz Hesabı detay", "\(scheme)://campaigns/ceyiz"),
            ("Cüzdan (auth-gate)", "\(scheme)://wallet"),
            ("Profil", "\(scheme)://profile"),
        ]
    }
    // Bir firmanın Studio'da kurduğu kampanyaya bağlayacağı deeplink'ler — keyName SDK'da
    // campaignData'ya resolve olur, source/campaign_id attribution'a girer, auth=required gate açar.
    private var firmCampaignURLs: [(String, String)] {
        [
            ("Çeyiz — push (key + source)", "\(scheme)://campaigns/ceyiz?keyName=\(campaignKey)&campaign_id=CMP-001&source=push"),
            ("Çeyiz — başvuruya (auth-gate)", "\(scheme)://campaigns/ceyiz/apply?auth=required&source=email"),
            ("Sadece key (resolve → yönlen)", "\(scheme)://campaigns?keyName=\(campaignKey)&source=sms"),
        ]
    }
    private var universalURLs: [(String, String)] {
        [
            ("Ürün A detay", "https://\(domain)/products/a"),
            ("Çeyiz Hesabı", "https://\(domain)/campaigns/ceyiz"),
        ]
    }

    var body: some View {
        List {
            Section(header: Text("Kampanya Key (resolve testi)")) {
                TextField("keyName", text: $campaignKey)
                    .autocapitalization(.none).disableAutocorrection(true)
                    .font(.system(.body, design: .monospaced))
                if campaignKey == DeepLinkTestConfig.defaultCampaignKey {
                    Text("⚠️ Canlı keyName gir.").font(.caption).foregroundColor(.orange)
                }
            }

            Section(header: Text("Custom Scheme — gerçek ekranlara yönlenir")) {
                ForEach(customURLs, id: \.1) { item in
                    urlRow(item.0, item.1, "Aç") { open(item.1) }
                }
            }

            Section(header: Text("🏢 Firma kampanya deeplink'i"),
                    footer: Text("Bir firmanın Studio'da kurduğu kampanyaya bağlayacağı link (keyName + source + auth).")) {
                ForEach(firmCampaignURLs, id: \.1) { item in
                    urlRow(item.0, item.1, "Aç") { open(item.1) }
                }
            }

            Section(header: Text("Universal Link"),
                    footer: Text("Gerçek Safari→app açılışı AASA \(domain)/.well-known/'a yayınlanınca çalışır.")) {
                ForEach(universalURLs, id: \.1) { item in
                    urlRow(item.0, item.1, "Simüle Et") { simulateUniversal(item.1) }
                }
            }

            Section(header: Text("Deferred Deeplink")) {
                HStack { Text("Durum"); Spacer(); Text(router.deferredStatus).foregroundColor(.secondary) }
                Button { router.runDeferredCheck(reset: true) } label: {
                    IconLabel("Reset + Tekrar Kontrol", systemImage: "arrow.clockwise")
                }
            }

            Section(header:
                HStack {
                    Text("Olay Günlüğü (\(router.events.count))")
                    Spacer()
                    Button("Temizle") { router.clear() }.font(.caption)
                }
            ) {
                if router.events.isEmpty {
                    Text("Henüz olay yok.").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(router.events) { eventRow($0) }
                }
            }
        }
        .navigationBarTitle(Text("Deeplink Log"), displayMode: .inline)
    }

    private func urlRow(_ label: String, _ url: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).bold()
            Text(url).font(.system(.caption, design: .monospaced)).foregroundColor(.secondary).lineLimit(2)
            HStack {
                Button(action: run) {
                    Text(action).font(.caption).fontWeight(.semibold)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Color.blue).foregroundColor(.white).cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
                Button { UIPasteboard.general.string = url } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(PlainButtonStyle())
            }
        }.padding(.vertical, 2)
    }

    private func eventRow(_ e: DeepLinkEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(e.kind.rawValue).font(.caption).bold()
                Spacer()
                Text(DateFormatter.localizedString(from: e.time, dateStyle: .none, timeStyle: .medium))
                    .font(.caption).foregroundColor(.secondary)
            }
            if e.url != "-" { Text(e.url).font(.system(.caption, design: .monospaced)).lineLimit(2) }
            if e.destination != "-" {
                Text("dest=\(e.destination)  scheme=\(e.scheme)").font(.caption).foregroundColor(.secondary)
            }
            if e.campaignKey != nil || e.jid != nil || e.campaignTitle != nil {
                Text("key=\(e.campaignKey ?? "-")  jid=\(e.jid ?? "-")  title=\(e.campaignTitle ?? "-")")
                    .font(.caption).foregroundColor(.blue)
            }
            if let note = e.note { Text("· \(note)").font(.caption).foregroundColor(.orange) }
        }.padding(.vertical, 2)
    }

    private func open(_ s: String) {
        guard let url = URL(string: s) else { return }
        UIApplication.shared.open(url)
    }
    private func simulateUniversal(_ s: String) {
        guard let url = URL(string: s) else { return }
        let a = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)
        a.webpageURL = url
        _ = PaylisherSDK.shared.handleUserActivity(a)
    }
}
