import Foundation
#if canImport(MLXVLM)
import MLXVLM

enum VLMShim {
    static func bootstrap() {
        _ = VLMRegistry.shared
    }
}
#endif
