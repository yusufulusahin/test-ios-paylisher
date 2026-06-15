import SwiftUI
import Paylisher

// MARK: - Deeplink Log & Manuel Test (Profil → Geliştirici)
//
// Asıl test artık gerçek ekranlarla yapılır; bu ekran yalnızca debug içindir:
// handler'a düşen her olayı listeler ve Studio'ya gitmeden hızlı URL denemesi sağlar.

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
            ("Cüzdan (auth-gate)", "\(scheme)://wallet"),
            ("Profil", "\(scheme)://profile"),
            ("Kampanya key", "\(scheme)://products?keyName=\(campaignKey)"),
        ]
    }
    private var universalURLs: [(String, String)] {
        [
            ("Ürün A detay", "https://\(domain)/products/a"),
            ("Ürün A içerik", "https://\(domain)/products/a/content"),
        ]
    }

    var body: some View {
        List {
            Section("Kampanya Key (resolve testi)") {
                TextField("keyName", text: $campaignKey)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                if campaignKey == DeepLinkTestConfig.defaultCampaignKey {
                    Text("⚠️ Canlı keyName gir.").font(.caption2).foregroundColor(.orange)
                }
            }

            Section {
                ForEach(customURLs, id: \.1) { item in
                    urlRow(item.0, item.1, "Aç") { open(item.1) }
                }
            } header: { Text("Custom Scheme — gerçek ekranlara yönlenir") }

            Section {
                ForEach(universalURLs, id: \.1) { item in
                    urlRow(item.0, item.1, "Simüle Et") { simulateUniversal(item.1) }
                }
            } header: { Text("Universal Link") } footer: {
                Text("Gerçek Safari→app açılışı AASA \(domain)/.well-known/'a yayınlanınca çalışır.")
            }

            Section {
                LabeledContent("Durum", value: router.deferredStatus)
                Button { router.runDeferredCheck(reset: true) } label: {
                    Label("Reset + Tekrar Kontrol", systemImage: "arrow.clockwise")
                }
            } header: { Text("Deferred Deeplink") }

            Section {
                if router.events.isEmpty {
                    Text("Henüz olay yok.").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(router.events) { eventRow($0) }
                }
            } header: {
                HStack {
                    Text("Olay Günlüğü (\(router.events.count))")
                    Spacer()
                    Button("Temizle") { router.clear() }.font(.caption)
                }
            }
        }
        .navigationTitle("Deeplink Log")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func urlRow(_ label: String, _ url: String, _ action: String, _ run: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).bold()
            Text(url).font(.system(.caption2, design: .monospaced)).foregroundColor(.secondary).lineLimit(2)
            HStack {
                Button(action, action: run).buttonStyle(.borderedProminent).controlSize(.small)
                Button { UIPasteboard.general.string = url } label: { Image(systemName: "doc.on.doc") }.controlSize(.small)
            }
        }.padding(.vertical, 2)
    }

    private func eventRow(_ e: DeepLinkEvent) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(e.kind.rawValue).font(.caption).bold()
                Spacer()
                Text(DateFormatter.localizedString(from: e.time, dateStyle: .none, timeStyle: .medium))
                    .font(.caption2).foregroundColor(.secondary)
            }
            if e.url != "-" { Text(e.url).font(.system(.caption2, design: .monospaced)).lineLimit(2) }
            if e.destination != "-" {
                Text("dest=\(e.destination)  scheme=\(e.scheme)").font(.caption2).foregroundColor(.secondary)
            }
            if e.campaignKey != nil || e.jid != nil || e.campaignTitle != nil {
                Text("key=\(e.campaignKey ?? "-")  jid=\(e.jid ?? "-")  title=\(e.campaignTitle ?? "-")")
                    .font(.caption2).foregroundColor(.blue)
            }
            if let note = e.note { Text("· \(note)").font(.caption2).foregroundColor(.orange) }
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
