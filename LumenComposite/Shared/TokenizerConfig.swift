import Foundation

#if canImport(Tokenizers)
import Tokenizers
#endif

/// Tokenizer configuration helper
public struct TokenizerConfigHelper {
    /// Get EOS token ID from tokenizer config
    public static func getEOSTokenID(from url: URL) -> Int? {
        let fm = FileManager.default
        
        // Try tokenizer_config.json first
        let configURL = url.appendingPathComponent("tokenizer_config.json")
        if fm.fileExists(atPath: configURL.path),
           let data = try? Data(contentsOf: configURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Check for eos_token_id
            if let eosTokenID = json["eos_token_id"] as? Int {
                return eosTokenID
            }
            
            // Check for eos_token (might be a dictionary with id)
            if let eosToken = json["eos_token"] as? [String: Any],
               let eosID = eosToken["id"] as? Int {
                return eosID
            }
        }
        
        // Try config.json (for MLX models)
        let mlxConfigURL = url.appendingPathComponent("config.json")
        if fm.fileExists(atPath: mlxConfigURL.path),
           let data = try? Data(contentsOf: mlxConfigURL),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            
            // Check for eos_token_id in model config
            if let eosTokenID = json["eos_token_id"] as? Int {
                return eosTokenID
            }
        }
        
        return nil
    }
    
    #if canImport(Tokenizers)
    /// Get EOS token ID from loaded tokenizer
    public static func getEOSTokenID(from tokenizer: Tokenizer) -> Int? {
        // Try to get EOS token from tokenizer
        // This is a simplified approach - the actual implementation depends on the tokenizer type
        // Most tokenizers use token ID 2 (GPT-2 style) or have it in config
        return 2 // Default fallback
    }
    #endif
}






