import Foundation

enum Scoring {
    /// Difficulty 0...100 from the apps already ranking in the top 10.
    /// Mixes how established they are (rating counts) with how many target the term in their name.
    static func difficulty(term: String, topApps: [AppInfo]) -> Int {
        let top = Array(topApps.prefix(10))
        guard !top.isEmpty else { return 0 }
        let strength = top.map { min(1.0, log10(Double($0.ratingCount) + 1) / 5.5) }   // ~300K ratings = max
        let avgStrength = strength.reduce(0, +) / Double(top.count)
        let words = term.lowercased().split(separator: " ").map(String.init)
        let titleMatch = top.filter { app in
            let n = app.name.lowercased()
            return words.allSatisfy { n.contains($0) }
        }.count
        let matchRatio = Double(titleMatch) / Double(top.count)
        let score = 0.75 * avgStrength + 0.25 * matchRatio
        return Int((score * 100).rounded()).clamped(to: 0...100)
    }

    /// Popularity estimate 5...100 from App Store autocomplete:
    /// the shorter the prefix that surfaces the term, and the higher it appears, the more searched it is.
    static func estimatePopularity(term: String, country: String, client: AppStoreClient) async -> Int {
        let target = term.lowercased().trimmingCharacters(in: .whitespaces)
        guard !target.isEmpty else { return 5 }
        let chars = Array(target)
        let maxLen = min(chars.count, 14)
        var len = min(2, chars.count)
        while len <= maxLen {
            let prefix = String(chars[0..<len])
            guard let hints = try? await client.hints(for: prefix, country: country) else { return 5 }
            let lowered = hints.map { $0.lowercased() }
            if let pos = lowered.firstIndex(of: target) {
                // Each extra letter the user must type before it is suggested costs ~7 points.
                let base = 100.0 - Double(len - 2) * 7.0 - Double(pos) * 4.0
                return Int(base.rounded()).clamped(to: 5...100)
            }
            if hints.isEmpty { break }
            len += 1
        }
        // Not suggested even with the full term typed: low volume.
        let full = (try? await client.hints(for: target, country: country)) ?? []
        return full.isEmpty ? 5 : 10
    }
}

extension Comparable {
    func clamped(to r: ClosedRange<Self>) -> Self { min(max(self, r.lowerBound), r.upperBound) }
}
