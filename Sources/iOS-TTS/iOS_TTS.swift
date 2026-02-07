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
    // American English (11 female, 9 male)
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
    
    // British English (4 female, 4 male)
    case bfAlice = "bf_alice"
    case bfEmma = "bf_emma"
    case bfIsabella = "bf_isabella"
    case bfLily = "bf_lily"
    case bmDaniel = "bm_daniel"
    case bmFable = "bm_fable"
    case bmGeorge = "bm_george"
    case bmLewis = "bm_lewis"
    
    // French (1 female)
    case ffSiwis = "ff_siwis"
    
    // Hindi (2 female, 2 male)
    case hfAlpha = "hf_alpha"
    case hfBeta = "hf_beta"
    case hmOmega = "hm_omega"
    case hmPsi = "hm_psi"
    
    // Japanese (4 female, 1 male)
    case jfAlpha = "jf_alpha"
    case jfGongitsune = "jf_gongitsune"
    case jfNezumi = "jf_nezumi"
    case jfTebukuro = "jf_tebukuro"
    case jmKumo = "jm_kumo"
    
    // Mandarin Chinese (4 female, 4 male)
    case zfXiaobei = "zf_xiaobei"
    case zfXiaoni = "zf_xiaoni"
    case zfXiaoxiao = "zf_xiaoxiao"
    case zfXiaoyi = "zf_xiaoyi"
    case zmYunjian = "zm_yunjian"
    case zmYunxi = "zm_yunxi"
    case zmYunxia = "zm_yunxia"
    case zmYunyang = "zm_yunyang"
    
    // Spanish (1 female, 2 male)
    case efDora = "ef_dora"
    case emAlex = "em_alex"
    case emSanta = "em_santa"
    
    // Italian (1 female, 1 male)
    case ifSara = "if_sara"
    case imNicola = "im_nicola"
    
    // Brazilian Portuguese (1 female, 2 male)
    case pfDora = "pf_dora"
    case pmAlex = "pm_alex"
    case pmSanta = "pm_santa"
    
    var filename: String {
        return "\(rawValue).npy"
    }
    
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
    
    public var gender: Gender {
        let secondChar = String(rawValue.dropFirst().prefix(1))
        return secondChar == "f" ? .female : .male
    }
    
    public var displayName: String {
        let name = String(rawValue.dropFirst(3))
        return name.capitalized
    }
    
    public static func voices(for language: Language) -> [VoiceStyle] {
        return allCases.filter { $0.language == language }
    }
    
    public static var femaleVoices: [VoiceStyle] {
        return allCases.filter { $0.gender == .female }
    }
    
    public static var maleVoices: [VoiceStyle] {
        return allCases.filter { $0.gender == .male }
    }
    
    public static func voices(for language: Language, gender: Gender) -> [VoiceStyle] {
        return allCases.filter { $0.language == language && $0.gender == gender }
    }
}

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

// MARK: - Generation Options

/// Options for TTS audio generation with voice modification support.
///
/// ## Parameters
/// - `style`: Voice style (e.g., .afHeart, .amAdam)
/// - `speed`: Playback speed 0.5-2.0 (default: 1.0)
/// - `pitchShiftSemitones`: Pitch shift -12 to +12 semitones (default: 0)
/// - `pitchRangeScale`: Expressiveness 0.5-1.5 (default: 1.0)
///
/// ## Usage
/// ```swift
/// // Default settings
/// let options = GenerationOptions()
///
/// // Custom voice with pitch modifications
/// let options = GenerationOptions(
///     style: .afHeart,
///     speed: 0.9,
///     pitchShiftSemitones: 2.0,
///     pitchRangeScale: 1.2
/// )
/// ```
public struct GenerationOptions {
    public let style: VoiceStyle
    public let speed: Float
    public let pitchShiftSemitones: Float
    public let pitchRangeScale: Float
    
    public init(
        style: VoiceStyle = .amAdam,
        speed: Float = 1.0,
        pitchShiftSemitones: Float = 0.0,
        pitchRangeScale: Float = 1.0
    ) {
        self.style = style
        self.speed = max(0.5, min(2.0, speed))
        self.pitchShiftSemitones = max(-12.0, min(12.0, pitchShiftSemitones))
        self.pitchRangeScale = max(0.5, min(1.5, pitchRangeScale))
    }
}

// MARK: - TTS Pipeline

public class TTSPipeline {
    private let model: TTSModel
    private let modelPath: URL
    private let vocabURL: URL
    private let postaggerModelURL: URL
    public private(set) var language: Language
    private let g2p: G2P
    private var vocab: [String: Int] = [:]
    
    public var performanceMonitoringEnabled: Bool {
        get { PerformanceMonitor.shared.isEnabled }
        set { PerformanceMonitor.shared.isEnabled = newValue }
    }
    
    public init(modelPath: URL, vocabURL: URL, postaggerModelURL: URL, language: Language, espeakDataPath: String? = nil, g2p: G2P? = nil, configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        self.modelPath = modelPath
        self.vocabURL = vocabURL
        self.postaggerModelURL = postaggerModelURL
        self.language = language
        self.model = try TTSModel(modelPath: modelPath, configuration: configuration)

        if let externalG2P = g2p {
            self.g2p = externalG2P
        } else {
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
        }
        try loadVocabulary()
    }
    
    private func getInputIds(from text: String) throws -> [Int] {
        let g2pResult = try g2p.convert(text)
        let phonemeString = g2pResult.phonemeString
        
        var inputIds: [Int] = []
        
        for scalar in phonemeString.unicodeScalars {
            let charStr = String(Character(scalar))
            
            if let vocabId = vocab[charStr] {
                inputIds.append(vocabId)
            } else {
                let unkId = vocab["<unk>"] ?? vocab["[UNK]"] ?? 1
                inputIds.append(unkId)
            }
        }
        
        let bosEosId = vocab["<pad>"] ?? vocab["[PAD]"] ?? 0
        let finalIds = [bosEosId] + inputIds + [bosEosId]
        
        return finalIds
    }
    
    public func generate(text: String, options: GenerationOptions = GenerationOptions()) async throws -> [Float] {
        // Verify voice language matches pipeline language
        let voiceLanguage = options.style.language
        guard voiceLanguage == language else {
            throw TTSError.invalidInput("Voice language \(voiceLanguage.rawValue) doesn't match pipeline language \(language.rawValue)")
        }
        
        // Load style vectors from .npy file (format: 510x1x256)
        let styleURL = modelPath.appendingPathComponent(options.style.filename)
        let rawStyleVector = try NPYParser.loadArray(from: styleURL)
        
        // Get input IDs
        let inputIds = try getInputIds(from: text)
        let sequenceLength = inputIds.count
        
        // Validate style data format (should be 510x1x256 = 130560 elements)
        let expectedTotalElements = 510 * 256
        guard rawStyleVector.count == expectedTotalElements else {
            throw NSError(domain: "TTSPipeline", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Style vector should have \(expectedTotalElements) elements (510x1x256), got \(rawStyleVector.count)"
            ])
        }
        
        // Select appropriate style vector based on phoneme sequence length
        // Following Python logic: pack[len(ps)-1] where ps is phoneme sequence
        let styleIndex = min(max(sequenceLength - 1, 0), 509)
        let styleStartIndex = styleIndex * 256
        let styleEndIndex = styleStartIndex + 256
        
        let styleVector = Array(rawStyleVector[styleStartIndex..<styleEndIndex])
        
        #if DEBUG
        print("Selected style vector \(styleIndex) for sequence length \(sequenceLength)")
        #endif
        
        // Call model inference with pitch modification parameters
        return try model.infer(
            inputIds: inputIds,
            refS: styleVector,
            speed: options.speed,
            pitchShiftSemitones: options.pitchShiftSemitones,
            pitchRangeScale: options.pitchRangeScale
        )
    }
    
    public func getPerformanceReport() -> String {
        return PerformanceMonitor.shared.generateReport()
    }
    
    public func printPerformanceReport() {
        PerformanceMonitor.shared.printReport()
    }
    
    public func clearPerformanceMeasurements() {
        PerformanceMonitor.shared.clearMeasurements()
    }
    
    private func loadVocabulary() throws {
        let vocabFileName: String
        
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
        
        #if DEBUG
        print("Loading vocab from: \(vocabFileURL.path)")
        #endif
        
        guard FileManager.default.fileExists(atPath: vocabFileURL.path) else {
            print("Vocabulary file not found: \(vocabFileName). G2P may not work correctly.")
            return
        }
        
        let data = try Data(contentsOf: vocabFileURL)
        guard let vocabDict = try JSONSerialization.jsonObject(with: data) as? [String: Int] else {
            throw TTSError.invalidInput("Invalid vocab file format: \(vocabFileName)")
        }
        
        self.vocab = vocabDict
        
        #if DEBUG
        print("Loaded \(vocab.count) vocab entries")
        #endif
    }
}
