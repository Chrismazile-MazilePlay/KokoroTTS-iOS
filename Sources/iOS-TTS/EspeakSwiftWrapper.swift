import Foundation
import EspeakWrapper

/// Swift wrapper для espeak-ng C библиотеки
public class EspeakSwiftWrapper {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _isInitialized = false
    
    private static var isInitialized: Bool {
        lock.withLock { _isInitialized }
    }
    
    /// Инициализация espeak с данными из bundle
    public static func initialize() -> Bool {
        lock.withLock {
            guard !_isInitialized else { return true }
            
            let result = espeak_wrapper_initialize_with_bundle()
            _isInitialized = (result != 0)
            
            return _isInitialized
        }
    }
    
    /// Инициализация espeak с указанным путем к данным
    /// - Parameter dataPath: Путь к директории с espeak-ng-data
    /// - Returns: true если инициализация прошла успешно
    public static func initialize(withDataPath dataPath: String) -> Bool {
        lock.withLock {
            guard !_isInitialized else { return true }
            
            let result = espeak_wrapper_initialize_with_path(dataPath)
            _isInitialized = (result != 0)
            
            return _isInitialized
        }
    }
    
    /// Конвертация текста в фонемы
    /// - Parameters:
    ///   - text: Текст для конвертации
    ///   - language: Код языка (например "en-us", "fr", "es")
    ///   - dataPath: Опциональный путь к данным espeak
    /// - Returns: Фонемная строка или nil при ошибке
    public static func textToPhonemes(_ text: String, language: String, dataPath: String? = nil) -> String? {
        let initialized = if let dataPath = dataPath {
            initialize(withDataPath: dataPath)
        } else {
            initialize()
        }
        
        guard initialized else { return nil }
        
        let result = espeak_wrapper_text_to_phonemes(text, language)
        guard result.success != 0, let phonemes = result.phonemes else {
            return nil
        }
        return String(cString: phonemes)
    }
    
    /// Завершение работы с espeak
    public static func terminate() {
        lock.withLock {
            guard _isInitialized else { return }
            
            // TODO: Uncomment when C wrapper is properly linked
            // espeak_ng_Terminate()
            
            _isInitialized = false
        }
    }
    
    // MARK: - Stub Implementation
    
    /// Заглушка для обработки текста (пока нет реального espeak)
    private static func processTextAsPhonemes(_ text: String, language: String) -> String {
        var processed = text.lowercased()
        
        // Базовые правила для разных языков
        switch language {
        case "fr", "fr-fr":
            processed = processFrenchPhonemes(processed)
        case "es":
            processed = processSpanishPhonemes(processed)
        case "it":
            processed = processItalianPhonemes(processed)
        case "pt", "pt-br":
            processed = processPortuguesePhonemes(processed)
        case "hi":
            processed = processHindiPhonemes(processed)
        default:
            // Для неизвестных языков просто возвращаем как есть
            break
        }
        
        return processed
    }
    
    private static func processFrenchPhonemes(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "eau", with: "o")
            .replacingOccurrences(of: "eu", with: "ø")
            .replacingOccurrences(of: "ou", with: "u")
            .replacingOccurrences(of: "ch", with: "ʃ")
            .replacingOccurrences(of: "qu", with: "k")
    }
    
    private static func processSpanishPhonemes(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "ñ", with: "ɲ")
            .replacingOccurrences(of: "ll", with: "ʎ")
            .replacingOccurrences(of: "rr", with: "r")
            .replacingOccurrences(of: "j", with: "x")
    }
    
    private static func processItalianPhonemes(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "gli", with: "ʎ")
            .replacingOccurrences(of: "gn", with: "ɲ")
            .replacingOccurrences(of: "sc", with: "ʃ")
    }
    
    private static func processPortuguesePhonemes(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "nh", with: "ɲ")
            .replacingOccurrences(of: "lh", with: "ʎ")
            .replacingOccurrences(of: "ão", with: "ɐ̃w")
    }
    
    private static func processHindiPhonemes(_ text: String) -> String {
        // Для хинди пока просто возвращаем как есть
        return text
    }
}