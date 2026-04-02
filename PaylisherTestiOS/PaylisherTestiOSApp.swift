import SwiftUI
import Paylisher
import UserNotifications
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
struct PaylisherTestiOSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - AppDelegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FirebaseApp.configure()
        setupPaylisher()
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

        PaylisherSDK.shared.setup(config)
        PaylisherSDK.shared.register(["deviceID": UIDevice.staticID])
        print("[SDK] Setup ✓  deviceID: \(UIDevice.staticID)")
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

    // MARK: - APNs Token → Firebase'e ilet (FCM token'a çevirir)

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
        print("[FCM] APNs token Firebase'e iletildi")
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[FCM] APNs kayıt hatası: \(error)")
    }

    // MARK: - FCM Token → Paylisher'a kaydet

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken, !token.isEmpty else { return }
        UserDefaults.standard.set(token, forKey: "fcm_token")
        PaylisherSDK.shared.register(["token": token, "platform": "ios"])
        PaylisherSDK.shared.capture("$set", userProperties: ["token": token, "platform": "ios"])
        print("[FCM] FCM token kaydedildi: \(token)")
    }

    // MARK: - Foreground Bildirim (Push + In-App)

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let userInfo = notification.request.content.userInfo
        let type   = userInfo["type"]   as? String ?? ""
        let source = userInfo["source"] as? String ?? ""

        if type == "IN-APP" && source == "Paylisher" {
            // In-app mesaj: modal olarak göster
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
            } else {
                completionHandler([.sound, .list, .banner, .badge])
            }
        } else {
            // Normal push: banner göster
            completionHandler([.sound, .list, .banner, .badge])
        }
    }

    // MARK: - Background / Inactive In-App Mesaj

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        let type   = userInfo["type"]   as? String ?? ""
        let source = userInfo["source"] as? String ?? ""

        if type == "IN-APP" && source == "Paylisher" {
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
        }

        completionHandler(.newData)
    }

    // MARK: - Bildirime tıklanınca

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        completionHandler()
    }
}
