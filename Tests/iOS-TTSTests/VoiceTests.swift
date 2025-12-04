import Testing
import Foundation
@testable import iOS_TTS

/// Тесты для голосов и языков
struct VoiceTests {
    
    @Test("Голоса правильно определяют язык")
    func testVoiceLanguageDetection() {
        // American English
        #expect(VoiceStyle.amAdam.language == .englishUS)
        #expect(VoiceStyle.afHeart.language == .englishUS)
        
        // British English
        #expect(VoiceStyle.bfAlice.language == .englishGB)
        #expect(VoiceStyle.bmDaniel.language == .englishGB)
        
        // Other languages
        #expect(VoiceStyle.ffSiwis.language == .french)
        #expect(VoiceStyle.hfAlpha.language == .hindi)
        #expect(VoiceStyle.jfAlpha.language == .japanese)
        #expect(VoiceStyle.zfXiaobei.language == .chinese)
        #expect(VoiceStyle.efDora.language == .spanish)
        #expect(VoiceStyle.ifSara.language == .italian)
        #expect(VoiceStyle.pfDora.language == .portuguese)
    }
    
    @Test("Голоса правильно определяют пол")
    func testVoiceGenderDetection() {
        // Female voices
        #expect(VoiceStyle.afHeart.gender == .female)
        #expect(VoiceStyle.bfAlice.gender == .female)
        #expect(VoiceStyle.ffSiwis.gender == .female)
        #expect(VoiceStyle.hfAlpha.gender == .female)
        #expect(VoiceStyle.jfAlpha.gender == .female)
        #expect(VoiceStyle.zfXiaobei.gender == .female)
        #expect(VoiceStyle.efDora.gender == .female)
        #expect(VoiceStyle.ifSara.gender == .female)
        #expect(VoiceStyle.pfDora.gender == .female)
        
        // Male voices
        #expect(VoiceStyle.amAdam.gender == .male)
        #expect(VoiceStyle.bmDaniel.gender == .male)
        #expect(VoiceStyle.hmOmega.gender == .male)
        #expect(VoiceStyle.jmKumo.gender == .male)
        #expect(VoiceStyle.zmYunjian.gender == .male)
        #expect(VoiceStyle.emAlex.gender == .male)
        #expect(VoiceStyle.imNicola.gender == .male)
        #expect(VoiceStyle.pmAlex.gender == .male)
    }
    
    @Test("Фильтрация голосов по языку")
    func testVoicesFilteringByLanguage() {
        let americanVoices = VoiceStyle.voices(for: .englishUS)
        let britishVoices = VoiceStyle.voices(for: .englishGB)
        let frenchVoices = VoiceStyle.voices(for: .french)
        
        #expect(americanVoices.count == 20) // 11 женских + 9 мужских
        #expect(britishVoices.count == 8)   // 4 женских + 4 мужских
        #expect(frenchVoices.count == 1)    // 1 женский
        
        // Проверяем, что все американские голоса действительно американские
        for voice in americanVoices {
            #expect(voice.language == .englishUS)
        }
        
        // Проверяем, что все британские голоса действительно британские
        for voice in britishVoices {
            #expect(voice.language == .englishGB)
        }
    }
    
    @Test("Фильтрация голосов по полу")
    func testVoicesFilteringByGender() {
        let femaleVoices = VoiceStyle.femaleVoices
        let maleVoices = VoiceStyle.maleVoices
        
        #expect(femaleVoices.count == 29) // Общее количество женских голосов
        #expect(maleVoices.count == 25)   // Общее количество мужских голосов
        
        // Проверяем, что все женские голоса действительно женские
        for voice in femaleVoices {
            #expect(voice.gender == .female)
        }
        
        // Проверяем, что все мужские голоса действительно мужские
        for voice in maleVoices {
            #expect(voice.gender == .male)
        }
    }
    
    @Test("Фильтрация голосов по языку и полу")
    func testVoicesFilteringByLanguageAndGender() {
        let americanFemaleVoices = VoiceStyle.voices(for: .englishUS, gender: .female)
        let americanMaleVoices = VoiceStyle.voices(for: .englishUS, gender: .male)
        
        #expect(americanFemaleVoices.count == 11)
        #expect(americanMaleVoices.count == 9)
        
        // Проверяем, что все голоса соответствуют критериям
        for voice in americanFemaleVoices {
            #expect(voice.language == .englishUS)
            #expect(voice.gender == .female)
        }
        
        for voice in americanMaleVoices {
            #expect(voice.language == .englishUS)
            #expect(voice.gender == .male)
        }
    }
    
    @Test("Отображаемые имена голосов")
    func testVoiceDisplayNames() {
        #expect(VoiceStyle.amAdam.displayName == "Adam")
        #expect(VoiceStyle.afHeart.displayName == "Heart")
        #expect(VoiceStyle.bfAlice.displayName == "Alice")
        #expect(VoiceStyle.ffSiwis.displayName == "Siwis")
        #expect(VoiceStyle.zfXiaobei.displayName == "Xiaobei")
    }
    
    
    
    
    @Test("Всего голосов и языков")
    func testTotalVoicesAndLanguages() {
        #expect(VoiceStyle.allCases.count == 54) // Общее количество голосов
        #expect(Language.allCases.count == 9)    // Общее количество языков
        #expect(Gender.allCases.count == 2)      // Мужской и женский
    }
}