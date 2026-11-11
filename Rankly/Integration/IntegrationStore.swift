import Foundation
import CryptoKit

/// Paired API clients (Vitrin, MCP clients) and release markers. Only token hashes are stored.
@MainActor
final class IntegrationStore: ObservableObject {
    struct Client: Codable, Identifiable, Hashable {
        var id: String
        var name: String
        var tokenHash: String
        var createdAt: Date
        var lastUsed: Date?
    }

    /// A dated note on an app's timeline, e.g. "Vitrin uploaded new metadata".
    struct Event: Codable, Identifiable, Hashable {
        var id = UUID().uuidString
        var appId: String
        var date: Date
        var kind: String            // "release" | "note"
        var note: String
        var source: String          // client name
        var countries: [String]?
    }

    @Published private(set) var clients: [Client] = []
    @Published private(set) var events: [Event] = []
    @Published var apiPort: UInt16?
    @Published var apiError: String?

    private let clientsKey = "integration.clients"
    private let eventsKey = "integration.events"

    init() {
        let d = UserDefaults.standard
        if let data = d.data(forKey: clientsKey), let c = try? JSONDecoder.api.decode([Client].self, from: data) { clients = c }
        if let data = d.data(forKey: eventsKey), let e = try? JSONDecoder.api.decode([Event].self, from: data) { events = e }
    }

    // MARK: Clients

    /// Creates a client and returns its token (shown/returned once, never stored in clear).
    func addClient(name: String) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let token = "rk_" + Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        clients.append(Client(id: UUID().uuidString, name: name, tokenHash: Self.hash(token), createdAt: .now))
        saveClients()
        return token
    }

    func client(forToken token: String) -> Client? {
        let h = Self.hash(token)
        guard let i = clients.firstIndex(where: { $0.tokenHash == h }) else { return nil }
        if clients[i].lastUsed.map({ Date().timeIntervalSince($0) > 60 }) ?? true {
            clients[i].lastUsed = .now
            saveClients()
        }
        return clients[i]
    }

    func revoke(_ id: String) {
        clients.removeAll { $0.id == id }
        saveClients()
    }

    private func saveClients() {
        if let data = try? JSONEncoder.api.encode(clients) { UserDefaults.standard.set(data, forKey: clientsKey) }
    }

    static func hash(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Events

    func addEvent(_ e: Event) {
        events.append(e)
        events = Array(events.sorted { $0.date < $1.date }.suffix(500))
        if let data = try? JSONEncoder.api.encode(events) { UserDefaults.standard.set(data, forKey: eventsKey) }
    }

    func events(for appId: String) -> [Event] { events.filter { $0.appId == appId } }

    @discardableResult
    func removeEvent(id: String) -> Bool {
        let before = events.count
        events.removeAll { $0.id == id }
        if let data = try? JSONEncoder.api.encode(events) { UserDefaults.standard.set(data, forKey: eventsKey) }
        return events.count != before
    }
}
