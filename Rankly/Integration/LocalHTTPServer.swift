import Foundation
import Network

/// Minimal HTTP/1.1 server bound to 127.0.0.1 (no dependencies). One request per connection.
struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]   // lower-cased names
    let body: Data

    func json<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder.api.decode(T.self, from: body.isEmpty ? Data("{}".utf8) : body)
    }
}

struct HTTPResponse {
    var status: Int
    var body: Data
    var contentType = "application/json; charset=utf-8"

    static func json<T: Encodable>(_ value: T, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, body: (try? JSONEncoder.api.encode(value)) ?? Data("{}".utf8))
    }
    static func error(_ status: Int, _ message: String) -> HTTPResponse {
        .json(["error": message], status: status)
    }
    static let noContent = HTTPResponse(status: 202, body: Data(), contentType: "text/plain")
}

extension JSONEncoder {
    static let api: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()
}

extension JSONDecoder {
    static let api: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

final class LocalHTTPServer: @unchecked Sendable {
    typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    static let basePort: UInt16 = 47390
    private let queue = DispatchQueue(label: "rankly.http")
    private var listener: NWListener?
    private(set) var port: UInt16?
    private let handler: Handler
    private let maxBody = 1 << 20

    init(handler: @escaping Handler) { self.handler = handler }

    /// Tries 47390…47394 and returns the port it listens on.
    func start() throws -> UInt16 {
        var lastError: Error?
        for p in Self.basePort..<(Self.basePort + 5) {
            do {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: p)!)
                let l = try NWListener(using: params)
                let ready = DispatchSemaphore(value: 0)
                var failed: Error?
                l.stateUpdateHandler = { state in
                    switch state {
                    case .ready: ready.signal()
                    case .failed(let e): failed = e; ready.signal()
                    default: break
                    }
                }
                l.newConnectionHandler = { [weak self] c in self?.accept(c) }
                l.start(queue: queue)
                _ = ready.wait(timeout: .now() + 2)
                if let failed { l.cancel(); throw failed }
                listener = l
                port = p
                return p
            } catch { lastError = error }
        }
        throw lastError ?? NWError.posix(.EADDRINUSE)
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
    }

    // MARK: Connection handling

    private func accept(_ c: NWConnection) {
        c.start(queue: queue)
        receive(c, buffer: Data())
    }

    private func receive(_ c: NWConnection, buffer: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, done, error in
            guard let self else { c.cancel(); return }
            var buf = buffer
            if let data { buf.append(data) }
            if error != nil { c.cancel(); return }
            switch Self.parse(buf, maxBody: self.maxBody) {
            case .incomplete where !done:
                self.receive(c, buffer: buf)
            case .incomplete:
                c.cancel()
            case .invalid(let status, let msg):
                self.send(c, .error(status, msg))
            case .request(let req):
                let handler = self.handler
                Task {
                    let res = await handler(req)
                    self.send(c, res)
                }
            }
        }
    }

    private func send(_ c: NWConnection, _ r: HTTPResponse) {
        let reason = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 409: "Conflict", 413: "Payload Too Large",
                      429: "Too Many Requests", 500: "Internal Server Error", 503: "Service Unavailable"][r.status] ?? "OK"
        var head = "HTTP/1.1 \(r.status) \(reason)\r\n"
        head += "Content-Type: \(r.contentType)\r\nContent-Length: \(r.body.count)\r\n"
        head += "Cache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        var out = Data(head.utf8)
        out.append(r.body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }

    // MARK: Parsing

    enum Parsed {
        case incomplete
        case invalid(Int, String)
        case request(HTTPRequest)
    }

    static func parse(_ buf: Data, maxBody: Int) -> Parsed {
        guard let headerEnd = buf.range(of: Data("\r\n\r\n".utf8)) else {
            return buf.count > 32 * 1024 ? .invalid(400, "headers too large") : .incomplete
        }
        guard let head = String(data: buf[..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid(400, "bad headers") }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else { return .invalid(400, "bad request line") }
        var headers: [String: String] = [:]
        for line in lines {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        if length > maxBody { return .invalid(413, "body too large") }
        let bodyStart = headerEnd.upperBound
        if buf.count - bodyStart < length { return .incomplete }
        let target = String(requestLine[1])
        let comps = URLComponents(string: "http://localhost" + (target.hasPrefix("/") ? target : "/" + target))
        var query: [String: String] = [:]
        for item in comps?.queryItems ?? [] { query[item.name] = item.value ?? "" }
        return .request(HTTPRequest(method: String(requestLine[0]).uppercased(), path: comps?.path ?? target,
                                    query: query, headers: headers, body: buf.subdata(in: bodyStart..<(bodyStart + length))))
    }
}
