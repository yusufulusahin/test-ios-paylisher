import SwiftUI
import Paylisher
import UserNotifications
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
struct PaylisherTestiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var l10n = LocalizationManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(l10n)
                .environmentObject(DeepLinkRouter.shared)
                .environment(\.locale, l10n.locale)
                // Tek satır: custom scheme (onOpenURL) + Universal Link (onContinueUserActivity)
                // ikisini de SDK'ya yönlendirir.
                .paylisherDeepLinks()
        }
    }
}

// MARK: - AppDelegate
//
// Multi-SDK host senaryosu — banka uygulamalarında tipik kurulum:
// Birden fazla push SDK kullanılır (Paylisher + X SDK + banka kendi push'u). iOS'ta
// `UNUserNotificationCenter.delegate` ve `Messaging.messaging().delegate` host
// tarafından tek bir noktada (AppDelegate) set edilir. Her gelen push'ta host,
// payload'a bakarak doğru SDK'ya forward eder.

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        setupPaylisher()
        setupBankSimulators()
        setupNotifications(application)
        return true
    }

    // MARK: - Paylisher Setup

    private func setupPaylisher() {
        let config = PaylisherConfig(
            apiKey: "phc_3wZe1GW8GRdeUGQK0LqaS25PEDUNS9EBSxe7FiQFqQW",
            host: "https://ds-tr.paylisher.com"
        )
        config.debug = true
        config.flushAt = 1
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = true
        config.repeatedIdentifyBehavior = .capture

        // Engage API Pull mode: in-app mesajları SDK ile Engage'den çek (mirrors
        // dietapp + Android test app). teamId/projectId/sourceId/sdkKey zorunlu değil —
        // Engage public sdkKey'den (SDK apiKey'i) reverse-resolve eder.
        // LOCAL: fetchEndpoint = "http://10.0.2.2:1924/v1/push/inapp/fetch"
        // LAN:   fetchEndpoint = "http://10.254.132.106:1924/v1/push/inapp/fetch"
        // Test projesi EU/test ortamında (app-eu.paylisher.com) → Engage endpoint'i de EU.
        let engageConfig = PaylisherEngageInAppConfig(
            fetchEndpoint: "https://api-eu.paylisher.com/engage/v1/push/inapp/fetch"
        )
        engageConfig.autoFetchOnForeground = true
        engageConfig.maxMessages = 5
        engageConfig.debugLogging = true
        config.engageInAppConfig = engageConfig

        // Deeplink config — setup ÖNCESİ set edilir; setup() manager'ı OTOMATİK init eder
        // (artık ayrı PaylisherDeepLinkManager.shared.initialize çağrısı YOK).
        let deepLinkConfig = PaylisherDeepLinkConfig()
        deepLinkConfig.customSchemes = ["paylishertest"]
        deepLinkConfig.universalLinkDomains = ["link.paylisher.com"]
        deepLinkConfig.authRequiredDestinations = ["wallet"]
        deepLinkConfig.debugLogging = true
        config.deepLinkConfig = deepLinkConfig

        // Deferred deeplink (ilk kurulum attribution) — setup ÖNCESİ config'e yazılmalı.
        // Host dietapp'te kanıtlanmış pyl.sh; test için 2 saatlik attribution penceresi.
        config.deferredDeepLinkConfig = PaylisherDeferredDeepLinkConfig()
            .withEnabled(true)
            .withAPIHost("https://link-eu.paylisher.com/v1/deferred-deeplink")
            .withAttributionWindow(2 * 60 * 60 * 1000)
            .withIDFA(true)
            .withDebugLogging(true)
            .withAutoHandle(true)

        PaylisherSDK.shared.setup(config)
        PaylisherSDK.shared.register(["deviceID": UIDevice.staticID])
        CoreDataManager.shared.configure(appGroupIdentifier: "group.com.paylisher.testios")
        print("[SDK] Setup ✓  deviceID: \(UIDevice.staticID)")

        // setup() deeplink manager'ı + attribution'ı OTOMATİK hallediyor. Handler için protokol
        // implement etmeye gerek yok — sadece closure ver:
        PaylisherSDK.shared.onDeepLink { deepLink, requiresAuth in
            DeepLinkRouter.shared.handleReceived(deepLink, requiresAuth: requiresAuth)
        }
        PaylisherSDK.shared.onDeepLinkRequiresAuth { deepLink, completion in
            DeepLinkRouter.shared.handleAuthRequired(deepLink, completion: completion)
        }
        PaylisherSDK.shared.onDeepLinkFailed { url, error in
            DeepLinkRouter.shared.handleFailure(url, error: error)
        }

        // İlk açılışta deferred deeplink kontrolü (ilk kurulumda match aranır).
        DeepLinkRouter.shared.runDeferredCheck(reset: false)

        Messaging.messaging().token { token, error in
            guard let token = token, error == nil else {
                print("[FCM] Startup token alınamadı: \(error?.localizedDescription ?? "unknown")")
                return
            }
            UserDefaults.standard.set(token, forKey: "fcm_token")
            PaylisherSDK.shared.register(["token": token, "platform": "ios"])
            print("[FCM] Startup token register edildi: \(token)")
        }
    }

    // MARK: - Bank / X SDK simulators (multi-SDK senaryosu için)

    private func setupBankSimulators() {
        BankNotificationManager.shared.registerCategories()
        XSdkSimulator.shared.bootstrap()
        print("[BankSim] BankNotificationManager + XSdkSimulator hazır")
    }

    // MARK: - Notifications Setup

    private func setupNotifications(_ application: UIApplication) {
        UNUserNotificationCenter.current().delegate = self
        Messaging.messaging().delegate = self

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            print("[FCM] Bildirim izni: \(granted)")
            guard granted else { return }
            DispatchQueue.main.async {
                application.registerForRemoteNotifications()
            }
        }
    }

    // MARK: - APNs Token → Firebase'e ilet

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("[FCM] APNs token Firebase'e iletildi")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[FCM] APNs kayıt hatası: \(error)")
    }

    // MARK: - FCM Token → ÇOKLU SDK FORWARD
    //
    // Multi-SDK senaryosunda host her SDK'ya yeni token'ı kendisi bildirir.

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        UserDefaults.standard.set(token, forKey: "fcm_token")

        // [1] Paylisher SDK
        PaylisherSDK.shared.register(["token": token, "platform": "ios"])
        PaylisherSDK.shared.capture("$set", userProperties: ["token": token, "platform": "ios"])

        // [2] X SDK simülasyonu
        XSdkSimulator.shared.setPushToken(token)

        // [3] Banka kendi backend'ine kayıt (sembolik)
        print("[BANK] backend.registerDeviceToken(\(token)) (sembolik)")

        print("[FCM] FCM token kaydedildi (multi-SDK forward yapıldı): \(token)")
    }

    // MARK: - Foreground Push — ÇOKLU SDK FORWARD
    //
    // iOS'ta delegate tek bir kişide olduğu için multi-SDK ayırması burada yapılır.
    // Her SDK'nın payload imzasına göre forward edilir.

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let source = userInfo["source"] as? String ?? ""
        let type = userInfo["type"] as? String ?? ""

        // [1] Paylisher mesajları
        if source == "Paylisher" {
            print("[BANK delegate] Paylisher mesajı → SDK'ya forward (type=\(type))")
            // Foreground'da iOS willPresent'e düşen Paylisher push'lar için
            // notificationReceived event'ini burada fire et. iOS Android'den
            // farklı olarak foreground arrival (willPresent) ve tap (didReceive)
            // ayrı delegate callback'lerine bölüyor; SDK didReceive yolunda
            // notificationOpen'ı zaten otomatik atıyor ama willPresent için
            // host explicit forward yapmalı — aksi halde foreground push'ta
            // notificationReceived metrik kaybediliyor.
            NotificationManager.shared.handleForegroundPresentation(notification)
            if type == "IN-APP" {
                let windowScene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                if let scene = windowScene {
                    let content = notification.request.content.mutableCopy() as! UNMutableNotificationContent
                    NotificationManager.shared.customNotification(
                        windowScene: scene,
                        userInfo: userInfo,
                        content,
                        notification.request
                    ) { _ in }
                    completionHandler([]) // Banner'ı bastır, modal göster
                    return
                }
            }
            completionHandler([.sound, .list, .banner, .badge])
            return
        }

        // [2] X SDK mesajları
        if source == "XSdk" {
            print("[BANK delegate] X SDK mesajı → X SDK'ya forward")
            XSdkSimulator.shared.handleForeground(notification: notification)
            completionHandler([.sound, .list, .banner, .badge])
            return
        }

        // [3] Banka kendi push'u (varsayılan akış)
        print("[BANK delegate] Banka kendi push'u (Paylisher/XSdk değil) — banka template ile gösteriliyor")
        completionHandler([.sound, .list, .banner, .badge])
    }

    // MARK: - Background / Inactive In-App

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let source = userInfo["source"] as? String ?? ""
        let type   = userInfo["type"]   as? String ?? ""

        if source == "Paylisher" && type == "IN-APP" {
            DispatchQueue.main.async {
                let windowScene = UIApplication.shared.connectedScenes
                    .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
                if let scene = windowScene {
                    let content = UNMutableNotificationContent()
                    content.userInfo = userInfo
                    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
                    NotificationManager.shared.customNotification(
                        windowScene: scene,
                        userInfo: userInfo,
                        content,
                        request
                    ) { _ in }
                }
            }
        } else if source == "XSdk" {
            XSdkSimulator.shared.handleBackground(userInfo: userInfo)
        }

        completionHandler(.newData)
    }

    // MARK: - Tap — ÇOKLU SDK FORWARD

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        let source = userInfo["source"] as? String ?? ""

        if source == "Paylisher" {
            _ = NotificationManager.shared.handleNotificationResponse(response)
        } else if source == "XSdk" {
            XSdkSimulator.shared.handleTap(response: response)
        } else {
            print("[BANK delegate] Banka push'una tıklandı")
        }

        // Action URL açma (her SDK için ortak)
        if let actionURLString = userInfo["action"] as? String,
           !actionURLString.isEmpty,
           let actionURL = URL(string: actionURLString) {
            print("[FCM] Action URL: \(actionURLString)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                UIApplication.shared.open(actionURL, options: [:]) { success in
                    print("[FCM] URL açma sonucu: \(success), url: \(actionURLString)")
                }
            }
        }

        completionHandler()
    }
}

// MARK: - BankNotificationManager (banka kendi push akışının simülasyonu)
//
// Gerçek bir bankada bu sınıfın yerine banka kendi notification builder'ı,
// encryption decrypt, deep link routing vb. bulunur. Burada amacımız sadece
// Paylisher forward kodumuzun banka push'unu BOZMADIĞINI kanıtlamak.

final class BankNotificationManager {
    static let shared = BankNotificationManager()
    private init() {}

    private let categoryId = "BANK_CATEGORY"

    func registerCategories() {
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != self.categoryId }
            updated.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
    }

    /// Local notification ile banka push'unu simüle eder. Test app'teki butondan
    /// çağrılır. Gerçek senaryoda FCM payload `source` field'ı OLMADAN gelir,
    /// AppDelegate'in `willPresent` delegate'i bunu "banka kendi push'u" olarak
    /// işler.
    func simulateBankPush(title: String, body: String, txId: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        // Banka payload'unda `source` YOK — sadece kendine özgü field'lar
        content.userInfo = [
            "tx_id": txId,
            "channel": "bank"
        ]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[BANK] simulateBankPush error: \(error)")
            } else {
                print("[BANK] simulateBankPush gönderildi | tx_id=\(txId)")
            }
        }
    }
}

// MARK: - XSdkSimulator (başka bir push-SDK'nın simülasyonu)
//
// Bu sınıf "Paylisher dışı bir SDK" gibi davranır. Banka multi-SDK senaryosunda
// AppDelegate buradan ayrı bir push-handling SDK çağırır. Amacımız Paylisher forward
// kodunun bu SDK'yı engellemediğini ve iki SDK'nın aynı seansta beraber
// çalışabildiğini canlı göstermek.

final class XSdkSimulator {
    static let shared = XSdkSimulator()
    private init() {}

    private let categoryId = "XSDK_CATEGORY"
    private var lastToken: String?

    func bootstrap() {
        let category = UNNotificationCategory(
            identifier: categoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().getNotificationCategories { existing in
            var updated = existing.filter { $0.identifier != self.categoryId }
            updated.insert(category)
            UNUserNotificationCenter.current().setNotificationCategories(updated)
        }
        print("[XSDK] bootstrap")
    }

    func setPushToken(_ token: String) {
        lastToken = token
        print("[XSDK] setPushToken(\(token)) — backend'e kaydedildi (sembolik)")
    }

    func simulateXSdkPush(title: String, body: String, campaignId: String) {
        let content = UNMutableNotificationContent()
        content.title = "[XSDK] \(title)"
        content.body = body
        content.sound = .default
        content.categoryIdentifier = categoryId
        content.userInfo = [
            "source": "XSdk",
            "campaign_id": campaignId,
            "channel": "x_sdk"
        ]
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("[XSDK] simulateXSdkPush error: \(error)")
            } else {
                print("[XSDK] simulateXSdkPush gönderildi | campaign=\(campaignId)")
            }
        }
    }

    func handleForeground(notification: UNNotification) {
        let campaign = notification.request.content.userInfo["campaign_id"] as? String ?? "?"
        print("[XSDK] handleForeground | campaign=\(campaign) (banner banka tarafından gösterilecek)")
    }

    func handleBackground(userInfo: [AnyHashable: Any]) {
        let campaign = userInfo["campaign_id"] as? String ?? "?"
        print("[XSDK] handleBackground | campaign=\(campaign)")
    }

    func handleTap(response: UNNotificationResponse) {
        let campaign = response.notification.request.content.userInfo["campaign_id"] as? String ?? "?"
        print("[XSDK] handleTap | campaign=\(campaign) → kendi analytics event'i atılır")
    }
}
