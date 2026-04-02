import UIKit

extension UIDevice {
    /// Uygulama silinene kadar sabit kalan cihaz kimliği.
    static var staticID: String {
        if let id = UIDevice.current.identifierForVendor?.uuidString {
            return id
        }
        let key = "com.paylisher.test.deviceID"
        if let saved = KeychainHelper.read(key: key) { return saved }
        let new = UUID().uuidString
        KeychainHelper.save(key: key, value: new)
        return new
    }
}

struct KeychainHelper {
    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecValueData as String: data]
        SecItemDelete(q as CFDictionary)
        SecItemAdd(q as CFDictionary, nil)
    }

    static func read(key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrAccount as String: key,
                                kSecReturnData as String: true,
                                kSecMatchLimit as String: kSecMatchLimitOne]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
