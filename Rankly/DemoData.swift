import SwiftUI
import SwiftData

/// `-demo` launch argument: in-memory store with a fictional app and sample history.
/// Used for website screenshots; never touches the user's data or Apple's servers.
/// `-demoMenuBar` additionally shows the menu bar panel inside the main window.
@MainActor
enum Demo {
    nonisolated static let isOn = CommandLine.arguments.contains("-demo")
    nonisolated static let showMenuBarPanel = CommandLine.arguments.contains("-demoMenuBar")

    static func container() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let c = try! ModelContainer(for: TrackedApp.self, Keyword.self, RankSnapshot.self, configurations: config)
        seed(c.mainContext)
        return c
    }

    private static func seed(_ ctx: ModelContext) {
        let app = TrackedApp(appId: "demo-1", name: "Streakly: Habit Tracker", developer: "Demo Studio",
                             iconURL: "demo:flame.fill:orange")
        ctx.insert(app)
        for (name, icon) in [("Tiny Wins", "demo:star.fill:green"), ("Loopwise", "demo:arrow.triangle.2.circlepath:blue")] {
            ctx.insert(TrackedApp(appId: "demo-\(name)", name: name, developer: "Other", iconURL: icon, isCompetitor: true))
        }
        // term, ranks over 14 days (oldest → newest; 0 = not ranked), popularity, difficulty
        let rows: [(String, [Int], Int, Int)] = [
            ("habit tracker",   [9, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 3, 3, 2], 89, 77),
            ("streak tracker",  [3, 3, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1], 51, 50),
            ("habit journal",   [6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2, 2, 2, 1], 61, 43),
            ("goal tracker",    [14, 14, 13, 12, 12, 11, 11, 10, 9, 9, 8, 10, 9, 11], 73, 64),
            ("morning routine", [7, 7, 6, 6, 6, 5, 5, 5, 4, 4, 4, 4, 4, 4], 82, 53),
            ("daily planner",   [31, 29, 28, 26, 25, 24, 22, 22, 21, 20, 19, 19, 24, 19], 66, 67),
            ("habit tracker widget", [12, 11, 10, 10, 9, 8, 8, 7, 7, 6, 6, 5, 5, 5], 53, 27),
            ("build habits",    [40, 38, 35, 33, 30, 28, 27, 25, 23, 21, 20, 18, 17, 15], 61, 35),
            ("routine planner", [0, 0, 0, 0, 120, 98, 87, 76, 70, 66, 61, 58, 55, 48], 47, 38),
            ("self care",       [88, 85, 90, 84, 80, 78, 82, 79, 75, 73, 77, 74, 70, 72], 79, 81),
            ("adhd planner",    [60, 58, 55, 50, 49, 47, 44, 42, 40, 38, 36, 35, 37, 33], 73, 19),
            ("todo list",       [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], 85, 83),
        ]
        let cal = Calendar.current
        for (term, ranks, pop, diff) in rows {
            let kw = Keyword(term: term, country: "us", app: app)
            kw.popularity = pop
            kw.difficulty = diff
            kw.popularityUpdatedAt = .now
            kw.lastCheckedAt = .now
            ctx.insert(kw)
            for (i, r) in ranks.enumerated() {
                let day = cal.date(byAdding: .day, value: i - (ranks.count - 1), to: .now)!
                let snap = RankSnapshot(date: day, rank: r == 0 ? nil : r, resultCount: 250)
                ctx.insert(snap)
                snap.keyword = kw
            }
        }
        try? ctx.save()
    }
}

/// Placeholder icon for demo apps ("demo:<sf symbol>:<color>").
struct DemoIcon: View {
    let spec: String
    var size: CGFloat
    var body: some View {
        let parts = spec.split(separator: ":").map(String.init)
        let symbol = parts.count > 1 ? parts[1] : "app.fill"
        let color: Color = switch parts.count > 2 ? parts[2] : "" {
        case "green": .green
        case "blue": .blue
        default: .orange
        }
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                .fill(LinearGradient(colors: [color.opacity(0.75), color], startPoint: .top, endPoint: .bottom))
            Image(systemName: symbol).font(.system(size: size * 0.5, weight: .bold)).foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }
}
