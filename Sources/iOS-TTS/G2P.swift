import Foundation

/// Токен с метаданными для G2P обработки (как в Python MToken)
public class MToken {
    let text: String
    let tag: String  // POS tag
    var whitespace: String  // Пробелы после токена
    var phonemes: String?  // Фонемы для токена
    var rating: Int? = nil  // Качество фонетизации (0-5)
    let startTs: Double?  // Временная метка начала
    let endTs: Double?    // Временная метка конца
    var underscore: Underscore  // Дополнительные метаданные (как _ в Python)
    
    /// Структура для дополнительных метаданных (как Python MToken.Underscore)
    public class Underscore {
        var isHead: Bool = true
        var alias: String? = nil
        var stress: Double? = nil  // -2 to 2, может быть 0.5/-0.5
        var currency: String? = nil
        var numFlags: String = ""
        var prespace: Bool = false
        var rating: Int? = nil
        
        public init(isHead: Bool = true, alias: String? = nil, stress: Double? = nil, currency: String? = nil, numFlags: String = "", prespace: Bool = false, rating: Int? = nil) {
            self.isHead = isHead
            self.alias = alias
            self.stress = stress
            self.currency = currency
            self.numFlags = numFlags
            self.prespace = prespace
            self.rating = rating
        }
    }
    
    public init(text: String, tag: String, whitespace: String = "", phonemes: String? = nil, startTs: Double? = nil, endTs: Double? = nil, underscore: Underscore? = nil) {
        self.text = text
        self.tag = tag
        self.whitespace = whitespace
        self.phonemes = phonemes
        self.startTs = startTs
        self.endTs = endTs
        self.underscore = underscore ?? Underscore()
    }
}

/// Результат G2P обработки
public struct G2PResult {
    let phonemeString: String
    let tokens: [MToken]
    
    public init(phonemeString: String, tokens: [MToken]) {
        self.phonemeString = phonemeString
        self.tokens = tokens
    }
}

/// Протокол для реализации G2P (Grapheme-to-Phoneme) конвертации
public protocol G2P {
    /// Основной метод конвертации текста в фонемы
    /// - Parameter text: Входной текст
    /// - Returns: Результат с фонемной строкой и токенами
    /// - Throws: Ошибка обработки
    func convert(_ text: String) throws -> G2PResult
}
