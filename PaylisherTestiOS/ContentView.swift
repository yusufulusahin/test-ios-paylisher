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
                PaylisherSDK.shared.register(["deviceID": UIDevice.staticID])
                print("[SDK] reset() + register()  deviceID: \(UIDevice.staticID)")
                isLoggedIn = false
                activeUserId = ""
            }
        } else {
            LoginView(userId: $userId) {
                var props: [String: Any] = ["deviceID": UIDevice.staticID, "platform": "ios"]
                if let token = UserDefaults.standard.string(forKey: "fcm_token") {
                    props["token"] = token
                }
                PaylisherSDK.shared.identify(userId, userProperties: props)
                // SDK skips $identify if already identified with same userId.
                // Force-update person properties so token/deviceID always reflect current device.
                PaylisherSDK.shared.capture("$set", userProperties: props)
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
