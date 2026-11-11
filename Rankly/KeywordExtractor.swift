import Foundation

/// Turns app metadata (name, subtitle, description) into candidate search terms.
enum KeywordExtractor {
    static let stopwords: Set<String> = [
        // English
        "a","an","the","and","or","but","if","of","to","in","on","at","by","for","with","from","into","onto","as",
        "is","are","was","were","be","been","being","it","its","it's","this","that","these","those","you","your",
        "yours","we","our","us","they","their","them","he","she","his","her","i","me","my","mine","not","no","yes",
        "all","any","each","every","more","most","less","so","than","too","very","can","will","just","do","does",
        "did","done","have","has","had","get","gets","got","use","using","used","app","apps","new","now","also",
        "one","two","about","up","out","how","what","when","where","which","who","why","make","makes","help",
        "helps","way","ways","day","days","time","like","free","best","easy","simple","great","need","want","more",
        "only","own","per","via","etc","then","there","here","over","after","before","while","without","within",
        "feature","features","premium","subscription","subscriptions","pro","plus","version","terms","privacy",
        "policy","account","apple","iphone","ipad","ios","watch","support","contact","email","download","start",
        "let","lets","let's","keep","even","much","many","other","others","such","into","really","something",
        "anything","everything","whether","ever","never","always","again","still","yet","well","back","may",
        "might","must","should","would","could","whatever","through","across","around","both","few","some",
        // Turkish
        "ve","ile","bir","bu","şu","o","da","de","ki","mi","mı","mu","mü","için","gibi","daha","en","çok","her",
        "ama","fakat","veya","ya","yada","hem","ne","nasıl","neden","sen","siz","biz","ben","onlar","senin",
        "sizin","bizim","olan","olarak","olur","oldu","var","yok","kadar","sonra","önce","şimdi","artık","tüm",
        "bütün","hiç","uygulama","uygulaması","ücretsiz","yeni","kolay","hızlı","ile","gün","günlük","abonelik",
    ]

    struct Candidate: Hashable {
        let term: String
        let source: String   // KeywordSource code
    }

    /// Lowercase without Turkish dotless-i rules (metadata mixes English brand words like "BMI").
    static func lower(_ s: String) -> String {
        s.replacingOccurrences(of: "İ", with: "i").lowercased()
    }

    static func locale(for country: String) -> Locale {
        country == "tr" || country == "az" ? Locale(identifier: "tr_TR") : Locale(identifier: "en_US")
    }

    /// Text split into phrases (no n-gram crosses punctuation), each a list of normalized tokens.
    static func phrases(_ text: String, locale: Locale) -> [[String]] {
        let lowered = lower(text)
        let breakers = CharacterSet(charactersIn: ".,:;!?|()[]{}–—-&/\\\n\r\t•*\"“”‘+=#~<>…·")
        return lowered.components(separatedBy: breakers).map { seg in
            seg.split(whereSeparator: { $0.isWhitespace }).map { tok in
                String(tok).trimmingCharacters(in: CharacterSet.alphanumerics.inverted.subtracting(CharacterSet(charactersIn: "'")))
                    .trimmingCharacters(in: CharacterSet(charactersIn: "'"))
            }
            .filter { !$0.isEmpty }
        }
        .filter { !$0.isEmpty }
    }

    static func isUsable(_ tok: String) -> Bool {
        tok.count >= 2 && !stopwords.contains(tok) && !tok.allSatisfy(\.isNumber)
            && tok.unicodeScalars.contains { CharacterSet.letters.contains($0) }
    }

    /// n-grams (1...3) whose first and last tokens are meaningful.
    static func ngrams(_ phrase: [String], maxN: Int = 3) -> [String] {
        var out: [String] = []
        for n in 1...maxN where phrase.count >= n {
            for i in 0...(phrase.count - n) {
                let gram = Array(phrase[i..<(i + n)])
                guard isUsable(gram.first!), isUsable(gram.last!) else { continue }
                if n == 1 && gram[0].count < 3 { continue }
                out.append(gram.joined(separator: " "))
            }
        }
        return out
    }

    /// Terms from name + subtitle (most important ASO fields).
    static func titleTerms(name: String, subtitle: String?, country: String) -> [Candidate] {
        let loc = locale(for: country)
        var seen = Set<String>()
        var out: [Candidate] = []
        for (text, src) in [(name, KeywordSource.name), (subtitle ?? "", KeywordSource.subtitle)] {
            for p in phrases(text, locale: loc) {
                for g in ngrams(p) where seen.insert(g).inserted { out.append(Candidate(term: g, source: src)) }
            }
        }
        return out
    }

    /// Most repeated meaningful n-grams in the description.
    static func descriptionTerms(_ description: String?, country: String, limit: Int) -> [Candidate] {
        guard let description, !description.isEmpty else { return [] }
        var counts: [String: Int] = [:]
        for p in phrases(description, locale: locale(for: country)) {
            for g in ngrams(p) { counts[g, default: 0] += 1 }
        }
        func top(_ n: Int, minCount: Int, take: Int) -> [String] {
            counts.filter { $0.key.split(separator: " ").count == n && $0.value >= minCount }
                .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
                .prefix(take).map(\.key)
        }
        let picks = top(2, minCount: 2, take: limit / 2) + top(1, minCount: 3, take: limit / 3) + top(3, minCount: 2, take: limit / 6)
        return picks.map { Candidate(term: $0, source: KeywordSource.description) }
    }

    /// Words that make up a keyword field suggestion, excluding words already in name/subtitle.
    static func words(of term: String, country: String) -> [String] {
        phrases(term, locale: locale(for: country)).flatMap { $0 }.filter(isUsable)
    }
}
