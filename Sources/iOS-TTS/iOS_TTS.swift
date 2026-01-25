// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import CoreML

public enum TTSError: Error {
    case modelNotFound(String)
    case predictionFailed(String)
    case invalidInput(String)
    case vocabLoadFailed(String)
}

public enum Language: String, CaseIterable {
    case englishUS = "en_us"
    case englishGB = "en_gb"
    case french = "fr"
    case hindi = "hi"
    case japanese = "ja"
    case chinese = "zh"
    case spanish = "es"
    case italian = "it"
    case portuguese = "pt"
    
    /// Получить базовый язык (без региона)
    var baseLanguage: String {
        switch self {
        case .englishUS, .englishGB:
            return "en"
        case .french:
            return "fr"
        case .hindi:
            return "hi"
        case .japanese:
            return "ja"
        case .chinese:
            return "zh"
        case .spanish:
            return "es"
        case .italian:
            return "it"
        case .portuguese:
            return "pt"
        }
    }
    
    /// Проверить, является ли это американским вариантом
    var isAmericanEnglish: Bool {
        switch self {
        case .englishUS:
            return true
        case .englishGB:
            return false
        default:
            return false
        }
    }
    
    
}

public enum VoiceStyle: String, CaseIterable {
    // American English (11 женских, 9 мужских)
    case afHeart = "af_heart"
    case afAlloy = "af_alloy"
    case afAoede = "af_aoede"
    case afBella = "af_bella"
    case afJessica = "af_jessica"
    case afKore = "af_kore"
    case afNicole = "af_nicole"
    case afNova = "af_nova"
    case afRiver = "af_river"
    case afSarah = "af_sarah"
    case afSky = "af_sky"
    case amAdam = "am_adam"
    case amEcho = "am_echo"
    case amEric = "am_eric"
    case amFenrir = "am_fenrir"
    case amLiam = "am_liam"
    case amMichael = "am_michael"
    case amOnyx = "am_onyx"
    case amPuck = "am_puck"
    case amSanta = "am_santa"
    
    // British English (4 женских, 4 мужских)
    case bfAlice = "bf_alice"
    case bfEmma = "bf_emma"
    case bfIsabella = "bf_isabella"
    case bfLily = "bf_lily"
    case bmDaniel = "bm_daniel"
    case bmFable = "bm_fable"
    case bmGeorge = "bm_george"
    case bmLewis = "bm_lewis"
    
    // French (1 женский)
    case ffSiwis = "ff_siwis"
    
    // Hindi (2 женских, 2 мужских)
    case hfAlpha = "hf_alpha"
    case hfBeta = "hf_beta"
    case hmOmega = "hm_omega"
    case hmPsi = "hm_psi"
    
    // Japanese (4 женских, 1 мужской)
    case jfAlpha = "jf_alpha"
    case jfGongitsune = "jf_gongitsune"
    case jfNezumi = "jf_nezumi"
    case jfTebukuro = "jf_tebukuro"
    case jmKumo = "jm_kumo"
    
    // Mandarin Chinese (4 женских, 4 мужских)
    case zfXiaobei = "zf_xiaobei"
    case zfXiaoni = "zf_xiaoni"
    case zfXiaoxiao = "zf_xiaoxiao"
    case zfXiaoyi = "zf_xiaoyi"
    case zmYunjian = "zm_yunjian"
    case zmYunxi = "zm_yunxi"
    case zmYunxia = "zm_yunxia"
    case zmYunyang = "zm_yunyang"
    
    // Spanish (1 женский, 2 мужских)
    case efDora = "ef_dora"
    case emAlex = "em_alex"
    case emSanta = "em_santa"
    
    // Italian (1 женский, 1 мужской)
    case ifSara = "if_sara"
    case imNicola = "im_nicola"
    
    // Brazilian Portuguese (1 женский, 2 мужских)
    case pfDora = "pf_dora"
    case pmAlex = "pm_alex"
    case pmSanta = "pm_santa"
    
    var filename: String {
        return "\(rawValue).npy"
    }
    
    /// Определить язык голоса
    public var language: Language {
        let prefix = String(rawValue.prefix(2))
        switch prefix {
        case "af", "am":
            return .englishUS
        case "bf", "bm":
            return .englishGB
        case "ff", "fm":
            return .french
        case "hf", "hm":
            return .hindi
        case "jf", "jm":
            return .japanese
        case "zf", "zm":
            return .chinese
        case "ef", "em":
            return .spanish
        case "if", "im":
            return .italian
        case "pf", "pm":
            return .portuguese
        default:
            return .englishUS
        }
    }
    
    /// Определить пол голоса
    public var gender: Gender {
        let secondChar = String(rawValue.dropFirst().prefix(1))
        return secondChar == "f" ? .female : .male
    }
    
    /// Получить отображаемое имя голоса
    public var displayName: String {
        let name = String(rawValue.dropFirst(3)) // Убираем префикс типа "af_"
        return name.capitalized
    }
    
    /// Получить все голоса для определенного языка
    public static func voices(for language: Language) -> [VoiceStyle] {
        return allCases.filter { $0.language == language }
    }
    
    /// Получить все женские голоса
    public static var femaleVoices: [VoiceStyle] {
        return allCases.filter { $0.gender == .female }
    }
    
    /// Получить все мужские голоса
    public static var maleVoices: [VoiceStyle] {
        return allCases.filter { $0.gender == .male }
    }
    
    /// Получить голоса по языку и полу
    public static func voices(for language: Language, gender: Gender) -> [VoiceStyle] {
        return allCases.filter { $0.language == language && $0.gender == gender }
    }
}

/// Пол голоса
public enum Gender: String, CaseIterable {
    case female = "female"
    case male = "male"
    
    public var displayName: String {
        switch self {
        case .female:
            return "Female"
        case .male:
            return "Male"
        }
    }
}

public struct GenerationOptions {
    public let style: VoiceStyle
    public let speed: Float
    
    public init(style: VoiceStyle = .amAdam, speed: Float = 1.0) {
        self.style = style
        self.speed = speed
    }
}

public class TTSPipeline {
    private let model: TTSModel
    private let modelPath: URL
    private let vocabURL: URL
    private let postaggerModelURL: URL
    public private(set) var language: Language  // Публичное для чтения, приватное для записи
    private let g2p: G2P
    private var vocab: [String: Int] = [:]
    
    /// Enable or disable performance monitoring
    public var performanceMonitoringEnabled: Bool {
        get { PerformanceMonitor.shared.isEnabled }
        set { PerformanceMonitor.shared.isEnabled = newValue }
    }
    
    
    public init(modelPath: URL, vocabURL: URL, postaggerModelURL: URL, language: Language, espeakDataPath: String? = nil, configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        self.modelPath = modelPath
        self.vocabURL = vocabURL
        self.postaggerModelURL = postaggerModelURL
        self.language = language
        self.model = try TTSModel(modelPath: modelPath, configuration: configuration)
        
        // Создаем G2P для указанного языка
        switch language {
        case .englishUS:
            self.g2p = try G2PEn(british: false, vocabURL: vocabURL, postaggerModelURL: postaggerModelURL, espeakDataPath: espeakDataPath)
        case .englishGB:
            self.g2p = try G2PEn(british: true, vocabURL: vocabURL, postaggerModelURL: postaggerModelURL, espeakDataPath: espeakDataPath)
        case .french, .spanish, .italian, .portuguese, .hindi:
            self.g2p = try G2PSimple(language: language, espeakDataPath: espeakDataPath)
        case .japanese:
            self.g2p = G2PJa()
        case .chinese:
            self.g2p = G2PZh()
        }
        try loadVocabulary()
    }
    
    /// Получает input IDs из текста для передачи в модель
    /// - Parameters:
    ///   - text: Входной текст
    /// - Returns: Массив input IDs
    /// - Throws: TTSError если обработка не удалась
    private func getInputIds(from text: String) throws -> [Int] {
        // print("🔍 TTSPipeline.getInputIds input: \"\(text)\"")
        
        // Используем G2P для конвертации текста в фонемы
        let g2pResult = try g2p.convert(text)
        let phonemeString = g2pResult.phonemeString
        
        // print("🔍 G2P phoneme string: \"\(phonemeString)\"")
        
        // Конвертируем фонемную строку в input IDs
        var inputIds: [Int] = []
        
        // Обрабатываем каждый Unicode scalar в фонемной строке
        // Важно: используем unicodeScalars вместо characters для правильной обработки 
        // носовых гласных (ɔ̃ = ɔ + ̃ как отдельные scalars)
        for scalar in phonemeString.unicodeScalars {
            let charStr = String(Character(scalar))
            
            // Ищем символ в vocab словаре
            if let vocabId = vocab[charStr] {
                inputIds.append(vocabId)
                // print("🔍 '\(charStr)' -> ID: \(vocabId)")
            } else {
                // Если символ не найден в vocab, используем ID для unknown token (обычно 1)
                let unkId = vocab["<unk>"] ?? vocab["[UNK]"] ?? 1
                inputIds.append(unkId)
                // print("⚠️ Unknown phoneme '\(charStr)' -> UNK ID: \(unkId)")
            }
        }
        
        // Добавляем BOS/EOS токены как указано в CLAUDE.md: [0] + ids + [0]
        let bosEosId = vocab["<pad>"] ?? vocab["[PAD]"] ?? 0  // BOS/EOS обычно 0
        let finalIds = [bosEosId] + inputIds + [bosEosId]
        
        print("🔍 Final input IDs (\(finalIds.count) tokens): \(finalIds)")
        
        return finalIds
    }
    
    public func generate(text: String, options: GenerationOptions = GenerationOptions()) async throws -> [Float] {
        // Проверяем совместимость голоса с языком pipeline
        let voiceLanguage = options.style.language
        guard voiceLanguage == language else {
            throw TTSError.invalidInput("Voice language \(voiceLanguage.rawValue) doesn't match pipeline language \(language.rawValue)")
        }
        
        // Load style vectors from .npy file (format: 510x1x256)
        let styleURL = modelPath.appendingPathComponent(options.style.filename)
        let rawStyleVector = try NPYParser.loadArray(from: styleURL)
        
        // Получаем input IDs
        let inputIds = try getInputIds(from: text)
        let sequenceLength = inputIds.count
        
        // Validate style data format (should be 510x1x256 = 130560 elements)
        let expectedTotalElements = 510 * 256 // 510 style vectors, each 256 elements
        guard rawStyleVector.count == expectedTotalElements else {
            throw NSError(domain: "TTSPipeline", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Style vector should have \(expectedTotalElements) elements (510x1x256), got \(rawStyleVector.count)"
            ])
        }
        
        // Select appropriate style vector based on phoneme sequence length
        // Following Python logic: pack[len(ps)-1] where ps is phoneme sequence
        let styleIndex = min(max(sequenceLength - 1, 0), 509) // Clamp to valid range [0, 509]
        let styleStartIndex = styleIndex * 256
        let styleEndIndex = styleStartIndex + 256
        
        let styleVector = Array(rawStyleVector[styleStartIndex..<styleEndIndex])
        print("Selected style vector \(styleIndex) for sequence length \(sequenceLength)")
        
        // Call model inference
        return try model.infer(inputIds: inputIds, refS: styleVector, speed: options.speed)
    }
    
    /// Get the performance report for the last generation
    /// - Returns: A formatted performance report string
    public func getPerformanceReport() -> String {
        return PerformanceMonitor.shared.generateReport()
    }
    
    /// Print the performance report to console
    public func printPerformanceReport() {
        PerformanceMonitor.shared.printReport()
    }
    
    /// Clear all performance measurements
    public func clearPerformanceMeasurements() {
        PerformanceMonitor.shared.clearMeasurements()
    }
    
    private func loadVocabulary() throws {
        let vocabFileName: String
        
        // Определяем какой vocab файл нужен на основе текущего языка
        switch language {
        case .englishUS:
            vocabFileName = "en_us_vocab.json"
        case .englishGB:
            vocabFileName = "en_gb_vocab.json"
        case .french:
            vocabFileName = "f_vocab.json"
        case .hindi:
            vocabFileName = "h_vocab.json"
        case .japanese:
            vocabFileName = "j_vocab.json"
        case .chinese:
            vocabFileName = "z_vocab.json"
        case .spanish:
            vocabFileName = "e_vocab.json"
        case .italian:
            vocabFileName = "i_vocab.json"
        case .portuguese:
            vocabFileName = "p_vocab.json"
        }
        
        let vocabFileURL = vocabURL.appendingPathComponent(vocabFileName)
        
        // Загружаем vocab файл
        guard FileManager.default.fileExists(atPath: vocabFileURL.path) else {
            print("⚠️ Vocabulary file not found: \(vocabFileName). G2P may not work correctly.")
            return
        }
        
        let data = try Data(contentsOf: vocabFileURL)
        guard let vocabDict = try JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            throw TTSError.invalidInput("Invalid vocab file format: \(vocabFileName)")
        }
        
        self.vocab = vocabDict
        
        print("🔍 Loaded vocabulary with \(vocab.count) tokens")
        
        // Выводим несколько примеров для отладки
        let sampleTokens = Array(vocab.keys.prefix(5))
        for token in sampleTokens {
            print("🔍 Vocab example: '\(token)' -> \(vocab[token] ?? -1)")
        }
    }
    
}
