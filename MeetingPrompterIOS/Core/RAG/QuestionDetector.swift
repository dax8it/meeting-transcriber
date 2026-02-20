import Foundation

class QuestionDetector {
    struct Config {
        static let minWords = 4
        static let confidenceThreshold = 0.3
    }
    
    func isQuestion(_ text: String) -> Bool {
        let words = text.components(separatedBy: .whitespacesAndNewlines)
        guard words.count >= Config.minWords else { return false }
        
        let score = calculateQuestionScore(text: text)
        return score >= Float(Config.confidenceThreshold)
    }
    
    private func calculateQuestionScore(text: String) -> Float {
        var score: Float = 0
        let lowercase = text.lowercased()
        
        let questionWords = ["what", "when", "where", "who", "why", "how"]
        let modalVerbs = ["can", "could", "should", "would", "will", "may", "might"]
        let auxVerbs = ["is", "are", "do", "does", "did", "was", "were"]
        
        for word in questionWords {
            if lowercase.hasPrefix(word) || lowercase.contains(" \(word) ") {
                score += 0.5
            }
        }
        
        for verb in modalVerbs {
            if lowercase.hasPrefix(verb) || lowercase.contains(" \(verb) ") {
                score += 0.3
            }
        }
        
        for verb in auxVerbs {
            if lowercase.hasPrefix(verb) || lowercase.contains(" \(verb) ") {
                score += 0.2
            }
        }
        
        if text.contains("?") {
            score += 0.4
        }
        
        let questionPhrases = ["tell me about", "explain", "describe", "clarify"]
        for phrase in questionPhrases {
            if lowercase.contains(phrase) {
                score += 0.3
            }
        }
        
        return min(score, 1.0)
    }
}

struct QueryIntent {
    private static let citationKeywords = [
        "source",
        "sources",
        "citation",
        "citations",
        "cite",
        "reference",
        "references",
        "evidence",
        "where does it say",
        "where in the document",
        "which document",
        "show sources",
        "provide sources"
    ]

    private static let summaryReadbackPhrases = [
        "read back everything",
        "read back summary",
        "read back the summary",
        "read back",
        "read the summary",
        "read summary",
        "play summary",
        "play the summary",
        "read it back",
        "play it back",
        "speak summary",
        "speak the summary"
    ]

    static func citationsRequested(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return citationKeywords.contains(where: { lowercased.contains($0) })
    }

    static func summaryReadbackRequested(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return summaryReadbackPhrases.contains(where: { lowercased.contains($0) })
    }

    static func stripCitationMarkers(_ text: String) -> String {
        let patterns = ["\\[S\\d+\\]", "\\[\\d+\\]"]
        var output = text
        for pattern in patterns {
            output = output.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        while output.contains("  ") {
            output = output.replacingOccurrences(of: "  ", with: " ")
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}