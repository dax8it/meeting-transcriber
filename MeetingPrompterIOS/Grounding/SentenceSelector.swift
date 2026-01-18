import Foundation
import NaturalLanguage

nonisolated class SentenceSelector {
    func selectBestSentences(question: String, chunks: [DocumentChunk], maxSentences: Int) -> String {
        let questionLowercased = question.lowercased()
        let questionWords = tokenize(text: questionLowercased)
        
        var scoredSentences: [(sentence: String, score: Float, source: String)] = []
        
        for chunk in chunks {
            let sentences = splitIntoSentences(text: chunk.text)
            
            for sentence in sentences {
                let sentenceLowercased = sentence.lowercased()
                let sentenceWords = tokenize(text: sentenceLowercased)
                
                let score = calculateScore(
                    questionWords: questionWords,
                    sentenceWords: sentenceWords,
                    question: questionLowercased,
                    sentence: sentenceLowercased
                )
                
                if score > 0 {
                    scoredSentences.append((
                        sentence: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                        score: score,
                        source: "\(chunk.title) - \(chunk.sectionPath)"
                    ))
                }
            }
        }
        
        let sortedSentences = scoredSentences
            .sorted { $0.score > $1.score }
            .prefix(maxSentences)
        
        let evidenceBlock = sortedSentences
            .map { "\($0.sentence)" }
            .joined(separator: "\n\n")
        
        return evidenceBlock
    }
    
    private func splitIntoSentences(text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            sentences.append(String(text[tokenRange]))
            return true
        }
        
        return sentences
    }
    
    private func tokenize(text: String) -> Set<String> {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        
        var words = Set<String>()
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { tokenRange, _ in
            let word = String(text[tokenRange]).lowercased()
            if word.count > 2 {
                words.insert(word)
            }
            return true
        }
        
        return words
    }
    
    private func calculateScore(questionWords: Set<String>, sentenceWords: Set<String>, question: String, sentence: String) -> Float {
        var score: Float = 0
        
        let intersection = questionWords.intersection(sentenceWords)
        score += Float(intersection.count) * 2.0
        
        let union = questionWords.union(sentenceWords)
        if !union.isEmpty {
            let jaccard = Float(intersection.count) / Float(union.count)
            score += jaccard * 3.0
        }
        
        if sentence.contains(question) || question.contains(sentence) {
            score += 5.0
        }
        
        return score
    }
}