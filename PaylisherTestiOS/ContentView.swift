import SwiftUI
import Paylisher

struct ContentView: View {
    @State private var userId = ""
    @State private var isLoggedIn = false
    @State private var activeUserId = ""

    var body: some View {
        if isLoggedIn {
            // Giriş sonrası: tab bar. Login sırasında gelen (cold-start) deeplink,
            // DeepLinkRouter durumuna yazıldığı için tab bar açılır açılmaz uygulanır.
            MainTabView(userId: activeUserId) {
                PaylisherSDK.shared.reset()
                // reset() super property'leri siliyor — deviceID ve token'ı yeniden kaydet
                var resetProps: [String: Any] = ["deviceID": UIDevice.staticID]
                if let token = UserDefaults.standard.string(forKey: "fcm_token") {
                    resetProps["token"] = token
                    resetProps["platform"] = "ios"
                }
                PaylisherSDK.shared.register(resetProps)
                print("[SDK] reset() + register()  props: \(resetProps)")
                DeepLinkRouter.shared.setAuthenticated(false)
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
                print("[SDK] identify(\(userId))  props: \(props)")
                activeUserId = userId
                isLoggedIn = true
                // Auth-gate: login olundu → bekleyen (cold-start) wallet deeplink'i tamamlanır.
                DeepLinkRouter.shared.setAuthenticated(true)
            }
        }
    }
}

// MARK: - Login

struct LoginView: View {
    @Binding var userId: String
    let onLogin: () -> Void
    @EnvironmentObject var l10n: LocalizationManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.blue)

                Text(l10n.t("login_title")).font(.title).bold()

                VStack(alignment: .leading, spacing: 6) {
                    Text(l10n.t("login_userid_label")).font(.caption).foregroundColor(.secondary)
                    TextField(l10n.t("login_userid_placeholder"), text: $userId)
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
                    Label(l10n.t("login_button"), systemImage: "arrow.right.circle.fill")
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
            .navigationTitle(l10n.t("login_nav_title"))
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    LanguageMenu(l10n: l10n)
                }
            }
        }
    }
}
