import Foundation

/// G2P реализация для китайского языка
public class G2PZh: G2P {
    
    public init() {
        // TODO: Initialize Chinese G2P components
    }
    
    public func convert(_ text: String) throws -> G2PResult {
        // TODO: Implement Chinese G2P
        throw TTSError.invalidInput("G2PZh not implemented yet")
    }
}