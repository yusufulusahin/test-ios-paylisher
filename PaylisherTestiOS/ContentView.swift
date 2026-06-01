import SwiftUI
import Paylisher

struct ContentView: View {
    @State private var userId = ""
    @State private var isLoggedIn = false
    @State private var activeUserId = ""

    var body: some View {
        if isLoggedIn {
            HomeView(userId: activeUserId) {
                PaylisherSDK.shared.reset()
                // reset() super property'leri siliyor — deviceID ve token'ı yeniden kaydet
                var resetProps: [String: Any] = ["deviceID": UIDevice.staticID]
                if let token = UserDefaults.standard.string(forKey: "fcm_token") {
                    resetProps["token"] = token
                    resetProps["platform"] = "ios"
                }
                PaylisherSDK.shared.register(resetProps)
                print("[SDK] reset() + register()  props: \(resetProps)")
                isLoggedIn = false
                activeUserId = ""
            }
        } else {
            LoginView(userId: $userId) {
                // Android ile birebir aynı: deviceID + platform + token (varsa)
                var props: [String: Any] = [
                    "deviceID": UIDevice.staticID,
                    "platform": "ios"
                ]
                if let token = UserDefaults.standard.string(forKey: "fcm_token") {
                    props["token"] = token
                }
                PaylisherSDK.shared.identify(userId, userProperties: props)
                print("[SDK] identify(\(userId))  props: \(props)")
                activeUserId = userId
                isLoggedIn = true
            }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @Binding var userId: String
    let onLogin: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text("Paylisher Test")
                    .font(.title).bold()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Müşteri No (userId)").font(.caption).foregroundColor(.secondary)
                    TextField("Örn: 12345", text: $userId)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                }
                .padding(.horizontal, 32)

                Text("deviceID: \(UIDevice.staticID)")
                    .font(.caption2).foregroundColor(.gray)
                    .padding(.horizontal, 32)

                Button {
                    guard !userId.isEmpty else { return }
                    onLogin()
                } label: {
                    Label("Giriş Yap (identify)", systemImage: "arrow.right.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(userId.isEmpty ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(userId.isEmpty)
                .padding(.horizontal, 32)

                Spacer()
            }
            .navigationTitle("Login")
        }
    }
}

// MARK: - Home

struct HomeView: View {
    let userId: String
    let onLogout: () -> Void
    @State private var logs: [String] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Oturum") {
                    LabeledContent("userId", value: userId)
                    LabeledContent("deviceID", value: UIDevice.staticID)
                        .font(.caption)
                }

                Section("Event Gönder") {
                    eventRow("Ekran Görüntülendi", event: "screen_view", props: ["screen": "home"])
                    eventRow("Ürün Tıklandı", event: "product_click", props: ["product_id": "abc123"])
                    eventRow("Sepete Eklendi", event: "add_to_cart", props: ["product_id": "abc123", "price": "99.9"])
                    eventRow("Ödeme Başlatıldı", event: "checkout_start", props: ["amount": "99.9"])
                }

                // ─── Multi-SDK push simülasyonu ─────────────────────────────────
                // "source" field'ı OLMAYAN payload → banka kendi push'u
                // "source: XSdk" payload → başka bir SDK
                // Paylisher push'u zaten Swagger üzerinden FCM ile gelir.
                // Üç akış da AppDelegate'te farklı yollardan handle edilir;
                // Paylisher forward kodu banka/XSdk akışlarını bozmamalı.
                Section("Multi-SDK Push Simülasyonu") {
                    Text("Bu butonlar Paylisher forward kodunu bypass edip her SDK'nın kendi notification yolunu test eder. Faz 1/Faz 2 fark etmeden aynı sonucu vermesi beklenir.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Button {
                        let txId = "TRX-\(Int(Date().timeIntervalSince1970))"
                        BankNotificationManager.shared.simulateBankPush(
                            title: "Para Transferi Alındı",
                            body: "Hesabınıza 1.250,00 TL EFT yapıldı. (Test)",
                            txId: txId
                        )
                        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                        logs.append("[\(ts)] BANK push: para transferi")
                    } label: {
                        Label("Banka: Para Transferi", systemImage: "banknote.fill")
                    }

                    Button {
                        let txId = "AUTH-\(Int(Date().timeIntervalSince1970))"
                        BankNotificationManager.shared.simulateBankPush(
                            title: "3D Secure Onay",
                            body: "Cep telefonunuza gelen kodu giriniz. (Test)",
                            txId: txId
                        )
                        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                        logs.append("[\(ts)] BANK push: 3D Secure")
                    } label: {
                        Label("Banka: 3D Secure", systemImage: "lock.shield.fill")
                    }

                    Button {
                        let campaign = "camp-\(Int(Date().timeIntervalSince1970))"
                        XSdkSimulator.shared.simulateXSdkPush(
                            title: "Kampanya",
                            body: "Bu hafta sonu %20 indirim! (XSdk Test)",
                            campaignId: campaign
                        )
                        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
                        logs.append("[\(ts)] XSDK push: kampanya")
                    } label: {
                        Label("X SDK: Kampanya", systemImage: "megaphone.fill")
                    }
                }

                if !logs.isEmpty {
                    Section("Gönderilen Eventler") {
                        ForEach(logs, id: \.self) { log in
                            Text(log).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        onLogout()
                    } label: {
                        Label("Çıkış Yap (reset)", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Home")
        }
    }

    private func eventRow(_ title: String, event: String, props: [String: Any]) -> some View {
        Button {
            PaylisherSDK.shared.capture(event, properties: props)
            let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
            logs.append("[\(ts)] \(event)")
            print("[SDK] capture(\(event)) props: \(props)")
        } label: {
            Label(title, systemImage: "bolt.fill")
        }
    }
}
