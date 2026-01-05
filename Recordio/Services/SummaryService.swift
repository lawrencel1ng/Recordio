import Foundation
import NaturalLanguage
import CoreData

class SummaryService {
    static let shared = SummaryService()
    
    private init() {}
    
    enum SummaryType {
        case executive
        case detailed
        case bulletPoints
        case actionItems
    }
    
    struct SummaryResult {
        let title: String
        let summary: String
        let actionItems: [String]
        let keyTopics: [String]
        let sentiment: Sentiment
    }
    
    struct Sentiment {
        let score: Double
        let label: String
    }
    
    func generateSummary(from text: String, type: SummaryType = .executive) -> SummaryResult {
        guard !text.isEmpty else {
            return SummaryResult(title: "Summary", summary: "No content available", actionItems: [], keyTopics: [], sentiment: Sentiment(score: 0, label: "Neutral"))
        }
        
        let actionItems = extractActionItems(from: text)
        let keyTopics = extractKeyTopics(from: text)
        let sentiment = analyzeSentiment(from: text)
        let summary = generateSummaryText(from: text, type: type)
        
        return SummaryResult(
            title: summaryTitle(for: type),
            summary: summary,
            actionItems: actionItems,
            keyTopics: keyTopics,
            sentiment: sentiment
        )
    }
    
    private func summaryTitle(for type: SummaryType) -> String {
        switch type {
        case .executive:
            return "Executive Summary"
        case .detailed:
            return "Detailed Summary"
        case .bulletPoints:
            return "Key Points"
        case .actionItems:
            return "Action Items"
        }
    }
    
    private func generateSummaryText(from text: String, type: SummaryType) -> String {
        let sentences = extractSentences(from: text)
        
        switch type {
        case .executive:
            return generateExecutiveSummary(sentences: sentences)
        case .detailed:
            return generateDetailedSummary(sentences: sentences)
        case .bulletPoints:
            return generateBulletPoints(sentences: sentences)
        case .actionItems:
            return generateActionItemsSummary(sentences: sentences)
        }
    }
    
    private func extractSentences(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.tokenType])
        tagger.string = text
        
        var sentences: [String] = []
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .sentence, scheme: .tokenType, options: options) { tag, range in
            sentences.append(String(text[range]))
            return true
        }
        
        return sentences
    }
    
    private func generateExecutiveSummary(sentences: [String]) -> String {
        let tokenizer = NLTokenizer(unit: .word)
        
        var sentenceScores: [(sentence: String, score: Double)] = []
        
        for sentence in sentences {
            tokenizer.string = sentence
            
            var wordCount = 0
            var importantWords = Set<String>()
            
            tokenizer.enumerateTokens(in: sentence.startIndex..<sentence.endIndex) { tokenRange, _ in
                let word = String(sentence[tokenRange]).lowercased()
                wordCount += 1
                
                if word.count > 3 {
                    importantWords.insert(word)
                }
                return true
            }
            
            let score = Double(importantWords.count) / max(1, Double(wordCount))
            sentenceScores.append((sentence: sentence, score: score))
        }
        
        let topSentences = sentenceScores
            .sorted { $0.score > $1.score }
            .prefix(min(5, sentences.count))
            .map { $0.sentence }
        
        return topSentences.joined(separator: " ")
    }
    
    private func generateDetailedSummary(sentences: [String]) -> String {
        let numberOfSentences = min(10, sentences.count)
        let selectedSentences = sentences.prefix(numberOfSentences)
        
        var summary = ""
        var sentenceIndex = 0
        
        for sentence in selectedSentences {
            if sentenceIndex % 3 == 0 && sentenceIndex > 0 {
                summary += "\n\n"
            }
            summary += sentence + " "
            sentenceIndex += 1
        }
        
        return summary.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func generateBulletPoints(sentences: [String]) -> String {
        let importantSentences = sentences.filter { sentence in
            let keywords = ["important", "key", "significant", "critical", "essential", "main", "primary"]
            return keywords.contains { sentence.lowercased().contains($0) }
        }
        
        var bulletPoints = importantSentences.map { "• " + $0 }
        
        if bulletPoints.count < 5 {
            let additionalSentences = sentences
                .prefix(max(5, 5 - bulletPoints.count))
                .filter { sentence in
                    !bulletPoints.contains { $0.contains(sentence) }
                }
            
            bulletPoints += additionalSentences.map { "• " + $0 }
        }
        
        return bulletPoints.joined(separator: "\n")
    }
    
    private func generateActionItemsSummary(sentences: [String]) -> String {
        let actionItems = extractActionItems(from: sentences.joined(separator: " "))
        
        if actionItems.isEmpty {
            return "No action items detected in this recording."
        }
        
        return actionItems.enumerated().map { index, item in
            "\(index + 1). \(item)"
        }.joined(separator: "\n")
    }
    
    private func extractActionItems(from text: String) -> [String] {
        let actionIndicators = ["will", "should", "need to", "going to", "must", "have to", "plan to", "going to", "decided to"]
        let sentences = extractSentences(from: text)
        
        var actionItems: [String] = []
        
        for sentence in sentences {
            let lowercased = sentence.lowercased()
            if actionIndicators.contains(where: { lowercased.contains($0) }) {
                actionItems.append(sentence.trimmingCharacters(in: .punctuationCharacters))
            }
        }
        
        return Array(actionItems.prefix(10))
    }
    
    private func extractKeyTopics(from text: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lemma, .lexicalClass])
        tagger.string = text
        
        var nouns: [String: Int] = [:]
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace]
        
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: options) { tag, range in
            if tag?.rawValue == "Noun" {
                let word = String(text[range]).lowercased()
                if word.count > 3 {
                    nouns[word, default: 0] += 1
                }
            }
            return true
        }
        
        let stopWords = ["thing", "something", "nothing", "someone", "something", "anything"]
        for word in stopWords {
            nouns.removeValue(forKey: word)
        }
        
        let sortedTopics = nouns
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key.capitalized }
        
        return sortedTopics
    }
    
    private func analyzeSentiment(from text: String) -> Sentiment {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        tagger.string = text
        
        var totalScore: Double = 0
        var count = 0
        
        let sentences = extractSentences(from: text)
        
        for sentence in sentences {
            let sentimentRange = sentence.startIndex..<sentence.endIndex
            if let sentimentTag = tagger.tag(at: sentimentRange.lowerBound, unit: .paragraph, scheme: .sentimentScore).0,
               let score = Double(sentimentTag.rawValue) {
                totalScore += score
                count += 1
            }
        }
        
        let averageScore = count > 0 ? totalScore / Double(count) : 0.0
        
        let label: String
        if averageScore > 0.3 {
            label = "Positive"
        } else if averageScore < -0.3 {
            label = "Negative"
        } else {
            label = "Neutral"
        }
        
        return Sentiment(score: averageScore, label: label)
    }
    
    func updateRecordingSummary(_ recording: Recording, type: SummaryType = .executive) {
        guard let transcript = recording.transcript, !transcript.isEmpty else {
            recording.aiSummary = "No transcript available for summary generation."
            recording.actionItems = nil
            recording.keyTopics = nil
            try? recording.managedObjectContext?.save()
            return
        }
        
        let result = generateSummary(from: transcript, type: type)
        
        recording.aiSummary = result.summary
        recording.actionItems = result.actionItems.joined(separator: "|||")
        recording.keyTopics = result.keyTopics.joined(separator: ", ")
        
        try? recording.managedObjectContext?.save()
    }
}
