import Testing
import Foundation
@testable import iOS_TTS

struct G2PSimpleTests {
    
    @Test func testG2PSimpleInitialization() async throws {
        // Тестируем инициализацию для французского
        let frenchG2P = try G2PSimple(language: .french)
        #expect(frenchG2P != nil)
        
        // Тестируем инициализацию для испанского
        let spanishG2P = try G2PSimple(language: .spanish)
        #expect(spanishG2P != nil)
        
        // Тестируем инициализацию для итальянского
        let italianG2P = try G2PSimple(language: .italian)
        #expect(italianG2P != nil)
        
        // Тестируем инициализацию для португальского
        let portugueseG2P = try G2PSimple(language: .portuguese)
        #expect(portugueseG2P != nil)
        
        // Тестируем инициализацию для хинди
        let hindiG2P = try G2PSimple(language: .hindi)
        #expect(hindiG2P != nil)
    }
    
    @Test func testG2PSimpleInvalidLanguage() async throws {
        // Тестируем что G2PSimple отклоняет неподдерживаемые языки
        #expect(throws: TTSError.self) {
            _ = try G2PSimple(language: .englishUS)
        }
    }
    
    @Test func testG2PSimpleBasicConversion() async throws {
        let frenchG2P = try G2PSimple(language: .french)
        
        // Тестируем базовую конвертацию
        let result = try frenchG2P.convert("bonjour")
        
        // Результат должен содержать фонемную строку
        #expect(!result.phonemeString.isEmpty)
        
        // Токены пока пустые в простой реализации
        #expect(result.tokens.isEmpty)
        
        print("French 'bonjour' -> '\(result.phonemeString)'")
    }
    
    @Test func testG2PSimpleLanguageSpecificProcessing() async throws {
        // Французский
        let frenchG2P = try G2PSimple(language: .french)
        let frenchResult = try frenchG2P.convert("château")
        print("French 'château' -> '\(frenchResult.phonemeString)'")
        
        // Испанский
        let spanishG2P = try G2PSimple(language: .spanish)
        let spanishResult = try spanishG2P.convert("llamar")
        print("Spanish 'llamar' -> '\(spanishResult.phonemeString)'")
        
        // Итальянский
        let italianG2P = try G2PSimple(language: .italian)
        let italianResult = try italianG2P.convert("gnocchi")
        print("Italian 'gnocchi' -> '\(italianResult.phonemeString)'")
        
        // Португальский
        let portugueseG2P = try G2PSimple(language: .portuguese)
        let portugueseResult = try portugueseG2P.convert("trabalho")
        print("Portuguese 'trabalho' -> '\(portugueseResult.phonemeString)'")
        
        // Все результаты должны содержать фонемные строки
        #expect(!frenchResult.phonemeString.isEmpty)
        #expect(!spanishResult.phonemeString.isEmpty)
        #expect(!italianResult.phonemeString.isEmpty)
        #expect(!portugueseResult.phonemeString.isEmpty)
    }
    
    @Test func testEspeakWrapperDirectly() async throws {
        // Тестируем wrapper напрямую
        guard let frenchPhonemes = EspeakSwiftWrapper.textToPhonemes("bonjour", language: "fr-fr") else {
            throw TTSError.invalidInput("EspeakWrapper returned nil")
        }
        
        #expect(!frenchPhonemes.isEmpty)
        print("Direct wrapper French 'bonjour' -> '\(frenchPhonemes)'")
        
        guard let spanishPhonemes = EspeakSwiftWrapper.textToPhonemes("hola", language: "es") else {
            throw TTSError.invalidInput("EspeakWrapper returned nil")
        }
        
        #expect(!spanishPhonemes.isEmpty)
        print("Direct wrapper Spanish 'hola' -> '\(spanishPhonemes)'")
    }
}