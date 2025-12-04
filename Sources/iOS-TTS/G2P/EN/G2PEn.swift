import Foundation
import SwiftPOSTagger

/// G2P реализация для английского языка
public class G2PEn: G2P {
    private let isAmericanEnglish: Bool
    private let vocabURL: URL
    private let postagger: SwiftPOSTagger
    private let lexicon: Lexicon
    private let unk: String = "❓"
    
    /// Инициализация G2P для английского языка
    /// - Parameters:
    ///   - british: false для американского английского, true для британского
    ///   - vocabURL: URL папки с vocab файлами (us_gold.json, us_silver.json, gb_gold.json, gb_silver.json)
    ///   - postaggerModelURL: URL папки с моделью SwiftPOSTagger (содержит Model.mlmodelc, vocab.txt, outTokens.txt)
    public init(british: Bool, vocabURL: URL, postaggerModelURL: URL) throws {
        self.isAmericanEnglish = !british
        self.vocabURL = vocabURL
        
        // Инициализируем POS tagger
        self.postagger = try SwiftPOSTagger(modelDirectoryURL: postaggerModelURL)
        
        // Инициализируем Lexicon
        self.lexicon = try Lexicon(british: british, vocabURL: vocabURL)
    }
    
    // MARK: - G2P Protocol Implementation
    
    public func convert(_ text: String) throws -> G2PResult {
        
        let preprocessResult = G2PEn.preprocess(text)
        print("🔍 G2P.preprocess result: \"\(preprocessResult.result)\"")
        print("🔍 G2P.preprocess tokens: \(preprocessResult.tokens)")
        print("🔍 G2P.preprocess features: \(preprocessResult.features)")
        
        // Токенизация и POS-теггинг
        var tokens = try tokenize(text: preprocessResult.result, tokens: preprocessResult.tokens, features: preprocessResult.features)
        for (i, token) in tokens.enumerated() {
            print("🔍 Token[\(i)]: text='\(token.text)', tag='\(token.tag)', whitespace='\(token.whitespace)', phonemes='\(token.phonemes ?? "nil")', stress=\(token.underscore.stress?.description ?? "nil"), numFlags='\(token.underscore.numFlags)', rating=\(token.underscore.rating?.description ?? "nil"), isHead=\(token.underscore.isHead)")
        }
        // fold_left - объединение токенов
        tokens = foldLeft(tokens: tokens)
        
        // retokenize - разбиение на подтокены
        let words = G2PEn.retokenize(tokens: tokens)
        
        // Процесс как в Python __call__ метода
        var context = TokenContext()
        
        // Обрабатываем в обратном порядке как в Python
        for i in stride(from: words.count - 1, through: 0, by: -1) {
            let word = words[i]
            
            if let singleToken = word as? MToken {
                // Отдельный токен - обрабатываем через lexicon
                if singleToken.phonemes == nil {
                    let (phonemes, rating) = lexicon.processToken(singleToken, context: context)
                    singleToken.phonemes = phonemes
                    singleToken.rating = rating
                }
                context = tokenContext(context: context, phonemes: singleToken.phonemes, token: singleToken)
            } else if let tokenGroup = word as? [MToken] {
                // Группа токенов - сложная логика как в Python
                processTokenGroup(tokenGroup, context: &context)
            }
        }
        
        // Финальная обработка - собираем токены и убираем группы
        var finalTokens: [MToken] = []
        for word in words {
            if let singleToken = word as? MToken {
                finalTokens.append(singleToken)
            } else if let tokenGroup = word as? [MToken] {
                let mergedToken = mergeTokens(tokenGroup, unk: unk)
                finalTokens.append(mergedToken)
            }
        }
        
        // Собираем результат как в Python: result = ''.join((self.unk if tk.phonemes is None else tk.phonemes) + tk.whitespace for tk in tokens)
        let phonemeString = finalTokens.map { token in
            let phonemes = token.phonemes ?? unk
            return phonemes + token.whitespace
        }.joined()
        
        print("🔍 Final phoneme string: \"\(phonemeString)\"")
        
        return G2PResult(phonemeString: phonemeString, tokens: finalTokens)
    }
    
    /// Токенизация текста точно как в Python G2P.tokenize
    public func tokenize(text: String, tokens: [String], features: [Int: Any]) throws -> [MToken] {
        
        // doc = self.nlp(text) - используем SwiftPOSTagger
        let tokenTagPairs = try postagger.predict(text: text)
        
        // Создаем MToken объекты как в Python
        var mutableTokens: [MToken] = []
        for (index, (tokenText, tag)) in tokenTagPairs.enumerated() {
            // Последний токен не имеет whitespace, остальные имеют пробел
            let whitespace = (index == tokenTagPairs.count - 1) ? "" : " "
            let mtoken = MToken(
                text: tokenText,
                tag: tag,
                whitespace: whitespace,
                underscore: MToken.Underscore(isHead: true, numFlags: "", prespace: false)
            )
            mutableTokens.append(mtoken)
        }
        
        // if not features: return mutable_tokens
        if features.isEmpty {
            let correctedTokens = fixApostropheTokens(mutableTokens)
            logTokenizeResult(correctedTokens)
            return correctedTokens
        }
        
        // Применяем фичи к токенам (упрощенная версия без spacy alignment)
        // В Python используется spacy.training.Alignment.from_strings для выравнивания
        // Мы делаем простое выравнивание по индексам
        for (featureIndex, featureValue) in features {
            if featureIndex < mutableTokens.count {
                let token = mutableTokens[featureIndex]
                
                // assert isinstance(v, str) or isinstance(v, int) or v in (0.5, -0.5)
                if let intValue = featureValue as? Int {
                    // if not isinstance(v, str): mutable_tokens[j]._.stress = v
                    token.underscore.stress = Double(intValue)
                } else if let doubleValue = featureValue as? Double {
                    token.underscore.stress = doubleValue
                } else if let stringValue = featureValue as? String {
                    if stringValue.hasPrefix("/") {
                        // elif v.startswith('/'): 
                        //   mutable_tokens[j]._.is_head = i == 0
                        //   mutable_tokens[j].phonemes = v.lstrip('/') if i == 0 else ''
                        //   mutable_tokens[j]._.rating = 5
                        token.underscore.isHead = true  // i == 0 (first occurrence)
                        token.phonemes = String(stringValue.dropFirst()) // v.lstrip('/')
                        token.underscore.rating = 5
                    } else if stringValue.hasPrefix("#") {
                        // elif v.startswith('#'): mutable_tokens[j]._.num_flags = v.lstrip('#')
                        token.underscore.numFlags = String(stringValue.dropFirst()) // v.lstrip('#')
                    }
                }
            }
        }
        
        // Post-process для исправления апострофных токенов как в Python spaCy
        let correctedTokens = fixApostropheTokens(mutableTokens)
        logTokenizeResult(correctedTokens)
        
        return correctedTokens
    }
    
    /// Исправление апострофных токенов для совместимости с Python spaCy
    private func fixApostropheTokens(_ tokens: [MToken]) -> [MToken] {
        var result: [MToken] = []
        var i = 0
        
        while i < tokens.count {
            let token = tokens[i]
            
            // Проверяем паттерны сокращений (учитываем разные виды апострофов)
            // Проверяем что следующий токен - это апостроф (любой вид)
            if i + 1 < tokens.count {
                let nextTokenText = tokens[i + 1].text
                print("🔍 Checking token pair: '\(token.text)' + '\(nextTokenText)' (length: \(nextTokenText.count), unicode: \(nextTokenText.unicodeScalars.map { String($0.value, radix: 16) }.joined()))")
            }
            
            // Проверяем что следующий токен похож на апостроф
            var isApostrophe = false
            if i + 1 < tokens.count {
                let nextText = tokens[i + 1].text
                // Проверяем через Unicode scalar value
                if nextText.count == 1, let scalar = nextText.unicodeScalars.first {
                    // U+0027 ('), U+2019 ('), U+2018 (')
                    isApostrophe = (scalar.value == 0x27 || scalar.value == 0x2019 || scalar.value == 0x2018)
                }
            }
            
            print("🔍 isApostrophe = \(isApostrophe) for token '\(i + 1 < tokens.count ? tokens[i + 1].text : "N/A")'")
            
            if i + 2 < tokens.count && isApostrophe {
                print("🔍 Found apostrophe pattern: '\(token.text)' + '\(tokens[i + 1].text)' + '\(tokens[i + 2].text)'")
                let nextToken = tokens[i + 2]
                let combined = token.text + "'" + nextToken.text
                
                // Обрабатываем общие сокращения как в spaCy
                if shouldCombineApostrophe(word: token.text, suffix: nextToken.text) {
                    let newText = getSpacyTokenization(for: combined)
                    
                    if newText.count == 2 {
                        // Создаем два токена как в spaCy (например, "can't" → ["ca", "n't"])
                        let firstToken = MToken(
                            text: newText[0],
                            tag: token.tag,
                            whitespace: "",
                            underscore: token.underscore
                        )
                        
                        let secondToken = MToken(
                            text: newText[1], 
                            tag: nextToken.tag,
                            whitespace: nextToken.whitespace,
                            underscore: nextToken.underscore
                        )
                        
                        result.append(firstToken)
                        result.append(secondToken)
                        
                        i += 3 // Пропускаем следующие 2 токена
                        continue
                    }
                }
            }
            
            // Если не нашли сокращение, добавляем токен как есть
            result.append(token)
            i += 1
        }
        
        return result
    }
    
    /// Проверяет нужно ли объединять апостроф
    private func shouldCombineApostrophe(word: String, suffix: String) -> Bool {
        let commonContractions = [
            "s", "t", "d", "m", "re", "ve", "ll"  // 's, 't, 'd, 'm, 're, 've, 'll
        ]
        return commonContractions.contains(suffix.lowercased())
    }
    
    /// Возвращает токенизацию как в Python spaCy
    private func getSpacyTokenization(for word: String) -> [String] {
        let lowered = word.lowercased()
        
        // Специальные случаи как в spaCy
        switch lowered {
        case "can't":
            return ["ca", "n't"]
        case "won't":
            return ["wo", "n't"]
        case "shan't":
            return ["sha", "n't"]
        case "wouldn't", "couldn't", "shouldn't", "hadn't", "haven't", "hasn't", "wasn't", "weren't", "isn't", "aren't", "don't", "doesn't", "didn't":
            if let apostropheIndex = lowered.firstIndex(of: "'") {
                let prefix = String(lowered[..<apostropheIndex])
                let suffix = String(lowered[apostropheIndex...])
                return [prefix, suffix]
            }
        default:
            // Для остальных случаев ('s, 'd, 'm, 're, 've, 'll)
            if let apostropheIndex = lowered.firstIndex(of: "'") {
                let prefix = String(lowered[..<apostropheIndex])
                let suffix = String(lowered[apostropheIndex...])
                return [prefix, suffix]
            }
        }
        
        return [word] // Fallback
    }
    
    /// Логирование результата токенизации
    private func logTokenizeResult(_ tokens: [MToken]) {
        print("🔍 Tokenize result (\(tokens.count) tokens):")
        for (i, token) in tokens.enumerated() {
            print("  [\(i)]: '\(token.text)' (tag: \(token.tag))")
        }
    }
    
    /// fold_left метод точно как в Python G2P.fold_left
    public func foldLeft(tokens: [MToken]) -> [MToken] {
        var result: [MToken] = []
        for tk in tokens {
            let processedToken: MToken
            
            // tk = merge_tokens([result.pop(), tk], unk=self.unk) if result and not tk._.is_head else tk
            if !result.isEmpty && !tk.underscore.isHead {
                let lastToken = result.removeLast() // result.pop()
                processedToken = mergeTokens([lastToken, tk], unk: "❓") // self.unk = "❓"
            } else {
                processedToken = tk
            }
            
            result.append(processedToken)
        }
        
        return result
    }
    
    /// merge_tokens функция точно как в Python
    private func mergeTokens(_ tokens: [MToken], unk: String?) -> MToken {
        // stress = {tk._.stress for tk in tokens if tk._.stress is not None}
        let stressValues = Set(tokens.compactMap { $0.underscore.stress })
        
        // currency = {tk._.currency for tk in tokens if tk._.currency is not None}
        let currencyValues = Set(tokens.compactMap { $0.underscore.currency })
        
        // rating = {tk._.rating for tk in tokens}
        let ratingValues = tokens.map { $0.underscore.rating }
        
        // Обработка фонем
        let phonemes: String?
        if unk == nil {
            phonemes = nil
        } else {
            var phonemesStr = ""
            for tk in tokens {
                // if tk._.prespace and phonemes and not phonemes[-1].isspace() and tk.phonemes:
                if tk.underscore.prespace && !phonemesStr.isEmpty && !phonemesStr.last!.isWhitespace && tk.phonemes != nil {
                    phonemesStr += " "
                }
                // phonemes += unk if tk.phonemes is None else tk.phonemes
                phonemesStr += tk.phonemes ?? unk!
            }
            phonemes = phonemesStr
        }
        
        // text=''.join(tk.text + tk.whitespace for tk in tokens[:-1]) + tokens[-1].text
        var text = ""
        for (index, tk) in tokens.enumerated() {
            if index < tokens.count - 1 {
                text += tk.text + tk.whitespace
            } else {
                text += tk.text
            }
        }
        
        // tag=max(tokens, key=lambda tk: sum(1 if c == c.lower() else 2 for c in tk.text)).tag
        let selectedToken = tokens.max { tk1, tk2 in
            let score1 = tk1.text.reduce(0) { sum, c in sum + (c.isLowercase ? 1 : 2) }
            let score2 = tk2.text.reduce(0) { sum, c in sum + (c.isLowercase ? 1 : 2) }
            return score1 < score2
        }!
        
        let mergedUnderscore = MToken.Underscore(
            isHead: tokens[0].underscore.isHead,                               // is_head=tokens[0]._.is_head
            alias: nil,                                                        // alias=None
            stress: stressValues.count == 1 ? stressValues.first : nil,       // stress=list(stress)[0] if len(stress) == 1 else None
            currency: currencyValues.max(),                                    // currency=max(currency) if currency else None
            numFlags: String(Set(tokens.flatMap { $0.underscore.numFlags }).sorted()), // num_flags=''.join(sorted({c for tk in tokens for c in tk._.num_flags}))
            prespace: tokens[0].underscore.prespace,                          // prespace=tokens[0]._.prespace
            rating: ratingValues.contains(nil) ? nil : ratingValues.compactMap { $0 }.min() // rating=None if None in rating else min(rating)
        )
        
        return MToken(
            text: text,
            tag: selectedToken.tag,
            whitespace: tokens.last!.whitespace,           // whitespace=tokens[-1].whitespace
            phonemes: phonemes,
            startTs: tokens.first!.startTs,               // start_ts=tokens[0].start_ts
            endTs: tokens.last!.endTs,                    // end_ts=tokens[-1].end_ts
            underscore: mergedUnderscore
        )
    }
    
    /// retokenize метод точно как в Python G2P.retokenize
    public static func retokenize(tokens: [MToken]) -> [Any] {
        print("🔍 G2P.retokenize input: \(tokens.count) tokens")
        
        var words: [Any] = []
        var currency: String? = nil
        
        for (i, token) in tokens.enumerated() {
            let tks: [MToken]
            
            // if token._.alias is None and token.phonemes is None:
            if token.underscore.alias == nil && token.phonemes == nil {
                // tks = [replace(token, text=t, whitespace='', _=MToken.Underscore(...)) for t in subtokenize(token.text)]
                let subtokens = subtokenize(token.text)
                tks = subtokens.map { subtext in
                    let newToken = MToken(
                        text: subtext,
                        tag: token.tag,
                        whitespace: "", // изначально пустой
                        underscore: MToken.Underscore(
                            isHead: true,
                            stress: token.underscore.stress,
                            numFlags: token.underscore.numFlags,
                            prespace: false
                        )
                    )
                    return newToken
                }
                print("🔍 G2P.retokenize subtokenized '\(token.text)' into: \(subtokens)")
            } else {
                tks = [token]
            }
            
            // tks[-1].whitespace = token.whitespace
            tks.last?.whitespace = token.whitespace
            print("🔍 G2P.retokenize processing subtokens: \(tks.map { "'\($0.text)'(ws:'\($0.whitespace)')" })")
            
            for (j, tk) in tks.enumerated() {
                // if tk._.alias is not None or tk.phonemes is not None: pass
                if tk.underscore.alias != nil || tk.phonemes != nil {
                    // pass - ничего не делаем
                }
                // elif tk.tag == '$' and tk.text in CURRENCIES:
                else if tk.tag == "$" && ["$", "£", "€"].contains(tk.text) {
                    currency = tk.text
                    tk.phonemes = ""
                    tk.underscore.rating = 4
                    print("🔍 G2P.retokenize found currency: '\(tk.text)'")
                }
                // elif tk.tag == ':' and tk.text in ('-', '–'):
                else if tk.tag == ":" && ["-", "–"].contains(tk.text) {
                    tk.phonemes = "—"
                    tk.underscore.rating = 3
                    print("🔍 G2P.retokenize converted dash: '\(tk.text)' -> '—'")
                }
                // elif tk.tag in PUNCT_TAGS and not all(97 <= ord(c.lower()) <= 122 for c in tk.text):
                else if isPunctTag(tk.tag) && !tk.text.allSatisfy({ c in c.isLetter }) {
                    let punctMap = ["-LRB-": "(", "-RRB-": ")", "``": "\u{201C}", "\"\"": "\u{201D}", "''": "\u{201D}"]
                    tk.phonemes = punctMap[tk.tag] ?? tk.text.filter { ";:,.!?—…\"".contains($0) }.map(String.init).joined()
                    tk.underscore.rating = 4
                    print("🔍 G2P.retokenize handled punctuation: '\(tk.text)' -> '\(tk.phonemes ?? "")'")
                }
                // elif currency is not None:
                else if currency != nil {
                    if tk.tag != "CD" {
                        currency = nil
                    } else if j + 1 == tks.count && (i + 1 == tokens.count || tokens[i + 1].tag != "CD") {
                        tk.underscore.currency = currency
                        print("🔍 G2P.retokenize assigned currency '\(currency!)' to '\(tk.text)'")
                    }
                }
                // elif 0 < j < len(tks)-1 and tk.text == '2' and (tks[j-1].text[-1]+tks[j+1].text[0]).isalpha():
                else if j > 0 && j < tks.count - 1 && tk.text == "2" {
                    let prevLast = tks[j-1].text.last
                    let nextFirst = tks[j+1].text.first
                    if let prev = prevLast, let next = nextFirst, prev.isLetter && next.isLetter {
                        tk.underscore.alias = "to"
                        print("🔍 G2P.retokenize converted '2' to 'to' between letters")
                    }
                }
                
                // Логика группировки токенов
                // if tk._.alias is not None or tk.phonemes is not None: words.append(tk)
                if tk.underscore.alias != nil || tk.phonemes != nil {
                    words.append(tk)
                    print("🔍 G2P.retokenize added token with alias/phonemes: '\(tk.text)'")
                }
                // elif words and isinstance(words[-1], list) and not words[-1][-1].whitespace:
                else if !words.isEmpty,
                        let lastWordArray = words.last as? [MToken],
                        lastWordArray.last?.whitespace.isEmpty == true {
                    // Добавляем к существующей группе
                    tk.underscore.isHead = false
                    var updatedArray = lastWordArray
                    updatedArray.append(tk)
                    words[words.count - 1] = updatedArray
                    print("🔍 G2P.retokenize added '\(tk.text)' to existing group (isHead=false)")
                }
                // else: words.append(tk if tk.whitespace else [tk])
                else {
                    print("🔍 G2P.retokenize token '\(tk.text)' has whitespace: '\(tk.whitespace)' (isEmpty: \(tk.whitespace.isEmpty))")
                    if !tk.whitespace.isEmpty {
                        // Токен с whitespace - добавляем как отдельный
                        words.append(tk)
                        print("🔍 G2P.retokenize added single token '\(tk.text)' (has whitespace)")
                    } else {
                        // Токен без whitespace - создаем новую группу или добавляем к последней группе
                        print("🔍 G2P.retokenize current words count: \(words.count), last is array: \(words.last is [MToken])")
                        if !words.isEmpty, let lastWordArray = words.last as? [MToken] {
                            // Последний элемент - группа, добавляем к ней
                            tk.underscore.isHead = false
                            var updatedArray = lastWordArray
                            updatedArray.append(tk)
                            words[words.count - 1] = updatedArray
                            print("🔍 G2P.retokenize added '\(tk.text)' to existing group (isHead=false)")
                        } else {
                            // Создаем новую группу
                            words.append([tk])
                            print("🔍 G2P.retokenize created new group with '\(tk.text)'")
                        }
                    }
                }
            }
        }
        
        // return [w[0] if isinstance(w, list) and len(w) == 1 else w for w in words]
        let result = words.map { word -> Any in
            if let tokenArray = word as? [MToken], tokenArray.count == 1 {
                return tokenArray[0]
            }
            return word
        }
        
        print("🔍 G2P.retokenize output: \(result.count) words")
        
        return result
    }
    
    /// Функция subtokenize - упрощенная версия Python regex
    private static func subtokenize(_ word: String) -> [String] {
        // Упрощенная версия сложного Python regex
        // Разбиваем по основным паттернам
        var result: [String] = []
        var current = ""
        
        for char in word {
            if char.isLetter || char.isNumber {
                current += String(char)
            } else {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
                if !char.isWhitespace {
                    result.append(String(char))
                }
            }
        }
        
        if !current.isEmpty {
            result.append(current)
        }
        
        return result.isEmpty ? [word] : result
    }
    
    /// Проверка является ли тег пунктуационным
    private static func isPunctTag(_ tag: String) -> Bool {
        let punctTags = [".", ",", "-LRB-", "-RRB-", "``", "\"\"", "''", ":", "$", "#", "NFP"]
        return punctTags.contains(tag)
    }
    
    
    // MARK: - Token processing helpers
    
    /// Обработка контекста токена (как token_context в Python)
    private func tokenContext(context: TokenContext, phonemes: String?, token: MToken) -> TokenContext {
        var vowel = context.futureVowel
        
        if let phonemes = phonemes {
            // vowel = next((None if c in NON_QUOTE_PUNCTS else (c in VOWELS) for c in ps if any(c in s for s in (VOWELS, CONSONANTS, NON_QUOTE_PUNCTS))), vowel)
            let vowelChars = Set("AIOQWYaiuæɑɒɔəɛɜɪʊʌᵻ")
            let consonantChars = Set("bdfhjklmnpstvwzðŋɡɹɾʃʒʤʧθ")
            let nonQuotePuncts = Set(";:,.!?—…")
            
            for char in phonemes {
                _ = String(char)
                if vowelChars.contains(char) || consonantChars.contains(char) || nonQuotePuncts.contains(char) {
                    if nonQuotePuncts.contains(char) {
                        vowel = nil
                    } else {
                        vowel = vowelChars.contains(char)
                    }
                    break
                }
            }
        }
        
        // future_to = token.text in ('to', 'To') or (token.text == 'TO' and token.tag in ('TO', 'IN'))
        let futureTo = token.text == "to" || token.text == "To" || (token.text == "TO" && (token.tag == "TO" || token.tag == "IN"))
        
        return TokenContext(futureVowel: vowel, futureTo: futureTo)
    }
    
    /// Обработка группы токенов (сложная логика из Python)
    private func processTokenGroup(_ tokenGroup: [MToken], context: inout TokenContext) {
        var left = 0
        var right = tokenGroup.count
        var shouldFallback = false
        
        while left < right {
            // Проверяем есть ли уже фонемы или алиасы
            let hasPhonemes = tokenGroup[left..<right].contains { $0.underscore.alias != nil || $0.phonemes != nil }
            
            let mergedToken: MToken?
            if hasPhonemes {
                mergedToken = nil
            } else {
                mergedToken = mergeTokens(Array(tokenGroup[left..<right]), unk: nil)
            }
            
            let (phonemes, rating): (String?, Int?)
            if let mergedToken = mergedToken {
                (phonemes, rating) = lexicon.processToken(mergedToken, context: context)
            } else {
                (phonemes, rating) = (nil, nil)
            }
            
            if phonemes != nil {
                // Успешно найдены фонемы для группы
                tokenGroup[left].phonemes = phonemes
                tokenGroup[left].rating = rating
                
                // Очищаем остальные токены в группе
                for i in (left + 1)..<right {
                    tokenGroup[i].phonemes = ""
                    tokenGroup[i].rating = rating
                }
                
                context = tokenContext(context: context, phonemes: phonemes, token: mergedToken!)
                right = left
                left = 0
            } else if left + 1 < right {
                left += 1
            } else {
                // Не можем найти фонемы, обрабатываем последний токен
                right -= 1
                let currentToken = tokenGroup[right]
                
                if currentToken.phonemes == nil {
                    // Проверяем на junk символы
                    let subtokenJunks = Set("',-._''/")
                    if currentToken.text.allSatisfy({ subtokenJunks.contains($0) }) {
                        currentToken.phonemes = ""
                        currentToken.underscore.rating = 3
                    } else {
                        // Нужен fallback, но у нас его нет - просто оставляем nil
                        shouldFallback = true
                        break
                    }
                }
                left = 0
            }
        }
        
        if shouldFallback {
            // В Python здесь используется fallback, но у нас его нет
            // Просто объединяем все токены и оставляем как есть
            _ = mergeTokens(tokenGroup, unk: nil)
            tokenGroup[0].phonemes = nil  // Оставляем nil, чтобы потом заменить на unk
            tokenGroup[0].underscore.rating = 1
            for i in 1..<tokenGroup.count {
                tokenGroup[i].phonemes = ""
                tokenGroup[i].rating = 1
            }
        } else {
            // Resolve tokens logic из Python
            resolveTokens(tokenGroup)
        }
    }
    
    /// Разрешение токенов (как resolve_tokens в Python)
    private func resolveTokens(_ tokens: [MToken]) {
        // text = ''.join(tk.text + tk.whitespace for tk in tokens[:-1]) + tokens[-1].text
        var text = ""
        for (i, token) in tokens.enumerated() {
            if i < tokens.count - 1 {
                text += token.text + token.whitespace
            } else {
                text += token.text
            }
        }
        
        // prespace = ' ' in text or '/' in text or len({0 if c.isalpha() else (1 if is_digit(c) else 2) for c in text if c not in SUBTOKEN_JUNKS}) > 1
        let subtokenJunks = Set("',-._''/")
        let categories = Set(text.compactMap { char -> Int? in
            guard !subtokenJunks.contains(char) else { return nil }
            if char.isLetter { return 0 }
            else if char.isNumber { return 1 }
            else { return 2 }
        })
        let prespace = text.contains(" ") || text.contains("/") || categories.count > 1
        
        // Устанавливаем prespace для токенов начиная со второго
        for i in 1..<tokens.count {
            if tokens[i].phonemes != nil {
                tokens[i].underscore.prespace = prespace
            }
        }
        
        if prespace { return }
        
        // Логика ударений из Python (упрощенная версия)
        let primaryStress = "ˈ"
        let stressWeight = { (phonemes: String?) -> Int in
            guard let phonemes = phonemes else { return 0 }
            let diphthongs = Set("AIOQWYʤʧ")
            return phonemes.reduce(0) { sum, char in
                sum + (diphthongs.contains(char) ? 2 : 1)
            }
        }
        
        let indices: [(Bool, Int, Int)] = tokens.enumerated().compactMap { (i, token) in
            guard let phonemes = token.phonemes, !phonemes.isEmpty else { return nil }
            return (phonemes.contains(primaryStress), stressWeight(phonemes), i)
        }
        
        if indices.count == 2 && tokens[indices[0].2].text.count == 1 {
            let i = indices[1].2
            if let phonemes = tokens[i].phonemes {
                tokens[i].phonemes = applyStress(phonemes, stress: -0.5)
            }
            return
        } else if indices.count < 2 || indices.filter({ $0.0 }).count <= (indices.count + 1) / 2 {
            return
        }
        
        let sortedIndices = indices.sorted { $0.1 < $1.1 }
        let toReduce = Array(sortedIndices.prefix(indices.count / 2))
        
        for (_, _, i) in toReduce {
            if let phonemes = tokens[i].phonemes {
                tokens[i].phonemes = applyStress(phonemes, stress: -0.5)
            }
        }
    }
    
    /// Применение ударения (упрощенная версия из Lexicon)
    private func applyStress(_ phonemes: String, stress: Double) -> String {
        // Упрощенная версия - просто заменяем ударения
        let primaryStress = "ˈ"
        let secondaryStress = "ˌ"
        
        if stress == -0.5 {
            return phonemes.replacingOccurrences(of: primaryStress, with: secondaryStress)
        }
        
        return phonemes
    }
    
    /// Структура результата предобработки (как в Python: result, tokens, features)
    public struct PreprocessResult {
        let result: String
        let tokens: [String] 
        let features: [Int: Any]
    }
    
    /// Предобработка текста точно как в Python G2P.preprocess
    public static func preprocess(_ text: String) -> PreprocessResult {
        print("🔍 G2P.preprocess input: \"\(text)\"")
        
        var result = ""
        var tokens: [String] = []
        var features: [Int: Any] = [:]
        var lastEnd = 0
        
        // text = text.lstrip() - убираем пробелы слева
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Regex для markdown ссылок: \[([^\]]+)\]\(([^\)]*)\)
        let linkRegex = try! NSRegularExpression(pattern: #"\[([^\]]+)\]\(([^\)]*)\)"#)
        let matches = linkRegex.matches(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText))
        
        for match in matches {
            // result += text[last_end:m.start()]
            let beforeRange = NSRange(location: lastEnd, length: match.range.location - lastEnd)
            if let beforeSwiftRange = Range(beforeRange, in: trimmedText) {
                let beforeText = String(trimmedText[beforeSwiftRange])
                result += beforeText
                // tokens.extend(text[last_end:m.start()].split())
                tokens.append(contentsOf: beforeText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
            }
            
            if let textRange = Range(match.range(at: 1), in: trimmedText),
               let featureRange = Range(match.range(at: 2), in: trimmedText) {
                
                let linkText = String(trimmedText[textRange])      // m.group(1)
                let featureString = String(trimmedText[featureRange]) // m.group(2)
                
                // Парсим фичу согласно Python логике
                let f = parseFeature(featureString)
                if f != nil {
                    features[tokens.count] = f
                }
                
                result += linkText
                tokens.append(linkText)
                lastEnd = match.range.location + match.range.length
            }
        }
        
        // if last_end < len(text): result += text[last_end:]; tokens.extend(text[last_end:].split())
        if lastEnd < trimmedText.count {
            let remainingRange = NSRange(location: lastEnd, length: trimmedText.count - lastEnd)
            if let remainingSwiftRange = Range(remainingRange, in: trimmedText) {
                let remainingText = String(trimmedText[remainingSwiftRange])
                result += remainingText
                tokens.append(contentsOf: remainingText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty })
            }
        }
        
        let preprocessResult = PreprocessResult(result: result, tokens: tokens, features: features)
        
        return preprocessResult
    }
    
    /// Парсит фичи точно как в Python
    private static func parseFeature(_ featureString: String) -> Any? {
        var f = featureString
        
        // if is_digit(f[1 if f[:1] in ('-', '+') else 0:]):
        let startIndex = (f.hasPrefix("-") || f.hasPrefix("+")) ? 1 : 0
        let numberPart = String(f.dropFirst(startIndex))
        if numberPart.allSatisfy({ $0.isNumber }) {
            return Int(f) ?? nil
        }
        
        // elif f in ('0.5', '+0.5'): f = 0.5
        if f == "0.5" || f == "+0.5" {
            return 0.5
        }
        // elif f == '-0.5': f = -0.5  
        else if f == "-0.5" {
            return -0.5
        }
        // elif len(f) > 1 and f[0] == '/' and f[-1] == '/': f = f[0] + f[1:].rstrip('/')
        else if f.count > 1 && f.hasPrefix("/") && f.hasSuffix("/") {
            f = "/" + String(f.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            return f
        }
        // elif len(f) > 1 and f[0] == '#' and f[-1] == '#': f = f[0] + f[1:].rstrip('#')
        else if f.count > 1 && f.hasPrefix("#") && f.hasSuffix("#") {
            f = "#" + String(f.dropFirst().trimmingCharacters(in: CharacterSet(charactersIn: "#")))
            return f
        }
        // else: f = None
        else {
            return nil
        }
    }
}
