import Foundation

/// Swift реализация num2words для английского языка
public class Num2Words {
    
    // Базовые числительные
    private static let lowNumbers = [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"
    ]
    
    private static let tens = [
        "", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"
    ]
    
    private static let ordinals = [
        "first", "second", "third", "fourth", "fifth", "sixth", "seventh", "eighth", "ninth", "tenth",
        "eleventh", "twelfth", "thirteenth", "fourteenth", "fifteenth", "sixteenth", "seventeenth", "eighteenth", "nineteenth", "twentieth"
    ]
    
    private static let ordinalSuffixes: [String: String] = [
        "one": "first", "two": "second", "three": "third", "four": "fourth", "five": "fifth",
        "six": "sixth", "seven": "seventh", "eight": "eighth", "nine": "ninth", "ten": "tenth",
        "eleven": "eleventh", "twelve": "twelfth"
    ]
    
    /// Конвертация числа в кардинальное числительное
    public static func cardinal(_ number: Int) -> String {
        if number < 0 {
            return "minus " + cardinal(abs(number))
        }
        
        if number < 20 {
            return lowNumbers[number]
        } else if number < 100 {
            let ten = number / 10
            let unit = number % 10
            if unit == 0 {
                return tens[ten]
            } else {
                return tens[ten] + "-" + lowNumbers[unit]
            }
        } else if number < 1000 {
            let hundred = number / 100
            let remainder = number % 100
            var result = lowNumbers[hundred] + " hundred"
            if remainder != 0 {
                result += " and " + cardinal(remainder)
            }
            return result
        } else if number < 1000000 {
            let thousand = number / 1000
            let remainder = number % 1000
            var result = cardinal(thousand) + " thousand"
            if remainder != 0 {
                result += remainder < 100 ? " and " + cardinal(remainder) : ", " + cardinal(remainder)
            }
            return result
        } else if number < 1000000000 {
            let million = number / 1000000
            let remainder = number % 1000000
            var result = cardinal(million) + " million"
            if remainder != 0 {
                result += remainder < 100 ? " and " + cardinal(remainder) : ", " + cardinal(remainder)
            }
            return result
        } else {
            let billion = number / 1000000000
            let remainder = number % 1000000000
            var result = cardinal(billion) + " billion"
            if remainder != 0 {
                result += remainder < 100 ? " and " + cardinal(remainder) : ", " + cardinal(remainder)
            }
            return result
        }
    }
    
    /// Конвертация числа в порядковое числительное
    public static func ordinal(_ number: Int) -> String {
        if number < 0 {
            return "minus " + ordinal(abs(number))
        }
        
        if number < ordinals.count {
            return ordinals[number - 1]  // ordinals array is 0-indexed but starts from "first"
        }
        
        let cardinalStr = cardinal(number)
        let words = cardinalStr.components(separatedBy: " ")
        var lastWords = words.last?.components(separatedBy: "-") ?? []
        let lastWord = lastWords.last?.lowercased() ?? ""
        
        if let ordinalForm = ordinalSuffixes[lastWord] {
            lastWords[lastWords.count - 1] = ordinalForm
        } else {
            var ordinalWord = lastWord
            if ordinalWord.hasSuffix("y") {
                ordinalWord = String(ordinalWord.dropLast()) + "ie"
            }
            ordinalWord += "th"
            lastWords[lastWords.count - 1] = ordinalWord
        }
        
        var result = words
        result[result.count - 1] = lastWords.joined(separator: "-")
        return result.joined(separator: " ")
    }
    
    /// Конвертация года в слова
    public static func year(_ number: Int) -> String {
        if number < 0 {
            return cardinal(abs(number)) + " BC"
        }
        
        if number < 100 || number >= 10000 {
            return cardinal(number)
        }
        
        let high = number / 100
        let low = number % 100
        
        // Если год вида X000, X00X или просто большой - используем кардинальные
        if (high % 10 == 0 && low < 10) {
            return cardinal(number)
        }
        
        if low == 0 {
            return cardinal(high) + " hundred"
        } else if low < 10 {
            return cardinal(high) + " oh " + lowNumbers[low]
        } else {
            return cardinal(high) + " " + cardinal(low)
        }
    }
    
    /// Конвертация десятичного числа в слова
    public static func float(_ number: Double) -> String {
        let integerPart = Int(number)
        let fractionalPart = number - Double(integerPart)
        
        if fractionalPart == 0 {
            return cardinal(integerPart)
        }
        
        var result = cardinal(integerPart) + " point"
        
        // Конвертируем дробную часть в строку и обрабатываем каждую цифру
        let fractionalStr = String(format: "%.10f", fractionalPart).dropFirst(2) // убираем "0."
        let trimmed = fractionalStr.trimmingCharacters(in: CharacterSet(charactersIn: "0")) // убираем trailing zeros
        
        for char in trimmed {
            if let digit = Int(String(char)) {
                result += " " + lowNumbers[digit]
            }
        }
        
        return result
    }
    
    /// Основной интерфейс, аналогичный Python num2words
    public static func convert(_ number: Int, to type: String = "cardinal") -> String {
        switch type {
        case "cardinal":
            return cardinal(number)
        case "ordinal":
            return ordinal(number)
        case "year":
            return year(number)
        default:
            return cardinal(number)
        }
    }
    
    /// Перегрузка для Float
    public static func convert(_ number: Double) -> String {
        return float(number)
    }
    
    /// Конвертация отдельных цифр в слова (для номеров телефонов и т.д.)
    public static func digits(_ number: String) -> String {
        return number.compactMap { char in
            if let digit = Int(String(char)) {
                return lowNumbers[digit]
            }
            return nil
        }.joined(separator: " ")
    }
}