import Foundation
import CryptoKit
import Security

// MARK: - Secure Chat Storage
public enum SecureStorage {
    private static let serviceName = "com.lumen.app"
    private static let encryptionKeyKey = "com.lumen.encryptionKey"
    private static let threadsKey = "com.lumen.threads"

    // Get or create encryption key
    private static func getEncryptionKey() throws -> SymmetricKey {
        // Try to get existing key from Keychain
        if let keyData = try? KeychainHelper.getData(forKey: encryptionKeyKey) {
            let key = SymmetricKey(data: keyData) // not throwing
            return key
        }

        // Generate new key and store it
        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        try KeychainHelper.saveData(keyData, forKey: encryptionKeyKey)
        return key
    }

    // Encrypt data
    private static func encrypt(_ data: Data) throws -> Data {
        let key = try getEncryptionKey()
        return try AES.GCM.seal(data, using: key).combined!
    }

    // Decrypt data
    private static func decrypt(_ data: Data) throws -> Data {
        let key = try getEncryptionKey()
        let sealedBox = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(sealedBox, using: key)
    }

    // Save threads securely
    public static func saveThreads(_ threads: [ChatThread]) throws {
        let data = try JSONEncoder().encode(threads)
        let encryptedData = try encrypt(data)
        try KeychainHelper.saveData(encryptedData, forKey: threadsKey)
    }

    // Load threads securely
    public static func loadThreads() throws -> [ChatThread] {
        guard let encryptedData = try? KeychainHelper.getData(forKey: threadsKey) else {
            return []
        }
        let decryptedData = try decrypt(encryptedData)
        return try JSONDecoder().decode([ChatThread].self, from: decryptedData)
    }

    // Clear all stored data
    public static func clearAllData() throws {
        try? KeychainHelper.deleteData(forKey: encryptionKeyKey)
        try? KeychainHelper.deleteData(forKey: threadsKey)
    }
}

// MARK: - Keychain Helper
private enum KeychainHelper {
    private static let serviceName = "com.lumen.app"
    
    static func saveData(_ data: Data, forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        // Delete existing item first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            let error = NSError(domain: "KeychainError", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain save failed with error code: \(status)"
            ])
            throw error
        }
    }

    static func getData(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess {
            return result as? Data
        } else if status == errSecItemNotFound {
            return nil
        } else {
            let error = NSError(domain: "KeychainError", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain read failed with error code: \(status)"
            ])
            throw error
        }
    }

    static func deleteData(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            let error = NSError(domain: "KeychainError", code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "Keychain delete failed with error code: \(status)"
            ])
            throw error
        }
    }
}
