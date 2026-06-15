//
//  NotificationService.swift
//  PaylisherNSE  (Notification Service Extension)
//
//  Per-device push language for iOS — the on-device equivalent of Android's
//  InAppLocalize.localize().
//
//  For a backgrounded / closed app, iOS draws the notification from the APNs
//  `aps.alert`, which the backend bakes in the campaign's defaultLang (e.g.
//  Turkish). A Notification Service Extension is the only place app code can
//  rewrite a remote notification before display, and it runs only when the push
//  carries `aps."mutable-content" = 1` (the backend sends this). Here we read
//  the full {tr,en,…} language maps the backend ships on the FCM `data` channel
//  and pick the device's language.
//
//  Self-contained (Foundation + UserNotifications only) — no Paylisher SDK link.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        guard let bestAttemptContent =
                request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        self.bestAttemptContent = bestAttemptContent

        let userInfo = bestAttemptContent.userInfo

        // Only touch Paylisher pushes; anything else passes through unchanged.
        guard (userInfo["source"] as? String) == "Paylisher" else {
            contentHandler(bestAttemptContent)
            return
        }

        let defaultLang = userInfo["defaultLang"] as? String

        // Re-localize title/body from the data-channel i18n maps. If a field
        // isn't a {lang: text} map, keep what iOS had (the baked defaultLang
        // alert) — never blank it out.
        if let titleJSON = userInfo["title"] as? String,
           let localizedTitle = Self.localize(titleJSON, defaultLang: defaultLang) {
            bestAttemptContent.title = localizedTitle
        }
        if let bodyJSON = userInfo["message"] as? String,
           let localizedBody = Self.localize(bodyJSON, defaultLang: defaultLang) {
            bestAttemptContent.body = localizedBody
        }

        // Optional rich media (parity with Android's BigPictureStyle).
        if let imageUrlString = userInfo["imageUrl"] as? String,
           !imageUrlString.isEmpty,
           let imageUrl = URL(string: imageUrlString) {
            Self.downloadAttachment(from: imageUrl) { attachment in
                if let attachment = attachment {
                    bestAttemptContent.attachments = [attachment]
                }
                contentHandler(bestAttemptContent)
            }
        } else {
            contentHandler(bestAttemptContent)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        if let contentHandler = contentHandler,
           let bestAttemptContent = bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

    // MARK: - Localization (device language → defaultLang → first value)

    /// Picks the device-language value from a `{"tr":"…","en":"…"}` JSON string.
    /// Order: device language → campaign defaultLang → first available value.
    /// Returns nil if `jsonString` isn't a non-empty language map. Uses
    /// `Locale.preferredLanguages` (the real device language, independent of the
    /// extension bundle's localizations), primary subtag only ("en-TR" → "en").
    static func localize(_ jsonString: String, defaultLang: String?) -> String? {
        guard let data = jsonString.data(using: .utf8),
              let map = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              !map.isEmpty else {
            return nil
        }
        let deviceLang = (Locale.preferredLanguages.first ?? Locale.current.languageCode ?? "")
            .split(separator: "-").first.map { $0.lowercased() }

        if let deviceLang = deviceLang, let value = map[deviceLang] {
            return value
        }
        if let defaultLang = defaultLang, let value = map[defaultLang] {
            return value
        }
        return map.values.first
    }

    static func downloadAttachment(
        from url: URL,
        completion: @escaping (UNNotificationAttachment?) -> Void
    ) {
        URLSession.shared.downloadTask(with: url) { localURL, _, _ in
            guard let localURL = localURL else { completion(nil); return }
            let ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: localURL, to: tmpURL)
                let attachment = try UNNotificationAttachment(
                    identifier: UUID().uuidString, url: tmpURL, options: nil
                )
                completion(attachment)
            } catch {
                completion(nil)
            }
        }.resume()
    }
}
