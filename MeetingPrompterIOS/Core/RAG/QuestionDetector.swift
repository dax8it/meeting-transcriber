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