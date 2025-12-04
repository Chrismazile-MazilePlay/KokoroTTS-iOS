import Foundation

/// G2P реализация для японского языка
public class G2PJa: G2P {
    
    public init() {
        // TODO: Initialize Japanese G2P components
    }
    
    public func convert(_ text: String) throws -> G2PResult {
        // TODO: Implement Japanese G2P
        throw TTSError.invalidInput("G2PJa not implemented yet")
    }
}